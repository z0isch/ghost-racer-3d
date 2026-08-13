# Run the headless test suite.
#   .\test.ps1        run every suite in tests/run_tests.gd
#
# Windows/PowerShell companion to test.sh. Fast (a couple of seconds) because nothing here
# touches a scene: KartModel is a RefCounted with no nodes, no Input and no transforms, which is
# the entire point of the module boundary.
#
# This does NOT run the type check — the two gates are independent and CI runs both. Use
# check.ps1 for typing.

$ErrorActionPreference = "Stop"
$godot = Join-Path $env:USERPROFILE "Downloads\Godot_v4.7.1-stable_win64\Godot_v4.7.1-stable_win64_console.exe"
$root = Resolve-Path (Join-Path $PSScriptRoot "..\..")

if (-not (Test-Path $godot)) { throw "Godot not found at $godot - see docs/engine-setup.md" }

Push-Location $root
try {
    # Same import-pass guard as check.ps1, and for the same reason: --script cannot resolve any
    # class_name until .godot/global_script_class_cache.cfg lists the project's classes, and
    # .godot/ is gitignored so a fresh clone has none. The guard tests the cache's CONTENT, not
    # just its existence — an empty cache is what a checkout imported before the scripts existed
    # leaves behind, and it walks straight past an existence-only test.
    $cache = ".godot\global_script_class_cache.cfg"
    $hasClasses = { (Test-Path $cache) -and ((Get-Content $cache -Raw) -match '"class"') }
    if (-not (& $hasClasses)) {
        Write-Host "test: class cache missing or empty, running import pass..."
        & $godot --headless --path . --editor --quit | Out-Null
        if (-not (& $hasClasses)) {
            throw "import pass did not populate .godot\global_script_class_cache.cfg"
        }
    }

    # Start-Process for the same reason check.ps1 uses it: Windows PowerShell 5.1 wraps a native
    # command's stderr in a NativeCommandError the moment it is redirected in-process, and
    # $ErrorActionPreference = "Stop" turns that into a throw before $LASTEXITCODE can be read.
    $errFile = [System.IO.Path]::GetTempFileName()
    try {
        $p = Start-Process -FilePath $godot -NoNewWindow -Wait -PassThru `
            -ArgumentList @("--headless", "--path", ".", "--script", "res://tests/run_tests.gd") `
            -RedirectStandardError $errFile
        Get-Content $errFile | ForEach-Object { Write-Host $_ }
        if ($p.ExitCode -ne 0) { throw "tests failed" }
    }
    finally { Remove-Item $errFile -ErrorAction SilentlyContinue }
}
finally { Pop-Location }
