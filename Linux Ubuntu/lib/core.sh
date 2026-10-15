#!/bin/bash
# ============================================================
#   core.sh - Motore comune (Linux / Ubuntu)
#   Log, esecuzione dei task, helper di sistema.
#
#   Stessa impostazione della versione Windows e di quella
#   macOS: questo file non conosce l'interfaccia.
#
#   Il registro dei task resta una tabella testuale anche qui,
#   dove bash 4 avrebbe gli array associativi: cosi' i due
#   progetti shell restano leggibili allo stesso modo e cio'
#   che si impara sull'uno vale sull'altro.
#
#   Sorgente in ASCII puro: niente lettere accentate, cosi'
#   l'output resta leggibile via SSH, in console TTY e con
#   LANG=C.
# ============================================================

TB_LOG=""
TB_DRYRUN=0
TB_ROOT_OK=0
TB_WSL=0
TB_SYSTEMD=0
TB_CONTAINER=""      # "" | docker | lxc | podman | systemd-nspawn | generico
TB_VIRTUALE=0        # 1 se WSL o container: il kernel non e' nostro

CTX_BYTES=0; CTX_ITEMS=0; CTX_SKIPPED=0
CTX_ERRORS=0; CTX_ERRLIST=""; CTX_REBOOT=0

# ------------------------------------------------------------
#   Ambiente
# ------------------------------------------------------------
tb_init_env() {
    if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then TB_WSL=1; fi
    if [ -d /run/systemd/system ]; then TB_SYSTEMD=1; fi
    tb_init_container

    # WSL e container condividono lo stesso vincolo: il kernel, i
    # dischi e buona parte dei servizi appartengono all'host. Le
    # sezioni e le operazioni che li riguardano vanno saltate in
    # entrambi i casi, quindi il codice interroga questo.
    if [ "$TB_WSL" -eq 1 ] || [ -n "$TB_CONTAINER" ]; then TB_VIRTUALE=1; fi

    if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
        TB_USER="$SUDO_USER"
    else
        TB_USER="$(id -un)"
    fi
    TB_HOME="$(getent passwd "$TB_USER" 2>/dev/null | cut -d: -f6)"
    if [ -z "$TB_HOME" ] || [ ! -d "$TB_HOME" ]; then TB_HOME="$HOME"; fi
}

# ------------------------------------------------------------
#   Container: Docker, Podman, LXC, nspawn.
#
#   Non esiste un metodo unico e affidabile, quindi se ne provano
#   diversi in ordine di attendibilita'. systemd-detect-virt e' il
#   piu' preciso quando c'e'; /run/.containerenv e /.dockerenv
#   sono marcatori espliciti; il cgroup e' l'ultimo appiglio e su
#   cgroup v2 spesso non dice nulla, per questo non e' il primo.
# ------------------------------------------------------------
tb_init_container() {
    local v
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        v=$(systemd-detect-virt --container 2>/dev/null)
        case "$v" in
            none|'') ;;
            *) TB_CONTAINER="$v"; return 0 ;;
        esac
    fi
    if [ -f /.dockerenv ]; then TB_CONTAINER="docker"; return 0; fi
    if [ -f /run/.containerenv ]; then TB_CONTAINER="podman"; return 0; fi
    if [ -n "$container" ]; then TB_CONTAINER="$container"; return 0; fi
    if grep -qaE '(:/docker/|:/lxc/|containerd)' /proc/1/cgroup 2>/dev/null; then
        TB_CONTAINER="generico"; return 0
    fi
    return 0
}

as_root() {
    if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi
}

as_user() {
    if [ "$(id -u)" -eq 0 ] && [ -n "$TB_USER" ] && [ "$TB_USER" != "root" ]; then
        sudo -u "$TB_USER" "$@"
    else
        "$@"
    fi
}

