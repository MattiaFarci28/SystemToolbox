#!/bin/bash
# ============================================================
#   tasks.sh - Registro delle operazioni (Linux / Ubuntu)
#
#   Formato del registro, come nella versione macOS:
#     id|nome|categoria|livello|stima_sec|root|riavvio|descrizione
#
#   livello: sicuro | avanzato | riavvio | sconsigliato
#
#   Differenza importante rispetto al vecchio Ubuntu.sh: qui
#   NIENTE viene eseguito senza conferma. Il vecchio script
#   lanciava apt upgrade, dist-upgrade e autoremove con -y
#   appena avviato, e autoremove puo' portarsi via dei kernel.
# ============================================================

task_registry() {
cat <<'FINE'
clean_apt_cache|Cache del gestore pacchetti|Pulizia|sicuro|20|1|0|Rimuove gli archivi scaricati e gia' installati. Verranno riscaricati solo se servisse reinstallare qualcosa.
clean_journal|Riduci il registro di sistema|Pulizia|sicuro|20|1|0|Mantiene gli ultimi 14 giorni di journal ed elimina il resto. Il registro corrente non viene toccato.
clean_cache_user|Cache utente|Pulizia|sicuro|40|0|0|Svuota ~/.cache. Contiene dati rigenerabili di browser, editor e strumenti vari.
clean_thumbnails|Miniature|Pulizia|sicuro|15|0|0|Svuota la cache delle anteprime dei file. Si rigenera aprendo le cartelle.
clean_trash|Cestino|Pulizia|sicuro|15|0|0|Svuota il cestino del tuo utente.
clean_apt_autoremove|Pacchetti non piu' necessari|Pulizia|avanzato|60|1|0|Rimuove le dipendenze rimaste orfane. Puo' includere kernel vecchi: l'elenco viene mostrato prima di procedere.
clean_snap_old|Revisioni snap superate|Pulizia|avanzato|90|1|0|Snap conserva le versioni precedenti di ogni pacchetto: spesso vale diversi GB. Le versioni in uso non vengono toccate.
clean_kernels|Kernel vecchi|Pulizia|avanzato|90|1|0|Rimuove i kernel inutilizzati mantenendo quello in uso e il piu' recente. Libera /boot, che e' una partizione piccola e si riempie in fretta.
clean_flatpak|Runtime Flatpak inutilizzati|Pulizia|avanzato|60|0|0|Rimuove i runtime non piu' richiesti da nessuna applicazione.
clean_docker|Spazio di Docker|Pulizia|avanzato|90|0|0|Rimuove immagini, contenitori e volumi non utilizzati. Da eseguire solo se sai cosa hai in Docker.
clean_devcache|Cache degli strumenti di sviluppo|Pulizia|avanzato|60|0|0|Cache di npm, pip, Yarn e Gradle. Sono pacchetti riscaricabili.
net_flushdns|Svuota la cache DNS|Rete|sicuro|10|1|0|Elimina le risoluzioni memorizzate da systemd-resolved.
net_renew|Rinnova indirizzo IP|Rete|sicuro|30|1|0|Richiede di nuovo l'indirizzo al router sull'interfaccia attiva.
net_restart|Riavvia la gestione di rete|Rete|avanzato|30|1|0|Riavvia NetworkManager o systemd-networkd. La connessione cade per qualche secondo.
maint_upgrade|Aggiorna i pacchetti di sistema|Manutenzione|avanzato|600|1|0|Aggiorna cio' che si puo' aggiornare senza installare o rimuovere altro (apt upgrade, dnf upgrade, pacman -Su). L'elenco viene mostrato prima di procedere.
maint_dist_upgrade|Aggiornamento completo (dist-upgrade)|Manutenzione|avanzato|900|1|0|A differenza dell'aggiornamento normale puo' installare e rimuovere pacchetti per risolvere dipendenze nuove: e' quello che serve per i passaggi di versione del kernel. L'elenco delle rimozioni viene mostrato prima, sempre.
maint_snap_refresh|Aggiorna i pacchetti snap|Manutenzione|avanzato|300|1|0|Esegue snap refresh. Le applicazioni snap aperte vengono aggiornate alla chiusura.
maint_flatpak_update|Aggiorna le applicazioni Flatpak|Manutenzione|avanzato|300|0|0|Esegue flatpak update per le applicazioni installate.
maint_fix_broken|Ripara i pacchetti danneggiati|Manutenzione|avanzato|120|1|0|Completa le installazioni interrotte e risolve le dipendenze rotte. Da usare quando il gestore pacchetti si rifiuta di procedere.
maint_fstrim|TRIM del disco (SSD)|Manutenzione|sicuro|60|1|0|Comunica all'SSD quali blocchi non servono piu'. NON e' una deframmentazione e non consuma cicli di scrittura inutili.
maint_pam_lastlog|Correggi pam_lastlog obsoleto|Manutenzione|avanzato|10|1|0|Su Ubuntu 24.04 e successivi il modulo pam_lastlog non esiste piu' e lascia un errore a ogni accesso. Rimuove la riga facendo prima una copia di sicurezza.
FINE
}

