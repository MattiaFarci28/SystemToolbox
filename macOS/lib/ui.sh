#!/bin/bash
# ============================================================
#   ui.sh - Rendering testuale
#
#   Tutto cio' che scrive a schermo sta qui. Le funzioni ui_*
#   consumano i dati prodotti da analysis.sh.
#   Stessa separazione della versione Windows: se un domani si
#   aggiunge un frontend grafico (osascript), il motore e i
#   raccoglitori dati non cambiano.
#
#   I colori si spengono da soli se l'output non e' un
#   terminale (redirezione su file, pipe).
# ============================================================

# ------------------------------------------------------------
#   Colori
#   CFG_colori: auto (predefinito) | si | no | daltonici
#
#   In modalita' daltonici verde e rosso, che sono la coppia
#   piu' problematica, vengono sostituiti da blu e arancione, e
#   soprattutto ogni stato porta un SIMBOLO: il colore smette di
#   essere l'unico segnale. Il resto dell'interfaccia usa gli
#   stessi simboli anche nelle altre modalita', cosi' il
#   significato non cambia da una modalita' all'altra.
# ------------------------------------------------------------
ui_colori_init() {
    local usa=0
    case "${CFG_colori:-auto}" in
        no)        usa=0 ;;
        si|daltonici) usa=1 ;;
        *)         [ -t 1 ] && usa=1 ;;
    esac

    if [ "$usa" -eq 0 ]; then
        C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""
        C_MAGENTA=""; C_CYAN=""; C_WHITE=""; C_DIM=""; C_OFF=""
    elif [ "${CFG_colori}" = "daltonici" ]; then
        C_RED=$'\033[0;33m'      # arancione al posto del rosso
        C_GREEN=$'\033[0;34m'    # blu al posto del verde
        C_YELLOW=$'\033[0;36m'
        C_BLUE=$'\033[0;34m';    C_MAGENTA=$'\033[0;35m'
        C_CYAN=$'\033[0;36m';    C_WHITE=$'\033[1;37m'
        C_DIM=$'\033[0;90m';     C_OFF=$'\033[0m'
    else
        C_RED=$'\033[0;31m';    C_GREEN=$'\033[0;32m'
        C_YELLOW=$'\033[0;33m'; C_BLUE=$'\033[0;34m'
        C_MAGENTA=$'\033[0;35m';C_CYAN=$'\033[0;36m'
        C_WHITE=$'\033[1;37m';  C_DIM=$'\033[0;90m'
        C_OFF=$'\033[0m'
    fi
}
ui_colori_init

# Larghezza adattata al terminale reale: con separatori piu'
# larghi della finestra il testo va a capo e si accavalla.
ui_width() {
    local w
    w=$(tput cols 2>/dev/null)
    [ -z "$w" ] && w=80
    [ "$w" -lt 50 ] && w=50
    [ "$w" -gt 100 ] && w=100
    echo $((w - 2))
}
TB_W=$(ui_width)

# Non aggiunge rientro: lo decide chi chiama, cosi' le righe di
# separazione restano allineate alle colonne che devono separare.
# In modalita' utf8 le linee diventano tratti continui.
# Costruita in bash e non con "printf | tr": tr lavora sui byte,
# quindi sostituire uno spazio con un carattere UTF-8 da tre byte
# lo troncherebbe. In piu' si risparmia un processo per riga.
ui_line() {
    local c="${1:-=}" n="${2:-$TB_W}"
    if [ "$CFG_cornici" = "utf8" ]; then
        case "$c" in
            '=') c=$'\xe2\x95\x90' ;;   # doppio tratto
            '-') c=$'\xe2\x94\x80' ;;   # tratto semplice
        esac
    fi
    local out="" i=0
    while [ "$i" -lt "$n" ]; do out="$out$c"; i=$(( i + 1 )); done
    printf '%s\n' "$out"
}

