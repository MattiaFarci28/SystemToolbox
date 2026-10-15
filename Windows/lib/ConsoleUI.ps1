# ============================================================
#   ConsoleUI.ps1 - Rendering testuale
#
#   Tutto cio' che scrive a schermo sta qui. Le funzioni
#   Show-* consumano gli oggetti prodotti da Analysis.ps1.
#
#   Questo file e' condiviso con la GUI: nel thread di lavoro
#   della finestra, Write-Host viene sostituito da una funzione
#   che accoda i segmenti colorati al pannello di output. Cosi'
#   le stesse Show-* producono l'output in entrambe le
#   interfacce, senza duplicare una riga di rendering.
#   Conseguenza pratica: qui NON si possono usare Read-Host,
#   Clear-Host o altre primitive interattive di console.
#
#   Larghezza di riferimento: 78 colonne.
# ============================================================

Set-StrictMode -Version 1.0

$script:W = 78

# Adatta la larghezza alla finestra reale: con separatori piu' larghi
# del terminale le righe vanno a capo e il testo si accavalla.
function Initialize-ConsoleWidth {
    try {
        $larghezza = $Host.UI.RawUI.WindowSize.Width
        if ($larghezza -ge 50) {
            $script:W = [math]::Min($larghezza - 2, 78)
        }
    } catch { }
    return $script:W
}

# ------------------------------------------------------------
#   Primitive
# ------------------------------------------------------------
function Write-Title {
    param([string]$Testo)
    $linea = ' ' + ('=' * $script:W)
    Write-Host ''
    Write-Host $linea -ForegroundColor Cyan
    Write-Host ('   ' + $Testo.ToUpper()) -ForegroundColor Cyan
    Add-Report ''; Add-Report ("## " + $Testo); Add-Report ''

    Write-Host $linea -ForegroundColor Cyan
}

function Write-Section {
    param([string]$Testo)
    Write-Host ''
    Write-Host ('  [' + $Testo + ']') -ForegroundColor Green
    Add-Report ''; Add-Report ("## " + $Testo); Add-Report ''

    Write-Host ('  ' + ('-' * ($script:W - 2))) -ForegroundColor DarkGray
}

function Write-Kv {
    param([string]$Chiave, $Valore, [string]$Colore = 'Gray')
    Write-Host ('   {0,-16}: ' -f $Chiave) -NoNewline
    Write-Host $Valore -ForegroundColor $Colore
    Add-Report "- **$Chiave**: $Valore"
}

function Write-Step { param([string]$N, [string]$Testo) Write-Host ('  [{0}] {1}' -f $N, $Testo) -ForegroundColor Yellow }
# Ogni stato porta un SIMBOLO oltre al colore: in modalita'
# daltonici il colore smette di essere l'unico segnale, e il
# significato resta lo stesso in tutte le modalita'.
# Le funzioni alimentano anche il buffer del report, cosi' il
# documento esportato nasce dallo stesso codice che disegna.
function Write-Ok   { param([string]$T) Write-Host ('   [ok] ' + $T) -ForegroundColor (Get-ColoreStato 'ok');   Add-Report "> [ok] $T" }
function Write-Warn { param([string]$T) Write-Host ('   [!]  ' + $T) -ForegroundColor (Get-ColoreStato 'warn'); Add-Report "> [!] $T" }
function Write-Err  { param([string]$T) Write-Host ('   [X]  ' + $T) -ForegroundColor (Get-ColoreStato 'err');  Add-Report "> [X] $T" }
function Write-Dim  { param([string]$T) Write-Host ('   ' + $T) -ForegroundColor DarkGray; Add-Report $T }

# In modalita' daltonici verde e rosso, la coppia piu'
# problematica, diventano blu e arancione.
function Get-ColoreStato {
    param([string]$Stato)
    $daltonici = ($script:CFG['colori'] -eq 'daltonici')
    switch ($Stato) {
        'ok'   { if ($daltonici) { 'Cyan' }   else { 'Green' } }
        'warn' { if ($daltonici) { 'Yellow' } else { 'Yellow' } }
        'err'  { if ($daltonici) { 'Magenta' } else { 'Red' } }
        default { 'Gray' }
    }
}

function Get-Bar {
    param([int]$Pct, [int]$Larghezza = 24)
    if ($Pct -lt 0) { $Pct = 0 }
    if ($Pct -gt 100) { $Pct = 100 }
    $pieni = [math]::Floor($Pct * $Larghezza / 100)
    return (('#' * $pieni) + ('.' * ($Larghezza - $pieni)))
}

function Get-PctColor {
    param([int]$Pct, [int]$Giallo = 65, [int]$Rosso = 85)
    if ($Pct -ge $Rosso)  { return 'Red' }
    if ($Pct -ge $Giallo) { return 'Yellow' }
    return 'Green'
}

function Format-Durata {
    param($Ts)
    if ($null -eq $Ts) { return 'n/d' }
    if ($Ts.TotalDays -ge 1) { return ('{0}g {1}h {2}m' -f [int]$Ts.TotalDays, $Ts.Hours, $Ts.Minutes) }
    if ($Ts.TotalHours -ge 1) { return ('{0}h {1}m' -f [int]$Ts.TotalHours, $Ts.Minutes) }
    return ('{0}m {1}s' -f [int]$Ts.TotalMinutes, $Ts.Seconds)
}

function Wait-Enter {
    param([string]$Testo = 'Premi INVIO per tornare al menu')
    Write-Host ''
    Read-Host ('  ' + $Testo) | Out-Null
}

function Read-YesNo {
    param([string]$Domanda, [switch]$DefaultSi)
    $suffisso = '[s/N]'
    if ($DefaultSi) { $suffisso = '[S/n]' }
    while ($true) {
        Write-Host ('  ' + $Domanda + ' ' + $suffisso + ' ') -NoNewline -ForegroundColor White
        $r = Read-Host
        if ([string]::IsNullOrWhiteSpace($r)) { return [bool]$DefaultSi }
        if ($r -match '^[sSyY]') { return $true }
        if ($r -match '^[nN]')   { return $false }
    }
}

