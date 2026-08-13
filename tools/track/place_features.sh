#!/usr/bin/env sh
# Place a circuit's checkpoints and coins evenly around its road-generator loop.
#   ./place_features.sh --scene scenes/circuit3.tscn --checkpoints 6 --coins 14
#   ./place_features.sh --scene scenes/circuit3.tscn --checkpoints 6 --coins 14 --dry-run
#   ./place_features.sh --help
#
# The last checkpoint is the start/finish, and it is placed BEHIND the StartLine
# (--start-finish-setback metres back along the loop), so a lap begins already clear of the gate
# that ends it. See CONTEXT.md's **Start line** entry for why either side would work and why this
# is the one chosen.
#
# Rewrites the scene's Checkpoints and Coins subtrees and NOTHING ELSE — the road, the ground,
# the StartLine and every unique_id come through the rewrite byte for byte. Run --dry-run first
# if you want to see the arclengths and positions before the file changes.
#
# This is only for circuits drawn with the road-generator addon.
#
# POSIX companion to place_features.ps1. See tools/track/place_features.gd for why the placement
# itself is a Godot script rather than Python: the frame a gate's prism has to lie flat on is
# defined by the addon's own interpolation, and this reads it rather than guessing it.
GODOT="$HOME/Downloads/Godot_v4.7.1-stable_win64/Godot_v4.7.1-stable_win64_console.exe"
HERE="$(dirname "$0")"
cd "$HERE/../.." || exit 1

exec "$GODOT" --headless --path . --script res://tools/track/place_features.gd -- "$@"
