# Re-launch a .bat elevated via UAC, forwarding remaining arguments.
# Usage (from a .bat):
#   powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\RelaunchElevated.ps1" -BatPath "%~f0" -WorkingDirectory "%~dp0." %*

param(
    [Parameter(Mandatory = $true)][string]$BatPath,
    [string]$WorkingDirectory = "",
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$BatArgs
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $BatPath)) {
    Write-Host "Bat not found: $BatPath"
    exit 1
}

$wd = $WorkingDirectory
if ([string]::IsNullOrWhiteSpace($wd)) {
    $wd = Split-Path -Parent $BatPath
}

$start = @{
    FilePath         = $BatPath
    WorkingDirectory = $wd
    Verb             = "RunAs"
    PassThru         = $true
    Wait             = $true
}
if ($BatArgs -and $BatArgs.Count -gt 0) {
    $start.ArgumentList = $BatArgs
}

try {
    $proc = Start-Process @start
}
catch {
    Write-Host $_
    exit 1
}

if ($null -eq $proc) {
    Write-Host "Failed to start elevated process (UAC cancelled?)."
    exit 1
}
exit $proc.ExitCode
