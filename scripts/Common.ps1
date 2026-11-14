# Shared helpers for HP2 Co-op scripts.
# Dot-source from other scripts: . "$PSScriptRoot\Common.ps1"

$ErrorActionPreference = "Stop"

# Default HP2 install location for all players. Override anytime via config.json.
$script:DefaultGamePath = 'C:\Program Files (x86)\Harry Potter\Chamber of Secrets'

function Get-RepoRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

function Get-DefaultGamePath {
    return $script:DefaultGamePath
}

function Get-ConfigPath {
    return (Join-Path (Get-RepoRoot) "config.json")
}

function Get-ConfigExamplePath {
    return (Join-Path (Get-RepoRoot) "config.example.json")
}

function Ensure-ConfigFile {
    $cfgPath = Get-ConfigPath
    if (-not (Test-Path $cfgPath)) {
        $example = Get-ConfigExamplePath
        if (-not (Test-Path $example)) {
            throw "Missing config.example.json in repo root."
        }
        Copy-Item $example $cfgPath -Force
        Write-Host "Created config.json from config.example.json"
    }
    return $cfgPath
}

function Load-Config {
    $cfgPath = Ensure-ConfigFile
    $raw = Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8
    $cfg = $raw | ConvertFrom-Json
    if (-not $cfg.default_map) { $cfg | Add-Member -NotePropertyName default_map -NotePropertyValue "PrivetDr.unr" -Force }
    if (-not $cfg.default_port) { $cfg | Add-Member -NotePropertyName default_port -NotePropertyValue 7777 -Force }
    $path = [string]$cfg.game_path
    if ([string]::IsNullOrWhiteSpace($path) -or ($path -match 'Path\\To\\')) {
        $cfg | Add-Member -NotePropertyName game_path -NotePropertyValue (Get-DefaultGamePath) -Force
        Save-Config $cfg
    }
    return $cfg
}

function Save-Config($cfg) {
    $cfgPath = Get-ConfigPath
    $json = $cfg | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText($cfgPath, $json + "`n", [Text.UTF8Encoding]::new($false))
}

function Test-GameRoot([string]$gameRoot) {
    if ([string]::IsNullOrWhiteSpace($gameRoot)) { return $false }
    if ($gameRoot -match 'Path\\To\\') { return $false }
    $exe = Join-Path $gameRoot "System\Game.exe"
    return (Test-Path -LiteralPath $exe)
}

function Test-M212Install([string]$gameRoot) {
    $ipDrvU = Join-Path $gameRoot "System\IpDrv.u"
    $ipDrvDll = Join-Path $gameRoot "System\IpDrv.dll"
    return ((Test-Path -LiteralPath $ipDrvU) -or (Test-Path -LiteralPath $ipDrvDll))
}

function Resolve-GamePath {
    param(
        [switch]$PromptIfMissing
    )
    $cfg = Load-Config
    $path = [string]$cfg.game_path
    $defaultPath = Get-DefaultGamePath
    $dirty = $false

    # Prefer the well-known default install when config path is missing/invalid.
    if (-not (Test-GameRoot $path) -and (Test-GameRoot $defaultPath)) {
        if ($path -ne $defaultPath) {
            Write-Host "Using default game_path: $defaultPath"
        }
        $path = $defaultPath
        $cfg.game_path = $defaultPath
        $dirty = $true
    }

    if (-not (Test-GameRoot $path)) {
        if (-not $PromptIfMissing) {
            $examplePath = Get-ConfigExamplePath
            throw @"
Invalid or missing game_path in config.json.
Expected HP2 + M212 at:
  $defaultPath
Or set game_path in config.json to your install folder (the folder that contains System\Game.exe), then run Install.bat again.
See example: $examplePath
"@
        }

        Write-Host ""
        Write-Host "Game not found at default path:"
        Write-Host "  $defaultPath"
        Write-Host "Enter the full path to your Harry Potter 2 game folder"
        Write-Host "(the folder that contains System\Game.exe, with M212 installed)."
        Write-Host ""
        $entered = Read-Host "game_path"
        $entered = $entered.Trim().Trim('"')
        if (-not (Test-GameRoot $entered)) {
            throw "Path is not a valid game root (System\Game.exe not found): $entered"
        }
        $cfg.game_path = $entered
        $path = $entered
        $dirty = $true
        Write-Host "Saved game_path to config.json"
    }

    if ($dirty) {
        Save-Config $cfg
    }

    return (Resolve-Path -LiteralPath $path).Path
}