# Come as_root ma NON chiede mai la password: se i privilegi non
# sono gia' disponibili fallisce in silenzio.
# Serve nell'analisi e in qualsiasi percorso di sola lettura, che
# non devono mai bloccarsi su una richiesta di password. Senza
# questa distinzione un'analisi lanciata da uno script o da cron
# resterebbe appesa per sempre.
as_root_quiet() {
    if [ "$(id -u)" -eq 0 ]; then "$@"; return $?; fi
    command -v sudo >/dev/null 2>&1 || return 1
    sudo -n "$@" 2>/dev/null
}

# Chiede la password una volta sola e la tiene viva, invece di
# farla ricomparire a meta' lavoro.
tb_need_root() {
    [ "$TB_ROOT_OK" -eq 1 ] && return 0
    if [ "$(id -u)" -eq 0 ]; then TB_ROOT_OK=1; return 0; fi
    command -v sudo >/dev/null 2>&1 || return 1
    if sudo -v 2>/dev/null; then
        TB_ROOT_OK=1
        ( while true; do sudo -n true 2>/dev/null; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) &
        TB_SUDO_PID=$!
        return 0
    fi
    return 1
}

tb_cleanup() {
    [ -n "$TB_SUDO_PID" ] && kill "$TB_SUDO_PID" 2>/dev/null
}

# ============================================================
#   GESTORE PACCHETTI
#
#   Il progetto nasce su Ubuntu e APT resta la piattaforma
#   collaudata, ma tutto cio' che le operazioni chiedono al
#   gestore pacchetti passa da qui. Aggiungere una distribuzione
#   significa aggiungere un ramo a queste funzioni, non toccare
#   i task.
#
#   Le funzioni che NON hanno un equivalente sensato altrove
#   (i kernel di Debian, pam_lastlog) restano dichiaratamente
#   legate ad APT: fingere un supporto che non c'e' sarebbe
#   peggio che dichiararlo.
#
#   Tutte le invocazioni che vengono poi analizzate girano con
#   LC_ALL=C: "Unpacking" e "Setting up" sono tradotti, e su un
#   sistema in italiano il conteggio dell'avanzamento sarebbe
#   sempre zero.
# ============================================================
TB_PKG=""          # apt | dnf | pacman | zypper | ""
TB_PKG_NOME="nessuno"

pkg_init() {
    if   command -v apt-get >/dev/null 2>&1; then TB_PKG="apt";    TB_PKG_NOME="APT"
    elif command -v dnf     >/dev/null 2>&1; then TB_PKG="dnf";    TB_PKG_NOME="DNF"
    elif command -v pacman  >/dev/null 2>&1; then TB_PKG="pacman"; TB_PKG_NOME="pacman"
    elif command -v zypper  >/dev/null 2>&1; then TB_PKG="zypper"; TB_PKG_NOME="zypper"
    else TB_PKG=""; TB_PKG_NOME="nessuno"; fi
}

pkg_presente() { [ -n "$TB_PKG" ]; }

# Cartella in cui il gestore tiene i pacchetti scaricati.
pkg_cache_dir() {
    case "$TB_PKG" in
        apt)    echo "/var/cache/apt/archives" ;;
        dnf)    echo "/var/cache/dnf" ;;
        pacman) echo "/var/cache/pacman/pkg" ;;
        zypper) echo "/var/cache/zypp/packages" ;;
        *)      echo "" ;;
    esac
}

pkg_pulisci_cache() {
    case "$TB_PKG" in
        apt)    as_root apt-get clean >/dev/null 2>&1
                as_root apt-get autoclean >/dev/null 2>&1 ;;
        dnf)    as_root dnf clean packages >/dev/null 2>&1 ;;
        # paccache conserva le ultime revisioni: e' il
        # comportamento prudente, quando c'e' si preferisce.
        pacman) if command -v paccache >/dev/null 2>&1; then
                    as_root paccache -rk1 >/dev/null 2>&1
                else
                    as_root pacman -Sc --noconfirm >/dev/null 2>&1
                fi ;;
        zypper) as_root zypper clean --all >/dev/null 2>&1 ;;
        *)      return 1 ;;
    esac
    return 0
}