# ============================================================
#   RENDERING ANALISI
# ============================================================

function Show-SysSummary {
    param($D)
    Write-Section 'SISTEMA'
    $ver = $D.OS
    if ($D.Versione) { $ver = '{0} ({1})' -f $D.OS, $D.Versione }
    Write-Kv 'Sistema'   $ver 'White'
    Write-Kv 'Build'     $D.Build
    Write-Kv 'Macchina'  $D.Modello
    Write-Kv 'BIOS'      $D.Bios
    Write-Kv 'CPU'       $D.Cpu
    Write-Kv 'Core'      ('{0} core / {1} thread ({2})' -f $D.Core, $D.Thread, $D.Architettura)
    Write-Kv 'Utente'    $D.Utente
    if ($D.Installato) { Write-Kv 'Installato il' (Get-Date $D.Installato -Format 'dd/MM/yyyy') }
    if ($D.Uptime) {
        $col = 'Gray'
        if ($D.Uptime.TotalDays -ge $script:CFG['uptime_avviso_giorni']) { $col = 'Yellow' }
        Write-Kv 'Acceso da' (Format-Durata $D.Uptime) $col
        if ($D.Uptime.TotalDays -ge $script:CFG['uptime_avviso_giorni']) {
            Write-Dim 'Un riavvio periodico libera memoria e applica gli aggiornamenti in sospeso.'
        }
    }
}

function Show-SysWindowsSupport {
    param($D)
    Write-Section 'SUPPORTO DI WINDOWS'
    if (-not $D.Noto) {
        Write-Dim ('Build {0}: non presente nella tabella del ciclo di vita.' -f $D.Build)
        Write-Dim 'Aggiorna la tabella in lib\Analysis.ps1 se la versione e'' recente.'
        return
    }
    Write-Kv 'Versione' ('{0}  (build {1}, edizione {2})' -f $D.Nome, $D.Build, $D.Edizione) 'White'
    if ($D.Supportato) {
        $col = 'Green'
        if ($D.Giorni -le 120) { $col = 'Yellow' }
        Write-Host '   Aggiornamenti   : ' -NoNewline
        Write-Host ('supportata fino al {0} ({1} giorni)' -f (Get-Date $D.Scadenza -Format 'dd/MM/yyyy'), $D.Giorni) -ForegroundColor $col
        if ($D.Giorni -le 120) {
            Write-Warn 'Il supporto scade fra poco: pianifica l''aggiornamento di versione.'
        }
    } else {
        Write-Host '   Aggiornamenti   : ' -NoNewline
        Write-Host ('SUPPORTO TERMINATO il {0}, {1} giorni fa' -f (Get-Date $D.Scadenza -Format 'dd/MM/yyyy'), [math]::Abs($D.Giorni)) -ForegroundColor Red
        Write-Err 'Questa versione non riceve piu'' aggiornamenti di sicurezza per il sistema.'
        Write-Dim 'Le definizioni antivirus continuano ad arrivare, le patch di Windows no.'
        Write-Dim 'Rimedio: aggiornare Windows a una versione supportata.'
    }
}

function Show-SysVolume {
    param($D)
    Write-Section 'SPAZIO SU DISCO'
    if (-not $D -or @($D).Count -eq 0) { Write-Dim 'Nessun volume rilevato.'; return }
    foreach ($v in $D) {
        $col = Get-PctColor -Pct $v.PctUsato
        $et = ''
        if ($v.Etichetta) { $et = ' ' + $v.Etichetta }
        Write-Host ('   {0,-3}{1,-14} [' -f $v.Lettera, $et) -NoNewline
        Write-Host (Get-Bar -Pct $v.PctUsato) -ForegroundColor $col -NoNewline
        Write-Host ('] {0,3}%  {1} liberi su {2}' -f $v.PctUsato, (Format-Bytes $v.Liberi), (Format-Bytes $v.Totale))
        if ($v.PctUsato -ge $script:CFG['disco_critico']) { Write-Err '  ATTENZIONE: spazio quasi esaurito' }
        elseif ($v.PctUsato -ge $script:CFG['disco_avviso']) { Write-Warn '  Sotto il 20 per cento libero conviene fare spazio.' }
    }
}

function Show-SysDiskHealth {
    param($D)
    Write-Section 'SALUTE DISCHI (SMART)'
    if (-not $D -or @($D).Count -eq 0) { Write-Dim 'Dati SMART non disponibili su questo sistema.'; return }
    foreach ($d in $D) {
        $col = 'Green'
        if ($d.Salute -ne 'Healthy') { $col = 'Red' }
        Write-Host ('   {0}' -f $d.Nome) -ForegroundColor White
        Write-Host ('     {0} {1}  -  stato: ' -f $d.Tipo, (Format-Bytes $d.Dimensione)) -NoNewline
        Write-Host $d.Salute -ForegroundColor $col
        $dett = @()
        if ($null -ne $d.Ore)   { $dett += ('{0} ore di accensione' -f $d.Ore) }
        if ($null -ne $d.Usura) { $dett += ('usura {0}%' -f $d.Usura) }
        if ($null -ne $d.Temp -and $d.Temp -gt 0) { $dett += ('{0} gradi' -f $d.Temp) }
        if ($dett.Count -gt 0) { Write-Dim ('  ' + ($dett -join '  |  ')) }
        if ($d.ErrLettura -gt 0 -or $d.ErrScrittura -gt 0) {
            Write-Err ('  Errori non correggibili: {0} in lettura, {1} in scrittura - valuta un backup' -f $d.ErrLettura, $d.ErrScrittura)
        }
        if ($null -ne $d.Usura -and $d.Usura -ge 80) {
            Write-Warn '  Usura elevata: l''unita'' si avvicina a fine vita.'
        }
        if ($null -ne $d.Temp -and $d.Temp -ge 70) {
            Write-Err ('  Temperatura {0} gradi: sopra la soglia di sicurezza, verifica il raffreddamento.' -f $d.Temp)
        } elseif ($null -ne $d.Temp -and $d.Temp -ge 60) {
            Write-Warn ('  Temperatura {0} gradi: alta ma entro i limiti per un NVMe sotto carico.' -f $d.Temp)
        }
    }
}

