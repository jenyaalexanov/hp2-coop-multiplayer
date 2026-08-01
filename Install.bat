@echo off
setlocal EnableExtensions
cd /d "%~dp0"

:: Always elevate — default install path is under Program Files (x86).
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

:: %~dp0. avoids trailing-backslash quoting bugs in PowerShell strings.
:: -Wait keeps this window open until the elevated install completes (or UAC is cancelled).
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $p = Start-Process -FilePath '%~f0' -WorkingDirectory '%~dp0.' -Verb RunAs -PassThru -Wait; if ($null -eq $p) { exit 1 }; exit $p.ExitCode } catch { Write-Host $_; exit 1 }"
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
