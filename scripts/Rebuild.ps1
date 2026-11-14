# Rebuild HGame.u from mod sources and refresh instance hardlinks + dist/.

. "$PSScriptRoot\Common.ps1"
Require-Administrator -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters

$repo = Get-RepoRoot
$gameRoot = Resolve-GamePath
$tools = Join-Path $repo "tools"
$injector = Join-Path $tools "unrealscript-injector\compiler.py"
$decompile = Join-Path $tools "HP2UScriptDecompile"
$modSrc = Join-Path $repo "mod\src"
$settingsExample = Join-Path $modSrc "compiler_settings.example.json"
$settingsOut = Join-Path $modSrc "compiler_settings.json"

if (-not (Test-Path -LiteralPath $injector)) {
    throw "Missing $injector`nRun SetupDev.bat first."
}
if (-not (Test-Path -LiteralPath $decompile)) {
    throw "Missing $decompile`nRun SetupDev.bat first."
}
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    throw "Python 3 not found on PATH."
}
if (-not (Test-M212Install $gameRoot)) {
    throw "M212 networking files not found (System\IpDrv.u / IpDrv.dll) under $gameRoot. Install Metallicafan212's M212 Engine/Editor into that folder first."
}

# Normalize paths for JSON (forward slashes)
function To-JsonPath([string]$p) {
    $full = (Resolve-Path -LiteralPath $p).Path
    return ($full -replace '\\', '/') + '/'
}

$decompilePath = To-JsonPath $decompile
$outDirPath = To-JsonPath $gameRoot

$settings = Get-Content -LiteralPath $settingsExample -Raw -Encoding UTF8 | ConvertFrom-Json
$settings.default.source_path = $decompilePath
$settings.default.out_dir = $outDirPath
$json = $settings | ConvertTo-Json -Depth 8
[IO.File]::WriteAllText($settingsOut, $json + "`n", [Text.UTF8Encoding]::new($false))
Write-Host "Wrote $settingsOut"
Write-Host "  source_path = $decompilePath"
Write-Host "  out_dir     = $outDirPath"

Write-Host "Stopping Game.exe..."
Get-Process -Name "Game" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# ucc make loads EditPackages from Documents\<UserFolder>\HP.ini.
Ensure-M212EditPackages $gameRoot
Assert-NoDependencySources $gameRoot

Write-Host "Compiling with M212 UCC (dist/HGame.u was built with Version 469, Compiled Nov 27 2025)..."
Push-Location $modSrc
try {
    # Injector may wait for Enter on some prompts; feed a newline.
    "" | python $injector --profile default --once
    if ($LASTEXITCODE -ne 0) {
        $userFolder = Get-M212UserFolder $gameRoot
        $uccLog = Join-Path $env:USERPROFILE "Documents\$userFolder\UCC.log"
        throw @"
Compile failed (exit $LASTEXITCODE).
UCC log: $uccLog
The build that produced dist/HGame.u used M212 UCC Version 469, Compiled Nov 27 2025 15:00:29 (X64-Release).
If your log header differs, install that M212 build. CoopLink extends IpDrv.UdpLink, so EditPackages=IpDrv must be before HGame in Documents\$userFolder\HP.ini.
"@
    }
}
finally {
    Pop-Location
}

$built = Join-Path $gameRoot "System\HGame.u"
if (-not (Test-Path -LiteralPath $built)) {
    # UE1 sometimes writes lowercase
    $builtLower = Join-Path $gameRoot "System\hgame.u"
    if (Test-Path -LiteralPath $builtLower) {
        $built = $builtLower
    }
    else {
        throw "Missing System\HGame.u after compile."
    }
}

Write-Host "Relinking into instances..."
foreach ($playerId in @("P1", "P2", "P3")) {
    $instSys = Join-Path $gameRoot "instances\$playerId\System"
    if (-not (Test-Path -LiteralPath $instSys)) { continue }
    $dest = Join-Path $instSys "hgame.u"
    if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Force }
    # Also clear HGame.u casing variant
    $destAlt = Join-Path $instSys "HGame.u"
    if ((Test-Path -LiteralPath $destAlt) -and ($destAlt -ne $dest)) {
        Remove-Item -LiteralPath $destAlt -Force -ErrorAction SilentlyContinue
    }
    cmd /c "mklink /H `"$dest`" `"$built`"" | Out-Null
    if (-not (Test-Path -LiteralPath $dest)) {
        Copy-Item -LiteralPath $built -Destination $dest -Force
    }
}

$distU = Join-Path $repo "dist\HGame.u"
Copy-Item -LiteralPath $built -Destination $distU -Force
Write-Host "Updated dist\HGame.u"

Write-Host ""
Write-Host "Done. Launch with PlayLocal.bat / Host.bat / Join.bat"
