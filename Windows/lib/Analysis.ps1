# ============================================================
#   Analysis.ps1 - Raccolta dati (sola lettura)
#
#   Ogni funzione restituisce OGGETTI, non testo: il rendering
#   e' compito della UI. E' questo che permettera' alla GUI di
#   fase C di riusare esattamente le stesse funzioni.
#
#   Nessuna funzione qui modifica lo stato del sistema.
# ============================================================

Set-StrictMode -Version 1.0

# ============================================================
#   CICLO DI VITA DI WINDOWS
#
#   Tabella da AGGIORNARE quando Microsoft pubblica nuove
#   versioni: le build sconosciute vengono dichiarate tali
#   invece di essere date per buone.
#   Home e Pro hanno 24 mesi di supporto, Enterprise ed
#   Education 36. Le date sono quelle ufficiali di fine
#   servizio (formato ISO).
# ============================================================
$script:CicloDiVita = @{
    19044 = @{ Nome = 'Windows 10 21H2'; Consumer = '2022-06-13'; Business = '2024-06-11' }
    19045 = @{ Nome = 'Windows 10 22H2'; Consumer = '2025-10-14'; Business = '2025-10-14' }
    22000 = @{ Nome = 'Windows 11 21H2'; Consumer = '2023-10-10'; Business = '2024-10-08' }
    22621 = @{ Nome = 'Windows 11 22H2'; Consumer = '2024-10-08'; Business = '2025-10-14' }
    22631 = @{ Nome = 'Windows 11 23H2'; Consumer = '2025-11-11'; Business = '2026-11-10' }
    26100 = @{ Nome = 'Windows 11 24H2'; Consumer = '2026-10-13'; Business = '2027-10-12' }
    26200 = @{ Nome = 'Windows 11 25H2'; Consumer = '2027-10-12'; Business = '2028-10-10' }
}

function Get-SysWindowsSupport {
    $build = 0
    try { $build = [int]((Get-CimCached -Class 'Win32_OperatingSystem') | Select-Object -First 1).BuildNumber } catch { }

    $edizione = ''
    try { $edizione = [string](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop).EditionID } catch { }
    # Solo Enterprise ed Education hanno il ciclo lungo: Pro segue
    # le stesse date di Home.
    $business = ($edizione -match 'Enterprise|Education')

    if (-not $script:CicloDiVita.ContainsKey($build)) {
        return [pscustomobject]@{
            Noto = $false; Build = $build; Edizione = $edizione
            Nome = ''; Scadenza = $null; Supportato = $null; Giorni = $null
        }
    }

    $voce = $script:CicloDiVita[$build]
    $testoData = $voce.Consumer
    if ($business) { $testoData = $voce.Business }

    $scadenza = $null
    try {
        $scadenza = [datetime]::ParseExact($testoData, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    } catch { }
    if (-not $scadenza) {
        return [pscustomobject]@{ Noto=$false; Build=$build; Edizione=$edizione; Nome=$voce.Nome; Scadenza=$null; Supportato=$null; Giorni=$null }
    }

    $giorni = [int][math]::Floor(($scadenza - (Get-Date)).TotalDays)
    return [pscustomobject]@{
        Noto       = $true
        Build      = $build
        Edizione   = $edizione
        Nome       = $voce.Nome
        Scadenza   = $scadenza
        Supportato = ($giorni -ge 0)
        Giorni     = $giorni
    }
}

# ------------------------------------------------------------
#   Sistema
# ------------------------------------------------------------
function Get-SysSummary {
    $os  = (Get-CimCached -Class 'Win32_OperatingSystem') | Select-Object -First 1
    $cs  = (Get-CimCached -Class 'Win32_ComputerSystem') | Select-Object -First 1
    $cpu = (Get-CimCached -Class 'Win32_Processor') | Select-Object -First 1
    $bios= (Get-CimCached -Class 'Win32_BIOS') | Select-Object -First 1

    $uptime = $null
    if ($os -and $os.LastBootUpTime) { $uptime = (Get-Date) - $os.LastBootUpTime }

    $displayVersion = $null
    try {
        $displayVersion = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop).DisplayVersion
    } catch { }

    return [pscustomobject]@{
        OS            = $(if ($os)  { $os.Caption }  else { 'n/d' })
        Versione      = $displayVersion
        Build         = $(if ($os)  { $os.Version }  else { 'n/d' })
        Installato    = $(if ($os)  { $os.InstallDate } else { $null })
        Modello       = $(if ($cs)  { ('{0} {1}' -f $cs.Manufacturer, $cs.Model).Trim() } else { 'n/d' })
        Bios          = $(if ($bios){ ('{0} {1}' -f $bios.Manufacturer, $bios.SMBIOSBIOSVersion).Trim() } else { 'n/d' })
        Cpu           = $(if ($cpu) { $cpu.Name.Trim() } else { 'n/d' })
        Core          = $(if ($cpu) { $cpu.NumberOfCores } else { 0 })
        Thread        = $(if ($cpu) { $cpu.NumberOfLogicalProcessors } else { 0 })
        Architettura  = $env:PROCESSOR_ARCHITECTURE
        Uptime        = $uptime
        Utente        = ('{0}\{1}' -f $env:USERDOMAIN, $env:USERNAME)
    }
}

