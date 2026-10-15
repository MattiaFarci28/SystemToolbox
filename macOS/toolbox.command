#!/bin/bash
# ============================================================
#   SYSTEM TOOLBOX - macOS
#   Punto di ingresso.
#
#   Unifica e sostituisce il vecchio macOS.sh. La logica sta in
#   lib/: qui c'e' solo l'orchestrazione e il menu.
#
#   Uso:
#     ./toolbox.command                menu interattivo
#     ./toolbox.command --dry-run      simulazione, non modifica nulla
#     ./toolbox.command --auto         manutenzione consigliata, senza domande
#     ./toolbox.command --help
#
#   L'estensione .command lo rende avviabile con doppio clic dal
#   Finder. Se e' appena stato copiato da un altro sistema serve
#   una volta sola:   chmod +x toolbox.command
#
#   NOTA IMPORTANTE: questo script NON va lanciato con sudo.
#   Va avviato come utente normale; le singole operazioni che
#   hanno bisogno dei privilegi li chiedono da sole, una volta.
#   Lanciarlo come root era il difetto della versione precedente:
#   $HOME diventava /var/root e la pulizia agiva sui file
#   sbagliati.
# ============================================================

TB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for modulo in common.sh core.sh ui.sh analysis.sh tasks.sh; do
    if [ ! -f "$TB_DIR/lib/$modulo" ]; then
        echo ""
        echo "  [ERRORE] File mancante: lib/$modulo"
        echo ""
        exit 1
    fi
    . "$TB_DIR/lib/$modulo"
done

# ------------------------------------------------------------
#   Parametri
# ------------------------------------------------------------
# Il file di configurazione, se presente, viene letto PRIMA dei
# parametri: cosi' la riga di comando ha sempre l'ultima parola.
cfg_load "$TB_DIR/toolbox.conf"

AUTO=0
while [ $# -gt 0 ]; do
    case "$1" in
        --auto)      AUTO=1 ;;
        --dry-run)   TB_DRYRUN=1 ;;
        --json)      TB_JSON=1; CFG_colori=no ;;
        --no-color)  CFG_colori=no ;;
        --daltonici) CFG_colori=daltonici ;;
        --emoji)     CFG_simboli=emoji ;;
        --no-emoji)  CFG_simboli=ascii ;;
        --report)    shift; TB_REPORT="$1" ;;
        --report=*)  TB_REPORT="${1#--report=}" ;;
        --config)    shift; cfg_load "$1" ;;
        --config=*)  cfg_load "${1#--config=}" ;;
        --versione|--version)
            echo "System Toolbox $TB_VERSIONE"
            exit 0 ;;
        --help|-h)
            cat <<AIUTO

  System Toolbox per macOS $TB_VERSIONE

    --dry-run          simulazione: mostra cosa farebbe, non modifica nulla
    --auto             manutenzione consigliata senza domande
    --report FILE      esporta il report (.md o .html)
    --json             stampa un riepilogo JSON invece del menu
    --config FILE      usa un file di configurazione diverso
    --no-color         disattiva i colori
    --daltonici        palette e simboli per daltonici
    --emoji            simboli di stato con le emoji (l'ascii resta il predefinito)
    --no-emoji         forza i simboli in ascii
    --versione         mostra la versione
    --help             questo messaggio

  Codici di uscita:
    0  nessuna criticita'
    1  avvisi presenti o operazioni con esito parziale
    2  criticita' rilevate o operazione fallita

AIUTO
            exit 0 ;;
        *)
            echo "  Parametro non riconosciuto: $1   (usa --help)"
            exit 2 ;;
    esac
    shift
done

# --json e --report implicano un'esecuzione non interattiva:
# senza --auto non ci sarebbe niente da riportare.
if [ "$TB_JSON" -eq 1 ] && [ "$AUTO" -eq 0 ]; then AUTO=1; fi
ui_colori_init
ui_simboli_init

# ------------------------------------------------------------
#   Inizializzazione
# ------------------------------------------------------------
# Titolo della finestra: costa nulla e rende riconoscibile la
# scheda fra le altre del Terminale.
printf '\033]0;System Toolbox\007'
# Il ridimensionamento e' disattivato di default: se lo lanci da
# una sessione gia' aperta, vedersela ridimensionare sotto le
# mani e' fastidioso. Si attiva con ridimensiona_terminale=si.
if [ "$CFG_ridimensiona_terminale" = "si" ] && [ -t 1 ]; then
    printf '\033[8;42;104t'
fi

