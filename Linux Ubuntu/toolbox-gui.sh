#!/bin/bash
# ============================================================
#   SYSTEM TOOLBOX - interfaccia grafica (zenity)
#
#   E' la fase C della versione Linux, sullo stesso modello di
#   quella Windows: l'interfaccia cambia, il motore no.
#
#   Qui non c'e' UNA riga di logica di manutenzione. Le
#   operazioni, il registro, la simulazione, il calcolo dei byte
#   e gli esiti sono gli stessi identici moduli che usa
#   toolbox.sh: questo file si limita a scegliere le voci e a
#   mostrare i risultati. Una correzione al motore vale per
#   tutte e due le interfacce, e non esiste una seconda versione
#   delle operazioni da tenere allineata.
#
#   L'output testuale delle funzioni ui_* viene raccolto su file
#   e mostrato in una finestra: e' lo stesso trucco della
#   versione Windows, dove il pannello grafico riceve cio' che
#   la console avrebbe stampato.
#
#   Uso:  ./toolbox-gui.sh  [--dry-run]
#
#   Senza zenity o senza sessione grafica passa da sola al menu
#   testuale, invece di fallire.
#
#   NON va lanciata con sudo.
# ============================================================

TB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for modulo in common.sh core.sh ui.sh analysis.sh tasks.sh; do
    if [ ! -f "$TB_DIR/lib/$modulo" ]; then
        echo "  [ERRORE] File mancante: lib/$modulo"
        exit 1
    fi
    . "$TB_DIR/lib/$modulo"
done

cfg_load "$TB_DIR/toolbox.conf"

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) TB_DRYRUN=1 ;;
        --config)  shift; cfg_load "$1" ;;
        --config=*) cfg_load "${1#--config=}" ;;
        --help|-h)
            echo ""
            echo "  System Toolbox - interfaccia grafica $TB_VERSIONE"
            echo ""
            echo "    --dry-run       simulazione: non modifica nulla"
            echo "    --config FILE   file di configurazione diverso"
            echo ""
            exit 0 ;;
        *) echo "  Parametro non riconosciuto: $1"; exit 2 ;;
    esac
    shift
done

# ------------------------------------------------------------
#   Requisiti. Mancando qualcosa si passa al menu testuale:
#   e' un ripiego che funziona, non un errore.
# ------------------------------------------------------------
manca_grafica=""
[ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ] || manca_grafica="nessuna sessione grafica"
command -v zenity >/dev/null 2>&1 || manca_grafica="zenity non installato"

if [ -n "$manca_grafica" ]; then
    echo ""
    echo "  Interfaccia grafica non disponibile: $manca_grafica."
    echo "  Passo al menu testuale."
    echo ""
    exec "$TB_DIR/toolbox.sh" ${TB_DRYRUN:+--dry-run}
fi

# Il logo su ogni finestra. Definita solo DOPO aver verificato che
# zenity esiste: prima, "command -v zenity" troverebbe questa
# funzione e il ripiego sul menu testuale non scatterebbe mai.
if [ -f "$TB_DIR/icona.png" ]; then
    zenity() { command zenity --window-icon="$TB_DIR/icona.png" "$@"; }
fi

# In modalita' grafica i colori ANSI finirebbero dentro le
# finestre come sequenze illeggibili.
CFG_colori=no
ui_colori_init
ui_simboli_init

tb_init_env
pkg_init
prefetch_init
cache_init "$TB_DIR/logs/cache"
storico_init "$TB_DIR/logs/storico.txt"
TB_LOG=$(log_init "$TB_DIR/logs")
TB_SISTEMA="$(awk -F= '/^PRETTY_NAME=/{gsub(/"/,"",$2); print $2}' /etc/os-release 2>/dev/null) - kernel $(uname -r)"
log_write "System Toolbox $TB_VERSIONE (grafica) avviato - utente $TB_USER - dryrun=$TB_DRYRUN" "INFO"

