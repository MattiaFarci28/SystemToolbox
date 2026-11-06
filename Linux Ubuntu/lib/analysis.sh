#!/bin/bash
# ============================================================
#   analysis.sh - Raccolta dati e rendering (Linux / Ubuntu)
#
#   Nessuna funzione qui dentro modifica lo stato del sistema.
#
#   Funziona sia su Ubuntu reale sia dentro WSL: cio' che in WSL
#   non ha senso (temperature, SMART, kernel, boot) viene
#   dichiarato non applicabile invece di produrre falsi allarmi.
# ============================================================

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
#   CICLO DI VITA DI UBUNTU
#   Le LTS hanno 5 anni di supporto standard, le intermedie 9
#   mesi. Dopo il supporto standard le LTS proseguono con ESM,
#   che pero' richiede un abbonamento Ubuntu Pro.
#   Tabella da AGGIORNARE: le versioni non presenti vengono
#   dichiarate sconosciute invece che date per supportate.
# ============================================================
ubuntu_eol() {
    case "$1" in
        18.04) echo "2023-05-31|LTS" ;;
        20.04) echo "2025-05-31|LTS" ;;
        22.04) echo "2027-06-01|LTS" ;;
        24.04) echo "2029-05-31|LTS" ;;
        26.04) echo "2031-05-31|LTS" ;;
        24.10) echo "2025-07-31|intermedia" ;;
        25.04) echo "2026-01-31|intermedia" ;;
        25.10) echo "2026-07-31|intermedia" ;;
        *)     echo "" ;;
    esac
}

giorni_da_oggi() {
    local t; t=$(date -d "$1" +%s 2>/dev/null)
    [ -z "$t" ] && { echo ""; return; }
    echo $(( (t - $(date +%s)) / 86400 ))
}

show_support() {
    ui_section "SUPPORTO DELLA DISTRIBUZIONE"
    local id ver nome
    if [ -r /etc/os-release ]; then
        id=$(awk -F= '/^ID=/{gsub(/"/,"",$2); print $2}' /etc/os-release)
        ver=$(awk -F= '/^VERSION_ID=/{gsub(/"/,"",$2); print $2}' /etc/os-release)
        nome=$(awk -F= '/^PRETTY_NAME=/{gsub(/"/,"",$2); print $2}' /etc/os-release)
    fi
    ui_kv "Distribuzione" "${nome:-non identificata}"

    if [ "$id" != "ubuntu" ]; then
        ui_dim "Tabella del ciclo di vita disponibile solo per Ubuntu."
        return
    fi

    local voce scad tipo giorni
    voce=$(ubuntu_eol "$ver")
    if [ -z "$voce" ]; then
        ui_dim "Versione $ver non presente in tabella: aggiorna ubuntu_eol() in lib/analysis.sh."
        return
    fi
    scad=$(echo "$voce" | cut -d'|' -f1)
    tipo=$(echo "$voce" | cut -d'|' -f2)
    giorni=$(giorni_da_oggi "$scad")
    ui_kv "Tipo di rilascio" "$tipo"
    [ -z "$giorni" ] && return

    if [ "$giorni" -ge 0 ]; then
        local col="$C_GREEN"; [ "$giorni" -le 180 ] && col="$C_YELLOW"
        ui_kvc "Supporto standard" "$col" "fino al $scad ($giorni giorni)"
        [ "$giorni" -le 180 ] && avviso_add "Il supporto standard di Ubuntu $ver scade fra $giorni giorni: pianifica l'aggiornamento."
    else
        ui_kvc "Supporto standard" "$C_RED" "TERMINATO il $scad ($(( -giorni )) giorni fa)"
        if [ "$tipo" = "LTS" ]; then
            ui_wrap "Le LTS proseguono con ESM, ma richiede un abbonamento Ubuntu Pro. Senza, non arrivano piu' aggiornamenti di sicurezza." 3 "$C_DIM"
        fi
        avviso_add "Ubuntu $ver non riceve piu' aggiornamenti di sicurezza standard."
    fi
}

show_system() {
    ui_section "SISTEMA"
    ui_kv "Kernel" "$(uname -r)"
    ui_kv "Architettura" "$(uname -m)"
    ui_kv "Utente" "$TB_USER"
    local up giorni_acceso
    up=$(awk '{d=int($1/86400); h=int(($1%86400)/3600); m=int(($1%3600)/60); printf "%dg %dh %dm", d, h, m}' /proc/uptime 2>/dev/null)
    [ -n "$up" ] && ui_kv "Acceso da" "$up"
    # In WSL e nei container l'accensione e' quella dell'host: un
    # riavvio suggerito qui non riavvierebbe niente di utile.
    giorni_acceso=$(awk '{print int($1/86400)}' /proc/uptime 2>/dev/null)
    if [ "$TB_VIRTUALE" -eq 0 ] && [ -n "$giorni_acceso" ] \
       && [ "$giorni_acceso" -ge "$CFG_uptime_avviso_giorni" ]; then
        ui_dim "Un riavvio periodico applica i kernel e le librerie aggiornate."
        avviso_add "Il sistema e' acceso da $giorni_acceso giorni: un riavvio applica gli aggiornamenti in sospeso."
    fi

    if [ "$TB_WSL" -eq 1 ]; then
        ui_kvc "Ambiente" "$C_YELLOW" "WSL (sottosistema Windows per Linux)"
        local wv
        wv=$(cmd.exe /c ver 2>/dev/null | tr -d '\r' | grep -oE '[0-9]+\.[0-9.]+' | head -1)
        [ -n "$wv" ] && ui_kv "Windows" "$wv"
    elif [ -n "$TB_CONTAINER" ]; then
        # Stesso vincolo di WSL: kernel, dischi e buona parte dei
        # servizi appartengono all'host. Vale la pena dirlo qui una
        # volta, invece di lasciare che ogni sezione dichiari
        # "non applicabile" senza spiegare perche'.
        ui_kvc "Ambiente" "$C_YELLOW" "container ($TB_CONTAINER)"
        ui_wrap "Kernel, dischi e servizi sono dell'host: le sezioni che li riguardano vengono saltate, e le operazioni corrispondenti non hanno effetto qui dentro." 3 "$C_DIM"
    fi
    ui_kv "Gestore pacchetti" "$TB_PKG_NOME"
    if [ "$TB_SYSTEMD" -eq 1 ]; then
        ui_kv "systemd" "attivo"
    else
        ui_kvc "systemd" "$C_YELLOW" "non attivo"
        if [ "$TB_WSL" -eq 1 ]; then
            ui_wrap "Per abilitarlo aggiungi a /etc/wsl.conf la sezione [boot] con systemd=true, poi wsl --shutdown da PowerShell." 3 "$C_DIM"
        fi
    fi
}

