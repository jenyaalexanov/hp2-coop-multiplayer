@echo off
setlocal EnableExtensions
cd /d "%~dp0"

net session >nul 2>&1
if "%errorLevel%"=="0" goto :run

echo HP2 Co-op SetupDev
echo Requesting Administrator ^(UAC^)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\RelaunchElevated.ps1" -BatPath "%~f0" -WorkingDirectory "%~dp0." %*
set "ERR=%ERRORLEVEL%"
if not "%ERR%"=="0" (
  echo.
  echo Failed to elevate. Right-click SetupDev.bat -^> Run as administrator.
  pause
  exit /b %ERR%
)
exit /b 0

:run
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\SetupDev.ps1" %*
set "ERR=%ERRORLEVEL%"
if not "%ERR%"=="0" (
  echo.
  echo SetupDev failed with exit code %ERR%.
  pause
  exit /b %ERR%
)
echo.
pause
exit /b 0
