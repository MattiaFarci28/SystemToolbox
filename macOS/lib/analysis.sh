#!/bin/bash
# ============================================================
#   analysis.sh - Raccolta dati e rendering dell'analisi
#
#   Nessuna funzione qui dentro modifica lo stato del sistema:
#   si legge soltanto.
#
#   Nota sulla struttura: su Windows i raccoglitori restituiscono
#   oggetti e le funzioni Show-* li disegnano. In bash 3.2 non
#   esistono strutture dati restituibili, quindi qui raccolta e
#   rendering stanno nella stessa funzione show_*. Cio' che si
#   mantiene e' l'altra meta' del contratto: le show_* non
#   toccano nulla e accumulano gli avvisi in AVVISI, che la
#   sintesi finale ripropone in ordine di importanza.
# ============================================================

# ------------------------------------------------------------
#   Architettura: Apple Silicon o Intel.
#   Alcune sezioni non hanno senso su entrambe: la limitazione
#   termica via pmset esiste solo su Intel, e le estensioni del
#   kernel si interrogano in modo diverso.
# ------------------------------------------------------------
TB_ARCH=""
tb_init_arch() {
    if [ "$(uname -m)" = "arm64" ] || [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = "1" ]; then
        TB_ARCH="apple"
    else
        TB_ARCH="intel"
    fi
}

AVVISI=""
avviso_add() {
    AVVISI="${AVVISI}${1}"$'\n'
    json_avviso_add "$1"
    exit_avviso
    return 0
}
# Per le criticita' vere: alzano il codice di uscita a 2.
avviso_grave() {
    AVVISI="${AVVISI}${1}"$'\n'
    json_avviso_add "$1"
    exit_critico
    return 0
}

# ============================================================
#   CICLO DI VITA DI macOS
#
#   Apple non pubblica date ufficiali di fine supporto: la
#   regola di fatto e' che riceve aggiornamenti di sicurezza la
#   versione corrente piu' le due precedenti, quindi circa tre
#   anni. Le date qui sotto seguono quella convenzione e vanno
#   AGGIORNATE quando esce una nuova versione: le versioni non
#   in tabella vengono dichiarate sconosciute invece di essere
#   date per supportate.
# ============================================================
macos_eol() {
    case "$1" in
        10.13) echo "High Sierra|2020-12-01" ;;
        10.14) echo "Mojave|2021-10-01" ;;
        10.15) echo "Catalina|2022-09-01" ;;
        11)    echo "Big Sur|2023-09-01" ;;
        12)    echo "Monterey|2024-09-01" ;;
        13)    echo "Ventura|2025-09-01" ;;
        14)    echo "Sonoma|2026-09-01" ;;
        15)    echo "Sequoia|2027-09-01" ;;
        26)    echo "Tahoe|2028-09-01" ;;
        *)     echo "" ;;
    esac
}

# Differenza in giorni fra una data ISO e oggi. date su BSD non
# ha -d: si usa -j -f.
giorni_da_oggi() {
    local iso="$1"
    local t_target t_oggi
    t_target=$(date -j -f "%Y-%m-%d" "$iso" "+%s" 2>/dev/null)
    [ -z "$t_target" ] && { echo ""; return; }
    t_oggi=$(date "+%s")
    echo $(( (t_target - t_oggi) / 86400 ))
}

