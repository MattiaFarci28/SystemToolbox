# ============================================================
#   Suite di collaudo - System Toolbox per Windows
#
#   Verifica cio' che si puo' verificare senza modificare il
#   sistema: integrita' del registro, formattazione, motore,
#   cancellazione su cartella di prova, configurazione, report,
#   JSON e storico.
#
#   NON esegue operazioni reali sul sistema.
#
#   Uso:  powershell -ExecutionPolicy Bypass -File test\Collaudo.ps1
#   Esce con 0 se tutto passa, 1 altrimenti.
# ============================================================

$Radice = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$script:Pass = 0
$script:Fail = 0

function Ok    { param($m) $script:Pass++; Write-Host ('  [ok]  ' + $m) -ForegroundColor Green }
function Ko    { param($m) $script:Fail++; Write-Host ('  [KO]  ' + $m) -ForegroundColor Red }
function Check { param($n, $a, $b) if ("$a" -eq "$b") { Ok $n } else { Ko ("$n  (atteso '$b', ottenuto '$a')") } }
function Titolo{ param($t) Write-Host ''; Write-Host ("=== $t ===") -ForegroundColor Cyan }

# ------------------------------------------------------------
Titolo 'Sintassi'
foreach ($f in @('Toolbox.ps1','lib\Common.ps1','lib\Core.ps1','lib\Tasks.ps1',
                 'lib\Analysis.ps1','lib\ConsoleUI.ps1','lib\GuiUI.ps1')) {
    $e = $null; $t = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Radice $f), [ref]$t, [ref]$e)
    if ($e -and $e.Count -gt 0) { Ko $f } else { Ok $f }
}

# ------------------------------------------------------------
Titolo 'Moduli caricati dal thread della GUI'
# Il runspace di lavoro della GUI ha uno spazio dei nomi tutto suo
# e carica i moduli per conto proprio. Se il suo elenco diverge da
# quello di Toolbox.ps1, la funzione che manca si scopre solo a
# video, a meta' di un'analisi. Questo controllo confronta i due.
$srcToolbox = Get-Content (Join-Path $Radice 'Toolbox.ps1') -Raw
$srcGui     = Get-Content (Join-Path $Radice 'lib\GuiUI.ps1') -Raw

$modToolbox = @()
if ($srcToolbox -match "foreach \(\`$modulo in @\(([^)]+)\)\)") {
    $modToolbox = ($matches[1] -split ',') | ForEach-Object { $_.Trim().Trim("'") } | Sort-Object
}
# Il separatore si cerca con un punto: nelle stringhe di PowerShell
# la barra rovesciata non e' un carattere di escape, e contarle per
# arrivare alla regex giusta e' una fonte di errori inutile.
$modGui = @([regex]::Matches($srcGui, "Join-Path .radice 'lib.([A-Za-z]+\.ps1)'") |
            ForEach-Object { $_.Groups[1].Value }) | Sort-Object -Unique

if ($modToolbox.Count -eq 0) { Ko 'elenco moduli di Toolbox.ps1 non riconosciuto' }
elseif ($modGui.Count -eq 0) { Ko 'elenco moduli del worker GUI non riconosciuto' }
elseif ((Compare-Object $modToolbox $modGui) -eq $null) {
    Ok ("GUI e menu caricano gli stessi $($modGui.Count) moduli")
} else {
    Ko ("elenchi diversi - Toolbox: $($modToolbox -join ',')  GUI: $($modGui -join ',')")
}

