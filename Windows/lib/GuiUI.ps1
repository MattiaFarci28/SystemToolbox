# ============================================================
#   GuiUI.ps1 - Interfaccia grafica WPF
#
#   Nessuna logica di sistema: questo file disegna la finestra
#   e fa da ponte verso il motore. Task, analisi e rendering
#   sono gli stessi usati dal menu testuale.
#
#   Due scelte importanti:
#
#   1) Il lavoro gira in un RUNSPACE separato. Eseguirlo sul
#      thread della UI congelerebbe la finestra e Windows la
#      marcherebbe "Non risponde".
#
#   2) Il thread di lavoro NON tocca i controlli. Accoda
#      messaggi in una coda sincronizzata che un DispatcherTimer
#      svuota sul thread della UI. E' piu' robusto di
#      Dispatcher.Invoke, che con chiamate frequenti puo'
#      bloccarsi a vicenda con il thread chiamante.
#
#   Il trucco che evita di riscrivere il rendering: nel runspace
#   di lavoro viene definita una funzione Write-Host che
#   sostituisce il cmdlet. Le funzioni Show-* di ConsoleUI.ps1
#   continuano a chiamare Write-Host senza saperlo e il loro
#   output, colori compresi, finisce nel pannello della GUI.
# ============================================================

Set-StrictMode -Version 1.0

$script:Sync     = $null
$script:Pennelli = @{}

# ------------------------------------------------------------
#   Console: nascondere/mostrare la finestra nera di appoggio
# ------------------------------------------------------------
function Initialize-ConsoleApi {
    if (-not ('ToolboxNativo.Console' -as [type])) {
        Add-Type -Namespace 'ToolboxNativo' -Name 'Console' -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
'@
    }
}

function Hide-ConsoleWindow {
    try {
        Initialize-ConsoleApi
        $h = [ToolboxNativo.Console]::GetConsoleWindow()
        if ($h -ne [IntPtr]::Zero) { [ToolboxNativo.Console]::ShowWindow($h, 0) | Out-Null }
    } catch { }
}

function Show-ConsoleWindow {
    try {
        Initialize-ConsoleApi
        $h = [ToolboxNativo.Console]::GetConsoleWindow()
        if ($h -ne [IntPtr]::Zero) { [ToolboxNativo.Console]::ShowWindow($h, 5) | Out-Null }
    } catch { }
}


# ------------------------------------------------------------
#   TEMA
#   Lo XAML usa segnaposto al posto dei colori: la palette viene
#   sostituita prima di caricare la finestra. E' molto meno
#   fragile di un rifacimento con DynamicResource, e permette di
#   seguire il tema chiaro o scuro di Windows.
#
#   La preferenza si legge da AppsUseLightTheme, la stessa chiave
#   che usa Windows per le applicazioni.
# ------------------------------------------------------------
function Get-TemaWindows {
    switch ($script:CFG['tema']) {
        'chiaro' { return 'chiaro' }
        'scuro'  { return 'scuro' }
    }
    try {
        $v = (Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' `
                               -Name AppsUseLightTheme -ErrorAction Stop).AppsUseLightTheme
        if ($v -eq 1) { return 'chiaro' }
    } catch { }
    return 'scuro'
}

function Get-Palette {
    param([string]$Tema)
    if ($Tema -eq 'chiaro') {
        return @{
            FONDO='#F4F4F7'; BARRA='#FFFFFF'; BORDO='#DCDCE4'; TESTO='#1A1A20'
            TESTO2='#6A6A76'; PANNELLO='#FAFAFC'; PANNELLO2='#F0F0F4'
            DIVISORE='#DCDCE4'; OUTFONDO='#FFFFFF'; OUTTESTO='#26262E'
            BTNFONDO='#FFFFFF'; BTNBORDO='#C6C6D0'; BTNTESTO='#22222A'
            BTNHOVER='#ECECF2'; BTNHOVERB='#9C9CAC'; BTNPICC='#F4F4F8'
            CHKTESTO='#2E2E38'; SEZIONE='#78788A'; BARRAFONDO='#E2E2EA'
            STATO='#565664'; CHIPFONDO='#DCF5E4'; CHIPBORDO='#7CCF9A'; CHIPTESTO='#146B39'
        }
    }
    return @{
        FONDO='#15151A'; BARRA='#1D1D25'; BORDO='#2C2C38'; TESTO='#F2F2F6'
        TESTO2='#7E7E8C'; PANNELLO='#1A1A21'; PANNELLO2='#16161D'
        DIVISORE='#2A2A34'; OUTFONDO='#0F0F13'; OUTTESTO='#C6C6CF'
        BTNFONDO='#292933'; BTNBORDO='#3A3A46'; BTNTESTO='#E6E6EC'
        BTNHOVER='#363642'; BTNHOVERB='#54546A'; BTNPICC='#22222B'
        CHKTESTO='#D2D2DA'; SEZIONE='#6E6E80'; BARRAFONDO='#26262F'
        STATO='#9A9AA8'; CHIPFONDO='#14351F'; CHIPBORDO='#1F5C33'; CHIPTESTO='#4ADE80'
    }
}

function Expand-Palette {
    param([string]$Xaml, [hashtable]$Palette)
    foreach ($k in $Palette.Keys) { $Xaml = $Xaml.Replace('@' + $k + '@', $Palette[$k]) }
    return $Xaml
}