show_disk() {
    ui_section "SPAZIO SU DISCO"
    local righe
    if [ "$TB_WSL" -eq 1 ]; then
        # Esclusi i dischi Windows sotto /mnt e il mount dei driver
        # grafici di WSL, che non sono spazio dell'utente.
        righe=$(df -P -h -x tmpfs -x devtmpfs 2>/dev/null | \
                awk 'NR>1 && $6 !~ /^\/mnt\// && $6 !~ /^\/usr\/lib\/wsl/ && $1 !~ /^(none|rootfs)$/')
    else
        righe=$(df -P -h -x tmpfs -x devtmpfs -x squashfs 2>/dev/null | awk 'NR>1 && $1 ~ /^\/dev\//')
    fi
    if [ -z "$righe" ]; then ui_dim "Nessun filesystem rilevato."; return; fi

    echo "$righe" | while read -r dev tot usa lib pct mnt; do
        local p=${pct%\%}
        printf '   %-16.16s[%s%s%s] %3s  %s liberi su %s\n' "$mnt" \
            "$(ui_pct_color "$p")" "$(ui_bar "$p")" "$C_OFF" "$pct" "$lib" "$tot"
    done

    local pct_root
    pct_root=$(df -P / 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5); print $5}')
    if [ -n "$pct_root" ] && [ "$pct_root" -ge "$CFG_disco_critico" ]; then
        ui_err "Radice piena al ${pct_root}%: aggiornamenti e compilazioni possono fallire."
        avviso_grave "Filesystem di radice pieno al ${pct_root}%."
    elif [ -n "$pct_root" ] && [ "$pct_root" -ge "$CFG_disco_avviso" ]; then
        ui_warn "Radice al ${pct_root}%: conviene fare spazio prima che si riempia."
    fi

    if [ "$TB_WSL" -eq 1 ]; then
        ui_dim "I dischi Windows montati sotto /mnt sono esclusi di proposito."
    fi
}

show_disk_health() {
    ui_section "SALUTE DEL DISCO (SMART)"
    if [ "$TB_VIRTUALE" -eq 1 ]; then
        if [ "$TB_WSL" -eq 1 ]; then
            ui_dim "Non applicabile in WSL: il disco e' gestito da Windows."
        else
            ui_dim "Non applicabile in un container: il disco e' dell'host."
        fi
        return
    fi
    if ! command -v smartctl >/dev/null 2>&1; then
        ui_dim "smartctl non installato ($(pkg_suggerisci_installazione smartmontools))."
        return
    fi
    local d
    for d in /dev/sd? /dev/nvme?n1; do
        [ -b "$d" ] || continue
        local out stato usura err
        out=$(as_root_quiet smartctl -H -A "$d")
        stato=$(printf '%s\n' "$out" | grep -iE 'overall-health|SMART Health' | sed 's/.*: *//' | head -1)
        if [ -z "$stato" ]; then
            ui_dim "$d: stato non leggibile senza privilegi gia' disponibili"
            continue
        fi
        case "$stato" in
            *PASSED*|*OK*) ui_kvc "$d" "$C_GREEN" "$stato" ;;
            *) ui_kvc "$d" "$C_RED" "$stato"
               avviso_grave "SMART di $d riporta '$stato': fai subito un backup." ;;
        esac
        # Usura (NVMe) ed errori: settori riallocati, in attesa e
        # non correggibili (SATA), errori di integrita' (NVMe).
        usura=$(printf '%s\n' "$out" | awk -F: '/Percentage Used/{gsub(/[ %]/, "", $2); print $2; exit}')
        err=$(printf '%s\n' "$out" | awk '
            /Media and Data Integrity Errors/ { split($0, a, ":"); gsub(/[ ,]/, "", a[2]); e += a[2]; t = 1 }
            ($1 == "5" || $1 == "197" || $1 == "198") && $10 ~ /^[0-9]+$/ { e += $10; t = 1 }
            END { if (t) print e }')
        [ -n "$usura" ] && ui_dim "$d: usura ${usura}%"
        smart_mostra_andamento "$(basename "$d")" "$stato" "${usura:--}" "${err:--}"
    done
}

show_memory() {
    ui_section "MEMORIA"
    local tot usa lib pct
    tot=$(awk '/MemTotal/{print $2*1024}' /proc/meminfo)
    lib=$(awk '/MemAvailable/{print $2*1024}' /proc/meminfo)
    [ -z "$lib" ] && lib=$(awk '/MemFree/{print $2*1024}' /proc/meminfo)
    usa=$((tot - lib))
    pct=0; [ "$tot" -gt 0 ] && pct=$((usa * 100 / tot))

    printf '   %-16s[%s%s%s] %3d%%  %s in uso su %s\n' "RAM" \
        "$(ui_pct_color "$pct")" "$(ui_bar "$pct")" "$C_OFF" "$pct" \
        "$(format_bytes "$usa")" "$(format_bytes "$tot")"
    [ "$pct" -ge "$CFG_ram_critica" ] && avviso_add "Memoria quasi satura (${pct}%)."

    local st su
    st=$(awk '/SwapTotal/{print $2*1024}' /proc/meminfo)
    su=$(awk '/SwapFree/{print $2*1024}' /proc/meminfo)
    if [ -n "$st" ] && [ "$st" -gt 0 ]; then
        local used=$((st - su))
        local col="$C_GREEN"
        [ "$used" -ge $(( CFG_swap_avviso_mb * 1048576 )) ] && col="$C_RED"
        ui_kvc "Swap in uso" "$col" "$(format_bytes "$used") su $(format_bytes "$st")"
        if [ "$used" -ge $(( CFG_swap_avviso_mb * 1048576 )) ]; then
            avviso_add "Swap oltre 1 GB in uso: memoria insufficiente per il carico attuale."
        fi
    else
        ui_kv "Swap" "assente"
    fi

    if [ -e /sys/block/zram0 ]; then ui_kv "zram" "attivo"; fi
}

show_processes() {
    ui_section "PROCESSI - TOP 6 PER CPU"
    ps -eo pcpu,pmem,rss,comm --sort=-pcpu 2>/dev/null | awk 'NR>1 && NR<=7 {
        printf "   %-34.34s %6.1f %%   RAM %8.1f MB\n", $4, $1, $3/1024 }'
    ui_section "PROCESSI - TOP 6 PER MEMORIA"
    ps -eo pcpu,pmem,rss,comm --sort=-rss 2>/dev/null | awk 'NR>1 && NR<=7 {
        printf "   %-34.34s %8.1f MB   CPU %5.1f %%\n", $4, $3/1024, $1 }'
}