function Show-SysMemory {
    param($D)
    Write-Section 'MEMORIA'
    $col = Get-PctColor -Pct $D.PctUsato
    Write-Host '   RAM              [' -NoNewline
    Write-Host (Get-Bar -Pct $D.PctUsato) -ForegroundColor $col -NoNewline
    Write-Host ('] {0,3}%  {1} usati su {2}' -f $D.PctUsato, (Format-Bytes $D.Usati), (Format-Bytes $D.Totale))
    if ($null -ne $D.PagefileTot -and $D.PagefileTot -gt 0) {
        Write-Kv 'File di paging' ('{0} usati su {1} allocati' -f (Format-Bytes $D.PagefileUsati), (Format-Bytes $D.PagefileTot))
    }
    if ($D.Moduli -and @($D.Moduli).Count -gt 0) {
        $desc = @($D.Moduli | ForEach-Object { '{0}: {1} @ {2} MHz' -f $_.Banco, (Format-Bytes $_.Capacita), $_.Velocita })
        Write-Kv 'Moduli' ($desc -join '  |  ')
        $col = 'Gray'
        if ($D.Modalita -like 'dual*')        { $col = 'Green' }
        elseif ($D.Modalita -like 'single*')  { $col = 'Yellow' }
        Write-Host '   Configurazione  : ' -NoNewline
        Write-Host $D.Modalita -ForegroundColor $col
        if ($D.Modalita -like 'single channel (probabile)') {
            Write-Warn 'Due moduli sullo stesso canale: spostandone uno si guadagna banda di memoria,'
            Write-Warn 'cosa che si sente soprattutto con la grafica integrata.'
        }
    }
}

function Show-SysPower {
    param($D)
    Write-Section 'ALIMENTAZIONE'
    if ($D.Piano) { Write-Kv 'Piano attivo' $D.Piano }
    if ($D.ModalitaAc) {
        $col = 'Green'
        if ($D.ModalitaAc -like 'Massimo risparmio*') { $col = 'Yellow' }
        Write-Host '   Con alimentatore: ' -NoNewline
        Write-Host $D.ModalitaAc -ForegroundColor $col
        if ($D.ModalitaAc -like 'Massimo risparmio*') {
            Write-Warn 'Con il portatile collegato alla corrente il risparmio energetico limita le'
            Write-Warn 'frequenze: passa a Bilanciata o Prestazioni migliori.'
        }
    }
    if ($D.Portatile -and $D.ModalitaDc) {
        $col = 'Green'
        if ($D.ModalitaDc -like 'Prestazioni migliori*') { $col = 'Yellow' }
        Write-Host '   A batteria      : ' -NoNewline
        Write-Host $D.ModalitaDc -ForegroundColor $col
        if ($D.ModalitaDc -like 'Prestazioni migliori*') {
            Write-Dim 'A batteria le prestazioni massime accorciano parecchio l''autonomia.'
        }
    }
    if (-not $D.Piano -and -not $D.ModalitaAc) {
        Write-Dim 'Impostazioni di alimentazione non leggibili.'
    }
}

function Show-SysProtection {
    param($D)
    Write-Section 'PROTEZIONE SISTEMA'
    if (-not $D.Leggibile) {
        if (-not $D.Admin) {
            Write-Dim 'Elenco non leggibile senza privilegi di amministratore.'
        } else {
            Write-Warn 'Punti di ripristino non elencabili: la protezione sistema e'' probabilmente disattivata.'
            Write-Dim 'Verifica con  SystemPropertiesProtection.exe  che su C: risulti Attivata.'
        }
        return
    }
    if ($D.Punti -eq 0) {
        Write-Warn 'Nessun punto di ripristino presente.'
        Write-Dim 'Se la protezione e'' disattivata, la relativa operazione di questo strumento fallira''.'
    } else {
        Write-Host '   Punti disponibili: ' -NoNewline
        Write-Host $D.Punti -ForegroundColor Green
        if ($D.Ultimo) { Write-Kv 'Ultimo' (Get-Date $D.Ultimo -Format 'dd/MM/yyyy HH:mm') }
    }
    if ($D.Usato -and $D.Massimo) {
        Write-Kv 'Spazio copie shadow' ('{0} usati su {1} massimi' -f $D.Usato, $D.Massimo)
        Write-Dim 'Al raggiungimento del tetto Windows elimina da solo i punti piu'' vecchi.'
    }
}

function Show-SysDeviceProblem {
    param($D)
    Write-Section 'DISPOSITIVI E DRIVER'
    if (-not $D -or @($D).Count -eq 0) {
        Write-Ok 'Nessun dispositivo con problemi di driver.'
        return
    }
    Write-Warn ('{0} dispositivi con problemi:' -f @($D).Count)
    foreach ($d in $D) {
        $nome = $d.Nome
        if ($nome -and $nome.Length -gt 46) { $nome = $nome.Substring(0, 43) + '...' }
        Write-Host ('   {0,-48} {1}' -f $nome, $d.Motivo) -ForegroundColor Yellow
    }
    Write-Dim 'Si risolvono da Gestione dispositivi, aggiornando o reinstallando il driver.'
}

