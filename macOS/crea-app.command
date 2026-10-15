#!/bin/bash
# ============================================================
#   SYSTEM TOOLBOX - creazione del wrapper .app
#
#   Costruisce "System Toolbox.app" accanto a toolbox.command,
#   cosi' il tool si avvia come una normale applicazione: doppio
#   clic dal Finder, icona propria, si puo' tenere nel Dock.
#
#   Perche' serve uno script e non un .app gia' pronto:
#   il bit di esecuzione non sopravvive alla copia da Windows
#   ne' allo scompattamento di uno zip creato altrove, e un .app
#   il cui eseguibile non e' eseguibile non parte e basta, senza
#   spiegare perche'. Ricostruirlo qui sul Mac risolve il
#   problema alla radice.
#
#   Uso:  ./crea-app.command       (oppure doppio clic)
#   Se e' appena stato copiato:    chmod +x crea-app.command
#
#   NON va lanciato con sudo: l'app deve appartenere all'utente.
# ============================================================

set -u

TB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$TB_DIR/System Toolbox.app"

titolo()  { printf '\n  \033[1m%s\033[0m\n  %s\n\n' "$1" "$(printf '%.0s-' $(seq 1 ${#1}))"; }
ok()      { printf '  \033[32m[ok]\033[0m  %s\n' "$1"; }
avviso()  { printf '  \033[33m[!]\033[0m   %s\n' "$1"; }
errore()  { printf '  \033[31m[X]\033[0m   %s\n' "$1"; }

titolo "System Toolbox - creazione dell'applicazione"

# ------------------------------------------------------------
#   Controlli preliminari
# ------------------------------------------------------------
if [ "$(uname -s)" != "Darwin" ]; then
    errore "Questo script funziona solo su macOS."
    exit 2
fi

if [ ! -f "$TB_DIR/toolbox.command" ]; then
    errore "toolbox.command non trovato in questa cartella."
    echo   "        Tieni crea-app.command accanto al resto del tool."
    exit 2
fi

if [ "$(id -u)" -eq 0 ]; then
    errore "Non lanciarlo con sudo: l'app resterebbe di proprieta' di root."
    exit 2
fi

# Il bit di esecuzione sul tool: e' il motivo per cui siamo qui.
if [ ! -x "$TB_DIR/toolbox.command" ]; then
    chmod +x "$TB_DIR/toolbox.command" 2>/dev/null \
        && ok "Permesso di esecuzione aggiunto a toolbox.command" \
        || avviso "Non sono riuscito a rendere eseguibile toolbox.command"
else
    ok "toolbox.command e' gia' eseguibile"
fi

# ------------------------------------------------------------
#   L'app esistente viene rifatta da zero
# ------------------------------------------------------------
if [ -d "$APP" ]; then
    # Rimozione mirata: solo il bundle che abbiamo creato noi,
    # riconosciuto dal file marcatore che ci scriviamo dentro.
    if [ -f "$APP/Contents/.system-toolbox" ]; then
        rm -rf "$APP"
        ok "Versione precedente dell'app rimossa"
    else
        errore "Esiste gia' una 'System Toolbox.app' che non ho creato io."
        echo   "        Spostala o rinominala, poi rilancia questo script."
        exit 2
    fi
fi

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" || {
    errore "Non riesco a creare l'applicazione in questa cartella."
    echo   "        Serve il permesso di scrittura su: $TB_DIR"
    exit 2
}
: > "$APP/Contents/.system-toolbox"

# ------------------------------------------------------------
#   Info.plist
#
#   LSUIElement non va messo: l'app deve comparire nel Dock
#   mentre il Terminale e' aperto. NSHighResolutionCapable evita
#   il rendering sfocato sui display Retina.
# ------------------------------------------------------------
cat > "$APP/Contents/Info.plist" <<'FINEPLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>System Toolbox</string>
    <key>CFBundleDisplayName</key>       <string>System Toolbox</string>
    <key>CFBundleIdentifier</key>        <string>local.systemtoolbox.launcher</string>
    <key>CFBundleVersion</key>           <string>1.0.0</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleExecutable</key>        <string>SystemToolbox</string>
    <key>CFBundleIconFile</key>          <string>icona</string>
    <key>NSHighResolutionCapable</key>   <true/>
</dict>
</plist>
FINEPLIST
ok "Info.plist scritto"

# ------------------------------------------------------------
#   Eseguibile del bundle
#
#   Non fa il lavoro: apre il Terminale sul toolbox. Serve il
#   Terminale perche' il tool e' interattivo, chiede conferme e
#   la password di amministratore.
#
#   Il percorso del tool viene inciso adesso: se sposti la
#   cartella, rilancia crea-app.command.
# ------------------------------------------------------------
cat > "$APP/Contents/MacOS/SystemToolbox" <<FINELAUNCHER
#!/bin/bash
# Avviatore generato da crea-app.command. Non modificarlo a mano:
# viene riscritto a ogni esecuzione di quello script.
TOOL="$TB_DIR/toolbox.command"