tb_init_user
prefetch_init
cache_init "$TB_DIR/logs/cache"
storico_init "$TB_DIR/logs/storico.txt"
TB_LOG=$(log_init "$TB_DIR/logs")
TB_SISTEMA="macOS $(sw_vers -productVersion 2>/dev/null) - $(sysctl -n hw.model 2>/dev/null)"
log_write "System Toolbox $TB_VERSIONE avviato - utente $TB_USER - dryrun=$TB_DRYRUN auto=$AUTO" "INFO"

# Alla chiusura: report, JSON e pulizia della cache di prefetch.
tb_chiudi() {
    report_write
    json_write
    prefetch_cleanup
    tb_cleanup
}
trap tb_chiudi EXIT

if [ "$(id -u)" -eq 0 ] && [ -z "$SUDO_USER" ]; then
    echo ""
    ui_warn "Lo script sta girando come root senza un utente originario."
    ui_wrap "Le operazioni sull'utente useranno /var/root invece della tua cartella personale. Chiudi e rilancia senza sudo." 3 "$C_YELLOW"
    ui_pause "Premi INVIO per continuare comunque, oppure Ctrl-C per uscire"
fi

# ============================================================
#   ESECUZIONE DI UN INSIEME DI OPERAZIONI
# ============================================================
esegui_insieme() {
    local titolo="$1" ids="$2" senza_conferma="${3:-0}" avvertenza="${4:-}"

    if [ -z "$(echo "$ids" | tr -d ' ')" ]; then
        ui_warn "Nessuna operazione selezionata."
        return 0
    fi

    clear
    ui_title "$titolo"
    echo ""
    printf '  %sOperazioni previste:%s\n\n' "$C_WHITE" "$C_OFF"
    ui_task_detail "$ids"

    local n_op stima
    n_op=$(echo "$ids" | wc -w | tr -d ' ')
    stima=$(task_stima_totale "$ids")
    echo ""
    ui_kv "Operazioni" "$n_op"
    ui_kv "Tempo stimato" "$(format_stima "$stima")"

    if [ -n "$avvertenza" ]; then
        echo ""
        ui_wrap "$avvertenza" 3 "$C_YELLOW"
    fi

    if [ "$TB_DRYRUN" -eq 1 ]; then
        echo ""
        printf '  %sMODALITA SIMULAZIONE ATTIVA: nessuna modifica verra applicata.%s\n' "$C_MAGENTA" "$C_OFF"
    fi

    if [ "$senza_conferma" -eq 0 ]; then
        echo ""
        # Per le operazioni non marcate [sicuro] la conferma puo'
        # passare da una finestra di dialogo: a un "[s/N]" in fondo
        # a una schermata di testo si risponde per abitudine.
        local distruttive="" id2
        for id2 in $ids; do
            [ "$(task_field "$id2" 4)" != "sicuro" ] && distruttive="si"
        done
        if [ -n "$distruttive" ] && [ "$TB_DRYRUN" -eq 0 ]; then
            ui_conferma "Procedere?" "$titolo" \
                "Stai per eseguire operazioni che modificano il sistema.

$titolo
$n_op operazioni, tempo stimato $(format_stima "$stima").

Procedere?" || { ui_dim "Annullato."; return 0; }
        else
            ui_yesno "Procedere?" "n" || { ui_dim "Annullato."; return 0; }
        fi
    fi

    # Privilegi: chiesti una volta sola, se servono davvero.
    local serve_root=0 id
    for id in $ids; do
        [ "$(task_field "$id" 6)" = "1" ] && serve_root=1
    done
    if [ "$serve_root" -eq 1 ] && [ "$TB_DRYRUN" -eq 0 ]; then
        echo ""
        ui_dim "Alcune operazioni richiedono i privilegi di amministratore."
        if ! tb_need_root; then
            ui_err "Privilegi non concessi: le operazioni che li richiedono non verranno eseguite."
        fi
    fi

    local spazio_prima; spazio_prima=$(free_space_bytes)
    local righe="" problemi="" reboot=0 i=0
    n_op=$(echo "$ids" | wc -w | tr -d ' ')

    echo ""
    ui_title "Esecuzione"
    for id in $ids; do
        i=$((i + 1))
        echo ""
        ui_step "$i/$n_op" "$(task_field "$id" 2)"
        run_task "$id"
        righe="${righe}${RES_ESITO}|$(task_field "$id" 2)|${RES_BYTES}|${RES_DURATA}|${RES_ERRORS}"$'\n'
        case "$RES_ESITO" in
            OK)       ui_ok   "[completato]" ;;
            PARZIALE) ui_warn "[completato con $RES_ERRORS avvisi]" ;;
            FALLITO)  ui_err  "[non riuscito]" ;;
        esac
        if [ "$RES_ESITO" != "OK" ]; then
            problemi="${problemi}$(task_field "$id" 2):"$'\n'
            problemi="${problemi}${RES_ERRLIST}"
        fi
        [ "$RES_REBOOT" -eq 1 ] && reboot=1
    done

    local spazio_dopo delta
    spazio_dopo=$(free_space_bytes)
    delta=$((spazio_dopo - spazio_prima))
    [ "$TB_DRYRUN" -eq 1 ] && delta=-1
    [ "$delta" -lt 0 ] && delta=-1

    ui_summary "$righe" "$delta" "$problemi"
    echo ""
    ui_dim "Log della sessione: $TB_LOG"

    # La finestra del terminale resta dietro se nel frattempo si e'
    # andati a fare altro: una notifica lo segnala.
    local nfail nparz
    nfail=$(printf '%s' "$righe" | grep -c '^FALLITO|')
    nparz=$(printf '%s' "$righe" | grep -c '^PARZIALE|')
    if [ "$nfail" -gt 0 ]; then
        ui_notifica "$titolo: $nfail operazioni non riuscite"
    elif [ "$nparz" -gt 0 ]; then
        ui_notifica "$titolo: completato con $nparz avvisi"
    else
        ui_notifica "$titolo: completato senza errori"
    fi

    if [ "$reboot" -eq 1 ] && [ "$TB_DRYRUN" -eq 0 ]; then
        echo ""
        ui_warn "Alcune modifiche diventano effettive solo dopo il riavvio del Mac."
        if ui_yesno "Riavviare adesso?" "n"; then
            log_write "Riavvio richiesto dall'utente" "INFO"
            as_root shutdown -r +1 "Riavvio richiesto da System Toolbox" 2>/dev/null
            ui_dim "Riavvio programmato fra un minuto. Per annullare: sudo killall shutdown"
        else
            log_write "Riavvio rimandato" "INFO"
        fi
    fi
    return 0
}

