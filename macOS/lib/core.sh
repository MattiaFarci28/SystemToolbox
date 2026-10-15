#!/bin/bash
# ============================================================
#   core.sh - Motore comune
#   Log, esecuzione dei task, helper di sistema.
#
#   Questo file NON conosce l'interfaccia: rendering e menu
#   stanno in ui.sh. Stessa impostazione della versione Windows.
#
#   VINCOLO IMPORTANTE: macOS spedisce ancora bash 3.2 (per
#   motivi di licenza), sia su Catalina sia sulle versioni
#   recenti. Quindi niente array associativi (declare -A),
#   niente ${var,,}, niente mapfile. Il codice qui dentro gira
#   identico su 10.15 e su macOS 26.
#
#   Sorgente in ASCII puro: niente lettere accentate, cosi'
#   l'output resta leggibile anche via SSH o con LANG=C.
# ============================================================

# ------------------------------------------------------------
#   Stato globale
# ------------------------------------------------------------
TB_LOG=""
TB_DRYRUN=0
TB_ROOT_OK=0          # 1 quando la sessione sudo e' gia' stata ottenuta

# Contesto del task in esecuzione (l'equivalente di $ctx su Windows)
CTX_BYTES=0
CTX_ITEMS=0
CTX_SKIPPED=0
CTX_ERRORS=0
CTX_ERRLIST=""
CTX_REBOOT=0

# ------------------------------------------------------------
#   Utente reale
#   Se lo script viene lanciato con sudo, $HOME diventa
#   /var/root: era il bug piu' grave della versione precedente,
#   che finiva per pulire la cache di root invece della tua.
#   Qui l'utente vero viene risolto una volta sola.
# ------------------------------------------------------------
tb_init_user() {
    if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
        TB_USER="$SUDO_USER"
    else
        TB_USER="$(id -un)"
    fi
    TB_HOME="$(dscl . -read "/Users/$TB_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
    if [ -z "$TB_HOME" ] || [ ! -d "$TB_HOME" ]; then
        TB_HOME="$(eval echo "~$TB_USER")"
    fi
    if [ ! -d "$TB_HOME" ]; then TB_HOME="$HOME"; fi
}

# Esegue un comando come root: diretto se gia' root, con sudo altrimenti.
as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

# Esegue un comando come utente reale anche se lo script gira
# sotto sudo. Serve per strumenti come Homebrew, che si rifiutano
# di girare da root e che altrimenti agirebbero sui file sbagliati.
as_user() {
    if [ "$(id -u)" -eq 0 ] && [ -n "$TB_USER" ] && [ "$TB_USER" != "root" ]; then
        sudo -u "$TB_USER" "$@"
    else
        "$@"
    fi
}

# Come as_root ma NON chiede mai la password: se i privilegi non
# sono gia' disponibili fallisce in silenzio.
# Serve nell'analisi e in ogni percorso di sola lettura, che non
# devono mai bloccarsi su una richiesta di password.
as_root_quiet() {
    if [ "$(id -u)" -eq 0 ]; then "$@"; return $?; fi
    command -v sudo >/dev/null 2>&1 || return 1
    sudo -n "$@" 2>/dev/null
}

# Chiede la password una volta sola e la tiene viva finche' lo
# script gira, invece di farla ricomparire a meta' lavoro.
tb_need_root() {
    if [ "$TB_ROOT_OK" -eq 1 ]; then return 0; fi
    if [ "$(id -u)" -eq 0 ]; then TB_ROOT_OK=1; return 0; fi
    if sudo -v 2>/dev/null; then
        TB_ROOT_OK=1
        ( while true; do sudo -n true 2>/dev/null; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) &
        TB_SUDO_PID=$!
        return 0
    fi
    return 1
}

tb_cleanup() {
    if [ -n "$TB_SUDO_PID" ]; then kill "$TB_SUDO_PID" 2>/dev/null; fi
}

# ============================================================
#   LOG
# ============================================================
log_init() {
    local dir="$1"
    local keep="${2:-$CFG_log_da_conservare}"
    [ -z "$keep" ] && keep=15
    mkdir -p "$dir" 2>/dev/null
    TB_LOG="$dir/toolbox_$(date '+%Y-%m-%d_%H-%M-%S').log"
    : > "$TB_LOG" 2>/dev/null
    # Rotazione: conserva solo gli ultimi $keep file.
    local vecchi
    vecchi=$(ls -1t "$dir"/toolbox_*.log 2>/dev/null | tail -n +$((keep + 1)))
    if [ -n "$vecchi" ]; then
        echo "$vecchi" | while IFS= read -r f; do rm -f "$f" 2>/dev/null; done
    fi
    echo "$TB_LOG"
}

log_write() {
    local livello="${2:-INFO}"
    [ -z "$TB_LOG" ] && return 0
    printf '[%s] [%-4s] %s\n' "$(date '+%H:%M:%S')" "$livello" "$1" >> "$TB_LOG" 2>/dev/null
}

# ============================================================
#   CONTESTO DEL TASK
# ============================================================
ctx_reset() {
    CTX_BYTES=0; CTX_ITEMS=0; CTX_SKIPPED=0
    CTX_ERRORS=0; CTX_ERRLIST=""; CTX_REBOOT=0
}