ui_title() {
    echo ""
    printf '%s ' "$C_CYAN"; ui_line '='
    printf '%s   %s%s\n' "$C_CYAN" "$(echo "$1" | tr '[:lower:]' '[:upper:]')" "$C_OFF"
    printf '%s ' "$C_CYAN"; ui_line '='; printf '%s' "$C_OFF"
    rep_add ""; rep_add "## $1"; rep_add ""
}

ui_section() {
    echo ""
    printf '  %s[%s]%s\n' "$C_GREEN" "$1" "$C_OFF"
    printf '  %s' "$C_DIM"; ui_line '-' $((TB_W - 2)); printf '%s' "$C_OFF"
    rep_add ""; rep_add "## $1"; rep_add ""
}

# Ogni funzione alimenta anche il buffer del report: il documento
# esportato nasce dallo stesso codice che disegna a schermo, cosi'
# non esistono due descrizioni da tenere allineate.
# ------------------------------------------------------------
#   Simboli di stato.
#   CFG_simboli: ascii (predefinito) | emoji
#
#   Il vecchio Ubuntu.sh usava le emoji, ed erano il suo tratto
#   piu' riconoscibile. Il problema e' che in una console TTY,
#   via SSH con LANG=C o dentro una console di ripristino
#   diventano caratteri illeggibili: per questo l'ascii resta il
#   predefinito e l'emoji e' una scelta esplicita.
#
#   Scritti come byte e non come caratteri, cosi' il sorgente
#   resta in ASCII puro e non dipende dalla codifica con cui il
#   file viene salvato o trasferito.
#
#   Le larghezze restano coerenti fra i tre stati: in ascii
#   quattro colonne, in emoji tre (due del glifo piu' lo
#   spazio). Cambia il rientro fra le due modalita', non
#   l'allineamento dentro la stessa.
# ------------------------------------------------------------
TB_SYM_OK="[ok]"; TB_SYM_WARN="[!] "; TB_SYM_ERR="[X] "

ui_simboli_init() {
    if [ "$CFG_simboli" = "emoji" ]; then
        TB_SYM_OK=$'\xe2\x9c\x85 '              # U+2705  segno di spunta
        TB_SYM_WARN=$'\xe2\x9a\xa0\xef\xb8\x8f ' # U+26A0  attenzione
        TB_SYM_ERR=$'\xe2\x9d\x8c '             # U+274C  croce
    else
        TB_SYM_OK="[ok]"; TB_SYM_WARN="[!] "; TB_SYM_ERR="[X] "
    fi
}
ui_simboli_init

ui_kv()    { printf '   %-20s: %s\n' "$1" "$2"; rep_add "- **$1**: $2"; }
ui_kvc()   { printf '   %-20s: %s%s%s\n' "$1" "$2" "$3" "$C_OFF"; rep_add "- **$1**: $3"; }
ui_step()  { printf '  %s[%s]%s %s\n' "$C_YELLOW" "$1" "$C_OFF" "$2"; }
# Il report resta sempre in ascii: un Markdown pieno di emoji
# invecchia male e non si legge in un diff.
ui_ok()    { printf '   %s%s %s%s\n' "$C_GREEN"  "$TB_SYM_OK"   "$1" "$C_OFF"; rep_add "> [ok] $1"; }
ui_warn()  { printf '   %s%s %s%s\n' "$C_YELLOW" "$TB_SYM_WARN" "$1" "$C_OFF"; rep_add "> [!] $1"; }
ui_err()   { printf '   %s%s %s%s\n' "$C_RED"    "$TB_SYM_ERR"  "$1" "$C_OFF"; rep_add "> [X] $1"; }
ui_dim()   { printf '   %s%s%s\n' "$C_DIM" "$1" "$C_OFF"; rep_add "$1"; }

# Chiamate dal motore in core.sh
ui_detail()     { printf '      %s%s%s\n' "$C_DIM" "$1" "$C_OFF"; }
ui_detail_err() { printf '      %s! %s%s\n' "$C_YELLOW" "$1" "$C_OFF"; }