show_support() {
    ui_section "SUPPORTO DI macOS"
    local ver major nome_eol nome scad giorni
    ver=$(sw_vers -productVersion 2>/dev/null)
    case "$ver" in
        10.*) major=$(echo "$ver" | cut -d. -f1,2) ;;
        *)    major=$(echo "$ver" | cut -d. -f1) ;;
    esac

    ui_kv "Versione" "macOS $ver (build $(sw_vers -buildVersion 2>/dev/null))"

    nome_eol=$(macos_eol "$major")
    if [ -z "$nome_eol" ]; then
        ui_dim "Versione non presente nella tabella del ciclo di vita."
        ui_dim "Aggiorna macos_eol() in lib/analysis.sh se e' una versione recente."
        return
    fi
    nome=$(echo "$nome_eol" | cut -d'|' -f1)
    scad=$(echo "$nome_eol" | cut -d'|' -f2)
    giorni=$(giorni_da_oggi "$scad")
    ui_kv "Nome" "$nome"

    if [ -z "$giorni" ]; then return; fi
    if [ "$giorni" -ge 0 ]; then
        local col="$C_GREEN"; [ "$giorni" -le 120 ] && col="$C_YELLOW"
        ui_kvc "Aggiornamenti" "$col" "supportata ancora per circa $giorni giorni"
    else
        ui_kvc "Aggiornamenti" "$C_RED" "SUPPORTO TERMINATO da circa $(( -giorni )) giorni"
        ui_wrap "Questa versione non riceve piu' aggiornamenti di sicurezza regolari. Apple rilascia solo correzioni sporadiche per falle gravi." 3 "$C_DIM"
        avviso_add "macOS $nome non riceve piu' aggiornamenti di sicurezza regolari."
    fi
}

show_system() {
    ui_section "SISTEMA"
    local modello cpu core ram boot up_sec
    modello=$(sysctl -n hw.model 2>/dev/null)
    cpu=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)
    [ -z "$cpu" ] && cpu=$(sysctl -n hw.model 2>/dev/null)
    core="$(sysctl -n hw.physicalcpu 2>/dev/null) core / $(sysctl -n hw.logicalcpu 2>/dev/null) thread"
    ram=$(sysctl -n hw.memsize 2>/dev/null)

    ui_kv "Modello" "$modello"
    ui_kv "CPU" "$cpu"
    ui_kv "Core" "$core"
    ui_kv "Memoria" "$(format_bytes "${ram:-0}")"
    ui_kv "Architettura" "$(uname -m)$( [ "$TB_ARCH" = "apple" ] && echo '  (Apple Silicon)' || echo '  (Intel)' )"
    ui_kv "Utente" "$TB_USER"

    boot=$(sysctl -n kern.boottime 2>/dev/null | sed -n 's/.*sec = \([0-9]*\).*/\1/p')
    if [ -n "$boot" ]; then
        up_sec=$(( $(date +%s) - boot ))
        local g=$((up_sec / 86400)) h=$(( (up_sec % 86400) / 3600 )) m=$(( (up_sec % 3600) / 60 ))
        ui_kv "Acceso da" "${g}g ${h}h ${m}m"
        if [ "$g" -ge "$CFG_uptime_avviso_giorni" ]; then
            ui_dim "Un riavvio periodico libera memoria e applica gli aggiornamenti in sospeso."
            avviso_add "Il Mac e' acceso da $g giorni: un riavvio aiuta."
        fi
    fi
}