foreach ($m in @('Common.ps1','Core.ps1','Tasks.ps1','Analysis.ps1','ConsoleUI.ps1')) {
    . (Join-Path $Radice ('lib\' + $m))
}
Initialize-Log -Directory (Join-Path $env:TEMP 'tb_collaudo') -Keep 3 | Out-Null

# ------------------------------------------------------------
Titolo 'Registro delle operazioni'
$tutti = @(Get-AllTask)
if ($tutti.Count -gt 0) { Ok ("$($tutti.Count) operazioni registrate") } else { Ko 'registro vuoto' }

$err = 0
foreach ($t in $tutti) {
    if (-not $t.ContainsKey('Stima') -or $t.Stima -le 0) { Ko ('stima mancante: ' + $t.Id); $err = 1 }
    if ($t.Livello -notin @('Sicuro','Avanzato','Riavvio')) { Ko ('livello ignoto: ' + $t.Id); $err = 1 }
    if ($t.Id -notmatch '^[a-z0-9_]+$') { Ko ('id non uniformato: ' + $t.Id); $err = 1 }
}
if ($err -eq 0) { Ok 'struttura del registro integra' }

$dupli = @($tutti | Group-Object { $_.Id } | Where-Object { $_.Count -gt 1 })
if ($dupli.Count -eq 0) { Ok 'nessun id duplicato' } else { Ko ("id duplicati: $($dupli.Count)") }

$setErr = 0
foreach ($s in @('PuliziaSicura','PuliziaAvanzata','RetePulizia','ReteReset','Manutenzione')) {
    foreach ($t in (Get-TaskSet -Nome $s)) {
        if (-not $t) { Ko ("insieme $s cita un id inesistente"); $setErr = 1 }
    }
}
if ($setErr -eq 0) { Ok 'insiemi predefiniti coerenti' }
# I livelli devono rispettare la loro definizione: un insieme che
# si chiama "sicura" contiene solo voci [sicuro], e nessuna voce
# [sicuro] puo' fermare servizi. Nasce da un errore vero: la cache
# dei font era [sicuro] pur fermando il servizio FontCache.
$fuori = @(Get-TaskSet -Nome 'PuliziaSicura' | Where-Object {
    $_.Livello -ne 'Sicuro' -or ($_.ContainsKey('Sconsigliato') -and $_.Sconsigliato) })
Check 'Pulizia sicura contiene solo voci [sicuro]' (($fuori | ForEach-Object { $_.Id }) -join ' ') ''
$fermaServizi = @($tutti | Where-Object { $_.Livello -eq 'Sicuro' -and "$($_.Azione)" -match 'Stop-ServiceSet|Stop-Service\b' })
Check 'nessuna voce [sicuro] ferma servizi' (($fermaServizi | ForEach-Object { $_.Id }) -join ' ') ''

# ------------------------------------------------------------
Titolo 'Formattazione'
Check 'Format-Bytes 0'          (Format-Bytes 0)          '0 B'
Check 'Format-Bytes 1024'       (Format-Bytes 1024)       '1 KB'
Check 'Format-Stima 3'          (Format-Stima 3)          'immediato'
Check 'Format-Stima 45'         (Format-Stima 45)         'circa 45 secondi'
Check 'Format-Stima 60'         (Format-Stima 60)         'circa 1 minuto'
if ((Format-Bytes 1073741824) -match '^1[.,]00 GB$') { Ok 'Format-Bytes 1 GB' } else { Ko 'Format-Bytes 1 GB' }

# ------------------------------------------------------------
Titolo 'Configurazione'
$cfgFile = Join-Path $env:TEMP ('tb_cfg_{0}.conf' -f $PID)
@'
# commento
disco_critico=95
colori=daltonici
chiave_inventata=qualcosa
disco_avviso=non_un_numero
'@ | Set-Content -LiteralPath $cfgFile -Encoding UTF8
Import-Configurazione $cfgFile
Check 'valore numerico letto'         $script:CFG['disco_critico'] '95'
Check 'valore testuale ammesso'       $script:CFG['colori']        'daltonici'
Check 'valore non numerico rifiutato' $script:CFG['disco_avviso']  '80'
Remove-Item $cfgFile -Force -ErrorAction SilentlyContinue
$script:CFG['colori'] = 'auto'; $script:CFG['disco_critico'] = 90

# ------------------------------------------------------------
Titolo 'Motore dei task: i tre esiti'
$tOk   = @{ Id='prova_ok';   Nome='Prova'; Categoria='Test'; Livello='Sicuro'; Stima=1; Descrizione='x'
            Azione={ param($c) $c.Note('ok'); $c.Bytes = 1048576 } }
$tWarn = @{ Id='prova_warn'; Nome='Prova'; Categoria='Test'; Livello='Sicuro'; Stima=1; Descrizione='x'
            Azione={ param($c) $c.Fail('problema') } }
$tBoom = @{ Id='prova_boom'; Nome='Prova'; Categoria='Test'; Livello='Sicuro'; Stima=1; Descrizione='x'
            Azione={ param($c) throw 'errore simulato' } }
Check 'task senza problemi' (Invoke-Task -Task $tOk).Esito   'OK'
Check 'task con avvisi'     (Invoke-Task -Task $tWarn).Esito 'PARZIALE'
Check 'task che fallisce'   (Invoke-Task -Task $tBoom).Esito 'FALLITO'
Check 'codice di uscita dopo un fallimento' (Get-EsitoCodice) '2'
$script:TB_EXIT = 0

# ------------------------------------------------------------
Titolo 'Cancellazione a scansione singola'
$sb = Join-Path $env:TEMP ('tb_sandbox_{0}' -f $PID)
New-Item -ItemType Directory -Path (Join-Path $sb 'sotto') -Force | Out-Null
1..3 | ForEach-Object { Set-Content -Path (Join-Path $sb "f$_.bin") -Value ('x' * 100000) }
Set-Content -Path (Join-Path $sb 'sotto\g.bin') -Value ('y' * 20000)

$ctx = New-TaskContext -DryRun
Clear-FolderContent -Path $sb -Ctx $ctx -Etichetta 'prova' *> $null
$rimasti = @(Get-ChildItem -LiteralPath $sb -Force).Count
Check 'simulazione non cancella' $rimasti '4'
if ($ctx.Bytes -gt 0) { Ok ("simulazione conta i byte ($(Format-Bytes $ctx.Bytes))") } else { Ko 'simulazione non conta i byte' }

$ctx = New-TaskContext
Clear-FolderContent -Path $sb -Ctx $ctx -Etichetta 'prova' *> $null
$rimasti = @(Get-ChildItem -LiteralPath $sb -Force -ErrorAction SilentlyContinue).Count
Check 'cancellazione completa' $rimasti '0'
Check 'elementi contati'       $ctx.Items '4'
if ($ctx.Bytes -gt 300000) { Ok ("byte liberati coerenti ($(Format-Bytes $ctx.Bytes))") } else { Ko ("byte liberati incoerenti: $($ctx.Bytes)") }
Remove-Item $sb -Recurse -Force -ErrorAction SilentlyContinue

# ------------------------------------------------------------
Titolo 'Report e JSON'
$script:TB_SISTEMA = 'sistema di prova'
$script:TB_REPORT = Join-Path $env:TEMP ('tb_report_{0}.md' -f $PID)
$script:TB_REPBUF.Clear()
Write-Section 'SEZIONE DI PROVA' | Out-Null
Write-Kv 'Chiave' 'valore' | Out-Null
Write-Warn 'un avviso' | Out-Null
Export-Report
if ((Get-Content $script:TB_REPORT -Raw) -match '## SEZIONE DI PROVA') { Ok 'report Markdown generato dal rendering' } else { Ko 'report Markdown incompleto' }
Remove-Item $script:TB_REPORT -Force -ErrorAction SilentlyContinue

$script:TB_REPORT = Join-Path $env:TEMP ('tb_report_{0}.html' -f $PID)
Export-Report
if ((Get-Content $script:TB_REPORT -Raw) -match '<h2>SEZIONE DI PROVA</h2>') { Ok 'report HTML generato' } else { Ko 'report HTML incompleto' }
Remove-Item $script:TB_REPORT -Force -ErrorAction SilentlyContinue
$script:TB_REPORT = ''

$script:TB_JSON = $true
$script:TB_JSON_OPS.Clear(); $script:TB_JSON_AVVISI.Clear()
Add-JsonOperazione 'prova_id' 'Nome con "virgolette"' 'OK' 1024 2 0
Add-JsonAvviso 'un avviso'
$j = Write-Json
try { $o = $j | ConvertFrom-Json; Ok ('JSON valido, ' + ($o.PSObject.Properties.Name.Count) + ' chiavi') }
catch { Ko 'JSON non valido' }
$script:TB_JSON = $false

# ------------------------------------------------------------
Titolo 'Storico e confronto'
$st = Join-Path $env:TEMP ('tb_storico_{0}.txt' -f $PID)
Initialize-Storico $st
$vecchio = [int][double]::Parse((Get-Date -UFormat %s)) - 172800
"$vecchio|1000000|3" | Set-Content -LiteralPath $st -Encoding UTF8
$c = Compare-Storico
if ($c -and $c.Giorni -eq 2) { Ok ("confronto con l'esecuzione precedente ($($c.Giorni) giorni)") } else { Ko 'confronto non prodotto' }
Remove-Item $st -Force -ErrorAction SilentlyContinue

# ------------------------------------------------------------
Titolo 'Configurazione: ogni chiave dichiarata e'' documentata'
# Nasce da una dimenticanza vera: `tema` e `analisi_aggiornamenti`
# esistevano nel codice ma non nel file d'esempio.
$sorgente = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\lib\Common.ps1') -Raw
$blocco = [regex]::Match($sorgente, '(?s)\$script:CFG = @\{(.*?)\r?\n\}').Groups[1].Value
$dich = @([regex]::Matches($blocco, '(?m)^\s+([a-z_]+)\s*=') | ForEach-Object { $_.Groups[1].Value } | Sort-Object)
$doc  = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\Toolbox.conf.esempio') |
        Where-Object { $_ -match '^[a-z_]+=' } | ForEach-Object { ($_ -split '=')[0] } | Sort-Object)
Check 'chiavi dichiarate ma non documentate' (($dich | Where-Object { $doc -notcontains $_ }) -join ' ') ''
Check 'chiavi documentate ma non dichiarate' (($doc | Where-Object { $dich -notcontains $_ }) -join ' ') ''
Check 'il parser ha trovato le chiavi' ($dich.Count -gt 5) $true

# ------------------------------------------------------------
Titolo 'Rilancio: tutti i parametri sopravvivono'
# Prima l'elenco da inoltrare era scritto a mano: -Report, -Json,
# -Config, -Daltonici e -NoColor si perdevano quando lo script si
# rilanciava per l'elevazione. Qui si prendono TUTTI i parametri
# dichiarati in Toolbox.ps1 e si verifica che arrivino.
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Radice 'Toolbox.ps1'), [ref]$null, [ref]$null)
$finti = @{}
foreach ($par in $ast.ParamBlock.Parameters) {
    $nome = $par.Name.VariablePath.UserPath
    if ($par.StaticType -eq [switch]) { $finti[$nome] = [switch]$true } else { $finti[$nome] = 'valore.txt' }
}
$arg = Get-ArgomentiRilancio -Parametri $finti -Script 'C:\x\Toolbox.ps1'
$persi = @($finti.Keys | Where-Object { $arg -notcontains ('-' + $_) })
Check 'nessun parametro perso nel rilancio' ($persi -join ' ') ''
if ($finti.Count -ge 10) { Ok ("$($finti.Count) parametri dichiarati, tutti inoltrati") } else { Ko 'parametri di Toolbox.ps1 non riconosciuti' }

