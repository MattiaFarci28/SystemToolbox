# ============================================================
#   Common.ps1 - Infrastruttura condivisa
#
#   Corrisponde a lib/common.sh dei due progetti shell:
#   versione, configurazione, codici di uscita, esportazione del
#   report, modalita' JSON e confronto con l'esecuzione
#   precedente.
#
#   Non conosce l'interfaccia ne' le operazioni.
# ============================================================

Set-StrictMode -Version 1.0

$script:TB_VERSIONE = '1.0.0'

# ============================================================
#   RILANCIO
#   Lo script riparte da solo in due casi: per passare a 64 bit e
#   per ottenere i privilegi di amministratore. I parametri vanno
#   inoltrati TUTTI: prima l'elenco era scritto a mano e quelli
#   aggiunti dopo (-Report, -Json, -Config, -Daltonici, -NoColor)
#   si perdevano, per cui "Toolbox.bat -Report r.html" chiedeva
#   l'UAC, ripartiva e non produceva alcun report.
#
#   I percorsi diventano assoluti: il processo elevato parte da
#   C:\Windows\System32, e "r.html" sarebbe finito li'.
# ============================================================
function Get-ArgomentiRilancio {
    param(
        [Parameter(Mandatory=$true)][System.Collections.IDictionary]$Parametri,
        [Parameter(Mandatory=$true)][string]$Script
    )
    $a = @('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File', ('"' + $Script + '"'))
    foreach ($k in @($Parametri.Keys)) {
        $v = $Parametri[$k]
        if ($v -is [System.Management.Automation.SwitchParameter] -or $v -is [bool]) {
            if ($v) { $a += ('-' + $k) }
            continue
        }
        # IsPathRooted e non GetUnresolvedProviderPathFromPSPath:
        # quest'ultimo va in errore se l'unita' non esiste (una
        # chiavetta non inserita) e fermerebbe tutto prima di partire.
        if ($k -in @('Report','Config') -and -not [System.IO.Path]::IsPathRooted([string]$v)) {
            $v = Join-Path (Get-Location).ProviderPath ([string]$v)
        }
        $a += ('-' + $k)
        $a += ('"' + [string]$v + '"')
    }
    return ,$a
}

# ============================================================
#   CODICI DI USCITA
#   0 = tutto a posto
#   1 = avvisi, oppure operazioni con esito parziale
#   2 = criticita': operazione fallita o problema grave
#   Servono a chi lo lancia dall'Utilita' di pianificazione, che
#   altrimenti non ha modo di sapere com'e' andata.
# ============================================================
$script:TB_EXIT = 0
function Set-EsitoAvviso  { if ($script:TB_EXIT -lt 1) { $script:TB_EXIT = 1 } }
function Set-EsitoCritico { $script:TB_EXIT = 2 }
function Get-EsitoCodice  { return $script:TB_EXIT }
function Get-EsitoTesto {
    switch ($script:TB_EXIT) {
        0 { 'nessuna criticita' }
        1 { 'avvisi presenti' }
        default { 'criticita rilevate' }
    }
}

# ============================================================
#   CONFIGURAZIONE
#   Le soglie erano costanti sparse nel codice. Ora hanno un
#   valore predefinito qui e si possono cambiare da file.
#
#   Il file NON viene interpretato come codice: si legge riga per
#   riga e si accettano solo le chiavi note.
# ============================================================
$script:CFG = @{
    disco_avviso         = 80
    disco_critico        = 90
    ram_critica          = 90
    swap_avviso_mb       = 1024
    avvii_avviso         = 12
    uptime_avviso_giorni = 7
    log_da_conservare    = 15
    analisi_aggiornamenti = 'si'
    colori               = 'auto'
    tema                 = 'auto'
    lingua               = 'it'
}

function Import-Configurazione {
    param([string]$Percorso)
    if (-not (Test-Path -LiteralPath $Percorso -ErrorAction SilentlyContinue)) { return }

    $numeriche = @('disco_avviso','disco_critico','ram_critica','swap_avviso_mb',
                   'avvii_avviso','uptime_avviso_giorni','log_da_conservare')
    $testuali  = @{ colori = @('auto','si','no','daltonici'); lingua = @('it','en')
                    analisi_aggiornamenti = @('si','no')
                    tema = @('auto','chiaro','scuro') }

    foreach ($riga in (Get-Content -LiteralPath $Percorso -ErrorAction SilentlyContinue)) {
        $r = $riga.Trim()
        if ($r -eq '' -or $r.StartsWith('#')) { continue }
        if ($r -notmatch '=') { continue }
        $k = ($r -split '=', 2)[0].Trim()
        $v = ($r -split '=', 2)[1]
        if ($v -match '#') { $v = ($v -split '#', 2)[0] }
        $v = $v.Trim()

        if ($numeriche -contains $k) {
            $n = 0
            if ([int]::TryParse($v, [ref]$n)) { $script:CFG[$k] = $n }
        } elseif ($testuali.ContainsKey($k)) {
            if ($testuali[$k] -contains $v) { $script:CFG[$k] = $v }
        }
        # chiavi sconosciute: ignorate di proposito
    }
}

