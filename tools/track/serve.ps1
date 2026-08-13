# Export to web, serve it on localhost, open the browser. One command.
#   .\serve.ps1              export (release), serve on http://127.0.0.1:8060, open browser
#   .\serve.ps1 -NoExport    serve whatever is already in build/web (fast re-open)
#   .\serve.ps1 -Port 9000   different port
#   .\serve.ps1 -DebugBuild  export the debug template instead (verbose JS console)
#   .\serve.ps1 -NoCheck     skip the type check (see below)
#
# -DebugBuild, not -Debug: -Debug is a PowerShell common parameter and collides.
#
# The export runs check.ps1 first, and it matters MORE here than in drive.ps1: the
# GDScript warnings block in project.godot is debug-only, so a release web export
# will happily ship a script that would be rejected on the desktop debug build. The
# check is the only thing standing between a typing error and a silently dead node
# in the browser. Skipped with -NoExport (nothing is being built) or -NoCheck.
#
# Windows/PowerShell companion to serve.sh; the desktop equivalent is drive.ps1.
#
# No COOP/COEP headers are set anywhere in this pipeline, and that is deliberate:
# the Web preset exports with variant/thread_support=false, which is 4.7's default,
# and the SharedArrayBuffer/cross-origin-isolation checks in Godot's shipped godot.js
# all sit inside `if (supportsThreads)`. Threads cost this project nothing (no audio,
# no Thread) and the nothreads wasm is not even larger. If threads are ever enabled,
# both this script and serve.py need the two headers.
#
# The build output is gitignored (build/) - a 39 MB wasm is not a repo artefact.
# export_presets.cfg is gitignored too, so it is per-checkout: see docs/engine-setup.md
# for how to recreate the Web preset if this script cannot find it.

param(
    [switch]$NoExport,
    [switch]$DebugBuild,
    [switch]$NoCheck,
    [int]$Port = 8060
)

$ErrorActionPreference = "Stop"
$godot = Join-Path $env:USERPROFILE "Downloads\Godot_v4.7.1-stable_win64\Godot_v4.7.1-stable_win64_console.exe"
$root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$out = Join-Path $root "build\web\index.html"

if (-not (Test-Path $godot)) { throw "Godot not found at $godot - see docs/engine-setup.md" }

Push-Location $root
try {
    if (-not $NoExport) {
        if (-not $NoCheck) { & (Join-Path $PSScriptRoot "check.ps1") }
        if (-not (Test-Path (Join-Path $root "export_presets.cfg"))) {
            throw "export_presets.cfg missing (it is gitignored) - see docs/engine-setup.md"
        }
        New-Item -ItemType Directory -Force (Split-Path $out) | Out-Null
        $mode = if ($DebugBuild) { "--export-debug" } else { "--export-release" }
        & $godot --headless --path . $mode "Web" $out
        if ($LASTEXITCODE -ne 0) { throw "Export failed with exit code $LASTEXITCODE" }
    }
    python (Join-Path $PSScriptRoot "serve.py") --root (Split-Path $out) --port $Port
}
finally { Pop-Location }