# Il registro viene analizzato UNA volta sola e scomposto in
# variabili TB_F<campo>_<id>. Prima ogni lettura di un campo
# eseguiva "task_registry | grep | cut", cioe' tre processi, e
# veniva chiamata in ciclo per ogni task in ogni menu, elenco e
# riepilogo: era il punto piu' caldo dell'intero progetto.
# Ora la lettura e' un'espansione di variabile, senza processi.
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
            if [ "$i" -eq 8 ]; then campo="$resto"; else campo=${resto%%|*}; fi
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
# fork, ed e' quello il costo residuo. Misurato in questa
# sessione, sullo stesso identico accesso:
#
#     con $( )   18369 us
#     senza fork    160 us
#
# La misura viene da bash su Cygwin, dove il fork costa molto
# piu' che su Linux, quindi il rapporto vero su Ubuntu e' piu'
# contenuto: resta che il fork domina, e la scelta della
# struttura dati non c'entra.
#
# Per confronto, sempre misurato qui: passare a un array
# associativo di bash 4 fa scendere la lettura da 41 a 35
# microsecondi. Sei microsecondi contro migliaia, in cambio di
# perdere la compatibilita' con bash 3.2 e quindi la simmetria
# con il progetto macOS. Non vale il prezzo, e questa funzione
# ottiene molto di piu' restando compatibile con entrambi.
#
# Si usa nei cicli: i menu, gli elenchi, i riepiloghi. Altrove
# task_field resta piu' leggibile e la differenza non si vede.
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
        PuliziaSicura)   echo "clean_apt_cache clean_journal clean_cache_user clean_thumbnails clean_trash" ;;
        PuliziaAvanzata) echo "clean_apt_autoremove clean_snap_old clean_kernels clean_flatpak clean_devcache" ;;
        Rete)            echo "net_flushdns net_renew" ;;
        ReteRiavvio)     echo "net_restart" ;;
        Aggiornamenti)   echo "maint_upgrade maint_dist_upgrade maint_snap_refresh maint_flatpak_update" ;;
        Manutenzione)    echo "maint_fstrim maint_fix_broken maint_pam_lastlog" ;;
        Consigliata)     echo "clean_apt_cache clean_journal clean_cache_user clean_thumbnails clean_trash net_flushdns" ;;
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

task_serve_backup() {
    local id
    for id in $1; do
        task_campo "$id" 4
        case "$TB_CAMPO" in
            riavvio) echo "si|stai per modificare la configurazione di sistema"; return ;;
        esac
    done
    for id in $1; do
        task_campo "$id" 4
        if [ "$TB_CAMPO" = "avanzato" ]; then
            echo "si|alcune operazioni rimuovono pacchetti o modificano la configurazione"; return
        fi
    done
    echo "no|le operazioni scelte rimuovono solo file rigenerabili"
}

# Comodita': segnala e salta cio' che in WSL non ha senso.
salta_in_wsl() {
    if [ "$TB_WSL" -eq 1 ]; then
        ctx_note "$1"
        return 0
    fi
    return 1
}

