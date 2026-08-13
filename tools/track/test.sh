#!/usr/bin/env sh
# Run the headless test suite.
#   ./test.sh        run every suite in tests/run_tests.gd
#
# Fast (a couple of seconds) because nothing here touches a scene: KartModel is a RefCounted with
# no nodes, no Input and no transforms, which is the entire point of the module boundary.
#
# This does NOT run the type check — the two gates are independent and CI runs both. Use check.sh
# for typing.
GODOT="$HOME/Downloads/Godot_v4.7.1-stable_win64/Godot_v4.7.1-stable_win64_console.exe"
cd "$(dirname "$0")/../.." || exit 1

# Same import-pass guard as check.sh, and for the same reason: --script cannot resolve any
# class_name until .godot/global_script_class_cache.cfg lists the project's classes, and .godot/
# is gitignored so a fresh clone has none. The guard tests the cache's CONTENT, not just its
# existence — an empty cache is what a checkout imported before the scripts existed leaves behind.
if ! grep -q '"class"' .godot/global_script_class_cache.cfg 2>/dev/null; then
	echo "test: class cache missing or empty, running import pass..."
	"$GODOT" --headless --path . --editor --quit >/dev/null 2>&1
	if ! grep -q '"class"' .godot/global_script_class_cache.cfg 2>/dev/null; then
		echo "test: import pass did not populate .godot/global_script_class_cache.cfg" >&2
		exit 1
	fi
fi

"$GODOT" --headless --path . --script res://tests/run_tests.gd
