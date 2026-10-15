# ============================================================
#   Core.ps1 - Motore comune
#   Log, esecuzione dei task, helper di sistema.
#
#   Questo file NON conosce l'interfaccia utente: viene usato
#   sia dal menu console sia (in seguito) dalla GUI WPF.
#   L'unico punto di contatto con la UI e' Write-Detail, che
#   si puo' reindirizzare con Set-DetailHandler.
#
#   Nota: tutto il sorgente e' volutamente ASCII puro (niente
#   lettere accentate) per evitare problemi di codifica tra
#   Windows PowerShell 5.1, conhost e Windows Terminal.
# ============================================================

Set-StrictMode -Version 1.0

# ---------- Stato del modulo -------------------------------
$script:LogFile        = $null
$script:DetailHandler  = { param($m) Write-Host ('      ' + $m) -ForegroundColor DarkGray }

# ============================================================
#   LOG
# ============================================================

function Initialize-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Directory,
        [int]$Keep = 0
    )
    if (-not (Test-Path -LiteralPath $Directory)) {
        New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    }
    $stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $script:LogFile = Join-Path $Directory ('toolbox_{0}.log' -f $stamp)
    New-Item -ItemType File -Path $script:LogFile -Force | Out-Null

    # Rotazione: conserva solo gli ultimi $Keep file di log.
    # Con $Keep a 0 non si cancella niente. Prima "Select-Object
    # -Skip 0" li eliminava TUTTI, compreso quello appena creato, e
    # siccome Toolbox.ps1 non passava -Keep ogni avvio cancellava
    # la storia dei log: ne restava sempre uno solo.
    if ($Keep -gt 0) {
        Get-ChildItem -LiteralPath $Directory -Filter 'toolbox_*.log' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -Skip $Keep |
            Where-Object { $_.FullName -ne $script:LogFile } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }

    return $script:LogFile
}

function Get-LogPath { return $script:LogFile }

# Serve al thread di lavoro della GUI: gira in un runspace separato,
# quindi ha un proprio $script:LogFile, e deve agganciarsi al file di
# log gia' aperto dalla finestra invece di crearne un secondo.
function Set-LogPath {
    param([string]$Percorso)
    Close-LogWriter
    $script:LogFile = $Percorso
}

# ------------------------------------------------------------
#   Scrittura del log
#   Add-Content apre e chiude il file a ogni riga: in una
#   sessione verbosa sono centinaia di aperture. Qui il file
#   resta aperto per tutta la sessione.
#
#   Condivisione: la GUI scrive sullo stesso file da un runspace
#   separato, quindi si apre con FileShare ReadWrite e si forza
#   lo scarico a ogni riga. Se l'apertura non riesce si ricade
#   su Add-Content, che tollera qualunque concorrenza.
# ------------------------------------------------------------
$script:LogWriter = $null

function Open-LogWriter {
    if ($script:LogWriter -or -not $script:LogFile) { return }
    try {
        $fs = New-Object System.IO.FileStream($script:LogFile,
                  [System.IO.FileMode]::Append,
                  [System.IO.FileAccess]::Write,
                  [System.IO.FileShare]::ReadWrite)
        $script:LogWriter = New-Object System.IO.StreamWriter($fs, [System.Text.UTF8Encoding]::new($false))
        $script:LogWriter.AutoFlush = $true
    } catch { $script:LogWriter = $null }
}

function Close-LogWriter {
    if ($script:LogWriter) {
        try { $script:LogWriter.Flush(); $script:LogWriter.Dispose() } catch { }
        $script:LogWriter = $null
    }
}

