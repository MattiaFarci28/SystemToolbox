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
        local stato
        stato=$(as_root_quiet smartctl -H "$d" | grep -iE 'overall-health|SMART Health' | sed 's/.*: *//')
        if [ -z "$stato" ]; then
            ui_dim "$d: stato non leggibile senza privilegi gia' disponibili"
            continue
        fi
        case "$stato" in
            *PASSED*|*OK*) ui_kvc "$d" "$C_GREEN" "$stato" ;;
            *) ui_kvc "$d" "$C_RED" "$stato"
               avviso_grave "SMART di $d riporta '$stato': fai subito un backup." ;;
        esac
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
        show_recuperabile
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