pkg_aggiorna_indice() {
    case "$TB_PKG" in
        apt)    as_root env LC_ALL=C apt-get update >/dev/null 2>&1 ;;
        dnf)    as_root dnf -q makecache >/dev/null 2>&1 ;;
        pacman) as_root pacman -Sy --noconfirm >/dev/null 2>&1 ;;
        zypper) as_root zypper --non-interactive refresh >/dev/null 2>&1 ;;
        *)      return 1 ;;
    esac
    return $?
}

# Nomi dei pacchetti aggiornabili, uno per riga. Non richiede i
# privilegi: e' sola lettura e non deve mai fermarsi su una
# richiesta di password.
pkg_elenco_aggiornabili() {
    case "$TB_PKG" in
        apt)    LC_ALL=C apt-get -s upgrade 2>/dev/null | awk '/^Inst /{print $2}' ;;
        # check-update esce con 100 quando ci sono aggiornamenti:
        # non e' un errore, va ignorato.
        dnf)    LC_ALL=C dnf -q check-update 2>/dev/null | awk 'NF==3 && $1 !~ /^(Last|Obsoleting)/ {print $1}' ;;
        pacman) if command -v checkupdates >/dev/null 2>&1; then
                    checkupdates 2>/dev/null | awk '{print $1}'
                else
                    pacman -Qu 2>/dev/null | awk '{print $1}'
                fi ;;
        zypper) LC_ALL=C zypper -q list-updates 2>/dev/null | awk -F'|' '/^v /{gsub(/ /,"",$3); print $3}' ;;
        *)      return 1 ;;
    esac
    return 0
}

# Pacchetti che l'aggiornamento completo rimuoverebbe. E' la
# differenza vera rispetto a un aggiornamento normale, per questo
# viene mostrata sempre a parte e mai nascosta dentro un -y.
pkg_elenco_rimossi_completo() {
    case "$TB_PKG" in
        apt)    LC_ALL=C apt-get -s full-upgrade 2>/dev/null | awk '/^Remv /{print $2}' ;;
        dnf)    LC_ALL=C dnf -q --assumeno distro-sync 2>/dev/null | awk '/^Removing/{f=1;next} /^$/{f=0} f{print $1}' ;;
        pacman) echo "" ;;   # pacman -Syu non rimuove pacchetti da solo
        zypper) echo "" ;;
        *)      return 1 ;;
    esac
    return 0
}

# Pacchetti orfani, cioe' dipendenze rimaste senza chi le usava.
pkg_elenco_orfani() {
    case "$TB_PKG" in
        apt)    LC_ALL=C apt-get -s autoremove --purge 2>/dev/null | awk '/^Remv /{print $2}' ;;
        dnf)    dnf -q repoquery --unneeded 2>/dev/null ;;
        pacman) pacman -Qtdq 2>/dev/null ;;
        zypper) LC_ALL=C zypper -q packages --unneeded 2>/dev/null | awk -F'|' '/^i/{gsub(/ /,"",$3); print $3}' ;;
        *)      return 1 ;;
    esac
    return 0
}

pkg_rimuovi_orfani() {
    case "$TB_PKG" in
        apt)    as_root env LC_ALL=C apt-get autoremove --purge -y ;;
        dnf)    as_root dnf -y autoremove ;;
        pacman) local orfani; orfani=$(pacman -Qtdq 2>/dev/null | tr '\n' ' ')
                [ -z "$orfani" ] && return 0
                # shellcheck disable=SC2086
                as_root pacman -Rns --noconfirm $orfani ;;
        zypper) return 1 ;;   # zypper non ha un autoremove equivalente
        *)      return 1 ;;
    esac
    return $?
}