# ------------------------------------------------------------
#   Dischi logici (spazio)
# ------------------------------------------------------------
function Get-SysVolume {
    $out = @()
    foreach ($d in (Get-CimCached -Class 'Win32_LogicalDisk' -Filter 'DriveType=3')) {
        $pct = 0
        if ($d.Size -gt 0) { $pct = [math]::Round((($d.Size - $d.FreeSpace) / $d.Size) * 100) }
        $out += [pscustomobject]@{
            Lettera   = $d.DeviceID
            Etichetta = $d.VolumeName
            Totale    = [long]$d.Size
            Liberi    = [long]$d.FreeSpace
            Usati     = [long]($d.Size - $d.FreeSpace)
            PctUsato  = $pct
        }
    }
    return $out
}

# ------------------------------------------------------------
#   Salute fisica dei dischi (SMART)
# ------------------------------------------------------------
function Get-SysDiskHealth {
    $out = @()
    if (-not (Get-Command Get-PhysicalDisk -ErrorAction SilentlyContinue)) { return $out }
    foreach ($d in (Get-PhysicalDisk -ErrorAction SilentlyContinue)) {
        $rc = $null
        try { $rc = $d | Get-StorageReliabilityCounter -ErrorAction Stop } catch { }
        $out += [pscustomobject]@{
            Nome       = $d.FriendlyName
            Tipo       = [string]$d.MediaType
            Bus        = [string]$d.BusType
            Dimensione = [long]$d.Size
            Salute     = [string]$d.HealthStatus
            Stato      = ($d.OperationalStatus -join ', ')
            Usura      = $(if ($rc) { $rc.Wear } else { $null })
            Ore        = $(if ($rc) { $rc.PowerOnHours } else { $null })
            Temp       = $(if ($rc) { $rc.Temperature } else { $null })
            ErrLettura = $(if ($rc) { $rc.ReadErrorsUncorrected } else { $null })
            ErrScrittura = $(if ($rc) { $rc.WriteErrorsUncorrected } else { $null })
        }
    }
    return $out
}

# ------------------------------------------------------------
#   Memoria
# ------------------------------------------------------------
function Get-SysMemory {
    $os = (Get-CimCached -Class 'Win32_OperatingSystem') | Select-Object -First 1
    $totale = 0; $liberi = 0
    if ($os) {
        $totale = [long]$os.TotalVisibleMemorySize * 1KB
        $liberi = [long]$os.FreePhysicalMemory * 1KB
    }
    $pct = 0
    if ($totale -gt 0) { $pct = [math]::Round((($totale - $liberi) / $totale) * 100) }

    $pf = (Get-CimCached -Class 'Win32_PageFileUsage') | Select-Object -First 1
    $moduli = @()
    $canali = New-Object System.Collections.ArrayList
    foreach ($m in (Get-CimCached -Class 'Win32_PhysicalMemory')) {
        $moduli += [pscustomobject]@{
            Banco   = $m.DeviceLocator
            Capacita= [long]$m.Capacity
            Velocita= $m.Speed
            Tipo    = $m.Manufacturer
        }
        # Il canale si ricava dall'etichetta del banco, che sui portatili
        # ha forme diverse: "Controller0-ChannelA", "ChannelA-DIMM0",
        # "BANK 0". Si tiene la parte che identifica il canale fisico.
        $etichetta = ('{0} {1}' -f $m.DeviceLocator, $m.BankLabel)
        $chiave = $null
        if     ($etichetta -match 'Controller(\d+)')  { $chiave = 'C' + $matches[1] }
        elseif ($etichetta -match 'Channel\s*([A-Z0-9]+)') { $chiave = 'CH' + $matches[1] }
        elseif ($etichetta -match 'BANK\s*(\d+)')     { $chiave = 'B' + $matches[1] }
        if ($chiave -and -not $canali.Contains($chiave)) { $canali.Add($chiave) | Out-Null }
    }

    # Euristica dichiarata come tale: Windows non espone direttamente
    # il numero di canali attivi.
    $modalita = 'non determinabile'
    if ($moduli.Count -ge 2 -and $canali.Count -ge 2)      { $modalita = 'dual channel (probabile)' }
    elseif ($moduli.Count -ge 2 -and $canali.Count -eq 1)  { $modalita = 'single channel (probabile)' }
    elseif ($moduli.Count -eq 1)                           { $modalita = 'single channel (un solo modulo)' }

    return [pscustomobject]@{
        Totale        = $totale
        Liberi        = $liberi
        Usati         = ($totale - $liberi)
        PctUsato      = $pct
        PagefileUsati = $(if ($pf) { [long]$pf.CurrentUsage * 1MB } else { $null })
        PagefileTot   = $(if ($pf) { [long]$pf.AllocatedBaseSize * 1MB } else { $null })
        Moduli        = $moduli
        Canali        = $canali.Count
        Modalita      = $modalita
    }
}