function Show-SysMaintenance {
    param($D)
    Write-Section 'MANUTENZIONE AUTOMATICA'
    $fmt = '   {0,-21}: '

    Write-Host ($fmt -f 'Sensore memoria') -NoNewline
    if ($null -eq $D.SensoreMemoria)   { Write-Host 'non leggibile' -ForegroundColor DarkGray }
    elseif ($D.SensoreMemoria)         { Write-Host 'attivo' -ForegroundColor Green }
    else                               { Write-Host 'disattivato' -ForegroundColor Yellow }

    Write-Host ($fmt -f 'TRIM (SSD)') -NoNewline
    if ($null -eq $D.Trim)  { Write-Host 'non leggibile' -ForegroundColor DarkGray }
    elseif ($D.Trim)        { Write-Host 'attivo' -ForegroundColor Green }
    else                    { Write-Host 'DISATTIVATO' -ForegroundColor Red }

    Write-Host ($fmt -f 'Ottimizzazione unita') -NoNewline
    if ($null -eq $D.OttPianificata)  { Write-Host 'non leggibile' -ForegroundColor DarkGray }
    elseif ($D.OttPianificata)        { Write-Host 'pianificata' -ForegroundColor Green }
    else                              { Write-Host 'disattivata' -ForegroundColor Yellow }
    if ($D.UltimaOtt) { Write-Kv 'Ultima esecuzione' (Get-Date $D.UltimaOtt -Format 'dd/MM/yyyy HH:mm') }

    if ($D.SensoreMemoria -eq $false) {
        Write-Dim 'Attivando il Sensore memoria buona parte di questa pulizia diventa automatica.'
    }
}

function Show-SysSpazioRecuperabile {
    param($D)
    Write-Section 'SPAZIO RECUPERABILE'
    if (-not $D -or @($D).Count -eq 0) {
        Write-Ok 'Niente di rilevante da recuperare oltre alla pulizia ordinaria.'
        return
    }
    foreach ($v in $D) {
        Write-Host ('   {0,-42} ' -f $v.Nome) -NoNewline
        Write-Host (Format-Bytes $v.Byte) -ForegroundColor Yellow
        foreach ($r in (Split-TextWidth -Testo $v.Nota -Larghezza 64)) { Write-Dim ('  ' + $r) }
    }
}

function Show-SysDiskEvent {
    param($D, [int]$Giorni = 30)
    Write-Section ('EVENTI DEL DISCO - ULTIMI {0} GIORNI' -f $Giorni)
    if (-not $D -or @($D).Count -eq 0) {
        Write-Ok 'Nessun errore hardware del disco registrato.'
        return
    }
    foreach ($e in $D) {
        Write-Host ('   {0,4} x  ID {1,-4} {2}' -f $e.Conteggio, $e.Id, $e.Motivo) -ForegroundColor Red
        Write-Dim ('       ultimo: {0}  ({1})' -f (Get-Date $e.Ultimo -Format 'dd/MM/yyyy HH:mm'), $e.Provider)
    }
    Write-Err 'Questi eventi precedono spesso un guasto: fai un backup e controlla lo stato SMART.'
}

function Show-SysTopProcess {
    param($D, [int]$Top = 6)
    Write-Section ('PROCESSI - TOP {0} PER CPU' -f $Top)
    Write-Dim 'Uso reale campionato su 1 secondo, istanze dello stesso programma raggruppate.'
    foreach ($p in $D.Cpu) {
        $et = $p.Nome
        if ($p.Istanze -gt 1) { $et = '{0} ({1} processi)' -f $p.Nome, $p.Istanze }
        $col = Get-PctColor -Pct ([int]$p.Pct) -Giallo 25 -Rosso 60
        Write-Host ('   {0,-34}' -f $et) -NoNewline
        Write-Host ('{0,6:N1} %' -f $p.Pct) -ForegroundColor $col -NoNewline
        Write-Host ('   RAM {0,10}' -f (Format-Bytes $p.Ram))
    }

    Write-Section ('PROCESSI - TOP {0} PER MEMORIA' -f $Top)
    foreach ($p in $D.Ram) {
        $et = $p.Nome
        if ($p.Istanze -gt 1) { $et = '{0} ({1} processi)' -f $p.Nome, $p.Istanze }
        Write-Host ('   {0,-34}{1,10}   CPU {2,5:N1} %' -f $et, (Format-Bytes $p.Ram), $p.Pct)
    }
}

function Show-SysService {
    param($D)
    Write-Section 'SERVIZI'
    foreach ($s in $D) {
        $sym = '[ok]'; $col = 'Green'
        if ($s.Problema)                     { $sym = '[!!]'; $col = 'Red' }
        elseif ($s.Stato -ne 'Running')      { $sym = '[--]'; $col = 'DarkGray' }
        Write-Host ('   {0}  {1,-26} {2,-9}' -f $sym, $s.Etichetta, $s.Stato) -ForegroundColor $col -NoNewline
        Write-Host ('avvio: {0}' -f $s.Avvio) -ForegroundColor DarkGray
    }
    $ko = @($D | Where-Object { $_.Problema })
    if ($ko.Count -gt 0) {
        foreach ($k in $ko) { Write-Warn ('{0}: {1}' -f $k.Etichetta, $k.Motivo) }
    } else {
        Write-Dim 'Nessun servizio critico in stato anomalo.'
    }
}

