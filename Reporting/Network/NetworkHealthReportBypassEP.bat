@echo off
:: --- CONFIGURATION ---
:: Script: NetworkHealthReportBypassEP.bat
:: Description: Safely bypasses the execution policy, handles elevation, and runs the script.
:: ---------------------

color 0A

:: Check for Administrator privileges
net session >nul 2>&1
if %errorLevel% == 0 (
    goto :runScript
) else (
    goto :elevate
)

:elevate
echo Requesting administrator privileges...
powershell -Command "Start-Process -FilePath '%comspec%' -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
exit /b

:runScript
color 0A
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "NetworkHealthReport.ps1"
pause