# Informazione: finisce a schermo e nel log, non incide sull'esito.
ctx_note() {
    ui_detail "$1"
    log_write "$1" "INFO"
}

# Problema: incide sull'esito, che diventa PARZIALE.
ctx_fail() {
    CTX_ERRORS=$((CTX_ERRORS + 1))
    CTX_ERRLIST="${CTX_ERRLIST}${1}"$'\n'
    ui_detail_err "$1"
    log_write "$1" "WARN"
}

# ============================================================
#   MISURE
# ============================================================

# Dimensione di un percorso in byte. du su BSD lavora in blocchi
# da 1 KB con -k, quindi si moltiplica.
bytes_of_path() {
    local p="$1"
    [ -e "$p" ] || { echo 0; return; }
    local kb
    kb=$(du -sk "$p" 2>/dev/null | awk 'NR==1{print $1}')
    [ -z "$kb" ] && kb=0
    echo $((kb * 1024))
}

free_space_bytes() {
    local kb
    kb=$(df -k / 2>/dev/null | awk 'NR==2{print $4}')
    [ -z "$kb" ] && kb=0
    echo $((kb * 1024))
}

# format_bytes, format_stima e format_durata stanno in common.sh:
# sono identiche nei due progetti shell e non usano piu' awk.

# ============================================================
#   CANCELLAZIONE
#
#   Differenze rispetto alla versione precedente:
#   - i file nascosti vengono inclusi (dotglob): prima le cache
#     che iniziano con "." restavano sempre li';
#   - lo spazio liberato viene misurato davvero, prima e dopo;
#   - i file bloccati o protetti da SIP non contano come errori:
#     su macOS e' normale, vengono conteggiati a parte.
# ============================================================
clear_folder_content() {
    local path="$1"
    local etichetta="${2:-$1}"
    local usa_root="${3:-0}"

    if [ ! -d "$path" ]; then
        ctx_note "$etichetta: non presente, saltato"
        return 0
    fi

    # UNA sola scansione del disco.
    # Prima si misurava l'intera cartella, si cancellava e si
    # rimisurava: due attraversamenti completi, e su una cartella
    # con decine di migliaia di file era il costo dominante
    # dell'operazione. Qui una sola invocazione di du restituisce
    # la dimensione di ogni voce di primo livello, poi si somma
    # solo cio' che viene davvero rimosso.
    local elenco
    if [ "$usa_root" -eq 1 ]; then
        elenco=$(as_root /bin/bash -c '
            shopt -s dotglob nullglob
            set -- "$1"/*
            [ $# -eq 0 ] && exit 0
            du -sk -- "$@" 2>/dev/null' _ "$path")
    else
        elenco=$( ( shopt -s dotglob nullglob
                    set -- "$path"/*
                    [ $# -eq 0 ] && exit 0
                    du -sk -- "$@" 2>/dev/null ) )
    fi

    if [ -z "$elenco" ]; then
        ctx_note "$etichetta: gia' vuoto"
        return 0
    fi

    local liberati=0 rimossi=0 bloccati=0
    local kb voce dim resto

    while IFS=$'\t' read -r kb voce; do
        [ -z "$voce" ] && continue
        case "$kb" in ''|*[!0-9]*) continue ;; esac
        dim=$(( kb * 1024 ))

        if [ "$TB_DRYRUN" -eq 1 ]; then
            liberati=$(( liberati + dim )); rimossi=$(( rimossi + 1 ))
            continue
        fi

        if [ "$usa_root" -eq 1 ]; then
            as_root rm -rf -- "$voce" 2>/dev/null
        else
            rm -rf -- "$voce" 2>/dev/null
        fi

        if [ ! -e "$voce" ]; then
            liberati=$(( liberati + dim )); rimossi=$(( rimossi + 1 ))
        else
            # Rimozione parziale: dentro c'era qualcosa di bloccato.
            # Si rimisura solo questa voce, non tutta la cartella.
            resto=$(bytes_of_path "$voce")
            [ "$resto" -lt "$dim" ] && liberati=$(( liberati + dim - resto ))
            bloccati=$(( bloccati + 1 ))
        fi
    done <<FINEELENCO
$elenco
FINEELENCO

    if [ "$TB_DRYRUN" -eq 1 ]; then
        ctx_note "$etichetta: $(format_bytes "$liberati") eliminabili (simulazione)"
        CTX_BYTES=$(( CTX_BYTES + liberati ))
        return 0
    fi

    CTX_BYTES=$(( CTX_BYTES + liberati ))
    CTX_ITEMS=$(( CTX_ITEMS + rimossi ))
    CTX_SKIPPED=$(( CTX_SKIPPED + bloccati ))

    local msg="$etichetta: $(format_bytes "$liberati") liberati, $rimossi elementi rimossi"
    [ "$bloccati" -gt 0 ] && msg="$msg, $bloccati in uso o protetti (saltati)"
    ctx_note "$msg"
}

# Rimuove i file che corrispondono a un pattern, senza toccare il resto.
remove_matching() {
    local dir="$1" pattern="$2" etichetta="${3:-$2}" usa_root="${4:-0}"
    [ -d "$dir" ] || { ctx_note "$etichetta: percorso non presente"; return 0; }

    local trovati
    trovati=$(find "$dir" -maxdepth 1 -name "$pattern" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$trovati" -eq 0 ]; then
        ctx_note "$etichetta: niente da rimuovere"
        return 0
    fi
    local prima dopo
    prima=$(bytes_of_path "$dir")
    if [ "$TB_DRYRUN" -eq 1 ]; then
        ctx_note "$etichetta: $trovati elementi (simulazione)"
        return 0
    fi
    if [ "$usa_root" -eq 1 ]; then
        as_root find "$dir" -maxdepth 1 -name "$pattern" -exec rm -rf -- {} + 2>/dev/null
    else
        find "$dir" -maxdepth 1 -name "$pattern" -exec rm -rf -- {} + 2>/dev/null
    fi
    dopo=$(bytes_of_path "$dir")
    local lib=$((prima - dopo)); [ "$lib" -lt 0 ] && lib=0
    CTX_BYTES=$((CTX_BYTES + lib))
    CTX_ITEMS=$((CTX_ITEMS + trovati))
    ctx_note "$etichetta: $(format_bytes "$lib") liberati, $trovati elementi"
}

# ============================================================
#   ESECUZIONE CON TIMEOUT
#   macOS non ha il comando timeout di GNU: si ricrea con un
#   processo di guardia.
# ============================================================
run_timeout() {
    local secondi="$1"; shift
    "$@" &
    local pid=$!
    ( sleep "$secondi"; kill -TERM "$pid" 2>/dev/null ) 2>/dev/null &
    local guardia=$!
    wait "$pid" 2>/dev/null
    local rc=$?
    kill "$guardia" 2>/dev/null
    wait "$guardia" 2>/dev/null
    return $rc
}

# ============================================================
#   MOTORE DEI TASK
#   Tre esiti reali, come su Windows:
#     OK       nessun problema registrato
#     PARZIALE ha girato ma ha segnalato qualcosa
#     FALLITO  la funzione del task e' uscita con errore
#   RES_* sono le variabili di ritorno: bash 3.2 non ha modo
#   pulito di restituire una struttura.
# ============================================================
RES_ESITO=""; RES_BYTES=0; RES_ITEMS=0; RES_SKIPPED=0
RES_ERRORS=0; RES_ERRLIST=""; RES_DURATA=0; RES_REBOOT=0

run_task() {
    local id="$1"
    local nome; nome=$(task_field "$id" 2)
    local reboot; reboot=$(task_field "$id" 7)

    ctx_reset
    log_write "=== TASK $id : $nome" "STEP"
    local t0; t0=$(date +%s)

    # Privilegi: tutti i punti d'avvio li chiedono UNA volta prima di
    # partire (tb_need_root). Se sono stati negati, le operazioni che
    # ne hanno bisogno non vengono eseguite: prima partivano lo stesso
    # e chiamavano sudo, che senza terminale (interfaccia grafica,
    # cron) falliva a meta' lavoro e in un terminale richiedeva la
    # password a ogni comando, smentendo il messaggio "verranno
    # saltate".
    local rc=0 serve_root
    serve_root=$(task_field "$id" 6)
    if [ "$serve_root" = "1" ] && [ "$TB_DRYRUN" -eq 0 ] \
       && [ "$TB_ROOT_OK" -ne 1 ] && [ "$(id -u)" -ne 0 ]; then
        ctx_fail "Servono i privilegi di amministratore e non sono stati concessi: operazione non eseguita"
        rc=1
    else
        "task_$id" || rc=$?
    fi

    local t1; t1=$(date +%s)
    RES_DURATA=$((t1 - t0))

    if [ "$rc" -ne 0 ]; then
        RES_ESITO="FALLITO"
    elif [ "$CTX_ERRORS" -gt 0 ]; then
        RES_ESITO="PARZIALE"
    else
        RES_ESITO="OK"
    fi

    RES_BYTES=$CTX_BYTES
    RES_ITEMS=$CTX_ITEMS
    RES_SKIPPED=$CTX_SKIPPED
    RES_ERRORS=$CTX_ERRORS
    RES_ERRLIST=$CTX_ERRLIST
    RES_REBOOT=$CTX_REBOOT
    [ "$reboot" = "1" ] && RES_REBOOT=1

    local lvl="OK"
    [ "$RES_ESITO" = "PARZIALE" ] && { lvl="WARN"; exit_avviso; }
    [ "$RES_ESITO" = "FALLITO" ]  && { lvl="FAIL"; exit_critico; }
    log_write "esito=$RES_ESITO liberati=$(format_bytes "$RES_BYTES") elementi=$RES_ITEMS saltati=$RES_SKIPPED durata=${RES_DURATA}s" "$lvl"

    json_op_add "$id" "$nome" "$RES_ESITO" "$RES_BYTES" "$RES_DURATA" "$RES_ERRORS"
    return 0
}
