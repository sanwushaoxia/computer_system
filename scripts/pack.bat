@echo off
cd /d "%~dp0scripts\"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Pack-LargeFiles.ps1"
pause