# Manda a capo un testo lungo rispettando la larghezza corrente.
# Tutto in bash: prima si invocava fold, cioe' un processo per
# ogni paragrafo, e su hardware datato si sente.
# set -f durante il ciclo, altrimenti una parola come * verrebbe
# espansa nei nomi dei file della cartella corrente.
ui_wrap() {
    local testo="$1" rientro="${2:-3}" colore="${3:-}"
    local larg=$(( TB_W - rientro ))
    [ "$larg" -lt 20 ] && larg=20
    local riga="" parola
    set -f
    for parola in $testo; do
        if [ -z "$riga" ]; then
            riga="$parola"
        elif [ $(( ${#riga} + 1 + ${#parola} )) -le "$larg" ]; then
            riga="$riga $parola"
        else
            printf '%*s%s%s%s\n' "$rientro" "" "$colore" "$riga" "$C_OFF"
            riga="$parola"
        fi
    done
    set +f
    [ -n "$riga" ] && printf '%*s%s%s%s\n' "$rientro" "" "$colore" "$riga" "$C_OFF"
    return 0
}

# Barra di riempimento. In modalita' utf8 usa i blocchi, che
# rendono molto meglio; l'ascii resta il predefinito perche' e'
# leggibile ovunque, anche via SSH e in console TTY.
ui_bar() {
    local pct="${1:-0}" larg="${2:-24}"
    [ "$pct" -lt 0 ] && pct=0
    [ "$pct" -gt 100 ] && pct=100
    local pieni=$(( pct * larg / 100 ))
    local i out="" c_pieno='#' c_vuoto='.'
    # Scritti come byte e non come caratteri: il sorgente resta in
    # ASCII puro, cosi' non dipende dalla codifica con cui il file
    # viene salvato o trasferito. U+2588 e U+2591.
    if [ "$CFG_cornici" = "utf8" ]; then
        c_pieno=$'\xe2\x96\x88'; c_vuoto=$'\xe2\x96\x91'
    fi
    i=0; while [ $i -lt $pieni ]; do out="$out$c_pieno"; i=$(( i + 1 )); done
    while [ $i -lt $larg ]; do out="$out$c_vuoto"; i=$(( i + 1 )); done
    printf '%s' "$out"
}

ui_pct_color() {
    local pct="${1:-0}" giallo="${2:-65}" rosso="${3:-85}"
    if   [ "$pct" -ge "$rosso" ];  then printf '%s' "$C_RED"
    elif [ "$pct" -ge "$giallo" ]; then printf '%s' "$C_YELLOW"
    else printf '%s' "$C_GREEN"; fi
}

ui_pause() {
    echo ""
    printf '  %s' "${1:-Premi INVIO per tornare al menu}"
    read -r _
}

# Risposta si/no. Niente ${var,,}: e' bash 4 e su macOS non esiste.
ui_yesno() {
    local domanda="$1" predefinito="${2:-n}"
    local suffisso="[s/N]"
    [ "$predefinito" = "s" ] && suffisso="[S/n]"
    while true; do
        printf '  %s%s %s%s ' "$C_WHITE" "$domanda" "$suffisso" "$C_OFF"
        local r; read -r r
        r=$(printf '%s' "$r" | tr '[:upper:]' '[:lower:]')
        [ -z "$r" ] && r="$predefinito"
        case "$r" in
            s|si|y|yes) return 0 ;;
            n|no)       return 1 ;;
        esac
    done
}

# ------------------------------------------------------------
#   Conferma con finestra di dialogo (solo macOS).
#   Serve per le operazioni distruttive: una finestra si nota,
#   mentre a un "[s/N]" in fondo a una schermata di testo si
#   risponde per abitudine senza leggere.
#   Si attiva con  conferme_grafiche=si  nella configurazione.
# ------------------------------------------------------------
ui_yesno_dialogo() {
    local titolo="$1" testo="$2"
    command -v osascript >/dev/null 2>&1 || return 2
    # Il testo va nel dialogo dentro virgolette AppleScript:
    # barre rovesciate e virgolette vanno protette, altrimenti un
    # nome di cartella con un apice manda in errore lo script e
    # la conferma non comparirebbe.
    local sicuro; sicuro=$(printf '%s' "$testo" | sed 's/\\/\\\\/g; s/"/\\"/g')
    local tit; tit=$(printf '%s' "$titolo" | sed 's/\\/\\\\/g; s/"/\\"/g')
    # Su una riga sola: la continuazione di riga di AppleScript e'
    # il carattere U+00AC, e il sorgente resta in ASCII puro.
    local risposta
    risposta=$(osascript 2>/dev/null <<FINEOSA
try
    set esito to button returned of (display dialog "$sicuro" with title "$tit" buttons {"Annulla", "Procedi"} default button "Annulla" with icon caution)
    return esito
on error messaggio number codice
    if codice is -128 then return "Annulla"
    return "ERRORE"
end try
FINEOSA
)
    # -128 e' il pulsante Annulla. Qualsiasi altro errore (nessuna
    # sessione grafica, Mac raggiunto via SSH, permesso negato) NON
    # e' una risposta dell'utente: si restituisce 2 e ui_conferma
    # chiede nel terminale. Prima veniva letto come "Annulla", e con
    # conferme_grafiche=si ogni operazione finiva annullata da sola.
    case "$risposta" in
        Procedi) return 0 ;;
        Annulla) return 1 ;;
        *)       return 2 ;;
    esac
}

