@echo off
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\CoopHost.ps1" %*
if errorlevel 1 pause
exit /b %ERRORLEVEL%
