#!/usr/bin/env bash
# ============================================================
#   SYSTEM TOOLBOX - misura dei tempi
#
#   Uso:  bash test/misura.sh
#
#   Lancia l'analisi completa e l'analisi rapida come le lancia lo
#   strumento, con un cronometro attorno a ogni sezione, e stampa
#   le sezioni dalla piu' lenta. Serve a sapere dove si perde tempo
#   prima di ottimizzare, e a confrontare il prima e il dopo.
#
#   Non modifica lo strumento: le sezioni vengono "avvolte" solo in
#   memoria, dentro questo script. L'analisi e' in sola lettura.
#   Lo stesso file sta in macOS/test e in "Linux Ubuntu"/test.
# ============================================================

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$(cd "$TEST_DIR/.." && pwd)"
cd "$BASE" || exit 1

# shellcheck source=/dev/null
. lib/common.sh; . lib/core.sh; . lib/ui.sh; . lib/tasks.sh; . lib/analysis.sh
TB_DIR="$BASE"
ui_colori_init
ui_simboli_init
if type tb_init_env >/dev/null 2>&1; then tb_init_env; fi
if type tb_init_user >/dev/null 2>&1; then tb_init_user; fi
if type pkg_init >/dev/null 2>&1; then pkg_init; fi
TB_LOG=$(log_init "/tmp/tb_misura_log" 3)
# Cache degli aggiornamenti in una cartella vuota: la prima analisi
# misura la ricerca vera, non un risultato gia' memorizzato.
cache_init "$(mktemp -d "${TMPDIR:-/tmp}/tb_misura_cache.XXXXXX")"

# Millisecondi da un'origine qualsiasi. bash 5 ha EPOCHREALTIME;
# il bash 3.2 del Mac no, e li' si usa perl, presente in macOS.
adesso_ms() {
    if [ -n "${EPOCHREALTIME:-}" ]; then
        local t=${EPOCHREALTIME/[.,]/}
        echo $(( t / 1000 ))
    elif command -v perl >/dev/null 2>&1; then
        perl -MTime::HiRes=time -e 'printf "%d\n", time * 1000'
    else
        echo $(( $(date +%s) * 1000 ))
    fi
}

# Elenco delle sezioni: le funzioni show_* chiamate da analisi().
SEZIONI=$(sed -n '/^analisi() {/,/^}/p' lib/analysis.sh | grep -oE '^[[:space:]]+show_[a-z_]+' | tr -d ' \t' | sort -u)

# Ogni sezione viene rinominata e sostituita da una che misura il
# tempo e poi chiama l'originale con gli stessi argomenti.
TEMPI="/tmp/tb_misura_tempi.txt"
for f in $SEZIONI; do
    type "$f" >/dev/null 2>&1 || continue
    eval "orig_$(declare -f "$f")"
    eval "$f() { local t0; t0=\$(adesso_ms); orig_$f \"\$@\"; local rc=\$?; echo \"\$(( \$(adesso_ms) - t0 ))|$f\" >> \"\$TEMPI\"; return \$rc; }"
done

misura() {
    local modo="$1" t0 tot
    : > "$TEMPI"
    prefetch_init
    t0=$(adesso_ms)
    analisi "$modo" > "/tmp/tb_misura_$modo.txt" 2>&1
    tot=$(( $(adesso_ms) - t0 ))
    prefetch_cleanup
    printf '\n=== Analisi %s: %d.%03d s in totale ===\n' "$modo" $(( tot / 1000 )) $(( tot % 1000 ))
    sort -t'|' -k1,1nr "$TEMPI" | while IFS='|' read -r ms nome; do
        printf '  %6d.%03d s   %s\n' $(( ms / 1000 )) $(( ms % 1000 )) "$nome"
    done
}

# Avvio dello strumento: caricare le librerie e uscire.
avvio="toolbox.sh"; [ -f toolbox.command ] && avvio="toolbox.command"
t0=$(adesso_ms)
bash "$avvio" --versione > /dev/null 2>&1
t=$(( $(adesso_ms) - t0 ))
printf '=== Avvio (%s --versione): %d.%03d s ===\n' "$avvio" $(( t / 1000 )) $(( t % 1000 ))

misura completa
misura rapida
exit 0