# ------------------------------------------------------------
#   ICONA
#   Disegnata a runtime invece di distribuire un file .ico: la
#   cartella resta fatta di soli script, e non c'e' un binario da
#   spiegare o da cui diffidare.
#   E' un quadrato arrotondato con le iniziali, nel blu di
#   accento della finestra.
# ------------------------------------------------------------
function New-IconaFinestra {
    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        $lato = 64
        $bmp = New-Object System.Drawing.Bitmap($lato, $lato)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.SmoothingMode     = [System.Drawing.Drawing2D]::SmoothingMode.AntiAlias
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias

        $perc = New-Object System.Drawing.Drawing2D.GraphicsPath
        $r = 14; $d = $r * 2
        $perc.AddArc(0, 0, $d, $d, 180, 90)
        $perc.AddArc($lato - $d, 0, $d, $d, 270, 90)
        $perc.AddArc($lato - $d, $lato - $d, $d, $d, 0, 90)
        $perc.AddArc(0, $lato - $d, $d, $d, 90, 90)
        $perc.CloseFigure()

        $pennello = New-Object System.Drawing.SolidBrush(
                        [System.Drawing.ColorTranslator]::FromHtml('#2563EB'))
        $g.FillPath($pennello, $perc)

        $font = New-Object System.Drawing.Font('Segoe UI', 26, [System.Drawing.FontStyle]::Bold)
        $fmt = New-Object System.Drawing.StringFormat
        $fmt.Alignment = 'Center'; $fmt.LineAlignment = 'Center'
        $g.DrawString('ST', $font, [System.Drawing.Brushes]::White,
                      (New-Object System.Drawing.RectangleF(0, 2, $lato, $lato)), $fmt)
        $g.Dispose()

        $hbmp = $bmp.GetHbitmap()
        $img = [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHBitmap(
                   $hbmp, [IntPtr]::Zero, [System.Windows.Int32Rect]::Empty,
                   [System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions())
        # L'handle GDI va rilasciato a mano, altrimenti resta appeso.
        [ToolboxNativo.Gdi]::DeleteObject($hbmp) | Out-Null
        $bmp.Dispose()
        return $img
    } catch { return $null }
}

function Initialize-GdiApi {
    if (-not ('ToolboxNativo.Gdi' -as [type])) {
        Add-Type -Namespace 'ToolboxNativo' -Name 'Gdi' -MemberDefinition @'
[DllImport("gdi32.dll")] public static extern bool DeleteObject(System.IntPtr o);
'@
    }
}

# ------------------------------------------------------------
#   Colori: dai nomi ConsoleColor usati da ConsoleUI.ps1 a
#   pennelli WPF leggibili su fondo scuro.
# ------------------------------------------------------------
function New-PennelloConsole {
    param([string]$Nome = 'Gray')
    if ($script:Pennelli.ContainsKey($Nome)) { return $script:Pennelli[$Nome] }

    # Questi valori NON sono segnaposto dello XAML: qui siamo in
    # codice PowerShell e la sostituzione della palette non passa.
    # Su fondo chiaro i toni pensati per il fondo scuro diventano
    # illeggibili, quindi la tabella e' doppia.
    if ($script:TemaCorrente -eq 'chiaro') {
        $mappa = @{
            'Black'      = '#1A1A20'; 'DarkBlue'    = '#1D4ED8'
            'DarkGreen'  = '#15803D'; 'DarkCyan'    = '#0E7490'
            'DarkRed'    = '#B91C1C'; 'DarkMagenta' = '#7E22CE'
            'DarkYellow' = '#A16207'; 'Gray'        = '#26262E'
            'DarkGray'   = '#6A6A76'; 'Blue'        = '#1D4ED8'
            'Green'      = '#15803D'; 'Cyan'        = '#0E7490'
            'Red'        = '#B91C1C'; 'Magenta'     = '#A21CAF'
            'Yellow'     = '#A16207'; 'White'       = '#0F0F14'
        }
        $hex = '#26262E'
    } else {
        $mappa = @{
            'Black'      = '#3A3A44'; 'DarkBlue'    = '#3B82F6'
            'DarkGreen'  = '#4ADE80'; 'DarkCyan'    = '#5EEAD4'
            'DarkRed'    = '#F87171'; 'DarkMagenta' = '#D8B4FE'
            'DarkYellow' = '#D9A441'; 'Gray'        = '#C6C6CF'
            'DarkGray'   = '#7E7E8C'; 'Blue'        = '#60A5FA'
            'Green'      = '#4ADE80'; 'Cyan'        = '#38D6EE'
            'Red'        = '#F87171'; 'Magenta'     = '#E879F9'
            'Yellow'     = '#FBBF24'; 'White'       = '#F4F4F7'
        }
        $hex = '#C6C6CF'
    }
    if ($mappa.ContainsKey($Nome)) { $hex = $mappa[$Nome] }
    $pennello = New-Object System.Windows.Media.SolidColorBrush(
                    [System.Windows.Media.ColorConverter]::ConvertFromString($hex))
    $pennello.Freeze()
    $script:Pennelli[$Nome] = $pennello
    return $pennello
}

# ============================================================
#   CODICE ESEGUITO NEL RUNSPACE DI LAVORO
#   Variabili iniettate: sync, radice, logPath, modo, taskIds,
#   dryRun, rapida
# ============================================================
$script:CodiceWorker = @'
$ErrorActionPreference = 'Continue'
try {
    # Il runspace di lavoro ha uno spazio dei nomi tutto suo: qui va
    # caricato lo STESSO elenco di moduli di Toolbox.ps1, altrimenti
    # le funzioni che mancano si scoprono solo a video, a meta' di
    # un'analisi. Common.ps1 va per primo: gli altri lo usano.
    . (Join-Path $radice 'lib\Common.ps1')
    . (Join-Path $radice 'lib\Core.ps1')
    . (Join-Path $radice 'lib\Tasks.ps1')
    . (Join-Path $radice 'lib\Analysis.ps1')
    . (Join-Path $radice 'lib\ConsoleUI.ps1')
    Set-LogPath $logPath
    Initialize-Storico $storicoPath
    if ($configPath) { Import-Configurazione $configPath }

    # Sostituisce il cmdlet Write-Host: le funzioni gia' scritte
    # per la console finiscono cosi' nel pannello della finestra.
    function Write-Host {
        param(
            [Parameter(Position = 0, ValueFromPipeline = $true)] $Object,
            [switch] $NoNewline,
            $ForegroundColor,
            $BackgroundColor,
            $Separator
        )
        $testo = ''
        if ($null -ne $Object) { $testo = [string]$Object }
        $colore = 'Gray'
        if ($ForegroundColor) { $colore = [string]$ForegroundColor }
        $sync.Coda.Enqueue(@{ Tipo = 'seg'; Testo = $testo; Colore = $colore; ACapo = (-not $NoNewline) })
    }

    Set-DetailHandler -Handler { param($m) Write-Host ('      ' + $m) -ForegroundColor DarkGray }

    if ($modo -eq 'analisi') {
        $titolo = 'Analisi completa del sistema'
        if ($rapida) { $titolo = 'Analisi rapida' }
        Write-Title $titolo
        Write-Log ('--- ' + $titolo + ' (GUI)') 'STEP'
        Show-Analisi -Rapida:$rapida | Out-Null
    }
    else {
        $tasks = @()
        foreach ($id in $taskIds) {
            $t = Get-Task -Id $id
            if ($t) { $tasks += $t }
        }
        $totale = $tasks.Count
        $spazioPrima = Get-FreeSpace
        $risultati = New-Object System.Collections.ArrayList
        $n = 0

        Write-Title 'Esecuzione'
        foreach ($t in $tasks) {
            if ($sync.Annulla) {
                Write-Host ''
                Write-Host '  Interrotto su richiesta: le operazioni rimanenti non sono state eseguite.' -ForegroundColor Yellow
                Write-Log 'Interrotto dall utente' 'WARN'
                break
            }
            $n++
            $sync.Coda.Enqueue(@{ Tipo = 'prog'; Valore = $n; Max = $totale; Stato = $t.Nome })
            Write-Host ''
            Write-Step ('{0}/{1}' -f $n, $totale) $t.Nome
            $r = Invoke-Task -Task $t -DryRun:$dryRun
            $risultati.Add($r) | Out-Null
            switch ($r.Esito) {
                'OK'       { Write-Ok   '[completato]' }
                'PARZIALE' { Write-Warn ('[completato con {0} avvisi]' -f $r.Errors.Count) }
                'FALLITO'  { Write-Err  '[non riuscito]' }
            }
        }

        $delta = (Get-FreeSpace) - $spazioPrima
        if ($dryRun -or $delta -lt 0) { $delta = -1 }
        Show-TaskSummary -Risultati @($risultati) -SpazioReale $delta

        $serveRiavvio = [bool](@($risultati | Where-Object { $_.Reboot }).Count -gt 0)
        $sync.Coda.Enqueue(@{
            Tipo     = 'esiti'
            Reboot   = $serveRiavvio
            Ok       = @($risultati | Where-Object { $_.Esito -eq 'OK' }).Count
            Parziali = @($risultati | Where-Object { $_.Esito -eq 'PARZIALE' }).Count
            Falliti  = @($risultati | Where-Object { $_.Esito -eq 'FALLITO' }).Count
            Byte     = [long](($risultati | Measure-Object -Property Bytes -Sum).Sum)
        })
    }
}
catch {
    $sync.Coda.Enqueue(@{ Tipo = 'seg'; Testo = ('  ERRORE NON GESTITO: ' + $_.Exception.Message); Colore = 'Red'; ACapo = $true })
    $sync.Coda.Enqueue(@{ Tipo = 'seg'; Testo = ('  ' + $_.ScriptStackTrace); Colore = 'DarkGray'; ACapo = $true })
}
finally {
    $sync.Coda.Enqueue(@{ Tipo = 'fine' })
}
'@

# ============================================================
#   XAML
# ============================================================
$script:Xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="System Toolbox" Height="740" Width="1180"
        MinHeight="600" MinWidth="1000"
        WindowStartupLocation="CenterScreen" Background="@FONDO@"
        TextOptions.TextFormattingMode="Display">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Foreground" Value="@BTNTESTO@"/>
      <Setter Property="Background" Value="@BTNFONDO@"/>
      <Setter Property="BorderBrush" Value="@BTNBORDO@"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="14,7"/>
      <Setter Property="Margin" Value="6,0,0,0"/>
      <Setter Property="FontSize" Value="12.5"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="4" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="@BTNHOVER@"/>
                <Setter TargetName="bd" Property="BorderBrush" Value="@BTNHOVERB@"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.35"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Primario" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Background" Value="#2563EB"/>
      <Setter Property="BorderBrush" Value="#3B82F6"/>
      <Setter Property="Foreground" Value="#FFFFFF"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
    </Style>

    <Style x:Key="Piccolo" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Padding" Value="9,4"/>
      <Setter Property="Margin" Value="0,0,6,6"/>
      <Setter Property="FontSize" Value="11.5"/>
      <Setter Property="Background" Value="@BTNPICC@"/>
    </Style>

    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="@CHKTESTO@"/>
      <Setter Property="FontSize" Value="12.5"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
      <Setter Property="Margin" Value="0,3,0,3"/>
    </Style>

    <Style x:Key="Sezione" TargetType="TextBlock">
      <Setter Property="Foreground" Value="@SEZIONE@"/>
      <Setter Property="FontSize" Value="10.5"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
      <Setter Property="Margin" Value="0,14,0,6"/>
    </Style>
  </Window.Resources>

  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <Border Grid.Row="0" Background="@BARRA@" BorderBrush="@BORDO@" BorderThickness="0,0,0,1" Padding="18,12">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <StackPanel Grid.Column="0">
          <TextBlock Text="System Toolbox" Foreground="@TESTO@" FontSize="17" FontWeight="SemiBold" FontFamily="Segoe UI"/>
          <TextBlock x:Name="TxtSottotitolo" Foreground="@TESTO2@" FontSize="11.5" FontFamily="Segoe UI" Margin="0,2,0,0"/>
        </StackPanel>
        <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
          <Border x:Name="ChipAdmin" Background="@CHIPFONDO@" BorderBrush="@CHIPBORDO@" BorderThickness="1" CornerRadius="10" Padding="10,3" Margin="0,0,14,0">
            <TextBlock x:Name="TxtAdmin" Text="Amministratore" Foreground="@CHIPTESTO@" FontSize="11" FontFamily="Segoe UI"/>
          </Border>
          <CheckBox x:Name="ChkSimula" Content="Modalita simulazione" ToolTip="Mostra cosa verrebbe fatto senza modificare nulla"/>
        </StackPanel>
      </Grid>
    </Border>

    <Grid Grid.Row="1">
      <Grid.ColumnDefinitions>
        <ColumnDefinition x:Name="ColSinistra" Width="410" MinWidth="300"/>
        <ColumnDefinition Width="4"/>
        <!-- 570 e' il minimo perche' la tabella del riepilogo, larga
             72 caratteri, entri sempre senza scorrimento orizzontale -->
        <ColumnDefinition Width="*" MinWidth="570"/>
      </Grid.ColumnDefinitions>

      <Border Grid.Column="0" Background="@PANNELLO@">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>

          <StackPanel Grid.Row="0" Margin="16,14,16,4">
            <TextBlock Text="SELEZIONE RAPIDA" Style="{StaticResource Sezione}" Margin="0,0,0,8"/>
            <WrapPanel x:Name="PanelPreset"/>
            <Border Background="@BTNPICC@" BorderBrush="@BTNBORDO@" BorderThickness="1"
                    CornerRadius="4" Padding="8,4" Margin="0,4,0,0">
              <Grid>
                <TextBlock x:Name="TxtCercaVuoto" Text="Cerca fra le operazioni..."
                           Foreground="@TESTO2@" FontSize="12" FontFamily="Segoe UI"
                           IsHitTestVisible="False" VerticalAlignment="Center"/>
                <TextBox x:Name="TxtCerca" Background="Transparent" Foreground="@CHKTESTO@"
                         BorderThickness="0" FontSize="12" FontFamily="Segoe UI"
                         CaretBrush="@CHKTESTO@" VerticalAlignment="Center"/>
              </Grid>
            </Border>
          </StackPanel>

          <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Margin="0,4,0,0">
            <StackPanel x:Name="PanelTask" Margin="16,0,16,10"/>
          </ScrollViewer>

          <Border Grid.Row="2" Background="@PANNELLO2@" BorderBrush="@DIVISORE@" BorderThickness="0,1,0,0" Padding="16,10">
            <StackPanel>
              <Border x:Name="PanSintesi" Visibility="Collapsed" CornerRadius="4"
                      Padding="10,7" Margin="0,0,0,10" BorderThickness="1">
                <StackPanel>
                  <TextBlock x:Name="TxtSintesiTitolo" FontSize="12.5" FontWeight="SemiBold" FontFamily="Segoe UI"/>
                  <TextBlock x:Name="TxtSintesiDett" FontSize="11.5" FontFamily="Segoe UI"
                             TextWrapping="Wrap" Margin="0,3,0,0"/>
                </StackPanel>
              </Border>
              <CheckBox x:Name="ChkRipristino" Content="Crea un punto di ripristino prima di iniziare"/>
              <TextBlock x:Name="TxtRipristino" Foreground="@TESTO2@" FontSize="11" FontFamily="Segoe UI" TextWrapping="Wrap" Margin="24,2,0,0"/>
              <TextBlock x:Name="TxtConteggio" Foreground="@STATO@" FontSize="11.5" FontFamily="Segoe UI" TextWrapping="Wrap" Margin="0,8,0,0"/>
            </StackPanel>
          </Border>
        </Grid>
      </Border>

      <GridSplitter Grid.Column="1" Width="4" Background="@DIVISORE@" HorizontalAlignment="Stretch"/>

      <Border Grid.Column="2" Background="@OUTFONDO@">
        <RichTextBox x:Name="RtbOut" IsReadOnly="True" IsDocumentEnabled="True"
                     Background="@OUTFONDO@" Foreground="@OUTTESTO@" BorderThickness="0"
                     FontFamily="Consolas" FontSize="12.5" Padding="12,10"
                     VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"/>
      </Border>
    </Grid>

    <Border Grid.Row="2" Background="@BARRA@" BorderBrush="@BORDO@" BorderThickness="0,1,0,0" Padding="16,10">
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Grid Grid.Row="0" Margin="0,0,0,10">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <ProgressBar x:Name="Barra" Grid.Column="0" Height="5" Minimum="0" Maximum="1" Value="0" Background="@BARRAFONDO@" Foreground="#3B82F6" BorderThickness="0"/>
          <TextBlock x:Name="TxtStato" Grid.Column="1" Margin="14,0,0,0" Foreground="@STATO@" FontSize="11.5" FontFamily="Segoe UI" VerticalAlignment="Center" Text="Pronto"/>
        </Grid>
        <StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Right">
          <Button x:Name="BtnPulisciOut" Content="Pulisci pannello"/>
          <Button x:Name="BtnLog" Content="Apri log"/>
          <Button x:Name="BtnReport" Content="Esporta report"/>
          <Button x:Name="BtnAnalisiRapida" Content="Analisi rapida"/>
          <Button x:Name="BtnAnalisi" Content="Analisi completa"/>
          <Button x:Name="BtnInterrompi" Content="Interrompi" IsEnabled="False"/>
          <Button x:Name="BtnEsegui" Content="Esegui selezionati" Style="{StaticResource Primario}"/>
        </StackPanel>
      </Grid>
    </Border>
  </Grid>
</Window>
'@


# ------------------------------------------------------------
#   STATO DELLA SESSIONE
#   Dimensioni della finestra, posizione del divisorio e ultima
#   selezione: senza, a ogni avvio si ricomincia da capo.
#   File di testo con chiave=valore, come la configurazione.
# ------------------------------------------------------------
function Get-PercorsoStato { return (Join-Path $script:Sync.Radice 'logs\stato-gui.txt') }

function Import-StatoGui {
    $f = Get-PercorsoStato
    if (-not (Test-Path -LiteralPath $f -ErrorAction SilentlyContinue)) { return }
    $s = $script:Sync
    foreach ($riga in (Get-Content -LiteralPath $f -ErrorAction SilentlyContinue)) {
        if ($riga -notmatch '=') { continue }
        $k = ($riga -split '=', 2)[0].Trim()
        $v = ($riga -split '=', 2)[1].Trim()
        switch ($k) {
            'larghezza' { $n=0; if ([int]::TryParse($v,[ref]$n) -and $n -ge 920)  { $s.Finestra.Width  = $n } }
            'altezza'   { $n=0; if ([int]::TryParse($v,[ref]$n) -and $n -ge 600)  { $s.Finestra.Height = $n } }
            'divisorio' { $n=0; if ([int]::TryParse($v,[ref]$n) -and $n -ge 300 -and $n -le 900) {
                              $s.Finestra.FindName('ColSinistra').Width = New-Object System.Windows.GridLength($n) } }
            'selezione' {
                foreach ($id in ($v -split ' ')) {
                    if ($id -and $s.Caselle.ContainsKey($id)) { $s.Caselle[$id].IsChecked = $true }
                }
                $s.SelezioneRipristinata = $true
            }
        }
    }
}

function Export-StatoGui {
    $s = $script:Sync
    try {
        $sel = @(Get-SelezioneGui | ForEach-Object { $_.Id }) -join ' '
        $larg = [int]$s.Finestra.FindName('ColSinistra').Width.Value
        @(
            ('larghezza=' + [int]$s.Finestra.Width)
            ('altezza='   + [int]$s.Finestra.Height)
            ('divisorio=' + $larg)
            ('selezione=' + $sel)
        ) | Set-Content -LiteralPath (Get-PercorsoStato) -Encoding UTF8 -ErrorAction Stop
    } catch { }
}

# ------------------------------------------------------------
#   RICERCA NELL'ELENCO
#   Con ventisette operazioni scorrere e' scomodo. Il filtro
#   agisce su nome e descrizione, e nasconde le intestazioni di
#   categoria rimaste senza voci visibili.
# ------------------------------------------------------------
function Update-FiltroGui {
    $s = $script:Sync
    $q = ''
    if ($s.TxtCerca) { $q = ([string]$s.TxtCerca.Text).Trim().ToLower() }
    $s.TxtCercaVuoto.Visibility = $(if ($q) { 'Collapsed' } else { 'Visible' })

    $ultimaIntestazione = $null
    $visibiliNelGruppo  = 0
    foreach ($figlio in $s.PanelTask.Children) {
        if ($figlio -is [System.Windows.Controls.TextBlock]) {
            if ($ultimaIntestazione -and $visibiliNelGruppo -eq 0) {
                $ultimaIntestazione.Visibility = 'Collapsed'
            }
            $ultimaIntestazione = $figlio
            $ultimaIntestazione.Visibility = 'Visible'
            $visibiliNelGruppo = 0
            continue
        }
        $casella = $figlio.Children | Where-Object { $_ -is [System.Windows.Controls.CheckBox] } | Select-Object -First 1
        if (-not $casella) { continue }
        $testo = (([string]$casella.Content) + ' ' + [string]$casella.ToolTip).ToLower()
        if (-not $q -or $testo.Contains($q)) {
            $figlio.Visibility = 'Visible'; $visibiliNelGruppo++
        } else {
            $figlio.Visibility = 'Collapsed'
        }
    }
    if ($ultimaIntestazione -and $visibiliNelGruppo -eq 0) { $ultimaIntestazione.Visibility = 'Collapsed' }
}

# ------------------------------------------------------------
#   RIQUADRO DI SINTESI
#   A fine esecuzione un riquadro colorato dice com'e' andata,
#   senza dover rileggere il testo scorso nel pannello.
# ------------------------------------------------------------
function Show-SintesiGui {
    param([int]$Ok, [int]$Parziali, [int]$Falliti, [long]$Byte)
    $s = $script:Sync
    if ($Falliti -gt 0) {
        $fondo = '#3A1A1A'; $bordo = '#F87171'; $testo = '#F87171'
        $titolo = "$Falliti operazioni non riuscite"
    } elseif ($Parziali -gt 0) {
        $fondo = '#3A2E12'; $bordo = '#D9A441'; $testo = '#D9A441'
        $titolo = "$Parziali operazioni con avvisi"
    } else {
        $fondo = '#14351F'; $bordo = '#1F5C33'; $testo = '#4ADE80'
        $titolo = 'Tutto completato senza errori'
    }
    if ($script:TemaCorrente -eq 'chiaro') {
        if     ($Falliti -gt 0)   { $fondo = '#FDE8E8'; $bordo = '#E06666'; $testo = '#B91C1C' }
        elseif ($Parziali -gt 0)  { $fondo = '#FBF0DA'; $bordo = '#D9A441'; $testo = '#8A5A00' }
        else                      { $fondo = '#DCF5E4'; $bordo = '#7CCF9A'; $testo = '#146B39' }
    }
    $conv = { param($h) New-Object System.Windows.Media.SolidColorBrush(
                        [System.Windows.Media.ColorConverter]::ConvertFromString($h)) }
    $s.PanSintesi.Background  = & $conv $fondo
    $s.PanSintesi.BorderBrush = & $conv $bordo
    $s.TxtSintesiTitolo.Foreground = & $conv $testo
    $s.TxtSintesiDett.Foreground   = & $conv $testo
    $s.TxtSintesiTitolo.Text = $titolo
    $s.TxtSintesiDett.Text = ('{0} completate, {1} con avvisi, {2} fallite   -   {3} liberati' -f `
                              $Ok, $Parziali, $Falliti, (Format-Bytes $Byte))
    $s.PanSintesi.Visibility = 'Visible'
}

# ============================================================
#   OUTPUT
# ============================================================

function Add-SegmentoGui {
    param([string]$Testo = '', [string]$Colore = 'Gray', [bool]$ACapo = $true)
    $s = $script:Sync
    if (-not $s.Paragrafo) {
        $p = New-Object System.Windows.Documents.Paragraph
        $p.Margin = New-Object System.Windows.Thickness(0)
        $p.LineHeight = 16
        $s.Paragrafo = $p
    }
    if ($Testo.Length -gt 0) {
        $run = New-Object System.Windows.Documents.Run($Testo)
        $run.Foreground = New-PennelloConsole $Colore
        $s.Paragrafo.Inlines.Add($run)
    }
    if ($ACapo) {
        if ($s.Paragrafo.Inlines.Count -eq 0) {
            $s.Paragrafo.Inlines.Add((New-Object System.Windows.Documents.Run(' ')))
        }
        $s.RtbOut.Document.Blocks.Add($s.Paragrafo)
        $s.Paragrafo = $null
        # Tetto alla memoria: una sessione lunga produrrebbe altrimenti
        # decine di migliaia di blocchi.
        while ($s.RtbOut.Document.Blocks.Count -gt 5000) {
            $s.RtbOut.Document.Blocks.Remove($s.RtbOut.Document.Blocks.FirstBlock)
        }
    }
}

function Clear-OutputGui { Show-LegendaGui }

# ------------------------------------------------------------
#   Larghezza utile del pannello, in caratteri, e larghezza del
#   documento. Vanno calcolate insieme: e' su PageWidth che WPF
#   manda a capo, quindi e' da li' che si ricava quanti
#   caratteri ci stanno.
#
#   Il passo del carattere NON e' semplicemente 0.55 volte il
#   corpo del font. Con TextFormattingMode="Display" WPF
#   arrotonda l'avanzamento dei glifi al pixel del dispositivo:
#   su un monitor al 125% il valore teorico sbaglia di quasi il
#   10 per cento e il testo va a capo prima del previsto.
#   Si replica quindi lo stesso arrotondamento.
# ------------------------------------------------------------
function Get-LarghezzaCaratteri {
    $s = $script:Sync

    $largh = 0
    try { $largh = [double]$s.RtbOut.ActualWidth } catch { }
    if ($largh -lt 200) { $largh = 760 }

    # 44 punti lasciati a padding interno e barra di scorrimento.
    # Il minimo di 520 e' quanto serve alla tabella del riepilogo
    # (72 caratteri) per restare allineata. La colonna destra ha
    # MinWidth 570 proprio perche' questo minimo non venga mai
    # superato: cosi' non compare mai lo scorrimento orizzontale.
    $pw = [math]::Max(520, $largh - 44)
    try { $s.RtbOut.Document.PageWidth = $pw } catch { }

    $scala = 1.0
    try {
        $sorgente = [System.Windows.PresentationSource]::FromVisual($s.Finestra)
        if ($sorgente) { $scala = [double]$sorgente.CompositionTarget.TransformToDevice.M11 }
    } catch { }
    if ($scala -le 0) { $scala = 1.0 }

    $corpo = 12.5
    try { $corpo = [double]$s.RtbOut.FontSize } catch { }
    # 0.5498 = avanzamento di Consolas in em (1126/2048)
    $avanzoDispositivo = [math]::Round($corpo * $scala * 0.5498)
    if ($avanzoDispositivo -lt 1) { $avanzoDispositivo = 1 }
    $passo = $avanzoDispositivo / $scala

    $n = [math]::Floor($pw / $passo) - 2
    if ($n -lt 44)  { $n = 44 }
    if ($n -gt 160) { $n = 160 }
    return [int]$n
}

# Paragrafo di testo scorrevole, mandato a capo alla larghezza attuale.
function Add-ParagrafoGui {
    param([string]$Testo, [string]$Colore = 'Gray', [int]$Rientro = 2, [int]$Larghezza = 76)
    foreach ($r in (Split-TextWidth -Testo $Testo -Larghezza ($Larghezza - $Rientro))) {
        Add-SegmentoGui -Testo ((' ' * $Rientro) + $r) -Colore $Colore
    }
}

# Voce con etichetta colorata a sinistra e testo allineato sotto
# di essa (rientro sporgente).
function Add-VoceGui {
    param([string]$Etichetta, [string]$ColoreEtichetta, [string]$Testo, [int]$Larghezza = 76)
    $rientro = $Etichetta.Length + 3
    $righe = @(Split-TextWidth -Testo $Testo -Larghezza ($Larghezza - $rientro))
    Add-SegmentoGui -Testo ('  ' + $Etichetta + ' ') -Colore $ColoreEtichetta -ACapo $false
    Add-SegmentoGui -Testo $righe[0] -Colore 'Gray'
    for ($i = 1; $i -lt $righe.Count; $i++) {
        Add-SegmentoGui -Testo ((' ' * $rientro) + $righe[$i]) -Colore 'Gray'
    }
}

function Get-BadgeGui {
    param($Task)
    if ($Task.ContainsKey('Sconsigliato') -and $Task.Sconsigliato) {
        return @{ Testo = '[SCONSIG.]'; Colore = 'Red' }
    }
    switch ($Task.Livello) {
        'Avanzato' { return @{ Testo = '[avanzato]'; Colore = 'DarkYellow' } }
        'Riavvio'  { return @{ Testo = '[riavvio] '; Colore = 'Magenta' } }
        default    { return @{ Testo = '[sicuro]  '; Colore = 'DarkGray' } }
    }
}

# ------------------------------------------------------------
#   Schermata iniziale: spiega etichette, analisi, punto di
#   ripristino e tempi. Tutto il testo viene mandato a capo
#   alla larghezza attuale del pannello, quindi si riadatta
#   quando si sposta il divisorio o si ridimensiona la finestra.
# ------------------------------------------------------------
function Show-LegendaGui {
    $s = $script:Sync
    $s.RtbOut.Document.Blocks.Clear()
    $s.Paragrafo = $null

    $L = Get-LarghezzaCaratteri
    $s.LarghezzaLegenda = $L
    $s.SoloLegenda = $true

    $titolo = {
        param($T)
        Add-SegmentoGui -Testo ''
        Add-SegmentoGui -Testo ('  ' + $T) -Colore 'Cyan'
        Add-SegmentoGui -Testo ''
    }

    & $titolo 'COSA SIGNIFICANO LE ETICHETTE'
    Add-VoceGui '[sicuro]  ' 'DarkGray' 'Cancella solo file che Windows ricrea da solo. Nessun rischio, si puo'' eseguire quando si vuole.' $L
    Add-VoceGui '[avanzato]' 'DarkYellow' 'Ha effetti collaterali: chiude Esplora risorse, ferma servizi o dura decine di minuti. Chiede sempre conferma.' $L
    Add-VoceGui '[riavvio] ' 'Magenta' 'Ha effetto solo dopo aver riavviato il PC. Azzera IP statici e componenti lasciati da VPN e antivirus: serve a riparare una rete rotta, non come manutenzione periodica.' $L
    Add-VoceGui '[SCONSIG.]' 'Red' 'Sconsigliato: cancellare il Prefetch RALLENTA i primi avvii finche'' Windows non lo ricostruisce, e recupera pochi MB. C''e'' solo per completezza.' $L

    & $titolo 'LE DUE ANALISI'
    Add-VoceGui 'Rapida  ' 'White' 'Circa 20 secondi: sistema, supporto di Windows, dischi, RAM, processi, servizi, sicurezza, batteria.' $L
    Add-VoceGui 'Completa' 'White' 'Circa un minuto: tutto quanto sopra, piu'' alimentazione, salute SMART del disco, test di connettivita'', aggiornamenti Windows, protezione sistema, driver difettosi, manutenzione automatica, spazio recuperabile, programmi all''avvio ed errori recenti di sistema e disco.' $L
    Add-SegmentoGui -Testo ''
    Add-ParagrafoGui 'Le analisi non modificano nulla: leggono soltanto.' 'Green' 2 $L
    Add-ParagrafoGui 'Segnalano i problemi ma non li correggono: la riparazione resta una tua decisione.' 'DarkGray' 2 $L

    & $titolo 'PUNTO DI RIPRISTINO'
    Add-ParagrafoGui 'Serve solo se stai per toccare servizi, la rete o componenti di Windows, cioe'' con le voci [avanzato] e [riavvio]. Per la sola pulizia di file temporanei non protegge da niente e costa tempo e spazio su disco.' 'Gray' 2 $L
    Add-ParagrafoGui 'Sotto la lista trovi il consiglio aggiornato in base a cio'' che hai selezionato.' 'Gray' 2 $L

    & $titolo 'TEMPI'
    Add-ParagrafoGui 'Il tempo stimato compare sotto la lista e cambia con la selezione. Premi un pulsante di selezione rapida, oppure "Dettagli", per vedere qui l''elenco delle operazioni con descrizione e tempo di ciascuna.' 'Gray' 2 $L
    Add-ParagrafoGui 'Sono stime prudenti: DISM e SFC dipendono dallo stato del disco e possono variare parecchio.' 'DarkGray' 2 $L

    & $titolo 'MODALITA'' SIMULAZIONE'
    Add-ParagrafoGui 'Con la spunta in alto a destra il giro viene fatto per intero ma senza toccare niente: vedi quanto spazio libereresti e cosa succederebbe. Utile per guardare prima di agire.' 'Gray' 2 $L
    Add-SegmentoGui -Testo ''
}

# ------------------------------------------------------------
#   Dettaglio di cio' che e' selezionato: intestazione con il
#   totale, poi ogni voce con etichetta, tempo e descrizione.
# ------------------------------------------------------------
function Show-DettagliSelezioneGui {
    param(
        [string]$Titolo = 'Selezione corrente',
        [string]$Descrizione = ''
    )

    $s = $script:Sync
    $s.SoloLegenda = $false
    $L = Get-LarghezzaCaratteri
    $scelti = @(Get-SelezioneGui)

    Add-SegmentoGui -Testo ''
    Add-SegmentoGui -Testo ('  ' + ('=' * ($L - 2))) -Colore 'Cyan'

    if ($scelti.Count -eq 0) {
        Add-SegmentoGui -Testo ('  ' + $Titolo.ToUpper()) -Colore 'Cyan'
        Add-SegmentoGui -Testo ('  ' + ('=' * ($L - 2))) -Colore 'Cyan'
        Add-SegmentoGui -Testo ''
        Add-ParagrafoGui 'Nessuna operazione selezionata.' 'DarkGray' 2 $L
        Add-SegmentoGui -Testo ''
        return
    }

    $secondi = Get-StimaTotale -Tasks $scelti
    $conRipristino = [bool]$s.ChkRipristino.IsChecked
    if ($conRipristino) { $secondi += (Get-Task -Id 'maint_restorepoint').Stima }

    $coda = '{0} operazioni  -  tempo stimato: {1}' -f $scelti.Count, (Format-Stima $secondi)
    $spazio = $L - 2 - $Titolo.Length - $coda.Length
    Add-SegmentoGui -Testo ('  ' + $Titolo.ToUpper()) -Colore 'Cyan' -ACapo:($spazio -lt 2)
    if ($spazio -ge 2) {
        Add-SegmentoGui -Testo ((' ' * $spazio) + $coda) -Colore 'White'
    } else {
        Add-SegmentoGui -Testo ('  ' + $coda) -Colore 'White'
    }
    Add-SegmentoGui -Testo ('  ' + ('=' * ($L - 2))) -Colore 'Cyan'

    if ($Descrizione) {
        Add-SegmentoGui -Testo ''
        Add-ParagrafoGui $Descrizione 'White' 2 $L
    }
    Add-SegmentoGui -Testo ''

    $rientro = 13
    foreach ($t in $scelti) {
        $b = Get-BadgeGui -Task $t
        $tempo = Format-Stima $t.Stima
        $sp = $L - 2 - $b.Testo.Length - 1 - $t.Nome.Length - $tempo.Length
        if ($sp -lt 2) { $sp = 2 }

        Add-SegmentoGui -Testo ('  ' + $b.Testo + ' ') -Colore $b.Colore -ACapo $false
        Add-SegmentoGui -Testo $t.Nome -Colore 'White' -ACapo $false
        Add-SegmentoGui -Testo ((' ' * $sp) + $tempo) -Colore 'DarkGray'
        foreach ($r in (Split-TextWidth -Testo $t.Descrizione -Larghezza ($L - $rientro))) {
            Add-SegmentoGui -Testo ((' ' * $rientro) + $r) -Colore 'Gray'
        }
        Add-SegmentoGui -Testo ''
    }

    Add-SegmentoGui -Testo ('  ' + ('-' * ($L - 2))) -Colore 'DarkGray'
    $consiglio = Get-ConsiglioRipristino -Tasks $scelti
    if ($conRipristino) {
        Add-ParagrafoGui ('Punto di ripristino: attivo, gia'' compreso nel totale.') 'Green' 2 $L
    } elseif ($consiglio.Consigliato) {
        Add-ParagrafoGui ('Punto di ripristino: consigliato, ' + $consiglio.Motivo + '.') 'DarkYellow' 2 $L
    } else {
        Add-ParagrafoGui ('Punto di ripristino: non necessario, ' + $consiglio.Motivo + '.') 'DarkGray' 2 $L
    }
    if ($s.ChkSimula.IsChecked) {
        Add-ParagrafoGui 'Simulazione attiva: niente verra'' modificato.' 'Magenta' 2 $L
    }
    Add-SegmentoGui -Testo ''
}

function Set-StatoGui {
    param([string]$Testo)
    $script:Sync.TxtStato.Text = $Testo
}

# Svuota la coda sul thread della UI. Chiamata dal DispatcherTimer.
function Update-OutputGui {
    $s = $script:Sync
    if (-not $s) { return }
    $lavorati = 0
    while ($s.Coda.Count -gt 0 -and $lavorati -lt 600) {
        $m = $s.Coda.Dequeue()
        $lavorati++
        switch ($m.Tipo) {
            'seg'   { Add-SegmentoGui -Testo $m.Testo -Colore $m.Colore -ACapo $m.ACapo }
            'prog'  {
                $s.Barra.Maximum = $m.Max
                $s.Barra.Value   = $m.Valore
                # Tempo rimanente dalle stime delle operazioni che
                # restano: la barra da sola dice a che punto siamo,
                # non quanto manca.
                $resta = ''
                if ($s.StimeCoda -and $m.Valore -le $s.StimeCoda.Count) {
                    $sec = 0
                    for ($i = $m.Valore - 1; $i -lt $s.StimeCoda.Count; $i++) { $sec += $s.StimeCoda[$i] }
                    if ($sec -gt 0) { $resta = '   -   restano ' + (Format-Stima $sec) }
                }
                Set-StatoGui ('{0}/{1}  {2}{3}' -f $m.Valore, $m.Max, $m.Stato, $resta)
            }
            'esiti' {
                $s.RebootRichiesto = [bool]$m.Reboot
                Show-SintesiGui -Ok $m.Ok -Parziali $m.Parziali -Falliti $m.Falliti -Byte $m.Byte
            }
            'fine'  { $s.Finito = $true }
        }
    }
    if ($lavorati -gt 0) { $s.RtbOut.ScrollToEnd() }
    if ($s.Finito -and $s.Coda.Count -eq 0 -and $s.InCorso) { Complete-LavoroGui }
}

# ============================================================
#   ESECUZIONE
# ============================================================

function Start-LavoroGui {
    param([string]$Modo, [string[]]$Ids = @(), [switch]$Rapida)

    $s = $script:Sync
    if ($s.InCorso) { return }

    $s.InCorso         = $true
    $s.Annulla         = $false
    $s.Finito          = $false
    $s.RebootRichiesto = $false
    $s.SoloLegenda     = $false   # da qui in poi il pannello non e' piu' solo legenda

    $s.BtnEsegui.IsEnabled        = $false
    $s.BtnAnalisi.IsEnabled       = $false
    $s.BtnAnalisiRapida.IsEnabled = $false
    $s.BtnPulisciOut.IsEnabled    = $false
    $s.BtnInterrompi.IsEnabled    = $true

    $s.StimeCoda = @()
    if ($Modo -ne 'analisi') {
        foreach ($id in $Ids) { $s.StimeCoda += [int](Get-Task -Id $id).Stima }
    }

    if ($Modo -eq 'analisi') {
        $s.Barra.IsIndeterminate = $true
        Set-StatoGui 'Raccolta dati in corso...'
    } else {
        $s.Barra.IsIndeterminate = $false
        $s.Barra.Minimum = 0
        $s.Barra.Maximum = [math]::Max(1, $Ids.Count)
        $s.Barra.Value   = 0
        Set-StatoGui 'Avvio...'
    }

    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'MTA'
    $rs.ThreadOptions  = 'ReuseThread'
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('sync',    $s)
    $rs.SessionStateProxy.SetVariable('radice',  $s.Radice)
    $rs.SessionStateProxy.SetVariable('logPath', $s.LogPath)
    # Lo storico e la configurazione vivono nel processo principale:
    # senza passarli, nel runspace resterebbero vuoti e il confronto
    # con l'esecuzione precedente non verrebbe mai scritto.
    $rs.SessionStateProxy.SetVariable('storicoPath', (Join-Path $s.Radice 'logs\storico.txt'))
    $rs.SessionStateProxy.SetVariable('configPath',  (Join-Path $s.Radice 'Toolbox.conf'))
    $rs.SessionStateProxy.SetVariable('modo',    $Modo)
    $rs.SessionStateProxy.SetVariable('taskIds', [string[]]$Ids)
    $rs.SessionStateProxy.SetVariable('dryRun',  [bool]$s.ChkSimula.IsChecked)
    $rs.SessionStateProxy.SetVariable('rapida',  [bool]$Rapida)

    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($script:CodiceWorker)

    $s.Ps       = $ps
    $s.Runspace = $rs
    $s.Handle   = $ps.BeginInvoke()
}

function Complete-LavoroGui {
    $s = $script:Sync
    try { if ($s.Ps -and $s.Handle) { $s.Ps.EndInvoke($s.Handle) | Out-Null } } catch { }
    try { if ($s.Ps) { $s.Ps.Dispose() } } catch { }
    try { if ($s.Runspace) { $s.Runspace.Close(); $s.Runspace.Dispose() } } catch { }
    $s.Ps = $null; $s.Runspace = $null; $s.Handle = $null
    $s.InCorso = $false

    $s.Barra.IsIndeterminate = $false
    $s.Barra.Value = $s.Barra.Maximum

    $s.BtnEsegui.IsEnabled        = $true
    $s.BtnAnalisi.IsEnabled       = $true
    $s.BtnAnalisiRapida.IsEnabled = $true
    $s.BtnPulisciOut.IsEnabled    = $true
    $s.BtnInterrompi.IsEnabled    = $false
    Set-StatoGui 'Completato'

    if ($s.RebootRichiesto -and -not $s.ChkSimula.IsChecked) {
        $testo = "Alcune modifiche diventano effettive solo dopo il riavvio del computer." + [Environment]::NewLine + [Environment]::NewLine +
                 "Riavviare adesso? Il riavvio partira' fra 60 secondi e si puo' annullare digitando  shutdown /a  in un prompt."
        $r = [System.Windows.MessageBox]::Show($s.Finestra, $testo, 'Riavvio necessario',
                 [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
        if ($r -eq [System.Windows.MessageBoxResult]::Yes) {
            Write-Log 'Riavvio avviato dalla GUI' 'INFO'
            Start-Process 'shutdown.exe' -ArgumentList '/r','/t','60','/c','Riavvio richiesto da System Toolbox.' -WindowStyle Hidden
        } else {
            Write-Log 'Riavvio rimandato dall utente (GUI)' 'INFO'
        }
    }
}

# ============================================================
#   COSTRUZIONE DELLA FINESTRA
# ============================================================

function Start-Gui {
    param(
        [Parameter(Mandatory=$true)][string]$Radice,
        [Parameter(Mandatory=$true)][string]$LogPath,
        [switch]$DryRun
    )

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml -ErrorAction Stop

    $script:TemaCorrente = Get-TemaWindows
    $xamlTema  = Expand-Palette $script:Xaml (Get-Palette $script:TemaCorrente)
    $lettore   = New-Object System.Xml.XmlNodeReader ([xml]$xamlTema)
    $finestra  = [Windows.Markup.XamlReader]::Load($lettore)

    Initialize-GdiApi
    # Il logo vero, se c'e' accanto allo strumento; altrimenti
    # quello disegnato da codice, cosi' la finestra ha sempre
    # un'icona anche se il file viene perso in una copia.
    $icona = $null
    $fileIcona = Join-Path $Radice 'icona.ico'
    if (Test-Path -LiteralPath $fileIcona -ErrorAction SilentlyContinue) {
        try { $icona = [System.Windows.Media.Imaging.BitmapFrame]::Create([Uri]$fileIcona) } catch { $icona = $null }
    }
    if (-not $icona) { $icona = New-IconaFinestra }
    if ($icona) { $finestra.Icon = $icona }

    $s = [hashtable]::Synchronized(@{})
    $s.Coda            = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue))
    $s.Annulla         = $false
    $s.InCorso         = $false
    $s.Finito          = $false
    $s.RebootRichiesto = $false
    $s.Paragrafo       = $null
    $s.Radice          = $Radice
    $s.LogPath         = $LogPath
    $s.Finestra        = $finestra
    $s.Caselle         = @{}
    $s.Ps = $null; $s.Runspace = $null; $s.Handle = $null

    foreach ($nome in @('TxtSottotitolo','TxtAdmin','ChipAdmin','ChkSimula','PanelPreset','PanelTask',
                        'ChkRipristino','TxtRipristino','TxtConteggio','RtbOut','Barra','TxtStato','BtnPulisciOut',
                        'BtnLog','BtnAnalisiRapida','BtnAnalisi','BtnInterrompi','BtnEsegui',
                        'TxtCerca','TxtCercaVuoto','BtnReport','PanSintesi','TxtSintesiTitolo','TxtSintesiDett')) {
        $s[$nome] = $finestra.FindName($nome)
    }
    $script:Sync = $s

    # Niente ritorno a capo automatico sotto i 660 punti: le tabelle a
    # larghezza fissa prodotte da ConsoleUI.ps1 resterebbero allineate
    # male. Sopra quella soglia il documento segue il pannello, cosi'
    # non compare mai una barra di scorrimento orizzontale inutile.
    $s.RtbOut.Document.PageWidth   = 660
    $s.RtbOut.Document.PagePadding = New-Object System.Windows.Thickness(0)
    $s.LarghezzaLegenda = 0
    $s.SoloLegenda      = $false

    # Ridimensionando la finestra o spostando il divisorio, il testo
    # discorsivo va rimandato a capo alla nuova larghezza. Si rigenera
    # solo la legenda, e solo se i caratteri utili sono davvero
    # cambiati: durante il trascinamento l'evento scatta di continuo.
    $s.RtbOut.Add_SizeChanged({
        $s2 = $script:Sync
        # Get-LarghezzaCaratteri aggiorna anche PageWidth.
        if ((Get-LarghezzaCaratteri) -ne $s2.LarghezzaLegenda -and $s2.SoloLegenda) {
            Show-LegendaGui
        }
    })

    $s.TxtSottotitolo.Text = 'Pulizia, analisi e manutenzione   -   log in ' + (Split-Path $LogPath -Leaf)
    $s.ChkSimula.IsChecked = [bool]$DryRun

    if (-not (Test-Admin)) {
        $s.TxtAdmin.Text        = 'Privilegi limitati'
        $s.TxtAdmin.Foreground  = New-PennelloConsole 'Yellow'
        $s.ChipAdmin.Background = (New-Object System.Windows.Media.SolidColorBrush(
                                      [System.Windows.Media.ColorConverter]::ConvertFromString('#3A2E12')))
    }

    # ---------- elenco delle operazioni ----------
    $badge = @{
        'Sicuro'   = @{ Testo = '[sicuro]  '; Colore = 'DarkGray' }
        'Avanzato' = @{ Testo = '[avanzato]'; Colore = 'DarkYellow' }
        'Riavvio'  = @{ Testo = '[riavvio] '; Colore = 'Magenta' }
    }

    foreach ($categoria in @('Pulizia','Rete','Manutenzione')) {
        $intestazione = New-Object System.Windows.Controls.TextBlock
        $intestazione.Text       = $categoria.ToUpper()
        $intestazione.Foreground = New-PennelloConsole 'DarkGray'
        $intestazione.FontSize   = 10.5
        $intestazione.FontWeight = 'SemiBold'
        $intestazione.Margin     = New-Object System.Windows.Thickness(0, 14, 0, 6)
        $s.PanelTask.Children.Add($intestazione) | Out-Null

        foreach ($t in (Get-TaskByCategory -Categoria $categoria)) {
            $riga = New-Object System.Windows.Controls.StackPanel
            $riga.Orientation = 'Horizontal'

            $etichetta = New-Object System.Windows.Controls.TextBlock
            $b = $badge[$t.Livello]
            if ($t.ContainsKey('Sconsigliato') -and $t.Sconsigliato) {
                $b = @{ Testo = '[SCONSIG.]'; Colore = 'Red' }
            }
            $etichetta.Text              = $b.Testo
            $etichetta.Foreground        = New-PennelloConsole $b.Colore
            $etichetta.FontFamily        = 'Consolas'
            $etichetta.FontSize          = 11.5
            $etichetta.Width             = 74
            $etichetta.VerticalAlignment = 'Center'
            $riga.Children.Add($etichetta) | Out-Null

            $casella = New-Object System.Windows.Controls.CheckBox
            $casella.Content = $t.Nome
            $casella.Tag     = $t.Id
            $casella.ToolTip = $t.Descrizione + '  (tempo stimato: ' + (Format-Stima $t.Stima) + ')'
            $casella.Add_Checked({   Update-ConteggioGui })
            $casella.Add_Unchecked({ Update-ConteggioGui })
            $riga.Children.Add($casella) | Out-Null

            # Doppio clic sulla riga: esegue solo quell'operazione,
            # senza toccare il resto della selezione.
            $riga.Tag = $t.Id
            $riga.Background = [System.Windows.Media.Brushes]::Transparent
            $riga.Add_MouseLeftButtonDown({
                param($mittente, $evento)
                if ($evento.ClickCount -ge 2) { Invoke-SingolaGui ([string]$mittente.Tag) }
            })
            $riga.ToolTip = 'Doppio clic per eseguire solo questa operazione'

            $s.PanelTask.Children.Add($riga) | Out-Null
            $s.Caselle[$t.Id] = $casella
        }
    }

    # ---------- pulsanti di selezione rapida ----------
    $preset = @(
        @{ Testo = 'Consigliata';      Nome = 'Consigliata'
           Desc = 'Manutenzione di routine: libera spazio e rinfresca la rete, senza effetti collaterali. E'' quella da usare di norma, ogni una o due settimane.' },
        @{ Testo = 'Pulizia sicura';   Nome = 'PuliziaSicura'
           Desc = 'Solo file temporanei, cestino e cache che Windows ricrea da solo. Si puo'' eseguire in qualsiasi momento, anche mentre lavori.' },
        @{ Testo = 'Pulizia avanzata'; Nome = 'PuliziaAvanzata'
           Desc = 'Recupera molto piu'' spazio, ma riavvia Esplora risorse, ferma i servizi di aggiornamento e compatta l''archivio componenti. Chiudi i browser prima di avviarla.' },
        @{ Testo = 'Rete leggera';     Nome = 'RetePulizia'
           Desc = 'Rinfresca DNS, cache ARP e indirizzo IP senza riavviare il PC. E'' il primo tentativo da fare quando la rete fa i capricci.' },
        @{ Testo = 'Rete reset';       Nome = 'ReteReset'
           Desc = 'Riscrive Winsock e gli stack TCP/IP e IPv6. Serve a riparare una rete che non funziona piu'', non come manutenzione: azzera IP statici e componenti di VPN e antivirus, e richiede il riavvio.' },
        @{ Testo = 'Manutenzione';     Nome = 'Manutenzione'
           Desc = 'Controlla e ripara i file di sistema di Windows con SFC e DISM. Operazione lunga da avviare quando non ti serve il PC, utile se vedi errori o crash ricorrenti.' },
        @{ Testo = 'Nessuna';          Nome = 'Nessuna'; Desc = '' },
        @{ Testo = 'Dettagli';         Nome = '__dettagli'; Desc = '' }
    )
    $s.PresetDesc = @{}
    foreach ($p in $preset) { $s.PresetDesc[$p.Nome] = $p.Desc }
    foreach ($p in $preset) {
        $pulsante = New-Object System.Windows.Controls.Button
        $pulsante.Content = $p.Testo
        $pulsante.Tag     = $p.Nome
        $pulsante.Style   = $finestra.FindResource('Piccolo')
        if ($p.Nome -eq '__dettagli') {
            $pulsante.ToolTip = 'Mostra a destra l''elenco di cio'' che hai selezionato, con descrizione e tempo di ogni voce'
        } elseif ($p.Nome -eq 'Nessuna') {
            $pulsante.ToolTip = 'Toglie tutte le spunte'
        } else {
            $insieme = @()
            if ($p.Nome -eq 'Consigliata') {
                $insieme = @(Get-TaskSet -Nome 'PuliziaSicura') + @(Get-TaskSet -Nome 'RetePulizia')
            } else {
                $insieme = @(Get-TaskSet -Nome $p.Nome)
            }
            $pulsante.ToolTip = '{0}{1}{2} operazioni  -  tempo stimato: {3}' -f `
                                $p.Desc, [Environment]::NewLine,
                                @($insieme).Count, (Format-Stima (Get-StimaTotale -Tasks $insieme))
        }
        $pulsante.Add_Click({
            param($mittente, $evento)
            $nome = [string]$mittente.Tag
            $desc = ''
            if ($script:Sync.PresetDesc.ContainsKey($nome)) { $desc = [string]$script:Sync.PresetDesc[$nome] }
            if ($nome -eq '__dettagli') {
                Show-DettagliSelezioneGui -Titolo 'Selezione corrente'
            } else {
                Select-PresetGui -Nome $nome
                Show-DettagliSelezioneGui -Titolo ([string]$mittente.Content) -Descrizione $desc
            }
            $script:Sync.RtbOut.ScrollToEnd()
        })
        $s.PanelPreset.Children.Add($pulsante) | Out-Null
    }

    # ---------- pulsanti principali ----------
    $s.BtnAnalisi.Add_Click({       Start-LavoroGui -Modo 'analisi' })
    $s.BtnAnalisiRapida.Add_Click({ Start-LavoroGui -Modo 'analisi' -Rapida })
    $s.BtnEsegui.Add_Click({        Invoke-EsecuzioneGui })
    $s.BtnPulisciOut.Add_Click({    Clear-OutputGui })
    $s.BtnInterrompi.Add_Click({
        $script:Sync.Annulla = $true
        $script:Sync.BtnInterrompi.IsEnabled = $false
        Set-StatoGui 'Interruzione dopo l''operazione in corso...'
    })
    $s.BtnLog.Add_Click({
        $cartella = Split-Path $script:Sync.LogPath -Parent
        if (Test-Path -LiteralPath $cartella) { Start-Process explorer.exe $cartella }
    })

    $s.ChkSimula.Add_Checked({      Update-ConteggioGui })
    $s.ChkSimula.Add_Unchecked({    Update-ConteggioGui })
    $s.ChkRipristino.Add_Checked({  Update-ConteggioGui })
    $s.ChkRipristino.Add_Unchecked({ Update-ConteggioGui })
    $s.TxtCerca.Add_TextChanged({   Update-FiltroGui })
    $s.BtnReport.Add_Click({        Export-ReportGui })

    # ---------- timer di svuotamento coda ----------
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [timespan]::FromMilliseconds(80)
    $timer.Add_Tick({ Update-OutputGui })
    $s.Timer = $timer

    $finestra.Add_Loaded({
        $script:Sync.Timer.Start()
        Import-StatoGui
        Update-FiltroGui
        Show-LegendaGui
        Update-ConteggioGui
    })

    $finestra.Add_Closing({
        param($mittente, $evento)
        $s2 = $script:Sync
        if ($s2.InCorso) {
            $r = [System.Windows.MessageBox]::Show($s2.Finestra,
                 'Un''operazione e'' ancora in corso. Chiudere comunque?', 'Operazione in corso',
                 [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
            if ($r -ne [System.Windows.MessageBoxResult]::Yes) { $evento.Cancel = $true; return }
            $s2.Annulla = $true
            try { if ($s2.Ps) { $s2.Ps.Stop() } } catch { }
        }
        try { $s2.Timer.Stop() } catch { }
        Export-StatoGui
        Write-Log 'Finestra chiusa' 'INFO'
    })

    # La selezione predefinita si applica solo se non ce n'e' una
    # salvata dalla sessione precedente: sovrascriverla sarebbe
    # esattamente il contrario di ricordarla.
    if (-not (Test-Path -LiteralPath (Get-PercorsoStato) -ErrorAction SilentlyContinue)) {
        Select-PresetGui -Nome 'Consigliata'
    }

    # La console di appoggio viene nascosta solo qui, un istante prima
    # di mostrare la finestra: se qualcosa fosse fallito prima, l'errore
    # resta visibile. Se ShowDialog stesso fallisce, e' il chiamante a
    # rimettere la console in primo piano (vedi Toolbox.ps1).
    Hide-ConsoleWindow
    $finestra.ShowDialog() | Out-Null
}

# ------------------------------------------------------------
#   Esportazione del report dalla finestra
#   Il buffer viene riempito dalle stesse funzioni che disegnano,
#   quindi qui basta scegliere dove scrivere.
# ------------------------------------------------------------
function Export-ReportGui {
    $s = $script:Sync
    if ($script:TB_REPBUF.Count -eq 0) {
        [System.Windows.MessageBox]::Show($s.Finestra,
            'Non c''e'' ancora niente da esportare: esegui prima un''analisi o una pulizia.',
            'Report vuoto', [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Information) | Out-Null
        return
    }
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Filter = 'Pagina HTML (*.html)|*.html|Testo Markdown (*.md)|*.md'
    $dlg.FileName = ('toolbox_{0}.html' -f (Get-Date -Format 'yyyy-MM-dd_HH-mm'))
    $dlg.InitialDirectory = (Join-Path $s.Radice 'logs')
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

    $precedente = $script:TB_REPORT
    $script:TB_REPORT = $dlg.FileName
    Export-Report
    $script:TB_REPORT = $precedente

    if (Test-Path -LiteralPath $dlg.FileName) {
        if ([System.Windows.MessageBox]::Show($s.Finestra,
                ('Report salvato in:' + [Environment]::NewLine + $dlg.FileName + [Environment]::NewLine + [Environment]::NewLine + 'Aprirlo adesso?'),
                'Report esportato', [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Information) -eq [System.Windows.MessageBoxResult]::Yes) {
            Start-Process $dlg.FileName
        }
    } else {
        [System.Windows.MessageBox]::Show($s.Finestra, 'Scrittura non riuscita.', 'Errore',
            [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
    }
}

# ------------------------------------------------------------
#   Esecuzione di una singola operazione (doppio clic)
# ------------------------------------------------------------
function Invoke-SingolaGui {
    param([string]$Id)
    $s = $script:Sync
    if ($s.InCorso -or -not $Id) { return }
    $t = Get-Task -Id $Id
    if (-not $t) { return }

    $testo = ('Eseguire solo questa operazione?' + [Environment]::NewLine + [Environment]::NewLine +
              $t.Nome + [Environment]::NewLine + [Environment]::NewLine +
              $t.Descrizione + [Environment]::NewLine + [Environment]::NewLine +
              'Tempo stimato: ' + (Format-Stima $t.Stima))
    $icona = [System.Windows.MessageBoxImage]::Question
    if ($t.Livello -ne 'Sicuro' -and -not $s.ChkSimula.IsChecked) {
        $icona = [System.Windows.MessageBoxImage]::Warning
    }
    if ([System.Windows.MessageBox]::Show($s.Finestra, $testo, 'Operazione singola',
            [System.Windows.MessageBoxButton]::YesNo, $icona) -ne [System.Windows.MessageBoxResult]::Yes) { return }

    Start-LavoroGui -Modo 'task' -Ids @($Id)
}

# ------------------------------------------------------------
#   Selezione e conteggio
# ------------------------------------------------------------
function Select-PresetGui {
    param([string]$Nome)
    $s = $script:Sync

    $ids = @()
    if ($Nome -eq 'Consigliata') {
        $ids = @(Get-TaskSet -Nome 'PuliziaSicura') + @(Get-TaskSet -Nome 'RetePulizia') | ForEach-Object { $_.Id }
    } elseif ($Nome -ne 'Nessuna') {
        $ids = @(Get-TaskSet -Nome $Nome | ForEach-Object { $_.Id })
    }

    foreach ($chiave in @($s.Caselle.Keys)) {
        $s.Caselle[$chiave].IsChecked = ($ids -contains $chiave)
    }
    Update-ConteggioGui
}

function Get-SelezioneGui {
    $s = $script:Sync
    $scelti = @()
    # L'ordine del registro conta: la pulizia va fatta prima della rete.
    foreach ($t in (Get-AllTask)) {
        if ($s.Caselle.ContainsKey($t.Id) -and $s.Caselle[$t.Id].IsChecked) { $scelti += $t }
    }
    return $scelti
}

function Update-ConteggioGui {
    $s = $script:Sync
    if (-not $s -or -not $s.TxtConteggio) { return }
    $scelti = @(Get-SelezioneGui)

    # --- punto di ripristino: una riga sola, evidenziata solo quando
    #     serve davvero o quando e' stato attivato. Il perche' esteso
    #     sta nel riepilogo a destra, qui non va ripetuto. ---
    $consiglio = Get-ConsiglioRipristino -Tasks $scelti
    $costo     = Format-Stima ((Get-Task -Id 'maint_restorepoint').Stima)
    $attivo    = [bool]$s.ChkRipristino.IsChecked

    if ($scelti.Count -eq 0) {
        $s.TxtRipristino.Text       = ''
        $s.ChkRipristino.Foreground = New-PennelloConsole 'Gray'
        $s.ChkRipristino.FontWeight = [System.Windows.FontWeights]::Normal
    } elseif ($attivo) {
        $s.TxtRipristino.Text       = 'Incluso nel totale: +' + $costo
        $s.TxtRipristino.Foreground = New-PennelloConsole 'Green'
        $s.ChkRipristino.Foreground = New-PennelloConsole 'Green'
        $s.ChkRipristino.FontWeight = [System.Windows.FontWeights]::Normal
    } elseif ($consiglio.Consigliato) {
        $s.TxtRipristino.Text       = 'Consigliato per questa selezione   (+' + $costo + ')'
        $s.TxtRipristino.Foreground = New-PennelloConsole 'DarkYellow'
        $s.ChkRipristino.Foreground = New-PennelloConsole 'DarkYellow'
        $s.ChkRipristino.FontWeight = [System.Windows.FontWeights]::SemiBold
    } else {
        $s.TxtRipristino.Text       = 'Non serve per questa selezione'
        $s.TxtRipristino.Foreground = New-PennelloConsole 'DarkGray'
        $s.ChkRipristino.Foreground = New-PennelloConsole 'Gray'
        $s.ChkRipristino.FontWeight = [System.Windows.FontWeights]::Normal
    }

    # --- conteggio e tempo stimato ---
    if ($scelti.Count -eq 0) {
        $s.TxtConteggio.Text = 'Nessuna operazione selezionata.'
        return
    }

    $secondi = Get-StimaTotale -Tasks $scelti
    if ($s.ChkRipristino.IsChecked) { $secondi += (Get-Task -Id 'maint_restorepoint').Stima }

    $testo = '{0} operazioni  -  tempo stimato: {1}' -f $scelti.Count, (Format-Stima $secondi)
    $riavvio = @($scelti | Where-Object { $_.Livello -eq 'Riavvio' }).Count
    if ($riavvio -gt 0) { $testo += ('   ({0} richiedono il riavvio del PC)' -f $riavvio) }
    if ($s.ChkSimula.IsChecked) { $testo += '   -   simulazione attiva' }
    $s.TxtConteggio.Text = $testo
}

# ------------------------------------------------------------
#   Avvio con conferme
# ------------------------------------------------------------
function Invoke-EsecuzioneGui {
    $s = $script:Sync
    $scelti = @(Get-SelezioneGui)

    if ($scelti.Count -eq 0) {
        [System.Windows.MessageBox]::Show($s.Finestra, 'Seleziona almeno un''operazione.', 'Niente da fare',
            [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
        return
    }

    $simula = [bool]$s.ChkSimula.IsChecked

    if (-not $simula) {
        $rischiosi = @($scelti | Where-Object {
            $_.Livello -ne 'Sicuro' -or ($_.ContainsKey('Sconsigliato') -and $_.Sconsigliato)
        })
        if ($rischiosi.Count -gt 0) {
            $righe = ($rischiosi | ForEach-Object { '  - ' + $_.Nome }) -join [Environment]::NewLine
            $testo = 'Queste operazioni hanno un impatto reale sul sistema:' + [Environment]::NewLine + [Environment]::NewLine +
                     $righe + [Environment]::NewLine + [Environment]::NewLine + 'Procedere?'
            $r = [System.Windows.MessageBox]::Show($s.Finestra, $testo, 'Conferma',
                     [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
            if ($r -ne [System.Windows.MessageBoxResult]::Yes) { return }
        }
    }

    $ids = @()
    if ($s.ChkRipristino.IsChecked -and -not $simula) { $ids += 'maint_restorepoint' }
    $ids += @($scelti | ForEach-Object { $_.Id } | Where-Object { $_ -ne 'maint_restorepoint' })

    Start-LavoroGui -Modo 'task' -Ids $ids
}
