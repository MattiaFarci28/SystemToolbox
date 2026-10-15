#!/bin/bash
# ============================================================
#   SYSTEM TOOLBOX - scorciatoie di sistema
#
#   Installa, per l'utente corrente e senza toccare niente
#   fuori dalla sua home:
#
#     - la voce nel menu applicazioni (file .desktop)
#     - il completamento bash dei parametri
#     - un collegamento in ~/.local/bin
#
#   Tutto sotto ~/.local e ~/.bash_completion.d: niente sudo,
#   niente file di sistema, e si disinstalla con --rimuovi.
#
#   Uso:  ./installa-scorciatoie.sh
#         ./installa-scorciatoie.sh --rimuovi
#
#   NON va lanciato con sudo: le scorciatoie finirebbero nella
#   home di root, cioe' da nessuna parte utile.
# ============================================================

set -u

TB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DIR_DESKTOP="$HOME/.local/share/applications"
DIR_BIN="$HOME/.local/bin"
DIR_COMP="$HOME/.bash_completion.d"

DIR_ICONE="$HOME/.local/share/icons/hicolor/256x256/apps"

FILE_DESKTOP="$DIR_DESKTOP/system-toolbox.desktop"
FILE_ICONA="$DIR_ICONE/system-toolbox.png"
FILE_BIN="$DIR_BIN/system-toolbox"
FILE_COMP="$DIR_COMP/system-toolbox"

ok()     { printf '  \033[32m[ok]\033[0m  %s\n' "$1"; }
avviso() { printf '  \033[33m[!]\033[0m   %s\n' "$1"; }
errore() { printf '  \033[31m[X]\033[0m   %s\n' "$1"; }

printf '\n  \033[1mSystem Toolbox - scorciatoie di sistema\033[0m\n\n'

if [ "$(id -u)" -eq 0 ] && [ -z "${SUDO_USER:-}" ]; then
    errore "Non lanciarlo come root: le scorciatoie finirebbero in /root."
    exit 2
fi

# ------------------------------------------------------------
#   Rimozione
# ------------------------------------------------------------
if [ "${1:-}" = "--rimuovi" ]; then
    for f in "$FILE_DESKTOP" "$FILE_BIN" "$FILE_COMP" "$FILE_ICONA"; do
        if [ -e "$f" ] || [ -L "$f" ]; then
            rm -f "$f" && ok "Rimosso: $f"
        fi
    done
    command -v update-desktop-database >/dev/null 2>&1 && \
        update-desktop-database "$DIR_DESKTOP" >/dev/null 2>&1
    echo ""
    ok "Scorciatoie rimosse. Il tool resta dov'e'."
    echo ""
    exit 0
fi

if [ ! -f "$TB_DIR/toolbox.sh" ]; then
    errore "toolbox.sh non trovato in questa cartella."
    exit 2
fi
# Il bit di esecuzione non sopravvive alla copia da Windows ne'
# a uno zip creato altrove: si rimette qui, che e' il momento in
# cui ce ne accorgeremmo comunque.
chmod +x "$TB_DIR/toolbox.sh" 2>/dev/null
[ -f "$TB_DIR/toolbox-gui.sh" ] && chmod +x "$TB_DIR/toolbox-gui.sh" 2>/dev/null

mkdir -p "$DIR_DESKTOP" "$DIR_BIN" "$DIR_COMP" || {
    errore "Non riesco a creare le cartelle sotto la tua home."
    exit 2
}

# ------------------------------------------------------------
#   Voce nel menu applicazioni
#
#   Terminal=true e' obbligatorio: il tool e' interattivo,
#   chiede conferme e la password di amministratore. Senza,
#   partirebbe senza che si veda nulla.
#
#   Le due azioni aggiuntive compaiono con il tasto destro
#   sull'icona, nel Dock come nel menu.
# ------------------------------------------------------------

