@echo off
setlocal EnableExtensions
cd /d "%~dp0"

net session >nul 2>&1
if "%errorLevel%"=="0" goto :elevated

echo HP2 Co-op Install
echo.
echo Administrator rights are required to install into:
echo   C:\Program Files ^(x86^)\Harry Potter\Chamber of Secrets
echo.
echo A UAC prompt will appear — click Yes.
echo.
echo Waiting for the elevated installer to finish...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\RelaunchElevated.ps1" -BatPath "%~f0" -WorkingDirectory "%~dp0." %*
set "ERR=%ERRORLEVEL%"
if not "%ERR%"=="0" (
  echo.
  echo Failed to elevate / install. Exit code %ERR%.
  echo If you cancelled UAC: right-click Install.bat -^> Run as administrator.
  pause
  exit /b %ERR%
)
exit /b 0

:elevated
echo HP2 Co-op Install ^(Administrator^)
echo Default game path: C:\Program Files ^(x86^)\Harry Potter\Chamber of Secrets
echo ^(override via config.json if needed^)
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