# ============================================================
#   REPORT
#   Le funzioni Write-* di ConsoleUI alimentano questo buffer:
#   il documento esportato nasce dallo stesso codice che disegna
#   a schermo, quindi non esiste una seconda descrizione da
#   tenere allineata.
# ============================================================
$script:TB_REPORT = ''
$script:TB_REPBUF = New-Object System.Collections.ArrayList

function Add-Report {
    param([string]$Riga)
    if (-not $script:TB_REPORT) { return }
    $script:TB_REPBUF.Add($Riga) | Out-Null
}

function Export-Report {
    if (-not $script:TB_REPORT) { return }
    if ($script:TB_REPORT -match '\.html?$') { Export-ReportHtml } else { Export-ReportMarkdown }
}

function Export-ReportMarkdown {
    $testa = @(
        '# System Toolbox - report'
        ''
        "- Versione strumento: $script:TB_VERSIONE"
        "- Data: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        "- Sistema: $script:TB_SISTEMA"
        "- Esito: $(Get-EsitoTesto)"
        ''
        '---'
        ''
    )
    try {
        ($testa + $script:TB_REPBUF) | Set-Content -LiteralPath $script:TB_REPORT -Encoding UTF8 -ErrorAction Stop
    } catch { }
}

function Export-ReportHtml {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<!doctype html><meta charset="utf-8"><title>System Toolbox - report</title>')
    [void]$sb.AppendLine(@'
<style>
 body{font:15px/1.6 Segoe UI,-apple-system,Roboto,sans-serif;max-width:60rem;
      margin:2rem auto;padding:0 1.2rem;background:#15151a;color:#c9c9d2}
 h1{font-size:1.5rem;color:#f2f2f6;margin-bottom:.2rem}
 h2{font-size:1.05rem;color:#38d6ee;margin-top:2rem;
    border-bottom:1px solid #2c2c38;padding-bottom:.3rem}
 .meta{color:#7e7e8c;font-size:.9rem;margin-bottom:2rem}
 .kv{display:flex;gap:.6rem;padding:.15rem 0}
 .kv b{color:#9a9aa8;font-weight:600;min-width:16rem}
 .avviso{background:#3a2e12;border-left:3px solid #d9a441;padding:.5rem .8rem;
         margin:.4rem 0;border-radius:0 4px 4px 0}
 .errore{background:#3a1a1a;border-left:3px solid #f87171;padding:.5rem .8rem;
         margin:.4rem 0;border-radius:0 4px 4px 0}
 .ok{color:#4ade80}
 .nota{color:#7e7e8c;font-size:.92rem}
</style>
'@)
    # System.Web non e' caricato di default in PowerShell 5.1:
    # System.Net.WebUtility fa la stessa cosa ed e' sempre presente.
    $meta = 'versione {0} - {1} - {2} - esito: {3}' -f $script:TB_VERSIONE,
            (Get-Date -Format 'yyyy-MM-dd HH:mm'), $script:TB_SISTEMA, (Get-EsitoTesto)
    [void]$sb.AppendLine('<h1>System Toolbox</h1>')
    [void]$sb.AppendLine('<div class="meta">' + [System.Net.WebUtility]::HtmlEncode($meta) + '</div>')

    foreach ($r in $script:TB_REPBUF) {
        if ($r -eq '') { [void]$sb.AppendLine(''); continue }
        if ($r -like '## *') {
            [void]$sb.AppendLine('<h2>' + [System.Net.WebUtility]::HtmlEncode($r.Substring(3)) + '</h2>')
        } elseif ($r -match '^- \*\*(.+?)\*\*: (.*)$') {
            $k = [System.Net.WebUtility]::HtmlEncode($matches[1])
            $v = [System.Net.WebUtility]::HtmlEncode($matches[2])
            [void]$sb.AppendLine('<div class="kv"><b>' + $k + '</b><span>' + $v + '</span></div>')
        } elseif ($r -like '> [!] *') {
            [void]$sb.AppendLine('<div class="avviso">' + [System.Net.WebUtility]::HtmlEncode($r.Substring(6)) + '</div>')
        } elseif ($r -like '> [X] *') {
            [void]$sb.AppendLine('<div class="errore">' + [System.Net.WebUtility]::HtmlEncode($r.Substring(6)) + '</div>')
        } elseif ($r -like '> [ok] *') {
            [void]$sb.AppendLine('<div class="ok">' + [System.Net.WebUtility]::HtmlEncode($r.Substring(7)) + '</div>')
        } else {
            [void]$sb.AppendLine('<div class="nota">' + [System.Net.WebUtility]::HtmlEncode($r) + '</div>')
        }
    }
    try { $sb.ToString() | Set-Content -LiteralPath $script:TB_REPORT -Encoding UTF8 -ErrorAction Stop } catch { }
}

# ============================================================
#   MODALITA' JSON
#   Per il consumo da script: monitoraggio, confronto fra due
#   esecuzioni, raccolta su piu' macchine.
# ============================================================
$script:TB_JSON = $false
$script:TB_JSON_OPS = New-Object System.Collections.ArrayList
$script:TB_JSON_AVVISI = New-Object System.Collections.ArrayList

function Add-JsonOperazione {
    param($Id, $Nome, $Esito, $Byte, $Durata, $Errori)
    $script:TB_JSON_OPS.Add([pscustomobject]@{
        id = $Id; nome = $Nome; esito = $Esito
        byte_liberati = [long]$Byte; durata_s = [int]$Durata; errori = [int]$Errori
    }) | Out-Null
}

function Add-JsonAvviso {
    param([string]$Testo)
    $script:TB_JSON_AVVISI.Add($Testo) | Out-Null
}

function Write-Json {
    if (-not $script:TB_JSON) { return }
    # $script:Simula appartiene a Toolbox.ps1: qui potrebbe non
    # esistere, per esempio quando i moduli vengono caricati da
    # soli dalla suite di collaudo.
    $simula = $false
    try { if (Get-Variable -Name Simula -Scope Script -ErrorAction SilentlyContinue) { $simula = [bool]$script:Simula } } catch { }
    [pscustomobject]@{
        versione_strumento = $script:TB_VERSIONE
        data               = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
        sistema            = $script:TB_SISTEMA
        simulazione        = $simula
        esito              = $script:TB_EXIT
        spazio_libero_byte = (Get-FreeSpace)
        avvisi             = @($script:TB_JSON_AVVISI)
        operazioni         = @($script:TB_JSON_OPS)
    } | ConvertTo-Json -Depth 4
}

# ============================================================
#   CONFRONTO CON L'ESECUZIONE PRECEDENTE
#   Storico minimo in un file di testo: una riga per esecuzione.
# ============================================================
$script:TB_STORICO = ''

function Initialize-Storico { param([string]$Percorso) $script:TB_STORICO = $Percorso }

function Write-Storico {
    param([int]$Avvisi = 0)
    if (-not $script:TB_STORICO) { return }
    try {
        $riga = '{0}|{1}|{2}' -f [int][double]::Parse((Get-Date -UFormat %s)), (Get-FreeSpace), $Avvisi
        Add-Content -LiteralPath $script:TB_STORICO -Value $riga -Encoding UTF8 -ErrorAction Stop
        $tutte = @(Get-Content -LiteralPath $script:TB_STORICO -ErrorAction Stop)
        if ($tutte.Count -gt 200) {
            $tutte | Select-Object -Last 100 | Set-Content -LiteralPath $script:TB_STORICO -Encoding UTF8
        }
    } catch { }
}

# Restituisce la voce piu' vecchia entro 30 giorni, escludendo
# l'ultima ora: confrontarsi con se stessi cinque minuti prima
# non direbbe nulla.
function Compare-Storico {
    if (-not $script:TB_STORICO -or -not (Test-Path -LiteralPath $script:TB_STORICO -EA SilentlyContinue)) { return $null }
    $ora = [int][double]::Parse((Get-Date -UFormat %s))
    foreach ($riga in (Get-Content -LiteralPath $script:TB_STORICO -ErrorAction SilentlyContinue)) {
        $p = $riga -split '\|'
        if ($p.Count -lt 3) { continue }
        $t = 0
        if (-not [int]::TryParse($p[0], [ref]$t)) { continue }
        if ($t -lt ($ora - 2592000)) { continue }
        if (($ora - $t) -lt 3600) { continue }
        return [pscustomobject]@{
            Giorni = [int](($ora - $t) / 86400)
            Delta  = [long]((Get-FreeSpace) - [long]$p[1])
            Avvisi = [int]$p[2]
        }
    }
    return $null
}
