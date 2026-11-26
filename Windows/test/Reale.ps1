# ============================================================
#   SYSTEM TOOLBOX - prova delle operazioni VERE (Windows)
#
#   Uso:  powershell -ExecutionPolicy Bypass -File test\Reale.ps1
#
#   A differenza di Collaudo.ps1, qui lo strumento lavora davvero,
#   senza simulazione: svuota cache e cestini, compatta i
#   componenti, verifica i file di sistema, ottimizza i dischi,
#   poi esegue l'analisi completa e la modalita' automatica.
#   Ogni operazione deve finire con OK o PARZIALE.
#
#   SOLO SULLE MACCHINE DI GITHUB ACTIONS, che vengono buttate via
#   dopo ogni prova: su un computer vero cancellerebbe cache, cestino
#   e file temporanei. Fuori da GitHub si rifiuta di partire.
# ============================================================

# Protezione: queste due variabili le imposta GitHub Actions sulle
# proprie macchine; su un runner installato su un computer qualsiasi
# RUNNER_ENVIRONMENT vale "self-hosted", e anche li' la prova non parte.
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted') {
    Write-Host 'Questa prova cancella davvero cache, cestino e file temporanei.'
    Write-Host 'Gira solo sulle macchine usa e getta di GitHub Actions.'
    exit 2
}

$ErrorActionPreference = 'Continue'
$Radice = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$script:Pass = 0; $script:Fail = 0
function Ok     { param($m) $script:Pass++; Write-Host ('  [ok]  ' + $m) }
function Ko     { param($m) $script:Fail++; Write-Host ('  [KO]  ' + $m) }
function Titolo { param($t) Write-Host ''; Write-Host ('=== ' + $t + ' ===') }

. (Join-Path $Radice 'lib\Common.ps1')
. (Join-Path $Radice 'lib\Core.ps1')
. (Join-Path $Radice 'lib\Tasks.ps1')
. (Join-Path $Radice 'lib\Analysis.ps1')
. (Join-Path $Radice 'lib\ConsoleUI.ps1')
$cartellaLog = Join-Path $env:TEMP 'tb_reale_log'
$null = Initialize-Log -Directory $cartellaLog -Keep 3

if (Test-Admin) { Ok 'privilegi di amministratore' } else { Ko 'privilegi di amministratore non presenti' }

# Escluse di proposito:
#   rete (rinnovo IP, Winsock, TCP/IP, IPv6): la macchina perderebbe
#     il collegamento con GitHub, o servirebbe un riavvio;
#   punto di ripristino: su Windows Server non esiste;
#   DISM /RestoreHealth, Windows Update, winget: durano molto e
#     dipendono da servizi esterni.
$operazioni = @(
    'clean_temp_user','clean_temp_system','clean_temp_allusers','clean_trash','clean_wer',
    'clean_crashdump','clean_deliveryopt','clean_fontcache','clean_browsercache','clean_thumbcache',
    'clean_wucache','clean_appcache','clean_devcache','clean_windowsold','clean_prefetch',
    'clean_componentstore','net_flushdns','net_arpcache','net_registerdns','maint_retrim','maint_sfc'
)

Titolo 'Operazioni vere'
foreach ($id in $operazioni) {
    $t = Get-Task -Id $id
    if (-not $t) { Ko ($id + ': non esiste nel registro'); continue }
    # L'output delle operazioni va nel log, non qui: interessa l'esito.
    $r = Invoke-Task -Task $t 6>$null
    switch ($r.Esito) {
        'OK'       { Ok ('{0} ({1} liberati, {2:N0}s)' -f $id, (Format-Bytes $r.Bytes), $r.Durata.TotalSeconds) }
        'PARZIALE' {
            # Un avviso non e' per forza un difetto (file in uso,
            # componenti assenti su Windows Server): si mostra.
            Ok ($id + ': PARZIALE, avvisi da leggere qui sotto')
            foreach ($e in $r.Errors) { Write-Host ('      ' + $e) }
        }
        default    {
            Ko ('{0}: {1} - {2}' -f $id, $r.Esito, $r.HardFail)
            foreach ($e in $r.Errors) { Write-Host ('      ' + $e) }
        }
    }
}

Titolo 'Analisi completa e report'
$report = Join-Path $env:TEMP 'tb_reale_report.html'
$script:TB_REPORT = $report
$eccezione = $null
try { Show-Analisi 6>$null | Out-Null } catch { $eccezione = $_.Exception.Message }
Export-Report
$script:TB_REPORT = ''
if ($eccezione) { Ko ('analisi completa: eccezione - ' + $eccezione) } else { Ok 'analisi completa senza eccezioni' }
$n = 0
if (Test-Path -LiteralPath $report) { $n = ([regex]::Matches((Get-Content -LiteralPath $report -Raw), '<h2>')).Count }
if ($n -gt 5) { Ok ('report HTML con {0} sezioni' -f $n) } else { Ko 'report HTML vuoto o incompleto' }

Titolo 'Modalita'' automatica vera'
$auto = Join-Path $env:TEMP 'tb_reale_auto.html'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Radice 'Toolbox.ps1') -Auto -NoElevate -Report $auto *> (Join-Path $env:TEMP 'tb_reale_auto.txt')
$rc = $LASTEXITCODE
if ($rc -in 0, 1) { Ok ('Toolbox.ps1 -Auto: uscita {0}' -f $rc) } else {
    Ko ('Toolbox.ps1 -Auto: uscita {0}' -f $rc)
    Get-Content (Join-Path $env:TEMP 'tb_reale_auto.txt') -Tail 15 | ForEach-Object { Write-Host ('      ' + $_) }
}
if ((Test-Path -LiteralPath $auto) -and (Get-Item -LiteralPath $auto).Length -gt 0) { Ok 'report della modalita'' automatica scritto' } else { Ko 'report della modalita'' automatica mancante' }

Write-Host ''
Write-Host '============================================'
Write-Host ("  superati: $script:Pass    falliti: $script:Fail")
Write-Host '============================================'
Write-Host ''
if ($script:Fail -gt 0) { exit 1 }
exit 0