# ============================================================
#   SELEZIONE PERSONALIZZATA
# ============================================================
selezione_personalizzata() {
    clear
    ui_title "Selezione personalizzata"
    echo ""
    local tutti; tutti=$(task_all_ids | tr '\n' ' ')
    ui_task_list_numbered "$tutti"
    echo ""
    ui_dim "Indica i numeri separati da spazio o virgola (esempio: 1,3,7). INVIO per annullare."
    printf '  %sSelezione:%s ' "$C_WHITE" "$C_OFF"
    local sel; read -r sel
    [ -z "$sel" ] && return 0

    local scelti="" p n=0 id
    for p in $(echo "$sel" | tr ',;' '  '); do
        case "$p" in
            ''|*[!0-9]*) ui_warn "Valore non valido: $p"; continue ;;
        esac
        id=$(echo "$tutti" | tr ' ' '\n' | grep -v '^$' | sed -n "${p}p")
        if [ -n "$id" ]; then
            scelti="$scelti $id"; n=$((n + 1))
        else
            ui_warn "Numero fuori intervallo: $p"
        fi
    done
    if [ "$n" -eq 0 ]; then
        ui_warn "Nessuna operazione valida selezionata."
        ui_pause
        return 0
    fi
    esegui_insieme "Operazioni personalizzate" "$scelti" 0 ""
}