# Come sopra, ma per tutto cio' che appartiene all'host: vale in
# WSL e dentro un container allo stesso modo. Il messaggio viene
# completato con l'ambiente rilevato, cosi' chi legge il log sa
# quale dei due era.
salta_se_virtuale() {
    if [ "$TB_WSL" -eq 1 ]; then
        ctx_note "In WSL $1"
        return 0
    fi
    if [ -n "$TB_CONTAINER" ]; then
        ctx_note "In un container ($TB_CONTAINER) $1"
        return 0
    fi
    return 1
}

# ============================================================
#   PULIZIA - livello sicuro
# ============================================================

task_clean_apt_cache() {
    pkg_presente || { ctx_note "Nessun gestore pacchetti riconosciuto"; return 0; }
    local dir; dir=$(pkg_cache_dir)
    [ -d "$dir" ] || { ctx_note "Cartella cache non presente: $dir"; return 0; }

    # Cartella piatta di archivi: si sommano i file, non serve
    # attraversare un albero.
    local prima; prima=$(bytes_of_files "$dir")
    if [ "$TB_DRYRUN" -eq 1 ]; then
        ctx_note "Cache $TB_PKG_NOME: $(format_bytes "$prima") eliminabili (simulazione)"
        CTX_BYTES=$((CTX_BYTES + prima))
        return 0
    fi
    pkg_pulisci_cache
    local dopo; dopo=$(bytes_of_files "$dir")
    local lib=$((prima - dopo)); [ "$lib" -lt 0 ] && lib=0
    CTX_BYTES=$((CTX_BYTES + lib))
    ctx_note "Cache $TB_PKG_NOME svuotata: $(format_bytes "$lib") liberati"
}

task_clean_journal() {
    [ "$TB_SYSTEMD" -eq 1 ] || { ctx_note "systemd non attivo: journal non presente"; return 0; }
    # La dimensione la dichiara systemd: journalctl --disk-usage
    # risponde in millisecondi cio' che a du costa attraversare
    # tutto /var/log/journal.
    local prima; prima=$(spazio_journal)
    if [ "$TB_DRYRUN" -eq 1 ]; then
        ctx_note "Journal: attualmente $(format_bytes "$prima"), verrebbero tenuti gli ultimi 14 giorni (simulazione)"
        return 0
    fi
    as_root journalctl --vacuum-time=14d >/dev/null 2>&1
    local dopo; dopo=$(spazio_journal)
    local lib=$((prima - dopo)); [ "$lib" -lt 0 ] && lib=0
    CTX_BYTES=$((CTX_BYTES + lib))
    ctx_note "Journal ridotto: $(format_bytes "$lib") liberati, ultimi 14 giorni conservati"
}

task_clean_cache_user() {
    clear_folder_content "$TB_HOME/.cache" "Cache utente" 0
}

task_clean_thumbnails() {
    clear_folder_content "$TB_HOME/.cache/thumbnails" "Miniature" 0
    clear_folder_content "$TB_HOME/.thumbnails" "Miniature (percorso storico)" 0
}

task_clean_trash() {
    clear_folder_content "$TB_HOME/.local/share/Trash/files" "Cestino - file" 0
    clear_folder_content "$TB_HOME/.local/share/Trash/info" "Cestino - metadati" 0
}

# ============================================================
#   PULIZIA - livello avanzato
# ============================================================