# Il logo va nel tema di icone dell'utente: cosi' la voce lo trova
# per nome, e i menu scelgono da soli la dimensione. Se manca il
# file si usa un'icona generica del tema di sistema.
NOME_ICONA="utilities-system-monitor"
if [ -f "$TB_DIR/icona.png" ] && mkdir -p "$DIR_ICONE" 2>/dev/null \
   && cp "$TB_DIR/icona.png" "$FILE_ICONA" 2>/dev/null; then
    NOME_ICONA="system-toolbox"
    command -v gtk-update-icon-cache >/dev/null 2>&1 && \
        gtk-update-icon-cache -q -t "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1
    ok "Icona installata: $FILE_ICONA"
fi

cat > "$FILE_DESKTOP" <<FINEDESKTOP
[Desktop Entry]
Type=Application
Version=1.0
Name=System Toolbox
GenericName=Manutenzione del sistema
Comment=Analisi, pulizia e manutenzione del sistema
Exec=$TB_DIR/toolbox.sh
Path=$TB_DIR
Icon=$NOME_ICONA
Terminal=true
Categories=System;Settings;
Keywords=pulizia;manutenzione;analisi;aggiornamenti;disco;
StartupNotify=false
Actions=grafica;simulazione;

[Desktop Action grafica]
Name=Interfaccia grafica
Exec=$TB_DIR/toolbox-gui.sh

[Desktop Action simulazione]
Name=Simulazione (non modifica nulla)
Exec=$TB_DIR/toolbox.sh --dry-run
FINEDESKTOP
chmod +x "$FILE_DESKTOP" 2>/dev/null
ok "Voce nel menu applicazioni: $FILE_DESKTOP"

# Il menu tiene in cache l'elenco: senza questo la voce compare
# solo al prossimo accesso.
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$DIR_DESKTOP" >/dev/null 2>&1
fi

# ------------------------------------------------------------
#   Collegamento in ~/.local/bin
# ------------------------------------------------------------
ln -sf "$TB_DIR/toolbox.sh" "$FILE_BIN"
ok "Comando: system-toolbox  ->  $FILE_BIN"
case ":$PATH:" in
    *":$DIR_BIN:"*) ;;
    *) avviso "$DIR_BIN non e' nel PATH: aggiungilo a ~/.profile per usare 'system-toolbox' da qualsiasi cartella." ;;
esac

# ------------------------------------------------------------
#   Completamento bash
# ------------------------------------------------------------
cat > "$FILE_COMP" <<'FINECOMP'
# Completamento bash per System Toolbox.
# Generato da installa-scorciatoie.sh.
_system_toolbox() {
    local corrente precedente opzioni
    corrente="${COMP_WORDS[COMP_CWORD]}"
    precedente="${COMP_WORDS[COMP_CWORD-1]}"

    # I due parametri che vogliono un percorso completano i file,
    # non le opzioni: proporre --dry-run dopo --report sarebbe
    # solo rumore.
    case "$precedente" in
        --report|--config)
            COMPREPLY=( $(compgen -f -- "$corrente") )
            return 0 ;;
    esac

    opzioni="--auto --dry-run --json --report --config --no-color
             --daltonici --emoji --no-emoji --versione --help"
    COMPREPLY=( $(compgen -W "$opzioni" -- "$corrente") )
    return 0
}
complete -F _system_toolbox system-toolbox toolbox.sh ./toolbox.sh
FINECOMP
ok "Completamento bash: $FILE_COMP"

# ~/.bash_completion.d non viene letto da solo su tutte le
# distribuzioni: si aggiunge la riga a ~/.bashrc, una volta sola.
RIGA="[ -f \"$FILE_COMP\" ] && . \"$FILE_COMP\"   # System Toolbox"
if [ -f "$HOME/.bashrc" ] && grep -Fq "System Toolbox" "$HOME/.bashrc"; then
    ok "~/.bashrc gia' predisposto"
else
    printf '\n%s\n' "$RIGA" >> "$HOME/.bashrc"
    ok "Riga aggiunta a ~/.bashrc"
fi

echo ""
ok "Fatto."
printf '  Il completamento si attiva alla prossima shell, oppure subito con:\n'
printf '    \033[1msource %s\033[0m\n' "$FILE_COMP"
printf '  Per togliere tutto:  ./installa-scorciatoie.sh --rimuovi\n'
echo ""
