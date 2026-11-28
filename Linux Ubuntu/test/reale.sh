#!/usr/bin/env bash
# ============================================================
#   SYSTEM TOOLBOX - prova delle operazioni VERE
#
#   Uso:  bash test/reale.sh
#
#   A differenza di collaudo.sh, qui lo strumento lavora davvero,
#   senza simulazione: svuota cache e cestini, ripara, ottimizza,
#   poi esegue l'analisi completa e la modalita' automatica.
#   Ogni operazione deve finire con OK o PARZIALE, e nell'output
#   non devono comparire errori della shell.
#
#   SOLO SULLE MACCHINE DI GITHUB ACTIONS, che vengono buttate via
#   dopo ogni prova: su un computer vero cancellerebbe cache,
#   cestini e log. Fuori da GitHub si rifiuta di partire.
#
#   Lo stesso file sta in macOS/test e in "Linux Ubuntu"/test:
#   le operazioni da eseguire si scelgono in base al sistema.
# ============================================================

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$(cd "$TEST_DIR/.." && pwd)"
cd "$BASE" || exit 1

# Protezione: solo su una macchina usa e getta di GitHub. Queste due
# variabili le imposta GitHub Actions sulle proprie macchine; su un
# runner installato su un computer qualsiasi RUNNER_ENVIRONMENT vale
# "self-hosted", e anche li' la prova non parte.
if [ "${GITHUB_ACTIONS:-}" != "true" ] || [ "${RUNNER_ENVIRONMENT:-}" != "github-hosted" ]; then
    echo "Questa prova cancella davvero cache, cestini e log."
    echo "Gira solo sulle macchine usa e getta di GitHub Actions."
    exit 2
fi

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  [ok]  %s\n' "$1"; }
ko()   { FAIL=$((FAIL+1)); printf '  [KO]  %s\n' "$1"; }
titolo(){ printf '\n=== %s ===\n' "$1"; }

# Errori della shell nell'output: vogliono dire codice rotto.
ERRORI_SHELL='command not found|syntax error|unbound variable|integer expression expected|bad substitution|ambiguous redirect'

# shellcheck source=/dev/null
. lib/common.sh; . lib/core.sh; . lib/ui.sh; . lib/tasks.sh; . lib/analysis.sh
TB_DIR="$BASE"
ui_colori_init
ui_simboli_init
# Inizializzazione come in toolbox.sh / toolbox.command: le due
# versioni hanno funzioni diverse, si chiama quella che c'e'.
if type tb_init_env >/dev/null 2>&1; then tb_init_env; fi
if type tb_init_user >/dev/null 2>&1; then tb_init_user; fi
if type pkg_init >/dev/null 2>&1; then pkg_init; fi
prefetch_init
TB_LOG=$(log_init "/tmp/tb_reale_log" 3)
TB_DRYRUN=0

# Sulle macchine di GitHub sudo non chiede la password.
if tb_need_root; then ok "privilegi di amministratore"; else ko "privilegi di amministratore non ottenuti"; fi

# Operazioni da eseguire. Escluse di proposito:
#   rete (rinnovo IP, reset, riavvio della gestione di rete): la
#     macchina perderebbe il collegamento con GitHub a meta' prova;
#   aggiornamenti di sistema e di Homebrew: durano molto e su Linux
#     li provano gia' i container (test/distro.sh);
#   Spotlight: reindicizza tutto il disco per ore.
case "$(uname -s)" in
    Darwin)
        OPERAZIONI="clean_trash clean_crashreports clean_logs clean_browsercache clean_quicklook
                    clean_mail clean_cache_user clean_cache_system clean_snapshots clean_xcode
                    clean_devcache clean_homebrew clean_docker clean_fontcache net_flushdns
                    maint_launchservices maint_verifydisk maint_purge"
        AVVIO="toolbox.command" ;;
    *)
        OPERAZIONI="clean_apt_cache clean_journal clean_cache_user clean_thumbnails clean_trash
                    clean_apt_autoremove clean_snap_old clean_kernels clean_flatpak clean_docker
                    clean_devcache net_flushdns maint_fix_broken maint_fstrim maint_pam_lastlog"
        AVVIO="toolbox.sh" ;;
