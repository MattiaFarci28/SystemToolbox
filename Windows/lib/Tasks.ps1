# ============================================================
#   Tasks.ps1 - Registro delle operazioni
#
#   Ogni operazione e' un oggetto dichiarativo. Il motore
#   (Invoke-Task in Core.ps1) si occupa di cronometro, log,
#   conteggi ed esito reale: qui c'e' solo il "cosa fare".
#
#   Livello:
#     Sicuro   -> nessun effetto collaterale rilevante
#     Avanzato -> impatto reale, richiede conferma esplicita
#     Riavvio  -> ha effetto solo dopo il riavvio del PC
#
#   Sconsigliato = $true segnala un'operazione che si puo'
#   eseguire ma che tipicamente NON conviene (vedi Prefetch).
# ============================================================

Set-StrictMode -Version 1.0

# ------------------------------------------------------------
#   Helper locali
# ------------------------------------------------------------

# Profili utente reali, presi dal registro invece che elencando
# C:\Users: esclude i profili di sistema e funziona anche se la
# cartella utenti non e' sul disco C.
function Get-UserProfilePath {
    $out = @()
    try {
        # Il flag Special non basta: i profili dei servizi installati da
        # terze parti (es. C:\Windows\ServiceProfiles\OpenVPNService)
        # risultano Special=False pur non essendo profili di persone.
        # Si escludono quindi tutti i percorsi dentro %WINDIR%.
        $out = @(Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop |
                 Where-Object { -not $_.Special -and $_.LocalPath -and
                                ($_.LocalPath -notlike ($env:WINDIR + '\*')) } |
                 Select-Object -ExpandProperty LocalPath)
    } catch {
        $root = Join-Path $env:SystemDrive 'Users'
        if (Test-Path -LiteralPath $root -ErrorAction SilentlyContinue) {
            $out = @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
                     Where-Object { $_.Name -notin @('Default','Default User','Public','All Users') } |
                     Select-Object -ExpandProperty FullName)
        }
    }
    return $out
}

function Get-RunningBrowser {
    $nomi = @('msedge','chrome','firefox','brave','opera','vivaldi')
    return @(Get-Process -Name $nomi -ErrorAction SilentlyContinue |
             Select-Object -ExpandProperty ProcessName -Unique)
}

# ============================================================
#   REGISTRO
# ============================================================

