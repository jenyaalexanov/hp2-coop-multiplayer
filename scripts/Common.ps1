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

function Ensure-GameWriteAccess {
    param(
        [Parameter(Mandatory = $true)][string]$GameRoot,
        [Parameter(Mandatory = $true)][string]$ScriptPath
    )
    $sys = Join-Path $GameRoot "System"
    if (Test-PathWritable $sys) { return }

    if (Test-IsAdministrator) {
        throw "Cannot write to game System folder even as Administrator: $sys"
    }

    Write-Host ""
    Write-Host "Administrator rights required to install into:"
    Write-Host "  $GameRoot"
    Write-Host "A UAC prompt will appear..."
    Write-Host ""

    $argList = @(
        "-NoProfile"
        "-ExecutionPolicy", "Bypass"
        "-File", "`"$ScriptPath`""
    )
    $proc = Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $argList -Wait -PassThru
    if ($null -eq $proc) {
        throw "Failed to start elevated installer (UAC cancelled?)."
    }
    exit $proc.ExitCode
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
        [string]$Map = "PrivetDr.unr"
    )
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