# Cartella di lavoro con mktemp: nome casuale e accessibile solo
# all'utente. Senza, si torna al menu testuale.
TB_TMP=$(mktemp -d "${TMPDIR:-/tmp}/toolbox_gui.XXXXXXXX" 2>/dev/null) || {
    echo "  Impossibile creare la cartella temporanea: passo al menu testuale."
    exec "$TB_DIR/toolbox.sh" ${TB_DRYRUN:+--dry-run}
}

gui_chiudi() {
    prefetch_cleanup
    tb_cleanup
    [ -n "$TB_TMP" ] && rm -rf "$TB_TMP" 2>/dev/null
}
trap gui_chiudi EXIT

TITOLO="System Toolbox"

# ------------------------------------------------------------
#   Finestre di base
# ------------------------------------------------------------
gui_errore() { zenity --error --title="$TITOLO" --text="$1" --width=420 2>/dev/null; }
gui_info()   { zenity --info  --title="$TITOLO" --text="$1" --width=420 2>/dev/null; }

# Il lavoro gira dentro una sottoshell, perche' l'avanzamento
# deve arrivare a zenity da una pipe. Le variabili non
# sopravvivono a una sottoshell, quindi il codice di uscita
# maturato la' dentro viene scritto su file e riletto qui: senza
# questo passaggio il tool tornerebbe sempre 0 e l'uso in uno
# script perderebbe ogni significato.
gui_assorbi_esito() {
    local f="$TB_TMP/esito_codice" v
    [ -f "$f" ] || return 0
    v=$(cat "$f" 2>/dev/null)
    rm -f "$f" 2>/dev/null
    case "$v" in ''|*[!0-9]*) return 0 ;; esac
    [ "$v" -gt "$TB_EXIT" ] && TB_EXIT="$v"
    return 0
}

# Mostra un file di testo in una finestra scorrevole. E' la
# finestra in cui finisce tutto cio' che il menu testuale
# avrebbe stampato.
gui_mostra_file() {
    local file="$1" titolo="$2"
    zenity --text-info --title="$titolo" --filename="$file" \
           --width=900 --height=640 --font="Monospace 10" 2>/dev/null
}

# ------------------------------------------------------------
#   Analisi
#
#   L'analisi e' lunga e non si puo' sapere a che punto e': la
#   barra e' quindi pulsante, non percentuale. Fingere una
#   percentuale inventata sarebbe peggio che non averla.
# ------------------------------------------------------------
gui_analisi() {
    local modo="$1" out="$TB_TMP/analisi.txt"
    : > "$out"

    (
        # La sottoshell scrive il risultato su file; alla finestra
        # arriva solo lo stato di avanzamento.
        echo "# Raccolta dati in corso..."
        analisi "$modo" > "$out" 2>&1
        echo "$TB_EXIT" > "$TB_TMP/esito_codice"
        echo "100"
    ) | zenity --progress --title="$TITOLO" \
               --text="Analisi in corso..." \
               --pulsate --auto-close --no-cancel --width=420 2>/dev/null
    gui_assorbi_esito

    if [ ! -s "$out" ]; then
        gui_errore "L'analisi non ha prodotto risultati."
        return 1
    fi
    gui_mostra_file "$out" "$TITOLO - $( [ "$modo" = "rapida" ] && echo 'Analisi rapida' || echo 'Analisi completa' )"
    return 0
}

# ------------------------------------------------------------
#   Scelta delle operazioni
#
#   Una riga per operazione, con la casella di spunta. Le voci
#   [sicuro] non arrivano preselezionate: la selezione la fa
#   l'utente, come nel menu testuale.
# ------------------------------------------------------------
gui_scegli_operazioni() {
    local righe=() id livello nome stima categoria
    for id in $(task_all_ids); do
        task_campo "$id" 2; nome="$TB_CAMPO"
        task_campo "$id" 3; categoria="$TB_CAMPO"
        task_campo "$id" 4; livello="$TB_CAMPO"
        task_campo "$id" 5; stima="$TB_CAMPO"
        righe+=( "FALSE" "$id" "$livello" "$categoria" "$nome" "$(format_stima "$stima")" )
    done

    zenity --list --checklist --title="$TITOLO - Scegli le operazioni" \
        --text="Spunta le operazioni da eseguire.\nLe voci <b>avanzato</b> modificano il sistema: leggi la conferma prima di procedere." \
        --column="" --column="id" --column="Livello" --column="Categoria" \
        --column="Operazione" --column="Tempo" \
        --hide-column=2 --print-column=2 --separator=" " \
        --width=820 --height=560 \
        "${righe[@]}" 2>/dev/null
}

