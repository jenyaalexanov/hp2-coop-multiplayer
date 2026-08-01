@echo off
setlocal
cd /d "%~dp0"

:: Writing into Program Files needs elevation. Re-launch once via UAC.
net session >nul 2>&1
if not "%errorLevel%"=="0" (
  echo HP2 Co-op Install
  echo.
  echo Administrator rights are required to install into:
  echo   C:\Program Files ^(x86^)\Harry Potter\Chamber of Secrets
  echo.
  echo A UAC prompt will appear — click Yes.
  echo.
  powershell -NoProfile -Command "Start-Process -LiteralPath '%~f0' -Verb RunAs"
  exit /b 0
)

echo HP2 Co-op Install
echo Default game path: C:\Program Files (x86)\Harry Potter\Chamber of Secrets
echo (override via config.json if needed)
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Install.ps1" %*
set "ERR=%ERRORLEVEL%"
if not "%ERR%"=="0" (
  echo.
  echo Install failed with exit code %ERR%.
  pause
  exit /b %ERR%
)
echo.
pause
exit /b 0