function Write-Log {
    param(
        [string]$Message = '',
        [ValidateSet('INFO','OK','WARN','FAIL','STEP')][string]$Level = 'INFO'
    )
    if (-not $script:LogFile) { return }
    $line = '[{0}] [{1,-4}] {2}' -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message
    if (-not $script:LogWriter) { Open-LogWriter }
    if ($script:LogWriter) {
        try { $script:LogWriter.WriteLine($line); return } catch { Close-LogWriter }
    }
    try { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}

# ============================================================
#   PONTE VERSO LA UI
#   La console imposta il proprio handler; la futura GUI
#   impostera' il suo (append su una TextBox) senza toccare
#   nulla del motore.
# ============================================================

function Set-DetailHandler {
    param([Parameter(Mandatory=$true)][scriptblock]$Handler)
    $script:DetailHandler = $Handler
}

function Write-Detail {
    param([string]$Message = '')
    if ($script:DetailHandler) { & $script:DetailHandler $Message }
}

# ============================================================
#   HELPER GENERICI
# ============================================================

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Format-Bytes {
    param([double]$Bytes = 0)
    $sign = ''
    if ($Bytes -lt 0) { $sign = '-'; $Bytes = [math]::Abs($Bytes) }
    if     ($Bytes -ge 1GB) { return ('{0}{1:N2} GB' -f $sign, ($Bytes / 1GB)) }
    elseif ($Bytes -ge 1MB) { return ('{0}{1:N1} MB' -f $sign, ($Bytes / 1MB)) }
    elseif ($Bytes -ge 1KB) { return ('{0}{1:N0} KB' -f $sign, ($Bytes / 1KB)) }
    else                    { return ('{0}{1:N0} B'  -f $sign, $Bytes) }
}

# Traduce una stima in secondi in una frase leggibile. Sopra il quarto
# d'ora si usa una forbice: dare un numero secco per SFC o DISM, che
# dipendono dallo stato del disco, sarebbe falsa precisione.
function Format-Stima {
    param([int]$Secondi = 0)
    if ($Secondi -le 5)  { return 'immediato' }
    if ($Secondi -lt 60) { return ('circa {0} secondi' -f $Secondi) }
    if ($Secondi -ge 600) {
        $a = [math]::Round($Secondi / 60 * 0.6)
        $b = [math]::Round($Secondi / 60 * 1.4)
        return ('da {0} a {1} minuti' -f $a, $b)
    }
    $min = [math]::Round($Secondi / 60)
    if ($min -le 1) { return 'circa 1 minuto' }
    return ('circa {0} minuti' -f $min)
}

function Measure-FolderBytes {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue)) { return [long]0 }
    try {
        $sum = (Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum
        if ($null -eq $sum) { return [long]0 }
        return [long]$sum
    } catch { return [long]0 }
}

# ============================================================
#   CACHE DELLE QUERY CIM
#   Win32_OperatingSystem veniva interrogata tre volte durante
#   un'analisi (riepilogo, memoria, supporto) e ogni query WMI
#   costa decine di millisecondi. Qui il risultato viene tenuto
#   per la durata dell'analisi.
#
#   ATTENZIONE: la cache va svuotata prima di ogni analisi e non
#   va MAI usata per lo spazio libero, che cambia proprio a
#   causa delle operazioni che lo strumento esegue.
# ============================================================
$script:CimCache = @{}

function Get-CimCached {
    param(
        [Parameter(Mandatory=$true)][string]$Class,
        [string]$Filter = '',
        [string]$Namespace = ''
    )
    $chiave = '{0}|{1}|{2}' -f $Class, $Filter, $Namespace
    if ($script:CimCache.ContainsKey($chiave)) { return $script:CimCache[$chiave] }

    $r = @()
    try {
        $p = @{ ClassName = $Class; ErrorAction = 'Stop' }
        if ($Filter)    { $p['Filter'] = $Filter }
        if ($Namespace) { $p['Namespace'] = $Namespace }
        $r = @(Get-CimInstance @p)
    } catch { $r = @() }
    $script:CimCache[$chiave] = $r
    return $r
}

function Clear-CimCache { $script:CimCache = @{} }

