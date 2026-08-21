# Type-check every GDScript file in the project. Fails loudly if any script is bad.
#   .\check.ps1        type-check scripts/**/*.gd and tests/**/*.gd
#
# Called automatically by drive.ps1 and serve.ps1; pass them --no-check to skip it.
# Windows/PowerShell companion to check.sh.
#
# WHY THIS EXISTS. project.godot promotes the GDScript warnings table to errors, but
# that gate is weaker than it looks:
#
#   - It is DEBUG-ONLY. A release export happily runs untyped and unsafe-cast code,
#     so the web build is not gated by it at all.
#   - When it does fire, the node SILENTLY LOSES ITS SCRIPT and the game runs on.
#     No crash, no dialog - just a kart that does not move or a HUD that never
#     updates. That is a materially worse failure mode than a compile error.
#
# So the warnings block alone gates nothing you would notice. This script is what
# turns it into a real gate: a bad script stops the launch instead of producing a
# dead node twenty seconds into a lap.
#
# THE IMPORT PASS IS NOT OPTIONAL. Resolving any class_name needs
# .godot/global_script_class_cache.cfg to list the project's classes - without it even
# kart.gd fails to find its own `class_name Kart`, and the resulting "Could not find
# type" errors look exactly like real type errors. .godot/ is gitignored, so this
# happens on every new clone/worktree. The guard below runs the editor once to build it.
#
# The guard tests the cache's CONTENT, not just its existence. A cache can be present
# and empty (`list=[]`), and an existence-only test walks straight past that into a wall
# of bogus type errors.
#
# THE CHECKER RUNS AS A LIVE SCENE TREE, NOT --check-only. --check-only never starts the
# SceneTree, so this project's autoloads (Purse, CircuitSession, LoadoutHolder,
# IncomeRunner) are never registered, and every script that references one by its global
# name fails with a bogus "Identifier not found" even though it is correct. tools/track/
# check.gd runs as a real --script SceneTree instead, where autoloads are live, and
# type-checks every scripts/**/*.gd and tests/**/*.gd file itself by loading each one.

$ErrorActionPreference = "Stop"
$godot = Join-Path $env:USERPROFILE "Downloads\Godot_v4.7.1-stable_win64\Godot_v4.7.1-stable_win64_console.exe"
$root = Resolve-Path (Join-Path $PSScriptRoot "..\..")

if (-not (Test-Path $godot)) { throw "Godot not found at $godot - see docs/engine-setup.md" }

Push-Location $root
try {
    $cache = ".godot\global_script_class_cache.cfg"
    $hasClasses = { (Test-Path $cache) -and ((Get-Content $cache -Raw) -match '"class"') }
    if (-not (& $hasClasses)) {
        Write-Host "check: class cache missing or empty, running import pass..."
        & $godot --headless --path . --editor --quit | Out-Null
        if (-not (& $hasClasses)) {
            throw "import pass did not populate .godot\global_script_class_cache.cfg"
        }
    }

    # Godot reports parse errors on stderr, and Start-Process is the only way to
    # read them here. Windows PowerShell 5.1 wraps a native command's stderr in a
    # NativeCommandError the moment it is redirected in-process - `2>&1` and
    # `2>$file` both do it - and $ErrorActionPreference = "Stop" turns that into a
    # throw before $LASTEXITCODE can be read, so the check would die on the first
    # bad script with a PowerShell stack trace instead of listing every failure.
    # Start-Process redirects at the OS level, so stderr is never a PS stream.
    $errFile = [System.IO.Path]::GetTempFileName()
    $outFile = [System.IO.Path]::GetTempFileName()
    try {
        $p = Start-Process -FilePath $godot -NoNewWindow -Wait -PassThru `
            -ArgumentList @("--headless", "--path", ".", "--script", "res://tools/track/check.gd") `
            -RedirectStandardError $errFile -RedirectStandardOutput $outFile
        if ($p.ExitCode -ne 0) {
            Write-Host ""
            Get-Content $outFile | Where-Object { $_ -match "^check:" } |
                ForEach-Object { Write-Host $_ -ForegroundColor Red }
            Write-Host ""
            Get-Content $errFile | Where-Object { $_ -match "error" } |
                ForEach-Object { Write-Host "  $_" }
            throw "type check failed"
        }
    }
    finally { Remove-Item $errFile, $outFile -ErrorAction SilentlyContinue }
}
finally { Pop-Location }