task_clean_apt_autoremove() {
    pkg_presente || { ctx_note "Nessun gestore pacchetti riconosciuto"; return 0; }
    # L'elenco si ricava senza privilegi: chiederli qui
    # bloccherebbe l'anteprima su una richiesta di password.
    local elenco n
    elenco=$(pkg_elenco_orfani)
    n=$(echo "$elenco" | grep -c '[^[:space:]]')
    if [ "$n" -eq 0 ]; then
        ctx_note "Nessun pacchetto orfano da rimuovere"
        return 0
    fi
    ctx_note "$n pacchetti verrebbero rimossi:"
    echo "$elenco" | head -12 | while IFS= read -r p; do [ -n "$p" ] && ctx_note "   $p"; done
    [ "$n" -gt 12 ] && ctx_note "   ... e altri $((n - 12))"

    if [ "$TB_DRYRUN" -eq 1 ]; then return 0; fi

    local prima; prima=$(free_space_bytes)
    run_con_avanzamento "Rimozione pacchetti orfani" "$n" pkg_rimuovi_orfani \
        || ctx_fail "La rimozione dei pacchetti orfani ha restituito un errore"
    local lib=$(( $(free_space_bytes) - prima )); [ "$lib" -lt 0 ] && lib=0
    CTX_BYTES=$((CTX_BYTES + lib))
    CTX_ITEMS=$((CTX_ITEMS + n))
    ctx_note "Rimossi $n pacchetti: $(format_bytes "$lib") liberati"
    return 0
}

task_clean_snap_old() {
    command -v snap >/dev/null 2>&1 || { ctx_note "Snap non installato"; return 0; }
    # Elenco gia' raccolto in parallelo all'inizio dell'analisi.
    local elenco n
    elenco=$(snap_revisioni_superate)
    n=$(echo "$elenco" | grep -c '[^[:space:]]')
    if [ "$n" -eq 0 ]; then
        ctx_note "Nessuna revisione superata"
        return 0
    fi
    if [ "$TB_DRYRUN" -eq 1 ]; then
        ctx_note "$n revisioni snap superate verrebbero rimosse (simulazione)"
        return 0
    fi
    local prima; prima=$(free_space_bytes)
    # Il ciclo gira nella shell corrente, non in una pipe: i
    # contatori devono sopravvivere all'iterazione.
    local ok=0 ko=0 riga nome rev
    for riga in $elenco; do
        nome=$(echo "$riga" | cut -d'|' -f1)
        rev=$(echo "$riga" | cut -d'|' -f2)
        # Nome e revisione arrivano dall'output di snap: si accettano
        # solo nel formato atteso, mai qualcosa che inizi con "-" e
        # possa essere letto come un'opzione.
        case "$nome" in ''|-*|*[!a-z0-9-]*) continue ;; esac
        case "$rev" in ''|*[!0-9]*) continue ;; esac
        if as_root snap remove "$nome" --revision="$rev" >/dev/null 2>&1; then
            ok=$((ok + 1))
        else
            ko=$((ko + 1))
        fi
    done
    local lib=$(( $(free_space_bytes) - prima )); [ "$lib" -lt 0 ] && lib=0
    CTX_BYTES=$((CTX_BYTES + lib))
    CTX_ITEMS=$((CTX_ITEMS + ok))
    ctx_note "$ok revisioni rimosse: $(format_bytes "$lib") liberati"
    [ "$ko" -gt 0 ] && ctx_fail "$ko revisioni non rimosse"
    return 0
}

task_clean_kernels() {
    salta_se_virtuale "il kernel e' fornito dall'host: non applicabile" && return 0
    # Una delle operazioni che NON si astrae: la convenzione
    # linux-image-<versione> e la garanzia di non toccare il
    # kernel in uso valgono su Debian e derivate. Fingere un
    # equivalente su dnf o pacman sarebbe peggio che dichiarare
    # che non c'e'.
    if [ "$TB_PKG" != "apt" ] || ! command -v dpkg >/dev/null 2>&1; then
        ctx_note "Rimozione dei kernel supportata solo su Debian e derivate (qui: $TB_PKG_NOME)"
        return 0
    fi

    local attuale installati recente da_rimuovere n
    attuale=$(uname -r | sed 's/-generic$//; s/-lowlatency$//')
    installati=$(dpkg -l 'linux-image-[0-9]*' 2>/dev/null | awk '/^ii/{print $2}' | sort -V)
    recente=$(echo "$installati" | tail -1)

    # Non si tocca mai il kernel in uso ne' il piu' recente.
    da_rimuovere=$(echo "$installati" | grep -v "$attuale" | grep -v "^${recente}$")
    n=$(echo "$da_rimuovere" | grep -c '[^[:space:]]')

    if [ "$n" -eq 0 ]; then
        ctx_note "Nessun kernel da rimuovere: restano solo quello in uso e il piu' recente"
        return 0
    fi
    ctx_note "In uso: $(uname -r)  |  piu' recente: $recente"
    echo "$da_rimuovere" | while IFS= read -r k; do [ -n "$k" ] && ctx_note "   rimuovibile: $k"; done

    if [ "$TB_DRYRUN" -eq 1 ]; then
        ctx_note "$n kernel verrebbero rimossi (simulazione)"
        return 0
    fi
    local prima; prima=$(free_space_bytes)
    # shellcheck disable=SC2086
    as_root env LC_ALL=C apt-get purge -y $(echo "$da_rimuovere" | tr '\n' ' ') >/dev/null 2>&1 || \
        ctx_fail "La rimozione di uno o piu' kernel non e' riuscita"
    local lib=$(( $(free_space_bytes) - prima )); [ "$lib" -lt 0 ] && lib=0
    CTX_BYTES=$((CTX_BYTES + lib))
    CTX_ITEMS=$((CTX_ITEMS + n))
    ctx_note "Kernel rimossi: $(format_bytes "$lib") liberati"
    return 0
}