function Test-IsAdministrator {
    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-PathWritable([string]$dir) {
    if (-not (Test-Path -LiteralPath $dir)) { return $false }
    $probe = Join-Path $dir (".hp2coop-write-test-" + [guid]::NewGuid().ToString("n"))
    try {
        [IO.File]::WriteAllText($probe, "ok")
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
        return $true
    }
    catch {
        return $false
    }
}

function Require-Administrator {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [hashtable]$BoundParameters = @{}
    )
    if (Test-IsAdministrator) { return }

    Write-Host "Administrator rights required. A UAC prompt will appear..."
    $argList = [System.Collections.Generic.List[string]]@(
        "-NoProfile"
        "-ExecutionPolicy"
        "Bypass"
        "-File"
        $ScriptPath
    )
    foreach ($entry in $BoundParameters.GetEnumerator()) {
        $name = [string]$entry.Key
        $val = $entry.Value
        if ($val -is [System.Management.Automation.SwitchParameter]) {
            if ($val.IsPresent) { $argList.Add("-$name") }
            continue
        }
        if ($null -eq $val) { continue }
        $text = [string]$val
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        $argList.Add("-$name")
        $argList.Add($text)
    }

    try {
        $proc = Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $argList.ToArray() -Wait -PassThru
    }
    catch {
        throw "UAC elevation cancelled or failed: $_"
    }
    if ($null -eq $proc) {
        throw "Failed to start elevated PowerShell (UAC cancelled?)."
    }
    exit $proc.ExitCode
}

function Get-PrimaryDisplaySize {
    # Physical pixels, not DPI-scaled. At 125% DPI, Forms/EnumDisplaySettings report
    # 2752x1152 for a real 3440x1440 panel — game then opens a smaller window on one side.
    # GetDeviceCaps(DESKTOP*) returns the real framebuffer size.
    if (-not ("HP2CoopDisplay" -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class HP2CoopDisplay {
    [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr hwnd, IntPtr hdc);
    [DllImport("gdi32.dll")] public static extern int GetDeviceCaps(IntPtr hdc, int index);
    public const int HORZRES = 8;
    public const int VERTRES = 10;
    public const int DESKTOPHORZRES = 118;
    public const int DESKTOPVERTRES = 117;
}
"@
    }

    $width = 0
    $height = 0
    $hdc = [HP2CoopDisplay]::GetDC([IntPtr]::Zero)
    try {
        $width = [HP2CoopDisplay]::GetDeviceCaps($hdc, [HP2CoopDisplay]::DESKTOPHORZRES)
        $height = [HP2CoopDisplay]::GetDeviceCaps($hdc, [HP2CoopDisplay]::DESKTOPVERTRES)
        if ($width -le 0 -or $height -le 0) {
            $width = [HP2CoopDisplay]::GetDeviceCaps($hdc, [HP2CoopDisplay]::HORZRES)
            $height = [HP2CoopDisplay]::GetDeviceCaps($hdc, [HP2CoopDisplay]::VERTRES)
        }
    }
    finally {
        [void][HP2CoopDisplay]::ReleaseDC([IntPtr]::Zero, $hdc)
    }

    if ($width -le 0 -or $height -le 0) {
        Add-Type -AssemblyName System.Windows.Forms
        $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $width = [int]$bounds.Width
        $height = [int]$bounds.Height
    }

    return @{
        Width  = [int]$width
        Height = [int]$height
    }
}

function Set-GameUserFolder {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$UserFolder
    )
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $enc = [Text.Encoding]::Default
    $lines = [System.Collections.Generic.List[string]]([IO.File]::ReadAllLines($Path, $enc))
    $inCore = $false
    $have = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\[') { $inCore = $false }
        if ($lines[$i] -match '^\[Core\.System\]') { $inCore = $true; continue }
        if (-not $inCore) { continue }
        if ($lines[$i] -match '^\s*UserFolder=') {
            $lines[$i] = "UserFolder=$UserFolder"
            $have = $true
        }
        elseif ($lines[$i] -match '^\s*SavePath=') {
            $lines[$i] = "SavePath=$env:USERPROFILE\Documents\$UserFolder\Save"
        }
    }
    if (-not $have) {
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\[Core\.System\]') {
                $lines.Insert($i + 1, "UserFolder=$UserFolder")
                break
            }
        }
    }
    [IO.File]::WriteAllLines($Path, $lines.ToArray(), $enc)
}