# ------------------------------------------------------------
#   Disco: spazio, tipo di supporto e SMART.
#   Su un Mac datato il tipo di disco e' l'informazione piu'
#   importante di tutta l'analisi.
# ------------------------------------------------------------
show_disk() {
    ui_section "DISCO"
    local tot usa lib pct
    tot=$(df -k / 2>/dev/null | awk 'NR==2{print $2}')
    usa=$(df -k / 2>/dev/null | awk 'NR==2{print $3}')
    lib=$(df -k / 2>/dev/null | awk 'NR==2{print $4}')
    tot=$((tot * 1024)); usa=$((usa * 1024)); lib=$((lib * 1024))
    pct=0
    [ "$tot" -gt 0 ] && pct=$(( usa * 100 / tot ))

    printf '   %-20s[%s%s%s] %3d%%  %s liberi su %s\n' "Volume di avvio" \
        "$(ui_pct_color "$pct")" "$(ui_bar "$pct")" "$C_OFF" "$pct" \
        "$(format_bytes "$lib")" "$(format_bytes "$tot")"

    if [ "$pct" -ge "$CFG_disco_critico" ]; then
        ui_err "Spazio quasi esaurito: sotto il 10 per cento libero macOS rallenta parecchio."
        avviso_grave "Disco pieno al ${pct}%: liberare spazio e' prioritario."
    elif [ "$pct" -ge "$CFG_disco_avviso" ]; then
        ui_warn "Sotto il 20 per cento libero conviene fare spazio."
    fi

    # Tipo di supporto: SSD, meccanico o Fusion Drive.
    # L'output di system_profiler e' stato richiesto in parallelo
    # all'inizio dell'analisi: qui di norma e' gia' pronto.
    local sp tipo fusion
    # Una sola invocazione per entrambi i tipi di dato: ognuna
    # costa un paio di secondi, e le chiavi cercate (Medium Type,
    # S.M.A.R.T., Cycle Count) appartengono a sezioni distinte.
    sp=$(prefetch_get sp_dati 40)
    [ -z "$sp" ] && sp=$(system_profiler SPStorageDataType SPPowerDataType 2>/dev/null)
    TB_SP_DATI="$sp"
    tipo=$(echo "$sp" | awk -F': ' '/Medium Type/{gsub(/^ +/,"",$2); print $2; exit}')
    fusion=$(diskutil info / 2>/dev/null | awk -F': ' '/Fusion Drive/{gsub(/^ +/,"",$2); print $2; exit}')

    if [ -n "$tipo" ]; then
        case "$tipo" in
            *SSD*|*Solid*)
                ui_kvc "Tipo di supporto" "$C_GREEN" "SSD" ;;
            *Rotational*|*HDD*)
                ui_kvc "Tipo di supporto" "$C_RED" "disco meccanico (HDD)"
                ui_wrap "E' il collo di bottiglia numero uno su un Mac datato: sostituirlo con un SSD da' un salto di prestazioni che nessuna pulizia puo' avvicinare." 3 "$C_YELLOW"
                avviso_add "Il volume di avvio e' un disco meccanico: la sostituzione con un SSD e' l'intervento con l'impatto piu' alto." ;;
            *)
                ui_kv "Tipo di supporto" "$tipo" ;;
        esac
    fi
    if [ "$fusion" = "Yes" ]; then
        ui_kv "Fusion Drive" "si (SSD + disco meccanico)"
    fi

    # SMART: prima da diskutil, poi dal riepilogo gia' raccolto.
    # Sui Mac datati il disco di avvio non e' sempre disk0.
    local smart
    smart=$(diskutil info disk0 2>/dev/null | awk -F': ' '/SMART Status/{gsub(/^ +/,"",$2); print $2; exit}')
    if [ -z "$smart" ]; then
        smart=$(echo "$sp" | awk -F': ' '/S\.M\.A\.R\.T\./{gsub(/^ +/,"",$2); print $2; exit}')
    fi
    if [ -n "$smart" ]; then
        if [ "$smart" = "Verified" ]; then
            ui_kvc "Stato SMART" "$C_GREEN" "$smart"
        else
            ui_kvc "Stato SMART" "$C_RED" "$smart"
            avviso_grave "SMART del disco riporta '$smart': fai subito un backup."
        fi
    fi
}

