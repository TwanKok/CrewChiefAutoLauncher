@echo off
set STARTUP=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup
set VBSFILE=%STARTUP%\CrewChiefAutoLauncher.vbs
set REGKEY=HKCU\Software\Microsoft\Windows\CurrentVersion\Run
set REGNAME=CrewChiefAutoLauncher

echo Verwijderen van CrewChief Auto-Launcher...

REM Verwijder VBS uit Startup-map
if exist "%VBSFILE%" del "%VBSFILE%" >nul 2>&1

REM Verwijder ook eventuele registry-entry (van oudere versie)
reg delete "%REGKEY%" /v "%REGNAME%" /f >nul 2>&1

echo [OK] Verwijderd uit Windows-opstart.

REM Stop eventueel draaiende instantie
powershell.exe -Command "
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
Where-Object { $_.CommandLine -like '*CrewChiefAutoLauncher*' } |
ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Write-Output 'Gestopt.'
" 2>&1

echo Klaar. CrewChief wordt niet meer automatisch gestart.
pause