function Set-GameDisplayIni {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$UserFolder = "",
        [ValidateSet("Windowed", "Fullscreen")][string]$Mode = "Windowed",
        [int]$Width = 960,
        [int]$Height = 540
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "INI not found: $Path"
    }

    $fullscreen = ($Mode -eq "Fullscreen")
    # M212/DX11 on Win10/11: borderless + native physical res is the reliable fullscreen.
    # CenterBorderlessWindow keeps the window on-screen when sizes disagree briefly.
    $startupFs = if ($fullscreen) { "True" } else { "False" }
    $borderless = if ($fullscreen) { "True" } else { "False" }
    $centerBorderless = if ($fullscreen) { "True" } else { "False" }
    $capture = if ($fullscreen) { "True" } else { "False" }

    $displayKeyPattern = '^\s*;?\s*(WindowedViewportX|WindowedViewportY|FullscreenViewportX|FullscreenViewportY|StartupFullscreen|BorderlessFullscreen|CenterBorderlessWindow|UseFullscreenCursorInBorderless|CaptureMouse)\s*='

    $enc = [Text.Encoding]::Default
    $lines = [System.Collections.Generic.List[string]]([IO.File]::ReadAllLines($Path, $enc))

    # Patch UserFolder / SavePath in [Core.System]
    if ($UserFolder) {
        $inCore = $false
        $haveUserFolder = $false
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\[') { $inCore = $false }
            if ($lines[$i] -match '^\[Core\.System\]') { $inCore = $true; continue }
            if (-not $inCore) { continue }
            if ($lines[$i] -match '^\s*UserFolder=') {
                $lines[$i] = "UserFolder=$UserFolder"
                $haveUserFolder = $true
            }
            elseif ($lines[$i] -match '^\s*SavePath=') {
                $lines[$i] = "SavePath=$env:USERPROFILE\Documents\$UserFolder\Save"
            }
        }
        if (-not $haveUserFolder) {
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match '^\[Core\.System\]') {
                    $lines.Insert($i + 1, "UserFolder=$UserFolder")
                    break
                }
            }
        }
    }

    # Rewrite display keys in viewport client sections. Strip old/commented duplicates,
    # then insert one clean authoritative block at the top of each section.
    $block = @(
        "WindowedViewportX=$Width"
        "WindowedViewportY=$Height"
        "FullscreenViewportX=$Width"
        "FullscreenViewportY=$Height"
        "StartupFullscreen=$startupFs"
        "BorderlessFullscreen=$borderless"
        "CenterBorderlessWindow=$centerBorderless"
        "UseFullscreenCursorInBorderless=False"
        "CaptureMouse=$capture"
    )

    $sectionHeaders = @('^\[WinDrv\.WindowsClient\]', '^\[XDrv\.XClient\]')
    $rewroteWinDrv = $false
    foreach ($headerPattern in $sectionHeaders) {
        $secStart = -1
        $secEnd = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match $headerPattern) {
                $secStart = $i
                $secEnd = $lines.Count
                for ($j = $i + 1; $j -lt $lines.Count; $j++) {
                    if ($lines[$j] -match '^\[') { $secEnd = $j; break }
                }
                break
            }
        }
        if ($secStart -lt 0) { continue }

        for ($i = $secEnd - 1; $i -gt $secStart; $i--) {
            if ($lines[$i] -match $displayKeyPattern) {
                $null = $lines.RemoveAt($i)
            }
        }

        for ($j = $block.Count - 1; $j -ge 0; $j--) {
            $lines.Insert($secStart + 1, $block[$j])
        }
        if ($headerPattern -match 'WinDrv') { $rewroteWinDrv = $true }
    }

    # Ensure the engine cache is big enough for fullscreen + co-op state.
    $inEngine = $false
    $haveCache = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\[') { $inEngine = $false }
        if ($lines[$i] -match '^\[Engine\.GameEngine\]') { $inEngine = $true; continue }
        if (-not $inEngine) { continue }
        if ($lines[$i] -match '^\s*;?\s*CacheSizeMegs=') {
            $lines[$i] = "CacheSizeMegs=256"
            $haveCache = $true
            $inEngine = $false
        }
    }
    if (-not $haveCache) {
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\[Engine\.GameEngine\]') {
                $lines.Insert($i + 1, "CacheSizeMegs=256")
                break
            }
        }
    }

    if (-not $rewroteWinDrv) {
        throw "Missing [WinDrv.WindowsClient] section in $Path"
    }

    [IO.File]::WriteAllLines($Path, $lines.ToArray(), $enc)
}