show_services() {
    ui_section "SERVIZI"
    if [ "$TB_SYSTEMD" -ne 1 ]; then
        ui_dim "systemd non attivo: controllo dei servizi non applicabile."
        local p
        for p in sshd cron; do
            if pgrep -x "$p" >/dev/null 2>&1; then ui_ok "[ok] $p in esecuzione"
            else ui_dim "[--] $p non in esecuzione (normale in WSL)"; fi
        done
        return
    fi

    local falliti n
    falliti=$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}' | grep '[^[:space:]]')

    # In WSL alcune unita' falliscono per forza, perche' l'hardware
    # che gestiscono non esiste: segnalarle come guasti sarebbe un
    # falso allarme ripetuto a ogni esecuzione.
    local rumore=0
    if [ "$TB_WSL" -eq 1 ]; then
        local noti='^(tpm-udev|systemd-remount-fs|e2scrub_reap|systemd-modules-load|ModemManager)'
        rumore=$(echo "$falliti" | grep -cE "$noti")
        falliti=$(echo "$falliti" | grep -vE "$noti")
    fi
    n=$(echo "$falliti" | grep -c '[^[:space:]]')

    if [ "$n" -eq 0 ]; then
        if [ "$rumore" -gt 0 ]; then
            ui_ok "Nessuna unita' rilevante in stato fallito."
            ui_dim "$rumore unita' ignorate: falliscono per forza in WSL, l'hardware non esiste."
        else
            ui_ok "Nessuna unita' di sistema in stato fallito."
        fi
    else
        ui_warn "$n unita' in stato fallito:"
        echo "$falliti" | while IFS= read -r u; do [ -n "$u" ] && ui_dim "  $u"; done
        [ "$rumore" -gt 0 ] && ui_dim "($rumore unita' strutturali di WSL ignorate)"
        avviso_add "$n unita' systemd in stato fallito: 'systemctl --failed' per i dettagli."
    fi
}

# ------------------------------------------------------------
#   Tempo di avvio: l'equivalente Linux dei programmi in avvio
#   automatico. E' la misura che dice davvero perche' il sistema
#   ci mette tanto a partire.
# ------------------------------------------------------------
show_boot() {
    ui_section "TEMPO DI AVVIO"
    if [ "$TB_VIRTUALE" -eq 1 ] || [ "$TB_SYSTEMD" -ne 1 ]; then
        ui_dim "Non applicabile: serve systemd su un sistema avviato normalmente."
        return
    fi
    # Anche questa e' raccolta in parallelo insieme a blame: sono
    # due invocazioni distinte di systemd-analyze e ognuna attende
    # la risposta del manager.
    local t
    t=$(prefetch_get sd_time 15 | head -1)
    [ -z "$t" ] && t=$(systemd-analyze time 2>/dev/null | head -1)
    [ -n "$t" ] && ui_wrap "$t" 3 ""
    echo ""
    ui_dim "Unita' piu' lente all'avvio:"
    prefetch_get sd_blame 20 | head -5 | while IFS= read -r r; do
        ui_dim "  $(echo "$r" | sed 's/^[[:space:]]*//')"
    done
}

# ------------------------------------------------------------
#   Servizi che girano con librerie ormai sostituite.
#
#   E' il caso piu' frequente di "ho aggiornato e sembra tutto a
#   posto" che a posto non e': il pacchetto nuovo e' su disco, ma
#   i processi gia' avviati hanno ancora in memoria la versione
#   vecchia, falle di sicurezza comprese, finche' non vengono
#   riavviati.
#
#   needrestart viene interrogato in sola lettura (-b, formato
#   stabile) e senza privilegi: senza root vede meno processi, e
#   in quel caso lo dichiara invece di far credere che sia tutto
#   a posto.
# ------------------------------------------------------------
show_needrestart() {
    ui_section "SERVIZI DA RIAVVIARE"
    if [ "$TB_VIRTUALE" -eq 1 ]; then
        ui_dim "Non applicabile: i servizi sono dell'host."
        return
    fi
    if ! command -v needrestart >/dev/null 2>&1; then
        ui_dim "needrestart non installato: controllo non eseguito."
        ui_wrap "Si installa con il gestore pacchetti ed e' il modo piu' diretto per sapere se un aggiornamento ha davvero avuto effetto sui processi in esecuzione." 3 "$C_DIM"
        return
    fi

    local out servizi n kernel
    out=$(prefetch_get needrestart 25)
    [ -z "$out" ] && out=$(as_root_quiet needrestart -b 2>/dev/null)
    [ -z "$out" ] && out=$(needrestart -b 2>/dev/null)
    if [ -z "$out" ]; then
        ui_dim "needrestart non ha prodotto un risultato leggibile."
        return
    fi

    # NEEDRESTART-SVC: una riga per servizio da riavviare.
    servizi=$(printf '%s\n' "$out" | awk '/^NEEDRESTART-SVC:/{print $2}')
    n=$(printf '%s' "$servizi" | grep -c '[^[:space:]]')

    # NEEDRESTART-KSTA: 0 sconosciuto, 1 aggiornato, 2 ABI
    # compatibile, 3 richiede riavvio.
    kernel=$(printf '%s\n' "$out" | awk '/^NEEDRESTART-KSTA:/{print $2}')
    case "$kernel" in
        3) ui_warn "Il kernel in esecuzione non e' quello installato: serve un riavvio."
           avviso_add "Kernel aggiornato ma non ancora in uso: e' richiesto un riavvio." ;;
        2) ui_ok "Kernel: la versione in esecuzione e' compatibile con quella installata." ;;
        1) ui_ok "Kernel: in esecuzione l'ultima versione installata." ;;
    esac

    if [ "$n" -eq 0 ]; then
        ui_ok "Nessun servizio sta usando librerie sostituite."
        return
    fi
    ui_warn "$n servizi usano ancora librerie sostituite da un aggiornamento:"
    printf '%s\n' "$servizi" | head -12 | while IFS= read -r s; do
        [ -n "$s" ] && ui_dim "  $s"
    done
    [ "$n" -gt 12 ] && ui_dim "  ... e altri $((n - 12))"
    ui_wrap "Finche' non vengono riavviati continuano a usare la versione vecchia, correzioni di sicurezza comprese. Si riavviano con 'systemctl restart NOME', oppure con un riavvio del sistema." 3 "$C_DIM"
    avviso_add "$n servizi usano librerie sostituite: vanno riavviati perche' l'aggiornamento abbia effetto."
}