$arg = Get-ArgomentiRilancio -Parametri @{ Report = 'r.html'; DryRun = [switch]$false } -Script 'C:\x\Toolbox.ps1'
$atteso = '"' + (Join-Path (Get-Location).ProviderPath 'r.html') + '"'
Check 'percorso relativo reso assoluto' ($arg[[array]::IndexOf($arg, '-Report') + 1]) $atteso
Check 'interruttore spento non inoltrato' ($arg -contains '-DryRun') $false
$arg = Get-ArgomentiRilancio -Parametri @{ Config = 'D:\conf\a.conf' } -Script 'C:\x\Toolbox.ps1'
Check 'percorso assoluto invariato' ($arg[[array]::IndexOf($arg, '-Config') + 1]) '"D:\conf\a.conf"'

# ------------------------------------------------------------
Titolo 'Configurazione: ogni chiave ha un effetto o e'' dichiarata non usata'
# Nasce da un difetto vero: sei soglie su undici erano documentate
# ma nessuna riga le leggeva, e il valore era scritto fisso nel
# codice. Cambiarle nel file non aveva alcun effetto.
$sorgenti = (Get-ChildItem -LiteralPath (Join-Path $Radice 'lib') -Filter '*.ps1' | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
$sorgenti += "`n" + (Get-Content -LiteralPath (Join-Path $Radice 'Toolbox.ps1') -Raw)
$conf = @(Get-Content -LiteralPath (Join-Path $Radice 'Toolbox.conf.esempio'))
$senzaEffetto = @()
foreach ($k in $script:CFG.Keys) {
    if ($sorgenti -match ("CFG\['" + $k + "'\]")) { continue }
    $i = [array]::FindIndex([string[]]$conf, [Predicate[string]]{ param($r) $r -like ($k + '=*') })
    $blocco = ''
    for ($j = $i - 1; $j -ge 0 -and $conf[$j].StartsWith('#'); $j--) { $blocco = $conf[$j] + ' ' + $blocco }
    if ($blocco -match '(?i)non usat') { continue }
    $senzaEffetto += $k
}
Check 'nessuna chiave documentata senza effetto' (($senzaEffetto | Sort-Object) -join ' ') ''

# ------------------------------------------------------------
Titolo 'Rotazione dei log'
# Prima Toolbox.ps1 non passava -Keep, e con Keep a 0
# "Select-Object -Skip 0" cancellava tutti i log a ogni avvio:
# ne restava sempre uno solo.
Close-LogWriter
$salvaLog = $script:LogFile
$dirLog = Join-Path $env:TEMP ('tb_rot_{0}' -f $PID)
New-Item -ItemType Directory -Path $dirLog -Force | Out-Null
foreach ($n in 1..5) {
    $f = Join-Path $dirLog ('toolbox_2020-01-0{0}_10-00-00.log' -f $n)
    Set-Content -LiteralPath $f -Value 'vecchio'
    (Get-Item -LiteralPath $f).LastWriteTime = (Get-Date).AddDays(-10 + $n)
}
$nuovo = Initialize-Log -Directory $dirLog -Keep 3
Check 'Keep 3: restano 3 file' (@(Get-ChildItem -LiteralPath $dirLog -Filter 'toolbox_*.log').Count) 3
Check 'Keep 3: il log nuovo resta' (Test-Path -LiteralPath $nuovo) $true
# Il nome del log e' al secondo: senza attesa le due chiamate
# produrrebbero lo stesso file.
Start-Sleep -Milliseconds 1100
$nuovo = Initialize-Log -Directory $dirLog -Keep 0
Check 'Keep 0: non cancella niente' (@(Get-ChildItem -LiteralPath $dirLog -Filter 'toolbox_*.log').Count) 4
$sorgToolbox = Get-Content -LiteralPath (Join-Path $Radice 'Toolbox.ps1') -Raw
Check 'Toolbox.ps1 passa log_da_conservare' ($sorgToolbox -match "Initialize-Log[^\r\n]*-Keep \`$script:CFG\['log_da_conservare'\]") $true
Remove-Item -LiteralPath $dirLog -Recurse -Force -ErrorAction SilentlyContinue
$script:LogFile = $salvaLog

# ------------------------------------------------------------
Titolo 'Pulizia: i collegamenti non vengono seguiti'
# La pulizia gira come amministratore anche sui profili degli altri
# utenti. Un collegamento in una cartella Temp che punta altrove non
# deve portare la cancellazione nella destinazione.
$radiceProva = Join-Path $env:TEMP ('tb_link_{0}' -f $PID)
$bersaglio = Join-Path $radiceProva 'bersaglio'
$pulire    = Join-Path $radiceProva 'da_pulire'
New-Item -ItemType Directory -Path $bersaglio, (Join-Path $pulire 'sotto\profondo') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $bersaglio 'prezioso.txt') -Value 'non toccare'
Set-Content -LiteralPath (Join-Path $pulire 'a.tmp') -Value 'x'
Set-Content -LiteralPath (Join-Path $pulire 'sotto\profondo\b.tmp') -Value 'x'
$solaLettura = Join-Path $pulire 'sotto\sola_lettura.tmp'
Set-Content -LiteralPath $solaLettura -Value 'x'
(Get-Item -LiteralPath $solaLettura).IsReadOnly = $true
New-Item -ItemType Junction -Path (Join-Path $pulire 'collegamento') -Target $bersaglio | Out-Null
New-Item -ItemType Junction -Path (Join-Path $pulire 'sotto\collegamento2') -Target $bersaglio | Out-Null