# ============================================================
#   BACKUP DI iPhone e iPad
#   Non e' un task del registro perche' richiede una scelta a
#   meta' strada, e i task devono poter girare senza domande.
#   Qui si elencano per dispositivo e si elimina solo cio' che
#   si sceglie.
# ============================================================
gestione_backup_ios() {
    local base="$TB_HOME/Library/Application Support/MobileSync/Backup"
    clear
    ui_title "Backup di iPhone e iPad"

    if [ ! -d "$base" ]; then
        echo ""
        ui_ok "Nessun backup presente su questo Mac."
        return 0
    fi

    local elenco="" n=0 d nome data ris byte parziale etichetta
    echo ""
    ui_dim "Lettura dei backup, ogni misura ha un tempo massimo..."
    echo ""
    for d in "$base"/*; do
        [ -d "$d" ] || continue
        n=$(( n + 1 ))
        # Il nome del dispositivo sta nell'Info.plist del backup.
        nome=$(defaults read "$d/Info.plist" "Device Name" 2>/dev/null)
        [ -z "$nome" ] && nome="dispositivo sconosciuto"
        data=$(defaults read "$d/Info.plist" "Last Backup Date" 2>/dev/null | cut -c1-19)
        [ -z "$data" ] && data=$(date -r "$d" '+%Y-%m-%d %H:%M' 2>/dev/null)

        ris=$(bytes_of_path_limitato "$d" "$CFG_misura_max_secondi")
        byte=$(echo "$ris" | cut -d'|' -f1)
        parziale=$(echo "$ris" | cut -d'|' -f2)
        etichetta="$(format_bytes "$byte")"
        [ "$parziale" = "1" ] && etichetta="oltre $etichetta"

        printf '  %s%2d)%s  %-28.28s %s%12s%s\n' "$C_WHITE" "$n" "$C_OFF" "$nome" "$C_YELLOW" "$etichetta" "$C_OFF"
        ui_dim "     ultimo: ${data:-n/d}"
        elenco="$elenco$d"$'\n'
    done

    if [ "$n" -eq 0 ]; then
        ui_ok "Nessun backup presente."
        return 0
    fi

    echo ""
    ui_wrap "Eliminare un backup e' definitivo: se e' l'unica copia dei dati di quel dispositivo, non si recupera. Verifica di averne un'altra prima di procedere." 3 "$C_YELLOW"
    echo ""
    ui_dim "Indica i numeri da eliminare separati da spazio o virgola. INVIO per non fare nulla."
    printf '  %sSelezione:%s ' "$C_WHITE" "$C_OFF"
    local sel; read -r sel
    [ -z "$sel" ] && { ui_dim "Nessuna eliminazione."; return 0; }

    local scelti="" pezzo riga
    for pezzo in $(echo "$sel" | tr ',;' '  '); do
        case "$pezzo" in ''|*[!0-9]*) ui_warn "Valore non valido: $pezzo"; continue ;; esac
        riga=$(printf '%s' "$elenco" | sed -n "${pezzo}p")
        [ -n "$riga" ] && scelti="$scelti$riga"$'\n' || ui_warn "Numero fuori intervallo: $pezzo"
    done
    [ -z "$scelti" ] && { ui_warn "Nessun backup valido selezionato."; return 0; }

    local quanti; quanti=$(printf '%s' "$scelti" | grep -c '[^[:space:]]')
    echo ""
    ui_conferma "Eliminare $quanti backup?" "Backup iOS" \
        "Stai per eliminare $quanti backup di dispositivi iOS.

L'operazione e' definitiva e non passa dal Cestino.

Procedere?" || { ui_dim "Annullato."; return 0; }

    if [ "$TB_DRYRUN" -eq 1 ]; then
        ui_dim "Simulazione attiva: nessun backup e' stato eliminato."
        return 0
    fi

    local prima dopo eliminati=0
    prima=$(free_space_bytes)
    while IFS= read -r d; do
        [ -z "$d" ] && continue
        if rm -rf -- "$d" 2>/dev/null; then
            eliminati=$(( eliminati + 1 ))
            log_write "Backup iOS eliminato: $d" "INFO"
        else
            ui_err "Non rimosso: $(basename "$d")"
        fi
    done <<FINESCELTI
$scelti
FINESCELTI
    dopo=$(free_space_bytes)
    echo ""
    ui_ok "$eliminati backup eliminati, $(format_bytes $(( dopo - prima ))) liberati."
    ui_notifica "Backup iOS: $eliminati eliminati"
}

# ============================================================
#   MODALITA NON INTERATTIVA
# ============================================================
if [ "$AUTO" -eq 1 ]; then
    log_write "Modalita automatica" "STEP"
    if [ "$TB_JSON" -eq 1 ]; then
        # In modalita' JSON l'output leggibile finirebbe mescolato
        # al documento: si esegue tutto in silenzio e si stampa solo
        # il JSON, alla chiusura.
        analisi rapida            >/dev/null 2>&1
        esegui_insieme "Manutenzione consigliata" "$(task_set Consigliata)" 1 "" >/dev/null 2>&1
    else
        analisi rapida
        esegui_insieme "Manutenzione consigliata" "$(task_set Consigliata)" 1 ""
        echo ""
        ui_title "Esecuzione automatica terminata"
        ui_dim "Log: $TB_LOG"
        [ -n "$TB_REPORT" ] && ui_dim "Report: $TB_REPORT"
    fi
    exit "$TB_EXIT"
fi

# ============================================================
#   MENU
# ============================================================
mostra_menu() {
    clear
    ui_title "System Toolbox - macOS"
    echo ""
    printf '   %sANALISI%s\n' "$C_GREEN" "$C_OFF"
    printf '     1)  Analisi completa del sistema\n'
    printf '     2)  Analisi rapida\n'
    echo ""
    printf '   %sPULIZIA%s\n' "$C_GREEN" "$C_OFF"
    printf '     3)  Pulizia sicura            %scestini, crash report, cache browser%s\n' "$C_DIM" "$C_OFF"
    printf '     4)  Pulizia avanzata          %scache, snapshot Time Machine, Xcode%s\n' "$C_DIM" "$C_OFF"
    echo ""
    printf '   %sRETE%s\n' "$C_GREEN" "$C_OFF"
    printf '     5)  Manutenzione rete         %sDNS e indirizzo IP, nessun riavvio%s\n' "$C_DIM" "$C_OFF"
    printf '     6)  Reset configurazione      %s%srichiede riavvio%s\n' "$C_MAGENTA" "" "$C_OFF"
    echo ""
    printf '   %sMANUTENZIONE%s\n' "$C_GREEN" "$C_OFF"
    printf '     7)  Manutenzione sistema      %sApri con, disco, Spotlight, aggiornamenti%s\n' "$C_DIM" "$C_OFF"
    printf '     8)  Manutenzione consigliata  %spulizia sicura + DNS%s\n' "$C_DIM" "$C_OFF"
    echo ""
    printf '   %sALTRO%s\n' "$C_GREEN" "$C_OFF"
    printf '     B)  Backup di iPhone e iPad  %selenca ed elimina per dispositivo%s\n' "$C_DIM" "$C_OFF"
    printf '     P)  Selezione personalizzata  %sscegli le singole operazioni%s\n' "$C_DIM" "$C_OFF"
    printf '     L)  Apri la cartella dei log\n'
    printf '     S)  Modalita simulazione: '
    if [ "$TB_DRYRUN" -eq 1 ]; then printf '%sATTIVA%s\n' "$C_MAGENTA" "$C_OFF"
    else printf '%sdisattivata%s\n' "$C_DIM" "$C_OFF"; fi
    printf '     0)  Esci\n'
    echo ""
    printf '  %s' "$C_DIM"; ui_line '-'; printf '%s' "$C_OFF"
    printf '   %sScelta:%s ' "$C_WHITE" "$C_OFF"
}

while true; do
    mostra_menu
    read -r scelta
    scelta=$(printf '%s' "$scelta" | tr '[:lower:]' '[:upper:]')
    case "$scelta" in
        1) analisi completa; ui_pause ;;
        2) analisi rapida;   ui_pause ;;
        3) esegui_insieme "Pulizia sicura" "$(task_set PuliziaSicura)" 0 ""; ui_pause ;;
        4) esegui_insieme "Pulizia avanzata" "$(task_set PuliziaAvanzata)" 0 \
             "Chiudi i browser e le applicazioni prima di procedere. Gli snapshot locali di Time Machine verranno eliminati: i backup sul disco esterno non vengono toccati."
           ui_pause ;;
        5) esegui_insieme "Manutenzione rete" "$(task_set Rete)" 0 ""; ui_pause ;;
        6) esegui_insieme "Reset configurazione di rete" "$(task_set ReteReset)" 0 \
             "Azzera la configurazione di rete di macOS. Le reti Wi-Fi salvate andranno reinserite. Ha effetto solo dopo il riavvio: serve a riparare una rete che non funziona, non come manutenzione periodica."
           ui_pause ;;
        7) esegui_insieme "Manutenzione sistema" "$(task_set Manutenzione)" 0 \
             "La reindicizzazione di Spotlight rende il Mac piu' lento per alcune ore, finche' l'indice non e' ricostruito. L'installazione degli aggiornamenti di macOS puo' richiedere molto tempo e riavviare il Mac."
           ui_pause ;;
        8) esegui_insieme "Manutenzione consigliata" "$(task_set Consigliata)" 0 ""; ui_pause ;;
        B) gestione_backup_ios; ui_pause ;;
        P) selezione_personalizzata; ui_pause ;;
        L) open "$TB_DIR/logs" 2>/dev/null ;;
        S) if [ "$TB_DRYRUN" -eq 1 ]; then TB_DRYRUN=0; else TB_DRYRUN=1; fi
           log_write "Modalita simulazione: $TB_DRYRUN" "INFO" ;;
        0) log_write "Sessione terminata" "INFO"
           echo ""; ui_dim "Log salvato in: $TB_LOG"
           [ -n "$TB_REPORT" ] && ui_dim "Report: $TB_REPORT"
           echo ""
           exit "$TB_EXIT" ;;
        *) echo ""; ui_warn "Scelta non riconosciuta."; sleep 1 ;;
    esac
done
