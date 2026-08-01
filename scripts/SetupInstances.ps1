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
$rootSys = Join-Path $root "System"
if (-not (Test-Path -LiteralPath (Join-Path $rootSys "game.exe"))) {
    throw "Not a valid game root (System\game.exe missing): $root"
}

function Get-ExistingPath([string[]]$candidates) {
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $null
}

function Ensure-SystemIniFiles([string]$systemDir) {
    $defaultIni = Get-ExistingPath @(
        (Join-Path $systemDir "Default.ini"),
        (Join-Path $systemDir "default.ini")
    )
    if (-not $defaultIni) {
        throw "Missing System\Default.ini in game install: $systemDir"
    }

    $gameIni = Join-Path $systemDir "Game.ini"
    if (-not (Test-Path -LiteralPath $gameIni)) {
        Copy-Item -LiteralPath $defaultIni -Destination $gameIni -Force
        Write-Host "Created System\Game.ini from Default.ini (fresh install)"
    }

    $userIni = Join-Path $systemDir "User.ini"
    if (-not (Test-Path -LiteralPath $userIni)) {
        $defUser = Get-ExistingPath @(
            (Join-Path $systemDir "DefUser.ini"),
            (Join-Path $systemDir "defuser.ini"),
            (Join-Path $systemDir "DefaultUser.ini")
        )
        if ($defUser) {
            Copy-Item -LiteralPath $defUser -Destination $userIni -Force
            Write-Host "Created System\User.ini from $(Split-Path $defUser -Leaf) (fresh install)"
        }
        else {
            # Minimal stub — game will fill it in on first launch.
            $stub = @"
[DefaultPlayer]
Name=Player
"@
            [IO.File]::WriteAllText($userIni, $stub + "`r`n", [Text.Encoding]::Default)
            Write-Host "Created stub System\User.ini (fresh install)"
        }
    }

    return @{
        DefaultIni = $defaultIni
        GameIni    = $gameIni
        UserIni    = $userIni
    }
}

function Set-WindowedIni([string]$path, [string]$userFolder) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "INI not found (sandbox incomplete): $path"
    }
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

function New-Junction([string]$link, [string]$target) {
    if (-not (Test-Path -LiteralPath $target)) { return }
    if (Test-Path -LiteralPath $link) {
        cmd /c "rmdir `"$link`"" | Out-Null
    }
    cmd /c "mklink /J `"$link`" `"$target`"" | Out-Null
    if (-not (Test-Path -LiteralPath $link)) {
        throw "Failed to create junction:`n  $link`n-> $target`nRun Install.bat as Administrator."
    }
}

function Publish-SystemFile([string]$source, [string]$dest) {
    if (Test-Path -LiteralPath $dest) {
        Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue
    }
    $ext = [IO.Path]::GetExtension($source)
    if ($ext -match '\.(ini|txt|int|bat|log)$') {
        Copy-Item -LiteralPath $source -Destination $dest -Force
    }
    else {
        cmd /c "mklink /H `"$dest`" `"$source`"" 2>$null | Out-Null
        if (-not (Test-Path -LiteralPath $dest)) {
            Copy-Item -LiteralPath $source -Destination $dest -Force
        }
    }
    if (-not (Test-Path -LiteralPath $dest)) {
        throw "Failed to publish System file into sandbox:`n  $source`n-> $dest`nRun Install.bat as Administrator."
    }
}

Write-Host "Ensuring base System INI files exist..."
$null = Ensure-SystemIniFiles $rootSys

$shared = @('Maps', 'Textures', 'Sounds', 'Music', 'Shaders', 'Help', 'M212Share', 'ModCache', 'ModFolders', 'ModPacks', 'DeusEx')
$players = @(
    @{ Id = 'P1'; UserFolder = 'HP2Coop-P1' },
    @{ Id = 'P2'; UserFolder = 'HP2Coop-P2' },
    @{ Id = 'P3'; UserFolder = 'HP2Coop-P3' }
)

foreach ($p in $players) {
    $inst = Join-Path $root "instances\$($p.Id)"
    $sys = Join-Path $inst "System"
    New-Item -ItemType Directory -Path $sys -Force | Out-Null

    foreach ($d in $shared) {
        New-Junction (Join-Path $inst $d) (Join-Path $root $d)
    }

    Get-ChildItem -LiteralPath $rootSys -File | ForEach-Object {
        Publish-SystemFile $_.FullName (Join-Path $sys $_.Name)
    }
    Get-ChildItem -LiteralPath $rootSys -Directory | ForEach-Object {
        New-Junction (Join-Path $sys $_.Name) $_.FullName
    }

    $instGameIni = Join-Path $sys "Game.ini"
    $instDefaultIni = Join-Path $sys "Default.ini"
    $instUserIni = Join-Path $sys "User.ini"

    if (-not (Test-Path -LiteralPath $instGameIni)) {
        if (Test-Path -LiteralPath $instDefaultIni) {
            Copy-Item -LiteralPath $instDefaultIni -Destination $instGameIni -Force
        }
        else {
            throw "Sandbox $($p.Id) missing Game.ini and Default.ini under $sys"
        }
    }
    if (-not (Test-Path -LiteralPath $instUserIni)) {
        $rootUser = Join-Path $rootSys "User.ini"
        if (Test-Path -LiteralPath $rootUser) {
            Copy-Item -LiteralPath $rootUser -Destination $instUserIni -Force
        }
    }

    Set-WindowedIni $instDefaultIni $p.UserFolder
    Set-WindowedIni $instGameIni $p.UserFolder

    $doc = Join-Path $env:USERPROFILE "Documents\$($p.UserFolder)"
    New-Item -ItemType Directory -Path "$doc\Save", "$doc\Logs" -Force | Out-Null
    $hp = Join-Path $doc "HP.ini"
    if (-not (Test-Path -LiteralPath $hp)) {
        Copy-Item -LiteralPath $instGameIni -Destination $hp -Force
    }
    Set-WindowedIni $hp $p.UserFolder
    $docUser = Join-Path $doc "User.ini"
    if (-not (Test-Path -LiteralPath $docUser)) {
        if (Test-Path -LiteralPath $instUserIni) {
            Copy-Item -LiteralPath $instUserIni -Destination $docUser -Force
        }
    }
    Write-Host "OK $($p.Id) -> $inst (UserFolder=$($p.UserFolder))"
}

Write-Host ""
Write-Host "Done. Soft sandboxes ready under $root\instances"
