# ============================================================
#   SYSTEM TOOLBOX - punto di ingresso
#
#   Unifica i vecchi ClearTEMP.bat e RefreshDNS.bat in un solo
#   strumento con menu. La logica sta in lib\: qui c'e' solo
#   l'orchestrazione e il menu console.
#
#   Uso:
#     Toolbox.bat                 menu interattivo
#     Toolbox.bat -Auto           manutenzione consigliata, senza domande
#     Toolbox.bat -DryRun         simulazione: non modifica nulla
#     Toolbox.bat -Auto -DryRun   combinabili
#
#   Fase C: bastera' aggiungere lib\GuiUI.ps1 e uno switch -Gui
#   qui sotto. Motore, task e analisi restano identici.
# ============================================================

[CmdletBinding()]
param(
    [switch]$Auto,        # esecuzione non interattiva
    [switch]$DryRun,      # simula, non modifica nulla
    [switch]$NoElevate,   # non tentare l'elevazione automatica
    [switch]$Console,     # forza il menu testuale anche se la GUI e' disponibile
    [switch]$Gui,         # forza la GUI (e' comunque il comportamento predefinito)
    [string]$Report,      # esporta il report: .md o .html
    [switch]$Json,        # stampa un riepilogo JSON invece dell'interfaccia
    [string]$Config,      # file di configurazione alternativo
    [switch]$Daltonici,   # palette e simboli per daltonici
    [switch]$NoColor,
    [switch]$Versione
)

Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Continue'

$Radice = Split-Path -Parent $MyInvocation.MyCommand.Path