$c = New-TaskContext
Clear-FolderContent -Path $pulire -Ctx $c -Etichetta 'prova'
Check 'la destinazione del collegamento resta intatta' (Test-Path -LiteralPath (Join-Path $bersaglio 'prezioso.txt')) $true
Check 'la cartella da pulire e'' vuota' (@(Get-ChildItem -LiteralPath $pulire -Force).Count) 0
Check 'anche i file in sola lettura sono rimossi' (Test-Path -LiteralPath $solaLettura) $false
Check 'nessun errore' (@($c.Errors).Count) 0

# Un file aperto non blocca il resto: si prosegue e si segnala.
New-Item -ItemType Directory -Path (Join-Path $pulire 'cartella') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $pulire 'cartella\aperto.tmp') -Value 'x'
Set-Content -LiteralPath (Join-Path $pulire 'cartella\libero.tmp') -Value 'x'
$aperto = [System.IO.File]::Open((Join-Path $pulire 'cartella\aperto.tmp'), 'Open', 'Read', 'None')
try {
    $esito = Remove-AlberoSicuro -Voce (Get-Item -LiteralPath (Join-Path $pulire 'cartella'))
    Check 'con un file aperto segnala la rimozione parziale' $esito $false
    Check 'gli altri file vengono rimossi comunque' (Test-Path -LiteralPath (Join-Path $pulire 'cartella\libero.tmp')) $false
} finally { $aperto.Dispose() }

$sorgTasks = Get-Content -LiteralPath (Join-Path $Radice 'lib\Tasks.ps1') -Raw
Check 'Windows.old non usa takeown ne'' icacls' ($sorgTasks -match '(?m)^(?!\s*#).*(takeown|icacls)') $false
$sorgTutto = ((Get-ChildItem -LiteralPath (Join-Path $Radice 'lib') -Filter '*.ps1' | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n")
Check 'nessun Remove-Item -Recurse nel codice' ($sorgTutto -match '(?m)^(?!\s*#).*Remove-Item[^\r\n]*-Recurse') $false

Remove-Item -LiteralPath $radiceProva -Recurse -Force -ErrorAction SilentlyContinue

# ------------------------------------------------------------
Write-Host ''
Write-Host '============================================'
Write-Host ("  superati: $script:Pass    falliti: $script:Fail")
Write-Host '============================================'
Write-Host ''
if ($script:Fail -gt 0) { exit 1 }
exit 0