# Sceglie da sola fra terminale e finestra, secondo la
# configurazione. Le operazioni distruttive usano questa.
ui_conferma() {
    local domanda="$1" titolo="${2:-System Toolbox}" testo="${3:-$1}"
    if [ "$CFG_conferme_grafiche" = "si" ]; then
        ui_yesno_dialogo "$titolo" "$testo"
        local rc=$?
        [ "$rc" -ne 2 ] && return $rc
        # osascript non disponibile: si ricade sul terminale.
    fi
    ui_yesno "$domanda" "n"
}

# ------------------------------------------------------------
#   Notifica di sistema a fine esecuzione.
#   Utile quando si lancia una pulizia lunga e si va a fare
#   altro: la finestra del terminale resta dietro.
# ------------------------------------------------------------
ui_notifica() {
    [ "$CFG_notifica_fine" = "si" ] || return 0
    command -v osascript >/dev/null 2>&1 || return 0
    local testo; testo=$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')
    osascript -e "display notification \"$testo\" with title \"System Toolbox\"" >/dev/null 2>&1
    return 0
}

# ============================================================
#   ELENCHI E RIEPILOGHI DEI TASK
# ============================================================

# In modalita' emoji il pallino sostituisce le parentesi ma la
# parola resta: il colore e la forma da soli non bastano, e chi
# non riconosce il glifo deve poter leggere comunque il livello.
ui_badge() {
    if [ "$CFG_simboli" = "emoji" ]; then
        case "$1" in
            avanzato)     printf '%s%s %-8s%s' "$C_YELLOW"  $'\xf0\x9f\x9f\xa1' "avanzato" "$C_OFF" ;;
            riavvio)      printf '%s%s %-8s%s' "$C_MAGENTA" $'\xf0\x9f\x94\x84' "riavvio"  "$C_OFF" ;;
            sconsigliato) printf '%s%s %-8s%s' "$C_RED"     $'\xf0\x9f\x94\xb4' "SCONSIG." "$C_OFF" ;;
            *)            printf '%s%s %-8s%s' "$C_DIM"     $'\xf0\x9f\x9f\xa2' "sicuro"   "$C_OFF" ;;
        esac
        return 0
    fi
    case "$1" in
        avanzato)     printf '%s[avanzato]%s' "$C_YELLOW" "$C_OFF" ;;
        riavvio)      printf '%s[riavvio] %s' "$C_MAGENTA" "$C_OFF" ;;
        sconsigliato) printf '%s[SCONSIG.]%s' "$C_RED" "$C_OFF" ;;
        *)            printf '%s[sicuro]  %s' "$C_DIM" "$C_OFF" ;;
    esac
}

