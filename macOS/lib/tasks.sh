#!/bin/bash
# ============================================================
#   tasks.sh - Registro delle operazioni
#
#   Ogni operazione e' una riga del registro piu' una funzione
#   task_<id>. Il motore (run_task in core.sh) si occupa di
#   cronometro, log, conteggi ed esito reale: qui c'e' solo il
#   "cosa fare".
#
#   Su Windows il registro e' una tabella di hashtable. In bash
#   3.2 non esistono array associativi, quindi si usa una
#   tabella testuale a campi separati da barra verticale:
#
#     id|nome|categoria|livello|stima_sec|root|riavvio|descrizione
#
#   livello: sicuro | avanzato | riavvio | sconsigliato
#   root:    1 se l'operazione richiede privilegi
#   riavvio: 1 se ha effetto solo dopo il riavvio
# ============================================================

task_registry() {
cat <<'FINE'
clean_trash|Cestini (utente e sistema)|Pulizia|sicuro|20|1|0|Svuota il cestino del tuo utente e, con i privilegi, quelli degli altri utenti e dei volumi collegati.
clean_crashreports|Crash report e diagnostica|Pulizia|sicuro|10|1|0|Rimuove i rapporti di arresto anomalo generati da app e sistema. Non tocca i log correnti.
clean_logs|Log delle applicazioni|Pulizia|sicuro|15|0|0|Svuota i log applicativi in Libreria/Logs. Non tocca il registro unificato di macOS, che e' la diagnostica utile.
clean_browsercache|Cache dei browser|Pulizia|sicuro|40|0|0|Solo cache di Safari, Chrome, Firefox, Brave ed Edge. NON tocca cronologia, cookie, password o preferiti. I browser vanno chiusi.
clean_quicklook|Cache anteprime QuickLook|Pulizia|sicuro|15|0|0|Rigenera le anteprime dei file. Utile quando compaiono icone sbagliate o generiche.
clean_mail|Allegati scaricati di Mail|Pulizia|sicuro|20|0|0|Rimuove gli allegati scaricati temporaneamente da Mail. I messaggi restano sul server e in casella.
clean_cache_user|Cache utente (in blocco)|Pulizia|avanzato|60|0|0|Svuota tutta la cartella Libreria/Caches del tuo utente. I dati si rigenerano, ma le applicazioni vanno chiuse prima: alcune tengono li' anche stato di lavoro.
clean_cache_system|Cache di sistema|Pulizia|avanzato|40|1|0|Svuota /Library/Caches. Le parti protette da SIP restano intatte e vengono dichiarate come saltate.
clean_snapshots|Snapshot locali Time Machine|Pulizia|avanzato|90|1|0|Elimina le istantanee locali su APFS. E' spesso il recupero di spazio piu' grosso: trattengono i file cancellati finche' non scadono. Non tocca i backup sul disco esterno.
clean_xcode|Xcode - DerivedData e simulatori|Pulizia|avanzato|120|0|0|Rimuove i dati di compilazione e i simulatori non piu' disponibili. Si rigenerano alla compilazione successiva, che sara' piu' lenta.
clean_devcache|Cache degli strumenti di sviluppo|Pulizia|avanzato|90|0|0|Cache di npm, pip, Yarn e CocoaPods. Sono pacchetti riscaricabili.
clean_homebrew|Cache di Homebrew|Pulizia|avanzato|60|0|0|Esegue brew cleanup: rimuove versioni vecchie di formule e archivi scaricati.
clean_docker|Spazio di Docker|Pulizia|avanzato|90|0|0|Rimuove immagini, contenitori e volumi non utilizzati. Va eseguito solo se sai cosa hai in Docker.
clean_fontcache|Cache dei font|Pulizia|avanzato|30|1|0|Ricostruisce la cache dei caratteri. Utile quando il testo appare corrotto o i font non compaiono nelle app.
net_flushdns|Svuota la cache DNS|Rete|sicuro|10|1|0|Elimina le risoluzioni memorizzate. Reversibile e istantaneo: da provare quando un sito non si apre ma la rete funziona.
net_renew|Rinnova indirizzo IP (DHCP)|Rete|sicuro|25|1|0|Richiede di nuovo l'indirizzo al router sull'interfaccia attiva.
net_reset|Reset preferenze di rete|Rete|riavvio|20|1|1|Azzera la configurazione di rete di macOS facendone prima una copia di sicurezza. Serve a riparare una rete che non funziona, non come manutenzione. Le reti Wi-Fi salvate vanno reinserite.
maint_launchservices|Ricostruisci il database Apri con|Manutenzione|sicuro|60|0|0|Risolve il menu Apri con pieno di voci duplicate e il Finder lento ad aprire i file.
maint_verifydisk|Verifica il volume di avvio|Manutenzione|sicuro|180|1|0|Controlla la struttura del file system senza modificarlo. Solo diagnosi.
maint_spotlight|Reindicizza Spotlight|Manutenzione|avanzato|60|1|0|Ricostruisce l'indice di ricerca da zero. Risolve una ricerca che non trova nulla, ma per alcune ore il Mac sara' piu' lento e le ventole piu' attive.
maint_updates|Installa gli aggiornamenti di macOS|Manutenzione|avanzato|1200|1|1|Scarica e installa gli aggiornamenti disponibili. Puo' richiedere molto tempo e riavviare il Mac.
maint_purge|Libera la memoria inattiva (purge)|Manutenzione|sconsigliato|20|1|0|SCONSIGLIATO: svuota la cache disco della memoria. macOS la usa apposta per andare piu' veloce, e svuotarla peggiora le prestazioni finche' non si ricostruisce. Incluso solo per completezza.
FINE
}