show_updates() {
    ui_section "AGGIORNAMENTI"
    if [ "$CFG_analisi_aggiornamenti" = "no" ]; then
        ui_dim "Sezione disattivata nella configurazione."
        return
    fi
    if ! pkg_presente; then
        ui_dim "Nessun gestore pacchetti riconosciuto su questo sistema."
        return
    fi
    # Il conteggio arriva sempre come "totali;sicurezza", chiunque
    # sia il gestore. Il risultato resta valido per qualche ora:
    # dipende dai metadati gia' scaricati, che non cambiano da soli
    # fra due analisi ravvicinate.
    local chk tot sec eta
    chk=$(cache_leggi pkg_conta "$CFG_cache_aggiornamenti_ore")
    if [ -n "$chk" ]; then
        eta=$(cache_eta_ore pkg_conta)
        ui_dim "Risultato memorizzato ${eta:-0} ore fa: nessuna nuova interrogazione."
    else
        chk=$(prefetch_get pkg_conta 40)
        [ -z "$chk" ] && chk=$(pkg_conta_aggiornamenti)
        [ -n "$chk" ] && printf '%s\n' "$chk" | cache_scrivi pkg_conta
    fi
    tot=$(echo "$chk" | cut -d';' -f1)
    sec=$(echo "$chk" | cut -d';' -f2)
    case "$tot" in ''|*[!0-9]*) tot=0 ;; esac
    # -1 significa "questo gestore non classifica gli aggiornamenti
    # di sicurezza": va detto, non trasformato in zero.
    case "$sec" in
        -1) sec=-1 ;;
        ''|*[!0-9]*) sec=-1 ;;
    esac

    if [ "$tot" -eq 0 ]; then
        ui_ok "Nessun aggiornamento disponibile."
    else
        ui_kv "Pacchetti aggiornabili" "$tot"
        if [ "$sec" -lt 0 ]; then
            ui_kvc "Di cui di sicurezza" "$C_DIM" "$TB_PKG_NOME non distingue gli aggiornamenti di sicurezza"
        elif [ "$sec" -gt 0 ]; then
            ui_kvc "Di cui di sicurezza" "$C_RED" "$sec"
            avviso_add "$sec aggiornamenti di sicurezza in attesa."
        else
            ui_kvc "Di cui di sicurezza" "$C_GREEN" "0"
        fi
    fi

    if pkg_serve_riavvio; then
        echo ""
        if [ "$TB_WSL" -eq 1 ]; then
            ui_warn "Riavvio di WSL richiesto: da PowerShell  wsl --shutdown"
        else
            ui_err "RIAVVIO DEL SISTEMA RICHIESTO"
            [ -f /var/run/reboot-required.pkgs ] && \
                head -5 /var/run/reboot-required.pkgs | while IFS= read -r p; do ui_dim "  $p"; done
        fi
        avviso_add "E' richiesto un riavvio per completare gli aggiornamenti installati."
    fi
}

show_kernels() {
    ui_section "KERNEL INSTALLATI"
    if [ "$TB_WSL" -eq 1 ]; then
        ui_dim "In WSL il kernel e' fornito da Windows: non applicabile."
        return
    fi
    if [ -n "$TB_CONTAINER" ]; then
        ui_dim "In un container il kernel e' quello dell'host: non applicabile."
        return
    fi
    command -v dpkg >/dev/null 2>&1 || { ui_dim "Elenco dei kernel disponibile solo su sistemi Debian/Ubuntu."; return; }
    local n attuale
    attuale=$(uname -r)
    n=$(dpkg -l 'linux-image-[0-9]*' 2>/dev/null | grep -c '^ii')
    ui_kv "In uso" "$attuale"
    ui_kv "Installati" "$n"
    if [ "$n" -ge 4 ]; then
        ui_warn "Molti kernel installati: occupano spazio in /boot, che e' piccolo."
        avviso_add "$n kernel installati: la pulizia avanzata rimuove quelli inutilizzati."
    fi
}

show_journal() {
    ui_section "REGISTRO DI SISTEMA"
    if [ "$TB_SYSTEMD" -ne 1 ]; then
        ui_dim "systemd non attivo: journal non applicabile."
        return
    fi
    local dim
    dim=$(journalctl --disk-usage 2>/dev/null | grep -oE '[0-9.]+[KMG]' | head -1)
    [ -n "$dim" ] && ui_kv "Spazio occupato" "$dim"

    # Errori del boot corrente, contati per unita' e non per riga:
    # una singola voce puo' occupare piu' righe e gonfiare il numero.
    local err
    err=$(journalctl -p err -b --no-pager -o short 2>/dev/null | wc -l)
    local unita
    unita=$(journalctl -p err -b --no-pager -o cat --output-fields=_SYSTEMD_UNIT 2>/dev/null | sort -u | grep -c '[^[:space:]]')
    if [ "$err" -eq 0 ]; then
        ui_ok "Nessun errore nel boot corrente."
    else
        ui_warn "$err voci di errore nel boot corrente"
        ui_dim "Dettagli:  journalctl -p err -b --no-pager"
    fi
}

show_snap() {
    ui_section "PACCHETTI SNAP"
    if ! command -v snap >/dev/null 2>&1; then
        ui_dim "Snap non installato."
        return
    fi
    if [ "$TB_WSL" -eq 1 ]; then
        ui_dim "In WSL snap e' spesso non funzionante."
    fi
    # Le revisioni superate sono l'unica parte davvero
    # recuperabile: gli snap in uso non si possono togliere. Si
    # riusa l'elenco gia' raccolto, e la dimensione si legge dai
    # singoli file .snap invece di attraversare la cartella.
    local n_vecchie
    n_vecchie=$(snap_revisioni_superate | grep -c '[^[:space:]]')
    local spazio
    spazio=$(bytes_of_files /var/lib/snapd/snaps 2>/dev/null)
    ui_kv "Spazio occupato" "$(format_bytes "${spazio:-0}")"
    if [ "$n_vecchie" -gt 0 ]; then
        ui_kvc "Revisioni vecchie" "$C_YELLOW" "$n_vecchie"
        ui_wrap "Snap conserva le versioni precedenti di ogni pacchetto. Si rimuovono dalla pulizia avanzata." 3 "$C_DIM"
        avviso_add "$n_vecchie revisioni snap superate occupano spazio."
    else
        ui_ok "Nessuna revisione superata."
    fi
}

show_temp() {
    ui_section "TEMPERATURE"
    if [ "$TB_VIRTUALE" -eq 1 ]; then
        if [ "$TB_WSL" -eq 1 ]; then
            ui_dim "Non disponibile in WSL: i sensori sono gestiti da Windows."
        else
            ui_dim "Non disponibile in un container: i sensori sono dell'host."
        fi
        return
    fi
    if command -v sensors >/dev/null 2>&1; then
        local out
        out=$(prefetch_get sensori 10)
        [ -z "$out" ] && out=$(sensors 2>/dev/null)
        printf '%s\n' "$out" | grep -E '^(Core|Package|temp)' | head -4 | while IFS= read -r r; do
            ui_dim "  $r"
        done
    else
        ui_dim "sensors non installato ($(pkg_suggerisci_installazione lm-sensors))."
    fi
}

show_firewall() {
    ui_section "FIREWALL"
    if [ "$TB_WSL" -eq 1 ]; then
        ui_dim "Gestito da Windows Defender Firewall."
        return
    fi
    if [ -n "$TB_CONTAINER" ]; then
        ui_dim "In un container le regole di rete sono dell'host: non applicabile."
        return
    fi
    if command -v ufw >/dev/null 2>&1; then
        local s
        s=$(as_root_quiet ufw status | head -1)
        case "$s" in
            '')                ui_dim "UFW: stato non leggibile senza privilegi gia' disponibili" ;;
            *inactive*|*inattivo*)
                               ui_kvc "UFW" "$C_YELLOW" "non attivo"
                               avviso_add "Firewall UFW non attivo." ;;
            *active*|*attivo*) ui_kvc "UFW" "$C_GREEN" "attivo" ;;
            *)                 ui_kv  "UFW" "$s" ;;
        esac
    else
        ui_dim "UFW non installato."
    fi
}