# Elenco con descrizione e tempo di ciascuna voce.
#
# Qui si usa task_campo, che scrive in TB_CAMPO invece di
# stampare: erano cinque sostituzioni di comando per riga, cioe'
# cinque fork, moltiplicati per tutte le voci di ogni menu,
# elenco e riepilogo. Il dettaglio della misura sta nel commento
# di task_campo, in tasks.sh.
ui_task_detail() {
    local id livello nome stima descr
    for id in $1; do
        task_campo "$id" 4; livello="$TB_CAMPO"
        task_campo "$id" 2; nome="$TB_CAMPO"
        task_campo "$id" 5; stima="$TB_CAMPO"
        task_campo "$id" 8; descr="$TB_CAMPO"
        printf '   %s %s%s%s' "$(ui_badge "$livello")" "$C_WHITE" "$nome" "$C_OFF"
        printf '  %s(%s)%s\n' "$C_DIM" "$(format_stima "$stima")" "$C_OFF"
        ui_wrap "$descr" 15 "$C_DIM"
    done
}

ui_task_list_numbered() {
    local n=1 id livello nome
    for id in $1; do
        task_campo "$id" 4; livello="$TB_CAMPO"
        task_campo "$id" 2; nome="$TB_CAMPO"
        printf '  %2d)  %s %s\n' "$n" "$(ui_badge "$livello")" "$nome"
        n=$((n + 1))
    done
}

# ============================================================
#   RIEPILOGO FINALE
#   I risultati arrivano come righe "esito|nome|byte|durata|errori"
#   accumulate durante l'esecuzione: bash 3.2 non ha strutture.
# ============================================================
ui_summary() {
    local righe="$1" spazio_reale="${2:--1}" problemi="$3"

    ui_title "Riepilogo"
    echo ""
    printf '   %s%-34s %-9s %11s %8s%s\n' "$C_WHITE" "Operazione" "Esito" "Liberato" "Durata" "$C_OFF"
    printf '   %s' "$C_DIM"; ui_line '-' 65; printf '%s' "$C_OFF"

    local tot=0
    while IFS='|' read -r esito nome byte durata err; do
        [ -z "$esito" ] && continue
        local col="$C_GREEN"
        [ "$esito" = "PARZIALE" ] && col="$C_YELLOW"
        [ "$esito" = "FALLITO" ]  && col="$C_RED"
        local corto="$nome"
        if [ ${#corto} -gt 33 ]; then corto="$(printf '%.30s...' "$corto")"; fi
        printf '   %-34s %s%-9s%s %11s %8s\n' "$corto" "$col" "$esito" "$C_OFF" "$(format_bytes "$byte")" "$(format_durata "$durata")"
        tot=$((tot + byte))
    done <<< "$righe"

    printf '   %s' "$C_DIM"; ui_line '-' 65; printf '%s' "$C_OFF"
    printf '   %s%-34s %-9s %11s%s\n' "$C_CYAN" "TOTALE" "" "$(format_bytes "$tot")" "$C_OFF"

    if [ "$spazio_reale" -ge 0 ] 2>/dev/null; then
        echo ""
        ui_kvc "Spazio su disco" "$C_CYAN" "$(format_bytes "$spazio_reale") liberi in piu' (misura di controllo)"
        ui_dim "Su APFS il valore puo' differire: gli snapshot trattengono lo spazio finche' non scadono."
    fi

    echo ""
    if [ -n "$problemi" ]; then
        printf '   %sDettaglio dei problemi:%s\n' "$C_YELLOW" "$C_OFF"
        echo "$problemi" | while IFS= read -r r; do
            [ -n "$r" ] && ui_warn "  $r"
        done
    else
        ui_ok "Tutte le operazioni completate senza errori."
    fi
}