task_clean_flatpak() {
    command -v flatpak >/dev/null 2>&1 || { ctx_note "Flatpak non installato"; return 0; }
    if [ "$TB_DRYRUN" -eq 1 ]; then
        ctx_note "flatpak uninstall --unused (simulazione)"
        return 0
    fi
    local prima; prima=$(free_space_bytes)
    as_user flatpak uninstall --unused -y >/dev/null 2>&1
    local lib=$(( $(free_space_bytes) - prima )); [ "$lib" -lt 0 ] && lib=0
    CTX_BYTES=$((CTX_BYTES + lib))
    ctx_note "Runtime inutilizzati rimossi: $(format_bytes "$lib") liberati"
}

task_clean_docker() {
    command -v docker >/dev/null 2>&1 || { ctx_note "Docker non installato"; return 0; }
    if ! docker info >/dev/null 2>&1; then
        ctx_note "Docker non in esecuzione o permessi mancanti: saltato"
        return 0
    fi
    if [ "$TB_DRYRUN" -eq 1 ]; then
        ctx_note "docker system prune -f (simulazione)"
        return 0
    fi
    local prima; prima=$(free_space_bytes)
    docker system prune -f >/dev/null 2>&1
    local lib=$(( $(free_space_bytes) - prima )); [ "$lib" -lt 0 ] && lib=0
    CTX_BYTES=$((CTX_BYTES + lib))
    ctx_note "Docker ripulito: $(format_bytes "$lib") liberati"
}

task_clean_devcache() {
    local trovate=0 v p e
    for v in \
        "$TB_HOME/.npm/_cacache|npm" \
        "$TB_HOME/.cache/pip|pip" \
        "$TB_HOME/.cache/yarn|Yarn" \
        "$TB_HOME/.gradle/caches/build-cache-1|Gradle build cache" \
        ; do
        p=$(echo "$v" | cut -d'|' -f1); e=$(echo "$v" | cut -d'|' -f2)
        if [ -d "$p" ]; then
            trovate=$((trovate + 1))
            clear_folder_content "$p" "$e" 0
        fi
    done
    [ "$trovate" -eq 0 ] && ctx_note "Nessuno strumento di sviluppo con cache su questo sistema"
    return 0
}

# ============================================================
#   RETE
# ============================================================

task_net_flushdns() {
    if [ "$TB_DRYRUN" -eq 1 ]; then ctx_note "resolvectl flush-caches (simulazione)"; return 0; fi
    if command -v resolvectl >/dev/null 2>&1; then
        as_root resolvectl flush-caches 2>/dev/null && ctx_note "Cache DNS svuotata" || \
            ctx_fail "resolvectl non ha potuto svuotare la cache"
    elif command -v systemd-resolve >/dev/null 2>&1; then
        as_root systemd-resolve --flush-caches 2>/dev/null && ctx_note "Cache DNS svuotata" || \
            ctx_fail "systemd-resolve non ha potuto svuotare la cache"
    else
        ctx_note "systemd-resolved non presente: nessuna cache DNS locale da svuotare"
    fi
    return 0
}