# ------------------------------------------------------------
#   Misura con budget di tempo.
#   Su una Windows.old da decine di GB l'enumerazione ricorsiva
#   puo' richiedere minuti, e un'analisi che si blocca senza
#   spiegazioni e' peggio di un dato approssimato. Qui si misura
#   in un runspace separato e, scaduto il tempo, si restituisce
#   quanto raccolto dichiarando che e' un valore parziale.
# ------------------------------------------------------------
function Measure-FolderBytesLimitato {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [int]$SecondiMax = 20
    )
    $vuoto = [pscustomobject]@{ Byte = [long]0; Parziale = $false }
    if (-not (Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue)) { return $vuoto }

    $condiviso = [hashtable]::Synchronized(@{ Byte = [long]0; Fatto = $false })
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'MTA'; $rs.ThreadOptions = 'ReuseThread'
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('cond', $condiviso)
    $rs.SessionStateProxy.SetVariable('percorso', $Path)

    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript({
        try {
            $t = [long]0
            Get-ChildItem -LiteralPath $percorso -Recurse -File -Force -ErrorAction SilentlyContinue |
                ForEach-Object { $t += $_.Length; $cond['Byte'] = $t }
            $cond['Byte'] = $t
        } catch { }
        $cond['Fatto'] = $true
    })
    $h = $ps.BeginInvoke()

    $sw = [Diagnostics.Stopwatch]::StartNew()
    while (-not $condiviso['Fatto'] -and $sw.Elapsed.TotalSeconds -lt $SecondiMax) {
        Start-Sleep -Milliseconds 200
    }
    $parziale = -not $condiviso['Fatto']
    $byte = [long]$condiviso['Byte']

    if ($parziale) { try { $ps.Stop() } catch { } }
    try { $ps.Dispose() } catch { }
    try { $rs.Close(); $rs.Dispose() } catch { }

    return [pscustomobject]@{ Byte = $byte; Parziale = $parziale }
}

function Get-FreeSpace {
    param([string]$DriveLetter = $env:SystemDrive)
    try {
        $d = Get-CimInstance -ClassName Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $DriveLetter) -ErrorAction Stop
        return [long]$d.FreeSpace
    } catch { return [long]0 }
}

# ------------------------------------------------------------
#   Riavvio in sospeso.
#   ATTENZIONE: RebootPending e RebootRequired sono CHIAVI di
#   registro, non valori. Controllarli con Get-ItemProperty -Name
#   produce sempre un falso negativo (era il bug della versione
#   precedente).
# ------------------------------------------------------------
function Test-RebootPending {
    $motivi = New-Object System.Collections.Generic.List[string]

    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
        $motivi.Add('Servicing componenti (CBS)') | Out-Null
    }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
        $motivi.Add('Windows Update') | Out-Null
    }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending') {
        $motivi.Add('Pacchetti in attesa') | Out-Null
    }
    $pfro = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' `
                             -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
    if ($pfro) { $motivi.Add('File da rinominare al prossimo avvio') | Out-Null }

    $cn = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' `
                           -Name 'NV Hostname' -ErrorAction SilentlyContinue
    $an = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' `
                           -Name 'ComputerName' -ErrorAction SilentlyContinue
    if ($cn -and $an -and ($cn.'NV Hostname' -ne $an.ComputerName)) {
        $motivi.Add('Rinomina del computer in sospeso') | Out-Null
    }

    return [pscustomobject]@{
        Pending = ($motivi.Count -gt 0)
        Motivi  = @($motivi)
    }
}

function New-RestorePoint {
    param([string]$Descrizione = 'System Toolbox - prima della manutenzione')
    try {
        Checkpoint-Computer -Description $Descrizione -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
        return [pscustomobject]@{ Ok = $true; Messaggio = 'Punto di ripristino creato.' }
    } catch {
        $m = $_.Exception.Message
        # Windows limita di default a un punto di ripristino ogni 24 ore.
        if ($m -match '1440|frequen') {
            $m = 'Esiste gia'' un punto di ripristino recente (limite di 24 ore di Windows).'
        }
        return [pscustomobject]@{ Ok = $false; Messaggio = $m }
    }
}

# ============================================================
#   ESECUZIONE DI PROCESSI ESTERNI
# ============================================================