esac

titolo "Operazioni vere"
for id in $OPERAZIONI; do
    if ! task_exists "$id"; then ko "$id: non esiste nel registro"; continue; fi
    out="/tmp/tb_reale_$id.txt"
    run_task "$id" > "$out" 2>&1
    if grep -qiE "$ERRORI_SHELL" "$out"; then
        ko "$id: errori della shell nell'output"
        grep -iE "$ERRORI_SHELL" "$out" | head -5 | sed 's/^/      /'
        continue
    fi
    case "$RES_ESITO" in
        OK)       ok "$id ($(format_bytes "$RES_BYTES") liberati, ${RES_DURATA}s)" ;;
        PARZIALE) # Un avviso non e' per forza un difetto (file in uso,
                  # cartelle protette): si mostra, e lo si valuta a mano.
                  ok "$id: PARZIALE, avvisi da leggere qui sotto"
                  printf '%s' "$RES_ERRLIST" | sed 's/^/      /' ;;
        *)        ko "$id: $RES_ESITO"
                  tail -15 "$out" | sed 's/^/      /' ;;
    esac
done

titolo "Analisi completa e report"
REP="/tmp/tb_reale_report.html"
TB_REPORT="$REP"; TB_REPBUF=""
analisi completa > /tmp/tb_reale_analisi.txt 2>&1
report_write
TB_REPORT=""
if grep -qiE "$ERRORI_SHELL" /tmp/tb_reale_analisi.txt; then
    ko "analisi completa: errori della shell nell'output"
    grep -iE "$ERRORI_SHELL" /tmp/tb_reale_analisi.txt | head -5 | sed 's/^/      /'
else
    ok "analisi completa senza errori della shell"
fi
n=$(grep -c '<h2>' "$REP" 2>/dev/null)
if [ "${n:-0}" -gt 5 ]; then ok "report HTML con $n sezioni"; else ko "report HTML vuoto o incompleto"; fi

titolo "Modalita' automatica vera"
OUT=$(bash "$AVVIO" --auto --report /tmp/tb_reale_auto.html < /dev/null 2>&1); rc=$?
# Codici: 0 tutto in ordine, 1 avvisi, 2 criticita'. Il 2 puo' venire
# dall'analisi (per esempio disco quasi pieno sulla macchina di
# GitHub) e allora non e' un difetto: conta che nessuna operazione sia
# FALLITA. In ogni caso si mostrano le righe che hanno dato il 2.
if printf '%s\n' "$OUT" | grep -q 'FALLITO'; then
    ko "$AVVIO --auto: operazioni fallite"
    printf '%s\n' "$OUT" | grep 'FALLITO' | head -5 | sed 's/^/      /'
else
    case "$rc" in
        0|1) ok "$AVVIO --auto: uscita $rc" ;;
        2)   ok "$AVVIO --auto: uscita 2 (criticita' dell'analisi, righe qui sotto)"
             printf '%s\n' "$OUT" | grep -F '[X]' | head -8 | sed 's/^/      /' ;;
        *)   ko "$AVVIO --auto: uscita $rc"
             printf '%s\n' "$OUT" | tail -15 | sed 's/^/      /' ;;
    esac
fi
if printf '%s\n' "$OUT" | grep -qiE "$ERRORI_SHELL"; then
    ko "$AVVIO --auto: errori della shell nell'output"
    printf '%s\n' "$OUT" | grep -iE "$ERRORI_SHELL" | head -5 | sed 's/^/      /'
else
    ok "$AVVIO --auto: nessun errore della shell"
fi
[ -s /tmp/tb_reale_auto.html ] && ok "report della modalita' automatica scritto" || ko "report della modalita' automatica mancante"

prefetch_cleanup
tb_cleanup

printf '\n============================================\n'
printf '  superati: %s    falliti: %s\n' "$PASS" "$FAIL"
printf '============================================\n\n'
[ "$FAIL" -eq 0 ] || exit 1
exit 0
