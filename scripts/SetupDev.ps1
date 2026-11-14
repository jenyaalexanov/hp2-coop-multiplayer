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

# Pins match the trees that compiled dist/HGame.u on M212 UCC 469 (Nov 27 2025).
# HP2UScriptDecompile default branch is Scaling-Patch; master is the stock decompile and is not used.
$repos = @(
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

foreach ($r in $repos) {
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

Write-Host ""
Write-Host "=== Dev toolchain ready ==="
Write-Host "tools\unrealscript-injector"
Write-Host "tools\HP2UScriptDecompile"
Write-Host ""
Write-Host "Python: $((python --version) 2>&1)"
Write-Host "Edit sources under mod\src\HP2Coop\, then run Rebuild.bat"
Write-Host ""
Write-Host "Also ensure Install.bat has been run (game_path + sandboxes + IpDrv EditPackages)."
