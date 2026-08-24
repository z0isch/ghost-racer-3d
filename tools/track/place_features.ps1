# Place a circuit's checkpoints and clocks evenly around its road-generator loop.
#   .\place_features.ps1 -Scene scenes/circuit3.tscn -Checkpoints 6 -Clocks 14
#   .\place_features.ps1 -Scene scenes/circuit3.tscn -Checkpoints 6 -Clocks 14 -DryRun
#
# The last checkpoint is the start/finish, and it is placed BEHIND the StartLine (-StartFinishSetback
# metres back along the loop), so a Run begins already clear of the gate that ends it. See
# CONTEXT.md's **Start line** entry for why either side would work and why this is the one chosen.
#
# Rewrites the scene's Checkpoints and Clocks subtrees and NOTHING ELSE — the road, the ground,
# the StartLine and every unique_id come through the rewrite byte for byte. Run -DryRun first if
# you want to see the arclengths and positions before the file changes.
#
# This is only for circuits drawn with the road-generator addon.
#
# Windows/PowerShell companion to place_features.sh. See tools/track/place_features.gd for why
# the placement itself is a Godot script rather than Python: the frame a gate's prism has to lie
# flat on is defined by the addon's own interpolation, and this reads it rather than guessing it.

param(
    [Parameter(Mandatory = $true)][string]$Scene,
    [Parameter(Mandatory = $true)][int]$Checkpoints,
    [Parameter(Mandatory = $true)][int]$Clocks,
    [double]$StartFinishSetback = 8.0,
    [double]$GateClearance = 4.0,
    [string]$ClockLateral = "0",
    [double]$HalfWidth = 4.5,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$godot = Join-Path $env:USERPROFILE "Downloads\Godot_v4.7.1-stable_win64\Godot_v4.7.1-stable_win64_console.exe"
$root = Resolve-Path (Join-Path $PSScriptRoot "..\..")

if (-not (Test-Path $godot)) { throw "Godot not found at $godot - see docs/engine-setup.md" }

Push-Location $root
try {
    $toolArgs = @(
        "--scene", $Scene,
        "--checkpoints", $Checkpoints,
        "--clocks", $Clocks,
        "--start-finish-setback", $StartFinishSetback,
        "--gate-clearance", $GateClearance,
        "--clock-lateral", $ClockLateral,
        "--half-width", $HalfWidth
    )
    if ($DryRun) { $toolArgs += "--dry-run" }

    & $godot --headless --path . --script res://tools/track/place_features.gd -- @toolArgs
    if ($LASTEXITCODE -ne 0) { throw "place_features failed with exit code $LASTEXITCODE" }
}
finally { Pop-Location }