function Invoke-Native {
    param(
        [Parameter(Mandatory=$true)][string]$File,
        [string[]]$Arguments = @(),
        [int]$TimeoutSec = 60
    )
    $tmpOut = [System.IO.Path]::GetTempFileName()
    $tmpErr = [System.IO.Path]::GetTempFileName()
    $exit   = -1
    $timedOut = $false
    try {
        $p = Start-Process -FilePath $File -ArgumentList $Arguments -NoNewWindow -PassThru `
                           -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr -ErrorAction Stop
        # Senza questa riga .ExitCode resta vuoto: Start-Process -PassThru
        # non conserva l'handle del processo, leggerlo lo mette in cache.
        try { $null = $p.Handle } catch { }
        if (-not $p.WaitForExit($TimeoutSec * 1000)) {
            $timedOut = $true
            try { $p.Kill() } catch { }
            $p.WaitForExit(3000) | Out-Null
        } else {
            $p.WaitForExit()
            $exit = $p.ExitCode
        }
    } catch {
        return [pscustomobject]@{ ExitCode = -1; Output = $_.Exception.Message; TimedOut = $false; Avviato = $false }
    }
    $out = ''
    try { $out = ((Get-Content -LiteralPath $tmpOut -Raw -ErrorAction SilentlyContinue) +
                  (Get-Content -LiteralPath $tmpErr -Raw -ErrorAction SilentlyContinue)) } catch { }
    Remove-Item -LiteralPath $tmpOut, $tmpErr -Force -ErrorAction SilentlyContinue
    if ($null -eq $out) { $out = '' }
    return [pscustomobject]@{ ExitCode = $exit; Output = $out.Trim(); TimedOut = $timedOut; Avviato = $true }
}

# Variante per comandi lunghi (DISM, SFC): mostra il tempo che
# passa invece di lasciare la finestra apparentemente bloccata.
function Invoke-LongNative {
    param(
        [Parameter(Mandatory=$true)][string]$File,
        [string[]]$Arguments = @(),
        [int]$TimeoutSec = 1800,
        [pscustomobject]$Ctx = $null
    )
    $tmpOut = [System.IO.Path]::GetTempFileName()
    $tmpErr = [System.IO.Path]::GetTempFileName()
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $timedOut = $false
    $exit = -1
    try {
        $p = Start-Process -FilePath $File -ArgumentList $Arguments -NoNewWindow -PassThru `
                           -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr -ErrorAction Stop
        try { $null = $p.Handle } catch { }
        $ultimo = -1
        while (-not $p.HasExited) {
            Start-Sleep -Milliseconds 500
            $sec = [int]$sw.Elapsed.TotalSeconds
            if ($sec -ne $ultimo -and ($sec % 10) -eq 0 -and $sec -gt 0) {
                $ultimo = $sec
                Write-Detail ('in corso... {0:mm\:ss} trascorsi' -f $sw.Elapsed)
            }
            if ($sw.Elapsed.TotalSeconds -gt $TimeoutSec) {
                $timedOut = $true
                try { $p.Kill() } catch { }
                break
            }
        }
        if (-not $timedOut) { $p.WaitForExit(); $exit = $p.ExitCode }
    } catch {
        return [pscustomobject]@{ ExitCode = -1; Output = $_.Exception.Message; TimedOut = $false; Avviato = $false }
    }
    $sw.Stop()
    $out = ''
    try { $out = ((Get-Content -LiteralPath $tmpOut -Raw -ErrorAction SilentlyContinue) +
                  (Get-Content -LiteralPath $tmpErr -Raw -ErrorAction SilentlyContinue)) } catch { }
    Remove-Item -LiteralPath $tmpOut, $tmpErr -Force -ErrorAction SilentlyContinue
    if ($null -eq $out) { $out = '' }
    return [pscustomobject]@{ ExitCode = $exit; Output = $out.Trim(); TimedOut = $timedOut; Avviato = $true }
}

# ============================================================
#   GESTIONE SERVIZI
#   Salva lo stato iniziale e ripristina SOLO quello: se un
#   servizio era gia' fermo o disabilitato resta com'era.
# ============================================================

