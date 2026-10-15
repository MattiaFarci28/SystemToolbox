#!/bin/bash
# ============================================================
#   common.sh - Infrastruttura condivisa
#
#   Questo file e' IDENTICO nei due progetti shell (macOS e
#   Linux), come ui.sh: contiene solo cio' che non dipende dal
#   sistema operativo. Se lo modifichi in uno, copialo
#   nell'altro.
#
#   Contiene: versione, configurazione, formattazione, codici di
#   uscita, prefetch parallelo, esportazione del report,
#   modalita' JSON e confronto con l'esecuzione precedente.
#
#   Compatibile bash 3.2 (macOS): niente array associativi,
#   niente ${var,,}, niente mapfile.
# ============================================================

TB_VERSIONE="1.0.0"

# ============================================================
#   CODICI DI USCITA
#   0 = tutto a posto
#   1 = rilevati avvisi, oppure operazioni con esito parziale
#   2 = criticita': operazione fallita o problema grave
#   Servono a chi lo lancia da uno script o da un'utilita' di
#   pianificazione, che altrimenti non ha modo di sapere com'e'
#   andata senza leggere il log.
# ============================================================
TB_EXIT=0
exit_avviso()  { [ "$TB_EXIT" -lt 1 ] && TB_EXIT=1; return 0; }
exit_critico() { TB_EXIT=2; return 0; }

# ============================================================
#   CONFIGURAZIONE
#   Le soglie erano costanti sparse nel codice. Ora hanno un
#   valore predefinito qui e si possono cambiare da file, senza
#   toccare gli script.
#
#   Il file NON viene eseguito con "source": si legge riga per
#   riga accettando solo chiavi note. Un file di configurazione
#   non deve poter eseguire comandi.
# ============================================================
CFG_disco_avviso=80
CFG_disco_critico=90
CFG_ram_critica=90
CFG_swap_avviso_mb=1024
CFG_avvii_avviso=12
CFG_uptime_avviso_giorni=7
CFG_log_da_conservare=15
CFG_colori=auto
CFG_lingua=it
CFG_cornici=ascii              # ascii | utf8
CFG_analisi_aggiornamenti=si   # si | no
CFG_cache_aggiornamenti_ore=6
CFG_misura_max_secondi=12
CFG_conferme_grafiche=no       # si = finestre di dialogo per le conferme
CFG_notifica_fine=si
CFG_ridimensiona_terminale=no
CFG_simboli=ascii              # ascii | emoji
CFG_avanzamento=si             # barra durante le operazioni lunghe

cfg_load() {
    local f="$1"
    [ -f "$f" ] || return 0
    local riga k v
    while IFS= read -r riga || [ -n "$riga" ]; do
        case "$riga" in ''|'#'*|' '*'#'*) ;; esac
        case "$riga" in ''|'#'*) continue ;; esac
        case "$riga" in *=*) ;; *) continue ;; esac
        k=${riga%%=*}
        v=${riga#*=}
        v=${v%%#*}
        # spazi ai bordi via, senza chiamare processi esterni
        while case "$k" in ' '*) k=${k# }; true;; *) false;; esac; do :; done
        while case "$k" in *' ') k=${k% }; true;; *) false;; esac; do :; done
        while case "$v" in ' '*) v=${v# }; true;; *) false;; esac; do :; done
        while case "$v" in *' ') v=${v% }; true;; *) false;; esac; do :; done

        case "$k" in
            disco_avviso|disco_critico|ram_critica|swap_avviso_mb|avvii_avviso|uptime_avviso_giorni|log_da_conservare|cache_aggiornamenti_ore|misura_max_secondi)
                case "$v" in ''|*[!0-9]*) continue ;; esac
                printf -v "CFG_$k" '%s' "$v" ;;
            colori)
                case "$v" in auto|si|no|daltonici) printf -v "CFG_$k" '%s' "$v" ;; esac ;;
            lingua)
                case "$v" in it|en) printf -v "CFG_$k" '%s' "$v" ;; esac ;;
            cornici)
                case "$v" in ascii|utf8) printf -v "CFG_$k" '%s' "$v" ;; esac ;;
            simboli)
                case "$v" in ascii|emoji) printf -v "CFG_$k" '%s' "$v" ;; esac ;;
            analisi_aggiornamenti|conferme_grafiche|notifica_fine|ridimensiona_terminale|avanzamento)
                case "$v" in si|no) printf -v "CFG_$k" '%s' "$v" ;; esac ;;
            *) : ;;   # chiave sconosciuta: ignorata di proposito
        esac
    done < "$f"
    return 0
}

