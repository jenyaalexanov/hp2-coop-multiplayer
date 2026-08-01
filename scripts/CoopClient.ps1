# LAN/Internet client: connect to host (fullscreen, max primary display)
# Usage: CoopClient.ps1 <hostIp> [port] [playerName]

param(
    [Parameter(Position = 0)][string]$HostIp,
    [Parameter(Position = 1)][string]$Port,
    [Parameter(Position = 2)][string]$PlayerName
)

. "$PSScriptRoot\Common.ps1"
Require-Administrator -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters

if ([string]::IsNullOrWhiteSpace($HostIp)) {
    Write-Host "Usage: Join.bat <hostIp> [port] [playerName]"
    Write-Host "Example: Join.bat 192.168.1.10 7777 Hermione"
    $HostIp = Read-Host "Host IP"
    if ([string]::IsNullOrWhiteSpace($HostIp)) {
        throw "Host IP is required."
    }
}

$cfg = Load-Config
$gameRoot = Resolve-GamePath
$map = [string]$cfg.default_map

if ([string]::IsNullOrWhiteSpace($Port)) { $Port = [string]$cfg.default_port }
if ([string]::IsNullOrWhiteSpace($PlayerName)) { $PlayerName = "Guest" }
$portNum = [int]$Port

Assert-Sandbox -GameRoot $gameRoot -PlayerId "P2"

$docs = Get-PlayerDocs "P2"
New-Item -ItemType Directory -Path $docs -Force | Out-Null

Write-CoopIni -Path (Join-Path $docs "HP2Coop.ini") -LastHost $HostIp -LastPort $portNum -PlayerName $PlayerName -WasHost $false
Write-CoopIni -Path (Join-Path $gameRoot "instances\P2\System\HP2Coop.ini") -LastHost $HostIp -LastPort $portNum -PlayerName $PlayerName -WasHost $false

Clear-RunningLock "P2"
Start-GameInstance -GameRoot $gameRoot -PlayerId "P2" -WindowTitle "HP2 Coop Client" -Map $map -DisplayMode Fullscreen

Write-Host "Connecting to ${HostIp}:$portNum as $PlayerName..."