function Show-SysSecurity {
    param($D)
    Write-Section 'SICUREZZA'
    $fmt = '   {0,-21}: '
    if ($D.Defender) {
        $dd = $D.Defender
        $col = 'Green'; $txt = 'attiva'
        if (-not $dd.TempoReale) { $col = 'Red'; $txt = 'DISATTIVATA' }
        Write-Host ($fmt -f 'Protezione realtime') -NoNewline
        Write-Host $txt -ForegroundColor $col
        $colF = 'Green'
        if ($dd.EtaFirme -ge 3) { $colF = 'Yellow' }
        if ($dd.EtaFirme -ge 7) { $colF = 'Red' }
        Write-Host ($fmt -f 'Firme antivirus') -NoNewline
        Write-Host ('{0} giorni fa' -f $dd.EtaFirme) -ForegroundColor $colF
        if ($dd.UltimaRapida) {
            Write-Host ($fmt -f 'Ultima scansione') -NoNewline
            Write-Host (Get-Date $dd.UltimaRapida -Format 'dd/MM/yyyy HH:mm')
        }
        if ($null -ne $dd.Tamper) {
            Write-Host ($fmt -f 'Tamper protection') -NoNewline
            Write-Host $(if ($dd.Tamper) { 'attiva' } else { 'non attiva' })
        }
    } else {
        Write-Dim 'Microsoft Defender non interrogabile (potrebbe esserci un antivirus di terze parti).'
    }

    if (@($D.Firewall).Count -gt 0) {
        $spenti = @($D.Firewall | Where-Object { -not $_.Attivo })
        $col = 'Green'; $txt = 'tutti i profili attivi'
        if ($spenti.Count -gt 0) { $col = 'Red'; $txt = ('DISATTIVO su: ' + (($spenti | ForEach-Object { $_.Profilo }) -join ', ')) }
        Write-Host '   Firewall             : ' -NoNewline
        Write-Host $txt -ForegroundColor $col
    }

    if (@($D.Crittografia).Count -gt 0) {
        foreach ($c in $D.Crittografia) {
            $col = 'Yellow'
            if ($c.Stato -eq 'On') { $col = 'Green' }
            Write-Host ('   Crittografia {0,-8}: ' -f $c.Volume) -NoNewline
            Write-Host $c.Stato -ForegroundColor $col
        }
    } else {
        Write-Dim 'Crittografia disco: non disponibile su questa edizione di Windows.'
    }

    if ($null -ne $D.Uac) {
        $col = 'Green'; $txt = 'attivo'
        if (-not $D.Uac) { $col = 'Red'; $txt = 'DISATTIVATO' }
        Write-Host '   Controllo account UAC: ' -NoNewline
        Write-Host $txt -ForegroundColor $col
    }
}

function Show-SysUpdate {
    param($D)
    Write-Section 'AGGIORNAMENTI WINDOWS'
    if (-not $D.Ok) {
        Write-Dim ('Interrogazione non riuscita: ' + $D.Errore)
        return
    }
    if ($D.Conteggio -eq 0) {
        Write-Ok 'Nessun aggiornamento in sospeso.'
        return
    }
    Write-Warn ('{0} aggiornamenti disponibili:' -f $D.Conteggio)
    $i = 0
    foreach ($t in $D.Titoli) {
        if ($i -ge 6) { Write-Dim ('  ... e altri {0}' -f ($D.Conteggio - 6)); break }
        $riga = $t
        if ($riga.Length -gt 66) { $riga = $riga.Substring(0, 63) + '...' }
        Write-Dim ('  - ' + $riga)
        $i++
    }
}

# Win32_StartupCommand restituisce percorsi di registro lunghissimi:
# tagliarli a meta' non dice nulla, meglio tradurli in etichette.
function Format-StartupOrigin {
    param([string]$Origine)
    if (-not $Origine) { return '' }
    switch -Regex ($Origine) {
        'Common Startup'                  { return 'Avvio automatico (tutti gli utenti)' }
        'Startup'                         { return 'Avvio automatico (cartella)' }
        '^HKLM|HKEY_LOCAL_MACHINE'        { return 'Registro (tutti gli utenti)' }
        '^HKU|^HKCU|HKEY_USERS|HKEY_CURRENT_USER' { return 'Registro (utente)' }
        default {
            if ($Origine.Length -gt 36) { return ('...' + $Origine.Substring($Origine.Length - 33)) }
            return $Origine
        }
    }
}

function Show-SysStartup {
    param($D, [int]$Top = 12)
    Write-Section 'PROGRAMMI ALL''AVVIO'
    $n = @($D).Count
    if ($n -eq 0) { Write-Dim 'Nessun elemento rilevato.'; return }
    $attivi = @($D | Where-Object { $_.Attivo })
    $spenti = @($D | Where-Object { -not $_.Attivo })

    Write-Host ('   {0} voci registrate: ' -f $n) -NoNewline
    Write-Host ('{0} attive' -f $attivi.Count) -ForegroundColor $(if ($attivi.Count -ge $script:CFG['avvii_avviso']) { 'Yellow' } else { 'Green' }) -NoNewline
    Write-Host (', {0} gia'' disattivate' -f $spenti.Count) -ForegroundColor DarkGray

    foreach ($s in (@($D) | Select-Object -First $Top)) {
        $nome = $s.Nome
        if ($nome.Length -gt 30) { $nome = $nome.Substring(0, 27) + '...' }
        if ($s.Attivo) {
            Write-Host ('   [on ] {0,-32} ' -f $nome) -NoNewline
        } else {
            Write-Host ('   [off] {0,-32} ' -f $nome) -NoNewline -ForegroundColor DarkGray
        }
        Write-Host (Format-StartupOrigin $s.Origine) -ForegroundColor DarkGray
    }
    if ($n -gt $Top) { Write-Dim ('  ... e altre {0} voci' -f ($n - $Top)) }
    if ($attivi.Count -ge $script:CFG['avvii_avviso']) {
        Write-Warn 'Molti programmi in avvio automatico: e'' la causa piu'' comune di boot lento.'
        Write-Dim 'Si disattivano da Gestione attivita'', scheda Avvio.'
    }
}

function Show-SysEventError {
    param($D, [int]$Giorni = 7)
    Write-Section ('ERRORI DI SISTEMA - ULTIMI {0} GIORNI' -f $Giorni)
    if (-not $D -or @($D).Count -eq 0) { Write-Ok 'Nessun errore critico registrato.'; return }
    foreach ($e in $D) {
        $col = 'Yellow'
        if ($e.Conteggio -ge 20) { $col = 'Red' }
        Write-Host ('   {0,4} x  {1} (ID {2})' -f $e.Conteggio, $e.Provider, $e.Id) -ForegroundColor $col
        if ($e.Messaggio) {
            $m = $e.Messaggio
            if ($m.Length -gt 68) { $m = $m.Substring(0, 65) + '...' }
            Write-Dim ('       ' + $m)
        }
    }
}