# ------------------------------------------------------------
#   Memoria
#   Su macOS la "RAM libera" non significa niente: il sistema
#   usa tutta la memoria disponibile come cache. Gli indicatori
#   veri sono la memoria compressa e soprattutto lo swap.
# ------------------------------------------------------------
show_memory() {
    ui_section "MEMORIA"
    local tot pagesize vms
    tot=$(sysctl -n hw.memsize 2>/dev/null)
    # Una sola lettura di vm_stat, riusata per tutti i valori.
    vms=$(vm_stat 2>/dev/null)
    pagesize=$(echo "$vms" | sed -n 's/.*page size of \([0-9]*\) bytes.*/\1/p')
    [ -z "$pagesize" ] && pagesize=4096

    local libere inattive wired compresse
    libere=$(echo "$vms"   | awk '/Pages free/{gsub(/\./,"",$3); print $3}')
    inattive=$(echo "$vms" | awk '/Pages inactive/{gsub(/\./,"",$3); print $3}')
    wired=$(echo "$vms"    | awk '/Pages wired down/{gsub(/\./,"",$4); print $4}')
    compresse=$(echo "$vms"| awk '/occupied by compressor/{gsub(/\./,"",$5); print $5}')
    for v in libere inattive wired compresse; do
        eval "[ -z \"\$$v\" ] && $v=0"
    done

    local b_lib=$(( (libere + inattive) * pagesize ))
    local b_wir=$(( wired * pagesize ))
    local b_cmp=$(( compresse * pagesize ))
    local usate=$(( tot - b_lib ))
    local pct=0
    [ "$tot" -gt 0 ] && pct=$(( usate * 100 / tot ))

    printf '   %-20s[%s%s%s] %3d%%  %s in uso su %s\n' "RAM" \
        "$(ui_pct_color "$pct")" "$(ui_bar "$pct")" "$C_OFF" "$pct" \
        "$(format_bytes "$usate")" "$(format_bytes "$tot")"
    ui_kv "Riservata al sistema" "$(format_bytes "$b_wir")"
    ui_kv "Compressa" "$(format_bytes "$b_cmp")"

    # Swap: il vero segnale di memoria insufficiente.
    local swap swap_used_mb
    swap=$(sysctl -n vm.swapusage 2>/dev/null)
    if [ -n "$swap" ]; then
        swap_used_mb=$(echo "$swap" | sed -n 's/.*used = \([0-9.]*\)M.*/\1/p')
        [ -z "$swap_used_mb" ] && swap_used_mb=0
        local intero; intero=$(printf '%.0f' "$swap_used_mb" 2>/dev/null); [ -z "$intero" ] && intero=0
        local col="$C_GREEN"
        [ "$intero" -ge "$CFG_swap_avviso_mb" ] && col="$C_RED"
        [ "$intero" -ge 256 ] && [ "$intero" -lt "$CFG_swap_avviso_mb" ] && col="$C_YELLOW"
        ui_kvc "Swap in uso" "$col" "${swap_used_mb} MB"
        if [ "$intero" -ge "$CFG_swap_avviso_mb" ]; then
            ui_wrap "Swap oltre 1 GB: il Mac sta scrivendo memoria sul disco. E' la causa piu' comune di lentezza percepita. Chiudi applicazioni o valuta piu' RAM." 3 "$C_YELLOW"
            avviso_add "Swap in uso oltre 1 GB: memoria insufficiente per il carico attuale."
        fi
    fi
    ui_dim "Su macOS la RAM libera non e' un indicatore utile: contano swap e memoria compressa."
}

show_processes() {
    ui_section "PROCESSI - TOP 6 PER CPU"
    ui_dim "La percentuale di ps su macOS e' una media decrescente sull'ultimo minuto."
    ps -A -o %cpu,%mem,rss,comm -r 2>/dev/null | awk 'NR>1 && NR<=7 {
        nome=$4; for(i=5;i<=NF;i++) nome=nome" "$i
        n=split(nome, parti, "/"); breve=parti[n]
        printf "   %-34.34s %6.1f %%   RAM %8.1f MB\n", breve, $1, $3/1024
    }'

    ui_section "PROCESSI - TOP 6 PER MEMORIA"
    ps -A -o %cpu,%mem,rss,comm -m 2>/dev/null | awk 'NR>1 && NR<=7 {
        nome=$4; for(i=5;i<=NF;i++) nome=nome" "$i
        n=split(nome, parti, "/"); breve=parti[n]
        printf "   %-34.34s %8.1f MB   CPU %5.1f %%\n", breve, $3/1024, $1
    }'
}

