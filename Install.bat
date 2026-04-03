@echo off
setlocal

set SCRIPT=%~dp0CrewChiefAutoLauncher.ps1
set STARTUP=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup
set VBSFILE=%STARTUP%\CrewChiefAutoLauncher.vbs
set REGKEY=HKCU\Software\Microsoft\Windows\CurrentVersion\Run
set REGNAME=CrewChiefAutoLauncher

echo Installeren van CrewChief Auto-Launcher...

REM Verwijder eventuele oude registry-entry (van eerdere versie)
reg delete "%REGKEY%" /v "%REGNAME%" /f >nul 2>&1

REM Maak VBS aan in Startup-map (start launcher verborgen bij Windows-opstart)
echo Dim shell > "%VBSFILE%"
echo Set shell = CreateObject("WScript.Shell") >> "%VBSFILE%"
echo shell.Run "powershell.exe -WindowStyle Hidden -NonInteractive -ExecutionPolicy Bypass -File ""%SCRIPT%""", 0, False >> "%VBSFILE%"
echo Set shell = Nothing >> "%VBSFILE%"

if exist "%VBSFILE%" (
    echo [OK] Toegevoegd aan Windows-opstart.
) else (
    echo [FOUT] Kon VBS niet aanmaken in Startup-map.
    pause
    exit /b 1
)

REM Controleer of launcher al actief is, zo ja, niet opnieuw starten
powershell.exe -Command "if (Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like '*CrewChiefAutoLauncher*' }) { exit 0 } else { exit 1 }" >nul 2>&1

if %ERRORLEVEL% EQU 1 (
    echo Launcher nu starten...
    start "" wscript.exe "%VBSFILE%"
    echo [OK] Launcher actief.
) else (
    echo [INFO] Launcher was al actief.
)

echo.
echo Klaar! CrewChief wordt voortaan automatisch gestart als je een racegame opent.
echo Log: %LOCALAPPDATA%\CrewChiefAutoLauncher\launcher.log
echo.
pause