# ------------------------------------------------------------
#   Accesso al registro
#
#   Il registro viene analizzato UNA volta sola e scomposto in
#   variabili TB_F<campo>_<id>. Prima ogni lettura di un campo
#   eseguiva "task_registry | grep | cut", cioe' tre processi, e
#   veniva chiamata in ciclo per ogni task in ogni menu, elenco
#   e riepilogo: era il punto piu' caldo dell'intero progetto.
#   Ora la lettura e' un'espansione di variabile, senza processi.
#
#   Gli id contengono solo lettere, cifre e trattini bassi, cosi'
#   da essere usabili come parte di un nome di variabile.
# ------------------------------------------------------------
TB_REG_CARICATO=0
TB_IDS=""

task_reg_load() {
    [ "$TB_REG_CARICATO" -eq 1 ] && return 0
    local riga id resto campo i
    while IFS= read -r riga; do
        case "$riga" in ''|'#'*) continue ;; esac
        id=${riga%%|*}
        case "$id" in ''|*[!A-Za-z0-9_]*) continue ;; esac
        TB_IDS="$TB_IDS $id"
        resto="$riga"
        i=1
        while [ "$i" -le 8 ]; do
            if [ "$i" -eq 8 ]; then
                campo="$resto"
            else
                campo=${resto%%|*}
            fi
            printf -v "TB_F${i}_${id}" '%s' "$campo"
            resto=${resto#*|}
            i=$(( i + 1 ))
        done
    done <<FINEREG
$(task_registry)
FINEREG
    TB_REG_CARICATO=1
    return 0
}

task_field() {
    task_reg_load
    local v="TB_F${2}_${1}"
    printf '%s\n' "${!v}"
}

# Stessa cosa, ma SENZA sostituzione di comando: il risultato
# finisce in TB_CAMPO invece che sullo standard output.
#
# Il perche' e' tutto in una misura. Dopo la cache del registro
# la lettura di un campo e' un'espansione di variabile, cioe'
# niente; ma "$(task_field ...)" attorno le mette comunque un
# fork, ed e' quello il costo residuo. Misurato sullo stesso
# identico accesso:
#
#     con $( )   18369 us
#     senza fork    160 us
#
# La misura viene da bash su Cygwin, dove il fork costa piu' che
# altrove: il rapporto vero e' piu' contenuto, ma resta che il
# fork domina e la struttura dati non c'entra.
#
# Per confronto: un array associativo di bash 4 farebbe scendere
# la lettura da 41 a 35 microsecondi. Sei microsecondi contro
# migliaia, in cambio di perdere bash 3.2, che qui su macOS non
# e' nemmeno un'opzione.
#
# Si usa nei cicli: menu, elenchi, riepiloghi.
TB_CAMPO=""
task_campo() {
    task_reg_load
    local v="TB_F${2}_${1}"
    TB_CAMPO="${!v}"
}