show_network() {
    ui_section "RETE"
    local iface ip gw
    iface=$(ip route show default 2>/dev/null | awk '/default/{print $5; exit}')
    gw=$(ip route show default 2>/dev/null | awk '/default/{print $3; exit}')
    if [ -z "$iface" ]; then ui_warn "Nessuna interfaccia predefinita."; return; fi
    ip=$(ip -4 addr show "$iface" 2>/dev/null | awk '/inet /{sub(/\/.*/,"",$2); print $2; exit}')
    ui_kv "Interfaccia" "$iface"
    ui_kv "Indirizzo IP" "${ip:-non assegnato}"
    ui_kv "Gateway" "${gw:-n/d}"
    local dns
    dns=$(resolvectl status 2>/dev/null | awk '/DNS Servers/{print $3; exit}')
    [ -z "$dns" ] && dns=$(awk '/^nameserver/{print $2; exit}' /etc/resolv.conf 2>/dev/null)
    ui_kv "Server DNS" "${dns:-n/d}"

    if [ "$1" = "completa" ]; then
        printf '   %-20s: ' "Connettivita'"
        if ping -c 2 -W 3 1.1.1.1 >/dev/null 2>&1; then printf '%sok%s\n' "$C_GREEN" "$C_OFF"
        else printf '%sNESSUNA RISPOSTA%s\n' "$C_RED" "$C_OFF"; avviso_add "Nessuna connettivita' di rete."; fi
        printf '   %-20s: ' "Risoluzione DNS"
        if getent hosts ubuntu.com >/dev/null 2>&1; then printf '%sok%s\n' "$C_GREEN" "$C_OFF"
        else printf '%sFALLITA%s\n' "$C_RED" "$C_OFF"; avviso_add "La risoluzione dei nomi non funziona."; fi
    fi
}

# ------------------------------------------------------------
#   Spazio recuperabile.
#
#   Le tre voci grosse non si misurano piu' con du:
#
#   - il journal lo dichiara systemd stesso, e journalctl
#     --disk-usage risponde in millisecondi cio' che a du costa
#     l'attraversamento di /var/log/journal;
#   - degli snap conta solo quello che si puo' davvero
#     recuperare, cioe' le revisioni disabilitate: snap list
#     --all le elenca, e ciascuna e' un singolo file .snap di cui
#     basta leggere la dimensione. Su un sistema con molti snap
#     du su /var/lib/snapd/snaps era la voce piu' lenta di tutta
#     l'analisi, e per di piu' rispondeva alla domanda sbagliata:
#     dava il totale, non il recuperabile;
#   - la cache dei pacchetti e' una cartella piatta di archivi,
#     quindi si sommano i file senza ricorrere.
#
#   Restano a du, con budget di tempo, solo le due voci nella
#   home, dove nessuno dichiara niente al posto nostro.
# ------------------------------------------------------------
riga_recuperabile() {
    local etichetta="$1" byte="$2" nota="$3" parziale="${4:-0}"
    [ "$byte" -ge 104857600 ] || return 1
    local testo; testo="$(format_bytes "$byte")"
    [ "$parziale" = "1" ] && testo="oltre $testo"
    printf '   %-40s %s%12s%s\n' "$etichetta" "$C_YELLOW" "$testo" "$C_OFF"
    ui_wrap "$nota" 5 "$C_DIM"
    return 0
}

show_recuperabile() {
    ui_section "SPAZIO RECUPERABILE"
    local trovato=0 b ris parziale

    # --- cache del gestore pacchetti: cartella piatta ---
    local cache_dir; cache_dir=$(pkg_cache_dir)
    if [ -n "$cache_dir" ] && [ -d "$cache_dir" ]; then
        b=$(bytes_of_files "$cache_dir")
        riga_recuperabile "Pacchetti scaricati ($TB_PKG_NOME)" "$b" \
            "Rimovibili dalla pulizia sicura." && trovato=1
    fi

    # --- journal: se lo dichiara systemd ---
    if [ "$TB_SYSTEMD" -eq 1 ] && command -v journalctl >/dev/null 2>&1; then
        b=$(spazio_journal)
        riga_recuperabile "Registro di sistema" "$b" \
            "Riducibile dalla pulizia sicura: si tengono gli ultimi 14 giorni." && trovato=1
    fi

    # --- snap: solo le revisioni superate, che sono il vero
    #     recuperabile. Il totale non serve a nessuno: gli snap in
    #     uso non si possono togliere.
    if command -v snap >/dev/null 2>&1; then
        local n_rev; n_rev=$(snap_revisioni_superate | grep -c '[^[:space:]]')
        if [ "$n_rev" -gt 0 ]; then
            b=$(spazio_snap_superati)
            riga_recuperabile "Revisioni snap superate ($n_rev)" "$b" \
                "Rimovibili dalla pulizia avanzata. Le versioni in uso non vengono toccate." && trovato=1
        fi
    fi

    # --- home: qui nessuno dichiara niente, si misura ---
    local voce p et no
    for voce in \
        "$TB_HOME/.cache|Cache utente|Rimovibile dalla pulizia sicura." \
        "$TB_HOME/.local/share/Trash|Cestino|Rimovibile dalla pulizia sicura." \
        ; do
        p=$(echo "$voce" | cut -d'|' -f1)
        et=$(echo "$voce" | cut -d'|' -f2)
        no=$(echo "$voce" | cut -d'|' -f3)
        [ -d "$p" ] || continue
        ris=$(bytes_of_path_limitato "$p" "$CFG_misura_max_secondi")
        b=$(echo "$ris" | cut -d'|' -f1)
        parziale=$(echo "$ris" | cut -d'|' -f2)
        riga_recuperabile "$et" "$b" "$no" "$parziale" && trovato=1
    done

    [ "$trovato" -eq 0 ] && ui_ok "Niente di rilevante oltre alla pulizia ordinaria."
}

# Dimensione del journal secondo systemd, senza attraversare
# nulla. La frase e' tradotta, quindi si estrae il primo numero
# con unita' invece di cercare "take up".
spazio_journal() {
    local out valore
    out=$(prefetch_get journal_uso 10)
    [ -z "$out" ] && out=$(journalctl --disk-usage 2>/dev/null)
    valore=$(printf '%s' "$out" | grep -oE '[0-9]+([.,][0-9]+)?[KMGT]?i?B' | head -1)
    if [ -z "$valore" ]; then
        # Nessuna risposta comprensibile: si ripiega sulla misura,
        # con budget, invece di dichiarare zero.
        bytes_of_path_limitato "/var/log/journal" "$CFG_misura_max_secondi" | cut -d'|' -f1
        return 0
    fi
    umano_in_byte "$valore"
}

# "nome|revisione" per ogni revisione snap disabilitata.
snap_revisioni_superate() {
    local out
    out=$(prefetch_get snap_all 15)
    [ -z "$out" ] && out=$(snap list --all 2>/dev/null)
    printf '%s\n' "$out" | awk '/disabled/{print $1"|"$3}'
    return 0
}

