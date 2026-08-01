# Local co-op: 2 windowed instances auto-connect on 127.0.0.1

. "$PSScriptRoot\Common.ps1"
Require-Administrator -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters

$cfg = Load-Config
$gameRoot = Resolve-GamePath
$map = [string]$cfg.default_map
$port = [int]$cfg.default_port

Assert-Sandbox -GameRoot $gameRoot -PlayerId "P1"
Assert-Sandbox -GameRoot $gameRoot -PlayerId "P2"

$docs1 = Get-PlayerDocs "P1"
$docs2 = Get-PlayerDocs "P2"
New-Item -ItemType Directory -Path $docs1, $docs2 -Force | Out-Null

Write-CoopIni -Path (Join-Path $docs1 "HP2Coop.ini") -LastHost "127.0.0.1" -LastPort $port -PlayerName "Player1" -WasHost $true
Write-CoopIni -Path (Join-Path $docs2 "HP2Coop.ini") -LastHost "127.0.0.1" -LastPort $port -PlayerName "Player2" -WasHost $false
Write-CoopIni -Path (Join-Path $gameRoot "instances\P1\System\HP2Coop.ini") -LastHost "127.0.0.1" -LastPort $port -PlayerName "Player1" -WasHost $true
Write-CoopIni -Path (Join-Path $gameRoot "instances\P2\System\HP2Coop.ini") -LastHost "127.0.0.1" -LastPort $port -PlayerName "Player2" -WasHost $false

Clear-RunningLock "P1"
Clear-RunningLock "P2"

Start-GameInstance -GameRoot $gameRoot -PlayerId "P1" -WindowTitle "HP2 Coop Host" -Map $map -DisplayMode Windowed
Start-Sleep -Seconds 3
Start-GameInstance -GameRoot $gameRoot -PlayerId "P2" -WindowTitle "HP2 Coop Client" -Map $map -DisplayMode Windowed

Write-Host "Launched host (P1) + client (P2) on $map (windowed)"
Write-Host "Console: CoopStatus / CoopDebug"