# ------------------------------------------------------------
#   Caricamento moduli
# ------------------------------------------------------------
foreach ($modulo in @('Common.ps1','Core.ps1','Tasks.ps1','Analysis.ps1','ConsoleUI.ps1')) {
    $percorso = Join-Path $Radice ('lib\' + $modulo)
    if (-not (Test-Path -LiteralPath $percorso)) {
        Write-Host (" [ERRORE] File mancante: {0}" -f $percorso) -ForegroundColor Red
        Read-Host ' Premi INVIO per chiudere' | Out-Null
        exit 1
    }
    . $percorso
}

# Rete di sicurezza: senza questo, un errore non gestito farebbe
# sparire la finestra prima che si riesca a leggere il messaggio.
trap {
    Write-Host ''
    Write-Host ('  [ERRORE NON GESTITO] ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host ('  Tipo: ' + $_.Exception.GetType().FullName) -ForegroundColor DarkGray
    Write-Host ('  ' + $_.InvocationInfo.PositionMessage) -ForegroundColor DarkGray
    Write-Host '  Stack:' -ForegroundColor DarkGray
    Write-Host ($_.ScriptStackTrace) -ForegroundColor DarkGray
    Write-Log ('ERRORE NON GESTITO: ' + $_.Exception.Message) 'FAIL'
    Write-Log ('Stack: ' + $_.ScriptStackTrace) 'FAIL'
    Read-Host '  Premi INVIO per chiudere' | Out-Null
    exit 1
}

# La versione si stampa subito: non ha senso chiedere
# l'elevazione solo per mostrare un numero.
if ($Versione) { Write-Host "System Toolbox $script:TB_VERSIONE"; exit 0 }

# ------------------------------------------------------------
#   Bitness
#   In un processo PowerShell a 32 bit su Windows a 64 bit,
#   System32 viene rediretto a SysWOW64: sfc.exe e dism.exe
#   verrebbero eseguiti nelle versioni sbagliate. Meglio
#   ripartire subito a 64 bit.
# ------------------------------------------------------------
if (-not [Environment]::Is64BitProcess -and [Environment]::Is64BitOperatingSystem) {
    $ps64 = Join-Path $env:WINDIR 'SysNative\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $ps64) {
        # -STA e' richiesto da WPF per l'interfaccia grafica.
        $rilancio = Get-ArgomentiRilancio -Parametri $PSBoundParameters -Script $MyInvocation.MyCommand.Path
        Start-Process -FilePath $ps64 -ArgumentList $rilancio -ErrorAction SilentlyContinue
        exit
    }
}

# ------------------------------------------------------------
#   Elevazione
#   A differenza della versione precedente, se l'utente rifiuta
#   l'UAC lo script lo dice invece di chiudersi in silenzio.
# ------------------------------------------------------------
if (-not (Test-Admin) -and -not $NoElevate) {
    Write-Host ''
    Write-Host '  Sono necessari i privilegi di amministratore.' -ForegroundColor Yellow
    Write-Host '  Riavvio con elevazione...' -ForegroundColor DarkGray
    $argomenti = Get-ArgomentiRilancio -Parametri $PSBoundParameters -Script $MyInvocation.MyCommand.Path
    try {
        Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -Verb RunAs -ArgumentList $argomenti -ErrorAction Stop
    } catch {
        Write-Host ''
        Write-Host '  [ERRORE] Elevazione annullata o non riuscita.' -ForegroundColor Red
        Write-Host '  Lo strumento non puo'' funzionare senza privilegi di amministratore.' -ForegroundColor Red
        Read-Host '  Premi INVIO per chiudere' | Out-Null
    }
    exit
}

# ------------------------------------------------------------
#   Inizializzazione
# ------------------------------------------------------------
# Configurazione: prima il file accanto allo script, poi quello
# indicato con -Config. La riga di comando ha l'ultima parola.
Import-Configurazione (Join-Path $Radice 'Toolbox.conf')
if ($Config) { Import-Configurazione $Config }
if ($Daltonici) { $script:CFG['colori'] = 'daltonici' }
if ($NoColor)   { $script:CFG['colori'] = 'no' }
if ($Report)    { $script:TB_REPORT = $Report }
if ($Json)      { $script:TB_JSON = $true; $Auto = $true; $Console = $true }

$script:TB_SISTEMA = ('{0} (build {1})' -f (Get-CimInstance Win32_OperatingSystem -EA SilentlyContinue).Caption, [Environment]::OSVersion.Version.Build)

$Host.UI.RawUI.WindowTitle = 'System Toolbox'
Initialize-ConsoleWidth | Out-Null
Initialize-Storico (Join-Path $Radice 'logs\storico.txt')
$LogPath = Initialize-Log -Directory (Join-Path $Radice 'logs') -Keep $script:CFG['log_da_conservare']
Set-DetailHandler -Handler { param($m) Write-Host ('      ' + $m) -ForegroundColor DarkGray }

Write-Log ('System Toolbox avviato - utente {0}\{1} - DryRun={2} - Auto={3}' -f $env:USERDOMAIN, $env:USERNAME, [bool]$DryRun, [bool]$Auto) 'INFO'

$script:Simula = [bool]$DryRun

# ============================================================
#   INTERFACCIA GRAFICA
#   E' il comportamento predefinito. Se WPF non e' caricabile
#   (installazione ridotta, PowerShell in modalita' vincolata)
#   si ricade sul menu testuale senza interrompere nulla.
# ============================================================
if (-not $Auto -and -not $Console) {
    $percorsoGui = Join-Path $Radice 'lib\GuiUI.ps1'
    $guiPronta   = $false
    $motivoGui   = ''

    if (-not (Test-Path -LiteralPath $percorsoGui)) {
        $motivoGui = 'lib\GuiUI.ps1 non trovato'
    } else {
        try {
            . $percorsoGui
            Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml -ErrorAction Stop
            $guiPronta = $true
        } catch {
            $motivoGui = $_.Exception.Message
        }
    }

    if ($guiPronta) {
        Write-Log 'Avvio interfaccia grafica' 'STEP'
        try {
            Start-Gui -Radice $Radice -LogPath $LogPath -DryRun:$DryRun
            Write-Log 'Sessione grafica terminata' 'INFO'
            exit 0
        } catch {
            # Se la finestra non si apre, la console e' stata magari gia'
            # nascosta: va rimessa in primo piano per mostrare l'errore.
            try { Show-ConsoleWindow } catch { }
            Write-Host ''
            Write-Host ('  [ERRORE] Interfaccia grafica non avviata: ' + $_.Exception.Message) -ForegroundColor Red
            Write-Host '  Passo al menu testuale.' -ForegroundColor DarkGray
            Write-Log ('GUI non avviata: ' + $_.Exception.Message) 'FAIL'
            Start-Sleep -Seconds 3
        }
    } else {
        Write-Host ''
        Write-Host ('  [INFO] Interfaccia grafica non disponibile: ' + $motivoGui) -ForegroundColor Yellow
        Write-Host '  Uso il menu testuale.' -ForegroundColor DarkGray
        Write-Log ('GUI non disponibile: ' + $motivoGui) 'WARN'
        Start-Sleep -Seconds 2
    }
}

# ============================================================
#   ANALISI
# ============================================================

function Invoke-Analisi {
    param([switch]$Rapida)

    Clear-Host
    $etichetta = 'Analisi completa del sistema'
    if ($Rapida) { $etichetta = 'Analisi rapida' }
    Write-Title $etichetta
    Write-Log ('--- ' + $etichetta) 'STEP'

    Show-Analisi -Rapida:$Rapida | Out-Null

    Write-Host ''
    Write-Dim ('Log della sessione: ' + $LogPath)
}


# ============================================================
#   ESECUZIONE DI UN INSIEME DI TASK
# ============================================================

function Invoke-Insieme {
    param(
        [Parameter(Mandatory=$true)][string]$Titolo,
        [Parameter(Mandatory=$true)]$Tasks,
        [switch]$SenzaConferma,
        [string]$Avvertenza = ''
    )

    if (@($Tasks).Count -eq 0) { Write-Warn 'Nessuna operazione selezionata.'; return @() }

    Clear-Host
    Write-Title $Titolo

    Write-Host ''
    Write-Host '  Operazioni previste:' -ForegroundColor White
    Write-Host ''
    Show-TaskDetail $Tasks

    Write-Host ''
    Write-Kv 'Operazioni' @($Tasks).Count 'White'
    Write-Kv 'Tempo stimato' (Format-Stima (Get-StimaTotale -Tasks $Tasks)) 'White'

    if ($Avvertenza) {
        Write-Host ''
        foreach ($riga in (Split-TextWidth -Testo $Avvertenza -Larghezza 70)) { Write-Warn $riga }
    }

    if ($script:Simula) {
        Write-Host ''
        Write-Host '  MODALITA'' SIMULAZIONE ATTIVA: nessuna modifica verra'' applicata.' -ForegroundColor Magenta
    }

    if (-not $SenzaConferma) {
        Write-Host ''
        if (-not (Read-YesNo 'Procedere?')) {
            Write-Dim 'Annullato.'
            return @()
        }
    }

    # Punto di ripristino: proposto solo quando serve davvero, cioe'
    # quando si toccano servizi, rete o componenti di Windows.
    $consiglio = Get-ConsiglioRipristino -Tasks $Tasks
    if ($consiglio.Consigliato -and -not $SenzaConferma -and -not $script:Simula) {
        Write-Host ''
        $frase = 'Punto di ripristino consigliato: ' + $consiglio.Motivo + '.'
        foreach ($riga in (Split-TextWidth -Testo $frase -Larghezza 70)) { Write-Warn $riga }
        Write-Dim ('Aggiunge ' + (Format-Stima (Get-Task -Id 'maint_restorepoint').Stima) + '.')
        Write-Host ''
        if (Read-YesNo 'Creare prima un punto di ripristino?' -DefaultSi) {
            Write-Host ''
            Write-Step '**' 'Punto di ripristino'
            $r = Invoke-Task -Task (Get-Task -Id 'maint_restorepoint')
            if ($r.Esito -eq 'OK') { Write-Ok '[fatto]' } else { Write-Warn '[non creato: si prosegue comunque]' }
        }
    }

    $spazioPrima = Get-FreeSpace
    # ArrayList: vedi nota in Core.ps1 su @() e List[object] in PS 5.1
    $risultati = New-Object System.Collections.ArrayList
    $n = 0
    $tot = @($Tasks).Count

    Write-Host ''
    Write-Title 'Esecuzione'

    foreach ($t in $Tasks) {
        $n++
        Write-Host ''
        Write-Step ('{0}/{1}' -f $n, $tot) $t.Nome
        $r = Invoke-Task -Task $t -DryRun:$script:Simula
        $risultati.Add($r) | Out-Null
        switch ($r.Esito) {
            'OK'       { Write-Ok   '[completato]' }
            'PARZIALE' { Write-Warn ('[completato con {0} avvisi]' -f $r.Errors.Count) }
            'FALLITO'  { Write-Err  '[non riuscito]' }
        }
    }

    $spazioDopo = Get-FreeSpace
    $delta = $spazioDopo - $spazioPrima
    if ($script:Simula -or $delta -lt 0) { $delta = -1 }

    Show-TaskSummary -Risultati $risultati -SpazioReale $delta
    Write-Host ''
    Write-Dim ('Log della sessione: ' + $LogPath)

    return @($risultati)
}

# ============================================================
#   FLUSSI SPECIFICI
# ============================================================

function Invoke-ResetRete {
    $tasks = Get-TaskSet -Nome 'ReteReset'
    $avv = 'Queste operazioni azzerano la configurazione di rete: eventuali IP statici, MTU personalizzati e componenti installati da VPN o antivirus verranno rimossi. Hanno effetto solo dopo il riavvio del PC. Usale per riparare una rete che non funziona, non come manutenzione periodica.'
    $ris = Invoke-Insieme -Titolo 'Rete - reset completo' -Tasks $tasks -Avvertenza $avv
    if (@($ris).Count -eq 0) { return }

    if ($script:Simula) { return }

    Write-Host ''
    Write-Warn 'Il riavvio e'' NECESSARIO per rendere effettivi questi reset.'
    if (Read-YesNo 'Riavviare ora il computer?') {
        Write-Log 'Riavvio richiesto dall''utente' 'INFO'
        Write-Host ''
        Write-Warn 'Riavvio programmato tra 60 secondi. Salva i documenti aperti.'
        Write-Dim  'Per annullare: apri un prompt e digita   shutdown /a'
        shutdown.exe /r /t 60 /c 'Riavvio per applicare le modifiche di rete. Salva i tuoi documenti.'
    } else {
        Write-Log 'Riavvio rimandato dall''utente' 'INFO'
        Write-Dim 'Ricordati di riavviare prima di usare la rete.'
    }
}

function Invoke-Personalizzata {
    Clear-Host
    Write-Title 'Selezione personalizzata'
    $tutti = @(Get-AllTask)
    Write-Host ''
    Show-TaskList -Tasks $tutti -Numerati
    Write-Host ''
    Write-Dim 'Indica i numeri separati da virgola (esempio: 1,3,7). Invio per annullare.'
    Write-Host '  Selezione: ' -NoNewline -ForegroundColor White
    $sel = Read-Host
    if ([string]::IsNullOrWhiteSpace($sel)) { return }

    $scelti = New-Object System.Collections.ArrayList
    foreach ($pezzo in ($sel -split '[,; ]+')) {
        if (-not $pezzo) { continue }
        $idx = 0
        if ([int]::TryParse($pezzo.Trim(), [ref]$idx)) {
            if ($idx -ge 1 -and $idx -le $tutti.Count) { $scelti.Add($tutti[$idx - 1]) | Out-Null }
            else { Write-Warn ('Numero fuori intervallo: {0}' -f $idx) }
        } else {
            Write-Warn ('Valore non valido: {0}' -f $pezzo)
        }
    }
    if ($scelti.Count -eq 0) { Write-Warn 'Nessuna operazione valida selezionata.'; Wait-Enter; return }

    $ris = Invoke-Insieme -Titolo 'Operazioni personalizzate' -Tasks @($scelti)
    if (@($ris | Where-Object { $_.Reboot }).Count -gt 0 -and -not $script:Simula) {
        Write-Host ''
        if (Read-YesNo 'Alcune modifiche richiedono il riavvio. Riavviare ora?') {
            shutdown.exe /r /t 60 /c 'Riavvio richiesto da System Toolbox.'
            Write-Dim 'Per annullare: shutdown /a'
        }
    }
}

function Invoke-ManutenzioneConsigliata {
    param([switch]$SenzaConferma)
    $tasks = @(Get-TaskSet -Nome 'PuliziaSicura') + @(Get-TaskSet -Nome 'RetePulizia')
    return (Invoke-Insieme -Titolo 'Manutenzione consigliata' -Tasks $tasks -SenzaConferma:$SenzaConferma)
}

# ============================================================
#   MODALITA' NON INTERATTIVA
# ============================================================

if ($Auto) {
    Write-Log 'Modalita automatica' 'STEP'
    if ($script:TB_JSON) {
        # In modalita' JSON l'output leggibile sporcherebbe il
        # documento: si esegue in silenzio e si stampa solo il JSON.
        Invoke-Analisi -Rapida *> $null
        Invoke-ManutenzioneConsigliata -SenzaConferma *> $null
    } else {
        Invoke-Analisi -Rapida
        Invoke-ManutenzioneConsigliata -SenzaConferma | Out-Null
        Write-Host ''
        Write-Title 'Esecuzione automatica terminata'
        Write-Dim ('Log: ' + $LogPath)
        if ($script:TB_REPORT) { Write-Dim ('Report: ' + $script:TB_REPORT) }
    }
    Write-Log 'Fine modalita automatica' 'INFO'
    Export-Report
    Write-Json
    exit (Get-EsitoCodice)
}

# ============================================================
#   MENU
# ============================================================

function Show-Menu {
    Clear-Host
    Write-Title 'System Toolbox'
    Write-Host ''
    Write-Host '   ANALISI' -ForegroundColor Green
    Write-Host '     1)  Analisi completa del sistema'
    Write-Host '     2)  Analisi rapida (senza aggiornamenti ed eventi)'
    Write-Host ''
    Write-Host '   PULIZIA' -ForegroundColor Green
    Write-Host '     3)  Pulizia sicura              ' -NoNewline
    Write-Host 'temp, cestino, dump, cache di sistema' -ForegroundColor DarkGray
    Write-Host '     4)  Pulizia avanzata            ' -NoNewline
    Write-Host 'browser, miniature, Windows Update, DISM' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '   RETE' -ForegroundColor Green
    Write-Host '     5)  Refresh leggero             ' -NoNewline
    Write-Host 'DNS, ARP, IP - nessun riavvio' -ForegroundColor DarkGray
    Write-Host '     6)  Reset completo              ' -NoNewline
    Write-Host 'Winsock e TCP/IP - richiede riavvio' -ForegroundColor Magenta
    Write-Host ''
    Write-Host '   MANUTENZIONE' -ForegroundColor Green
    Write-Host '     7)  Integrita'' del sistema       ' -NoNewline
    Write-Host 'punto di ripristino, SFC, DISM' -ForegroundColor DarkGray
    Write-Host '     8)  Manutenzione consigliata    ' -NoNewline
    Write-Host 'pulizia sicura + refresh rete' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '   ALTRO' -ForegroundColor Green
    Write-Host '     9)  Selezione personalizzata'
    Write-Host '     L)  Apri la cartella dei log'
    Write-Host '     S)  Modalita'' simulazione: ' -NoNewline
    if ($script:Simula) { Write-Host 'ATTIVA' -ForegroundColor Magenta }
    else                { Write-Host 'disattivata' -ForegroundColor DarkGray }
    Write-Host '     0)  Esci'
    Write-Host ''
    Write-Host ('  ' + ('-' * 76)) -ForegroundColor DarkGray
    Write-Host '   Scelta: ' -NoNewline -ForegroundColor White
}

while ($true) {
    Show-Menu
    $scelta = (Read-Host).Trim().ToUpper()

    switch ($scelta) {
        '1' { Invoke-Analisi;          Wait-Enter }
        '2' { Invoke-Analisi -Rapida;  Wait-Enter }
        '3' {
            Invoke-Insieme -Titolo 'Pulizia sicura' -Tasks (Get-TaskSet -Nome 'PuliziaSicura') | Out-Null
            Wait-Enter
        }
        '4' {
            $avv = 'La pulizia avanzata chiude Esplora risorse per rigenerare le miniature, ferma temporaneamente i servizi di Windows Update e puo'' impiegare 10-20 minuti per la compattazione DISM. Chiudi i browser prima di procedere.'
            Invoke-Insieme -Titolo 'Pulizia avanzata' -Tasks (Get-TaskSet -Nome 'PuliziaAvanzata') -Avvertenza $avv | Out-Null
            Wait-Enter
        }
        '5' {
            Invoke-Insieme -Titolo 'Rete - refresh leggero' -Tasks (Get-TaskSet -Nome 'RetePulizia') | Out-Null
            Write-Host ''
            Write-Dim 'Verifica della connettivita'' dopo il refresh...'
            Show-SysNetwork (Get-SysNetwork)
            Wait-Enter
        }
        '6' { Invoke-ResetRete; Wait-Enter }
        '7' {
            $avv = 'SFC e DISM analizzano l''intera installazione di Windows: insieme possono richiedere 30-40 minuti e non vanno interrotti. DISM ha bisogno della connessione a Internet.'
            Invoke-Insieme -Titolo 'Integrita'' del sistema' -Tasks (Get-TaskSet -Nome 'Manutenzione') -Avvertenza $avv | Out-Null
            Wait-Enter
        }
        '8' { Invoke-ManutenzioneConsigliata | Out-Null; Wait-Enter }
        '9' { Invoke-Personalizzata; Wait-Enter }
        'L' {
            $cartella = Join-Path $Radice 'logs'
            if (Test-Path -LiteralPath $cartella) { Start-Process explorer.exe $cartella }
        }
        'S' {
            $script:Simula = -not $script:Simula
            Write-Log ('Modalita simulazione: {0}' -f $script:Simula) 'INFO'
        }
        '0' {
            Write-Log 'Sessione terminata' 'INFO'
            Export-Report
            Write-Host ''
            Write-Dim ('Log salvato in: ' + $LogPath)
            if ($script:TB_REPORT) { Write-Dim ('Report: ' + $script:TB_REPORT) }
            Write-Host ''
            exit (Get-EsitoCodice)
        }
        default {
            Write-Host ''
            Write-Warn 'Scelta non riconosciuta.'
            Start-Sleep -Milliseconds 900
        }
    }
}