# ------------------------------------------------------------
#   Processi
#
#   La proprieta' CPU di Get-Process sono i secondi di CPU
#   ACCUMULATI dall'avvio del processo, non l'uso corrente:
#   qui si campiona due volte e si usa la differenza.
#   I processi con lo stesso nome (browser, editor) vengono
#   raggruppati, altrimenti il vero consumatore non emerge mai.
# ------------------------------------------------------------
function Get-SysTopProcess {
    param([int]$Top = 6, [int]$SampleMs = 1000)

    $core = [int]$env:NUMBER_OF_PROCESSORS
    if ($core -lt 1) { $core = 1 }

    $primo = @{}
    foreach ($p in (Get-Process -ErrorAction SilentlyContinue)) {
        if ($null -ne $p.CPU) { $primo[$p.Id] = [double]$p.CPU }
    }
    Start-Sleep -Milliseconds $SampleMs

    # ArrayList: vedi nota in Core.ps1 su @() e List[object] in PS 5.1
    $righe = New-Object System.Collections.ArrayList
    foreach ($p in (Get-Process -ErrorAction SilentlyContinue)) {
        $prima = 0.0
        if ($primo.ContainsKey($p.Id)) { $prima = $primo[$p.Id] }
        $ora = 0.0
        if ($null -ne $p.CPU) { $ora = [double]$p.CPU }
        $delta = $ora - $prima
        if ($delta -lt 0) { $delta = 0 }
        $righe.Add([pscustomobject]@{
            Nome = $p.ProcessName
            Pct  = ($delta / ($SampleMs / 1000.0) / $core) * 100.0
            Ram  = [long]$p.WorkingSet64
        }) | Out-Null
    }

    $gruppi = $righe | Group-Object Nome | ForEach-Object {
        [pscustomobject]@{
            Nome     = $_.Name
            Istanze  = $_.Count
            Pct      = [math]::Round((($_.Group | Measure-Object -Property Pct -Sum).Sum), 1)
            Ram      = [long](($_.Group | Measure-Object -Property Ram -Sum).Sum)
        }
    }

    return [pscustomobject]@{
        Cpu = @($gruppi | Sort-Object Pct -Descending | Select-Object -First $Top)
        Ram = @($gruppi | Sort-Object Ram -Descending | Select-Object -First $Top)
    }
}

# ------------------------------------------------------------
#   Servizi
# ------------------------------------------------------------
function Get-SysService {
    # Atteso:
    #   Running     -> deve essere in esecuzione, altrimenti e' un problema
    #   NotDisabled -> parte a richiesta: fermo va bene, disabilitato no.
    #                  E' il caso di wuauserv su Windows 10/11, che di norma
    #                  risulta "Manual + Stopped": segnalarlo come guasto,
    #                  come faceva la versione precedente, era un falso allarme.
    #   Any         -> puramente informativo
    $elenco = @(
        @{ Nome='WinDefend'; Etichetta='Microsoft Defender';    Atteso='Running'     },
        @{ Nome='MpsSvc';    Etichetta='Windows Firewall';      Atteso='Running'     },
        @{ Nome='EventLog';  Etichetta='Registro eventi';       Atteso='Running'     },
        @{ Nome='Dnscache';  Etichetta='Client DNS';            Atteso='Running'     },
        @{ Nome='wuauserv';  Etichetta='Windows Update';        Atteso='NotDisabled' },
        @{ Nome='BITS';      Etichetta='BITS (trasferimenti)';  Atteso='NotDisabled' },
        @{ Nome='WdNisSvc';  Etichetta='Defender - rete';       Atteso='NotDisabled' },
        @{ Nome='SysMain';   Etichetta='SysMain (Superfetch)';  Atteso='Any'         },
        @{ Nome='Spooler';   Etichetta='Spooler di stampa';     Atteso='Any'         },
        @{ Nome='LanmanWorkstation'; Etichetta='Workstation';   Atteso='Any'         },
        @{ Nome='WSearch';   Etichetta='Windows Search';        Atteso='Any'         }
    )
    # UNA sola query per tutti i servizi, poi si filtra in memoria.
    # Prima si eseguiva una Get-CimInstance per ciascuno degli undici
    # servizi: undici interrogazioni WMI dove ne basta una.
    $modiAvvio = @{}
    foreach ($s in (Get-CimCached -Class 'Win32_Service')) {
        $modiAvvio[$s.Name] = $s.StartMode
    }
    $statiServizio = @{}
    foreach ($s in (Get-Service -ErrorAction SilentlyContinue)) {
        $statiServizio[$s.Name] = $s.Status
    }

    $out = @()
    foreach ($e in $elenco) {
        if (-not $statiServizio.ContainsKey($e.Nome)) { continue }
        $svc = [pscustomobject]@{ Status = $statiServizio[$e.Nome] }
        $avvio = $null
        if ($modiAvvio.ContainsKey($e.Nome)) { $avvio = $modiAvvio[$e.Nome] }

        $problema = $false
        $motivo   = ''
        if ($e.Atteso -eq 'Running' -and $svc.Status -ne 'Running') {
            $problema = $true; $motivo = 'dovrebbe essere in esecuzione'
        } elseif ($e.Atteso -eq 'NotDisabled' -and $avvio -eq 'Disabled') {
            $problema = $true; $motivo = 'disabilitato'
        }

        $out += [pscustomobject]@{
            Nome      = $e.Nome
            Etichetta = $e.Etichetta
            Stato     = [string]$svc.Status
            Avvio     = $avvio
            Critico   = ($e.Atteso -ne 'Any')
            Problema  = $problema
            Motivo    = $motivo
        }
    }
    return $out
}

