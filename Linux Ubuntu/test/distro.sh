#!/usr/bin/env bash
# ============================================================
#   SYSTEM TOOLBOX - prova sul gestore pacchetti VERO
#
#   Uso:  bash test/distro.sh <apt|dnf|pacman|zypper>
#
#   A differenza di collaudo.sh, qui i comandi del gestore
#   pacchetti vengono eseguiti davvero: aggiornamento dell'indice,
#   elenchi, pulizia della cache, aggiornamento dei pacchetti.
#
#   VA LANCIATO SOLO DENTRO UN CONTAINER USA E GETTA, come fa il
#   collaudo automatico su GitHub (Fedora, Arch): su un computer
#   vero aggiornerebbe e ripulirebbe il sistema. Per questo si
#   rifiuta di partire fuori da un container.
# ============================================================

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$(cd "$TEST_DIR/.." && pwd)"
cd "$BASE" || exit 1

ATTESO="${1:-}"
case "$ATTESO" in
    apt|dnf|pacman|zypper) ;;
    *) echo "Uso: bash test/distro.sh <apt|dnf|pacman|zypper>"; exit 2 ;;
esac

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  [ok]  %s\n' "$1"; }
ko()   { FAIL=$((FAIL+1)); printf '  [KO]  %s\n' "$1"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else ko "$1  (atteso '$3', ottenuto '$2')"; fi; }
titolo(){ printf '\n=== %s ===\n' "$1"; }

# shellcheck source=/dev/null
. lib/common.sh; . lib/core.sh; . lib/ui.sh; . lib/tasks.sh
tb_init_env
pkg_init

# Protezione: solo dentro un container Docker o Podman. Non basta
# TB_CONTAINER: anche WSL viene riconosciuto come container (da
# systemd-detect-virt), ma un Ubuntu in WSL e' un sistema vero, non
# usa e getta. Servono i marcatori espliciti di Docker o Podman, e
# niente WSL.
if [ "$TB_WSL" -eq 1 ] || { [ ! -f /.dockerenv ] && [ ! -f /run/.containerenv ]; }; then
    echo "Questa prova modifica il sistema: va lanciata solo dentro un container Docker o Podman."
    exit 2
fi
if [ "$(id -u)" -ne 0 ]; then
    echo "Nel container serve l'utente root."
    exit 2
fi
TB_ROOT_OK=1; TB_DRYRUN=0
TB_LOG=$(log_init "/tmp/tb_distro_log" 3)

# Un nome di pacchetto per riga, senza spazi: e' quello che le
# operazioni passano poi al gestore come argomenti.
nomi_validi() {
    local riga
    while IFS= read -r riga; do
        [ -z "$riga" ] && continue
        case "$riga" in *[!A-Za-z0-9._+:@~-]*) return 1 ;; esac
    done
    return 0
}

titolo "Riconoscimento ($ATTESO)"
check "gestore riconosciuto" "$TB_PKG" "$ATTESO"
pkg_presente && ok "pkg_presente vero" || ko "pkg_presente falso"
d=$(pkg_cache_dir)
[ -d "$d" ] && ok "cartella cache presente: $d" || ko "cartella cache assente: $d"
check "container riconosciuto (sezioni del kernel saltate)" "$TB_VIRTUALE" "1"

titolo "Indice dei pacchetti"
if pkg_aggiorna_indice; then ok "aggiornamento dell'indice"; else ko "aggiornamento dell'indice fallito"; fi

titolo "Elenchi (sola lettura)"
L=$(pkg_elenco_aggiornabili); rc=$?
check "elenco aggiornabili: comando riuscito" "$rc" "0"
printf '%s\n' "$L" | nomi_validi && ok "elenco aggiornabili: nomi validi ($(printf '%s\n' "$L" | grep -c .) pacchetti)" \
                                 || ko "elenco aggiornabili: righe che non sono nomi di pacchetto"
C=$(pkg_conta_aggiornamenti)
case "$C" in [0-9]*\;-1|[0-9]*\;[0-9]*) ok "conteggio aggiornamenti: $C" ;; *) ko "conteggio aggiornamenti illeggibile: '$C'" ;; esac
L=$(pkg_elenco_orfani); rc=$?
check "elenco orfani: comando riuscito" "$rc" "0"
printf '%s\n' "$L" | nomi_validi && ok "elenco orfani: nomi validi" || ko "elenco orfani: righe non valide"
L=$(pkg_elenco_rimossi_completo); rc=$?
check "anteprima delle rimozioni: comando riuscito" "$rc" "0"
printf '%s\n' "$L" | nomi_validi && ok "anteprima delle rimozioni: nomi validi" || ko "anteprima delle rimozioni: righe non valide"

titolo "Riparazione (su un sistema sano non deve trovare niente)"
OUT=$(pkg_ripara); rc=$?
check "ripara: nessun problema" "$rc" "0"
[ "$rc" -ne 0 ] && printf '%s\n' "$OUT" | sed 's/^/      /'

titolo "Operazioni vere, come le esegue lo strumento"
# Le stesse funzioni chiamate dal menu. Nel container non c'e'
# niente da perdere: e' la prova piu' vicina all'uso reale.
for id in clean_apt_cache clean_apt_autoremove maint_fix_broken maint_upgrade maint_dist_upgrade; do
    ctx_reset
    "task_$id" > "/tmp/tb_distro_$id.txt" 2>&1
    rc=$?
    if [ "$rc" -eq 0 ] && [ "$CTX_ERRORS" -eq 0 ]; then
        ok "$id"
    else
        ko "$id (codice $rc, problemi $CTX_ERRORS)"
        sed 's/^/      /' "/tmp/tb_distro_$id.txt" | tail -15
        printf '%s' "$CTX_ERRLIST" | sed 's/^/      /'
    fi
done
L=$(pkg_elenco_aggiornabili)
check "dopo l'aggiornamento non resta niente da aggiornare" "$(printf '%s\n' "$L" | grep -c .)" "0"

titolo "Modalita' automatica completa (simulazione)"
OUT=$(bash toolbox.sh --auto --dry-run < /dev/null 2>&1); rc=$?
case "$rc" in 0|1) ok "toolbox.sh --auto: uscita $rc" ;; *) ko "toolbox.sh --auto: uscita $rc" ;; esac
if printf '%s\n' "$OUT" | grep -qiE 'command not found|syntax error|unbound variable|integer expression'; then
    ko "toolbox.sh --auto: errori nell'output"
    printf '%s\n' "$OUT" | grep -iE 'command not found|syntax error|unbound variable|integer expression' | head -5 | sed 's/^/      /'
else
    ok "toolbox.sh --auto: nessun errore nell'output"
fi

printf '\n============================================\n'
printf '  superati: %s    falliti: %s\n' "$PASS" "$FAIL"
printf '============================================\n\n'
[ "$FAIL" -eq 0 ] || exit 1
exit 0