# ------------------------------------------------------------
#   Esecuzione
#
#   Qui la percentuale e' vera: si sa quante operazioni sono e
#   quante ne sono finite.
#
#   Il ciclo gira in una sottoshell, quindi le variabili non
#   sopravvivono: gli esiti passano da un file, esattamente come
#   il worker della versione Windows passa i risultati alla coda
#   condivisa.
# ------------------------------------------------------------
gui_esegui() {
    local ids="$1"
    [ -z "$(echo "$ids" | tr -d ' ')" ] && { gui_info "Nessuna operazione selezionata."; return 0; }

    local n_op stima id nome livello distruttive=""
    n_op=$(echo "$ids" | wc -w | tr -d ' ')
    stima=$(task_stima_totale "$ids")

    # --- riepilogo e conferma ---
    local elenco=""
    for id in $ids; do
        task_campo "$id" 2; nome="$TB_CAMPO"
        task_campo "$id" 4; livello="$TB_CAMPO"
        [ "$livello" != "sicuro" ] && distruttive="si"
        elenco="$elenco  [$livello] $nome"$'\n'
    done

    local avviso=""
    [ -n "$distruttive" ] && avviso=$'\nAlcune operazioni modificano il sistema.\n'
    [ "$TB_DRYRUN" -eq 1 ] && avviso=$'\nSIMULAZIONE ATTIVA: non verra modificato nulla.\n'

    zenity --question --title="$TITOLO" \
        --text="$n_op operazioni, tempo stimato $(format_stima "$stima").
$avviso
$elenco
Procedere?" \
        --ok-label="Procedi" --cancel-label="Annulla" --default-cancel \
        --width=560 2>/dev/null || return 0

    # --- privilegi, chiesti una volta sola e prima di partire ---
    local serve_root=0
    for id in $ids; do
        task_campo "$id" 6
        [ "$TB_CAMPO" = "1" ] && serve_root=1
    done
    if [ "$serve_root" -eq 1 ] && [ "$TB_DRYRUN" -eq 0 ]; then
        if ! gui_chiedi_root; then
            gui_info "Privilegi non concessi: le operazioni che li richiedono
non verranno eseguite.

Per eseguirle avvia l'interfaccia da un terminale
(./toolbox-gui.sh), dove sudo puo' chiedere la password,
oppure usa il menu testuale (./toolbox.sh)."
        fi
    fi

    local out="$TB_TMP/esecuzione.txt" esiti="$TB_TMP/esiti.txt"
    : > "$out"; : > "$esiti"
    local spazio_prima; spazio_prima=$(free_space_bytes)

    (
        local i=0 pct nome2
        for id in $ids; do
            i=$(( i + 1 ))
            pct=$(( (i - 1) * 100 / n_op ))
            task_campo "$id" 2; nome2="$TB_CAMPO"
            echo "$pct"
            echo "# $i di $n_op: $nome2"
            {
                echo ""
                echo "=== $nome2 ==="
            } >> "$out"
            run_task "$id" >> "$out" 2>&1
            printf '%s|%s|%s|%s|%s\n' \
                "$RES_ESITO" "$nome2" "$RES_BYTES" "$RES_DURATA" "$RES_ERRORS" >> "$esiti"
        done
        echo "$TB_EXIT" > "$TB_TMP/esito_codice"
        echo "100"
    ) | zenity --progress --title="$TITOLO - Esecuzione" \
               --text="Avvio..." --auto-close --no-cancel \
               --width=460 2>/dev/null
    gui_assorbi_esito

    # --- riepilogo, scritto dallo stesso ui_summary del menu ---
    local delta=$(( $(free_space_bytes) - spazio_prima ))
    [ "$TB_DRYRUN" -eq 1 ] && delta=-1
    [ "$delta" -lt 0 ] && delta=-1

    local riepilogo="$TB_TMP/riepilogo.txt"
    {
        ui_summary "$(cat "$esiti")" "$delta" ""
        echo ""
        echo "--- Dettaglio ---"
        cat "$out"
        echo ""
        echo "Log della sessione: $TB_LOG"
    } > "$riepilogo" 2>&1

    gui_mostra_file "$riepilogo" "$TITOLO - Riepilogo"

    local nfail
    nfail=$(grep -c '^FALLITO|' "$esiti")
    if [ "$nfail" -gt 0 ]; then
        ui_notifica "$nfail operazioni non riuscite"
    else
        ui_notifica "Operazioni completate"
    fi
    return 0
}

