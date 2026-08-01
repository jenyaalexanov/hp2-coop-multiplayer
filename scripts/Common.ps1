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
    Add-Type -AssemblyName System.Windows.Forms
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    return @{
        Width  = [int]$bounds.Width
        Height = [int]$bounds.Height
    }
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
    $startupFs = if ($fullscreen) { "True" } else { "False" }
    $capture = if ($fullscreen) { "True" } else { "False" }

    $enc = [Text.Encoding]::Default
    $lines = [System.Collections.Generic.List[string]]([IO.File]::ReadAllLines($Path, $enc))
    $inWin = $false
    $inCore = $false
    $winSectionIdx = -1
    $have = @{
        WindowedViewportX                 = $false
        WindowedViewportY                 = $false
        FullscreenViewportX               = $false
        FullscreenViewportY               = $false
        StartupFullscreen                 = $false
        BorderlessFullscreen              = $false
        CenterBorderlessWindow            = $false
        UseFullscreenCursorInBorderless   = $false
        CaptureMouse                      = $false
        UserFolder                        = $false
        SavePath                          = $false
    }

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\[') { $inWin = $false; $inCore = $false }
        if ($lines[$i] -match '^\[WinDrv\.WindowsClient\]') {
            $inWin = $true
            $winSectionIdx = $i
        }
        if ($lines[$i] -match '^\[Core\.System\]') { $inCore = $true }

        if ($inCore -and $UserFolder -and $lines[$i] -match '^UserFolder=') {
            $lines[$i] = "UserFolder=$UserFolder"
            $have.UserFolder = $true
        }
        if ($inCore -and $UserFolder -and $lines[$i] -match '^SavePath=') {
            $lines[$i] = "SavePath=$env:USERPROFILE\Documents\$UserFolder\Save"
            $have.SavePath = $true
        }

        if (-not $inWin) { continue }

        if ($lines[$i] -match '^;?\s*WindowedViewportX=') { $lines[$i] = "WindowedViewportX=$Width"; $have.WindowedViewportX = $true }
        elseif ($lines[$i] -match '^;?\s*WindowedViewportY=') { $lines[$i] = "WindowedViewportY=$Height"; $have.WindowedViewportY = $true }
        elseif ($lines[$i] -match '^;?\s*FullscreenViewportX=') { $lines[$i] = "FullscreenViewportX=$Width"; $have.FullscreenViewportX = $true }
        elseif ($lines[$i] -match '^;?\s*FullscreenViewportY=') { $lines[$i] = "FullscreenViewportY=$Height"; $have.FullscreenViewportY = $true }
        elseif ($lines[$i] -match '^;?\s*StartupFullscreen=') { $lines[$i] = "StartupFullscreen=$startupFs"; $have.StartupFullscreen = $true }
        elseif ($lines[$i] -match '^;?\s*BorderlessFullscreen=') { $lines[$i] = "BorderlessFullscreen=False"; $have.BorderlessFullscreen = $true }
        elseif ($lines[$i] -match '^;?\s*CenterBorderlessWindow=') { $lines[$i] = "CenterBorderlessWindow=False"; $have.CenterBorderlessWindow = $true }
        elseif ($lines[$i] -match '^;?\s*UseFullscreenCursorInBorderless=') { $lines[$i] = "UseFullscreenCursorInBorderless=False"; $have.UseFullscreenCursorInBorderless = $true }
        elseif ($lines[$i] -match '^;?\s*CaptureMouse=') { $lines[$i] = "CaptureMouse=$capture"; $have.CaptureMouse = $true }
    }

    if ($winSectionIdx -ge 0) {
        $insertAt = $winSectionIdx + 1
        $toInsert = @()
        if (-not $have.FullscreenViewportX) { $toInsert += "FullscreenViewportX=$Width" }
        if (-not $have.FullscreenViewportY) { $toInsert += "FullscreenViewportY=$Height" }
        if (-not $have.WindowedViewportX) { $toInsert += "WindowedViewportX=$Width" }
        if (-not $have.WindowedViewportY) { $toInsert += "WindowedViewportY=$Height" }
        if (-not $have.StartupFullscreen) { $toInsert += "StartupFullscreen=$startupFs" }
        if (-not $have.BorderlessFullscreen) { $toInsert += "BorderlessFullscreen=False" }
        if (-not $have.CaptureMouse) { $toInsert += "CaptureMouse=$capture" }
        for ($j = $toInsert.Count - 1; $j -ge 0; $j--) {
            $lines.Insert($insertAt, $toInsert[$j])
        }
    }

    if ($UserFolder -and -not ($lines | Where-Object { $_ -match '^UserFolder=' })) {
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\[Core\.System\]') {
                $lines.Insert($i + 1, "UserFolder=$UserFolder")
                break
            }
        }
    }

    [IO.File]::WriteAllLines($Path, $lines.ToArray(), $enc)
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
        [ValidateSet("Windowed", "Fullscreen")][string]$DisplayMode = "Windowed"
    )
    if ($DisplayMode -eq "Fullscreen") {
        $size = Get-PrimaryDisplaySize
        Write-Host ("[{0}] Fullscreen {1}x{2} (primary display)" -f $PlayerId, $size.Width, $size.Height)
        Apply-PlayerDisplayMode -GameRoot $GameRoot -PlayerId $PlayerId -Mode Fullscreen -Width $size.Width -Height $size.Height
    }
    else {
        Apply-PlayerDisplayMode -GameRoot $GameRoot -PlayerId $PlayerId -Mode Windowed -Width 960 -Height 540
    }

    $sys = Join-Path $GameRoot "instances\$PlayerId\System"
    $log = "Game$PlayerId.log"
    Start-Process -FilePath (Join-Path $sys "game.exe") `
        -WorkingDirectory $sys `
        -ArgumentList @("-NEWWINDOW", "-NOFRONTEND", $Map, "INI=Game.ini", "USERINI=User.ini", "LOG=$log") `
        -WindowStyle Normal
}

function Ensure-IpDrvBeforeHGame([string]$iniPath) {
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
        Write-Warning "EditPackages=HGame not found in $iniPath - skipping IpDrv reorder."
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
    return $changed
}
