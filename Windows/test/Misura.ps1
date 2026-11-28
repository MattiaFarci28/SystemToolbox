# ============================================================
#   SYSTEM TOOLBOX - misura dei tempi (Windows)
#
#   Uso:  powershell -ExecutionPolicy Bypass -File test\Misura.ps1
#
#   Lancia l'analisi completa e l'analisi rapida come le lancia lo
#   strumento, con un cronometro attorno a ogni sezione, e stampa
#   le sezioni dalla piu' lenta. Serve a sapere dove si perde tempo
#   prima di ottimizzare, e a confrontare il prima e il dopo.
#
#   Non modifica lo strumento: le sezioni vengono "avvolte" solo in
#   memoria, dentro questo script. L'analisi e' in sola lettura.
# ============================================================

$Radice = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. (Join-Path $Radice 'lib\Common.ps1')
. (Join-Path $Radice 'lib\Core.ps1')
. (Join-Path $Radice 'lib\Tasks.ps1')
. (Join-Path $Radice 'lib\Analysis.ps1')
. (Join-Path $Radice 'lib\ConsoleUI.ps1')
$null = Initialize-Log -Directory (Join-Path $env:TEMP 'tb_misura_log') -Keep 3

# Le sezioni: tutte le funzioni dello strumento chiamate da
# Show-Analisi. Su Windows il tempo si spende soprattutto nelle
# Get-* (raccolta dei dati), non nelle Show-* (disegno a schermo).
# I cmdlet di sistema (Get-Date, ...) non sono funzioni e vengono
# esclusi piu' sotto da Get-Command -CommandType Function.
$corpo = (Get-Command Show-Analisi -CommandType Function).ScriptBlock.ToString()
$sezioni = @([regex]::Matches($corpo, '\b(?:Show|Get|Test|Start|Compare)-[A-Z][A-Za-z]+') | ForEach-Object { $_.Value } |
             Where-Object { $_ -ne 'Show-Analisi' } | Sort-Object -Unique)

# Ogni sezione viene sostituita da una che misura il tempo e poi
# chiama l'originale con gli stessi argomenti.
$script:Tempi = New-Object System.Collections.ArrayList
foreach ($nome in $sezioni) {
    $cmd = Get-Command $nome -CommandType Function -ErrorAction SilentlyContinue
    if (-not $cmd) { continue }
    $var = 'Orig_' + ($nome -replace '-', '_')
    Set-Variable -Name $var -Scope Script -Value $cmd.ScriptBlock
    $codice = ('$sw = [Diagnostics.Stopwatch]::StartNew(); & $script:{0} @args; $sw.Stop(); ' +
               '[void]$script:Tempi.Add([pscustomobject]@{{ Sezione = ''{1}''; Ms = $sw.ElapsedMilliseconds }})') -f $var, $nome
    Set-Item -Path ('function:script:' + $nome) -Value ([scriptblock]::Create($codice))
}

function Write-Misura {
    param([string]$Titolo, [long]$TotaleMs)
    Write-Output ''
    Write-Output ('=== {0}: {1:N3} s in totale ===' -f $Titolo, ($TotaleMs / 1000))
    $script:Tempi | Sort-Object Ms -Descending | ForEach-Object {
        Write-Output ('  {0,10:N3} s   {1}' -f ($_.Ms / 1000), $_.Sezione)
    }
}

# Avvio dello strumento: caricare le librerie e uscire.
$sw = [Diagnostics.Stopwatch]::StartNew()
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Radice 'Toolbox.ps1') -Versione -NoElevate *> $null
$sw.Stop()
Write-Output ('=== Avvio (Toolbox.ps1 -Versione): {0:N3} s ===' -f ($sw.ElapsedMilliseconds / 1000))

foreach ($rapida in $false, $true) {
    $script:Tempi.Clear()
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Show-Analisi -Rapida:$rapida 6> $null | Out-Null
    $sw.Stop()
    $titolo = 'Analisi completa'
    if ($rapida) { $titolo = 'Analisi rapida' }
    Write-Misura -Titolo $titolo -TotaleMs $sw.ElapsedMilliseconds
}
exit 0