task_net_renew() {
    salta_se_virtuale "la rete e' gestita dall'host: non applicabile" && return 0
    local iface
    iface=$(ip route show default 2>/dev/null | awk '/default/{print $5; exit}')
    if [ -z "$iface" ]; then ctx_fail "Nessuna interfaccia predefinita"; return 0; fi
    if [ "$TB_DRYRUN" -eq 1 ]; then ctx_note "Rinnovo DHCP su $iface (simulazione)"; return 0; fi

    ctx_note "Rinnovo indirizzo su $iface..."
    if command -v nmcli >/dev/null 2>&1 && nmcli -t -f RUNNING general 2>/dev/null | grep -q running; then
        as_root nmcli device reapply "$iface" >/dev/null 2>&1 || \
            as_root nmcli device disconnect "$iface" >/dev/null 2>&1 && as_root nmcli device connect "$iface" >/dev/null 2>&1
    elif command -v dhclient >/dev/null 2>&1; then
        as_root dhclient -r "$iface" >/dev/null 2>&1
        as_root dhclient "$iface" >/dev/null 2>&1
    else
        ctx_fail "Nessuno strumento DHCP disponibile (nmcli o dhclient)"
        return 0
    fi
    sleep 3
    local ip; ip=$(ip -4 addr show "$iface" 2>/dev/null | awk '/inet /{sub(/\/.*/,"",$2); print $2; exit}')
    if [ -n "$ip" ]; then ctx_note "Indirizzo attivo: $ip"
    else ctx_fail "Nessun indirizzo assegnato dopo il rinnovo"; fi
    return 0
}

task_net_restart() {
    salta_se_virtuale "la rete e' gestita dall'host: non applicabile" && return 0
    if [ "$TB_DRYRUN" -eq 1 ]; then ctx_note "Riavvio del gestore di rete (simulazione)"; return 0; fi
    if systemctl is-active --quiet NetworkManager 2>/dev/null; then
        as_root systemctl restart NetworkManager && ctx_note "NetworkManager riavviato" || ctx_fail "Riavvio non riuscito"
    elif systemctl is-active --quiet systemd-networkd 2>/dev/null; then
        as_root systemctl restart systemd-networkd && ctx_note "systemd-networkd riavviato" || ctx_fail "Riavvio non riuscito"
    else
        ctx_note "Nessun gestore di rete attivo da riavviare"
    fi
    return 0
}

# ============================================================
#   MANUTENZIONE
# ============================================================

task_maint_upgrade() {
    pkg_presente || { ctx_note "Nessun gestore pacchetti riconosciuto"; return 0; }
    ctx_note "Aggiornamento dell'elenco pacchetti..."
    if [ "$TB_DRYRUN" -eq 0 ]; then
        pkg_aggiorna_indice || ctx_fail "L'aggiornamento dell'elenco pacchetti ha restituito un errore"
    fi
    local elenco n
    elenco=$(pkg_elenco_aggiornabili)
    n=$(echo "$elenco" | grep -c '[^[:space:]]')
    if [ "$n" -eq 0 ]; then
        ctx_note "Nessun pacchetto da aggiornare"
        return 0
    fi
    ctx_note "$n pacchetti verranno aggiornati:"
    echo "$elenco" | head -12 | while IFS= read -r p; do [ -n "$p" ] && ctx_note "   $p"; done
    [ "$n" -gt 12 ] && ctx_note "   ... e altri $((n - 12))"

    if [ "$TB_DRYRUN" -eq 1 ]; then return 0; fi

    ctx_note "Installazione in corso, puo' richiedere parecchi minuti..."
    # Ogni pacchetto produce all'incirca tre righe riconoscibili
    # (scaricamento, spacchettamento, configurazione): il totale
    # e' quindi una stima, ed e' il motivo per cui la barra si
    # ferma al 99% finche' il comando non termina davvero.
    if run_con_avanzamento "Aggiornamento" "$(( n * 3 ))" pkg_esegui_upgrade; then
        CTX_ITEMS=$((CTX_ITEMS + n))
        ctx_note "$n pacchetti aggiornati"
    else
        ctx_fail "L'aggiornamento ha restituito un errore: prova 'Ripara i pacchetti danneggiati'"
    fi
    pkg_serve_riavvio && CTX_REBOOT=1
    return 0
}