# Ogni revisione e' un singolo file .snap: basta leggerne la
# dimensione, non serve attraversare la cartella.
spazio_snap_superati() {
    local elenco="" riga nome rev f
    while IFS= read -r riga; do
        [ -z "$riga" ] && continue
        nome=${riga%%|*}
        rev=${riga#*|}
        f="/var/lib/snapd/snaps/${nome}_${rev}.snap"
        [ -f "$f" ] && elenco="$elenco $f"
    done <<FINEREV
$(snap_revisioni_superate)
FINEREV
    # shellcheck disable=SC2086
    bytes_of_files $elenco
}

# ============================================================
#   ORCHESTRAZIONE
# ============================================================
analisi() {
    local modo="${1:-completa}"
    AVVISI=""
    AVVISI_NUOVI=0
    TB_AVVISI_MODO="$modo"

    ui_title "$( [ "$modo" = "rapida" ] && echo 'Analisi rapida' || echo 'Analisi completa del sistema' )"
    log_write "--- Analisi $modo" "STEP"

    # I comandi lenti e indipendenti partono subito, tutti insieme:
    # quando la sezione che li usa arriva, il risultato e' pronto.
    # Si parallelizza la RACCOLTA, non il rendering: le sezioni
    # restano nell'ordine di sempre e l'output non si mescola.
    if [ "$modo" != "rapida" ]; then
        # Solo se la sezione e' attiva e non c'e' gia' un risultato
        # memorizzato ancora valido.
        if [ "$CFG_analisi_aggiornamenti" != "no" ] \
           && ! cache_leggi pkg_conta "$CFG_cache_aggiornamenti_ore" >/dev/null 2>&1; then
            pkg_presente && prefetch_start pkg_conta pkg_conta_aggiornamenti
        fi
        if [ "$TB_SYSTEMD" -eq 1 ] && [ "$TB_VIRTUALE" -eq 0 ]; then
            prefetch_start sd_blame systemd-analyze blame
            prefetch_start sd_time  systemd-analyze time
        fi
        [ "$TB_SYSTEMD" -eq 1 ] && command -v journalctl >/dev/null 2>&1 && \
            prefetch_start journal_uso journalctl --disk-usage
        command -v snap >/dev/null 2>&1 && \
            prefetch_start snap_all snap list --all
        command -v needrestart >/dev/null 2>&1 && [ "$TB_VIRTUALE" -eq 0 ] && \
            prefetch_start needrestart as_root_quiet needrestart -b
        command -v sensors >/dev/null 2>&1 && [ "$TB_VIRTUALE" -eq 0 ] && \
            prefetch_start sensori sensors
    fi

    show_support
    show_system
    show_disk
    show_memory
    show_processes
    show_services
    show_network "$modo"

    if [ "$modo" != "rapida" ]; then
        show_boot
        show_updates
        show_needrestart
        show_kernels
        show_journal
        show_snap
        show_disk_health
        show_temp
        show_firewall
        show_backup
        show_recuperabile
        show_grandi
    fi

    # --- confronto con l'esecuzione precedente ---
    local conf giorni delta av_allora n_avvisi giorni_txt
    n_avvisi=$(printf '%s' "$AVVISI" | grep -c '[^[:space:]]')
    conf=$(storico_confronta)
    if [ -n "$conf" ]; then
        giorni=$(echo "$conf" | cut -d'|' -f1)
        delta=$(echo "$conf" | cut -d'|' -f2)
        av_allora=$(echo "$conf" | cut -d'|' -f3)
        ui_section "RISPETTO ALL'ULTIMA VOLTA"
        if [ "$giorni" -eq 0 ]; then giorni_txt="oggi"; else giorni_txt="$giorni giorni fa"; fi
        if [ "$delta" -ge 0 ]; then
            ui_kv "Spazio libero" "$(format_bytes "$delta") in piu' rispetto a $giorni_txt"
        else
            ui_kv "Spazio libero" "$(format_bytes "$delta") rispetto a $giorni_txt"
        fi
        ui_kv "Avvisi" "$av_allora allora, $n_avvisi adesso"
    fi

    show_novita

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
    avvisi_salva "$AVVISI"
    echo ""
    ui_dim "Log della sessione: $TB_LOG"
}
# ------------------------------------------------------------
#   Andamento della salute di un disco
#   smart_mostra_andamento <disco> <stato> <usura|-> <errori|->
# ------------------------------------------------------------
smart_mostra_andamento() {
    local disco="$1" tipo testo giorni="" peggio=0
    while IFS='|' read -r tipo testo; do
        case "$tipo" in
            prima)  giorni="$testo" ;;
            peggio) peggio=1
                    ui_warn "Disco $disco: $testo"
                    avviso_add "Disco $disco: $testo rispetto a $giorni giorni fa. Fai un backup e tieni d'occhio il disco." ;;
        esac
    done <<FINEANDAMENTO
$(smart_confronto "$@")
FINEANDAMENTO
    if [ -n "$giorni" ] && [ "$peggio" -eq 0 ]; then
        ui_dim "Nessun peggioramento rispetto a $giorni giorni fa."
    fi
    return 0
}

# ------------------------------------------------------------
#   Novita' rispetto all'analisi precedente dello stesso tipo
# ------------------------------------------------------------
show_novita() {
    local f nuovi risolti
    f=$(avvisi_file) || return 0
    [ -f "$f" ] || return 0           # prima analisi: niente da confrontare
    nuovi=$(avvisi_nuovi "$AVVISI")
    risolti=$(avvisi_risolti "$AVVISI")
    AVVISI_NUOVI=$(printf '%s\n' "$nuovi" | grep -c '[^[:space:]]')
    ui_section "NOVITA' DALL'ULTIMA ANALISI"
    if [ "$AVVISI_NUOVI" -eq 0 ] && [ "$risolti" -eq 0 ]; then
        ui_ok "Nessun problema nuovo: la situazione e' la stessa."
        return 0
    fi
    if [ "$AVVISI_NUOVI" -gt 0 ]; then
        printf '%s\n' "$nuovi" | while IFS= read -r a; do
            [ -n "$a" ] && ui_warn "nuovo: $a"
        done
    fi
    [ "$risolti" -gt 0 ] && ui_ok "$risolti problemi dell'analisi precedente non ci sono piu'."
    return 0
}

