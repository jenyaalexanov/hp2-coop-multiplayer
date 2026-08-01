@echo off
setlocal
cd /d "%~dp0"
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