function Stop-ServiceSet {
    param(
        [Parameter(Mandatory=$true)][string[]]$Names,
        [Parameter(Mandatory=$true)][pscustomobject]$Ctx,
        [int]$TimeoutSec = 20
    )
    # ArrayList e non List[object]: in Windows PowerShell 5.1
    # l'operatore @() su una List[object] solleva ArgumentException
    # ("Tipi di argomento non corrispondenti").
    $stato = New-Object System.Collections.ArrayList

    foreach ($n in $Names) {
        $svc = Get-Service -Name $n -ErrorAction SilentlyContinue
        if (-not $svc) { continue }
        $avvio = $null
        try { $avvio = (Get-CimInstance -ClassName Win32_Service -Filter ("Name='{0}'" -f $n) -ErrorAction Stop).StartMode } catch { }
        $stato.Add([pscustomobject]@{
            Name       = $n
            WasRunning = ($svc.Status -eq 'Running')
            StartMode  = $avvio
        }) | Out-Null
        if ($svc.Status -eq 'Running') {
            try { Stop-Service -Name $n -Force -NoWait -ErrorAction Stop }
            catch { $Ctx.Fail(('Arresto di {0} non riuscito: {1}' -f $n, $_.Exception.Message)) }
        }
    }

    # Attesa con budget INDIVIDUALE per ogni servizio.
    foreach ($s in $stato) {
        if (-not $s.WasRunning) { continue }
        $deadline = (Get-Date).AddSeconds($TimeoutSec)
        while ((Get-Date) -lt $deadline) {
            $svc = Get-Service -Name $s.Name -ErrorAction SilentlyContinue
            if (-not $svc -or $svc.Status -ne 'Running') { break }
            Start-Sleep -Milliseconds 400
        }
        $svc = Get-Service -Name $s.Name -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Running') {
            $Ctx.Fail(('Il servizio {0} e'' ancora attivo dopo {1} s' -f $s.Name, $TimeoutSec))
        }
    }
    return ,@($stato)
}

function Restore-ServiceSet {
    param(
        [object[]]$State = @(),
        [Parameter(Mandatory=$true)][pscustomobject]$Ctx
    )
    foreach ($s in $State) {
        if (-not $s.WasRunning) {
            $Ctx.Note(('Servizio {0} lasciato fermo: non era attivo prima' -f $s.Name))
            continue
        }
        if ($s.StartMode -eq 'Disabled') {
            $Ctx.Note(('Servizio {0} disabilitato: non riavviato' -f $s.Name))
            continue
        }
        try { Start-Service -Name $s.Name -ErrorAction Stop }
        catch { $Ctx.Fail(('Riavvio di {0} non riuscito: {1}' -f $s.Name, $_.Exception.Message)) }
    }
}

# ============================================================
#   CANCELLAZIONE CONTENUTO CARTELLE
#
#   Differenze rispetto alla versione precedente:
#   - niente doppia ricorsione (Get-ChildItem -Recurse seguito
#     da Remove-Item -Recurse enumerava figli gia' cancellati);
#   - misura reale dello spazio liberato (prima/dopo);
#   - i file bloccati NON sono errori: in una cartella Temp e'
#     normale, vengono contati a parte e dichiarati.
# ============================================================

# ------------------------------------------------------------
#   Cancellazione di un albero SENZA seguire i collegamenti.
#
#   La pulizia gira come amministratore e tocca anche i profili
#   degli altri utenti. Un collegamento (junction o link simbolico)
#   messo in una cartella Temp che punta altrove, per esempio a
#   C:\Windows, non deve mai portare la cancellazione nella sua
#   destinazione. Remove-Item -Recurse di Windows PowerShell 5.1
#   segue i link simbolici di cartella; qui un collegamento viene
#   solo scollegato: si rimuove il link, la destinazione resta.
#
#   Restituisce $true se tutto e' stato rimosso. Un elemento
#   bloccato non ferma il resto: si prosegue e si segnala.
# ------------------------------------------------------------
function Remove-AlberoSicuro {
    param([Parameter(Mandatory=$true)][System.IO.FileSystemInfo]$Voce)
    $tutto = $true
    $collegamento = [bool]($Voce.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
    if (($Voce -is [System.IO.DirectoryInfo]) -and -not $collegamento) {
        $figli = @()
        try { $figli = @($Voce.EnumerateFileSystemInfos()) } catch { $tutto = $false }
        foreach ($f in $figli) {
            if (-not (Remove-AlberoSicuro -Voce $f)) { $tutto = $false }
        }
    }
    try {
        if ($Voce.Attributes -band [System.IO.FileAttributes]::ReadOnly) {
            $Voce.Attributes = $Voce.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)
        }
        # Su un collegamento Directory.Delete(.., $false) rimuove il
        # link e non tocca la destinazione.
        if ($Voce -is [System.IO.DirectoryInfo]) { [System.IO.Directory]::Delete($Voce.FullName, $false) }
        else { [System.IO.File]::Delete($Voce.FullName) }
    } catch { $tutto = $false }
    return $tutto
}

