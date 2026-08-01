# Recreate soft sandboxes for local HP2 co-op multi-instance.
# Each instance has its own System INI + Documents UserFolder; shared Maps/Textures via junctions.
# Requires -NEWWINDOW (M212) to bypass single-window lock.
#
# Usage: .\SetupInstances.ps1 -GameRoot "D:\Games\HP2"

param(
    [Parameter(Mandatory = $true)][string]$GameRoot
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path -LiteralPath $GameRoot).Path
if (-not (Test-Path -LiteralPath (Join-Path $root "System\game.exe"))) {
    throw "Not a valid game root (System\game.exe missing): $root"
}

$shared = @('Maps', 'Textures', 'Sounds', 'Music', 'Shaders', 'Help', 'M212Share', 'ModCache', 'ModFolders', 'ModPacks', 'DeusEx')
$players = @(
    @{ Id = 'P1'; UserFolder = 'HP2Coop-P1' },
    @{ Id = 'P2'; UserFolder = 'HP2Coop-P2' },
    @{ Id = 'P3'; UserFolder = 'HP2Coop-P3' }
)

function Set-WindowedIni([string]$path, [string]$userFolder) {
    $enc = [Text.Encoding]::Default
    $lines = [IO.File]::ReadAllLines($path, $enc)
    $inWin = $false; $inCore = $false
    for ($i = 0; $i -lt $lines.Length; $i++) {
        if ($lines[$i] -match '^\[') { $inWin = $false; $inCore = $false }
        if ($lines[$i] -match '^\[WinDrv\.WindowsClient\]') { $inWin = $true }
        if ($lines[$i] -match '^\[Core\.System\]') { $inCore = $true }
        if ($inCore -and $lines[$i] -match '^UserFolder=') { $lines[$i] = "UserFolder=$userFolder" }
        if ($inCore -and $lines[$i] -match '^SavePath=') { $lines[$i] = "SavePath=$env:USERPROFILE\Documents\$userFolder\Save" }
        if ($inWin -and $lines[$i] -match '^WindowedViewportX=') { $lines[$i] = 'WindowedViewportX=960' }
        if ($inWin -and $lines[$i] -match '^WindowedViewportY=') { $lines[$i] = 'WindowedViewportY=540' }
        if ($inWin -and $lines[$i] -match '^FullscreenViewportX=') { $lines[$i] = 'FullscreenViewportX=960' }
        if ($inWin -and $lines[$i] -match '^FullscreenViewportY=') { $lines[$i] = 'FullscreenViewportY=540' }
        if ($inWin -and $lines[$i] -match '^;?\s*StartupFullscreen=') { $lines[$i] = 'StartupFullscreen=False' }
        if ($inWin -and $lines[$i] -match '^;?\s*BorderlessFullscreen=') { $lines[$i] = 'BorderlessFullscreen=False' }
        if ($inWin -and $lines[$i] -match '^;?\s*CenterBorderlessWindow=') { $lines[$i] = 'CenterBorderlessWindow=False' }
        if ($inWin -and $lines[$i] -match '^;?\s*UseFullscreenCursorInBorderless=') { $lines[$i] = 'UseFullscreenCursorInBorderless=False' }
        if ($inWin -and $lines[$i] -match '^CaptureMouse=') { $lines[$i] = 'CaptureMouse=False' }
    }
    if (-not ($lines | Where-Object { $_ -match '^UserFolder=' })) {
        $list = [System.Collections.Generic.List[string]]$lines
        for ($i = 0; $i -lt $list.Count; $i++) {
            if ($list[$i] -match '^\[Core\.System\]') { $list.Insert($i + 1, "UserFolder=$userFolder"); break }
        }
        $lines = $list.ToArray()
    }
    [IO.File]::WriteAllLines($path, $lines, $enc)
}

foreach ($p in $players) {
    $inst = Join-Path $root "instances\$($p.Id)"
    $sys = Join-Path $inst "System"
    New-Item -ItemType Directory -Path $sys -Force | Out-Null

    foreach ($d in $shared) {
        $target = Join-Path $root $d
        $link = Join-Path $inst $d
        if (-not (Test-Path -LiteralPath $target)) { continue }
        if (Test-Path -LiteralPath $link) { cmd /c "rmdir `"$link`"" | Out-Null }
        cmd /c "mklink /J `"$link`" `"$target`"" | Out-Null
    }

    Get-ChildItem (Join-Path $root "System") -File | ForEach-Object {
        $dest = Join-Path $sys $_.Name
        if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue }
        if ($_.Extension -match '\.(ini|txt|int|bat|log)$') {
            Copy-Item $_.FullName $dest -Force
        }
        else {
            cmd /c "mklink /H `"$dest`" `"$($_.FullName)`"" 2>$null | Out-Null
            if (-not (Test-Path -LiteralPath $dest)) { Copy-Item $_.FullName $dest -Force }
        }
    }
    Get-ChildItem (Join-Path $root "System") -Directory | ForEach-Object {
        $link = Join-Path $sys $_.Name
        if (Test-Path -LiteralPath $link) { cmd /c "rmdir `"$link`"" | Out-Null }
        cmd /c "mklink /J `"$link`" `"$($_.FullName)`"" | Out-Null
    }

    Set-WindowedIni (Join-Path $sys "Default.ini") $p.UserFolder
    Set-WindowedIni (Join-Path $sys "Game.ini") $p.UserFolder

    $doc = Join-Path $env:USERPROFILE "Documents\$($p.UserFolder)"
    New-Item -ItemType Directory -Path "$doc\Save", "$doc\Logs" -Force | Out-Null
    $hp = Join-Path $doc "HP.ini"
    if (-not (Test-Path -LiteralPath $hp)) {
        Copy-Item (Join-Path $sys "Game.ini") $hp -Force
    }
    Set-WindowedIni $hp $p.UserFolder
    if (-not (Test-Path -LiteralPath (Join-Path $doc "User.ini"))) {
        Copy-Item (Join-Path $sys "User.ini") (Join-Path $doc "User.ini") -Force
    }
    Write-Host "OK $($p.Id) -> $inst (UserFolder=$($p.UserFolder))"
}

Write-Host ""
Write-Host "Done. Soft sandboxes ready under $root\instances"
