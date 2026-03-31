@echo off
setlocal

set SCRIPT=%~dp0CrewChiefAutoLauncher.ps1
set REGKEY=HKCU\Software\Microsoft\Windows\CurrentVersion\Run
set REGNAME=CrewChiefAutoLauncher

echo Installeren van CrewChief Auto-Launcher...

REM Registreer in Windows startup (geen admin nodig)
reg add "%REGKEY%" /v "%REGNAME%" /t REG_SZ /d "powershell.exe -WindowStyle Hidden -NonInteractive -ExecutionPolicy Bypass -File \"%SCRIPT%\"" /f >nul 2>&1

if %ERRORLEVEL% EQU 0 (
    echo [OK] Toegevoegd aan Windows-opstart.
) else (
    echo [FOUT] Kon niet registreren in registry.
    pause
    exit /b 1
)

REM Controleer of launcher al actief is, zo ja, niet opnieuw starten
powershell.exe -Command "if (Get-Process powershell -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like '*CrewChiefAutoLauncher*' }) { exit 0 } else { exit 1 }" >nul 2>&1

if %ERRORLEVEL% EQU 1 (
    echo Launcher nu starten...
    start "" powershell.exe -WindowStyle Hidden -NonInteractive -ExecutionPolicy Bypass -File "%SCRIPT%"
    echo [OK] Launcher actief.
) else (
    echo [INFO] Launcher was al actief.
)

echo.
echo Klaar! CrewChief wordt voortaan automatisch gestart als je een racegame opent.
echo Log: %LOCALAPPDATA%\CrewChiefAutoLauncher\launcher.log
echo.
pause
