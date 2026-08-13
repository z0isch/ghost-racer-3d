#!/usr/bin/env sh
# Export to web, serve it on localhost, open the browser. One command.
#   ./serve.sh              export (release), serve on http://127.0.0.1:8060, open browser
#   ./serve.sh --no-export  serve whatever is already in build/web (fast re-open)
#   ./serve.sh --port 9000  different port
#   ./serve.sh --debug      export the debug template instead (verbose JS console)
#   ./serve.sh --no-check   skip the type check (see below)
#
# The desktop equivalent is drive.sh.
#
# The export runs check.sh first, and it matters MORE here than in drive.sh: the
# GDScript warnings block in project.godot is debug-only, so a release web export
# will happily ship a script that would be rejected on the desktop debug build. The
# check is the only thing standing between a typing error and a silently dead node
# in the browser. Skipped with --no-export (nothing is being built) or --no-check.
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
GODOT="$HOME/Downloads/Godot_v4.7.1-stable_win64/Godot_v4.7.1-stable_win64_console.exe"
HERE="$(dirname "$0")"
cd "$HERE/../.." || exit 1

EXPORT=1
CHECK=1
MODE="--export-release"
PORT=8060
while [ $# -gt 0 ]; do
	case "$1" in
		--no-export) EXPORT=0 ;;
		--no-check) CHECK=0 ;;
		--debug) MODE="--export-debug" ;;
		--port) shift; PORT="$1" ;;
		*) echo "unknown option: $1" >&2; exit 1 ;;
	esac
	shift
done

if [ "$EXPORT" -eq 1 ]; then
	[ "$CHECK" -eq 1 ] && { sh "$HERE/check.sh" || exit 1; }
	[ -f export_presets.cfg ] || { echo "export_presets.cfg missing (gitignored) - see docs/engine-setup.md" >&2; exit 1; }
	mkdir -p build/web
	"$GODOT" --headless --path . "$MODE" "Web" build/web/index.html || exit 1
fi

exec python "$HERE/serve.py" --root build/web --port "$PORT"
