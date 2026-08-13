#!/usr/bin/env sh
# Drive the game with a gamepad.
#   ./drive.sh                     play main.tscn (countdown, laps, ghost)
#   ./drive.sh --no-check          skip the type check (see below)
#
# Every launch runs check.sh first (~1.5 s warm). A GDScript typing error does not
# crash the game — the node silently loses its script and you get a dead kart or a
# frozen HUD instead — so the check is what turns that into a visible failure before
# the window opens. --no-check is the escape hatch and is not passed on to Godot.
#
# There is no build step: the project is GDScript, so the standard (non-Mono) editor
# runs the source directly.
GODOT="$HOME/Downloads/Godot_v4.7.1-stable_win64/Godot_v4.7.1-stable_win64_console.exe"
HERE="$(dirname "$0")"
cd "$HERE/../.." || exit 1

CHECK=1

# Rebuild "$@" without --no-check, so Godot never sees an option it does not know.
for a in "$@"; do
	case "$a" in
		--no-check) CHECK=0 ;;
		*) set -- "$@" "$a" ;;
	esac
	shift
done

if [ "$CHECK" -eq 1 ]; then
	sh "$HERE/check.sh" || exit 1
fi

exec "$GODOT" --path . "$@"