function Reset-GameDisplayIni {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$Width = 1280,
        [int]$Height = 1024
    )
    # Restore M212 stock video defaults: 1280x1024, no borderless, windowed start.
    if (-not (Test-Path -LiteralPath $Path)) { return }

    $displayKeyPattern = '^\s*;?\s*(WindowedViewportX|WindowedViewportY|FullscreenViewportX|FullscreenViewportY|StartupFullscreen|BorderlessFullscreen|CenterBorderlessWindow|UseFullscreenCursorInBorderless|CaptureMouse)\s*='
    $block = @(
        "WindowedViewportX=$Width"
        "WindowedViewportY=$Height"
        "FullscreenViewportX=$Width"
        "FullscreenViewportY=$Height"
        "StartupFullscreen=False"
        "BorderlessFullscreen=False"
        "CenterBorderlessWindow=False"
        "UseFullscreenCursorInBorderless=False"
        "CaptureMouse=False"
    )

    $enc = [Text.Encoding]::Default
    $lines = [System.Collections.Generic.List[string]]([IO.File]::ReadAllLines($Path, $enc))
    foreach ($headerPattern in @('^\[WinDrv\.WindowsClient\]', '^\[XDrv\.XClient\]')) {
        $secStart = -1
        $secEnd = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match $headerPattern) {
                $secStart = $i
                $secEnd = $lines.Count
                for ($j = $i + 1; $j -lt $lines.Count; $j++) {
                    if ($lines[$j] -match '^\[') { $secEnd = $j; break }
                }
                break
            }
        }
        if ($secStart -lt 0) { continue }
        for ($i = $secEnd - 1; $i -gt $secStart; $i--) {
            if ($lines[$i] -match $displayKeyPattern) { $null = $lines.RemoveAt($i) }
        }
        for ($j = $block.Count - 1; $j -ge 0; $j--) {
            $lines.Insert($secStart + 1, $block[$j])
        }
    }
    [IO.File]::WriteAllLines($Path, $lines.ToArray(), $enc)
    Write-Host "Reset video defaults: $Path"
}

function Apply-PlayerDisplayMode {
    param(
        [Parameter(Mandatory = $true)][string]$GameRoot,
        [Parameter(Mandatory = $true)][string]$PlayerId,
        [ValidateSet("Windowed", "Fullscreen")][string]$Mode = "Windowed",
        [int]$Width = 960,
        [int]$Height = 540
    )
    $userFolder = "HP2Coop-$PlayerId"
    $docs = Get-PlayerDocs $PlayerId
    New-Item -ItemType Directory -Path $docs -Force | Out-Null

    $gameIni = Join-Path $GameRoot "instances\$PlayerId\System\Game.ini"
    $hpIni = Join-Path $docs "HP.ini"
    if ((-not (Test-Path -LiteralPath $hpIni)) -and (Test-Path -LiteralPath $gameIni)) {
        Copy-Item -LiteralPath $gameIni -Destination $hpIni -Force
    }

    $paths = @(
        $gameIni,
        (Join-Path $GameRoot "instances\$PlayerId\System\Default.ini"),
        $hpIni
    )
    foreach ($p in $paths) {
        if (Test-Path -LiteralPath $p) {
            Set-GameDisplayIni -Path $p -UserFolder $userFolder -Mode $Mode -Width $Width -Height $Height
        }
    }
}

function Get-PlayerDocs([string]$playerId) {
    # playerId: P1, P2, P3
    $folder = "HP2Coop-$playerId"
    return (Join-Path $env:USERPROFILE "Documents\$folder")
}

function Write-CoopIni {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$LastHost,
        [Parameter(Mandatory = $true)][int]$LastPort,
        [Parameter(Mandatory = $true)][string]$PlayerName,
        [Parameter(Mandatory = $true)][bool]$WasHost,
        [bool]$SessionActive = $true,
        [bool]$ShowDebug = $true
    )
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $wasHostStr = if ($WasHost) { "True" } else { "False" }
    $sessionStr = if ($SessionActive) { "True" } else { "False" }
    $debugStr = if ($ShowDebug) { "True" } else { "False" }
    $content = @"