task_maint_dist_upgrade() {
    pkg_presente || { ctx_note "Nessun gestore pacchetti riconosciuto"; return 0; }
    if [ "$TB_DRYRUN" -eq 0 ]; then
        ctx_note "Aggiornamento dell'elenco pacchetti..."
        pkg_aggiorna_indice || ctx_fail "L'aggiornamento dell'elenco pacchetti ha restituito un errore"
    fi
    # Le due domande le fa il gestore, ognuna una volta sola:
    # cosa verrebbe aggiornato e cosa verrebbe rimosso.
    local inst remv n_i n_r
    inst=$(pkg_elenco_aggiornabili)
    remv=$(pkg_elenco_rimossi_completo)
    n_i=$(echo "$inst" | grep -c '[^[:space:]]')
    n_r=$(echo "$remv" | grep -c '[^[:space:]]')

    if [ "$n_i" -eq 0 ] && [ "$n_r" -eq 0 ]; then
        ctx_note "Nessun aggiornamento completo da applicare"
        return 0
    fi
    ctx_note "$n_i pacchetti da installare o aggiornare, $n_r da rimuovere"
    if [ "$n_r" -gt 0 ]; then
        # La rimozione e' la differenza vera rispetto ad apt upgrade:
        # va mostrata sempre, non nascosta dentro un -y.
        ctx_note "Verranno RIMOSSI:"
        echo "$remv" | head -12 | while IFS= read -r p; do [ -n "$p" ] && ctx_note "   $p"; done
        [ "$n_r" -gt 12 ] && ctx_note "   ... e altri $((n_r - 12))"
    fi

    if [ "$TB_DRYRUN" -eq 1 ]; then return 0; fi

    ctx_note "Installazione in corso, puo' richiedere parecchi minuti..."
    if run_con_avanzamento "Aggiornamento completo" "$(( (n_i + n_r) * 3 ))" pkg_esegui_upgrade_completo; then
        CTX_ITEMS=$((CTX_ITEMS + n_i + n_r))
        ctx_note "Aggiornamento completo eseguito"
    else
        ctx_fail "L'aggiornamento completo ha restituito un errore: prova 'Ripara i pacchetti danneggiati'"
    fi
    pkg_serve_riavvio && CTX_REBOOT=1
    return 0
}

task_maint_snap_refresh() {
    command -v snap >/dev/null 2>&1 || { ctx_note "Snap non installato"; return 0; }
    if [ "$TB_WSL" -eq 1 ]; then
        ctx_note "In WSL snap e' spesso non funzionante: se fallisce non e' un problema del sistema"
    fi
    local disponibili n
    disponibili=$(snap refresh --list 2>/dev/null | awk 'NR>1{print $1}')
    n=$(echo "$disponibili" | grep -c '[^[:space:]]')
    if [ "$n" -eq 0 ]; then
        ctx_note "Tutti gli snap sono gia' aggiornati"
        return 0
    fi
    ctx_note "$n snap da aggiornare:"
    echo "$disponibili" | head -10 | while IFS= read -r p; do [ -n "$p" ] && ctx_note "   $p"; done

    if [ "$TB_DRYRUN" -eq 1 ]; then return 0; fi

    ctx_note "Aggiornamento in corso..."
    if as_root snap refresh >/dev/null 2>&1; then
        CTX_ITEMS=$((CTX_ITEMS + n))
        ctx_note "$n snap aggiornati"
        ctx_note "Le applicazioni snap aperte si aggiornano alla chiusura"
    else
        ctx_fail "snap refresh ha restituito un errore"
    fi
    return 0
}