function Show-SysBattery {
    param($D)
    if (-not $D) { return }
    Write-Section 'BATTERIA'
    Write-Kv 'Carica attuale' ('{0}%' -f $D.Carica)
    if ($null -ne $D.SalutePct) {
        $col = Get-PctColor -Pct (100 - $D.SalutePct) -Giallo 20 -Rosso 40
        Write-Host '   Salute          : ' -NoNewline
        Write-Host ('{0}%  ({1:N0} mWh su {2:N0} mWh di progetto)' -f $D.SalutePct, $D.Attuale, $D.Progetto) -ForegroundColor $col
    } else {
        Write-Dim 'Capacita'' di progetto non leggibile ne'' da WMI ne'' dal report di powercfg.'
    }
    if ($null -ne $D.Cicli -and $D.Cicli -gt 0) {
        Write-Kv 'Cicli di carica' $D.Cicli
    }
}

function Show-SysNetwork {
    param($D)
    Write-Section 'RETE'
    $reali    = @($D.Schede | Where-Object { -not $_.Virtuale })
    $virtuali = @($D.Schede | Where-Object { $_.Virtuale })

    if ($reali.Count -eq 0) { Write-Warn 'Nessuna scheda di rete con connettivita'' attiva.' }
    foreach ($s in $reali) {
        Write-Host ('   {0}' -f $s.Nome) -ForegroundColor White
        Write-Dim ('  {0}  -  {1}' -f $s.Descrizione, $s.Velocita)
        Write-Kv '  Indirizzo IP' ('{0}  ({1})' -f $s.Ip, $s.Origine)
        if ($s.Gateway) { Write-Kv '  Gateway' $s.Gateway }
        if (@($s.Dns).Count -gt 0) { Write-Kv '  Server DNS' (($s.Dns) -join ', ') }
    }
    if ($virtuali.Count -gt 0) {
        Write-Dim ('{0} schede virtuali senza connettivita'' ignorate: {1}' -f `
                   $virtuali.Count, (($virtuali | ForEach-Object { $_.Nome }) -join ', '))
    }

    if ($null -ne $D.PingOk) {
        Write-Host ''
        Write-Host '   Connettivita IP  : ' -NoNewline
        if ($D.PingOk) { Write-Host 'ok (ping 1.1.1.1)' -ForegroundColor Green }
        else           { Write-Host 'NESSUNA RISPOSTA' -ForegroundColor Red }

        Write-Host '   Risoluzione DNS  : ' -NoNewline
        if ($D.DnsOk) { Write-Host ('ok ({0} ms)' -f $D.DnsMs) -ForegroundColor Green }
        else          { Write-Host 'FALLITA' -ForegroundColor Red }

        Write-Host '   Navigazione HTTPS: ' -NoNewline
        if ($D.HttpsOk) { Write-Host 'ok' -ForegroundColor Green }
        else            { Write-Host 'FALLITA' -ForegroundColor Red }

        if ($D.PingOk -and -not $D.DnsOk) {
            Write-Warn 'La rete funziona ma i nomi non vengono risolti: problema di DNS.'
        }
    }
}

function Show-RebootPending {
    param($D)
    Write-Section 'RIAVVIO IN SOSPESO'
    if (-not $D.Pending) { Write-Ok 'Nessun riavvio richiesto.'; return }
    Write-Warn 'E'' richiesto un riavvio per completare le seguenti operazioni:'
    foreach ($m in $D.Motivi) { Write-Dim ('  - ' + $m) }
}

# ============================================================
#   ANALISI COMPLETA
#   Orchestrazione condivisa fra menu console e GUI: raccoglie,
#   mostra e alla fine sintetizza cio' che merita attenzione.
#   Restituisce l'elenco degli avvisi.
# ============================================================

function Show-Analisi {
    param([switch]$Rapida)

    $avvisi = New-Object System.Collections.Generic.List[string]

    # La cache CIM vale per una sola analisi: se non si svuotasse,
    # la seconda esecuzione mostrerebbe i dati della prima.
    Clear-CimCache

    # La ricerca degli aggiornamenti parte subito, in parallelo:
    # e' la sezione piu' lenta e non dipende dalle altre.
    if (-not $Rapida) { Start-SysUpdateJob }

    Show-SysSummary (Get-SysSummary)

    # Il supporto di Windows sta anche nell'analisi rapida: costa
    # niente ed e' l'informazione piu' importante di tutte.
    $sup = Get-SysWindowsSupport
    Show-SysWindowsSupport $sup
    if ($sup.Noto -and -not $sup.Supportato) {
        $avvisi.Add(('{0} non riceve piu'' aggiornamenti di sicurezza dal {1}: aggiorna Windows a una versione supportata.' -f `
                     $sup.Nome, (Get-Date $sup.Scadenza -Format 'dd/MM/yyyy'))) | Out-Null
    } elseif ($sup.Noto -and $sup.Giorni -le 120) {
        $avvisi.Add(('Il supporto di {0} scade fra {1} giorni.' -f $sup.Nome, $sup.Giorni)) | Out-Null
    }

    $vol = Get-SysVolume
    Show-SysVolume $vol
    foreach ($v in $vol) {
        if ($v.PctUsato -ge $script:CFG['disco_critico']) { $avvisi.Add(('Il disco {0} e'' pieno al {1}%: libera spazio.' -f $v.Lettera, $v.PctUsato)) | Out-Null }
        elseif ($v.PctUsato -ge $script:CFG['disco_avviso']) { $avvisi.Add(('Il disco {0} e'' al {1}%: conviene fare spazio prima che si riempia.' -f $v.Lettera, $v.PctUsato)) | Out-Null }
    }

    $mem = Get-SysMemory
    Show-SysMemory $mem
    if ($mem.PctUsato -ge $script:CFG['ram_critica']) { $avvisi.Add('Memoria RAM quasi satura: chiudi qualche applicazione o valuta un upgrade.') | Out-Null }
    if ($null -ne $mem.PagefileUsati -and $mem.PagefileUsati -ge ([long]$script:CFG['swap_avviso_mb'] * 1MB)) {
        $avvisi.Add(('File di paging in uso per {0}: la RAM non basta per il carico attuale.' -f (Format-Bytes $mem.PagefileUsati))) | Out-Null
    }
    if ($mem.Modalita -eq 'single channel (probabile)') {
        $avvisi.Add('I moduli di RAM sembrano sullo stesso canale: spostandone uno si guadagna banda di memoria.') | Out-Null
    }

    Show-SysTopProcess (Get-SysTopProcess)

    if (-not $Rapida) {
        $pow = Get-SysPower
        Show-SysPower $pow
        if ($pow.ModalitaAc -like 'Massimo risparmio*') {
            $avvisi.Add('Modalita'' risparmio energetico attiva anche con l''alimentatore collegato: limita le prestazioni.') | Out-Null
        }

        $salute = Get-SysDiskHealth
        Show-SysDiskHealth $salute
        foreach ($d in $salute) {
            if ($d.Salute -ne 'Healthy') { $avvisi.Add(('Disco "{0}" in stato {1}: esegui subito un backup.' -f $d.Nome, $d.Salute)) | Out-Null }
            if ($null -ne $d.Temp -and $d.Temp -ge 70) { $avvisi.Add(('Disco "{0}" a {1} gradi: verifica il raffreddamento.' -f $d.Nome, $d.Temp)) | Out-Null }
            if ($null -ne $d.Usura -and $d.Usura -ge 80) { $avvisi.Add(('Disco "{0}" con usura al {1}%: pianifica la sostituzione.' -f $d.Nome, $d.Usura)) | Out-Null }
        }
    }

    $svc = Get-SysService
    Show-SysService $svc
    foreach ($s in ($svc | Where-Object { $_.Problema })) {
        $avvisi.Add(('Servizio "{0}": {1}.' -f $s.Etichetta, $s.Motivo)) | Out-Null
    }

    $sec = Get-SysSecurity
    Show-SysSecurity $sec
    if ($sec.Defender -and -not $sec.Defender.TempoReale) { $avvisi.Add('La protezione in tempo reale di Defender e'' disattivata.') | Out-Null }
    if ($sec.Defender -and $sec.Defender.EtaFirme -ge 7)  { $avvisi.Add('Le firme antivirus hanno piu'' di una settimana.') | Out-Null }
    foreach ($f in ($sec.Firewall | Where-Object { -not $_.Attivo })) {
        $avvisi.Add(('Firewall disattivato sul profilo {0}.' -f $f.Profilo)) | Out-Null
    }

    $bat = Get-SysBattery
    if ($bat) {
        Show-SysBattery $bat
        if ($null -ne $bat.SalutePct -and $bat.SalutePct -lt 60) {
            $avvisi.Add(('Salute della batteria al {0}%: sostituzione consigliata.' -f $bat.SalutePct)) | Out-Null
        }
    }

    Write-Host ''
    Write-Dim 'Verifica della rete in corso...'
    Show-SysNetwork (Get-SysNetwork -SkipTest:$Rapida)

    if (-not $Rapida) {
        Write-Host ''
        Write-Dim 'Interrogazione di Windows Update, puo'' richiedere fino a un minuto...'
        $upd = Get-SysUpdate
        Show-SysUpdate $upd
        if ($upd.Ok -and $upd.Conteggio -gt 0) {
            $avvisi.Add(('{0} aggiornamenti di Windows in sospeso.' -f $upd.Conteggio)) | Out-Null
        }

        $avvio = Get-SysStartup
        Show-SysStartup $avvio
        $avviiAttivi = @($avvio | Where-Object { $_.Attivo }).Count
        if ($avviiAttivi -ge $script:CFG['avvii_avviso']) {
            $avvisi.Add(('{0} programmi in avvio automatico: e'' la causa piu'' comune di boot lento.' -f $avviiAttivi)) | Out-Null
        }

        $prot = Get-SysProtection
        Show-SysProtection $prot
        if ($prot.Admin -and ((-not $prot.Leggibile) -or $prot.Punti -eq 0)) {
            $avvisi.Add('Nessun punto di ripristino disponibile: verifica che la protezione sistema sia attiva su C:.') | Out-Null
        }

        $disp = Get-SysDeviceProblem
        Show-SysDeviceProblem $disp
        if (@($disp).Count -gt 0) {
            $avvisi.Add(('{0} dispositivi con problemi di driver.' -f @($disp).Count)) | Out-Null
        }

        $manu = Get-SysMaintenance
        Show-SysMaintenance $manu
        if ($manu.Trim -eq $false)           { $avvisi.Add('TRIM disattivato: sull''SSD peggiora prestazioni e durata.') | Out-Null }
        if ($manu.SensoreMemoria -eq $false) { $avvisi.Add('Sensore memoria disattivato: attivandolo la pulizia diventa automatica.') | Out-Null }

        Write-Host ''
        Write-Dim 'Calcolo dello spazio recuperabile...'
        Show-SysSpazioRecuperabile (Get-SysSpazioRecuperabile)

        Show-SysEventError (Get-SysEventError -Giorni 7)

        $evd = Get-SysDiskEvent -Giorni 30
        Show-SysDiskEvent $evd -Giorni 30
        if (@($evd).Count -gt 0) {
            $avvisi.Add('Errori hardware del disco nel registro eventi: fai un backup e controlla lo stato SMART.') | Out-Null
        }
    }

    $rb = Test-RebootPending
    Show-RebootPending $rb
    if ($rb.Pending) { $avvisi.Add('Riavvio in sospeso: completalo prima di altre manutenzioni.') | Out-Null }

    # --- confronto con l'esecuzione precedente ---
    $conf = Compare-Storico
    if ($conf) {
        Write-Section 'RISPETTO ALL''ULTIMA VOLTA'
        $quando = if ($conf.Giorni -eq 0) { 'oggi' } else { ('{0} giorni fa' -f $conf.Giorni) }
        if ($conf.Delta -ge 0) {
            Write-Kv 'Spazio libero' ('{0} in piu'' rispetto a {1}' -f (Format-Bytes $conf.Delta), $quando)
        } else {
            Write-Kv 'Spazio libero' ('{0} rispetto a {1}' -f (Format-Bytes $conf.Delta), $quando)
        }
        Write-Kv 'Avvisi' ('{0} allora, {1} adesso' -f $conf.Avvisi, $avvisi.Count)
    }

    Write-Title 'Cosa merita attenzione'
    if ($avvisi.Count -eq 0) {
        Write-Ok 'Nessuna criticita'' rilevata. Il sistema risulta in ordine.'
    } else {
        $i = 1
        foreach ($a in $avvisi) {
            Write-Host ('   {0}. {1}' -f $i, $a) -ForegroundColor Yellow
            Add-Report "> [!] $a"
            Add-JsonAvviso $a
            Set-EsitoAvviso
            Write-Log ('AVVISO: ' + $a) 'WARN'
            $i++
        }
    }

    Write-Storico $avvisi.Count
    return $avvisi
}

