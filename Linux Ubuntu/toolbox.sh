#!/bin/bash
# ============================================================
#   SYSTEM TOOLBOX - Linux / Ubuntu
#   Punto di ingresso.
#
#   Sostituisce il vecchio Ubuntu.sh. Funziona sia su Ubuntu
#   reale sia dentro WSL: l'ambiente viene rilevato da solo e
#   cio' che in WSL non ha senso viene dichiarato non
#   applicabile invece di dare falsi allarmi.
#
#   Uso:
#     ./toolbox.sh                 menu interattivo
#     ./toolbox.sh --dry-run       simulazione, non modifica nulla
#     ./toolbox.sh --auto          manutenzione consigliata, senza domande
#     ./toolbox.sh --help
#
#   Alla prima copia da un altro sistema serve una volta sola:
#     chmod +x toolbox.sh
#
#   NON va lanciato con sudo: va avviato come utente normale e
#   le operazioni che hanno bisogno dei privilegi li chiedono da
#   sole, una volta. Sotto sudo, $HOME diventa /root e la
#   pulizia della cache utente finirebbe sui file sbagliati.
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
#   Il file di configurazione viene letto PRIMA: cosi' la riga di
#   comando ha sempre l'ultima parola.
# ------------------------------------------------------------
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

  System Toolbox per Linux / Ubuntu $TB_VERSIONE

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
        *) echo "  Parametro non riconosciuto: $1   (usa --help)"; exit 2 ;;
    esac
    shift
done

if [ "$TB_JSON" -eq 1 ] && [ "$AUTO" -eq 0 ]; then AUTO=1; fi
ui_colori_init
ui_simboli_init

tb_init_env
pkg_init
prefetch_init
cache_init "$TB_DIR/logs/cache"
storico_init "$TB_DIR/logs/storico.txt"
TB_LOG=$(log_init "$TB_DIR/logs")
TB_SISTEMA="$(awk -F= '/^PRETTY_NAME=/{gsub(/"/,"",$2); print $2}' /etc/os-release 2>/dev/null) - kernel $(uname -r)"
log_write "System Toolbox $TB_VERSIONE avviato - utente $TB_USER - wsl=$TB_WSL container=${TB_CONTAINER:-no} pkg=$TB_PKG systemd=$TB_SYSTEMD dryrun=$TB_DRYRUN auto=$AUTO" "INFO"

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
    ui_wrap "Le operazioni sull'utente useranno /root invece della tua cartella personale. Chiudi e rilancia senza sudo." 3 "$C_YELLOW"
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
            task_campo "$id2" 4
            [ "$TB_CAMPO" != "sicuro" ] && distruttive="si"
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

    local serve_root=0 id
    for id in $ids; do
        task_campo "$id" 6
        [ "$TB_CAMPO" = "1" ] && serve_root=1
    done
    if [ "$serve_root" -eq 1 ] && [ "$TB_DRYRUN" -eq 0 ]; then
        echo ""
        ui_dim "Alcune operazioni richiedono i privilegi di amministratore."
        if ! tb_need_root; then
            ui_err "Privilegi non concessi: le operazioni che li richiedono non verranno eseguite."
        fi
    fi

    local spazio_prima; spazio_prima=$(free_space_bytes)
    local righe="" problemi="" reboot=0 i=0 nome_task=""

    echo ""
    ui_title "Esecuzione"
    for id in $ids; do
        i=$((i + 1))
        echo ""
        task_campo "$id" 2; nome_task="$TB_CAMPO"
        ui_step "$i/$n_op" "$nome_task"
        run_task "$id"
        righe="${righe}${RES_ESITO}|${nome_task}|${RES_BYTES}|${RES_DURATA}|${RES_ERRORS}"$'\n'
        case "$RES_ESITO" in
            OK)       ui_ok   "[completato]" ;;
            PARZIALE) ui_warn "[completato con $RES_ERRORS avvisi]" ;;
            FALLITO)  ui_err  "[non riuscito]" ;;
        esac
        if [ "$RES_ESITO" != "OK" ]; then
            problemi="${problemi}${nome_task}:"$'\n'
            problemi="${problemi}${RES_ERRLIST}"
        fi
        [ "$RES_REBOOT" -eq 1 ] && reboot=1
    done

    local delta=$(( $(free_space_bytes) - spazio_prima ))
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
        if [ "$TB_WSL" -eq 1 ]; then
            ui_warn "E' richiesto un riavvio di WSL: da PowerShell esegui  wsl --shutdown"
        else
            ui_warn "Alcune modifiche diventano effettive solo dopo il riavvio."
            if ui_yesno "Riavviare adesso?" "n"; then
                log_write "Riavvio richiesto dall'utente" "INFO"
                as_root shutdown -r +1 "Riavvio richiesto da System Toolbox" 2>/dev/null
                ui_dim "Riavvio programmato fra un minuto. Per annullare: sudo shutdown -c"
            else
                log_write "Riavvio rimandato" "INFO"
            fi
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
        case "$p" in ''|*[!0-9]*) ui_warn "Valore non valido: $p"; continue ;; esac
        id=$(echo "$tutti" | tr ' ' '\n' | grep -v '^$' | sed -n "${p}p")
        if [ -n "$id" ]; then scelti="$scelti $id"; n=$((n + 1))
        else ui_warn "Numero fuori intervallo: $p"; fi
    done
    if [ "$n" -eq 0 ]; then
        ui_warn "Nessuna operazione valida selezionata."; ui_pause; return 0
    fi
    esegui_insieme "Operazioni personalizzate" "$scelti" 0 ""
}