# I due livelli di aggiornamento. Su APT la distinzione fra
# upgrade e full-upgrade e' quella che conta: il primo non
# installa ne' rimuove nulla di nuovo, il secondo si'.
#
# Sono funzioni e non stringhe da valutare: run_con_avanzamento
# le riceve come "$@" e le esegue senza passare da eval, cosi'
# non c'e' una riga di comando ricostruita a mano che possa
# spezzarsi su uno spazio.
pkg_esegui_upgrade() {
    case "$TB_PKG" in
        apt)    as_root env LC_ALL=C apt-get upgrade -y ;;
        dnf)    as_root env LC_ALL=C dnf -y upgrade ;;
        pacman) as_root pacman -Su --noconfirm ;;
        zypper) as_root zypper --non-interactive update ;;
        *)      return 1 ;;
    esac
}

pkg_esegui_upgrade_completo() {
    case "$TB_PKG" in
        apt)    as_root env LC_ALL=C apt-get full-upgrade -y ;;
        dnf)    as_root env LC_ALL=C dnf -y distro-sync ;;
        pacman) as_root pacman -Syu --noconfirm ;;
        zypper) as_root zypper --non-interactive dist-upgrade ;;
        *)      return 1 ;;
    esac
}

pkg_ripara() {
    case "$TB_PKG" in
        apt)    as_root dpkg --configure -a >/dev/null 2>&1
                as_root env LC_ALL=C apt-get --fix-broken install -y >/dev/null 2>&1 ;;
        dnf)    as_root dnf -y --best --allowerasing distro-sync >/dev/null 2>&1 ;;
        pacman) as_root pacman -Syu --noconfirm >/dev/null 2>&1 ;;
        zypper) as_root zypper --non-interactive verify >/dev/null 2>&1 ;;
        *)      return 1 ;;
    esac
    return $?
}

# "totali;sicurezza". Il conteggio di sicurezza non e' disponibile
# ovunque: quando manca si restituisce -1 invece di zero, cosi'
# chi legge sa che il dato non c'e' e non che e' tutto a posto.
pkg_conta_aggiornamenti() {
    local tot sec
    case "$TB_PKG" in
        apt)
            if [ -x /usr/lib/update-notifier/apt-check ]; then
                /usr/lib/update-notifier/apt-check 2>&1
                return 0
            fi
            tot=$(pkg_elenco_aggiornabili | grep -c '[^[:space:]]')
            sec=-1 ;;
        dnf)
            tot=$(pkg_elenco_aggiornabili | grep -c '[^[:space:]]')
            sec=$(LC_ALL=C dnf -q updateinfo list --security 2>/dev/null | grep -c '[^[:space:]]')
            case "$sec" in ''|*[!0-9]*) sec=-1 ;; esac ;;
        pacman)
            tot=$(pkg_elenco_aggiornabili | grep -c '[^[:space:]]')
            sec=-1 ;;   # Arch non classifica gli aggiornamenti
        zypper)
            tot=$(pkg_elenco_aggiornabili | grep -c '[^[:space:]]')
            sec=$(LC_ALL=C zypper -q list-patches --category security 2>/dev/null | grep -c '^[a-zA-Z]') ;;
        *)  echo "0;0"; return 1 ;;
    esac
    case "$tot" in ''|*[!0-9]*) tot=0 ;; esac
    echo "${tot};${sec}"
    return 0
}

# Comando da suggerire per installare qualcosa che manca. Serve
# solo nei messaggi: suggerire "apt install" su Fedora sarebbe
# peggio che non suggerire niente.
pkg_suggerisci_installazione() {
    case "$TB_PKG" in
        apt)    echo "sudo apt install $1" ;;
        dnf)    echo "sudo dnf install $1" ;;
        pacman) echo "sudo pacman -S $1" ;;
        zypper) echo "sudo zypper install $1" ;;
        *)      echo "installa $1 con il gestore pacchetti del sistema" ;;
    esac
}

