# Engine setup

This project targets **Godot 4.7.1-stable, standard (non-Mono) build**.

Not the Mono build, and not by accident: the project is GDScript specifically so that it
can export to the web, which a C# project cannot.

- Download `Godot_v4.7.1-stable_win64.zip` from the official Godot releases.
- Extract it to `~/Downloads/Godot_v4.7.1-stable_win64/` — the engine binary is not
  committed, and the launch scripts look for it at exactly that path.
- Open the repo root in the editor: it contains `project.godot` directly.
- **There is no build step.** The editor runs the `.gd` sources directly. Nothing to
  compile, no SDK, no solution file.

Do not bump the engine version casually. 4.7.1 is pinned so that a feel regression is
attributable to a code change rather than to the engine.

## Verifying a checkout

`tools/track/check.ps1` (or `check.sh`) type-checks every script and is the closest thing
this project has to a build. A clean run means the tree is sound:

```
.\tools\track\check.ps1
```

It runs automatically before every desktop launch and every web export, and it is
load-bearing rather than decorative — the GDScript warnings block in `project.godot` is
**debug-only**, and a script that fails it is *silently dropped from its node* instead of
crashing. **Do not unwire it** from the launch scripts on the grounds that
`project.godot` already sets the warnings.

The first run on a fresh clone or worktree is slow (~4.5 s): `.godot/` is gitignored, so
the check has to run the editor once to build the class cache before any `class_name` can
be resolved. Warm runs are ~1.5 s.

The check itself runs as a live `SceneTree` (`tools/track/check.gd`, launched via
`--script`) rather than per-file `--check-only`: `--check-only` never starts the
`SceneTree`, so this project's autoloads (`Purse`, `CircuitSession`, `LoadoutHolder`,
`IncomeRunner`) are never registered, and any script that references one by its global
name would fail with a bogus "Identifier not found".

## Desktop

```
.\tools\track\drive.ps1                     play main.tscn (countdown, laps, ghost)
.\tools\track\drive.ps1 --no-check          skip the type check
```

`drive.sh` is the bash companion.

## Placing a circuit's gates and coins

```
.\tools\track\place_features.ps1 -Scene scenes/circuit3.tscn -Checkpoints 6 -Coins 14
```

Rewrites the named circuit's `Checkpoints` and `Coins` subtrees in place, spacing them
evenly around the road-generator loop. `-DryRun` reports the placement without writing.
`place_features.sh` is the bash companion.

## Web export

```
.\tools\track\serve.ps1                     export, serve on http://127.0.0.1:8060, open browser
.\tools\track\serve.ps1 -NoExport           serve whatever is already in build/web
.\tools\track\serve.ps1 -DebugBuild         export the debug template (verbose JS console)
```

`serve.sh` is the bash companion. `-DebugBuild`, not `-Debug`, because `-Debug` is a
PowerShell common parameter.

The script needs two things that are **not in the repo**, because both are gitignored:

**1. Export templates.** Install the 4.7.1 templates from the editor
(*Editor → Manage Export Templates → Download and Install*). They land in
`%APPDATA%\Godot\export_templates\4.7.1.stable\` and include all eight `web_*` variants.

**2. `export_presets.cfg`.** Gitignored, so it is per-checkout and every fresh clone or
git worktree starts without it. Recreate it from the editor
(*Project → Export → Add → Web*), leaving every option at its default. The defaults are
the correct ones — in particular **`variant/thread_support` must stay off**, which is
already 4.7's default. Set `export_path` to `build/web/index.html`; `build/` is gitignored.
Add a *Windows Desktop* preset the same way if you want desktop exports.

Threads off is what keeps serving simple: the `SharedArrayBuffer` and cross-origin
isolation checks in Godot's shipped `godot.js` all sit inside `if (supportsThreads)`, so
no COOP/COEP headers are needed anywhere. Threads cost this project nothing — no audio,
no `Thread` — and the nothreads wasm is not even smaller. If threads are ever turned on,
both `serve.ps1`/`serve.sh` and `serve.py` need those two headers added.

What *is* required is a **secure context**: serve on `localhost` or `127.0.0.1`, never a
LAN IP, or the build refuses to start. `serve.py` binds the loopback interface for exactly
this reason.

The renderer is `gl_compatibility`, which is the only one that works on the web and is
already set in `project.godot`. Output is ~39.5 MB, essentially all `index.wasm`
(~9.7 MB gzipped); the game's own `.pck` is 163 KB, so compression on the server is the
only lever that matters and asset weight is not a concern.
