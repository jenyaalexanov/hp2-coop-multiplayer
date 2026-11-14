# Clone developer toolchain into tools/ (gitignored) at the pinned commits.

. "$PSScriptRoot\Common.ps1"
Require-Administrator -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters

if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    throw "python was not found on PATH. Install Python 3, then run SetupDev.bat again."
}

Sync-DevToolchain

Write-Host ""
Write-Host "=== Dev toolchain ready ==="
Write-Host "tools\unrealscript-injector"
Write-Host "tools\HP2UScriptDecompile"
Write-Host ""
Write-Host "Python: $((python --version) 2>&1)"
Write-Host "Edit sources under mod\src\HP2Coop\, then run Rebuild.bat"
Write-Host "Rebuild.bat also clones these pins if tools\ is missing."
Write-Host ""
Write-Host "Also ensure the game + M212 are installed (Install.bat sets game_path, sandboxes, and IpDrv EditPackages)."
