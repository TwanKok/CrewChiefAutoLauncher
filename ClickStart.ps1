<#
    Wacht tot CrewChief geladen is en klikt automatisch op "Start Crew Chief".
    Gebruikt WM_COMMAND (BN_CLICKED) - werkt zonder dat het venster focus nodig heeft.
#>
param([string]$LogFile = "$env:LOCALAPPDATA\CrewChiefAutoLauncher\launcher.log")

function Log([string]$msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFile -Value "[$ts] [CLICK] $msg" -ErrorAction SilentlyContinue
}

Add-Type @'
using System;
using System.Text;
using System.Threading;
using System.Runtime.InteropServices;
using System.Collections.Generic;

public class CCClick {
    const uint WM_COMMAND   = 0x0111;
    const int  BN_CLICKED   = 0;

    [DllImport("user32.dll")] static extern bool   EnumChildWindows(IntPtr h, EnumProc fn, IntPtr lp);
    [DllImport("user32.dll")] static extern int    GetWindowText(IntPtr h, StringBuilder sb, int n);
    [DllImport("user32.dll")] static extern int    GetDlgCtrlID(IntPtr h);
    [DllImport("user32.dll")] static extern bool   PostMessage(IntPtr h, uint msg, IntPtr wp, IntPtr lp);
    [DllImport("user32.dll")] static extern bool   ShowWindow(IntPtr h, int cmd);

    public delegate bool EnumProc(IntPtr h, IntPtr lp);

    // Geeft de HWND terug van de knop met tekst 'searchText' (& wordt genegeerd)
    public static IntPtr FindButton(IntPtr parent, string searchText) {
        IntPtr found = IntPtr.Zero;
        EnumChildWindows(parent, (h, lp) => {
            var sb = new StringBuilder(256);
            GetWindowText(h, sb, 256);
            if (sb.ToString().Replace("&", "").Equals(searchText, StringComparison.OrdinalIgnoreCase)) {
                found = h;
                return false;
            }
            return true;
        }, IntPtr.Zero);
        return found;
    }

    // Stuurt WM_COMMAND (BN_CLICKED) naar het parent venster - werkt zonder focus
    public static void TriggerButton(IntPtr mainWnd, IntPtr btnHwnd) {
        ShowWindow(mainWnd, 9); // SW_RESTORE - venster terugzetten als geminimaliseerd
        Thread.Sleep(200);
        int ctrlId = GetDlgCtrlID(btnHwnd);
        IntPtr wParam = new IntPtr((BN_CLICKED << 16) | (ctrlId & 0xFFFF));
        PostMessage(mainWnd, WM_COMMAND, wParam, btnHwnd);
    }

    // Geeft de huidige tekst van de start/stop knop terug.
    // Start-toestand: "&Start Crew Chief", Luister-toestand: "&Stop"
    public static string GetStartStopText(IntPtr parent) {
        string result = "";
        EnumChildWindows(parent, (h, lp) => {
            var sb = new StringBuilder(256);
            GetWindowText(h, sb, 256);
            string clean = sb.ToString().Replace("&", "").Trim();
            if (clean.Equals("Stop", StringComparison.OrdinalIgnoreCase)
                || clean.IndexOf("Start Crew Chief", StringComparison.OrdinalIgnoreCase) >= 0
                || clean.IndexOf("Stop Crew Chief", StringComparison.OrdinalIgnoreCase) >= 0) {
                result = clean;
                return false;
            }
            return true;
        }, IntPtr.Zero);
        return result;
    }

    public static void MinimizeWindow(IntPtr hwnd) {
        ShowWindow(hwnd, 6); // SW_MINIMIZE
    }
}
'@

Log "ClickStart gestart - wacht op CC venster..."

# Wacht tot CC actief is met een geldig venster-handle (max 45s)
$deadline = (Get-Date).AddSeconds(45)
$proc = $null
while ((Get-Date) -lt $deadline) {
    $proc = Get-Process "CrewChiefV4" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc -and $proc.MainWindowHandle -ne [IntPtr]::Zero -and $proc.MainWindowTitle -ne "") { break }
    Start-Sleep -Milliseconds 500
    $proc = $null
}

if (-not $proc) { Log "Timeout - CC venster niet gevonden"; exit 1 }

Log "CC venster gevonden (PID $($proc.Id)) - wacht tot UI volledig geladen..."

# Wacht tot de Start-knop beschikbaar is (max 25s extra)
$btnDeadline = (Get-Date).AddSeconds(25)
$btn = [IntPtr]::Zero
while ((Get-Date) -lt $btnDeadline) {
    $p = Get-Process "CrewChiefV4" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $p) { Log "CC gestopt tijdens wachten"; exit 1 }
    $btn = [CCClick]::FindButton($p.MainWindowHandle, "Start Crew Chief")
    if ($btn -ne [IntPtr]::Zero) { $proc = $p; break }
    Start-Sleep -Milliseconds 500
}

if ($btn -eq [IntPtr]::Zero) {
    $cur = [CCClick]::GetStartStopText($proc.MainWindowHandle)
    if ($cur -like "*Stop*") {
        Log "CC is al gestart ('$cur') - niets te doen"
    } else {
        Log "Start-knop niet gevonden na wachten (huidig: '$cur')"
    }
    exit 0
}

Log "Start-knop gevonden - WM_COMMAND sturen..."
[CCClick]::TriggerButton($proc.MainWindowHandle, $btn)

# Wacht even en controleer resultaat
Start-Sleep -Seconds 2
$p2 = Get-Process "CrewChiefV4" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($p2) {
    $newText = [CCClick]::GetStartStopText($p2.MainWindowHandle)
    if ($newText -like "*Stop*") {
        Log "Gelukt! CC luistert nu ('$newText')"
        Start-Sleep -Milliseconds 500
        [CCClick]::MinimizeWindow($p2.MainWindowHandle)
    } else {
        Log "Knop na klik: '$newText' - controleer CC handmatig"
    }
} else {
    Log "CC is verdwenen na klikpoging"
}