$script:TaskRegistry = @(

# ------------------------------------------------------------
#   PULIZIA - livello sicuro
# ------------------------------------------------------------
@{
    Id        = 'clean_temp_user'
    Nome      = 'Temp utente corrente'
    Categoria = 'Pulizia'
    Livello   = 'Sicuro'
    Descrizione = 'Svuota la cartella temporanea dell''utente attualmente connesso.'
    Azione = {
        param($ctx)
        Clear-FolderContent -Path $env:TEMP -Ctx $ctx -Etichetta 'Temp utente'
    }
},
@{
    Id        = 'clean_temp_system'
    Nome      = 'Temp di sistema'
    Categoria = 'Pulizia'
    Livello   = 'Sicuro'
    Descrizione = 'Svuota C:\Windows\Temp.'
    Azione = {
        param($ctx)
        Clear-FolderContent -Path (Join-Path $env:WINDIR 'Temp') -Ctx $ctx -Etichetta 'Windows\Temp'
    }
},
@{
    Id        = 'clean_temp_allusers'
    Nome      = 'Temp e cache di tutti i profili'
    Categoria = 'Pulizia'
    Livello   = 'Sicuro'
    Descrizione = 'Temp e INetCache di ogni profilo utente reale (profili di sistema esclusi).'
    Azione = {
        param($ctx)
        $profili = Get-UserProfilePath
        if ($profili.Count -eq 0) { $ctx.Fail('Nessun profilo utente individuato'); return }
        foreach ($p in $profili) {
            $nome = Split-Path $p -Leaf
            Clear-FolderContent -Path (Join-Path $p 'AppData\Local\Temp') -Ctx $ctx -Etichetta ('Temp di ' + $nome)
            Clear-FolderContent -Path (Join-Path $p 'AppData\Local\Microsoft\Windows\INetCache') -Ctx $ctx -Etichetta ('INetCache di ' + $nome)
        }
    }
},
@{
    Id        = 'clean_trash'
    Nome      = 'Cestino (tutti i dischi)'
    Categoria = 'Pulizia'
    Livello   = 'Sicuro'
    Descrizione = 'Svuota il cestino con l''API di Windows, senza cancellare la cartella di sistema.'
    Azione = {
        param($ctx)
        $dischi = @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction SilentlyContinue)
        foreach ($d in $dischi) {
            $lettera = $d.DeviceID.TrimEnd(':')
            $cartella = Join-Path ($d.DeviceID + '\') '$Recycle.Bin'
            $prima = Measure-FolderBytes $cartella

            if ($ctx.DryRun) {
                $ctx.Note(('Cestino {0}: {1} eliminabili (simulazione)' -f $d.DeviceID, (Format-Bytes $prima)))
                $ctx.Bytes += $prima
                continue
            }
            if ($prima -le 0) {
                $ctx.Note(('Cestino {0}: gia'' vuoto' -f $d.DeviceID))
                continue
            }
            try {
                Clear-RecycleBin -DriveLetter $lettera -Force -Confirm:$false -ErrorAction Stop
            } catch {
                # Windows solleva un errore anche quando il cestino
                # e' semplicemente vuoto: non e' un fallimento.
                if ($_.Exception.Message -notmatch 'vuot|empty|0x80070091') {
                    $ctx.Fail(('Cestino {0}: {1}' -f $d.DeviceID, $_.Exception.Message))
                    continue
                }
            }
            $dopo = Measure-FolderBytes $cartella
            $lib  = $prima - $dopo
            if ($lib -lt 0) { $lib = 0 }
            $ctx.Bytes += $lib
            $ctx.Note(('Cestino {0}: {1} liberati' -f $d.DeviceID, (Format-Bytes $lib)))
        }
    }
},
@{
    Id        = 'clean_wer'
    Nome      = 'Segnalazioni errori Windows (WER)'
    Categoria = 'Pulizia'
    Livello   = 'Sicuro'
    Descrizione = 'Rimuove le code di segnalazione errori. Non tocca i log diagnostici di CBS/DISM.'
    Azione = {
        param($ctx)
        $percorsi = @(
            @{ P = (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportArchive');  E = 'WER sistema - archivio' },
            @{ P = (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportQueue');    E = 'WER sistema - coda' },
            @{ P = (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\WER\ReportArchive'); E = 'WER utente - archivio' },
            @{ P = (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\WER\ReportQueue');   E = 'WER utente - coda' }
        )
        foreach ($x in $percorsi) {
            Clear-FolderContent -Path $x.P -Ctx $ctx -Etichetta $x.E
        }
    }
},
@{
    Id        = 'clean_crashdump'
    Nome      = 'Dump di crash e minidump'
    Categoria = 'Pulizia'
    Livello   = 'Sicuro'
    Descrizione = 'Rimuove i file di dump dei crash di sistema (spesso centinaia di MB).'
    Azione = {
        param($ctx)
        Clear-FolderContent -Path (Join-Path $env:WINDIR 'Minidump') -Ctx $ctx -Etichetta 'Minidump'
        $memdmp = Join-Path $env:WINDIR 'MEMORY.DMP'
        if (Test-Path -LiteralPath $memdmp) {
            $dim = (Get-Item -LiteralPath $memdmp -Force).Length
            if ($ctx.DryRun) {
                $ctx.Note(('MEMORY.DMP: {0} eliminabili (simulazione)' -f (Format-Bytes $dim)))
                $ctx.Bytes += $dim
            } else {
                try {
                    Remove-Item -LiteralPath $memdmp -Force -ErrorAction Stop
                    $ctx.Bytes += $dim; $ctx.Items++
                    $ctx.Note(('MEMORY.DMP rimosso: {0}' -f (Format-Bytes $dim)))
                } catch { $ctx.Fail('MEMORY.DMP in uso, non rimosso') }
            }
        } else {
            $ctx.Note('MEMORY.DMP: non presente')
        }
    }
},
@{
    Id        = 'clean_deliveryopt'
    Nome      = 'Cache Delivery Optimization'
    Categoria = 'Pulizia'
    Livello   = 'Sicuro'
    Descrizione = 'Cache di distribuzione degli aggiornamenti peer-to-peer. Si ricrea da sola.'
    Azione = {
        param($ctx)
        # La cache sta in due posti diversi a seconda della build di
        # Windows: vanno misurati entrambi, altrimenti il cmdlet svuota
        # davvero qualcosa ma il conteggio resta a zero.
        $cartelle = @(
            (Join-Path $env:WINDIR 'SoftwareDistribution\DeliveryOptimization'),
            (Join-Path $env:WINDIR 'ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache')
        )
        $prima = 0
        foreach ($c in $cartelle) { $prima += (Measure-FolderBytes $c) }

        if ($ctx.DryRun) {
            $ctx.Note(('Delivery Optimization: {0} eliminabili (simulazione)' -f (Format-Bytes $prima)))
            $ctx.Bytes += $prima
            return
        }
        if (Get-Command Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue) {
            try {
                # *>$null perche' il cmdlet scrive "Deleting..." direttamente
                # a schermo; -ErrorAction Stop fa comunque scattare il catch.
                Delete-DeliveryOptimizationCache -Force -ErrorAction Stop *>$null
                $dopo = 0
                foreach ($c in $cartelle) { $dopo += (Measure-FolderBytes $c) }
                $lib = $prima - $dopo; if ($lib -lt 0) { $lib = 0 }
                $ctx.Bytes += $lib
                $ctx.Note(('Delivery Optimization: {0} liberati' -f (Format-Bytes $lib)))
                return
            } catch {
                $ctx.Note('Cmdlet Delivery Optimization non utilizzabile, uso il metodo manuale')
            }
        }
        foreach ($c in $cartelle) {
            Clear-FolderContent -Path $c -Ctx $ctx -Etichetta 'Delivery Optimization'
        }
    }
},
@{
    Id        = 'clean_fontcache'
    Nome      = 'Cache dei font'
    Categoria = 'Pulizia'
    Livello   = 'Avanzato'
    Descrizione = 'Ricostruisce la cache dei caratteri. Utile se il testo appare corrotto.'
    Azione = {
        param($ctx)
        if ($ctx.DryRun) { $ctx.Note('Cache font: verrebbe rigenerata (simulazione)'); return }
        $stato = Stop-ServiceSet -Names @('FontCache','FontCache3.0.0.0') -Ctx $ctx -TimeoutSec 15
        Clear-FolderContent -Path (Join-Path $env:WINDIR 'ServiceProfiles\LocalService\AppData\Local\FontCache') -Ctx $ctx -Etichetta 'FontCache'
        Remove-FilePattern -Path (Join-Path $env:WINDIR 'ServiceProfiles\LocalService\AppData\Local') -Filtro 'FontCache*.dat' -Ctx $ctx -Etichetta 'FontCache*.dat'
        Restore-ServiceSet -State $stato -Ctx $ctx
    }
},

# ------------------------------------------------------------
#   PULIZIA - livello avanzato
# ------------------------------------------------------------
@{
    Id        = 'clean_browsercache'
    Nome      = 'Cache dei browser'
    Categoria = 'Pulizia'
    Livello   = 'Avanzato'
    Descrizione = 'Solo cache di Edge/Chrome/Firefox. NON tocca cronologia, cookie, password o segnalibri. I browser devono essere chiusi.'
    Azione = {
        param($ctx)
        $aperti = Get-RunningBrowser
        if ($aperti.Count -gt 0) {
            $ctx.Note(('Browser aperti ({0}): molti file saranno bloccati' -f ($aperti -join ', ')))
        }
        foreach ($prof in (Get-UserProfilePath)) {
            $utente = Split-Path $prof -Leaf
            $basi = @(
                (Join-Path $prof 'AppData\Local\Microsoft\Edge\User Data'),
                (Join-Path $prof 'AppData\Local\Google\Chrome\User Data'),
                (Join-Path $prof 'AppData\Local\BraveSoftware\Brave-Browser\User Data')
            )
            foreach ($base in $basi) {
                if (-not (Test-Path -LiteralPath $base)) { continue }
                $etichettaBase = Split-Path (Split-Path $base -Parent) -Leaf
                $profiliBrowser = @(Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue |
                                    Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' })
                foreach ($pb in $profiliBrowser) {
                    foreach ($sub in @('Cache\Cache_Data','Code Cache\js','Code Cache\wasm','GPUCache')) {
                        $target = Join-Path $pb.FullName $sub
                        if (Test-Path -LiteralPath $target) {
                            Clear-FolderContent -Path $target -Ctx $ctx -Etichetta ('{0} {1}/{2} [{3}]' -f $etichettaBase, $pb.Name, (Split-Path $sub -Leaf), $utente)
                        }
                    }
                }
            }
            $ff = Join-Path $prof 'AppData\Local\Mozilla\Firefox\Profiles'
            if (Test-Path -LiteralPath $ff) {
                foreach ($pb in (Get-ChildItem -LiteralPath $ff -Directory -ErrorAction SilentlyContinue)) {
                    $target = Join-Path $pb.FullName 'cache2'
                    if (Test-Path -LiteralPath $target) {
                        Clear-FolderContent -Path $target -Ctx $ctx -Etichetta ('Firefox {0} [{1}]' -f $pb.Name, $utente)
                    }
                }
            }
        }
    }
},
@{
    Id        = 'clean_thumbcache'
    Nome      = 'Cache miniature e icone'
    Categoria = 'Pulizia'
    Livello   = 'Avanzato'
    Descrizione = 'Riavvia Esplora risorse (le finestre aperte verranno chiuse) e rigenera la cache di miniature e icone.'
    Azione = {
        param($ctx)
        $cartella = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer'
        if ($ctx.DryRun) {
            $dim = 0
            Get-ChildItem -LiteralPath $cartella -Filter '*cache*.db' -File -Force -ErrorAction SilentlyContinue |
                ForEach-Object { $dim += $_.Length }
            $ctx.Note(('Cache miniature: {0} eliminabili (simulazione)' -f (Format-Bytes $dim)))
            $ctx.Bytes += $dim
            return
        }
        $explorerAttivo = [bool](Get-Process -Name explorer -ErrorAction SilentlyContinue)
        if ($explorerAttivo) {
            $ctx.Note('Arresto di Esplora risorse...')
            Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
        Remove-FilePattern -Path $cartella -Filtro 'thumbcache_*.db' -Ctx $ctx -Etichetta 'Miniature'
        Remove-FilePattern -Path $cartella -Filtro 'iconcache_*.db'  -Ctx $ctx -Etichetta 'Icone'
        if ($explorerAttivo -and -not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) {
            Start-Process explorer.exe
            $ctx.Note('Esplora risorse riavviato')
        }
    }
},
@{
    Id        = 'clean_wucache'
    Nome      = 'Cache di Windows Update'
    Categoria = 'Pulizia'
    Livello   = 'Avanzato'
    Descrizione = 'Ferma i servizi di aggiornamento, svuota SoftwareDistribution\Download e ripristina lo stato iniziale dei servizi.'
    Azione = {
        param($ctx)
        $servizi = @('wuauserv','bits','cryptSvc','appidsvc')
        if ($ctx.DryRun) {
            $p = Measure-FolderBytes (Join-Path $env:WINDIR 'SoftwareDistribution\Download')
            $ctx.Note(('Cache Windows Update: {0} eliminabili (simulazione)' -f (Format-Bytes $p)))
            $ctx.Bytes += $p
            return
        }
        $ctx.Note('Arresto dei servizi di aggiornamento...')
        $stato = Stop-ServiceSet -Names $servizi -Ctx $ctx -TimeoutSec 20
        Clear-FolderContent -Path (Join-Path $env:WINDIR 'SoftwareDistribution\Download') -Ctx $ctx -Etichetta 'SoftwareDistribution\Download'
        $ctx.Note('Ripristino dello stato dei servizi...')
        Restore-ServiceSet -State $stato -Ctx $ctx
    }
},
@{
    Id        = 'clean_componentstore'
    Nome      = 'Compattazione archivio componenti (DISM)'
    Categoria = 'Pulizia'
    Livello   = 'Avanzato'
    Descrizione = 'Rimuove le versioni superate dei componenti di Windows. E'' l''operazione che libera piu'' spazio, ma puo'' durare 10-20 minuti e non e'' interrompibile.'
    Azione = {
        param($ctx)
        if ($ctx.DryRun) {
            $ctx.Note('Analisi archivio componenti (sola lettura)...')
            $r = Invoke-LongNative -File 'dism.exe' -Arguments @('/Online','/Cleanup-Image','/AnalyzeComponentStore') -TimeoutSec 900 -Ctx $ctx
            foreach ($riga in ($r.Output -split "`r?`n")) {
                if ($riga -match 'Reclaimable|recuperabil|Component Store Cleanup|Pulizia') { $ctx.Note($riga.Trim()) }
            }
            return
        }
        $prima = Get-FreeSpace
        $ctx.Note('Avvio pulizia archivio componenti: puo'' richiedere parecchi minuti...')
        $r = Invoke-LongNative -File 'dism.exe' -Arguments @('/Online','/Cleanup-Image','/StartComponentCleanup') -TimeoutSec 2400 -Ctx $ctx
        if ($r.TimedOut) { $ctx.Fail('DISM interrotto per timeout'); return }
        if ($r.ExitCode -ne 0) { $ctx.Fail(('DISM ha restituito il codice {0}' -f $r.ExitCode)); return }
        $dopo = Get-FreeSpace
        $lib = $dopo - $prima
        if ($lib -gt 0) { $ctx.Bytes += $lib }
        $ctx.Note(('Archivio componenti compattato: {0} liberati' -f (Format-Bytes ([math]::Max(0,$lib)))))
    }
},
@{
    Id        = 'clean_appcache'
    Nome      = 'Cache delle applicazioni'
    Categoria = 'Pulizia'
    Livello   = 'Avanzato'
    Descrizione = 'Cache di Teams, Discord, Spotify e cache web delle app dello Store. Non tocca account, cronologia o impostazioni. Le applicazioni interessate vanno chiuse.'
    Azione = {
        param($ctx)
        $attive = @(Get-Process -Name 'Teams','ms-teams','Discord','Spotify' -ErrorAction SilentlyContinue |
                    Select-Object -ExpandProperty ProcessName -Unique)
        if ($attive.Count -gt 0) {
            $ctx.Note(('Applicazioni aperte ({0}): molti file saranno bloccati' -f ($attive -join ', ')))
        }

        foreach ($prof in (Get-UserProfilePath)) {
            $utente = Split-Path $prof -Leaf
            $percorsi = @(
                @{ P = (Join-Path $prof 'AppData\Roaming\Microsoft\Teams\Cache');        E = 'Teams (classico)' },
                @{ P = (Join-Path $prof 'AppData\Roaming\Microsoft\Teams\GPUCache');     E = 'Teams GPU' },
                @{ P = (Join-Path $prof 'AppData\Roaming\discord\Cache');                E = 'Discord' },
                @{ P = (Join-Path $prof 'AppData\Roaming\discord\Code Cache');           E = 'Discord code' },
                @{ P = (Join-Path $prof 'AppData\Roaming\discord\GPUCache');             E = 'Discord GPU' },
                @{ P = (Join-Path $prof 'AppData\Local\Spotify\Storage');                E = 'Spotify' },
                @{ P = (Join-Path $prof 'AppData\Local\Spotify\Data');                   E = 'Spotify dati' }
            )
            foreach ($x in $percorsi) {
                if (Test-Path -LiteralPath $x.P -ErrorAction SilentlyContinue) {
                    Clear-FolderContent -Path $x.P -Ctx $ctx -Etichetta ('{0} [{1}]' -f $x.E, $utente)
                }
            }

            # App dello Store: si tocca solo AC\INetCache, che e' la
            # cache web del contenitore. Il resto di LocalCache puo'
            # contenere dati veri dell'applicazione.
            $pacchetti = Join-Path $prof 'AppData\Local\Packages'
            if (Test-Path -LiteralPath $pacchetti -ErrorAction SilentlyContinue) {
                $n = 0
                foreach ($pk in (Get-ChildItem -LiteralPath $pacchetti -Directory -ErrorAction SilentlyContinue)) {
                    $cache = Join-Path $pk.FullName 'AC\INetCache'
                    if (Test-Path -LiteralPath $cache -ErrorAction SilentlyContinue) {
                        $prima = Measure-FolderBytes $cache
                        if ($prima -le 0) { continue }
                        if ($ctx.DryRun) { $ctx.Bytes += $prima; $n++; continue }
                        Get-ChildItem -LiteralPath $cache -Force -ErrorAction SilentlyContinue | ForEach-Object {
                            if (Remove-AlberoSicuro -Voce $_) { $ctx.Items++ } else { $ctx.Skipped++ }
                        }
                        $ctx.Bytes += ($prima - (Measure-FolderBytes $cache))
                        $n++
                    }
                }
                if ($n -gt 0) { $ctx.Note(('Cache web di {0} app dello Store [{1}]' -f $n, $utente)) }
            }
        }
    }
},
@{
    Id        = 'clean_devcache'
    Nome      = 'Cache degli strumenti di sviluppo'
    Categoria = 'Pulizia'
    Livello   = 'Avanzato'
    Descrizione = 'Cache di npm, pip, Yarn, NuGet e Gradle. Sono pacchetti riscaricabili: il primo build successivo sara'' piu'' lento. Non tocca i progetti ne'' il repository Maven locale.'
    Azione = {
        param($ctx)
        $trovate = 0
        foreach ($prof in (Get-UserProfilePath)) {
            $utente = Split-Path $prof -Leaf
            $percorsi = @(
                @{ P = (Join-Path $prof 'AppData\Local\npm-cache\_cacache');   E = 'npm' },
                @{ P = (Join-Path $prof 'AppData\Local\pip\Cache');            E = 'pip' },
                @{ P = (Join-Path $prof 'AppData\Local\Yarn\Cache');           E = 'Yarn' },
                @{ P = (Join-Path $prof 'AppData\Local\NuGet\v3-cache');       E = 'NuGet http' },
                @{ P = (Join-Path $prof 'AppData\Local\NuGet\plugins-cache');  E = 'NuGet plugin' },
                @{ P = (Join-Path $prof 'AppData\Local\Temp\NuGetScratch');    E = 'NuGet temporanei' },
                @{ P = (Join-Path $prof '.gradle\caches\build-cache-1');       E = 'Gradle build cache' },
                @{ P = (Join-Path $prof '.gradle\caches\transforms-3');        E = 'Gradle transforms' }
            )
            foreach ($x in $percorsi) {
                if (Test-Path -LiteralPath $x.P -ErrorAction SilentlyContinue) {
                    $trovate++
                    Clear-FolderContent -Path $x.P -Ctx $ctx -Etichetta ('{0} [{1}]' -f $x.E, $utente)
                }
            }
        }
        if ($trovate -eq 0) {
            $ctx.Note('Nessuno strumento di sviluppo con cache su questo sistema')
        } elseif ($ctx.Bytes -eq 0) {
            $ctx.Note(('{0} cache presenti ma gia'' vuote' -f $trovate))
        }
    }
},
@{
    Id        = 'clean_windowsold'
    Nome      = 'Installazione precedente (Windows.old)'
    Categoria = 'Pulizia'
    Livello   = 'Avanzato'
    RichiedeReboot = $false
    Descrizione = 'Rimuove la copia della versione precedente di Windows lasciata da un aggiornamento di funzionalita''. Libera spesso decine di GB, ma dopo non sara'' piu'' possibile tornare indietro alla versione precedente.'
    Azione = {
        param($ctx)
        $cartella = Join-Path $env:SystemDrive 'Windows.old'
        if (-not (Test-Path -LiteralPath $cartella -ErrorAction SilentlyContinue)) {
            $ctx.Note('Windows.old non presente: niente da fare')
            return
        }
        $prima = Measure-FolderBytes $cartella
        if ($ctx.DryRun) {
            $ctx.Note(('Windows.old: {0} eliminabili (simulazione)' -f (Format-Bytes $prima)))
            $ctx.Bytes += $prima
            return
        }

        # Si usa Pulizia disco di Windows, non takeown + icacls.
        # Windows.old contiene junction dell'installazione precedente
        # che puntano a percorsi assoluti come C:\Users\...: dopo
        # l'aggiornamento sono i profili ATTUALI. takeown /R e
        # icacls /T le seguono (verificato, anche con /L), e avrebbero
        # cambiato proprietario e permessi ai file degli utenti.
        # Pulizia disco conosce la struttura di Windows.old e la
        # rimuove senza attraversare quei collegamenti.
        #
        # Si attiva la sola voce "Installazioni precedenti" con un
        # profilo numerato riservato allo strumento, lo si esegue e
        # lo si toglie: le impostazioni di Pulizia disco dell'utente
        # non vengono toccate.
        $chiave = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Previous Installations'
        $profilo = 4242
        $valore = 'StateFlags{0:D4}' -f $profilo
        if (-not (Test-Path -LiteralPath $chiave) -or -not (Get-Command cleanmgr.exe -ErrorAction SilentlyContinue)) {
            $ctx.Fail('Pulizia disco non disponibile su questo sistema: rimuovi Windows.old da Impostazioni > Sistema > Archiviazione > File temporanei.')
            return
        }
        $ctx.Note('Rimozione tramite Pulizia disco di Windows, puo'' richiedere parecchi minuti...')
        try {
            New-ItemProperty -LiteralPath $chiave -Name $valore -Value 2 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
            $r = Invoke-LongNative -File 'cleanmgr.exe' -Arguments @(('/sagerun:{0}' -f $profilo)) -TimeoutSec 1800 -Ctx $ctx
            if (-not $r.Avviato) { $ctx.Fail('Pulizia disco non avviabile') }
        } catch {
            $ctx.Fail('Pulizia disco non configurabile: ' + $_.Exception.Message)
        } finally {
            Remove-ItemProperty -LiteralPath $chiave -Name $valore -ErrorAction SilentlyContinue
        }

        $dopo = Measure-FolderBytes $cartella
        $lib = $prima - $dopo
        if ($lib -lt 0) { $lib = 0 }
        $ctx.Bytes += $lib
        if (Test-Path -LiteralPath $cartella -ErrorAction SilentlyContinue) {
            $ctx.Fail(('Windows.old non rimossa del tutto: restano {0}. Prova con Pulizia disco come amministratore.' -f (Format-Bytes $dopo)))
        } else {
            $ctx.Items++
            $ctx.Note(('Windows.old rimossa: {0} liberati' -f (Format-Bytes $lib)))
        }
    }
},
@{
    Id        = 'clean_prefetch'
    Nome      = 'Prefetch'
    Categoria = 'Pulizia'
    Livello   = 'Avanzato'
    Sconsigliato = $true
    Descrizione = 'SCONSIGLIATO: cancellare il Prefetch RALLENTA i primi avvii di sistema e applicazioni finche'' Windows non ricostruisce i profili. Recupera pochi MB. Incluso solo per completezza.'
    Azione = {
        param($ctx)
        $ctx.Note('Attenzione: questa operazione peggiora temporaneamente i tempi di avvio.')
        Clear-FolderContent -Path (Join-Path $env:WINDIR 'Prefetch') -Ctx $ctx -Etichetta 'Prefetch'
    }
},

# ------------------------------------------------------------
#   RETE - refresh leggero (nessun riavvio)
# ------------------------------------------------------------
@{
    Id        = 'net_flushdns'
    Nome      = 'Svuota cache DNS'
    Categoria = 'Rete'
    Livello   = 'Sicuro'
    Descrizione = 'Elimina le risoluzioni DNS memorizzate. Reversibile e istantaneo.'
    Azione = {
        param($ctx)
        if ($ctx.DryRun) { $ctx.Note('ipconfig /flushdns (simulazione)'); return }
        if (Get-Command Clear-DnsClientCache -ErrorAction SilentlyContinue) {
            Clear-DnsClientCache -ErrorAction Stop
            $ctx.Note('Cache DNS svuotata')
        } else {
            $r = Invoke-Native -File 'ipconfig.exe' -Arguments @('/flushdns') -TimeoutSec 30
            if ($r.ExitCode -ne 0) { $ctx.Fail(('ipconfig /flushdns codice {0}' -f $r.ExitCode)) }
            else { $ctx.Note('Cache DNS svuotata') }
        }
    }
},
@{
    Id        = 'net_arpcache'
    Nome      = 'Svuota cache ARP'
    Categoria = 'Rete'
    Livello   = 'Sicuro'
    Descrizione = 'Usa netsh invece di "arp -d *", che restituisce codici di errore anche quando funziona.'
    Azione = {
        param($ctx)
        if ($ctx.DryRun) { $ctx.Note('netsh interface ip delete arpcache (simulazione)'); return }
        $r = Invoke-Native -File 'netsh.exe' -Arguments @('interface','ip','delete','arpcache') -TimeoutSec 30
        if ($r.ExitCode -ne 0) {
            $ctx.Note(('netsh ha restituito il codice {0}: normale se la cache era gia'' vuota' -f $r.ExitCode))
        } else {
            $ctx.Note('Cache ARP svuotata')
        }
    }
},
@{
    Id        = 'net_renew'
    Nome      = 'Rinnova indirizzo IP (release + renew)'
    Categoria = 'Rete'
    Livello   = 'Sicuro'
    Descrizione = 'Rilascia e richiede di nuovo l''indirizzo al router. Con timeout reale: non puo'' bloccare la finestra.'
    Azione = {
        param($ctx)
        if ($ctx.DryRun) { $ctx.Note('ipconfig /release + /renew (simulazione)'); return }

        $statiche = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                      Where-Object { $_.PrefixOrigin -eq 'Manual' -and $_.IPAddress -notlike '127.*' })
        if ($statiche.Count -gt 0) {
            $ctx.Note('Rilevata configurazione IP statica: release/renew non ha effetto su queste schede.')
        }

        $ctx.Note('Rilascio indirizzo...')
        $r1 = Invoke-Native -File 'ipconfig.exe' -Arguments @('/release') -TimeoutSec 45
        if ($r1.TimedOut) { $ctx.Fail('ipconfig /release bloccato, interrotto dopo 45 s') }

        $ctx.Note('Richiesta nuovo indirizzo (max 60 s)...')
        $r2 = Invoke-Native -File 'ipconfig.exe' -Arguments @('/renew') -TimeoutSec 60
        if ($r2.TimedOut) {
            $ctx.Fail('ipconfig /renew bloccato, interrotto dopo 60 s')
        } elseif ($r2.ExitCode -ne 0) {
            $ctx.Note('Rinnovo non riuscito: normale senza un server DHCP raggiungibile o con IP statico.')
        }

        # Attende che una scheda torni ad avere un indirizzo valido.
        $deadline = (Get-Date).AddSeconds(20)
        $ok = $false
        while ((Get-Date) -lt $deadline) {
            $ip = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                    Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' })
            if ($ip.Count -gt 0) { $ok = $true; break }
            Start-Sleep -Milliseconds 700
        }
        if ($ok) {
            $ctx.Note(('Indirizzo attivo: {0}' -f (($ip | Select-Object -First 3 | ForEach-Object { $_.IPAddress }) -join ', ')))
        } else {
            $ctx.Fail('Nessun indirizzo IPv4 valido assegnato dopo 20 s')
        }
    }
},
@{
    Id        = 'net_registerdns'
    Nome      = 'Registrazione DNS'
    Categoria = 'Rete'
    Livello   = 'Sicuro'
    Descrizione = 'Registra di nuovo il nome del computer presso il server DNS.'
    Azione = {
        param($ctx)
        if ($ctx.DryRun) { $ctx.Note('ipconfig /registerdns (simulazione)'); return }
        $r = Invoke-Native -File 'ipconfig.exe' -Arguments @('/registerdns') -TimeoutSec 45
        if ($r.TimedOut)          { $ctx.Fail('ipconfig /registerdns bloccato, interrotto') }
        elseif ($r.ExitCode -ne 0) { $ctx.Note(('Codice {0}: normale fuori da un dominio' -f $r.ExitCode)) }
        else                      { $ctx.Note('Registrazione DNS completata') }
    }
},

# ------------------------------------------------------------
#   RETE - reset completo (richiede riavvio)
# ------------------------------------------------------------
@{
    Id        = 'net_winsock'
    Nome      = 'Reset catalogo Winsock'
    Categoria = 'Rete'
    Livello   = 'Riavvio'
    RichiedeReboot = $true
    Descrizione = 'Rimuove i layer LSP di terze parti (VPN, antivirus, proxy). Ha effetto solo dopo il riavvio.'
    Azione = {
        param($ctx)
        if ($ctx.DryRun) { $ctx.Note('netsh winsock reset (simulazione)'); return }
        $r = Invoke-Native -File 'netsh.exe' -Arguments @('winsock','reset') -TimeoutSec 60
        if ($r.TimedOut) { $ctx.Fail('netsh winsock reset bloccato'); return }
        if ($r.ExitCode -ne 0) { $ctx.Fail(('netsh winsock reset codice {0}' -f $r.ExitCode)); return }
        $ctx.RebootNeeded = $true
        $ctx.Note('Catalogo Winsock ripristinato: effettivo dopo il riavvio')
    }
},
@{
    Id        = 'net_ipreset'
    Nome      = 'Reset stack TCP/IP'
    Categoria = 'Rete'
    Livello   = 'Riavvio'
    RichiedeReboot = $true
    Descrizione = 'Riscrive la configurazione TCP/IP. Azzera IP statici e MTU personalizzati. Ha effetto solo dopo il riavvio.'
    Azione = {
        param($ctx)
        if ($ctx.DryRun) { $ctx.Note('netsh int ip reset (simulazione)'); return }
        $r = Invoke-Native -File 'netsh.exe' -Arguments @('int','ip','reset') -TimeoutSec 90
        if ($r.TimedOut) { $ctx.Fail('netsh int ip reset bloccato'); return }
        # netsh int ip reset restituisce spesso un codice diverso da 0
        # con "Accesso negato" su singole chiavi di registro pur avendo
        # completato il reset. Non e' un errore da segnalare.
        if ($r.ExitCode -ne 0) {
            $ctx.Note(('netsh ha restituito il codice {0}: tipico quando alcune chiavi di registro sono protette, il reset e'' comunque avvenuto' -f $r.ExitCode))
        }
        $ctx.RebootNeeded = $true
        $ctx.Note('Stack TCP/IP ripristinato: effettivo dopo il riavvio')
    }
},
@{
    Id        = 'net_ipv6reset'
    Nome      = 'Reset stack IPv6'
    Categoria = 'Rete'
    Livello   = 'Riavvio'
    RichiedeReboot = $true
    Descrizione = 'Riscrive la configurazione IPv6. Ha effetto solo dopo il riavvio.'
    Azione = {
        param($ctx)
        if ($ctx.DryRun) { $ctx.Note('netsh int ipv6 reset (simulazione)'); return }
        $r = Invoke-Native -File 'netsh.exe' -Arguments @('int','ipv6','reset') -TimeoutSec 90
        if ($r.TimedOut) { $ctx.Fail('netsh int ipv6 reset bloccato'); return }
        if ($r.ExitCode -ne 0) {
            $ctx.Note(('netsh ha restituito il codice {0}: tipicamente non critico' -f $r.ExitCode))
        }
        $ctx.RebootNeeded = $true
        $ctx.Note('Stack IPv6 ripristinato: effettivo dopo il riavvio')
    }
},

# ------------------------------------------------------------
#   MANUTENZIONE
# ------------------------------------------------------------
@{
    Id        = 'maint_restorepoint'
    Nome      = 'Crea punto di ripristino'
    Categoria = 'Manutenzione'
    Livello   = 'Sicuro'
    Descrizione = 'Rete di sicurezza da creare prima delle operazioni avanzate.'
    Azione = {
        param($ctx)
        if ($ctx.DryRun) { $ctx.Note('Creazione punto di ripristino (simulazione)'); return }
        $r = New-RestorePoint
        if ($r.Ok) { $ctx.Note($r.Messaggio) } else { $ctx.Fail($r.Messaggio) }
    }
},
@{
    Id        = 'maint_retrim'
    Nome      = 'Ottimizzazione unita'' (TRIM per SSD)'
    Categoria = 'Manutenzione'
    Livello   = 'Sicuro'
    Descrizione = 'Comunica all''SSD quali blocchi non servono piu'', cosa che ne mantiene la velocita'' di scrittura. Sugli SSD NON e'' una deframmentazione: non consuma cicli di scrittura inutili. I dischi meccanici vengono lasciati alla pianificazione di Windows.'
    Azione = {
        param($ctx)
        if (-not (Get-Command Optimize-Volume -ErrorAction SilentlyContinue)) {
            $ctx.Fail('Optimize-Volume non disponibile su questo sistema'); return
        }

        # Si ricava il tipo di supporto dal disco fisico: il retrim ha
        # senso solo sugli SSD.
        $tipoPerLettera = @{}
        try {
            foreach ($d in (Get-PhysicalDisk -ErrorAction Stop)) {
                foreach ($p in ($d | Get-Disk -ErrorAction SilentlyContinue | Get-Partition -ErrorAction SilentlyContinue)) {
                    if ($p.DriveLetter) { $tipoPerLettera[[string]$p.DriveLetter] = [string]$d.MediaType }
                }
            }
        } catch { }

        $volumi = @(Get-Volume -ErrorAction SilentlyContinue |
                    Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' -and $_.FileSystem -eq 'NTFS' })
        if ($volumi.Count -eq 0) { $ctx.Note('Nessun volume idoneo'); return }

        foreach ($v in $volumi) {
            $lettera = [string]$v.DriveLetter
            $tipo = 'sconosciuto'
            if ($tipoPerLettera.ContainsKey($lettera)) { $tipo = $tipoPerLettera[$lettera] }

            if ($tipo -eq 'HDD') {
                $ctx.Note(('{0}: disco meccanico, lasciato alla pianificazione di Windows' -f $lettera))
                continue
            }
            if ($ctx.DryRun) {
                $ctx.Note(('{0}: verrebbe eseguito il ReTrim ({1})' -f $lettera, $tipo))
                continue
            }
            try {
                Optimize-Volume -DriveLetter $lettera -ReTrim -ErrorAction Stop -WarningAction SilentlyContinue
                $ctx.Items++
                $ctx.Note(('{0}: ReTrim completato ({1})' -f $lettera, $tipo))
            } catch {
                $ctx.Fail(('{0}: {1}' -f $lettera, $_.Exception.Message))
            }
        }
    }
},
@{
    Id        = 'maint_sfc'
    Nome      = 'Verifica integrita'' file di sistema (SFC)'
    Categoria = 'Manutenzione'
    Livello   = 'Avanzato'
    Descrizione = 'sfc /scannow: controlla e ripara i file di sistema. Puo'' durare 10-20 minuti.'
    Azione = {
        param($ctx)
        if ($ctx.DryRun) { $ctx.Note('sfc /scannow (simulazione)'); return }
        $ctx.Note('Avvio di sfc /scannow, attendere...')
        $r = Invoke-LongNative -File 'sfc.exe' -Arguments @('/scannow') -TimeoutSec 2400 -Ctx $ctx
        if ($r.TimedOut) { $ctx.Fail('SFC interrotto per timeout'); return }
        # L'output di sfc e' in UTF-16: puo' arrivare con caratteri
        # nulli interlacciati, li ripulisco prima di analizzarlo.
        $testo = ($r.Output -replace "`0", '')
        if     ($testo -match 'non ha rilevato|did not find any integrity') { $ctx.Note('Nessun problema di integrita'' rilevato') }
        elseif ($testo -match 'ha riparato|successfully repaired')          { $ctx.Note('Trovati e riparati file danneggiati'); $ctx.RebootNeeded = $true }
        elseif ($testo -match 'non e'' stato in grado|was unable to fix')   { $ctx.Fail('Trovati file danneggiati NON riparabili: eseguire DISM RestoreHealth') }
        else { $ctx.Note(('SFC terminato con codice {0}' -f $r.ExitCode)) }
    }
},
@{
    Id        = 'maint_dism_restore'
    Nome      = 'Riparazione immagine di Windows (DISM)'
    Categoria = 'Manutenzione'
    Livello   = 'Avanzato'
    Descrizione = 'DISM /RestoreHealth: ripara l''immagine di sistema scaricando i componenti mancanti. Richiede connessione a Internet.'
    Azione = {
        param($ctx)
        if ($ctx.DryRun) { $ctx.Note('DISM /RestoreHealth (simulazione)'); return }
        $ctx.Note('Avvio di DISM /RestoreHealth, puo'' richiedere parecchi minuti...')
        $r = Invoke-LongNative -File 'dism.exe' -Arguments @('/Online','/Cleanup-Image','/RestoreHealth') -TimeoutSec 3600 -Ctx $ctx
        if ($r.TimedOut) { $ctx.Fail('DISM interrotto per timeout'); return }
        if ($r.ExitCode -eq 0) { $ctx.Note('Immagine di Windows integra o riparata correttamente') }
        else { $ctx.Fail(('DISM ha restituito il codice {0}' -f $r.ExitCode)) }
    }
}

)

# ------------------------------------------------------------
#   Stime di durata, in secondi.
#   Tenute in una tabella a parte invece che dentro ogni task:
#   sono numeri da ritoccare, non parte della definizione.
#   Valori prudenti, riferiti a un PC gia' in uso da un po'.
# ------------------------------------------------------------
$script:Stime = @{
    'clean_temp_user'      = 20;   'clean_temp_system'    = 15
    'clean_temp_allusers'  = 30;   'clean_trash'     = 15
    'clean_wer'            = 5;    'clean_crashdump'      = 5
    'clean_deliveryopt'    = 10;   'clean_fontcache'      = 20
    'clean_browsercache'   = 45;   'clean_thumbcache'     = 25
    'clean_wucache'        = 60;   'clean_componentstore' = 900
    'clean_prefetch'       = 5;    'clean_appcache'       = 60
    'clean_devcache'       = 90;   'clean_windowsold'     = 600
    'net_flushdns'         = 3;    'net_arpcache'         = 3
    'net_renew'            = 25;   'net_registerdns'      = 5
    'net_winsock'          = 5;    'net_ipreset'          = 10
    'net_ipv6reset'        = 10
    'maint_restorepoint'   = 50;   'maint_sfc'            = 900
    'maint_dism_restore'   = 1200; 'maint_retrim'         = 90
}
foreach ($t in $script:TaskRegistry) {
    $t.Stima = 30
    if ($script:Stime.ContainsKey($t.Id)) { $t.Stima = $script:Stime[$t.Id] }
}

# ============================================================
#   ACCESSO AL REGISTRO
# ============================================================

function Get-AllTask { return $script:TaskRegistry }

function Get-StimaTotale {
    param($Tasks)
    $tot = 0
    foreach ($t in @($Tasks)) { $tot += [int]$t.Stima }
    return $tot
}

# ------------------------------------------------------------
#   Serve un punto di ripristino?
#   Se si cancellano solo file rigenerabili no: costerebbe un
#   minuto e occuperebbe spazio senza proteggere da nulla.
#   Se si toccano servizi, rete o componenti di Windows si'.
# ------------------------------------------------------------
function Get-ConsiglioRipristino {
    param($Tasks)
    $lista    = @($Tasks)
    $riavvio  = @($lista | Where-Object { $_.Livello -eq 'Riavvio' })
    $avanzati = @($lista | Where-Object { $_.Livello -eq 'Avanzato' })

    # Il Motivo e' una frase breve senza prefisso: sono i chiamanti a
    # comporre "consigliato: ..." o "non necessario: ...", cosi' la
    # stessa informazione non viene ripetuta due volte a schermo.
    if ($riavvio.Count -gt 0) {
        return [pscustomobject]@{
            Consigliato = $true
            Motivo = 'stai per riscrivere la configurazione di rete'
        }
    }
    if ($avanzati.Count -gt 0) {
        return [pscustomobject]@{
            Consigliato = $true
            Motivo = ('{0} operazioni toccano servizi o componenti di Windows' -f $avanzati.Count)
        }
    }
    return [pscustomobject]@{
        Consigliato = $false
        Motivo = 'le operazioni scelte non modificano la configurazione del sistema'
    }
}

function Get-Task {
    param([Parameter(Mandatory=$true)][string]$Id)
    return ($script:TaskRegistry | Where-Object { $_.Id -eq $Id } | Select-Object -First 1)
}

function Get-TaskByCategory {
    param([Parameter(Mandatory=$true)][string]$Categoria)
    return @($script:TaskRegistry | Where-Object { $_.Categoria -eq $Categoria })
}

# Insiemi predefiniti usati dal menu.
function Get-TaskSet {
    param([Parameter(Mandatory=$true)][string]$Nome)
    $ids = switch ($Nome) {
        'PuliziaSicura'   { @('clean_temp_user','clean_temp_system','clean_temp_allusers',
                              'clean_trash','clean_wer','clean_crashdump','clean_deliveryopt') }
        'PuliziaAvanzata' { @('clean_browsercache','clean_appcache','clean_devcache',
                              'clean_thumbcache','clean_fontcache','clean_wucache',
                              'clean_windowsold','clean_componentstore') }
        'RetePulizia'     { @('net_flushdns','net_arpcache','net_renew','net_registerdns') }
        'ReteReset'       { @('net_winsock','net_ipreset','net_ipv6reset') }
        'Manutenzione'    { @('maint_restorepoint','maint_retrim','maint_sfc','maint_dism_restore') }
        default           { @() }
    }
    return @($ids | ForEach-Object { Get-Task -Id $_ } | Where-Object { $_ })
}
