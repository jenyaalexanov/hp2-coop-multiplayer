# One-click player install: configure game path, deploy HGame.u, patch INI, create sandboxes.

. "$PSScriptRoot\Common.ps1"

$repo = Get-RepoRoot
Write-Host "=== HP2 Co-op Install ==="
Write-Host "Repo: $repo"
Write-Host ""

$gameRoot = Resolve-GamePath -PromptIfMissing
Write-Host "Game: $gameRoot"

if (-not (Test-M212Install $gameRoot)) {
    Write-Host ""
    Write-Host "ERROR: M212 networking files not found (System\IpDrv.u / IpDrv.dll)."
    Write-Host "This mod requires Metallicafan212's M212 Engine/Editor installed into your game folder."
    Write-Host ""
    Write-Host "Get M212 from the Harry Potter Modding Discord (author forbids redistributing the installer):"
    Write-Host "  https://discord.gg/th3K6Epnug"
    Write-Host "Project info / download pointers:"
    Write-Host "  https://hp-games.net/metallicafan212-s-harry-potter-2-en"
    Write-Host ""
    exit 1
}

$distU = Join-Path $repo "dist\HGame.u"
if (-not (Test-Path -LiteralPath $distU)) {
    throw "Missing prebuilt package: $distU"
}

$sys = Join-Path $gameRoot "System"
$targetU = Join-Path $sys "HGame.u"
$backupU = Join-Path $sys "HGame.u.bak-hp2coop"

if ((Test-Path -LiteralPath $targetU) -and -not (Test-Path -LiteralPath $backupU)) {
    Copy-Item -LiteralPath $targetU -Destination $backupU -Force
    Write-Host "Backed up original HGame.u -> HGame.u.bak-hp2coop"
}
elseif (Test-Path -LiteralPath $backupU) {
    Write-Host "Backup already exists: HGame.u.bak-hp2coop"
}

Copy-Item -LiteralPath $distU -Destination $targetU -Force
Write-Host "Installed dist\HGame.u -> System\HGame.u"

$defaultIni = Join-Path $sys "Default.ini"
$null = Ensure-IpDrvBeforeHGame $defaultIni

Write-Host ""
Write-Host "Creating soft sandboxes (instances\P1..P3)..."
& "$PSScriptRoot\SetupInstances.ps1" -GameRoot $gameRoot

Write-Host ""
Write-Host "=== Install complete ==="
Write-Host ""
Write-Host "Next steps:"
Write-Host "  PlayLocal.bat              - two instances on one PC"
Write-Host "  Host.bat [port] [name]     - host a LAN/Internet session"
Write-Host "  Join.bat <ip> [port] [name]- join a host"
Write-Host ""
Write-Host "Game path is saved in config.json (edit anytime, then re-run Install.bat)."