# ------------------------------------------------------------
#   Sicurezza
# ------------------------------------------------------------
function Get-SysSecurity {
    $defender = $null
    if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
        try {
            $m = Get-MpComputerStatus -ErrorAction Stop
            $defender = [pscustomobject]@{
                Antivirus    = $m.AntivirusEnabled
                TempoReale   = $m.RealTimeProtectionEnabled
                Tamper       = $m.IsTamperProtected
                EtaFirme     = $m.AntivirusSignatureAge
                DataFirme    = $m.AntivirusSignatureLastUpdated
                UltimaRapida = $m.QuickScanEndTime
                UltimaCompleta = $m.FullScanEndTime
            }
        } catch { }
    }

    $firewall = @()
    if (Get-Command Get-NetFirewallProfile -ErrorAction SilentlyContinue) {
        try {
            foreach ($f in (Get-NetFirewallProfile -ErrorAction Stop)) {
                $firewall += [pscustomobject]@{ Profilo = $f.Name; Attivo = [bool]$f.Enabled }
            }
        } catch { }
    }

    $crittografia = @()
    if (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue) {
        try {
            foreach ($b in (Get-BitLockerVolume -ErrorAction Stop)) {
                $crittografia += [pscustomobject]@{
                    Volume = $b.MountPoint
                    Stato  = [string]$b.ProtectionStatus
                    Metodo = [string]$b.EncryptionMethod
                }
            }
        } catch { }
    }

    $uac = $null
    try {
        $uac = [bool](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name EnableLUA -ErrorAction Stop).EnableLUA
    } catch { }

    return [pscustomobject]@{
        Defender     = $defender
        Firewall     = $firewall
        Crittografia = $crittografia
        Uac          = $uac
    }
}

# ------------------------------------------------------------
#   Aggiornamenti Windows
#   Eseguito in un job separato: la ricerca COM puo' bloccarsi
#   per minuti su alcune configurazioni e nella versione
#   precedente non c'era alcun timeout.
# ------------------------------------------------------------
# Avvia la ricerca degli aggiornamenti SENZA attendere: e' la
# sezione piu' lenta dell'analisi (fino a un minuto e passa) ed
# e' del tutto indipendente dalle altre. Si lancia all'inizio e
# si raccoglie quando la sezione arriva.
# Un runspace costa molto meno di Start-Job, che avvia un intero
# processo PowerShell (circa un secondo solo di avvio) e ne duplica
# la memoria. Il risultato finisce in una hashtable condivisa.
function Start-SysUpdateJob {
    if ($script:CFG['analisi_aggiornamenti'] -eq 'no') { return }
    $script:UpdCond = [hashtable]::Synchronized(@{ Fatto = $false; Ris = $null })
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'MTA'; $rs.ThreadOptions = 'ReuseThread'
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('cond', $script:UpdCond)
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    [void]$ps.AddScript({
        try {
            $sess = New-Object -ComObject Microsoft.Update.Session
            $ris  = $sess.CreateUpdateSearcher().Search("IsInstalled=0 and Type='Software' and IsHidden=0")
            $titoli = @()
            foreach ($u in $ris.Updates) { $titoli += [string]$u.Title }
            $cond['Ris'] = [pscustomobject]@{ Ok=$true; Conteggio=$titoli.Count; Titoli=$titoli; Errore=$null }
        } catch {
            $cond['Ris'] = [pscustomobject]@{ Ok=$false; Conteggio=0; Titoli=@(); Errore=$_.Exception.Message }
        }
        $cond['Fatto'] = $true
    })
    $script:UpdPs = $ps
    $script:UpdRs = $rs
    $script:UpdHandle = $ps.BeginInvoke()
}

# Ripiego conservato: se il runspace non fosse utilizzabile.
function Start-SysUpdateJobConProcesso {
    $script:JobUpdate = Start-Job -ScriptBlock {
        try {
            $sess = New-Object -ComObject Microsoft.Update.Session
            $ris  = $sess.CreateUpdateSearcher().Search("IsInstalled=0 and Type='Software' and IsHidden=0")
            $titoli = @()
            foreach ($u in $ris.Updates) { $titoli += [string]$u.Title }
            [pscustomobject]@{ Ok = $true; Conteggio = $titoli.Count; Titoli = $titoli; Errore = $null }
        } catch {
            [pscustomobject]@{ Ok = $false; Conteggio = 0; Titoli = @(); Errore = $_.Exception.Message }
        }
    }
}

