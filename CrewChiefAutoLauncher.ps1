<#
.SYNOPSIS
    CrewChief Auto-Launcher met systray-icoon
.DESCRIPTION
    Draait op de achtergrond, toont een icoon in de taakbalk en start CrewChief
    automatisch zodra een racegame wordt gedetecteerd.
#>

$ErrorActionPreference = "SilentlyContinue"

# Verberg console-venster via Win32 API (betrouwbaarder dan -WindowStyle Hidden bij opstart)
Add-Type -Name ConsoleHelper -Namespace Native -MemberDefinition @'
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]   public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@
$hwnd = [Native.ConsoleHelper]::GetConsoleWindow()
if ($hwnd -ne [IntPtr]::Zero) { [Native.ConsoleHelper]::ShowWindow($hwnd, 0) | Out-Null }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ============================================================
# INSTELLINGEN - Pas hier aan indien nodig
# ============================================================

$CrewChiefExe  = "C:\Program Files (x86)\Britton IT Ltd\CrewChiefV4\CrewChiefV4.exe"
$CheckInterval = 5000  # milliseconden tussen process-checks
$GracePeriod   = 15    # seconden wachten nadat spel sluit, voor CC ook stopt
$LogFile       = "$env:LOCALAPPDATA\CrewChiefAutoLauncher\launcher.log"
$MaxLogLines   = 1000

# Mapping: procesnaam (zonder .exe) -> CrewChief GameEnum waarde
$GameMap = [ordered]@{
    # iRacing
    "iRacingSim64DX11"          = "IRACING"
    "iRacingSim64"              = "IRACING"

    # Le Mans Ultimate
    "Le Mans Ultimate"          = "LMU"
    "LMU"                       = "LMU"
    "LeMansCentral"             = "LMU"

    # Assetto Corsa Competizione
    "AC2-Win64-Shipping"        = "ACC"

    # Content Manager / Assetto Corsa
    "AssettoCorsa"              = "ASSETTO_64BIT"
    "Content Manager"           = "ASSETTO_64BIT"
    "acs"                       = "ASSETTO_64BIT"

    # Assetto Corsa EVO
    "AssettoCorsaEVO"           = "ASSETTO_EVO"

    # Automobilista 2
    "AMS2AVX"                   = "AMS2"
    "AMS2"                      = "AMS2"

    # rFactor 2
    "rFactor2"                  = "RF2_64BIT"

    # Project CARS 2
    "pCARS2"                    = "PCARS2"

    # Project CARS 3
    "pCARS3"                    = "PCARS3"

    # Project CARS (origineel)
    "pCARS64"                   = "PCARS_64BIT"
    "pCARS"                     = "PCARS_32BIT"

    # RaceRoom Racing Experience
    "RRRE64"                    = "RACE_ROOM"
    "RRRE"                      = "RACE_ROOM"

    # DiRT Rally (1)
    "dirtrally"                 = "DIRT"

    # F1 2024 (draait op F1_2023 engine in CC)
    "F1_24"                     = "F1_2023"
    "F1_23"                     = "F1_2023"
    "F1_22"                     = "F1_2022"
    "F1_21"                     = "F1_2021"
    "F1_2020"                   = "F1_2020"
    "F1_2019"                   = "F1_2019"
    "F1_2018"                   = "F1_2018"

    # GTR2
    "GTR2"                      = "GTR2"

    # Richard Burns Rally
    "RichardBurnsRally_SSE"     = "RBR"

    # rFactor / Automobilista 1
    "rFactor"                   = "RF1"
}

# ============================================================
# ICOON HELPERS
# ============================================================

function New-TrayIconImage {
    param(
        [System.Drawing.Color]$CircleColor,
        [System.Drawing.Color]$DotColor = [System.Drawing.Color]::Transparent
    )
    $bmp = New-Object System.Drawing.Bitmap 32, 32
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    # Buitenste cirkel (rand)
    $border = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(60, 60, 60))
    $g.FillEllipse($border, 1, 1, 30, 30)
    $border.Dispose()

    # Gekleurde cirkel
    $fill = New-Object System.Drawing.SolidBrush $CircleColor
    $g.FillEllipse($fill, 3, 3, 26, 26)
    $fill.Dispose()

    # "CC" tekst in het midden
    $font  = New-Object System.Drawing.Font "Arial", 10, ([System.Drawing.FontStyle]::Bold)
    $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
    $fmt   = New-Object System.Drawing.StringFormat
    $fmt.Alignment     = [System.Drawing.StringAlignment]::Center
    $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
    $g.DrawString("CC", $font, $brush, (New-Object System.Drawing.RectangleF 0, 0, 32, 32), $fmt)

    $font.Dispose(); $brush.Dispose(); $fmt.Dispose(); $g.Dispose()

    $handle = $bmp.GetHicon()
    return [System.Drawing.Icon]::FromHandle($handle)
}

