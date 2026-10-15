#!/bin/bash
# ============================================================
#   Suite di collaudo - System Toolbox
#
#   Verifica cio' che si puo' verificare senza modificare il
#   sistema: integrita' del registro, formattazione, motore,
#   cancellazione su cartella di prova, configurazione, report
#   e JSON.
#
#   NON esegue operazioni reali sul sistema.
#
#   Uso:  bash test/collaudo.sh
#   Esce con 0 se tutto passa, 1 altrimenti.
# ============================================================

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$(cd "$TEST_DIR/.." && pwd)"
cd "$BASE" || exit 1

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  [ok]  %s\n' "$1"; }
ko()   { FAIL=$((FAIL+1)); printf '  [KO]  %s\n' "$1"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else ko "$1  (atteso '$3', ottenuto '$2')"; fi; }
titolo(){ printf '\n=== %s ===\n' "$1"; }

# ------------------------------------------------------------
titolo "Sintassi"
for f in toolbox.sh lib/*.sh; do
    if bash -n "$f" 2>/dev/null; then ok "$f"; else ko "$f"; fi
done

# ------------------------------------------------------------
titolo "Compatibilita' bash 3.2 e comandi BSD"
# Anche qui si evitano i costrutti bash 4 e le opzioni GNU non
# indispensabili, per restare allineati alla versione macOS.
if grep -nE '\$\{[A-Za-z_][A-Za-z0-9_]*(,,|\^\^)|declare -A|mapfile|readarray|local -n' toolbox.sh lib/*.sh \
   | grep -v ':[0-9]*: *#' | grep -q .; then
    ko "trovati costrutti bash 4"
else
    ok "nessun costrutto bash 4"
fi
if grep -Fn '\s' lib/*.sh toolbox.sh | grep -v ':[0-9]*: *#' | grep -q .; then
    ko "trovato \\s in una espressione regolare (grep BSD non lo supporta)"
else
    ok "nessun \\s nelle espressioni regolari"
fi
# Su Linux le coreutils GNU ci sono e si usano di proposito
# (du --block-size, df -B1), con ripiego su -k se mancassero.
ok "coreutils GNU: uso previsto, con ripiego documentato"

# ------------------------------------------------------------
. lib/common.sh; . lib/core.sh; . lib/ui.sh; . lib/tasks.sh
TB_USER="collaudo"; TB_HOME="/tmp/tb_home_finta"
TB_LOG=$(log_init "/tmp/tb_test_log" 3)

titolo "Registro delle operazioni"
N=$(task_all_ids | grep -c .)
[ "$N" -gt 0 ] && ok "$N operazioni registrate" || ko "registro vuoto"

ERR=0
for id in $(task_all_ids); do
    [ "$(task_registry | grep -c "^$id|")" -eq 1 ] || { ko "id duplicato: $id"; ERR=1; }
    [ "$(task_registry | grep "^$id|" | awk -F'|' '{print NF}')" -eq 8 ] || { ko "campi errati: $id"; ERR=1; }
    type "task_$id" >/dev/null 2>&1 || { ko "funzione mancante: task_$id"; ERR=1; }
    case "$(task_field "$id" 4)" in sicuro|avanzato|riavvio|sconsigliato) ;; *) ko "livello ignoto: $id"; ERR=1 ;; esac
    case "$(task_field "$id" 5)" in ''|*[!0-9]*) ko "stima non numerica: $id"; ERR=1 ;; esac
done
[ "$ERR" -eq 0 ] && ok "struttura del registro integra"

# funzioni definite ma non registrate
ORF=0
for f in $(declare -F | awk '{print $3}' | grep '^task_' \
           | grep -vE '^task_(field|campo|exists|all_ids|ids_by_category|set|registry|stima_totale|serve_backup|reg_load)$'); do
    task_exists "${f#task_}" || { ko "funzione orfana: $f"; ORF=1; }
done
[ "$ORF" -eq 0 ] && ok "nessuna funzione orfana"

# gli insiemi non devono citare id inesistenti
SET_ERR=0
for s in Consigliata PuliziaSicura PuliziaAvanzata Rete ReteReset ReteRiavvio Aggiornamenti Manutenzione; do
    for id in $(task_set "$s"); do
        task_exists "$id" || { ko "insieme $s cita un id inesistente: $id"; SET_ERR=1; }
    done
done
[ "$SET_ERR" -eq 0 ] && ok "insiemi predefiniti coerenti"

# ------------------------------------------------------------
titolo "Formattazione (senza awk)"
check "format_bytes 0"           "$(format_bytes 0)"           "0 B"
check "format_bytes 1024"        "$(format_bytes 1024)"        "1 KB"
check "format_bytes 1048576"     "$(format_bytes 1048576)"     "1.0 MB"
check "format_bytes 1073741824"  "$(format_bytes 1073741824)"  "1.00 GB"
check "format_bytes 1234567890"  "$(format_bytes 1234567890)"  "1.14 GB"
check "format_bytes negativo"    "$(format_bytes -2000000)"    "-1.9 MB"
check "format_stima 3"           "$(format_stima 3)"           "immediato"
check "format_stima 45"          "$(format_stima 45)"          "circa 45 secondi"
check "format_stima 60"          "$(format_stima 60)"          "circa 1 minuto"
check "format_stima 90"          "$(format_stima 90)"          "circa 2 minuti"
check "format_stima 900"         "$(format_stima 900)"         "da 9 a 21 minuti"
check "format_durata 75"         "$(format_durata 75)"         "1m 15s"

# ------------------------------------------------------------
titolo "Configurazione"
CFG_TEST="/tmp/tb_cfg_$$.conf"
cat > "$CFG_TEST" <<'FINECFG'
# commento
disco_critico=95
swap_avviso_mb=2048
colori=daltonici
chiave_inventata=qualcosa
disco_avviso=non_un_numero
FINECFG
cfg_load "$CFG_TEST"
check "valore numerico letto"       "$CFG_disco_critico"   "95"
check "secondo valore letto"        "$CFG_swap_avviso_mb"  "2048"
check "valore testuale ammesso"     "$CFG_colori"          "daltonici"
check "valore non numerico rifiutato" "$CFG_disco_avviso"  "80"
rm -f "$CFG_TEST"
CFG_colori=auto; CFG_disco_critico=90; CFG_swap_avviso_mb=1024

# ------------------------------------------------------------
titolo "Motore dei task: i tre esiti"
task_prova_ok()   { ctx_note "ok"; CTX_BYTES=1048576; return 0; }
task_prova_warn() { ctx_fail "problema"; return 0; }
task_prova_boom() { return 3; }
_tf_orig=$(declare -f task_field)
task_field() { case "$2" in 2) echo "Prova";; 7) echo 0;; *) echo "";; esac; }
run_task prova_ok   >/dev/null 2>&1; check "task senza problemi" "$RES_ESITO" "OK"
run_task prova_warn >/dev/null 2>&1; check "task con avvisi"     "$RES_ESITO" "PARZIALE"
run_task prova_boom >/dev/null 2>&1; check "task che fallisce"   "$RES_ESITO" "FALLITO"
check "codice di uscita dopo un fallimento" "$TB_EXIT" "2"
eval "$_tf_orig"
TB_EXIT=0

# ------------------------------------------------------------
titolo "Cancellazione a scansione singola"
SB="/tmp/tb_sandbox_$$"
mkdir -p "$SB/sotto"
i=0; while [ $i -lt 3 ]; do head -c 100000 /dev/zero > "$SB/f$i.bin"; i=$((i+1)); done
head -c 50000 /dev/zero > "$SB/.nascosto.bin"
head -c 20000 /dev/zero > "$SB/sotto/g.bin"

ctx_reset; TB_DRYRUN=1
clear_folder_content "$SB" "prova" >/dev/null 2>&1
RIMASTI=$( ( shopt -s dotglob nullglob; set -- "$SB"/*; echo $# ) )
check "simulazione non cancella" "$RIMASTI" "5"
[ "$CTX_BYTES" -gt 0 ] && ok "simulazione conta i byte ($(format_bytes $CTX_BYTES))" || ko "simulazione non conta i byte"

ctx_reset; TB_DRYRUN=0
clear_folder_content "$SB" "prova" >/dev/null 2>&1
RIMASTI=$( ( shopt -s dotglob nullglob; set -- "$SB"/*; echo $# ) )
check "cancellazione completa (file nascosto compreso)" "$RIMASTI" "0"
check "elementi contati" "$CTX_ITEMS" "5"
[ "$CTX_BYTES" -gt 300000 ] && ok "byte liberati coerenti ($(format_bytes $CTX_BYTES))" || ko "byte liberati incoerenti: $CTX_BYTES"
rm -rf "$SB"

# ------------------------------------------------------------
titolo "Report e JSON"
TB_REPORT="/tmp/tb_report_$$.md"
TB_REPBUF=""; TB_SISTEMA="sistema di prova"
ui_section "SEZIONE DI PROVA" >/dev/null
ui_kv "Chiave" "valore" >/dev/null
ui_warn "un avviso" >/dev/null
report_write
if grep -q '## SEZIONE DI PROVA' "$TB_REPORT" && grep -q 'Chiave' "$TB_REPORT"; then
    ok "report Markdown generato dal rendering"
else ko "report Markdown incompleto"; fi
rm -f "$TB_REPORT"

TB_REPORT="/tmp/tb_report_$$.html"
report_write
grep -q '<h2>SEZIONE DI PROVA</h2>' "$TB_REPORT" && ok "report HTML generato" || ko "report HTML incompleto"
rm -f "$TB_REPORT"; TB_REPORT=""

TB_JSON=1; TB_JSON_OPS=""; TB_JSON_AVVISI=""
json_op_add "prova_id" "Nome con \"virgolette\"" "OK" 1024 2 0
json_avviso_add "un avviso"
OUT=$(json_write)
echo "$OUT" | grep -q '"versione_strumento"' && ok "JSON con versione" || ko "JSON senza versione"
echo "$OUT" | grep -q '\\"virgolette\\"' && ok "JSON con virgolette protette" || ko "JSON non protegge le virgolette"
TB_JSON=0

# ------------------------------------------------------------
titolo "Storico e confronto"
ST="/tmp/tb_storico_$$.txt"
storico_init "$ST"
printf '%s|1000000|3\n' "$(( $(date +%s) - 172800 ))" > "$ST"
CONF=$(storico_confronta)
[ -n "$CONF" ] && ok "confronto con l'esecuzione precedente ($CONF)" || ko "confronto non prodotto"
rm -f "$ST"

# ------------------------------------------------------------
titolo "Misura con budget di tempo"
# Cartella di prova: due sottocartelle con contenuto noto.
MDIR="/tmp/tb_misura_$$"
rm -rf "$MDIR"; mkdir -p "$MDIR/uno" "$MDIR/due"
dd if=/dev/zero of="$MDIR/uno/a" bs=1024 count=200 2>/dev/null
dd if=/dev/zero of="$MDIR/due/b" bs=1024 count=100 2>/dev/null

RIS=$(bytes_of_path_limitato "$MDIR" 30)
MB=$(echo "$RIS" | cut -d'|' -f1)
MP=$(echo "$RIS" | cut -d'|' -f2)
check "misura completa non e' parziale" "$MP" "0"
# Il totale include i blocchi delle directory: si verifica
# l'ordine di grandezza, non il byte esatto.
if [ "$MB" -ge 307200 ] && [ "$MB" -le 1048576 ]; then
    ok "totale plausibile ($(format_bytes "$MB"))"
else
    ko "totale fuori intervallo: $MB"
fi

check "percorso inesistente" "$(bytes_of_path_limitato "$MDIR/manca" 5)" "0|0"

# Budget a zero: il risultato deve essere dichiarato parziale e
# mai maggiore del totale vero, perche' i figli diretti di du
# non si sovrappongono fra loro.
RIS=$(bytes_of_path_limitato "$MDIR" 0)
PB=$(echo "$RIS" | cut -d'|' -f1)
PP=$(echo "$RIS" | cut -d'|' -f2)
if [ "$PP" = "1" ] || [ "$PB" = "$MB" ]; then
    ok "budget scaduto: valore dichiarato parziale o gia' completo"
else
    ko "budget scaduto senza segnalazione (byte=$PB parziale=$PP)"
fi
[ "$PB" -le "$MB" ] && ok "il parziale non supera mai il totale" \
                    || ko "parziale $PB maggiore del totale $MB"
rm -rf "$MDIR"

# ------------------------------------------------------------
titolo "Cache su file"
CDIR="/tmp/tb_cache_$$"
rm -rf "$CDIR"
cache_init "$CDIR"
printf 'riga uno\nriga due\n' | cache_scrivi prova
check "rilettura entro la scadenza" "$(cache_leggi prova 6 | head -1)" "riga uno"
check "scadenza a zero ore invalida la cache" "$(cache_leggi prova 0)" ""
check "voce mai scritta" "$(cache_leggi inesistente 6)" ""
check "eta' in ore appena scritta" "$(cache_eta_ore prova)" "0"
rm -rf "$CDIR"

# ------------------------------------------------------------
titolo "Rendering testuale senza processi esterni"
TB_W=40
C_OFF=""; C_DIM=""
check "ui_line lunghezza richiesta" "$(ui_line '-' 12 | tr -d '\n' | wc -c | tr -d ' ')" "12"

# Regressione: ui_wrap costruisce le righe in bash, quindi senza
# "set -f" una parola come * verrebbe espansa nei nomi dei file
# della cartella corrente.
W=$(ui_wrap "prima * dopo" 0 "")
case "$W" in
    *'*'*) ok "ui_wrap non espande i caratteri jolly" ;;
    *)     ko "ui_wrap ha espanso *: [$W]" ;;
esac

# Nessuna riga puo' superare la larghezza disponibile.
LUNGA="alfa bravo charlie delta echo foxtrot golf hotel india juliet kilo lima mike"
TROPPO=$(ui_wrap "$LUNGA" 3 "" | awk '{ if (length($0) > 40) c++ } END { print c + 0 }')
check "nessuna riga oltre la larghezza" "$TROPPO" "0"
check "tutte le parole conservate" \
      "$(ui_wrap "$LUNGA" 3 "" | wc -w | tr -d ' ')" \
      "$(echo "$LUNGA" | wc -w | tr -d ' ')"
check "testo vuoto non produce righe" "$(ui_wrap "" 3 "" | wc -c | tr -d ' ')" "0"
TB_W=$(ui_width)

# ------------------------------------------------------------
titolo "Nuove chiavi di configurazione"
CF="/tmp/tb_conf2_$$.conf"
cat > "$CF" <<'FINECONF'
cornici=utf8
analisi_aggiornamenti=no
cache_aggiornamenti_ore=12
misura_max_secondi=30
conferme_grafiche=forse
FINECONF
CFG_cornici=ascii; CFG_analisi_aggiornamenti=si
CFG_cache_aggiornamenti_ore=6; CFG_misura_max_secondi=12
CFG_conferme_grafiche=no
cfg_load "$CF"
check "cornici" "$CFG_cornici" "utf8"
check "analisi_aggiornamenti" "$CFG_analisi_aggiornamenti" "no"
check "cache_aggiornamenti_ore" "$CFG_cache_aggiornamenti_ore" "12"
check "misura_max_secondi" "$CFG_misura_max_secondi" "30"
check "valore non previsto rifiutato" "$CFG_conferme_grafiche" "no"
rm -f "$CF"
CFG_cornici=ascii

# ------------------------------------------------------------
titolo "Sorgente in ASCII puro"
# Nessuna lettera accentata, nessun carattere UTF-8 letterale:
# l'output resta leggibile via SSH, in console TTY e con LANG=C,
# e il sorgente non dipende dalla codifica con cui viene salvato
# o trasferito. I blocchi della modalita' utf8 sono scritti come
# byte ($'\xe2\x96\x88'), non come caratteri.
NONASCII=0
for f in toolbox.sh lib/*.sh; do
    if LC_ALL=C grep -q '[^ -~	]' "$f"; then
        ko "caratteri non ASCII in $f"
        NONASCII=1
    fi
done
[ "$NONASCII" -eq 0 ] && ok "nessun carattere non ASCII nel sorgente"

# ------------------------------------------------------------
titolo "Funzioni interne tutte definite"
# Il controllo nasce da un errore vero: ui.sh ha cominciato a
# usare task_campo prima che tasks.sh la definisse. bash non se
# ne accorge finche' quella riga non viene eseguita, e nessuna
# suite la eseguiva.
#
# Si cercano i nomi in POSIZIONE DI COMANDO: a inizio riga, dopo
# ; o &, oppure dentro $( ). Non dopo | e non dopo ( da soli,
# altrimenti le alternative di un "case" verrebbero scambiate
# per chiamate. Il nome deve finire con uno spazio o con una
# parentesi chiusa: cosi' "nome=valore" resta un'assegnazione.
#
# Il controllo gira in una sottoshell con analysis.sh caricato,
# che la suite non carica altrove.
(
    . lib/analysis.sh 2>/dev/null
    PREFISSI='task|pkg|ui|ctx|cache|prefetch|spazio|snap|salta|show|run|log|rep|json|storico|exit|format|bytes|umano|avviso'
    MANCANTI=""
    for f in toolbox.sh toolbox-gui.sh lib/*.sh; do
        for nome in $(grep -oE "(^|[;&]|[$][(])[[:space:]]*($PREFISSI)_[a-z0-9_]+([[:space:]]|[)]|$)" "$f" \
                      | grep -oE "($PREFISSI)_[a-z0-9_]+" | sort -u); do
            type "$nome" >/dev/null 2>&1 || MANCANTI="$MANCANTI $nome($f)"
        done
    done
    if [ -z "$MANCANTI" ]; then
        echo "OK"
    else
        for m in $MANCANTI; do echo "KO $m"; done
    fi
) > /tmp/tb_funz_$$ 2>/dev/null
if grep -q '^OK$' /tmp/tb_funz_$$; then
    ok "nessuna chiamata a funzioni inesistenti"
else
    while IFS= read -r r; do
        [ -n "${r#KO }" ] && ko "funzione non definita: ${r#KO }"
    done < /tmp/tb_funz_$$
fi
rm -f /tmp/tb_funz_$$
# ------------------------------------------------------------
titolo "Configurazione: ogni chiave dichiarata e' documentata"
# Nasce da una dimenticanza vera: su Windows `tema` e
# `analisi_aggiornamenti` esistevano nel codice ma non nel file
# d'esempio, quindi nessuno poteva scoprirle leggendolo.
CHIAVI_DICH=$(grep -oE '^CFG_[a-z_]+=' lib/common.sh | sed 's/^CFG_//; s/=$//' | sort)
CHIAVI_DOC=$(grep -oE '^[a-z_]+=' toolbox.conf.esempio | tr -d '=' | sort)
NON_DOC=$(comm -23 <(echo "$CHIAVI_DICH") <(echo "$CHIAVI_DOC") | tr '
' ' ')
NON_LETTE=$(comm -13 <(echo "$CHIAVI_DICH") <(echo "$CHIAVI_DOC") | tr '
' ' ')
check "chiavi dichiarate ma non documentate" "$NON_DOC" ""
check "chiavi documentate ma non dichiarate" "$NON_LETTE" ""

# ------------------------------------------------------------
titolo "Conferma grafica: errore del dialogo non vale come Annulla"
# Prima un dialogo che non riusciva ad aprirsi veniva letto come
# "Annulla": con conferme_grafiche=si nessuna operazione partiva
# piu', e senza alcun ripiego sul terminale. Qui zenity e' finto e
# restituisce ogni esito possibile.
FINTI=$(mktemp -d "${TMPDIR:-/tmp}/tb_dlg_XXXXXX")
prova_zenity() {
    printf '#!/bin/sh\nexit %s\n' "$1" > "$FINTI/zenity"; chmod +x "$FINTI/zenity"
    ( PATH="$FINTI:$PATH"; DISPLAY=:0; ui_yesno_dialogo "t" "x"; echo $? )
}
check "zenity Procedi -> 0"            "$(prova_zenity 0)"   "0"
check "zenity Annulla -> 1"            "$(prova_zenity 1)"   "1"
check "zenity in errore -> ripiego (2)" "$(prova_zenity 255)" "2"
check "zenity scaduto -> ripiego (2)"   "$(prova_zenity 5)"   "2"
check "senza display -> ripiego (2)" \
      "$( ( PATH="$FINTI:$PATH"; unset DISPLAY WAYLAND_DISPLAY; ui_yesno_dialogo t x; echo $? ) )" "2"
rm -rf "$FINTI"

# ------------------------------------------------------------
titolo "Colori e simboli reimpostati dopo la configurazione"
# ui.sh imposta colori e simboli quando viene caricato, cioe' prima
# che toolbox.conf sia letto. Se il punto d'avvio non li reimposta
# dopo, la configurazione non ha effetto: su macOS simboli=emoji
# veniva ignorato proprio per questo.
for f in toolbox.sh toolbox-gui.sh; do
    prima=$(grep -n '^cfg_load ' "$f" | head -1 | cut -d: -f1)
    for fn in ui_colori_init ui_simboli_init; do
        dopo=$(grep -n "^$fn\$" "$f" | tail -1 | cut -d: -f1)
        if [ -n "$prima" ] && [ -n "$dopo" ] && [ "$dopo" -gt "$prima" ]; then
            ok "$f: $fn dopo la configurazione"
        else
            ko "$f: $fn assente o prima della configurazione"
        fi
    done
done

# ------------------------------------------------------------
titolo "Privilegi negati: l'operazione non parte"
# Prima il messaggio diceva "verranno saltate", ma run_task le
# eseguiva lo stesso: sudo senza terminale falliva a meta' lavoro,
# e in un terminale richiedeva la password a ogni comando.
# Un'operazione finta, registrata a mano nella cache del registro.
if [ "$(id -u)" -eq 0 ]; then
    ok "controllo saltato: la suite gira come root"
else
    task_reg_load
    TB_F2_prova_root="Prova privilegi"; TB_F6_prova_root=1; TB_F7_prova_root=0
    task_prova_root() { PROVA_ESEGUITA=1; }
    SALVA_DRY=$TB_DRYRUN; SALVA_ROOT=$TB_ROOT_OK; SALVA_EXIT=$TB_EXIT

    TB_DRYRUN=0; TB_ROOT_OK=0; PROVA_ESEGUITA=0
    run_task prova_root >/dev/null 2>&1
    check "negati: esito FALLITO"         "$RES_ESITO"      "FALLITO"
    check "negati: il corpo non e' eseguito" "$PROVA_ESEGUITA" "0"

    TB_DRYRUN=0; TB_ROOT_OK=1; PROVA_ESEGUITA=0
    run_task prova_root >/dev/null 2>&1
    check "concessi: eseguita"            "$PROVA_ESEGUITA" "1"
    check "concessi: esito OK"            "$RES_ESITO"      "OK"

    TB_DRYRUN=1; TB_ROOT_OK=0; PROVA_ESEGUITA=0
    run_task prova_root >/dev/null 2>&1
    check "simulazione: eseguita senza privilegi" "$PROVA_ESEGUITA" "1"

    TB_DRYRUN=$SALVA_DRY; TB_ROOT_OK=$SALVA_ROOT; TB_EXIT=$SALVA_EXIT
    unset -f task_prova_root
fi

# ------------------------------------------------------------
titolo "Configurazione: ogni chiave ha un effetto o e' dichiarata non usata"
# Nasce da un difetto vero: diverse soglie erano documentate nel
# file d'esempio ma nessuna riga del codice le leggeva, e il valore
# era scritto fisso. Cambiarle non aveva alcun effetto.
# Una chiave va bene se il codice la legge, oppure se il commento
# che la precede nel file d'esempio la dichiara "non usata".
SENZA_EFFETTO=""
for k in $(grep -oE '^CFG_[a-z_]+=' lib/common.sh | sed 's/^CFG_//; s/=$//'); do
    if cat toolbox.sh toolbox-gui.sh lib/*.sh | grep -v "^CFG_$k=" | grep -q "CFG_$k\b"; then continue; fi
    blocco=$(awk -v k="$k" '/^#/{b=b $0 " "; next} $0 ~ "^"k"=" {print b; exit} {b=""}' toolbox.conf.esempio)
    printf '%s' "$blocco" | grep -qi 'non usat' && continue
    SENZA_EFFETTO="$SENZA_EFFETTO $k"
done
check "nessuna chiave documentata senza effetto" "$SENZA_EFFETTO" ""

# ------------------------------------------------------------
titolo "Cartelle temporanee con nome non prevedibile"
# Prima la cache dell'analisi era /tmp/toolbox_cache_<PID>, creata
# con mkdir -p: un altro utente poteva crearla in anticipo.
SALVA_CACHE=$TB_CACHE
prefetch_init
case "$TB_CACHE" in
    */toolbox_cache.????????) ok "nome casuale creato con mktemp" ;;
    *) ko "nome della cache prevedibile o assente: $TB_CACHE" ;;