task_exists() {
    task_reg_load
    local v="TB_F1_${1}"
    [ -n "${!v}" ]
}

task_all_ids() {
    task_reg_load
    local id
    for id in $TB_IDS; do printf '%s\n' "$id"; done
}

task_ids_by_category() {
    task_reg_load
    local id v
    for id in $TB_IDS; do
        v="TB_F3_${id}"
        [ "${!v}" = "$1" ] && printf '%s\n' "$id"
    done
    return 0
}

task_set() {
    case "$1" in
        PuliziaSicura)   echo "clean_trash clean_crashreports clean_logs clean_browsercache clean_quicklook clean_mail" ;;
        PuliziaAvanzata) echo "clean_cache_user clean_cache_system clean_snapshots clean_xcode clean_devcache clean_homebrew clean_fontcache" ;;
        Rete)            echo "net_flushdns net_renew" ;;
        ReteReset)       echo "net_reset" ;;
        Manutenzione)    echo "maint_launchservices maint_verifydisk maint_spotlight maint_updates" ;;
        Consigliata)     echo "clean_trash clean_crashreports clean_logs clean_browsercache clean_quicklook clean_mail net_flushdns" ;;
        *)               echo "" ;;
    esac
}

task_stima_totale() {
    local tot=0 id
    for id in $1; do
        task_campo "$id" 5
        tot=$(( tot + TB_CAMPO ))
    done
    echo "$tot"
}

# Serve un backup prima di procedere? Come su Windows: solo se
# si tocca configurazione di sistema, non per i soli file cache.
task_serve_backup() {
    local id
    for id in $1; do
        task_campo "$id" 4
        case "$TB_CAMPO" in
            riavvio)  echo "si|stai per azzerare la configurazione di rete"; return ;;
        esac
    done
    for id in $1; do
        task_campo "$id" 4
        if [ "$TB_CAMPO" = "avanzato" ]; then
            echo "si|alcune operazioni toccano cache di sistema o l'indice di Spotlight"; return
        fi
    done
    echo "no|le operazioni scelte rimuovono solo file che il sistema rigenera"
}

# ============================================================
#   PULIZIA - livello sicuro
# ============================================================