# Drie icoonstatussen
$iconIdle     = New-TrayIconImage -CircleColor ([System.Drawing.Color]::FromArgb(120, 120, 120))  # grijs
$iconStarting = New-TrayIconImage -CircleColor ([System.Drawing.Color]::FromArgb(220, 140, 0))    # oranje
$iconActive   = New-TrayIconImage -CircleColor ([System.Drawing.Color]::FromArgb(40, 180, 40))    # groen

# ============================================================
# HULPFUNCTIES
# ============================================================

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    $dir  = Split-Path $LogFile -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
    try {
        $lines = [System.IO.File]::ReadAllLines($LogFile)
        if ($lines.Count -gt $MaxLogLines) {
            [System.IO.File]::WriteAllLines($LogFile, ($lines | Select-Object -Last ($MaxLogLines / 2)))
        }
    } catch {}
}

function Get-CrewChiefConfigPath {
    $urlDirs = Get-ChildItem "$env:LOCALAPPDATA\Britton_IT_Ltd\CrewChiefV4.exe_Url_*" -Directory -ErrorAction SilentlyContinue
    if (-not $urlDirs) { return $null }
    return $urlDirs | ForEach-Object {
        Get-ChildItem $_.FullName -Directory -ErrorAction SilentlyContinue
    } | Where-Object {
        Test-Path "$($_.FullName)\user.config"
    } | Sort-Object {
        try { [version]$_.Name } catch { [version]"0.0.0.0" }
    } -Descending | ForEach-Object {
        "$($_.FullName)\user.config"
    } | Select-Object -First 1
}

function Update-CrewChiefConfig {
    param([string]$ConfigPath, [string]$GameEnum)
    try {
        [xml]$cfg = [System.IO.File]::ReadAllText($ConfigPath)
        foreach ($pair in @{
            "last_game_definition" = $GameEnum
            "run_immediately"      = "True"
            "minimize_on_startup"  = "True"
        }.GetEnumerator()) {
            $node = $cfg.SelectSingleNode("//setting[@name='$($pair.Key)']/value")
            if ($node) { $node.InnerText = $pair.Value }
        }
        $cfg.Save($ConfigPath)
        Write-Log "Config bijgewerkt: last_game_definition=$GameEnum"
    } catch {
        Write-Log "Fout bij bijwerken config: $_" "ERROR"
    }
}

function Get-DetectedGame {
    $running = Get-Process -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ProcessName
    foreach ($procName in $GameMap.Keys) {
        if ($running -contains $procName) {
            return @{ ProcessName = $procName; GameEnum = $GameMap[$procName] }
        }
    }
    return $null
}

function Test-CrewChiefRunning {
    return $null -ne (Get-Process "CrewChiefV4" -ErrorAction SilentlyContinue)
}