function Get-SysUpdate {
    param([int]$TimeoutSec = 75)

    if ($script:CFG['analisi_aggiornamenti'] -eq 'no') {
        return [pscustomobject]@{ Ok=$false; Conteggio=0; Titoli=@()
                                  Errore='sezione disattivata nella configurazione' }
    }

    # Percorso normale: il runspace e' partito all'inizio
    # dell'analisi, qui si raccoglie soltanto il risultato.
    if ($script:UpdCond) {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while (-not $script:UpdCond['Fatto'] -and $sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
            Start-Sleep -Milliseconds 200
        }
        $fatto = [bool]$script:UpdCond['Fatto']
        $ris   = $script:UpdCond['Ris']
        if (-not $fatto) { try { $script:UpdPs.Stop() } catch { } }
        try { $script:UpdPs.Dispose() } catch { }
        try { $script:UpdRs.Close(); $script:UpdRs.Dispose() } catch { }
        $script:UpdCond = $null; $script:UpdPs = $null; $script:UpdRs = $null
        if ($fatto -and $ris) { return $ris }
        return [pscustomobject]@{ Ok=$false; Conteggio=0; Titoli=@()
                                  Errore=("Nessuna risposta entro {0} secondi" -f $TimeoutSec) }
    }

    # Ripiego con processo separato.
    $job = $null
    if ($script:JobUpdate) { $job = $script:JobUpdate; $script:JobUpdate = $null }
    if (-not $job) { $job = Start-Job -ScriptBlock {
        try {
            $sess = New-Object -ComObject Microsoft.Update.Session
            $ris  = $sess.CreateUpdateSearcher().Search("IsInstalled=0 and Type='Software' and IsHidden=0")
            $titoli = @()
            foreach ($u in $ris.Updates) { $titoli += [string]$u.Title }
            [pscustomobject]@{ Ok = $true; Conteggio = $titoli.Count; Titoli = $titoli; Errore = $null }
        } catch {
            [pscustomobject]@{ Ok = $false; Conteggio = 0; Titoli = @(); Errore = $_.Exception.Message }
        }
    } }

    $finito = Wait-Job -Job $job -Timeout $TimeoutSec
    if (-not $finito) {
        Stop-Job   -Job $job -ErrorAction SilentlyContinue
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        return [pscustomobject]@{ Ok = $false; Conteggio = 0; Titoli = @(); Errore = ('Nessuna risposta entro {0} secondi' -f $TimeoutSec) }
    }
    $res = Receive-Job -Job $job
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    if (-not $res) {
        return [pscustomobject]@{ Ok = $false; Conteggio = 0; Titoli = @(); Errore = 'Risposta vuota da Windows Update' }
    }
    return $res
}

# ------------------------------------------------------------
#   Programmi all'avvio
#   Win32_StartupCommand elenca anche le voci che l'utente ha
#   gia' disattivato da Gestione attivita': lo stato vero sta
#   nelle chiavi StartupApproved, dove il primo byte con il bit
#   meno significativo a 1 indica "disattivato".
# ------------------------------------------------------------
function Get-StartupApprovato {
    $stato = @{}
    $chiavi = @(
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
    )
    foreach ($k in $chiavi) {
        if (-not (Test-Path -LiteralPath $k -ErrorAction SilentlyContinue)) { continue }
        $prop = $null
        try { $prop = Get-ItemProperty -LiteralPath $k -ErrorAction Stop } catch { continue }
        foreach ($p in $prop.PSObject.Properties) {
            if ($p.Name -like 'PS*') { continue }
            $v = $p.Value
            if ($v -is [byte[]] -and $v.Length -gt 0) {
                $stato[$p.Name] = (($v[0] -band 1) -eq 0)
            }
        }
    }
    return $stato
}

function Get-SysStartup {
    $approvato = Get-StartupApprovato
    $out = @()
    $visti = @{}
    try {
        foreach ($s in (Get-CimInstance -ClassName Win32_StartupCommand -ErrorAction Stop)) {
            # La stessa voce compare piu' volte quando e' registrata in
            # rami diversi: si conta una sola volta.
            $chiave = ('{0}|{1}' -f $s.Name, $s.Command)
            if ($visti.ContainsKey($chiave)) { continue }
            $visti[$chiave] = $true

            $attivo = $true
            if ($approvato.ContainsKey($s.Name)) { $attivo = [bool]$approvato[$s.Name] }
            $out += [pscustomobject]@{
                Nome    = $s.Name
                Comando = $s.Command
                Origine = $s.Location
                Utente  = $s.User
                Attivo  = $attivo
            }
        }
    } catch { }
    return ($out | Sort-Object @{Expression='Attivo';Descending=$true}, Nome)
}

# ------------------------------------------------------------
#   Alimentazione
#   Su Windows 11 contano due cose distinte: il piano classico
#   e la "modalita' alimentazione" sovrapposta, che e' quella
#   che si vede in Impostazioni e che incide davvero.
# ------------------------------------------------------------
function Get-SysPower {
    $piano = ''
    try {
        $r = Invoke-Native -File 'powercfg.exe' -Arguments @('/getactivescheme') -TimeoutSec 20
        if ($r.Output -match '\(([^)]+)\)') { $piano = $matches[1] }
    } catch { }

    $sovrapposte = @{
        '00000000-0000-0000-0000-000000000000' = 'Bilanciata'
        'ded574b5-45a0-4f42-8737-46345c09c238' = 'Prestazioni migliori'
        '961cc777-2547-4f9d-8174-7d86181b8a7a' = 'Massimo risparmio energetico'
    }
    $ac = $null; $dc = $null
    try {
        $k = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes' -ErrorAction Stop
        $gAc = [string]$k.ActiveOverlayAcPowerScheme
        $gDc = [string]$k.ActiveOverlayDcPowerScheme
        if ($gAc) { $ac = $(if ($sovrapposte.ContainsKey($gAc)) { $sovrapposte[$gAc] } else { $gAc }) }
        if ($gDc) { $dc = $(if ($sovrapposte.ContainsKey($gDc)) { $sovrapposte[$gDc] } else { $gDc }) }
    } catch { }

    $portatile = $false
    try { $portatile = [bool](@(Get-CimCached -Class 'Win32_Battery').Count) } catch { }

    return [pscustomobject]@{
        Piano      = $piano
        ModalitaAc = $ac
        ModalitaDc = $dc
        Portatile  = $portatile
    }
}