# ============================================================
#   MODALITA NON INTERATTIVA
# ============================================================
if [ "$AUTO" -eq 1 ]; then
    log_write "Modalita automatica" "STEP"
    if [ "$TB_JSON" -eq 1 ]; then
        analisi rapida >/dev/null 2>&1
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
    ui_title "System Toolbox - Linux / Ubuntu"
    if [ "$TB_WSL" -eq 1 ]; then
        printf '   %sAmbiente WSL rilevato: le voci non applicabili verranno saltate.%s\n' "$C_YELLOW" "$C_OFF"
    fi
    echo ""
    printf '   %sANALISI%s\n' "$C_GREEN" "$C_OFF"
    printf '     1)  Analisi completa del sistema\n'
    printf '     2)  Analisi rapida\n'
    echo ""
    printf '   %sPULIZIA%s\n' "$C_GREEN" "$C_OFF"
    printf '     3)  Pulizia sicura            %sAPT, journal, cache utente, cestino%s\n' "$C_DIM" "$C_OFF"
    printf '     4)  Pulizia avanzata          %spacchetti orfani, snap, kernel vecchi%s\n' "$C_DIM" "$C_OFF"
    echo ""
    printf '   %sRETE%s\n' "$C_GREEN" "$C_OFF"
    printf '     5)  Manutenzione rete         %sDNS e indirizzo IP%s\n' "$C_DIM" "$C_OFF"
    printf '     6)  Riavvia gestione di rete  %sla connessione cade per qualche secondo%s\n' "$C_DIM" "$C_OFF"
    echo ""
    printf '   %sAGGIORNAMENTI E MANUTENZIONE%s\n' "$C_GREEN" "$C_OFF"
    printf '     7)  Aggiornamenti del sistema %sapt, dist-upgrade, snap, flatpak%s\n' "$C_DIM" "$C_OFF"
    printf '     8)  Riparazione e disco       %sTRIM, fix pacchetti, PAM%s\n' "$C_DIM" "$C_OFF"
    printf '     9)  Manutenzione consigliata  %spulizia sicura + DNS%s\n' "$C_DIM" "$C_OFF"
    echo ""
    printf '   %sALTRO%s\n' "$C_GREEN" "$C_OFF"
    printf '     P)  Selezione personalizzata  %sscegli le singole operazioni%s\n' "$C_DIM" "$C_OFF"
    printf '     L)  Percorso della cartella dei log\n'
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
             "Queste operazioni rimuovono pacchetti dal sistema. L'elenco preciso di cio' che verra' rimosso viene mostrato prima di procedere, e il kernel in uso non viene mai toccato."
           ui_pause ;;
        5) esegui_insieme "Manutenzione rete" "$(task_set Rete)" 0 ""; ui_pause ;;
        6) esegui_insieme "Riavvio della gestione di rete" "$(task_set ReteRiavvio)" 0 \
             "La connessione cadra' per qualche secondo. Se sei collegato da remoto, la sessione si interrompe."
           ui_pause ;;
        7) esegui_insieme "Aggiornamenti del sistema" "$(task_set Aggiornamenti)" 0 \
             "E' il giro completo: apt upgrade, poi full-upgrade che puo' anche rimuovere pacchetti per risolvere dipendenze, poi snap e flatpak. L'elenco di cio' che verra' installato e rimosso viene mostrato prima di ogni passo. Puo' richiedere parecchi minuti e in alcuni casi il riavvio."
           ui_pause ;;
        8) esegui_insieme "Riparazione e disco" "$(task_set Manutenzione)" 0 \
             "La correzione PAM interviene solo se il modulo pam_lastlog non esiste piu' su questo sistema, e fa comunque una copia di sicurezza."
           ui_pause ;;
        9) esegui_insieme "Manutenzione consigliata" "$(task_set Consigliata)" 0 ""; ui_pause ;;
        P) selezione_personalizzata; ui_pause ;;
        L) echo ""; ui_kv "Cartella dei log" "$TB_DIR/logs"
           command -v xdg-open >/dev/null 2>&1 && [ "$TB_WSL" -eq 0 ] && xdg-open "$TB_DIR/logs" >/dev/null 2>&1
           sleep 2 ;;
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