function Start-CrewChief {
    param([string]$GameEnum)
    if (-not (Test-Path $CrewChiefExe)) {
        Write-Log "CrewChief executable niet gevonden" "ERROR"
        return
    }
    $cfg = Get-CrewChiefConfigPath
    if ($cfg) { Update-CrewChiefConfig -ConfigPath $cfg -GameEnum $GameEnum }

    Start-Process -FilePath $CrewChiefExe -ArgumentList "-game", $GameEnum -WindowStyle Minimized
    Write-Log "CrewChief gestart met spel: $GameEnum"

    $clickScript = Join-Path $PSScriptRoot "ClickStart.ps1"
    if (Test-Path $clickScript) {
        Start-Process powershell.exe `
            -ArgumentList "-WindowStyle Hidden -NonInteractive -ExecutionPolicy Bypass -File `"$clickScript`" -LogFile `"$LogFile`"" `
            -WindowStyle Hidden
        Write-Log "ClickStart.ps1 gestart"
    }
}

function Stop-CrewChief {
    $proc = Get-Process "CrewChiefV4" -ErrorAction SilentlyContinue
    if ($proc) { $proc | Stop-Process -Force -ErrorAction SilentlyContinue; Write-Log "CrewChief gestopt" }
}

function Set-TrayStatus {
    param([string]$Status, [System.Drawing.Icon]$Icon, [string]$Game = "")
    $script:tray.Icon = $Icon
    $gameText = if ($Game) { " ($Game)" } else { "" }
    $script:tray.Text = "CrewChief Launcher$gameText"
    $script:menuStatus.Text = $Status
}

# ============================================================
# TRAY ICON & MENU
# ============================================================

$tray = New-Object System.Windows.Forms.NotifyIcon
$tray.Icon    = $iconIdle
$tray.Text    = "CrewChief Launcher"
$tray.Visible = $true

$menu = New-Object System.Windows.Forms.ContextMenuStrip

$menuStatus = New-Object System.Windows.Forms.ToolStripMenuItem
$menuStatus.Text    = "Wacht op racegame..."
$menuStatus.Enabled = $false
$menuStatus.Font    = New-Object System.Drawing.Font "Segoe UI", 9, ([System.Drawing.FontStyle]::Bold)
$menu.Items.Add($menuStatus) | Out-Null

$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

$menuLog = New-Object System.Windows.Forms.ToolStripMenuItem "Open logbestand"
$menuLog.add_Click({ Start-Process notepad.exe $LogFile })
$menu.Items.Add($menuLog) | Out-Null

$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

$menuExit = New-Object System.Windows.Forms.ToolStripMenuItem "Launcher stoppen"
$menuExit.add_Click({
    $script:tray.Visible = $false
    $script:timer.Stop()
    Stop-CrewChief
    [System.Windows.Forms.Application]::Exit()
})
$menu.Items.Add($menuExit) | Out-Null

$tray.ContextMenuStrip = $menu

# ============================================================
# TIMER - vervangt de while-loop
# ============================================================

$script:launchedByUs = $false
$script:lastGameEnum = $null
$script:gameGoneAt   = $null
$script:ccWasRunning = Test-CrewChiefRunning

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = $CheckInterval

$timer.add_Tick({
    try {
        $detected  = Get-DetectedGame
        $ccRunning = Test-CrewChiefRunning

        if ($detected) {
            $script:gameGoneAt = $null

            if (-not $ccRunning) {
                $script:ccWasRunning = $false
                Set-TrayStatus -Status "CC starten voor $($detected.GameEnum)..." -Icon $iconStarting -Game $detected.GameEnum
                Start-CrewChief -GameEnum $detected.GameEnum
                $script:launchedByUs = $true
                $script:lastGameEnum = $detected.GameEnum

            } elseif ($script:launchedByUs -and $detected.GameEnum -ne $script:lastGameEnum) {
                Write-Log "Spelswitch: $($script:lastGameEnum) -> $($detected.GameEnum)"
                Set-TrayStatus -Status "CC herstarten voor $($detected.GameEnum)..." -Icon $iconStarting -Game $detected.GameEnum
                Stop-CrewChief
                Start-Sleep -Seconds 2
                Start-CrewChief -GameEnum $detected.GameEnum
                $script:lastGameEnum = $detected.GameEnum

            } else {
                Set-TrayStatus -Status "CC actief: $($detected.GameEnum)" -Icon $iconActive -Game $detected.GameEnum
            }

        } else {
            if ($script:launchedByUs -and $ccRunning) {
                if (-not $script:gameGoneAt) {
                    $script:gameGoneAt = Get-Date
                    Write-Log "Spel gestopt, wacht $GracePeriod seconden..."
                    Set-TrayStatus -Status "Spel gestopt, CC sluit over ${GracePeriod}s..." -Icon $iconStarting
                } elseif (((Get-Date) - $script:gameGoneAt).TotalSeconds -gt $GracePeriod) {
                    Stop-CrewChief
                    $script:launchedByUs = $false
                    $script:lastGameEnum = $null
                    $script:gameGoneAt   = $null
                    Set-TrayStatus -Status "Wacht op racegame..." -Icon $iconIdle
                }
            } elseif (-not $ccRunning) {
                if ($script:launchedByUs) {
                    Write-Log "CrewChief handmatig gesloten"
                    $script:launchedByUs = $false
                    $script:lastGameEnum = $null
                }
                $script:ccWasRunning = $false
                $script:gameGoneAt   = $null
                Set-TrayStatus -Status "Wacht op racegame..." -Icon $iconIdle
            }
        }
    } catch {
        Write-Log "Fout in timer: $_ - doorgaan..." "ERROR"
    }
})

$timer.Start()

Write-Log "====================================================="
Write-Log "CrewChief Auto-Launcher gestart (PID: $PID)"
Write-Log "====================================================="

# Start de Windows message loop (blokkeert tot Application.Exit() wordt aangeroepen)
[System.Windows.Forms.Application]::Run()

# Opruimen
$tray.Visible = $false
$iconIdle.Dispose()
$iconStarting.Dispose()
$iconActive.Dispose()