# Serve un riavvio dopo gli aggiornamenti?
pkg_serve_riavvio() {
    [ -f /var/run/reboot-required ] && return 0
    [ -f /run/reboot-required ] && return 0
    if command -v dnf >/dev/null 2>&1 && [ "$TB_PKG" = "dnf" ]; then
        dnf -q needs-restarting -r >/dev/null 2>&1 || return 0
    fi
    return 1
}

# ============================================================
#   AVANZAMENTO VISIBILE
#
#   Un dist-upgrade da dieci minuti con l'output mandato in
#   /dev/null non distingue "sta lavorando" da "e' bloccato".
#   Qui l'output viene letto riga per riga e trasformato in una
#   sola riga che si aggiorna: il registro completo resta nel
#   log, lo schermo non si riempie di migliaia di righe.
#
#   Il totale e' una stima: si conoscono i pacchetti coinvolti,
#   non quante righe produrranno. La barra viene percio' fermata
#   al 99% finche' il comando non termina davvero, per non
#   mostrare 100% mentre sta ancora lavorando.
# ============================================================
avanzamento_filtro() {
    local etichetta="$1" totale="${2:-0}"
    local fatti=0 riga pct
    while IFS= read -r riga; do
        [ -n "$TB_LOG" ] && printf '%s\n' "$riga" >> "$TB_LOG" 2>/dev/null
        case "$riga" in
            'Unpacking '*|'Setting up '*|'Get:'*|'Preparing to unpack'*| \
            'Installing '*|'Upgrading '*|'Removing '*|'installing '*|'upgrading '*)
                fatti=$(( fatti + 1 )) ;;
            *)  continue ;;
        esac
        if [ "$totale" -gt 0 ]; then
            pct=$(( fatti * 100 / totale ))
            [ "$pct" -gt 99 ] && pct=99
            printf '\r      %s [%s] %3d%%' "$etichetta" "$(ui_bar "$pct" 24)" "$pct"
        else
            printf '\r      %s ... %d passi completati' "$etichetta" "$fatti"
        fi
    done
    return 0
}

# run_con_avanzamento <etichetta> <passi_stimati> <comando...>
run_con_avanzamento() {
    local etichetta="$1" totale="${2:-0}"
    shift 2
    # Senza terminale (report, cron, --json) o su richiesta, si
    # torna al comportamento silenzioso di prima.
    if [ ! -t 1 ] || [ "$CFG_avanzamento" != "si" ]; then
        "$@" >/dev/null 2>&1
        return $?
    fi
    local rc
    "$@" 2>&1 | avanzamento_filtro "$etichetta" "$totale"
    rc=${PIPESTATUS[0]}
    # Riga cancellata e sostituita dall'esito: lasciare una barra
    # al 99% sullo schermo sarebbe piu' confuso che non averla.
    printf '\r%*s\r' "$(( TB_W + 6 ))" ""
    return "$rc"
}