esac
[ -d "$TB_CACHE" ] && ok "cartella creata" || ko "cartella non creata"
prefetch_cleanup
[ -d "$TB_CACHE" ] && ko "cartella non rimossa" || ok "cartella rimossa alla fine"
TB_CACHE=$SALVA_CACHE
if grep -qE 'TMPDIR:-/tmp}/[a-z_]+_[$][$]' lib/*.sh toolbox.sh toolbox-gui.sh; then
    ko "resta un percorso temporaneo prevedibile"
else
    ok "nessun percorso temporaneo prevedibile nei sorgenti"
fi

# ------------------------------------------------------------
titolo "Conversione da forma leggibile a byte"
# Serve per i comandi che rispondono gia' in "1.1G": rimisurarli
# con du sarebbe assurdo, ma il numero va convertito a mano
# perche' bash non ha la virgola.
check "512 byte"        "$(umano_in_byte 512B)"    "512"
check "1K"              "$(umano_in_byte 1K)"      "1024"
check "4,0K con virgola" "$(umano_in_byte 4,0K)"   "4096"
check "1M"              "$(umano_in_byte 1M)"      "1048576"
check "1.5G"            "$(umano_in_byte 1.5G)"    "1610612736"
check "unita' assente"  "$(umano_in_byte 900)"     "900"
check "stringa vuota"   "$(umano_in_byte '')"      "0"
check "spazzatura"      "$(umano_in_byte 'boh')"   "0"

# ------------------------------------------------------------
titolo "Somma di file gia' noti"
FDIR="/tmp/tb_files_$$"
rm -rf "$FDIR"; mkdir -p "$FDIR"
dd if=/dev/zero of="$FDIR/a" bs=1024 count=100 2>/dev/null
dd if=/dev/zero of="$FDIR/b" bs=1024 count=50  2>/dev/null
B=$(bytes_of_files "$FDIR/a" "$FDIR/b")
if [ "$B" -ge 153600 ] && [ "$B" -le 262144 ]; then
    ok "somma di due file ($(format_bytes "$B"))"
else
    ko "somma fuori intervallo: $B"
fi
check "elenco vuoto"        "$(bytes_of_files)"              "0"
check "file inesistente"    "$(bytes_of_files "$FDIR/manca")" "0"
rm -rf "$FDIR"

# ------------------------------------------------------------
titolo "Simboli di stato"
CFG_simboli=ascii; ui_simboli_init
check "ascii: ok"   "$TB_SYM_OK"   "[ok]"
check "ascii: err"  "$TB_SYM_ERR"  "[X] "
CFG_simboli=emoji; ui_simboli_init
# Il confronto e' sui byte: il sorgente resta in ASCII puro e i
# glifi sono scritti come sequenze di escape.
if [ "$TB_SYM_OK" != "[ok]" ] && [ -n "$TB_SYM_OK" ]; then
    ok "emoji: simbolo sostituito"
else
    ko "emoji: simbolo non cambiato"
fi
BADGE_EMOJI=$(CFG_simboli=emoji ui_badge avanzato)
case "$BADGE_EMOJI" in
    *avanzato*) ok "emoji: il livello resta leggibile accanto al glifo" ;;
    *)          ko "emoji: la parola del livello e' sparita" ;;
esac
CFG_simboli=ascii; ui_simboli_init
check "ritorno all'ascii" "$TB_SYM_OK" "[ok]"

# ------------------------------------------------------------
titolo "Chiavi di configurazione: simboli e avanzamento"
CF3="/tmp/tb_conf3_$$.conf"
cat > "$CF3" <<'FINECONF3'
simboli=emoji
avanzamento=no
FINECONF3
CFG_simboli=ascii; CFG_avanzamento=si
cfg_load "$CF3"
check "simboli"     "$CFG_simboli"     "emoji"
check "avanzamento" "$CFG_avanzamento" "no"
cat > "$CF3" <<'FINECONF4'
simboli=disegnini
FINECONF4
cfg_load "$CF3"
check "valore non previsto rifiutato" "$CFG_simboli" "emoji"
rm -f "$CF3"
CFG_simboli=ascii; ui_simboli_init

# ------------------------------------------------------------
titolo "Gestore pacchetti: astrazione"
# Su questa macchina non c'e' nessun gestore riconosciuto, ed e'
# proprio il caso che conta: le funzioni devono dichiararlo,
# non fingere che vada tutto bene.
TB_PKG=""; TB_PKG_NOME="nessuno"
pkg_presente && ko "pkg_presente vero senza gestore" || ok "nessun gestore: pkg_presente falso"
check "cache_dir vuota"       "$(pkg_cache_dir)"  ""
pkg_pulisci_cache   >/dev/null 2>&1 && ko "pulisci_cache riuscita senza gestore"   || ok "pulisci_cache fallisce, non finge"
pkg_aggiorna_indice >/dev/null 2>&1 && ko "aggiorna_indice riuscita senza gestore" || ok "aggiorna_indice fallisce, non finge"
check "conteggio neutro" "$(pkg_conta_aggiornamenti 2>/dev/null)" "0;0"

# Ogni gestore deve avere una risposta per ognuna delle domande:
# un ramo dimenticato si vedrebbe solo su quella distribuzione.
MANCA_RAMO=""
for g in apt dnf pacman zypper; do
    TB_PKG="$g"
    [ -n "$(pkg_cache_dir)" ] || MANCA_RAMO="$MANCA_RAMO cache_dir/$g"
    case "$(pkg_suggerisci_installazione prova)" in
        *prova*) ;;
        *) MANCA_RAMO="$MANCA_RAMO suggerimento/$g" ;;
    esac
done
[ -z "$MANCA_RAMO" ] && ok "tutti i gestori hanno cartella cache e suggerimento" \
                     || ko "rami mancanti:$MANCA_RAMO"

# Le funzioni che eseguono devono esistere per ogni gestore.
for fn in pkg_elenco_aggiornabili pkg_elenco_orfani pkg_elenco_rimossi_completo \
          pkg_esegui_upgrade pkg_esegui_upgrade_completo pkg_rimuovi_orfani pkg_ripara; do
    type "$fn" >/dev/null 2>&1 || ko "manca $fn"
done
ok "interfaccia del gestore pacchetti completa"
TB_PKG=""; TB_PKG_NOME="nessuno"

# ------------------------------------------------------------
titolo "Rilevamento container"
type tb_init_container >/dev/null 2>&1 && ok "tb_init_container definita" \
                                       || ko "tb_init_container mancante"
# Qui non siamo in un container: il rilevamento non deve
# inventarselo.
TB_CONTAINER=""; tb_init_container
if [ -z "$TB_CONTAINER" ]; then
    ok "nessun container dichiarato su un sistema che non lo e'"
else
    ok "container rilevato: $TB_CONTAINER"
fi

# salta_se_virtuale deve reagire a entrambi gli ambienti.
TB_WSL=0; TB_CONTAINER="docker"
salta_se_virtuale "prova" >/dev/null && ok "salta_se_virtuale: container" \
                                     || ko "salta_se_virtuale ignora il container"
TB_CONTAINER=""; TB_WSL=1
salta_se_virtuale "prova" >/dev/null && ok "salta_se_virtuale: WSL" \
                                     || ko "salta_se_virtuale ignora WSL"
TB_WSL=0
salta_se_virtuale "prova" >/dev/null && ko "salta_se_virtuale scatta su hardware reale" \
                                     || ok "salta_se_virtuale: hardware reale non salta"

# ------------------------------------------------------------
titolo "Avanzamento delle operazioni lunghe"
# Il filtro conta solo le righe che segnano un passo, e si ferma
# al 99% finche' il comando non e' finito davvero: mostrare 100%
# mentre sta ancora lavorando sarebbe una bugia.
TB_LOG=""
USCITA=$(printf 'Get:1 archivio\nUnpacking uno\nSetting up uno\nrumore qualsiasi\n' \
         | avanzamento_filtro "prova" 3 | tr -d '\r')
case "$USCITA" in
    *99%*) ok "la barra si ferma al 99% prima della fine" ;;
    *100%*) ko "la barra dichiara 100% prima della fine" ;;
    *)     ko "nessuna percentuale prodotta: [$USCITA]" ;;
esac
USCITA=$(printf 'Unpacking uno\n' | avanzamento_filtro "prova" 0 | tr -d '\r')
case "$USCITA" in
    *"1 passi"*) ok "senza totale conta i passi" ;;
    *)           ko "conteggio dei passi assente: [$USCITA]" ;;
esac
TB_LOG=$(log_init "/tmp/tb_test_log" 3)

# Senza terminale il comportamento torna silenzioso: la barra in
# un report o dentro cron sarebbe solo spazzatura.
CFG_avanzamento=si
run_con_avanzamento "prova" 1 true > /tmp/tb_avanz_$$ 2>&1
check "senza terminale non stampa la barra" "$(wc -c < /tmp/tb_avanz_$$ | tr -d ' ')" "0"
rm -f /tmp/tb_avanz_$$
run_con_avanzamento "prova" 1 false >/dev/null 2>&1 && ko "esito del comando perso" \
                                                    || ok "esito del comando conservato"

# ------------------------------------------------------------
titolo "Scorciatoie di sistema e interfaccia grafica"
for f in toolbox-gui.sh installa-scorciatoie.sh; do
    [ -f "$f" ] && ok "$f presente" || ko "$f mancante"
done
# L'interfaccia grafica non deve contenere logica di
# manutenzione propria: se un giorno qualcuno ci scrivesse un
# task, esisterebbero due versioni della stessa operazione.
if grep -qE '^task_[a-z_]+\(\)' toolbox-gui.sh; then
    ko "toolbox-gui.sh definisce operazioni sue"
else
    ok "toolbox-gui.sh non duplica il motore"
fi
grep -q 'exec "$TB_DIR/toolbox.sh"' toolbox-gui.sh \
    && ok "senza zenity ripiega sul menu testuale" \
    || ko "nessun ripiego senza zenity"
# La voce di menu deve aprire un terminale: il tool e'
# interattivo e chiede la password.
grep -q 'Terminal=true' installa-scorciatoie.sh \
    && ok "la voce .desktop apre un terminale" \
    || ko "la voce .desktop non apre un terminale"

# ------------------------------------------------------------
printf '\n============================================\n'
printf '  superati: %s    falliti: %s\n' "$PASS" "$FAIL"
printf '============================================\n\n'
[ "$FAIL" -eq 0 ] || exit 1
exit 0