# ------------------------------------------------------------
#   Protezione sistema e punti di ripristino
# ------------------------------------------------------------
function Get-SysProtection {
    $punti = @()
    $leggibile = $true
    try {
        $punti = @(Get-ComputerRestorePoint -ErrorAction Stop)
    } catch { $leggibile = $false }

    $usato = $null; $massimo = $null
    try {
        $r = Invoke-Native -File (Join-Path $env:WINDIR 'System32\vssadmin.exe') -Arguments @('list','shadowstorage') -TimeoutSec 30
        # Le etichette di vssadmin sono localizzate, quindi non si
        # possono cercare per nome: si prendono i numeri nell'ordine
        # in cui compaiono (utilizzato, allocato, massimo).
        $valori = @([regex]::Matches($r.Output, '([\d]+[.,][\d]+|\d+) (KB|MB|GB|TB)') | ForEach-Object { $_.Value })
        if ($valori.Count -ge 3) { $usato = $valori[0]; $massimo = $valori[2] }
    } catch { }

    $ultimo = $null
    if ($punti.Count -gt 0) {
        try { $ultimo = ($punti | Select-Object -Last 1).ConvertToDateTime(($punti | Select-Object -Last 1).CreationTime) } catch { }
    }

    return [pscustomobject]@{
        Leggibile = $leggibile
        Admin     = (Test-Admin)
        Punti     = $punti.Count
        Ultimo    = $ultimo
        Usato     = $usato
        Massimo   = $massimo
    }
}

# ------------------------------------------------------------
#   Dispositivi con problemi di driver
#   Si escludono il codice 22 (disattivato dall'utente) e il 45
#   (periferica non collegata in questo momento): non sono guasti.
# ------------------------------------------------------------
function Get-SysDeviceProblem {
    $descrizioni = @{
        1  = 'configurazione non completata'
        3  = 'driver danneggiato o memoria insufficiente'
        10 = 'impossibile avviare la periferica'
        12 = 'risorse insufficienti'
        14 = 'richiede il riavvio del computer'
        18 = 'reinstallare i driver'
        19 = 'informazioni di configurazione danneggiate'
        21 = 'rimozione in corso'
        24 = 'periferica non presente o non funzionante'
        28 = 'driver non installati'
        31 = 'driver non funzionante'
        37 = 'driver non inizializzato'
        39 = 'driver danneggiato o mancante'
        43 = 'arrestata per un problema segnalato'
    }
    $out = @()
    try {
        $tutti = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop
        foreach ($d in $tutti) {
            $c = [int]$d.ConfigManagerErrorCode
            if ($c -eq 0 -or $c -eq 22 -or $c -eq 45) { continue }
            $motivo = ('codice {0}' -f $c)
            if ($descrizioni.ContainsKey($c)) { $motivo = $descrizioni[$c] }
            $out += [pscustomobject]@{
                Nome    = $d.Name
                Codice  = $c
                Motivo  = $motivo
                Classe  = $d.PNPClass
            }
        }
    } catch { }
    return $out
}

# ------------------------------------------------------------
#   Manutenzione automatica del sistema operativo
#   Sensore memoria, TRIM e pianificazione dell'ottimizzazione:
#   sono le cose che, se attive, fanno da sole il lavoro che
#   altrimenti tocca fare a mano.
# ------------------------------------------------------------
function Get-SysMaintenance {
    $sensore = $null
    try {
        $k = Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' -ErrorAction Stop
        $sensore = ([int]$k.'01' -eq 1)
    } catch { }

    $trim = $null
    try {
        $r = Invoke-Native -File 'fsutil.exe' -Arguments @('behavior','query','DisableDeleteNotify') -TimeoutSec 20
        # 0 = notifiche di eliminazione attive, cioe' TRIM funzionante
        if ($r.Output -match 'DisableDeleteNotify\D*(\d)') { $trim = ($matches[1] -eq '0') }
    } catch { }

    $pianificata = $null; $ultimaOtt = $null
    try {
        $task = Get-ScheduledTask -TaskName 'ScheduledDefrag' -ErrorAction Stop
        $pianificata = ($task.State -ne 'Disabled')
        $info = $task | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
        if ($info -and $info.LastRunTime -gt [datetime]'2000-01-01') { $ultimaOtt = $info.LastRunTime }
    } catch { }

    return [pscustomobject]@{
        SensoreMemoria = $sensore
        Trim           = $trim
        OttPianificata = $pianificata
        UltimaOtt      = $ultimaOtt
    }
}