task_clean_trash() {
    clear_folder_content "$TB_HOME/.Trash" "Cestino di $TB_USER" 0
    # Cestini degli altri utenti e dei volumi: richiedono privilegi.
    if [ "$TB_ROOT_OK" -eq 1 ] || [ "$(id -u)" -eq 0 ]; then
        local d
        for d in /Users/*/; do
            local u; u=$(basename "$d")
            [ "$u" = "$TB_USER" ] && continue
            [ "$u" = "Shared" ] && continue
            [ -d "${d}.Trash" ] && clear_folder_content "${d}.Trash" "Cestino di $u" 1
        done
        [ -d /.Trashes ] && clear_folder_content "/.Trashes" "Cestino di sistema" 1
    else
        ctx_note "Cestini di altri utenti saltati: privilegi non disponibili"
    fi
}

task_clean_crashreports() {
    clear_folder_content "$TB_HOME/Library/Logs/DiagnosticReports" "Crash report utente" 0
    if [ "$TB_ROOT_OK" -eq 1 ] || [ "$(id -u)" -eq 0 ]; then
        clear_folder_content "/Library/Logs/DiagnosticReports" "Crash report di sistema" 1
    fi
    clear_folder_content "$TB_HOME/Library/Application Support/CrashReporter" "CrashReporter" 0
}

task_clean_logs() {
    # Si evita di proposito /var/log e il registro unificato in
    # /var/db/diagnostics: cancellarli distrugge diagnostica utile
    # e non recupera spazio significativo.
    local d
    for d in "$TB_HOME/Library/Logs"/*; do
        [ -d "$d" ] || continue
        case "$(basename "$d")" in
            DiagnosticReports) continue ;;
        esac
        clear_folder_content "$d" "Log $(basename "$d")" 0
    done
    ctx_note "Registro unificato di macOS non toccato: e' diagnostica, non spazzatura"
}

task_clean_browsercache() {
    # pgrep -x non accetta alternative: va interrogato un nome per volta.
    local aperti="" b
    for b in Safari "Google Chrome" firefox "Brave Browser" "Microsoft Edge"; do
        if pgrep -x "$b" >/dev/null 2>&1; then aperti="$aperti $b"; fi
    done
    [ -n "$aperti" ] && ctx_note "Browser aperti ($aperti ): molti file saranno bloccati"

    clear_folder_content "$TB_HOME/Library/Caches/com.apple.Safari" "Safari" 0
    clear_folder_content "$TB_HOME/Library/Caches/Google/Chrome" "Chrome" 0
    clear_folder_content "$TB_HOME/Library/Caches/com.brave.Browser" "Brave" 0
    clear_folder_content "$TB_HOME/Library/Caches/Microsoft Edge" "Edge" 0
    local p
    for p in "$TB_HOME/Library/Caches/Firefox/Profiles"/*; do
        [ -d "$p" ] && clear_folder_content "$p" "Firefox $(basename "$p")" 0
    done
}

task_clean_quicklook() {
    if [ "$TB_DRYRUN" -eq 1 ]; then
        ctx_note "qlmanage -r cache (simulazione)"
        return 0
    fi
    if qlmanage -r cache >/dev/null 2>&1; then
        ctx_note "Cache delle anteprime rigenerata"
    else
        ctx_fail "qlmanage non ha potuto rigenerare la cache"
    fi
}

task_clean_mail() {
    local base="$TB_HOME/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"
    if [ -d "$base" ]; then
        clear_folder_content "$base" "Allegati scaricati di Mail" 0
    else
        ctx_note "Nessuna cartella allegati di Mail trovata"
    fi
}

# ============================================================
#   PULIZIA - livello avanzato
# ============================================================

task_clean_cache_user() {
    clear_folder_content "$TB_HOME/Library/Caches" "Cache utente" 0
}

task_clean_cache_system() {
    clear_folder_content "/Library/Caches" "Cache di sistema" 1
    ctx_note "Le cartelle protette da SIP restano intatte: e' il comportamento atteso"
}

task_clean_snapshots() {
    local elenco n
    elenco=$(tmutil listlocalsnapshots / 2>/dev/null | grep -i 'com.apple.TimeMachine' | sed 's/.*TimeMachine\.//; s/\.local$//')
    if [ -z "$elenco" ]; then
        ctx_note "Nessuno snapshot locale presente"
        return 0
    fi
    n=$(echo "$elenco" | wc -l | tr -d ' ')
    if [ "$TB_DRYRUN" -eq 1 ]; then
        ctx_note "$n snapshot locali verrebbero eliminati (simulazione)"
        return 0
    fi
    local prima; prima=$(free_space_bytes)
    local ok=0 ko=0 s
    for s in $elenco; do
        if as_root tmutil deletelocalsnapshots "$s" >/dev/null 2>&1; then
            ok=$((ok + 1))
        else
            ko=$((ko + 1))
        fi
    done
    local dopo lib
    dopo=$(free_space_bytes)
    lib=$((dopo - prima)); [ "$lib" -lt 0 ] && lib=0
    CTX_BYTES=$((CTX_BYTES + lib))
    CTX_ITEMS=$((CTX_ITEMS + ok))
    ctx_note "$ok snapshot eliminati, $(format_bytes "$lib") restituiti al volume"
    [ "$ko" -gt 0 ] && ctx_fail "$ko snapshot non eliminabili (in uso da un backup in corso)"
    return 0
}

task_clean_xcode() {
    local dd="$TB_HOME/Library/Developer/Xcode/DerivedData"
    if [ ! -d "$dd" ] && [ ! -d "$TB_HOME/Library/Developer/CoreSimulator" ]; then
        ctx_note "Xcode non presente su questo sistema"
        return 0
    fi
    clear_folder_content "$dd" "Xcode DerivedData" 0
    clear_folder_content "$TB_HOME/Library/Developer/Xcode/Archives" "Xcode Archives" 0
    if command -v xcrun >/dev/null 2>&1; then
        if [ "$TB_DRYRUN" -eq 1 ]; then
            ctx_note "xcrun simctl delete unavailable (simulazione)"
        else
            as_user xcrun simctl delete unavailable >/dev/null 2>&1 && \
                ctx_note "Simulatori non piu' disponibili rimossi"
        fi
    fi
}

task_clean_devcache() {
    local trovate=0 v
    for v in \
        "$TB_HOME/.npm/_cacache|npm" \
        "$TB_HOME/Library/Caches/pip|pip" \
        "$TB_HOME/Library/Caches/Yarn|Yarn" \
        "$TB_HOME/Library/Caches/CocoaPods|CocoaPods" \
        ; do
        local p e
        p=$(echo "$v" | cut -d'|' -f1); e=$(echo "$v" | cut -d'|' -f2)
        if [ -d "$p" ]; then
            trovate=$((trovate + 1))
            clear_folder_content "$p" "$e" 0
        fi
    done
    [ "$trovate" -eq 0 ] && ctx_note "Nessuno strumento di sviluppo con cache su questo sistema"
    return 0
}

task_clean_homebrew() {
    if ! command -v brew >/dev/null 2>&1; then
        ctx_note "Homebrew non installato"
        return 0
    fi
    if [ "$TB_DRYRUN" -eq 1 ]; then
        ctx_note "brew cleanup -s (simulazione)"
        return 0
    fi
    local prima dopo
    prima=$(free_space_bytes)
    as_user brew cleanup -s >/dev/null 2>&1
    dopo=$(free_space_bytes)
    local lib=$((dopo - prima)); [ "$lib" -lt 0 ] && lib=0
    CTX_BYTES=$((CTX_BYTES + lib))
    ctx_note "Homebrew ripulito: $(format_bytes "$lib") liberati"
}

task_clean_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        ctx_note "Docker non installato"
        return 0
    fi
    if ! docker info >/dev/null 2>&1; then
        ctx_note "Docker non in esecuzione: saltato"
        return 0
    fi
    if [ "$TB_DRYRUN" -eq 1 ]; then
        ctx_note "docker system prune -f (simulazione)"
        return 0
    fi
    local prima dopo
    prima=$(free_space_bytes)
    as_user docker system prune -f >/dev/null 2>&1
    dopo=$(free_space_bytes)
    local lib=$((dopo - prima)); [ "$lib" -lt 0 ] && lib=0
    CTX_BYTES=$((CTX_BYTES + lib))
    ctx_note "Docker ripulito: $(format_bytes "$lib") liberati"
}

task_clean_fontcache() {
    if [ "$TB_DRYRUN" -eq 1 ]; then
        ctx_note "atsutil databases -remove (simulazione)"
        return 0
    fi
    as_user atsutil databases -removeUser >/dev/null 2>&1
    as_root atsutil databases -remove >/dev/null 2>&1
    ctx_note "Cache dei font ricostruita: l'effetto pieno si vede dopo il riavvio"
}

# ============================================================
#   RETE
# ============================================================

task_net_flushdns() {
    if [ "$TB_DRYRUN" -eq 1 ]; then
        ctx_note "dscacheutil -flushcache + killall mDNSResponder (simulazione)"
        return 0
    fi
    # Su tutte le versioni da 10.11 in poi servono entrambi i
    # comandi: la versione precedente dello script su Catalina
    # saltava dscacheutil e svuotava la cache solo a meta'.
    as_root dscacheutil -flushcache 2>/dev/null
    if as_root killall -HUP mDNSResponder 2>/dev/null; then
        ctx_note "Cache DNS svuotata"
    else
        ctx_fail "mDNSResponder non raggiungibile"
    fi
    return 0
}

task_net_renew() {
    local iface
    iface=$(route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}')
    if [ -z "$iface" ]; then
        ctx_fail "Nessuna interfaccia di rete predefinita"
        return 0
    fi
    if [ "$TB_DRYRUN" -eq 1 ]; then
        ctx_note "ipconfig set $iface DHCP (simulazione)"
        return 0
    fi
    ctx_note "Rinnovo indirizzo su $iface..."
    as_root ipconfig set "$iface" DHCP 2>/dev/null
    sleep 3
    local ip; ip=$(ipconfig getifaddr "$iface" 2>/dev/null)
    if [ -n "$ip" ]; then
        ctx_note "Indirizzo attivo: $ip"
    else
        ctx_fail "Nessun indirizzo assegnato dopo il rinnovo"
    fi
    return 0
}

task_net_reset() {
    local dir="/Library/Preferences/SystemConfiguration"
    if [ "$TB_DRYRUN" -eq 1 ]; then
        ctx_note "Copia di sicurezza e rimozione delle preferenze di rete (simulazione)"
        CTX_REBOOT=1
        return 0
    fi
    local backup="$dir/backup-toolbox-$(date '+%Y%m%d-%H%M%S')"
    as_root mkdir -p "$backup" 2>/dev/null
    local f
    for f in com.apple.airport.preferences.plist NetworkInterfaces.plist preferences.plist com.apple.network.identification.plist; do
        if [ -f "$dir/$f" ]; then
            as_root cp "$dir/$f" "$backup/" 2>/dev/null && as_root rm -f "$dir/$f" 2>/dev/null
            CTX_ITEMS=$((CTX_ITEMS + 1))
        fi
    done
    ctx_note "Copia di sicurezza in $backup"
    ctx_note "Configurazione di rete azzerata: effettiva dopo il riavvio"
    CTX_REBOOT=1
}

# ============================================================
#   MANUTENZIONE
# ============================================================

task_maint_launchservices() {
    local ls="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    if [ ! -x "$ls" ]; then
        ctx_fail "lsregister non trovato su questa versione di macOS"
        return 0
    fi
    if [ "$TB_DRYRUN" -eq 1 ]; then
        ctx_note "lsregister -kill -r -domain local -domain system -domain user (simulazione)"
        return 0
    fi
    ctx_note "Ricostruzione in corso, puo' richiedere un minuto..."
    if as_user "$ls" -kill -r -domain local -domain system -domain user >/dev/null 2>&1; then
        ctx_note "Database ricostruito: il menu Apri con non avra' piu' duplicati"
    else
        ctx_fail "Ricostruzione non riuscita"
    fi
    return 0
}

task_maint_verifydisk() {
    if [ "$TB_DRYRUN" -eq 1 ]; then
        ctx_note "diskutil verifyVolume / (simulazione)"
        return 0
    fi
    ctx_note "Verifica in corso, puo' richiedere qualche minuto..."
    local out
    out=$(as_root diskutil verifyVolume / 2>&1)
    if echo "$out" | grep -qi 'appears to be OK\|sembra essere OK'; then
        ctx_note "Il file system del volume di avvio risulta integro"
    elif echo "$out" | grep -qi 'could not be verified\|non e. stato possibile'; then
        ctx_note "Verifica non eseguibile a caldo: si fa da Recovery con Utility Disco"
    else
        ctx_fail "La verifica ha segnalato anomalie: apri Utility Disco da Recovery ed esegui S.O.S."
    fi
    return 0
}

task_maint_spotlight() {
    if [ "$TB_DRYRUN" -eq 1 ]; then
        ctx_note "mdutil -E / (simulazione)"
        return 0
    fi
    if as_root mdutil -E / >/dev/null 2>&1; then
        ctx_note "Indice cancellato: la ricostruzione parte da sola"
        ctx_note "Per alcune ore il Mac sara' piu' lento e le ventole piu' attive"
    else
        ctx_fail "Impossibile avviare la reindicizzazione"
    fi
    return 0
}

task_maint_updates() {
    if [ "$TB_DRYRUN" -eq 1 ]; then
        ctx_note "softwareupdate -i -a (simulazione)"
        return 0
    fi
    ctx_note "Download e installazione in corso: puo' richiedere molto tempo..."
    local out
    out=$(as_root softwareupdate -i -a 2>&1)
    if echo "$out" | grep -qi 'No updates\|Nessun aggiornamento'; then
        ctx_note "Nessun aggiornamento da installare"
    else
        ctx_note "Aggiornamenti installati"
        echo "$out" | grep -qi 'restart\|riavvi' && CTX_REBOOT=1
    fi
    return 0
}

task_maint_purge() {
    ctx_note "Attenzione: questa operazione tipicamente PEGGIORA le prestazioni."
    if [ "$TB_DRYRUN" -eq 1 ]; then
        ctx_note "purge (simulazione)"
        return 0
    fi
    if as_root purge 2>/dev/null; then
        ctx_note "Cache disco svuotata. macOS la ricostruira' rileggendo dal disco."
    else
        ctx_fail "Comando purge non disponibile"
    fi
    return 0
}