# ============================================================
#   FORMATTAZIONE
#   Prima ogni chiamata avviava un processo awk. In
#   un'esecuzione completa sono centinaia di processi, e su
#   hardware datato si sentono. Qui e' tutta aritmetica di bash.
# ============================================================
format_bytes() {
    local b="${1:-0}" segno="" i f
    case "$b" in ''|*[!0-9-]*) b=0 ;; esac
    if [ "$b" -lt 0 ]; then segno="-"; b=$(( 0 - b )); fi
    if   [ "$b" -ge 1073741824 ]; then
        i=$(( b / 1073741824 )); f=$(( (b % 1073741824) * 100 / 1073741824 ))
        printf '%s%d.%02d GB\n' "$segno" "$i" "$f"
    elif [ "$b" -ge 1048576 ]; then
        i=$(( b / 1048576 ));    f=$(( (b % 1048576) * 10 / 1048576 ))
        printf '%s%d.%d MB\n' "$segno" "$i" "$f"
    elif [ "$b" -ge 1024 ]; then
        printf '%s%d KB\n' "$segno" $(( b / 1024 ))
    else
        printf '%s%d B\n' "$segno" "$b"
    fi
}

format_stima() {
    local s="${1:-0}" m a b
    case "$s" in ''|*[!0-9]*) s=0 ;; esac
    [ "$s" -le 5 ]  && { echo "immediato"; return; }
    [ "$s" -lt 60 ] && { echo "circa $s secondi"; return; }
    if [ "$s" -ge 900 ]; then
        # Sopra il quarto d'ora una forbice e' piu' onesta di un
        # numero secco: SFC, DISM e simili variano molto.
        a=$(( (s * 6 / 10 + 30) / 60 ))
        b=$(( (s * 14 / 10 + 30) / 60 ))
        echo "da $a a $b minuti"
        return
    fi
    m=$(( (s + 30) / 60 ))
    [ "$m" -le 1 ] && { echo "circa 1 minuto"; return; }
    echo "circa $m minuti"
}

format_durata() {
    local s="${1:-0}"
    case "$s" in ''|*[!0-9]*) s=0 ;; esac
    [ "$s" -lt 60 ] && { echo "${s}s"; return; }
    echo "$(( s / 60 ))m $(( s % 60 ))s"
}

# ============================================================
#   PREFETCH PARALLELO
#   I comandi lenti e indipendenti vengono avviati in
#   sottoprocessi all'inizio dell'analisi; quando la sezione
#   corrispondente arriva, il risultato e' gia' pronto.
#   Le sezioni restano in ordine: si parallelizza la raccolta,
#   non il rendering.
# ============================================================
TB_CACHE=""

# Cartella creata con mktemp: nome casuale, creazione atomica,
# accessibile solo all'utente. Con un nome prevedibile e mkdir -p
# un altro utente avrebbe potuto crearla prima, falsare i risultati
# dell'analisi o predisporre collegamenti verso file altrui.
# Se mktemp fallisce la raccolta in parallelo resta spenta: ogni
# sezione esegue il proprio comando direttamente, come prima.
prefetch_init() {
    TB_CACHE=$(mktemp -d "${TMPDIR:-/tmp}/toolbox_cache.XXXXXXXX" 2>/dev/null) || TB_CACHE=""
    return 0
}

prefetch_cleanup() {
    [ -n "$TB_CACHE" ] && [ -d "$TB_CACHE" ] && rm -rf "$TB_CACHE" 2>/dev/null
    return 0
}

# prefetch_start <chiave> <comando...>
prefetch_start() {
    [ -z "$TB_CACHE" ] && return 0
    local k="$1"; shift
    ( "$@" > "$TB_CACHE/$k.parziale" 2>/dev/null
      mv "$TB_CACHE/$k.parziale" "$TB_CACHE/$k" 2>/dev/null ) &
    return 0
}