function Clear-FolderContent {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][pscustomobject]$Ctx,
        [string]$Etichetta = ''
    )
    if (-not $Etichetta) { $Etichetta = $Path }
    # -ErrorAction sul Test-Path: su percorsi protetti (profili di
    # servizio come C:\Windows\ServiceProfiles) solleva un errore di
    # accesso negato che finirebbe a schermo sporcando l'output.
    if (-not (Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue)) {
        $Ctx.Note(('{0}: non presente o non accessibile, saltato' -f $Etichetta))
        return
    }

    # UNA sola scansione del disco.
    # Prima si misurava l'intera cartella, si cancellava e si
    # rimisurava: due attraversamenti completi, e su un Temp con
    # decine di migliaia di file era il costo dominante
    # dell'operazione. Qui si misura ogni voce di primo livello
    # una volta sola e si somma solo cio' che viene davvero
    # rimosso: stesso numero di file visitati, meta' del lavoro.
    $voci = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue)
    if ($voci.Count -eq 0) {
        $Ctx.Note(('{0}: gia'' vuoto' -f $Etichetta))
        return
    }

    $liberati = [long]0
    $rimossi  = 0
    $bloccati = 0

    foreach ($v in $voci) {
        $dim = [long]0
        $collegamento = [bool]($v.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
        try {
            if ($collegamento) {
                # Un collegamento non occupa spazio suo: liberarlo non
                # restituisce i byte della destinazione.
                $dim = [long]0
            } elseif ($v.PSIsContainer) {
                $s = (Get-ChildItem -LiteralPath $v.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
                      Measure-Object -Property Length -Sum).Sum
                if ($s) { $dim = [long]$s }
            } else {
                $dim = [long]$v.Length
            }
        } catch { }

        if ($Ctx.DryRun) {
            $liberati += $dim; $rimossi++
            continue
        }

        try {
            if (-not (Remove-AlberoSicuro -Voce $v)) { throw 'rimozione parziale' }
            $liberati += $dim; $rimossi++
        } catch {
            # Rimozione parziale: dentro c'era qualcosa di bloccato.
            # Si rimisura SOLO questa voce, non tutta la cartella.
            $resto = [long]0
            try {
                if (Test-Path -LiteralPath $v.FullName -ErrorAction SilentlyContinue) {
                    $r = (Get-ChildItem -LiteralPath $v.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
                          Measure-Object -Property Length -Sum).Sum
                    if ($r) { $resto = [long]$r }
                }
            } catch { }
            if ($resto -lt $dim) { $liberati += ($dim - $resto) }
            $bloccati++
        }
    }

    if ($Ctx.DryRun) {
        $Ctx.Note(('{0}: {1} eliminabili (simulazione)' -f $Etichetta, (Format-Bytes $liberati)))
        $Ctx.Bytes += $liberati
        return
    }

    $Ctx.Bytes   += $liberati
    $Ctx.Items   += $rimossi
    $Ctx.Skipped += $bloccati

    $msg = '{0}: {1} liberati, {2} elementi rimossi' -f $Etichetta, (Format-Bytes $liberati), $rimossi
    if ($bloccati -gt 0) { $msg += (', {0} in uso (saltati)' -f $bloccati) }
    $Ctx.Note($msg)
}