[HGame.CoopManager]
LastHost=$LastHost
LastPort=$LastPort
PlayerName=$PlayerName
bSessionActive=$sessionStr
bWasHost=$wasHostStr
bShowDebug=$debugStr
"@
    [IO.File]::WriteAllText($Path, $content.TrimEnd() + "`r`n", [Text.Encoding]::Default)
}

function Clear-RunningLock([string]$playerId) {
    $lock = Join-Path (Get-PlayerDocs $playerId) "Running.ini"
    if (Test-Path -LiteralPath $lock) {
        Remove-Item -LiteralPath $lock -Force -ErrorAction SilentlyContinue
    }
}

function Assert-Sandbox {
    param(
        [Parameter(Mandatory = $true)][string]$GameRoot,
        [Parameter(Mandatory = $true)][string]$PlayerId
    )
    $exe = Join-Path $GameRoot "instances\$PlayerId\System\game.exe"
    if (-not (Test-Path -LiteralPath $exe)) {
        throw "Sandbox $PlayerId missing at $exe`nRun Install.bat first."
    }
}

function Start-GameInstance {
    param(
        [Parameter(Mandatory = $true)][string]$GameRoot,
        [Parameter(Mandatory = $true)][string]$PlayerId,
        [Parameter(Mandatory = $true)][string]$WindowTitle,
        [string]$Map = "PrivetDr.unr",
        [ValidateSet("Default", "Windowed")][string]$DisplayMode = "Default"
    )
    # "Default" = leave the game's own video settings untouched (normal users).
    # "Windowed" = force two small windows (PlayLocal only).
    if ($DisplayMode -eq "Windowed") {
        Apply-PlayerDisplayMode -GameRoot $GameRoot -PlayerId $PlayerId -Mode Windowed -Width 960 -Height 540
    }

    $sys = Join-Path $GameRoot "instances\$PlayerId\System"
    $log = "Game$PlayerId.log"
    Start-Process -FilePath (Join-Path $sys "game.exe") `
        -WorkingDirectory $sys `
        -ArgumentList @("-NEWWINDOW", "-NOFRONTEND", $Map, "INI=Game.ini", "USERINI=User.ini", "LOG=$log") `
        -WindowStyle Normal
}

function Get-IniUserFolder([string]$iniPath) {
    if (-not (Test-Path -LiteralPath $iniPath)) { return $null }
    foreach ($line in [IO.File]::ReadAllLines($iniPath, [Text.Encoding]::Default)) {
        if ($line -match '^\s*UserFolder\s*=\s*(.+?)\s*$') {
            $name = $Matches[1].Trim()
            if ($name) { return $name }
        }
    }
    return $null
}

function Get-M212UserFolder([string]$gameRoot) {
    $name = Get-IniUserFolder (Join-Path $gameRoot "System\Default.ini")
    if ($name) { return $name }
    return "Harry - Coding Evolved"
}

# Commits that compiled dist/HGame.u against M212 UCC 469 (Nov 27 2025).
# HP2UScriptDecompile's default branch is Scaling-Patch. master is the stock decompile and is not used.
function Get-DevToolchainRepos {
    return @(
        @{
            Name   = "unrealscript-injector"
            Url    = "https://github.com/Die4Ever/unrealscript-injector.git"
            Commit = "3307ecb5c43be8c9ddf0fdf5958b93c76ef235c0"
        },
        @{
            Name   = "HP2UScriptDecompile"
            Url    = "https://github.com/metallicafan212/HP2UScriptDecompile.git"
            Commit = "d052c5bdb3ed2e232fa0f71d0189880d585b295d"
        }
    )
}

function Test-DevToolchainPinned {
    $tools = Join-Path (Get-RepoRoot) "tools"
    foreach ($r in (Get-DevToolchainRepos)) {
        $dest = Join-Path $tools $r.Name
        if (-not (Test-Path -LiteralPath (Join-Path $dest ".git"))) { return $false }
        Push-Location $dest
        try {
            $head = (git rev-parse HEAD 2>$null)
            if ($LASTEXITCODE -ne 0) { return $false }
            if ($head.Trim() -ne $r.Commit) { return $false }
        }
        finally {
            Pop-Location
        }
    }
    $compiler = Join-Path $tools "unrealscript-injector\compiler.py"
    return (Test-Path -LiteralPath $compiler)
}

function Sync-DevToolchain {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "git was not found on PATH. Install Git, then run SetupDev.bat or Rebuild.bat again."
    }
    $tools = Join-Path (Get-RepoRoot) "tools"
    New-Item -ItemType Directory -Path $tools -Force | Out-Null

    foreach ($r in (Get-DevToolchainRepos)) {
        $dest = Join-Path $tools $r.Name
        if (Test-Path -LiteralPath (Join-Path $dest ".git")) {
            Write-Host "Resetting $($r.Name) to $($r.Commit.Substring(0, 12))..."
        }
        else {
            if (Test-Path -LiteralPath $dest) {
                throw "Path exists but is not a git repo: $dest"
            }
            Write-Host "Cloning $($r.Name)..."
            git clone $r.Url $dest
            if ($LASTEXITCODE -ne 0) {
                throw "git clone failed for $($r.Name)"
            }
        }

        Push-Location $dest
        try {
            git fetch origin
            if ($LASTEXITCODE -ne 0) {
                throw "git fetch failed for $($r.Name)"
            }
            git checkout --force --detach $r.Commit
            if ($LASTEXITCODE -ne 0) {
                throw "git checkout $($r.Commit) failed for $($r.Name)"
            }
            git clean -fd
            if ($LASTEXITCODE -ne 0) {
                throw "git clean failed for $($r.Name)"
            }
            $head = (git rev-parse HEAD).Trim()
            if ($head -ne $r.Commit) {
                throw "$($r.Name) HEAD is $head, expected $($r.Commit)"
            }
            Write-Host "  $($r.Name) @ $head"
        }
        finally {
            Pop-Location
        }
    }
}

function Assert-M212ScriptPackages([string]$gameRoot) {
    $need = @(
        "UCC.exe", "Core.u", "Engine.u", "Editor.u", "UWindow.u", "Fire.u",
        "UnrealShare.u", "HPSounds.u", "HPModels.u", "HPParticle.u", "HProps.u", "IpDrv.u"
    )
    $missing = New-Object System.Collections.Generic.List[string]
    $sys = Join-Path $gameRoot "System"
    foreach ($name in $need) {
        if (-not (Test-Path -LiteralPath (Join-Path $sys $name))) {
            $missing.Add($name)
        }
    }
    if ($missing.Count -eq 0) { return }
    $list = $missing -join ", "
    throw @"
M212 install is incomplete. These files are missing from ${sys}:
  $list
Install Metallicafan212's M212 Engine/Editor into the game folder, then run the script again.
"@
}

function Ensure-IpDrvBeforeHGame {
    param(
        [Parameter(Mandatory = $true)][string]$iniPath,
        # Commented-out lists (typical Game.ini) are not an error.
        [switch]$Quiet
    )
    if (-not (Test-Path -LiteralPath $iniPath)) {
        throw "INI not found: $iniPath"
    }
    $enc = [Text.Encoding]::Default
    $lines = [System.Collections.Generic.List[string]]([IO.File]::ReadAllLines($iniPath, $enc))

    $ipIdx = -1
    $hgIdx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*EditPackages\s*=\s*IpDrv\s*$') { $ipIdx = $i }
        if ($lines[$i] -match '^\s*EditPackages\s*=\s*HGame\s*$') { $hgIdx = $i }
    }

    if ($hgIdx -lt 0) {
        if (-not $Quiet) {
            Write-Warning "EditPackages=HGame not found in $iniPath - skipping IpDrv reorder."
        }
        return $false
    }

    $changed = $false
    if ($ipIdx -lt 0) {
        $lines.Insert($hgIdx, "EditPackages=IpDrv")
        $changed = $true
        Write-Host "Inserted EditPackages=IpDrv before HGame in $(Split-Path $iniPath -Leaf)"
    }
    elseif ($ipIdx -gt $hgIdx) {
        $null = $lines.RemoveAt($ipIdx)
        # HGame index may have shifted if IpDrv was after it
        $hgIdx = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\s*EditPackages\s*=\s*HGame\s*$') { $hgIdx = $i; break }
        }
        $lines.Insert($hgIdx, "EditPackages=IpDrv")
        $changed = $true
        Write-Host "Moved EditPackages=IpDrv before HGame in $(Split-Path $iniPath -Leaf)"
    }

    if ($changed) {
        [IO.File]::WriteAllLines($iniPath, $lines.ToArray(), $enc)
    }
    return $true
}

# ucc make reads EditPackages from the UserFolder HP.ini (Documents\<UserFolder>\HP.ini),
# not from System\Default.ini, once that file exists. Patch every ini it might load.
function Ensure-M212EditPackages([string]$gameRoot) {
    $sys = Join-Path $gameRoot "System"
    $defaultIni = Join-Path $sys "Default.ini"
    if (-not (Test-Path -LiteralPath $defaultIni)) {
        throw "Missing $defaultIni"
    }

    $ok = New-Object System.Collections.Generic.List[string]
    if (-not (Ensure-IpDrvBeforeHGame $defaultIni)) {
        throw "EditPackages=HGame not found in $defaultIni. Install M212 into this game folder, then run the script again."
    }
    $ok.Add((Resolve-Path -LiteralPath $defaultIni).Path)

    $gameIni = Join-Path $sys "Game.ini"
    if (Test-Path -LiteralPath $gameIni) {
        $gameFull = (Resolve-Path -LiteralPath $gameIni).Path
        if ($gameFull.ToLowerInvariant() -ne $ok[0].ToLowerInvariant()) {
            if (Ensure-IpDrvBeforeHGame $gameIni -Quiet) {
                $ok.Add($gameFull)
            }
        }
    }

    # ucc follows UserFolder from Default.ini. Also patch Game.ini's folder when it differs,
    # so a sandbox UserFolder on Game.ini cannot hide a stale EditPackages list.
    $primaryFolder = Get-M212UserFolder $gameRoot
    $folders = New-Object System.Collections.Generic.List[string]
    $folders.Add($primaryFolder)
    if (Test-Path -LiteralPath $gameIni) {
        $gameFolder = Get-IniUserFolder $gameIni
        if ($gameFolder -and -not $folders.Contains($gameFolder)) {
            $folders.Add($gameFolder)
        }
    }

    foreach ($userFolder in $folders) {
        $doc = Join-Path $env:USERPROFILE "Documents\$userFolder"
        $hpIni = Join-Path $doc "HP.ini"
        $isPrimary = ($userFolder -eq $primaryFolder)
        if (-not (Test-Path -LiteralPath $hpIni)) {
            if (-not $isPrimary) { continue }
            New-Item -ItemType Directory -Path $doc -Force | Out-Null
            Copy-Item -LiteralPath $defaultIni -Destination $hpIni -Force
            Write-Host "Created $hpIni from Default.ini (ucc make reads this file)."
        }
        $quiet = $false
        if (-not $isPrimary) { $quiet = $true }
        if (-not (Ensure-IpDrvBeforeHGame $hpIni -Quiet:$quiet)) {
            if ($isPrimary) {
                throw "EditPackages=HGame not found in $hpIni"
            }
            continue
        }
        $ok.Add((Resolve-Path -LiteralPath $hpIni).Path)
    }

    Write-Host "EditPackages: IpDrv is listed before HGame in:"
    foreach ($path in $ok) {
        Write-Host "  $path"
    }
}

# A full decompile copied into the game folder makes ucc rebuild HPModels/HProps/... and fail.
function Assert-NoDependencySources([string]$gameRoot) {
    $packages = @(
        "Core", "Engine", "Editor", "UWindow", "Fire", "UnrealShare",
        "HPSounds", "HPModels", "HPParticle", "HProps", "IpDrv", "M212Share"
    )
    $hits = New-Object System.Collections.Generic.List[string]
    foreach ($pkg in $packages) {
        $dir = Join-Path $gameRoot "$pkg\Classes"
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        $uc = Get-ChildItem -LiteralPath $dir -Filter *.uc -Recurse -File -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($uc) { $hits.Add($pkg) }
    }
    if ($hits.Count -eq 0) { return }

    $list = $hits -join ", "
    throw @"
UCC would rebuild dependency packages because their Classes folders are inside the game directory:
  $list
under
  $gameRoot
Move those folders out of the game directory. Rebuild writes only HGame\Classes; Core, Engine, HPModels, HProps, IpDrv and the rest must stay as the .u files shipped with M212.
"@
}