# prefetch_get <chiave> [secondi di attesa]
# Se la chiave non e' stata avviata o scade l'attesa, non
# restituisce nulla: chi chiama deve gestire il caso vuoto.
prefetch_get() {
    local k="$1" attesa="${2:-90}" f i=0
    [ -z "$TB_CACHE" ] && return 0
    f="$TB_CACHE/$k"
    while [ ! -f "$f" ] && [ "$i" -lt $(( attesa * 10 )) ]; do
        sleep 0.1
        i=$(( i + 1 ))
    done
    [ -f "$f" ] && cat "$f"
    return 0
}

# ============================================================
#   MISURA CON BUDGET DI TEMPO
#
#   du deve attraversare tutto l'albero: su un backup di iPhone
#   da decine di GB, e a maggior ragione su un disco meccanico,
#   puo' richiedere minuti. Un'analisi che si blocca senza dire
#   niente e' peggio di un numero dichiarato come parziale.
#
#   Il trucco per avere comunque un valore utile: "du -d 1"
#   stampa una riga per ogni figlio diretto man mano che li
#   completa. Se il tempo scade, la somma dei figli gia' emessi
#   e' un limite inferiore corretto, senza doppi conteggi.
#
#   Restituisce "byte|parziale" (parziale = 1 se interrotta).
# ============================================================
bytes_of_path_limitato() {
    local p="$1" secondi="${2:-$CFG_misura_max_secondi}"
    [ -z "$secondi" ] && secondi=12
    if [ ! -e "$p" ]; then echo "0|0"; return 0; fi

    # Cartella temporanea con mktemp, per lo stesso motivo di
    # prefetch_init. Se non si riesce a crearla la misura non si fa:
    # meglio un valore dichiarato parziale che un percorso prevedibile.
    local dir_tmp tmp
    dir_tmp=$(mktemp -d "${TMPDIR:-/tmp}/tb_du.XXXXXXXX" 2>/dev/null) || { echo "0|1"; return 0; }
    tmp="$dir_tmp/du"
    ( du -k -d 1 -- "$p" > "$tmp.parziale" 2>/dev/null; mv "$tmp.parziale" "$tmp.fatto" 2>/dev/null ) &
    local pid=$!

    local i=0
    while [ ! -f "$tmp.fatto" ] && kill -0 "$pid" 2>/dev/null && [ "$i" -lt $(( secondi * 10 )) ]; do
        sleep 0.1
        i=$(( i + 1 ))
    done

    local byte=0 parziale=0
    if [ -f "$tmp.fatto" ]; then
        # L'ultima riga di du -d 1 e' il totale del percorso stesso.
        byte=$(awk -v obiettivo="$p" '$2 == obiettivo { t = $1 } END { print (t + 0) * 1024 }' "$tmp.fatto")
        [ -z "$byte" ] && byte=0
    else
        kill "$pid" 2>/dev/null
        parziale=1
        # Somma dei soli figli diretti gia' emessi: non si
        # sovrappongono fra loro, quindi e' un minimo attendibile.
        if [ -f "$tmp.parziale" ]; then
            byte=$(awk -v obiettivo="$p" '$2 != obiettivo { t += $1 } END { print (t + 0) * 1024 }' "$tmp.parziale")
        fi
        [ -z "$byte" ] && byte=0
    fi
    wait "$pid" 2>/dev/null
    rm -rf "$dir_tmp" 2>/dev/null
    echo "${byte}|${parziale}"
}

