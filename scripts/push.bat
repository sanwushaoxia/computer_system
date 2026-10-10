@echo off
cd /d "%~dp0scripts\"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Push-Git.ps1"
pause