task_maint_flatpak_update() {
    command -v flatpak >/dev/null 2>&1 || { ctx_note "Flatpak non installato"; return 0; }
    local disponibili n
    disponibili=$(as_user flatpak remote-ls --updates --app 2>/dev/null | awk '{print $1}')
    n=$(echo "$disponibili" | grep -c '[^[:space:]]')
    if [ "$n" -eq 0 ]; then
        ctx_note "Tutte le applicazioni Flatpak sono gia' aggiornate"
        return 0
    fi
    ctx_note "$n applicazioni da aggiornare:"
    echo "$disponibili" | head -10 | while IFS= read -r p; do [ -n "$p" ] && ctx_note "   $p"; done

    if [ "$TB_DRYRUN" -eq 1 ]; then return 0; fi

    if as_user flatpak update -y >/dev/null 2>&1; then
        CTX_ITEMS=$((CTX_ITEMS + n))
        ctx_note "$n applicazioni aggiornate"
    else
        ctx_fail "flatpak update ha restituito un errore"
    fi
    return 0
}

task_maint_fix_broken() {
    pkg_presente || { ctx_note "Nessun gestore pacchetti riconosciuto"; return 0; }
    if [ "$TB_DRYRUN" -eq 1 ]; then
        ctx_note "Riparazione delle installazioni interrotte con $TB_PKG_NOME (simulazione)"
        return 0
    fi
    if pkg_ripara; then
        ctx_note "Nessuna dipendenza rotta rimasta"
    else
        ctx_fail "Restano dipendenze non risolvibili automaticamente"
    fi
    return 0
}

task_maint_fstrim() {
    salta_se_virtuale "il disco e' gestito dall'host: non applicabile" && return 0
    command -v fstrim >/dev/null 2>&1 || { ctx_fail "fstrim non disponibile"; return 0; }
    if [ "$TB_DRYRUN" -eq 1 ]; then ctx_note "fstrim -av (simulazione)"; return 0; fi
    local out
    out=$(as_root fstrim -av 2>&1)
    if [ -n "$out" ]; then
        echo "$out" | head -4 | while IFS= read -r r; do ctx_note "$r"; done
    else
        ctx_note "Nessun filesystem ha richiesto il TRIM (gia' aggiornato o non supportato)"
    fi
    return 0
}

# Versione controllata della correzione che il vecchio script
# applicava da solo, senza chiedere e senza verificare la
# versione di Ubuntu.
task_maint_pam_lastlog() {
    local file="/etc/pam.d/login"
    [ -f "$file" ] || { ctx_note "$file non presente"; return 0; }
    if ! grep -q "pam_lastlog" "$file" 2>/dev/null; then
        ctx_note "Nessun riferimento a pam_lastlog: niente da correggere"
        return 0
    fi
    # Il modulo esiste ancora fino a Ubuntu 22.04: rimuoverlo li'
    # sarebbe un danno, non una correzione.
    local ver
    ver=$(awk -F= '/^VERSION_ID=/{gsub(/"/,"",$2); print $2}' /etc/os-release 2>/dev/null)
    if [ -f /lib/x86_64-linux-gnu/security/pam_lastlog.so ] || \
       [ -f /usr/lib/x86_64-linux-gnu/security/pam_lastlog.so ]; then
        ctx_note "Il modulo pam_lastlog.so e' presente su questo sistema (Ubuntu $ver): la riga e' legittima, non la tocco"
        return 0
    fi
    if [ "$TB_DRYRUN" -eq 1 ]; then
        ctx_note "La riga pam_lastlog verrebbe rimossa da $file (simulazione)"
        return 0
    fi
    local backup="${file}.toolbox-$(date '+%Y%m%d-%H%M%S')"
    as_root cp "$file" "$backup" 2>/dev/null || { ctx_fail "Copia di sicurezza non riuscita: non procedo"; return 0; }
    as_root sed -i '/pam_lastlog/d' "$file" 2>/dev/null
    CTX_ITEMS=$((CTX_ITEMS + 1))
    ctx_note "Riga rimossa. Copia di sicurezza in $backup"
    return 0
}