# ------------------------------------------------------------
#   Avvio automatico: l'equivalente macOS dei programmi in avvio.
#   Si leggono i file, senza usare System Events via osascript:
#   quello farebbe comparire una richiesta di permesso.
# ------------------------------------------------------------
show_startup() {
    ui_section "AVVIO AUTOMATICO"
    local dirs="$TB_HOME/Library/LaunchAgents /Library/LaunchAgents /Library/LaunchDaemons"
    local totale=0 d f nome
    for d in $dirs; do
        [ -d "$d" ] || continue
        local n
        n=$(ls -1 "$d"/*.plist 2>/dev/null | grep -v -c '/com\.apple\.' 2>/dev/null)
        [ -z "$n" ] && n=0
        totale=$((totale + n))
    done

    if [ "$totale" -eq 0 ]; then
        ui_ok "Nessun elemento di avvio di terze parti."
    else
        ui_kv "Elementi di terze parti" "$totale"
        for d in $dirs; do
            [ -d "$d" ] || continue
            ls -1 "$d"/*.plist 2>/dev/null | grep -v '/com\.apple\.' | head -8 | while IFS= read -r f; do
                nome=$(basename "$f" .plist)
                printf '   %-46.46s %s%s%s\n' "$nome" "$C_DIM" "$(dirname "$f")" "$C_OFF"
            done
        done
        if [ "$totale" -ge "$CFG_avvii_avviso" ]; then
            ui_warn "Molti agenti di avvio: sono la causa piu' comune di avvio lento."
            avviso_add "$totale elementi di avvio di terze parti: incidono su tempo di boot e memoria."
        fi
    fi
    ui_dim "Gli elementi di login si controllano in Preferenze di Sistema, Utenti e Gruppi."
}

# ------------------------------------------------------------
#   Snapshot locali di Time Machine
#   Su APFS sono la prima causa di spazio che "sparisce": i file
#   cancellati restano dentro lo snapshot finche' non scade.
# ------------------------------------------------------------
show_snapshots() {
    ui_section "SNAPSHOT LOCALI TIME MACHINE"
    local elenco n
    elenco=$(tmutil listlocalsnapshots / 2>/dev/null | grep -i 'com.apple.TimeMachine')
    if [ -z "$elenco" ]; then
        ui_ok "Nessuno snapshot locale presente."
        return
    fi
    n=$(echo "$elenco" | wc -l | tr -d ' ')
    ui_kvc "Snapshot presenti" "$C_YELLOW" "$n"
    echo "$elenco" | head -5 | while IFS= read -r r; do ui_dim "  $r"; done
    [ "$n" -gt 5 ] && ui_dim "  ... e altri $((n - 5))"
    ui_wrap "Trattengono lo spazio dei file cancellati finche' non scadono. Si eliminano dalla pulizia avanzata." 3 "$C_DIM"
    if [ "$n" -ge 3 ]; then
        avviso_add "$n snapshot locali di Time Machine trattengono spazio sul disco."
    fi
}

show_spotlight() {
    ui_section "SPOTLIGHT"
    local stato
    stato=$(mdutil -s / 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//')
    if [ -z "$stato" ]; then
        ui_dim "Stato non leggibile."
        return
    fi
    case "$stato" in
        *enabled*|*abilitat*) ui_kvc "Indicizzazione" "$C_GREEN" "attiva" ;;
        *disabled*|*disabilitat*)
            ui_kvc "Indicizzazione" "$C_YELLOW" "disattivata"
            ui_dim "La ricerca non trovera' i file finche' non viene riattivata." ;;
        *) ui_kv "Indicizzazione" "$stato" ;;
    esac
}

show_security() {
    ui_section "SICUREZZA"
    local sip fv gk fw
    sip=$(csrutil status 2>/dev/null | sed 's/.*: //; s/\.$//')
    if [ -n "$sip" ]; then
        case "$sip" in
            enabled*|abilitat*) ui_kvc "Protezione SIP" "$C_GREEN" "attiva" ;;
            *) ui_kvc "Protezione SIP" "$C_RED" "$sip"
               avviso_add "System Integrity Protection disattivata." ;;
        esac
    fi

    fv=$(fdesetup status 2>/dev/null | head -1)
    if [ -n "$fv" ]; then
        case "$fv" in
            *On*|*Attiv*) ui_kvc "FileVault" "$C_GREEN" "attivo" ;;
            *)            ui_kvc "FileVault" "$C_YELLOW" "non attivo" ;;
        esac
    fi

    gk=$(spctl --status 2>/dev/null)
    case "$gk" in
        *enabled*) ui_kvc "Gatekeeper" "$C_GREEN" "attivo" ;;
        *)         ui_kvc "Gatekeeper" "$C_YELLOW" "${gk:-non leggibile}" ;;
    esac

    fw=$(defaults read /Library/Preferences/com.apple.alf globalstate 2>/dev/null)
    case "$fw" in
        1|2) ui_kvc "Firewall" "$C_GREEN" "attivo" ;;
        0)   ui_kvc "Firewall" "$C_YELLOW" "disattivato"
             avviso_add "Firewall di macOS disattivato." ;;
        *)   ui_dim "Firewall: stato non leggibile" ;;
    esac
}

show_thermal() {
    ui_section "TEMPERATURA E ALIMENTAZIONE"
    local limite=""
    if [ "$TB_ARCH" = "intel" ]; then
        limite=$(pmset -g therm 2>/dev/null | awk -F= '/CPU_Speed_Limit/{gsub(/ /,"",$2); print $2}')
    else
        ui_dim "Limitazione termica: non esposta su Apple Silicon."
    fi
    if [ -n "$limite" ]; then
        if [ "$limite" -ge 100 ] 2>/dev/null; then
            ui_kvc "Velocita' CPU" "$C_GREEN" "100% (nessuna limitazione termica)"
        else
            ui_kvc "Velocita' CPU" "$C_RED" "limitata al ${limite}%"
            ui_wrap "La CPU e' rallentata per calore. Su un Mac datato di solito significa ventole o dissipatore pieni di polvere." 3 "$C_YELLOW"
            avviso_add "CPU limitata al ${limite}% per motivi termici: controlla ventole e polvere."
        fi
    elif [ "$TB_ARCH" = "intel" ]; then
        ui_dim "Nessun dato di limitazione termica disponibile."
    fi

    # Batteria: solo sui portatili.
    local batt
    batt=$(pmset -g batt 2>/dev/null | grep -c 'InternalBattery')
    if [ "$batt" -gt 0 ]; then
        # Anche qui una sola chiamata: system_profiler e' lento.
        # Riusa l'output gia' raccolto da show_disk: e' la stessa
        # invocazione di system_profiler.
        local sp_pwr cicli cond
        sp_pwr="$TB_SP_DATI"
        [ -z "$sp_pwr" ] && sp_pwr=$(system_profiler SPPowerDataType 2>/dev/null)
        cicli=$(echo "$sp_pwr" | awk -F': ' '/Cycle Count/{gsub(/ /,"",$2); print $2; exit}')
        cond=$(echo "$sp_pwr" | awk -F': ' '/Condition/{print $2; exit}')
        [ -n "$cicli" ] && ui_kv "Cicli batteria" "$cicli"
        if [ -n "$cond" ]; then
            case "$cond" in
                *Normal*) ui_kvc "Condizione batteria" "$C_GREEN" "$cond" ;;
                *) ui_kvc "Condizione batteria" "$C_YELLOW" "$cond"
                   avviso_add "Condizione della batteria: $cond." ;;
            esac
        fi
    fi
}

show_network() {
    ui_section "RETE"
    local iface ip
    iface=$(route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}')
    if [ -z "$iface" ]; then
        ui_warn "Nessuna interfaccia di rete predefinita."
        return
    fi
    ip=$(ipconfig getifaddr "$iface" 2>/dev/null)
    ui_kv "Interfaccia" "$iface"
    ui_kv "Indirizzo IP" "${ip:-non assegnato}"
    ui_kv "Router" "$(route -n get default 2>/dev/null | awk '/gateway:/{print $2; exit}')"
    local dns
    dns=$(scutil --dns 2>/dev/null | awk '/nameserver\[0\]/{print $3; exit}')
    ui_kv "Server DNS" "${dns:-non leggibile}"

    if [ "$1" = "completa" ]; then
        printf '   %-20s: ' "Connettivita'"
        if ping -c 2 -t 4 1.1.1.1 >/dev/null 2>&1; then
            printf '%sok%s\n' "$C_GREEN" "$C_OFF"
        else
            printf '%sNESSUNA RISPOSTA%s\n' "$C_RED" "$C_OFF"
            avviso_add "Nessuna risposta dalla rete: connettivita' assente."
        fi
        printf '   %-20s: ' "Risoluzione DNS"
        if host -W 4 www.apple.com >/dev/null 2>&1 || nslookup www.apple.com >/dev/null 2>&1; then
            printf '%sok%s\n' "$C_GREEN" "$C_OFF"
        else
            printf '%sFALLITA%s\n' "$C_RED" "$C_OFF"
            avviso_add "La risoluzione dei nomi non funziona: problema di DNS."
        fi
    fi
}

show_updates() {
    ui_section "AGGIORNAMENTI DI macOS"
    if [ "$CFG_analisi_aggiornamenti" = "no" ]; then
        ui_dim "Sezione disattivata nella configurazione."
        return
    fi

    # Il risultato resta valido per qualche ora: softwareupdate
    # richiede la rete e puo' impiegare un minuto e mezzo, e due
    # analisi ravvicinate non hanno motivo di ripetere l'attesa.
    local out eta
    out=$(cache_leggi softwareupdate "$CFG_cache_aggiornamenti_ore")
    if [ -n "$out" ]; then
        eta=$(cache_eta_ore softwareupdate)
        ui_dim "Risultato memorizzato ${eta:-0} ore fa: nessuna nuova interrogazione."
    else
        ui_dim "Interrogazione in corso, puo' richiedere un minuto..."
        out=$(prefetch_get softwareupdate 95)
        [ -z "$out" ] && out=$(run_timeout 90 softwareupdate -l 2>&1)
        [ -n "$out" ] && printf '%s\n' "$out" | cache_scrivi softwareupdate
    fi
    if echo "$out" | grep -qi 'No new software\|Nessun nuovo software'; then
        ui_ok "Nessun aggiornamento disponibile."
        return
    fi
    # ATTENZIONE: qui NON si puo' usare \s. grep di macOS e' BSD e
    # non conosce le classi in stile Perl: '^\s*\*' verrebbe letto
    # come "zero o piu' lettere s", il conteggio sarebbe sempre zero
    # e gli aggiornamenti non comparirebbero mai. Serve [[:space:]].
    local n
    n=$(echo "$out" | grep -c '^[[:space:]]*\*')
    if [ "$n" -gt 0 ]; then
        ui_warn "$n aggiornamenti disponibili:"
        # Il formato cambia fra Catalina ("* Nome") e le versioni
        # recenti ("* Label: Nome"): si ripuliscono entrambi.
        echo "$out" | grep '^[[:space:]]*\*' \
            | sed 's/^[[:space:]]*\*[[:space:]]*//; s/^Label:[[:space:]]*//' \
            | head -5 | while IFS= read -r r; do
                ui_dim "  $r"
            done
        avviso_add "$n aggiornamenti di macOS disponibili."
    else
        ui_dim "Nessuna informazione utilizzabile da softwareupdate."
    fi
}

# ------------------------------------------------------------
#   Spazio recuperabile che non compare altrove
# ------------------------------------------------------------
show_recuperabile() {
    ui_section "SPAZIO RECUPERABILE"
    ui_dim "Calcolo in corso, ogni voce ha un tempo massimo..."
    local trovato=0 voce p et no ris b parziale etichetta

    # Ogni misura ha un budget: du deve attraversare tutto
    # l'albero, e su un backup di iPhone da decine di GB, per di
    # piu' su un disco meccanico, puo' durare minuti.
    for voce in \
        "$TB_HOME/Library/Application Support/MobileSync/Backup|Backup di iPhone e iPad|Vengono solo segnalati. Dal menu, la voce Backup iOS permette di eliminarli scegliendo il dispositivo." \
        "$TB_HOME/Library/Developer/Xcode/DerivedData|Xcode - DerivedData|Si rigenera compilando. Rimovibile dalla pulizia avanzata." \
        "$TB_HOME/Library/Developer/CoreSimulator|Xcode - simulatori|Ogni versione di iOS scaricata occupa alcuni GB." \
        "$TB_HOME/Library/Caches|Cache utente|Rimovibile dalla pulizia avanzata." \
        "$TB_HOME/Downloads|Cartella Download|Contenuto tuo: viene solo segnalato, mai toccato." \
        ; do
        p=$(echo "$voce" | cut -d'|' -f1)
        et=$(echo "$voce" | cut -d'|' -f2)
        no=$(echo "$voce" | cut -d'|' -f3)
        [ -d "$p" ] || continue

        ris=$(bytes_of_path_limitato "$p" "$CFG_misura_max_secondi")
        b=$(echo "$ris" | cut -d'|' -f1)
        parziale=$(echo "$ris" | cut -d'|' -f2)
        [ "$b" -ge 209715200 ] || continue

        etichetta="$(format_bytes "$b")"
        [ "$parziale" = "1" ] && etichetta="oltre $etichetta"
        printf '   %-40s %s%12s%s\n' "$et" "$C_YELLOW" "$etichetta" "$C_OFF"
        [ "$parziale" = "1" ] && ui_dim "  misura interrotta dopo ${CFG_misura_max_secondi}s: il valore e' un minimo"
        ui_wrap "$no" 5 "$C_DIM"
        trovato=1
    done
    [ "$trovato" -eq 0 ] && ui_ok "Niente di rilevante oltre alla pulizia ordinaria."
}

# ============================================================
#   ORCHESTRAZIONE
# ============================================================
analisi() {
    local modo="${1:-completa}"
    AVVISI=""

    tb_init_arch
    ui_title "$( [ "$modo" = "rapida" ] && echo 'Analisi rapida' || echo 'Analisi completa del sistema' )"
    log_write "--- Analisi $modo (architettura $TB_ARCH)" "STEP"

    # I comandi lenti e indipendenti partono subito, in parallelo:
    # quando la sezione che li usa arriva, il risultato e' pronto.
    # Le sezioni restano nell'ordine di sempre, si parallelizza
    # solo la raccolta.
    prefetch_start sp_dati system_profiler SPStorageDataType SPPowerDataType
    if [ "$modo" != "rapida" ] && [ "$CFG_analisi_aggiornamenti" != "no" ]; then
        # Solo se non c'e' gia' un risultato memorizzato valido.
        if ! cache_leggi softwareupdate "$CFG_cache_aggiornamenti_ore" >/dev/null 2>&1; then
            prefetch_start softwareupdate softwareupdate -l
        fi
    fi

    show_support
    show_system
    show_disk
    show_memory
    show_processes
    show_security

    if [ "$modo" != "rapida" ]; then
        show_thermal
        show_startup
        show_snapshots
        show_spotlight
    fi

    show_network "$modo"

    if [ "$modo" != "rapida" ]; then
        show_updates
        show_recuperabile
    fi

    # --- confronto con l'esecuzione precedente ---
    local conf giorni delta av_allora n_avvisi
    n_avvisi=$(printf '%s' "$AVVISI" | grep -c '[^[:space:]]')
    conf=$(storico_confronta)
    if [ -n "$conf" ]; then
        giorni=$(echo "$conf" | cut -d'|' -f1)
        delta=$(echo "$conf" | cut -d'|' -f2)
        av_allora=$(echo "$conf" | cut -d'|' -f3)
        ui_section "RISPETTO ALL'ULTIMA VOLTA"
        [ "$giorni" -eq 0 ] && giorni_txt="oggi" || giorni_txt="$giorni giorni fa"
        if [ "$delta" -ge 0 ]; then
            ui_kv "Spazio libero" "$(format_bytes "$delta") in piu' rispetto a $giorni_txt"
        else
            ui_kv "Spazio libero" "$(format_bytes "$delta") rispetto a $giorni_txt"
        fi
        ui_kv "Avvisi" "$av_allora allora, $n_avvisi adesso"
    fi

    ui_title "Cosa merita attenzione"
    if [ -z "$(echo "$AVVISI" | tr -d '\n')" ]; then
        ui_ok "Nessuna criticita' rilevata. Il sistema risulta in ordine."
    else
        local n=1
        echo "$AVVISI" | while IFS= read -r a; do
            [ -z "$a" ] && continue
            printf '   %s%d. %s%s\n' "$C_YELLOW" "$n" "$a" "$C_OFF"
            rep_add "> [!] $a"
            log_write "AVVISO: $a" "WARN"
            n=$((n + 1))
        done
    fi

    storico_scrivi "$n_avvisi"
    echo ""
    ui_dim "Log della sessione: $TB_LOG"
}