# ============================================================
#   RENDERING TASK
# ============================================================

function Show-TaskList {
    param($Tasks, [switch]$Numerati)
    $i = 1
    foreach ($t in $Tasks) {
        $tag = ''
        $col = 'Gray'
        switch ($t.Livello) {
            'Avanzato' { $tag = '[avanzato]'; $col = 'Yellow' }
            'Riavvio'  { $tag = '[riavvio] '; $col = 'Magenta' }
            default    { $tag = '[sicuro]  '; $col = 'DarkGray' }
        }
        if ($t.ContainsKey('Sconsigliato') -and $t.Sconsigliato) { $tag = '[SCONSIG.]'; $col = 'Red' }
        $prefisso = '     - '
        if ($Numerati) { $prefisso = ('   {0,2})  ' -f $i) }
        Write-Host $prefisso -NoNewline
        Write-Host $tag -ForegroundColor $col -NoNewline
        Write-Host (' ' + $t.Nome)
        $i++
    }
}

function Show-TaskDetail {
    param($Tasks)
    foreach ($t in $Tasks) {
        Write-Host ('   ' + $t.Nome) -NoNewline -ForegroundColor White
        Write-Host ('   (' + (Format-Stima $t.Stima) + ')') -ForegroundColor DarkGray
        $d = $t.Descrizione
        foreach ($riga in (Split-TextWidth -Testo $d -Larghezza 68)) { Write-Dim ('  ' + $riga) }
    }
}