# ------------------------------------------------------------
#   Cartelle e file piu' grandi della cartella personale
#   Solo da guardare: spesso lo spazio "sparito" sta in un
#   video, in una macchina virtuale o in un download dimenticato,
#   che nessuna pulizia automatica deve toccare.
# ------------------------------------------------------------
show_grandi() {
    ui_section "SPAZIO NELLA CARTELLA PERSONALE"
    ui_dim "Le cartelle e i file piu' grandi, solo da guardare: niente viene toccato."
    local sec out parz kb p
    sec=$(( CFG_misura_max_secondi * 2 ))
    out=$(grandi_cartelle "$TB_HOME" "$sec")
    parz=$(printf '%s\n' "$out" | head -1 | cut -d'|' -f2)
    printf '\n   %sCartelle%s\n' "$C_WHITE" "$C_OFF"
    printf '%s\n' "$out" | sed 1d | head -10 | while IFS=$'\t' read -r kb p; do
        [ -z "$kb" ] && continue
        printf '   %12s  %s\n' "$(format_bytes $(( kb * 1024 )))" "$(percorso_breve "$p")"
    done
    [ "$parz" = "1" ] && ui_dim "Misura interrotta dopo ${sec} secondi: i valori sono minimi."

    out=$(grandi_file "$TB_HOME" "$sec" 100)
    parz=$(printf '%s\n' "$out" | head -1 | cut -d'|' -f2)
    printf '\n   %sFile oltre 100 MB%s\n' "$C_WHITE" "$C_OFF"
    if [ -z "$(printf '%s\n' "$out" | sed 1d)" ]; then
        ui_dim "Nessuno."
    else
        printf '%s\n' "$out" | sed 1d | head -10 | while IFS=$'\t' read -r kb p; do
            [ -z "$kb" ] && continue
            printf '   %12s  %s\n' "$(format_bytes $(( kb * 1024 )))" "$(percorso_breve "$p")"
        done
    fi
    [ "$parz" = "1" ] && ui_dim "Ricerca interrotta dopo ${sec} secondi: potrebbero esserci altri file grandi."
    return 0
}

# ------------------------------------------------------------
#   Backup
#   Si cercano i due strumenti piu' diffusi: Timeshift (istantanee
#   del sistema) e Deja Dup, il "Backup" di Ubuntu (documenti).
#   Sono complementari: Timeshift di norma esclude la home.
# ------------------------------------------------------------

# backup_riga <nome> <AAAA-MM-GG o vuoto> <motivo se vuoto>
backup_riga() {
    local nome="$1" data="$2" giorni
    if [ -z "$data" ]; then
        ui_kvc "$nome" "$C_YELLOW" "$3"
        return 0
    fi
    giorni=$(giorni_da_oggi "$data")
    case "$giorni" in ''|*[!0-9-]*) ui_kv "$nome" "ultimo backup $data"; return 0 ;; esac
    giorni=$(( -giorni ))
    [ "$giorni" -lt 0 ] && giorni=0
    if [ "$giorni" -gt "$CFG_backup_avviso_giorni" ]; then
        ui_kvc "$nome" "$C_YELLOW" "ultimo backup $data ($giorni giorni fa)"
        avviso_add "L'ultimo backup di $nome e' di $giorni giorni fa."
    else
        ui_kvc "$nome" "$C_GREEN" "ultimo backup $data ($giorni giorni fa)"
    fi
    return 0
}

