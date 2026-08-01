# LAN/Internet host: starts P1 listening on UDP (fullscreen, max primary display)
# Usage: CoopHost.ps1 [port] [playerName]

param(
    [string]$Port,
    [string]$PlayerName
)

. "$PSScriptRoot\Common.ps1"
Require-Administrator -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters

$cfg = Load-Config
$gameRoot = Resolve-GamePath
$map = [string]$cfg.default_map

if ([string]::IsNullOrWhiteSpace($Port)) { $Port = [string]$cfg.default_port }
if ([string]::IsNullOrWhiteSpace($PlayerName)) { $PlayerName = "Host" }
$portNum = [int]$Port

Assert-Sandbox -GameRoot $gameRoot -PlayerId "P1"

$docs = Get-PlayerDocs "P1"
New-Item -ItemType Directory -Path $docs -Force | Out-Null

Write-CoopIni -Path (Join-Path $docs "HP2Coop.ini") -LastHost "0.0.0.0" -LastPort $portNum -PlayerName $PlayerName -WasHost $true
Write-CoopIni -Path (Join-Path $gameRoot "instances\P1\System\HP2Coop.ini") -LastHost "0.0.0.0" -LastPort $portNum -PlayerName $PlayerName -WasHost $true

Clear-RunningLock "P1"
Start-GameInstance -GameRoot $gameRoot -PlayerId "P1" -WindowTitle "HP2 Coop Host" -Map $map -DisplayMode Fullscreen

Write-Host "Host listening UDP $portNum. Open firewall for UDP $portNum."
Write-Host "Friend joins with: Join.bat YOUR_LAN_IP $portNum"