function Split-TextWidth {
    param([string]$Testo, [int]$Larghezza = 68)
    $righe = @()
    $corrente = ''
    foreach ($parola in ($Testo -split '\s+')) {
        if (($corrente.Length + $parola.Length + 1) -gt $Larghezza) {
            $righe += $corrente
            $corrente = $parola
        } else {
            if ($corrente) { $corrente += ' ' + $parola } else { $corrente = $parola }
        }
    }
    if ($corrente) { $righe += $corrente }
    return $righe
}

function Show-TaskSummary {
    param($Risultati, [long]$SpazioReale = -1)

    Write-Title 'Riepilogo'
    Write-Host ''
    Write-Host ('   {0,-38} {1,-9} {2,11} {3,8}' -f 'Operazione', 'Esito', 'Liberato', 'Durata') -ForegroundColor White
    Write-Host ('   ' + ('-' * 69)) -ForegroundColor DarkGray

    $tot = [long]0
    foreach ($r in $Risultati) {
        $col = 'Green'
        if ($r.Esito -eq 'PARZIALE') { $col = 'Yellow' }
        if ($r.Esito -eq 'FALLITO')  { $col = 'Red' }
        $nome = $r.Nome
        if ($nome.Length -gt 37) { $nome = $nome.Substring(0, 34) + '...' }
        Write-Host ('   {0,-38} ' -f $nome) -NoNewline
        Write-Host ('{0,-9}' -f $r.Esito) -ForegroundColor $col -NoNewline
        Write-Host (' {0,11} {1,7:N1}s' -f (Format-Bytes $r.Bytes), $r.Durata.TotalSeconds)
        $tot += $r.Bytes
    }
    Write-Host ('   ' + ('-' * 69)) -ForegroundColor DarkGray
    Write-Host ('   {0,-38} {1,-9} {2,11}' -f 'TOTALE', '', (Format-Bytes $tot)) -ForegroundColor Cyan

    if ($SpazioReale -ge 0) {
        Write-Host ''
        Write-Kv 'Spazio su disco' ('{0} liberi in piu'' su {1} (misura di controllo)' -f (Format-Bytes $SpazioReale), $env:SystemDrive) 'Cyan'
    }

    # Dettaglio dei problemi: qui sta la differenza rispetto a un
    # semplice [OK] stampato a prescindere.
    $problemi = @($Risultati | Where-Object { $_.Esito -ne 'OK' })
    if ($problemi.Count -gt 0) {
        Write-Host ''
        Write-Host '   Dettaglio dei problemi:' -ForegroundColor Yellow
        foreach ($p in $problemi) {
            Write-Host ('    ' + $p.Nome) -ForegroundColor Yellow
            if ($p.HardFail) { Write-Err ('   ! ' + $p.HardFail) }
            foreach ($e in $p.Errors) { Write-Warn ('   - ' + $e) }
        }
    } else {
        Write-Host ''
        Write-Ok 'Tutte le operazioni completate senza errori.'
    }

    $saltati = ($Risultati | Measure-Object -Property Skipped -Sum).Sum
    if ($saltati -gt 0) {
        Write-Dim ('{0} elementi erano in uso e sono stati saltati: e'' normale, verranno rimossi alla prossima esecuzione.' -f $saltati)
    }

    if (@($Risultati | Where-Object { $_.Reboot }).Count -gt 0) {
        Write-Host ''
        Write-Warn 'Alcune modifiche diventano effettive solo dopo il riavvio del PC.'
    }
}