# ------------------------------------------------------------
#   Privilegi
#
#   La password NON passa da questo script: raccoglierla in una
#   finestra zenity e passarla a sudo sarebbe comodo e sbagliato.
#
#   Restano due strade che funzionano davvero:
#   - l'interfaccia e' stata avviata da un terminale: sudo chiede
#     la password li', e l'autorizzazione vale per questo processo;
#   - sudo non chiede password (NOPASSWD, o un'autorizzazione gia'
#     valida per questo stesso processo).
#
#   Le due strade della versione precedente NON funzionavano:
#   "pkexec true" autorizza solo il comando true e non apre alcuna
#   sessione a sudo; e una password digitata in un'altra finestra
#   di terminale non vale qui, perche' sudo ricorda l'autorizzazione
#   per terminale. In entrambi i casi l'utente inseriva la password
#   e le operazioni fallivano lo stesso.
# ------------------------------------------------------------
gui_chiedi_root() {
    [ "$TB_ROOT_OK" -eq 1 ] && return 0
    if [ "$(id -u)" -eq 0 ]; then TB_ROOT_OK=1; return 0; fi

    if sudo -n true 2>/dev/null; then
        tb_need_root && return 0
    fi
    if [ -t 0 ]; then
        gui_info "Servono i privilegi di amministratore.

Inserisci la password nel terminale da cui hai avviato
l'interfaccia. La password non passa da questa finestra."
        tb_need_root && return 0
    fi
    return 1
}

# ------------------------------------------------------------
#   Menu principale
# ------------------------------------------------------------
gui_menu() {
    local stato_sim scelta ids
    while true; do
        if [ "$TB_DRYRUN" -eq 1 ]; then stato_sim="ATTIVA"; else stato_sim="disattivata"; fi

        scelta=$(zenity --list --radiolist --title="$TITOLO $TB_VERSIONE" \
            --text="<b>$TB_SISTEMA</b>\nGestore pacchetti: $TB_PKG_NOME    Simulazione: <b>$stato_sim</b>" \
            --column="" --column="azione" --column="Cosa fa" \
            --hide-column=2 --print-column=2 \
            --width=680 --height=420 \
            TRUE  "rapida"    "Analisi rapida - lo stato in mezzo minuto, non modifica nulla" \
            FALSE "completa"  "Analisi completa - tutto, aggiornamenti e disco compresi" \
            FALSE "consigliata" "Manutenzione consigliata - pulizia sicura e cache DNS" \
            FALSE "scegli"    "Scegli le operazioni una per una" \
            FALSE "simulazione" "Attiva o disattiva la simulazione (ora: $stato_sim)" \
            FALSE "log"       "Apri il log di questa sessione" \
            2>/dev/null) || return 0

        case "$scelta" in
            rapida)      gui_analisi rapida ;;
            completa)    gui_analisi completa ;;
            consigliata) gui_esegui "$(task_set Consigliata)" ;;
            scegli)      ids=$(gui_scegli_operazioni) && gui_esegui "$ids" ;;
            simulazione) if [ "$TB_DRYRUN" -eq 1 ]; then TB_DRYRUN=0; else TB_DRYRUN=1; fi ;;
            log)         gui_mostra_file "$TB_LOG" "$TITOLO - Log" ;;
            '')          return 0 ;;
        esac
    done
}

gui_menu
exit "$TB_EXIT"