# ------------------------------------------------------------
#   Spazio recuperabile che non compare altrove
# ------------------------------------------------------------
function Get-SysSpazioRecuperabile {
    $voci = @()

    $hiber = Join-Path $env:SystemDrive 'hiberfil.sys'
    if (Test-Path -LiteralPath $hiber -ErrorAction SilentlyContinue) {
        $dim = 0
        try { $dim = [long](Get-Item -LiteralPath $hiber -Force -ErrorAction Stop).Length } catch { }
        $voci += [pscustomobject]@{
            Nome = 'File di ibernazione (hiberfil.sys)'
            Byte = $dim
            Nota = 'Si elimina solo disattivando ibernazione e avvio rapido: powercfg /h off'
        }
    }

    $vecchio = Join-Path $env:SystemDrive 'Windows.old'
    if (Test-Path -LiteralPath $vecchio -ErrorAction SilentlyContinue) {
        # Con budget di tempo: su una Windows.old da decine di GB
        # l'enumerazione completa puo' durare minuti, e un'analisi
        # che si blocca senza spiegazioni e' peggio di un numero
        # dichiarato come parziale.
        $mVecchio = Measure-FolderBytesLimitato -Path $vecchio -SecondiMax 20
        $voci += [pscustomobject]@{
            Nome = 'Installazione precedente (Windows.old)'
            Byte = $mVecchio.Byte
            Nota = $(if ($mVecchio.Parziale) {
                        'Misura interrotta dopo 20 secondi: il valore e'' un minimo. Rimuovendola si perde la possibilita'' di tornare alla versione precedente di Windows'
                     } else {
                        'Rimuovendola si perde la possibilita'' di tornare alla versione precedente di Windows'
                     })
        }
    }

    $sd = Join-Path $env:WINDIR 'SoftwareDistribution\Download'
    if (Test-Path -LiteralPath $sd -ErrorAction SilentlyContinue) {
        $b = Measure-FolderBytes $sd
        if ($b -gt 100MB) {
            $voci += [pscustomobject]@{
                Nome = 'Cache di Windows Update'
                Byte = $b
                Nota = 'Rimovibile dalla pulizia avanzata'
            }
        }
    }

    return $voci
}

# ------------------------------------------------------------
#   Eventi che precedono un guasto del disco
#   Sono ID specifici: settori illeggibili, timeout del
#   controller, errori del file system. Vale la pena separarli
#   dal rumore generico del registro eventi.
# ------------------------------------------------------------
function Get-SysDiskEvent {
    param([int]$Giorni = 30)
    $inizio = (Get-Date).AddDays(-$Giorni)
    $interessanti = @{
        7   = 'settore danneggiato'
        9   = 'timeout della periferica'
        11  = 'errore del controller'
        51  = 'errore di paging sul disco'
        52  = 'il disco segnala un guasto imminente'
        55  = 'file system danneggiato (serve chkdsk)'
        98  = 'errore di metadati NTFS'
        129 = 'reset del controller disco'
        153 = 'richiesta di I/O riprovata'
    }
    $out = @()
    try {
        $ev = Get-WinEvent -FilterHashtable @{
                  LogName = 'System'; StartTime = $inizio
                  ProviderName = @('disk','Disk','Ntfs','volmgr','storahci','stornvme','iaStorAC')
              } -MaxEvents 400 -ErrorAction Stop
        $out = @($ev | Where-Object { $interessanti.ContainsKey([int]$_.Id) } |
                 Group-Object Id | Sort-Object Count -Descending | ForEach-Object {
                     $p = $_.Group[0]
                     [pscustomobject]@{
                         Id        = [int]$p.Id
                         Conteggio = $_.Count
                         Motivo    = $interessanti[[int]$p.Id]
                         Ultimo    = $p.TimeCreated
                         Provider  = $p.ProviderName
                     }
                 })
    } catch { }
    return $out
}