# ============================================================
#   LOG
# ============================================================
log_init() {
    local dir="$1" keep="${2:-$CFG_log_da_conservare}"
    [ -z "$keep" ] && keep=15
    mkdir -p "$dir" 2>/dev/null
    TB_LOG="$dir/toolbox_$(date '+%Y-%m-%d_%H-%M-%S').log"
    : > "$TB_LOG" 2>/dev/null
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
ctx_note() { ui_detail "$1"; log_write "$1" "INFO"; }
ctx_fail() {
    CTX_ERRORS=$((CTX_ERRORS + 1))
    CTX_ERRLIST="${CTX_ERRLIST}${1}"$'\n'
    ui_detail_err "$1"
    log_write "$1" "WARN"
}

# ============================================================
#   MISURE
# ============================================================

# Occupazione reale su disco, in byte. Su GNU coreutils si puo'
# chiedere direttamente con --block-size=1.
bytes_of_path() {
    local p="$1"
    [ -e "$p" ] || { echo 0; return; }
    local b
    b=$(du -s --block-size=1 "$p" 2>/dev/null | awk 'NR==1{print $1}')
    if [ -z "$b" ]; then
        b=$(du -sk "$p" 2>/dev/null | awk 'NR==1{print $1*1024}')
    fi
    [ -z "$b" ] && b=0
    echo "$b"
}

free_space_bytes() {
    local b
    b=$(df -P -B1 / 2>/dev/null | awk 'NR==2{print $4}')
    if [ -z "$b" ]; then
        b=$(df -P -k / 2>/dev/null | awk 'NR==2{print $4*1024}')
    fi
    [ -z "$b" ] && b=0
    echo "$b"
}

# format_bytes, format_stima e format_durata stanno in common.sh:
# sono identiche nei due progetti shell e non usano piu' awk.

# ============================================================
#   CANCELLAZIONE
#   I file nascosti sono inclusi (dotglob); quelli non
#   rimovibili non contano come errori ma come saltati.
# ============================================================
clear_folder_content() {
    local path="$1" etichetta="${2:-$1}" usa_root="${3:-0}"

    if [ ! -d "$path" ]; then
        ctx_note "$etichetta: non presente, saltato"
        return 0
    fi

    # UNA sola scansione del disco.
    # Prima si misurava l'intera cartella, si cancellava e si
    # rimisurava: due attraversamenti completi, e su una cartella
    # con decine di migliaia di file era il costo dominante.
    # Qui una sola invocazione di du restituisce la dimensione di
    # ogni voce di primo livello, poi si somma solo cio' che viene
    # davvero rimosso.
    local elenco
    if [ "$usa_root" -eq 1 ]; then
        elenco=$(as_root bash -c '
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

    while IFS=$'	' read -r kb voce; do
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
            # Rimozione parziale: si rimisura solo questa voce.
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

# ============================================================
#   ESECUZIONE CON TIMEOUT
#   Su Linux c'e' il comando timeout di coreutils: si usa quello
#   quando disponibile, altrimenti si ricrea a mano.
# ============================================================
run_timeout() {
    local secondi="$1"; shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "$secondi" "$@"
        return $?
    fi
    "$@" &
    local pid=$!
    ( sleep "$secondi"; kill -TERM "$pid" 2>/dev/null ) 2>/dev/null &
    local guardia=$!
    wait "$pid" 2>/dev/null
    local rc=$?
    kill "$guardia" 2>/dev/null; wait "$guardia" 2>/dev/null
    return $rc
}

# ============================================================
#   MOTORE DEI TASK
#   Tre esiti reali: OK, PARZIALE, FALLITO.
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

    RES_DURATA=$(( $(date +%s) - t0 ))

    if   [ "$rc" -ne 0 ];        then RES_ESITO="FALLITO"
    elif [ "$CTX_ERRORS" -gt 0 ]; then RES_ESITO="PARZIALE"
    else                              RES_ESITO="OK"
    fi

    RES_BYTES=$CTX_BYTES; RES_ITEMS=$CTX_ITEMS; RES_SKIPPED=$CTX_SKIPPED
    RES_ERRORS=$CTX_ERRORS; RES_ERRLIST=$CTX_ERRLIST; RES_REBOOT=$CTX_REBOOT
    [ "$reboot" = "1" ] && RES_REBOOT=1

    local lvl="OK"
    [ "$RES_ESITO" = "PARZIALE" ] && { lvl="WARN"; exit_avviso; }
    [ "$RES_ESITO" = "FALLITO" ]  && { lvl="FAIL"; exit_critico; }
    log_write "esito=$RES_ESITO liberati=$(format_bytes "$RES_BYTES") elementi=$RES_ITEMS saltati=$RES_SKIPPED durata=${RES_DURATA}s" "$lvl"

    json_op_add "$id" "$nome" "$RES_ESITO" "$RES_BYTES" "$RES_DURATA" "$RES_ERRORS"
    return 0
}