function Remove-FilePattern {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Filtro,
        [Parameter(Mandatory=$true)][pscustomobject]$Ctx,
        [string]$Etichetta = ''
    )
    if (-not $Etichetta) { $Etichetta = $Filtro }
    if (-not (Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue)) {
        $Ctx.Note(('{0}: percorso non presente o non accessibile' -f $Etichetta))
        return
    }
    $file = @(Get-ChildItem -LiteralPath $Path -Filter $Filtro -File -Force -ErrorAction SilentlyContinue)
    if ($file.Count -eq 0) {
        $Ctx.Note(('{0}: niente da rimuovere' -f $Etichetta))
        return
    }
    $liberati = 0; $rimossi = 0; $bloccati = 0
    foreach ($f in $file) {
        $dim = $f.Length
        try {
            Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
            $liberati += $dim; $rimossi++
        } catch { $bloccati++ }
    }
    $Ctx.Bytes   += $liberati
    $Ctx.Items   += $rimossi
    $Ctx.Skipped += $bloccati
    $msg = '{0}: {1} liberati, {2} file' -f $Etichetta, (Format-Bytes $liberati), $rimossi
    if ($bloccati -gt 0) { $msg += (', {0} in uso (saltati)' -f $bloccati) }
    $Ctx.Note($msg)
}

# ============================================================
#   MOTORE DEI TASK
# ============================================================

function New-TaskContext {
    param([switch]$DryRun)

    $ctx = [pscustomobject]@{
        Bytes        = [long]0
        Items        = [int]0
        Skipped      = [int]0
        Errors       = (New-Object System.Collections.Generic.List[string])
        Notes        = (New-Object System.Collections.Generic.List[string])
        DryRun       = [bool]$DryRun
        RebootNeeded = $false
    }

    $ctx | Add-Member -MemberType ScriptMethod -Name Note -Value {
        param([string]$m)
        $this.Notes.Add($m) | Out-Null
        Write-Detail $m
        Write-Log $m 'INFO'
    }

    $ctx | Add-Member -MemberType ScriptMethod -Name Fail -Value {
        param([string]$m)
        $this.Errors.Add($m) | Out-Null
        Write-Detail ('! ' + $m)
        Write-Log $m 'WARN'
    }

    return $ctx
}

# Esegue un singolo task e restituisce un oggetto risultato con
# l'esito REALE. Tre stati possibili:
#   OK       -> nessun errore registrato
#   PARZIALE -> il task ha girato ma ha segnalato problemi
#   FALLITO  -> eccezione non gestita, il task non ha completato
function Invoke-Task {
    param(
        [Parameter(Mandatory=$true)]$Task,
        [switch]$DryRun
    )

    $ctx = New-TaskContext -DryRun:$DryRun
    $sw  = [System.Diagnostics.Stopwatch]::StartNew()
    $hardFail = $null

    Write-Log ('=== TASK {0} : {1}' -f $Task.Id, $Task.Nome) 'STEP'

    try {
        & $Task.Azione $ctx
    } catch {
        $hardFail = $_.Exception.Message
        Write-Detail ('! ECCEZIONE: ' + $hardFail)
        Write-Log ('ECCEZIONE: ' + $hardFail) 'FAIL'
    }
    $sw.Stop()

    $esito = 'OK'
    if     ($hardFail)               { $esito = 'FALLITO'  }
    elseif ($ctx.Errors.Count -gt 0) { $esito = 'PARZIALE' }

    $lvl = 'OK'
    if ($esito -eq 'PARZIALE') { $lvl = 'WARN'; Set-EsitoAvviso }
    if ($esito -eq 'FALLITO')  { $lvl = 'FAIL'; Set-EsitoCritico }
    Write-Log ('esito={0} liberati={1} elementi={2} saltati={3} durata={4:N1}s' -f `
               $esito, (Format-Bytes $ctx.Bytes), $ctx.Items, $ctx.Skipped, $sw.Elapsed.TotalSeconds) $lvl

    $reboot = $ctx.RebootNeeded
    if ($Task.ContainsKey('RichiedeReboot') -and $Task.RichiedeReboot) { $reboot = $true }

    Add-JsonOperazione $Task.Id $Task.Nome $esito $ctx.Bytes ([int]$sw.Elapsed.TotalSeconds) $ctx.Errors.Count

    return [pscustomobject]@{
        Id       = $Task.Id
        Nome     = $Task.Nome
        Esito    = $esito
        Bytes    = $ctx.Bytes
        Items    = $ctx.Items
        Skipped  = $ctx.Skipped
        Errors   = @($ctx.Errors)
        Notes    = @($ctx.Notes)
        Reboot   = $reboot
        Durata   = $sw.Elapsed
        HardFail = $hardFail
    }
}
