@echo off
:: --- CONFIGURATION ---
:: Script: RecycleBinInfo.bat
:: Description: Bypasses execution policy, elevates permissions, and executes RecycleBinInfo.ps1.
:: ---------------------

:: Set console background to Black (0) and text to Light Green (A)
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
:: Re-apply the green color after the elevated window opens
color 0A
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "RecycleBinInfo.ps1"
pause