if [ ! -x "\$TOOL" ]; then
    osascript -e 'display alert "System Toolbox" message "Il tool non si trova piu al percorso registrato. Rilancia crea-app.command dalla cartella del tool." as critical' >/dev/null 2>&1
    exit 1
fi

# "open -a Terminal" apre una scheda nuova e lascia il controllo
# al Terminale: il tool resta interattivo e la finestra non si
# chiude da sola quando finisce.
open -a Terminal "\$TOOL"
FINELAUNCHER
chmod +x "$APP/Contents/MacOS/SystemToolbox"
ok "Avviatore creato e reso eseguibile"

# ------------------------------------------------------------
#   Icona
#
#   Prima scelta: il logo del progetto, icona.png accanto al
#   tool. Il formato .icns si costruisce qui sul Mac con sips e
#   iconutil, che fanno parte di macOS: un .icns preparato su
#   Windows non si potrebbe verificare.
#
#   Ripiego: un'icona di sistema, gia' presente su ogni Mac.
#   L'elenco e' in ordine di preferenza e i nomi cambiano fra le
#   versioni di macOS, quindi si prova finche' non se ne trova una.
# ------------------------------------------------------------
icona_fatta=""
if [ -f "$TB_DIR/icona.png" ] && command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1; then
    SET="$(mktemp -d "${TMPDIR:-/tmp}/tb_icona_XXXXXX")/icona.iconset"
    mkdir -p "$SET"
    for n in 16 32 128 256 512; do
        sips -z "$n" "$n" "$TB_DIR/icona.png" --out "$SET/icon_${n}x${n}.png" >/dev/null 2>&1
        d=$(( n * 2 ))
        sips -z "$d" "$d" "$TB_DIR/icona.png" --out "$SET/icon_${n}x${n}@2x.png" >/dev/null 2>&1
    done
    if iconutil -c icns "$SET" -o "$APP/Contents/Resources/icona.icns" >/dev/null 2>&1; then
        icona_fatta="si"
        ok "Icona: logo di System Toolbox"
    fi
    rm -rf "$(dirname "$SET")"
fi

CORETYPES="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources"
icona_trovata=""
for candidata in \
    "$CORETYPES/ToolbarUtilitiesIcon.icns" \
    "$CORETYPES/UtilitiesFolder.icns" \
    "/System/Applications/Utilities/Disk Utility.app/Contents/Resources/AppIcon.icns" \
    "/Applications/Utilities/Disk Utility.app/Contents/Resources/AppIcon.icns" \
    "$CORETYPES/ExecutableBinaryIcon.icns" \
    "$CORETYPES/GenericApplicationIcon.icns" \
    ; do
    if [ -f "$candidata" ]; then icona_trovata="$candidata"; break; fi
done

if [ -n "$icona_fatta" ]; then
    :
elif [ -n "$icona_trovata" ]; then
    cp "$icona_trovata" "$APP/Contents/Resources/icona.icns" 2>/dev/null \
        && ok "Icona: $(basename "$icona_trovata")" \
        || avviso "Icona non copiata: l'app usera' quella generica"
else
    avviso "Nessuna icona di sistema trovata: l'app usera' quella generica"
fi

# ------------------------------------------------------------
#   Registrazione presso il Finder
#
#   Senza questo passaggio l'icona resta quella generica finche'
#   non si fa logout: il Finder tiene in cache l'aspetto dei
#   bundle e non si accorge di uno appena creato.
# ------------------------------------------------------------
touch "$APP"
LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
[ -x "$LSREG" ] && "$LSREG" -f "$APP" >/dev/null 2>&1

# Gatekeeper: il bundle e' stato creato in locale, non scaricato,
# quindi non ha l'attributo di quarantena. Lo si toglie comunque
# nel caso la cartella intera arrivi da uno zip scaricato.
xattr -dr com.apple.quarantine "$APP" >/dev/null 2>&1

echo ""
ok "Applicazione creata: System Toolbox.app"
echo ""
printf '  Da qui puoi:\n'
printf '    - avviarla con un doppio clic dal Finder\n'
printf '    - trascinarla nel Dock per tenerla a portata di mano\n'
printf '    - continuare a usare ./toolbox.command dal terminale\n'
echo ""
printf '  \033[2mSe sposti la cartella del tool, rilancia questo script:\n'
printf '  il percorso e inciso nell app.\033[0m\n'
echo ""
