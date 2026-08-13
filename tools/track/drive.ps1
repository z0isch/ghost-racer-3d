# Drive the game with a gamepad.
#   .\drive.ps1                       play main.tscn (countdown, laps, ghost)
#   .\drive.ps1 --no-check            skip the type check (see below)
#
# Every launch runs check.ps1 first (~1.5 s warm). A GDScript typing error does not
# crash the game - the node silently loses its script and you get a dead kart or a
# frozen HUD instead - so the check is what turns that into a visible failure before
# the window opens. --no-check is the escape hatch and is not consumed by Godot.
#
# Windows/PowerShell companion to drive.sh. There is no build step: the project is
# GDScript, so the standard (non-Mono) editor runs the source directly.

$ErrorActionPreference = "Stop"
$godot = Join-Path $env:USERPROFILE "Downloads\Godot_v4.7.1-stable_win64\Godot_v4.7.1-stable_win64_console.exe"
$root = Resolve-Path (Join-Path $PSScriptRoot "..\..")

if (-not (Test-Path $godot)) { throw "Godot not found at $godot - see docs/engine-setup.md" }

$godotArgs = @($args | Where-Object { $_ -ne "--no-check" })

if ($args -notcontains "--no-check") {
    & (Join-Path $PSScriptRoot "check.ps1")
}

Push-Location $root
try {
    & $godot --path . @godotArgs
}
finally { Pop-Location }
