@echo off
setlocal EnableExtensions
cd /d "%~dp0"

net session >nul 2>&1
if "%errorLevel%"=="0" goto :run

echo HP2 Co-op Host
echo Requesting Administrator ^(UAC^)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\RelaunchElevated.ps1" -BatPath "%~f0" -WorkingDirectory "%~dp0." %*
set "ERR=%ERRORLEVEL%"
if not "%ERR%"=="0" (
  echo.
  echo Failed to elevate. Right-click Host.bat -^> Run as administrator.
  pause
  exit /b %ERR%
)
exit /b 0

:run
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\CoopHost.ps1" %*
if errorlevel 1 pause
exit /b %ERRORLEVEL%