# ------------------------------------------------------------
#   Somma la dimensione di un elenco di FILE gia' noti.
#   Diversa da bytes_of_path: du su una lista di file non
#   ricorre, quindi non serve un budget di tempo. Si usa quando
#   si sa gia' quali file contano (i .snap di una revisione, i
#   pacchetti in cache) e attraversare l'albero sarebbe tempo
#   sprecato per arrivare allo stesso numero.
#   du e non stat perche' esiste identico su BSD e GNU: stat
#   vorrebbe -c su Linux e -f su macOS.
#   Passando una cartella piatta il comportamento resta utile,
#   ma li' du guarda comunque tutte le voci: va bene per una
#   cartella di archivi, non per un albero profondo.
# ------------------------------------------------------------
bytes_of_files() {
    [ "$#" -eq 0 ] && { echo 0; return 0; }
    local kb
    if [ "$#" -eq 1 ]; then
        kb=$(du -k -- "$1" 2>/dev/null | awk 'END{print $1}')
    else
        kb=$(du -k -c -- "$@" 2>/dev/null | awk 'END{print $1}')
    fi
    case "$kb" in ''|*[!0-9]*) echo 0; return 0 ;; esac
    echo $(( kb * 1024 ))
}

# ------------------------------------------------------------
#   Converte "1.1G", "512M", "4,0K" in byte.
#   Serve per i comandi che rispondono gia' in forma leggibile e
#   sarebbe assurdo rimisurare: journalctl --disk-usage risponde
#   in millisecondi cio' che a du costa l'attraversamento di
#   /var/log/journal.
#   Un solo decimale, che e' quanto quei comandi stampano; bash
#   non ha i numeri con la virgola e non serve fingere di si'.
# ------------------------------------------------------------
umano_in_byte() {
    local v="$1" num unita intero dec mult
    [ -z "$v" ] && { echo 0; return 0; }
    unita=$(printf '%s' "$v" | tr -d '0-9.,')
    num=$(printf '%s' "$v" | tr ',' '.' | tr -cd '0-9.')
    intero=${num%%.*}
    if [ "${num#*.}" = "$num" ]; then dec=0; else dec=$(printf '%s' "${num#*.}" | cut -c1); fi
    case "$intero" in ''|*[!0-9]*) intero=0 ;; esac
    case "$dec"    in ''|*[!0-9]*) dec=0 ;; esac
    case "$unita" in
        K|KB|KiB|k|kB) mult=1024 ;;
        M|MB|MiB|m)    mult=1048576 ;;
        G|GB|GiB|g)    mult=1073741824 ;;
        T|TB|TiB|t)    mult=1099511627776 ;;
        B|'')          mult=1 ;;
        *)             mult=1 ;;
    esac
    echo $(( intero * mult + dec * mult / 10 ))
}

# ============================================================
#   CACHE SU FILE
#   Per i comandi lenti che chiedono anche la rete: il risultato
#   resta valido per qualche ora, cosi' due analisi ravvicinate
#   non ripetono la stessa attesa.
# ============================================================
TB_CACHEDIR=""

cache_init() { TB_CACHEDIR="$1"; mkdir -p "$TB_CACHEDIR" 2>/dev/null; }

# cache_leggi <chiave> <ore_di_validita>
cache_leggi() {
    local k="$1" ore="${2:-6}" f
    [ -z "$TB_CACHEDIR" ] && return 1
    f="$TB_CACHEDIR/$k"
    [ -f "$f" ] || return 1
    local nato ora
    nato=$(head -1 "$f" 2>/dev/null)
    case "$nato" in ''|*[!0-9]*) return 1 ;; esac
    ora=$(date '+%s')
    [ $(( ora - nato )) -ge $(( ore * 3600 )) ] && return 1
    tail -n +2 "$f"
    return 0
}

cache_scrivi() {
    local k="$1"
    [ -z "$TB_CACHEDIR" ] && { cat > /dev/null; return 0; }
    { date '+%s'; cat; } > "$TB_CACHEDIR/$k" 2>/dev/null
    return 0
}

cache_eta_ore() {
    local k="$1" f nato
    [ -z "$TB_CACHEDIR" ] && { echo ""; return; }
    f="$TB_CACHEDIR/$k"
    [ -f "$f" ] || { echo ""; return; }
    nato=$(head -1 "$f" 2>/dev/null)
    case "$nato" in ''|*[!0-9]*) echo ""; return ;; esac
    echo $(( ( $(date '+%s') - nato ) / 3600 ))
}

# ============================================================
#   REPORT
#   Le funzioni ui_* alimentano anche questo buffer, quindi il
#   report nasce dallo stesso codice che disegna a schermo: non
#   c'e' una seconda descrizione da tenere allineata.
# ============================================================
TB_REPORT=""        # percorso del file richiesto con --report
TB_REPBUF=""

