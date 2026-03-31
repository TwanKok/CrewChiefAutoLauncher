@echo off
set REGKEY=HKCU\Software\Microsoft\Windows\CurrentVersion\Run
set REGNAME=CrewChiefAutoLauncher

echo Verwijderen van CrewChief Auto-Launcher...

REM Verwijder uit Windows-opstart
reg delete "%REGKEY%" /v "%REGNAME%" /f >nul 2>&1

echo [OK] Verwijderd uit Windows-opstart.

REM Stop eventueel draaiende instantie
powershell.exe -Command "
Get-Process powershell -ErrorAction SilentlyContinue |
Where-Object { (Get-WmiObject Win32_Process -Filter \"ProcessId = \$(\$_.Id)\" -ErrorAction SilentlyContinue).CommandLine -like '*CrewChiefAutoLauncher*' } |
Stop-Process -Force -ErrorAction SilentlyContinue
Write-Output 'Gestopt.'
" 2>&1

echo Klaar. CrewChief wordt niet meer automatisch gestart.
pause