show_backup() {
    ui_section "BACKUP"
    if [ "$TB_VIRTUALE" -eq 1 ]; then
        ui_dim "Non applicabile qui: in WSL e nei container i dati si proteggono dal sistema che li ospita."
        return
    fi
    local trovati=0 data f b lista

    if command -v timeshift >/dev/null 2>&1; then
        trovati=$((trovati + 1))
        data=""
        lista=$(as_root_quiet timeshift --list 2>/dev/null)
        if [ -n "$lista" ]; then
            data=$(printf '%s\n' "$lista" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}' | sort | tail -1 | cut -c1-10)
            backup_riga "Timeshift" "$data" "configurato, nessuna istantanea trovata"
            [ -z "$data" ] && avviso_add "Timeshift e' installato ma non risulta nessuna istantanea."
        else
            for f in /timeshift/snapshots/*; do
                [ -d "$f" ] || continue
                b=$(basename "$f" | cut -c1-10)
                [ "$b" \> "$data" ] && data="$b"
            done
            backup_riga "Timeshift" "$data" "data dell'ultima istantanea non leggibile senza privilegi"
        fi
        ui_dim "Timeshift salva il sistema: di norma la cartella personale e' esclusa."
    fi

    if command -v gsettings >/dev/null 2>&1 \
       && gsettings list-schemas 2>/dev/null | grep -qx 'org.gnome.DejaDup'; then
        trovati=$((trovati + 1))
        data=$(as_user gsettings get org.gnome.DejaDup last-backup 2>/dev/null | tr -d "'" | cut -c1-10)
        case "$data" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;; *) data="" ;; esac
        backup_riga "Backup (Deja Dup)" "$data" "installato, nessun backup eseguito"
        [ -z "$data" ] && avviso_add "Il Backup di Ubuntu (Deja Dup) non ha mai salvato i tuoi documenti."
    fi

    if [ "$trovati" -eq 0 ]; then
        ui_warn "Nessun programma di backup rilevato."
        ui_wrap "Senza un backup, un guasto del disco fa perdere tutto. Su Ubuntu c'e' gia' \"Backup\" (Deja Dup) per i documenti; Timeshift protegge il sistema. Se usi un altro programma, ignora questo avviso." 3 "$C_DIM"
        avviso_add "Nessun backup rilevato: configura Backup (Deja Dup) per i documenti."
    fi
}

# ============================================================
#   DIAGNOSI GUIDATA
#   Si parte da un sintomo e si controlla solo cio' che lo
#   spiega, un passo alla volta. Alla fine DIAG_PROPOSTA contiene
#   l'insieme di operazioni da proporre (nome per task_set), o
#   resta vuota.
# ============================================================
DIAG_PROPOSTA=""

diagnosi_rete() {
    DIAG_PROPOSTA=""
    ui_section "INTERNET NON VA"
    [ "$TB_WSL" -eq 1 ] && diag_passo info "In WSL la rete e' quella di Windows: se qui non va, controlla prima Windows."
    local iface="" gw="" ip=""
    if command -v ip >/dev/null 2>&1; then
        gw=$(ip -4 route show default 2>/dev/null | awk '/default/{print $3; exit}')
        iface=$(ip -4 route show default 2>/dev/null | awk '/default/{for (i = 1; i < NF; i++) if ($i == "dev") { print $(i+1); exit }}')
        if [ -z "$iface" ]; then
            diag_passo ko "Nessuna connessione di rete attiva" "Controlla che il Wi-Fi sia acceso e collegato a una rete, oppure che il cavo sia inserito."
            diag_conclusione "Il computer non e' collegato a nessuna rete."
            return 0
        fi
        diag_passo ok "Collegato alla rete ($iface)"
        ip=$(ip -4 -o addr show dev "$iface" scope global 2>/dev/null | awk '{print $4; exit}' | cut -d/ -f1)
        case "$ip" in
            ''|169.254.*)
                diag_passo ko "Indirizzo IP non valido (${ip:-assente})" "Il router non ha assegnato un indirizzo. Rinnovarlo di solito risolve."
                DIAG_PROPOSTA="Rete"
                diag_conclusione "Il computer e' collegato ma non ha ricevuto un indirizzo dal router."
                return 0 ;;
        esac
        diag_passo ok "Indirizzo IP $ip"
    fi

    if ping -c 2 -W 3 1.1.1.1 >/dev/null 2>&1; then
        diag_passo ok "Internet raggiungibile"
    else
        if [ -n "$gw" ] && ping -c 2 -W 3 "$gw" >/dev/null 2>&1; then
            diag_passo ko "Il router ($gw) risponde, ma Internet no" "Riavvia il router. Se il problema resta, e' la linea: contatta il gestore."
            diag_conclusione "Il problema e' oltre il router, non nel computer."
        else
            diag_passo ko "Il router non risponde" "Il collegamento fra computer e router non funziona: avvicinati al router, riavvialo o prova con il cavo."
            diag_conclusione "Il problema e' fra il computer e il router."
        fi
        return 0
    fi

    if getent hosts www.ubuntu.com >/dev/null 2>&1; then
        diag_passo ok "Risoluzione dei nomi (DNS) funzionante"
    else
        diag_passo ko "La risoluzione dei nomi (DNS) non funziona" "Internet c'e', ma i nomi dei siti non vengono tradotti in indirizzi. Svuotare la cache DNS spesso risolve."
        DIAG_PROPOSTA="Rete"
        diag_conclusione "Problema di DNS."
        return 0
    fi

    local https=1
    if command -v curl >/dev/null 2>&1; then
        curl -sS -o /dev/null -m 10 https://www.ubuntu.com 2>/dev/null || https=0
    elif command -v wget >/dev/null 2>&1; then
        wget -q --spider -T 10 https://www.ubuntu.com 2>/dev/null || https=0
    fi
    if [ "$https" -eq 1 ]; then
        diag_passo ok "Navigazione sicura (HTTPS) funzionante"
        diag_conclusione "La connessione funziona. Se un sito in particolare non si apre, il problema e' di quel sito."
    else
        diag_passo ko "I siti sicuri (HTTPS) non si aprono" "Rete e DNS funzionano: il blocco e' probabilmente un firewall, un proxy o una VPN."
        diag_conclusione "Qualcosa blocca il traffico web: controlla VPN, proxy e firewall."
    fi
    return 0
}

diagnosi_lento() {
    DIAG_PROPOSTA=""
    ui_section "IL COMPUTER E' LENTO"
    local cause=0 tot lib pct st sf su_mb src rota carico core nome giorni

    tot=$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null)
    lib=$(awk '/MemAvailable/{print $2}' /proc/meminfo 2>/dev/null)
    case "$tot" in ''|*[!0-9]*) tot=0 ;; esac
    case "$lib" in ''|*[!0-9]*) lib=0 ;; esac
    st=$(awk '/SwapTotal/{print $2}' /proc/meminfo 2>/dev/null)
    sf=$(awk '/SwapFree/{print $2}' /proc/meminfo 2>/dev/null)
    su_mb=$(( (${st:-0} - ${sf:-0}) / 1024 ))
    pct=0; [ "$tot" -gt 0 ] && pct=$(( (tot - lib) * 100 / tot ))
    if [ "$pct" -ge "$CFG_ram_critica" ] || [ "$su_mb" -ge "$CFG_swap_avviso_mb" ]; then
        diag_passo ko "Memoria insufficiente: RAM al ${pct}%, $su_mb MB di swap in uso" "Chiudi programmi e schede del browser che non usi; se succede sempre, serve piu' RAM."
        cause=$((cause + 1))
    else
        diag_passo ok "Memoria sufficiente (RAM al ${pct}%)"
    fi

    if [ "$TB_VIRTUALE" -eq 0 ] && command -v lsblk >/dev/null 2>&1; then
        src=$(findmnt -n -o SOURCE / 2>/dev/null)
        rota=$(lsblk -dno ROTA "$src" 2>/dev/null | tr -d ' ' | head -1)
        case "$rota" in
            1) diag_passo ko "Il disco di sistema e' meccanico (HDD)" "E' la causa di lentezza piu' comune sui PC datati: sostituirlo con un SSD da' un miglioramento che nessuna pulizia puo' avvicinare."
               cause=$((cause + 1)) ;;
            0) diag_passo ok "Disco di sistema SSD" ;;
        esac
    fi

    pct=$(df -P / 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5); print $5}')
    case "$pct" in ''|*[!0-9]*) pct=0 ;; esac
    if [ "$pct" -ge "$CFG_disco_avviso" ]; then
        diag_passo ko "Disco pieno al ${pct}%" "Con poco spazio libero aggiornamenti e programmi possono rallentare o fallire. Una pulizia sicura recupera spazio senza rischi."
        DIAG_PROPOSTA="PuliziaSicura"
        cause=$((cause + 1))
    else
        diag_passo ok "Spazio su disco sufficiente (${pct}% occupato)"
    fi

    carico=$(awk '{print int($1 + 0.5)}' /proc/loadavg 2>/dev/null)
    core=$(nproc 2>/dev/null || echo 1)
    case "$carico" in ''|*[!0-9]*) carico=0 ;; esac
    if [ "$carico" -gt "$core" ]; then
        nome=$(ps -eo comm= --sort=-pcpu 2>/dev/null | head -1)
        diag_passo ko "Processore sovraccarico (carico $carico su $core core)" "Il programma che usa piu' processore e' ${nome:-sconosciuto}: se non ti serve, chiudilo."
        cause=$((cause + 1))
    else
        diag_passo ok "Processore non sovraccarico (carico $carico su $core core)"
    fi

    if [ "$TB_VIRTUALE" -eq 0 ]; then
        giorni=$(awk '{print int($1 / 86400)}' /proc/uptime 2>/dev/null)
        case "$giorni" in ''|*[!0-9]*) giorni=0 ;; esac
        if [ "$giorni" -ge "$CFG_uptime_avviso_giorni" ]; then
            diag_passo ko "Acceso da $giorni giorni" "Un riavvio libera la memoria e applica kernel e librerie aggiornati."
            cause=$((cause + 1))
        else
            diag_passo ok "Riavviato di recente ($giorni giorni fa)"
        fi
    fi

    if [ "$cause" -eq 0 ]; then
        diag_conclusione "Nessuna causa evidente. Se la lentezza riguarda un solo programma, il problema e' probabilmente di quel programma. L'analisi completa mostra anche i servizi piu' lenti all'avvio."
    else
        diag_conclusione "Trovate $cause possibili cause: parti dalla prima dell'elenco."
    fi
    return 0
}

diagnosi_disco() {
    DIAG_PROPOSTA="PuliziaSicura"
    ui_section "DISCO PIENO"
    local tot lib pct
    tot=$(df -Pk / 2>/dev/null | awk 'NR==2{print $2}')
    lib=$(df -Pk / 2>/dev/null | awk 'NR==2{print $4}')
    case "$tot" in ''|*[!0-9]*) tot=0 ;; esac
    case "$lib" in ''|*[!0-9]*) lib=0 ;; esac
    pct=0; [ "$tot" -gt 0 ] && pct=$(( (tot - lib) * 100 / tot ))
    diag_passo info "Spazio libero: $(format_bytes $(( lib * 1024 ))) su $(format_bytes $(( tot * 1024 ))) (${pct}% occupato)"
    show_recuperabile
    show_grandi
    diag_conclusione "Parti dalla pulizia sicura, che non tocca i tuoi file. Per recuperare di piu' guarda le voci qui sopra: pacchetti orfani, kernel vecchi e revisioni snap si tolgono dalla pulizia avanzata."
    return 0
}