# ------------------------------------------------------------
#   Errori recenti nel registro eventi
# ------------------------------------------------------------
function Get-SysEventError {
    param([int]$Giorni = 7, [int]$Top = 8)

    $inizio = (Get-Date).AddDays(-$Giorni)
    $eventi = New-Object System.Collections.ArrayList
    foreach ($registro in @('System','Application')) {
        try {
            $e = Get-WinEvent -FilterHashtable @{ LogName = $registro; Level = 1,2; StartTime = $inizio } `
                              -MaxEvents 500 -ErrorAction Stop
            foreach ($x in $e) { $eventi.Add($x) | Out-Null }
        } catch { }
    }
    if ($eventi.Count -eq 0) { return @() }

    return @($eventi | Group-Object -Property ProviderName, Id |
             Sort-Object Count -Descending | Select-Object -First $Top | ForEach-Object {
                $p = $_.Group[0]
                $msg = ''
                if ($p.Message) { $msg = (($p.Message -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -First 1) }
                [pscustomobject]@{
                    Conteggio = $_.Count
                    Provider  = $p.ProviderName
                    Id        = $p.Id
                    Ultimo    = $p.TimeCreated
                    Messaggio = $msg
                }
             })
}

# ------------------------------------------------------------
#   Batteria (solo portatili)
# ------------------------------------------------------------
# Ripiego: estrae capacita' di progetto e capacita' attuale dal report
# HTML di powercfg. I numeri sono formattati secondo la lingua di Windows
# (in italiano "50.000 mWh"), quindi si tengono solo le cifre.
function Get-BatteryFromReport {
    $file = Join-Path $env:TEMP ('battreport_{0}.html' -f [guid]::NewGuid().ToString('N').Substring(0,8))
    try {
        $r = Invoke-Native -File 'powercfg.exe' -Arguments @('/batteryreport','/output', ('"' + $file + '"')) -TimeoutSec 45
        if (-not (Test-Path -LiteralPath $file -ErrorAction SilentlyContinue)) { return $null }
        $html = Get-Content -LiteralPath $file -Raw -ErrorAction SilentlyContinue
    } catch {
        return $null
    } finally {
        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
    }
    if (-not $html) { return $null }

    $progetto = $null; $attuale = $null; $cicli = $null
    if ($html -match '(?s)DESIGN CAPACITY.*?<td[^>]*>\s*([\d\.,\s]+?)\s*mWh') {
        $progetto = [long](($matches[1] -replace '[^\d]', ''))
    }
    if ($html -match '(?s)FULL CHARGE CAPACITY.*?<td[^>]*>\s*([\d\.,\s]+?)\s*mWh') {
        $attuale = [long](($matches[1] -replace '[^\d]', ''))
    }
    if ($html -match '(?s)CYCLE COUNT.*?<td[^>]*>\s*([\d\.,\s]+?)\s*<') {
        $cicli = [long](($matches[1] -replace '[^\d]', ''))
    }
    if (-not $progetto -and -not $attuale) { return $null }
    return [pscustomobject]@{ Progetto = $progetto; Attuale = $attuale; Cicli = $cicli }
}

function Get-SysBattery {
    $b = (Get-CimCached -Class 'Win32_Battery') | Select-Object -First 1
    if (-not $b) { return $null }

    $progetto = $null; $attuale = $null
    try { $progetto = (Get-CimInstance -Namespace 'root\wmi' -ClassName BatteryStaticData -ErrorAction Stop | Select-Object -First 1).DesignedCapacity } catch { }
    try { $attuale  = (Get-CimInstance -Namespace 'root\wmi' -ClassName BatteryFullChargedCapacity -ErrorAction Stop | Select-Object -First 1).FullChargedCapacity } catch { }

    # Molti firmware (fra cui questo Vivobook) non espongono le classi
    # root\wmi della batteria. In quel caso si ripiega sul report di
    # powercfg, che legge gli stessi dati per altra via.
    $cicli = $null
    if (-not $progetto -or -not $attuale) {
        $dati = Get-BatteryFromReport
        if ($dati) {
            if (-not $progetto) { $progetto = $dati.Progetto }
            if (-not $attuale)  { $attuale  = $dati.Attuale }
            $cicli = $dati.Cicli
        }
    }

    $salute = $null
    if ($progetto -and $attuale -and $progetto -gt 0) { $salute = [math]::Round(($attuale / $progetto) * 100) }

    return [pscustomobject]@{
        Nome       = $b.Name
        Carica     = $b.EstimatedChargeRemaining
        Progetto   = $progetto
        Attuale    = $attuale
        Cicli      = $cicli
        SalutePct  = $salute
    }
}

# ------------------------------------------------------------
#   Rete: schede, DNS in uso e prove di connettivita' reali
#   (la versione precedente testava solo un ping a 8.8.8.8,
#   che NON verifica affatto la risoluzione dei nomi)
# ------------------------------------------------------------
function Get-SysNetwork {
    param([switch]$SkipTest)

    $schede = @()
    if (Get-Command Get-NetAdapter -ErrorAction SilentlyContinue) {
        try {
            foreach ($a in (Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' })) {
                $ip = Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                      Where-Object { $_.IPAddress -notlike '127.*' } | Select-Object -First 1
                $dns = @()
                try {
                    $dns = @((Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction Stop).ServerAddresses)
                } catch { }
                $gw = $null
                try {
                    $gw = (Get-NetRoute -InterfaceIndex $a.ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop |
                           Select-Object -First 1).NextHop
                } catch { }
                $indirizzo = $(if ($ip) { $ip.IPAddress } else { $null })
                # Una scheda senza gateway e con solo un indirizzo APIPA
                # (169.254.x.x) e' quasi sempre un adattatore virtuale di
                # VirtualBox/VMware/Hyper-V: rumore, non connettivita' reale.
                $virtuale = ((-not $gw) -and ((-not $indirizzo) -or $indirizzo -like '169.254.*'))
                $schede += [pscustomobject]@{
                    Nome      = $a.Name
                    Descrizione = $a.InterfaceDescription
                    Velocita  = $a.LinkSpeed
                    Ip        = $indirizzo
                    Origine   = $(if ($ip) { [string]$ip.PrefixOrigin } else { $null })
                    Gateway   = $gw
                    Dns       = $dns
                    Virtuale  = $virtuale
                }
            }
        } catch { }
    }

    $ping = $null; $dnsOk = $null; $dnsMs = $null; $https = $null
    if (-not $SkipTest) {
        try { $ping = [bool](Test-Connection -ComputerName '1.1.1.1' -Count 2 -Quiet -ErrorAction Stop) } catch { $ping = $false }

        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $r = Resolve-DnsName -Name 'www.microsoft.com' -Type A -DnsOnly -ErrorAction Stop
            $dnsOk = ($r -ne $null)
        } catch { $dnsOk = $false }
        $sw.Stop()
        $dnsMs = [int]$sw.Elapsed.TotalMilliseconds

        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $resp = Invoke-WebRequest -Uri 'https://www.microsoft.com' -Method Head -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
            $https = ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 400)
        } catch { $https = $false }
    }

    return [pscustomobject]@{
        Schede  = $schede
        PingOk  = $ping
        DnsOk   = $dnsOk
        DnsMs   = $dnsMs
        HttpsOk = $https
    }
}
