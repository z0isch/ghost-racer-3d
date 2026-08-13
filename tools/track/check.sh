#!/usr/bin/env sh
# Type-check every GDScript file in the project. Fails loudly if any script is bad.
#   ./check.sh        type-check scripts/**/*.gd and tests/**/*.gd
#
# Called automatically by drive.sh and serve.sh; pass them --no-check to skip it.
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
# THE IMPORT PASS IS NOT OPTIONAL. --check-only cannot resolve any class_name until
# .godot/global_script_class_cache.cfg lists the project's classes - without it even
# kart.gd fails to find its own `class_name Kart`, and the resulting "Could not find
# type" errors look exactly like real type errors. .godot/ is gitignored, so this
# happens on every new clone/worktree. The guard below runs the editor once to build it.
#
# The guard tests the cache's CONTENT, not just its existence. A cache can be present
# and empty (`list=[]`), and an existence-only test walks straight past that into a wall
# of bogus type errors.
GODOT="$HOME/Downloads/Godot_v4.7.1-stable_win64/Godot_v4.7.1-stable_win64_console.exe"
cd "$(dirname "$0")/../.." || exit 1

if ! grep -q '"class"' .godot/global_script_class_cache.cfg 2>/dev/null; then
	echo "check: class cache missing or empty, running import pass..."
	"$GODOT" --headless --path . --editor --quit >/dev/null 2>&1
	if ! grep -q '"class"' .godot/global_script_class_cache.cfg 2>/dev/null; then
		echo "check: import pass did not populate .godot/global_script_class_cache.cfg" >&2
		exit 1
	fi
fi

FAILED=""
for f in $(find scripts tests -name '*.gd' | sort); do
	if ! OUT="$("$GODOT" --headless --path . --check-only --script "res://$f" 2>&1)"; then
		FAILED="$FAILED $f"
		echo ""
		echo "check: FAILED $f" >&2
		echo "$OUT" | grep -i error | sed 's/^/  /' >&2
	fi
done

if [ -n "$FAILED" ]; then
	echo "" >&2
	echo "check: script(s) failed the type check:$FAILED" >&2
	exit 1
fi