rep_add() {
    [ -z "$TB_REPORT" ] && return 0
    TB_REPBUF="${TB_REPBUF}${1}"$'\n'
    return 0
}

# Trasforma i caratteri speciali per l'HTML senza processi esterni.
html_escape() {
    local s="$1"
    s=${s//&/&amp;}
    s=${s//</&lt;}
    s=${s//>/&gt;}
    printf '%s' "$s"
}

report_write() {
    [ -z "$TB_REPORT" ] && return 0
    local dest="$TB_REPORT"
    case "$dest" in
        *.html|*.htm) report_write_html "$dest" ;;
        *)            report_write_md "$dest" ;;
    esac
}

report_write_md() {
    {
        printf '# System Toolbox - report\n\n'
        printf -- '- Versione strumento: %s\n' "$TB_VERSIONE"
        printf -- '- Data: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
        printf -- '- Sistema: %s\n' "$TB_SISTEMA"
        printf -- '- Esito: %s\n\n' "$(esito_testo)"
        printf -- '---\n\n'
        printf '%s' "$TB_REPBUF"
    } > "$1" 2>/dev/null
}

report_write_html() {
    local riga
    {
        cat <<'INTESTAZIONE'
<!doctype html>
<meta charset="utf-8">
<title>System Toolbox - report</title>
<style>
 body{font:15px/1.6 -apple-system,Segoe UI,Roboto,sans-serif;max-width:60rem;
      margin:2rem auto;padding:0 1.2rem;background:#15151a;color:#c9c9d2}
 h1{font-size:1.5rem;color:#f2f2f6;margin-bottom:.2rem}
 h2{font-size:1.05rem;color:#38d6ee;margin-top:2rem;
    border-bottom:1px solid #2c2c38;padding-bottom:.3rem}
 .meta{color:#7e7e8c;font-size:.9rem;margin-bottom:2rem}
 .kv{display:flex;gap:.6rem;padding:.15rem 0}
 .kv b{color:#9a9aa8;font-weight:600;min-width:14rem}
 .avviso{background:#3a2e12;border-left:3px solid #d9a441;
         padding:.5rem .8rem;margin:.4rem 0;border-radius:0 4px 4px 0}
 .errore{background:#3a1a1a;border-left:3px solid #f87171;
         padding:.5rem .8rem;margin:.4rem 0;border-radius:0 4px 4px 0}
 .ok{color:#4ade80}
 .nota{color:#7e7e8c;font-size:.92rem}
</style>
INTESTAZIONE
        printf '<h1>System Toolbox</h1>\n'
        printf '<div class="meta">versione %s &middot; %s &middot; %s &middot; esito: %s</div>\n' \
               "$TB_VERSIONE" "$(date '+%Y-%m-%d %H:%M')" "$(html_escape "$TB_SISTEMA")" "$(esito_testo)"
        while IFS= read -r riga; do
            case "$riga" in
                '## '*)  printf '<h2>%s</h2>\n' "$(html_escape "${riga#\#\# }")" ;;
                '- **'*) local k="${riga#- \*\*}"; k="${k%%\*\**}"
                         local v="${riga#*: }"
                         printf '<div class="kv"><b>%s</b><span>%s</span></div>\n' \
                                "$(html_escape "$k")" "$(html_escape "$v")" ;;
                '> [!] '*) printf '<div class="avviso">%s</div>\n' "$(html_escape "${riga#> [!] }")" ;;
                '> [X] '*) printf '<div class="errore">%s</div>\n' "$(html_escape "${riga#> [X] }")" ;;
                '> [ok] '*) printf '<div class="ok">%s</div>\n' "$(html_escape "${riga#> [ok] }")" ;;
                '') printf '\n' ;;
                *)  printf '<div class="nota">%s</div>\n' "$(html_escape "$riga")" ;;
            esac
        done <<FINEBUF
$TB_REPBUF
FINEBUF
    } > "$1" 2>/dev/null
}

esito_testo() {
    case "$TB_EXIT" in
        0) echo "nessuna criticita" ;;
        1) echo "avvisi presenti" ;;
        *) echo "criticita rilevate" ;;
    esac
}

# ============================================================
#   MODALITA' JSON
#   Pensata per il consumo da script: monitoraggio, confronto
#   fra due esecuzioni, raccolta su piu' macchine.
#   Non descrive ogni sezione dell'analisi, che non ha una
#   struttura dati: contiene i dati che il motore possiede
#   davvero, cioe' avvisi ed esiti delle operazioni.
# ============================================================
TB_JSON=0
TB_JSON_AVVISI=""
TB_JSON_OPS=""

json_escape() {
    local s="$1"
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//	/\\t}
    printf '%s' "$s"
}

json_op_add() {
    # id|nome|esito|byte|durata|errori
    local sep=""
    [ -n "$TB_JSON_OPS" ] && sep=","
    TB_JSON_OPS="${TB_JSON_OPS}${sep}
    {\"id\":\"$(json_escape "$1")\",\"nome\":\"$(json_escape "$2")\",\"esito\":\"$3\",\"byte_liberati\":$4,\"durata_s\":$5,\"errori\":$6}"
}

json_avviso_add() {
    local sep=""
    [ -n "$TB_JSON_AVVISI" ] && sep=","
    TB_JSON_AVVISI="${TB_JSON_AVVISI}${sep}\"$(json_escape "$1")\""
}

json_write() {
    [ "$TB_JSON" -eq 1 ] || return 0
    printf '{\n'
    printf '  "versione_strumento": "%s",\n' "$TB_VERSIONE"
    printf '  "data": "%s",\n' "$(date '+%Y-%m-%dT%H:%M:%S')"
    printf '  "sistema": "%s",\n' "$(json_escape "$TB_SISTEMA")"
    printf '  "simulazione": %s,\n' "$( [ "$TB_DRYRUN" -eq 1 ] && echo true || echo false )"
    printf '  "esito": %s,\n' "$TB_EXIT"
    printf '  "spazio_libero_byte": %s,\n' "$(free_space_bytes)"
    printf '  "avvisi": [%s],\n' "$TB_JSON_AVVISI"
    printf '  "operazioni": [%s\n  ]\n' "$TB_JSON_OPS"
    printf '}\n'
}

# ============================================================
#   CONFRONTO CON L'ESECUZIONE PRECEDENTE
#   Si tiene uno storico minimo in un file di testo: una riga
#   per esecuzione. Niente da analizzare, niente dipendenze.
# ============================================================
TB_STORICO=""

storico_init() { TB_STORICO="$1"; }

storico_scrivi() {
    [ -z "$TB_STORICO" ] && return 0
    printf '%s|%s|%s\n' "$(date '+%s')" "$(free_space_bytes)" "${1:-0}" >> "$TB_STORICO" 2>/dev/null
    # Non serve tenere piu' di 200 righe.
    local n; n=$(wc -l < "$TB_STORICO" 2>/dev/null | tr -d ' ')
    case "$n" in ''|*[!0-9]*) return 0 ;; esac
    if [ "$n" -gt 200 ]; then
        tail -100 "$TB_STORICO" > "$TB_STORICO.tmp" 2>/dev/null && mv "$TB_STORICO.tmp" "$TB_STORICO" 2>/dev/null
    fi
    return 0
}

# Restituisce "giorni|delta_byte|avvisi_allora" della voce piu'
# vecchia entro gli ultimi 30 giorni, oppure niente.
storico_confronta() {
    [ -z "$TB_STORICO" ] || [ ! -f "$TB_STORICO" ] && return 0
    local ora limite riga t sp av
    ora=$(date '+%s')
    limite=$(( ora - 2592000 ))
    while IFS='|' read -r t sp av; do
        case "$t" in ''|*[!0-9]*) continue ;; esac
        [ "$t" -lt "$limite" ] && continue
        [ $(( ora - t )) -lt 3600 ] && continue    # troppo recente
        printf '%s|%s|%s\n' $(( (ora - t) / 86400 )) $(( $(free_space_bytes) - sp )) "$av"
        return 0
    done < "$TB_STORICO"
    return 0
}
