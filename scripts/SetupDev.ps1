# Clone developer toolchain into tools/ (gitignored).

. "$PSScriptRoot\Common.ps1"
Require-Administrator -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters

$repo = Get-RepoRoot
$tools = Join-Path $repo "tools"
New-Item -ItemType Directory -Path $tools -Force | Out-Null

function Assert-Command([string]$name) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        throw "'$name' not found on PATH. Install it and re-run SetupDev.bat."
    }
}

Assert-Command "git"
Assert-Command "python"

$repos = @(
    @{
        Name = "unrealscript-injector"
        Url  = "https://github.com/Die4Ever/unrealscript-injector.git"
    },
    @{
        Name = "HP2UScriptDecompile"
        Url  = "https://github.com/metallicafan212/HP2UScriptDecompile.git"
    }
)

foreach ($r in $repos) {
    $dest = Join-Path $tools $r.Name
    if (Test-Path -LiteralPath (Join-Path $dest ".git")) {
        Write-Host "Already cloned: $($r.Name) - pulling..."
        Push-Location $dest
        try {
            git pull --ff-only
        }
        finally {
            Pop-Location
        }
    }
    else {
        if (Test-Path -LiteralPath $dest) {
            throw "Path exists but is not a git repo: $dest"
        }
        Write-Host "Cloning $($r.Name)..."
        git clone $r.Url $dest
    }
}

Write-Host ""
Write-Host "=== Dev toolchain ready ==="
Write-Host "tools\unrealscript-injector"
Write-Host "tools\HP2UScriptDecompile"
Write-Host ""
Write-Host "Python: $((python --version) 2>&1)"
Write-Host "Edit sources under mod\src\HP2Coop\, then run Rebuild.bat"
Write-Host ""
Write-Host "Also ensure Install.bat has been run (game_path + sandboxes + IpDrv EditPackages)."
