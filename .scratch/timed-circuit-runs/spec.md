# Spec: Timed Circuit Runs

Implements the model settled in a grilling session and recorded in `CONTEXT.md` (the "The run" section) and `docs/adr/0001-timed-circuit-runs.md`. Read both before implementing — this spec assumes their vocabulary (Run, Run phase, Timeout, Abort, Results) and doesn't re-derive it.

## Summary of the behavior change

Today: `LapDirector` drives an infinite loop — Countdown → Racing → Finished → Countdown forever — where a lap ends the instant the ordered checkpoint sequence is completed.

After this change: `RunDirector` drives a bounded Run — Countdown → Racing → Results, with no automatic loop back. Checkpoints still wrap in order, but wrapping the sequence no longer ends anything; only a **Timeout** (the clock reaching the circuit's configured duration) or an **Abort** (`reset`) ends a Run. Results is a real stop that waits for player input before a new Countdown begins.

## Scope

**In scope:**
- `LapDirector` → `RunDirector`: phase model, checkpoint wrap, timing, recording, record promotion.
- `Circuit`: new per-circuit configured duration.
- `race.gd`: wiring the duration through.
- `LapHud` / `CountdownHud`: read the renamed phase/fields, and the new Results state needs a "start a new run" prompt somewhere.
- Global rename of `Lap*` → `Run*` identifiers referenced from other scripts (grep-driven, see Renames below).

**Explicitly out of scope (per ADR 0001 / the grilling session):**
- Any change to `pace_ghost.gd`, `boost_ghost_field.gd`, `hazard_ghost_field.gd`, `income_runner.gd`, `income_ghost_sweep.gd` beyond updating references to renamed `RunDirector` symbols. They keep consuming whatever's on `ghost_line_positions`/`ghost_line_yaws` unchanged, even though that recording is now a full multi-wrap Run instead of a single short lap. This was flagged as an open question in the ADR, not resolved here.
- Any reset of the coin field / boost ghost field / hazard ghost field mid-Run. They stay restored once per Countdown only (confirmed in grilling: only a Run's first wrap earns anything; later wraps in the same Run drive an emptied circuit). No code change needed here beyond the rename — this is already how `CoinField`, `BoostGhostField` and `HazardGhostField` behave today, since none of them currently listen for a wrap event at all.
- A wrap counter / "lap N" HUD readout. Nothing tracks wrap count as a concept in the settled model (see **CONTEXT.md**, `Run`: "no single pass through the checkpoints is tracked or named on its own"). Skip it rather than inventing a term the domain model doesn't have.
- `laps_required` as a *feature* — see Removals below, it's deleted, not repurposed.

## Data model changes

### `Circuit` (`scripts/circuit.gd`)

Add:
```gdscript
## How long a Run on this circuit lasts, in seconds. Configured per circuit rather than a global
## constant, since the two existing circuits may want different budgets.
@export var run_duration_seconds: float = 90.0
```
Placed alongside `ghost_line_path` / `loadout_path` — same "one per circuit, read by both the world and the race scene" treatment, though only the race scene actually needs it.

### `GhostLine` (`scripts/ghost_line.gd`)

No change. It already stores an opaque `(positions, yaws, earn_rate)` recording regardless of how long the recording is.

## `RunDirector` (renamed from `LapDirector`, `scripts/lap_director.gd` → `scripts/run_director.gd`)

### Enum

```gdscript
enum RunPhase {
	COUNTDOWN,
	RACING,
	RESULTS,
}
```

`FINISHED` becomes `RESULTS` — not a synonym swap, a behavior change: `RESULTS` has no `_phase_remaining` countdown of its own and does not auto-transition. It is left by explicit player input only (see `_physics_process` below).

### New export

```gdscript
## How long a Run lasts. Set by race.gd from the circuit's own run_duration_seconds, the same way
## ghost_line_path is set today — RunDirector doesn't know what a Circuit is, only the number.
@export var run_duration_seconds: float = 90.0
```

### Removed exports

- `laps_required` — no replacement. A Run's checkpoint sequence wraps unconditionally and indefinitely; there is no "N circuits per Run" knob because there is no fixed circuit count to configure, only a fixed time budget.
- The `dev_laps_more` / `dev_laps_fewer` input handling in `_physics_process` goes with it. (Leave the input actions themselves in the input map if other code references them — check first — otherwise remove.)

### Renamed state / accessors

| Old | New | Notes |
|---|---|---|
| `_current_lap_time` / `current_lap_time` | `_run_clock` / `run_clock` | Same semantics: elapsed seconds since countdown-zero. Still counts *up*, not down — Timeout is detected by comparing it against `run_duration_seconds`, so nothing about the countdown-vs-count-up display choice is forced by this rename (see CountdownHud/LapHud below for what to show). |
| `_lap_earnings` / `lap_earnings` | `_run_earnings` / `run_earnings` | Unchanged semantics. |
| `_record_earn_rate` / `record_earn_rate` | unchanged name | `earn_rate` is kept as a rate per the grilling session (Q13) — no rename needed, just retarget its docstring at "Run". |
| `_lap_count` / `lap_count` | **removed** | Was only meaningful against `laps_required`, which is gone. |
| `lap_started` (signal) | `run_started` | |
| `lap_completed(lap_time, is_record)` | `run_completed(run_time, is_record)` | Now only ever fired by Timeout, never by the checkpoint sweep. |
| `lap_aborted` (signal) | `run_aborted` | |
| `countdown_started` (signal) | unchanged name | |
| `complete_lap()` | `complete_run()` | See below — caller changes, not just the name. |
| `_begin_countdown()` / `_start_lap()` | `_begin_countdown()` / `_start_run()` | |

`class_name LapDirector` → `class_name RunDirector`. Every other script that types a variable as `LapDirector` or matches on `LapDirector.LapPhase.*` needs the equivalent update — see Renames below.

### Behavior changes

**`_physics_process`, `RACING` branch** (today: `lap_director.gd:227-233`)

Today, Racing only advances the clock and sweeps checkpoints; the lap ends when `_sweep_pending_checkpoint` reaches the last checkpoint. After this change, Racing also has to check for Timeout on its own, independent of checkpoint progress:

```gdscript
RunPhase.RACING:
	_run_clock += delta
	if _run_clock >= run_duration_seconds:
		complete_run()
	else:
		_sweep_pending_checkpoint.call_deferred()
		_append_sample.call_deferred()
```

`complete_run()` is called inline here rather than deferred, since it doesn't touch kart position and nothing downstream of it in the same frame depends on frame ordering the way the checkpoint sweep does. Skipping the sweep/sample calls on the Timeout frame is deliberate: the Run is already over, so there's nothing left to record.

**`_sweep_pending_checkpoint`** (today: `lap_director.gd:337-370`)

Delete the `laps_required` branch entirely. The tail of the function becomes:

```gdscript
_checkpoint_index += 1
if _checkpoint_index >= _checkpoints.size():
	_checkpoint_index = 0 # wrap — a Run only ends by Timeout or Abort, never here
_update_gate_visibility()
```

Reaching the start/finish gate no longer calls `complete_run()`. This is the single most important behavior change in the file — everything else follows from it.

**`complete_run()`** (renamed/retargeted `complete_lap`, today: `lap_director.gd:247-271`)

Same promotion logic (`is_record` check, ghost line duplication, `_save_ghost_line()`), with `lap_time`/`rate` computed from the renamed fields. The phase transition changes:

```gdscript
_phase = RunPhase.RESULTS
if _kart != null:
	_kart.frozen = true # held wherever the Run ended, not teleported
run_completed.emit(run_time, is_record)
```

No `_phase_remaining = finished_hold_seconds` — Results has no timer. The kart freezes in place rather than being taught to hold at the start line; it was already mid-drive when the clock ran out, and there's no "finish line" moment to hold it at anymore.

**`_physics_process`, `RESULTS` branch** — new, replaces the old `FINISHED` branch's auto-timeout:

```gdscript
RunPhase.RESULTS:
	if Input.is_action_just_pressed("reset"):
		_begin_countdown(restart_countdown_seconds)
```

Reusing the `reset` action here is a spec-level decision, not a settled domain one — flag it for review. It reads naturally ("press reset to go again") and avoids adding a new input action, but if that's confusing next to `reset`'s Abort meaning during Racing, swap in a dedicated action instead. Either way, this is **not** an Abort: no `run_aborted` signal fires, because there's no in-progress Run left to discard.

**Abort handling** (today: `lap_director.gd:204-211`) — unchanged except the rename and it now only fires from `COUNTDOWN` or `RACING` (the `reset`-during-`RESULTS` case above is handled separately and must not also fall into this branch — check phase before treating `reset` as an abort):

```gdscript
if _phase != RunPhase.RESULTS and Input.is_action_just_pressed("reset"):
	_recording_positions.clear()
	_recording_yaws.clear()
	run_aborted.emit()
	_begin_countdown(restart_countdown_seconds)
	return
```

**`_begin_countdown()`** (today: `lap_director.gd:422-444`) — same body, renamed fields (`_run_clock = 0.0`, `_run_earnings = 0`), drop the `_lap_count = 1` line.

## HUD changes

### `CountdownHud` (`scripts/countdown_hud.gd`)

- Type references: `LapDirector` → `RunDirector`, `LapDirector.LapPhase.*` → `RunDirector.RunPhase.*`.
- `FINISHED` case → `RESULTS` case. Today it goes blank ("the completed time belongs to LapHud"). Under the new model, Results needs to tell the player how to continue — this is a new requirement from the grilling session (Q7: "stop and show results, wait for player input"), not just a rename. Minimum: show something like `"press RESET to run again"` here, since this is already the one place the player's eyes go for "what do I do right now." (`LapHud` is the alternative home for this if a results-summary layout ends up living there instead — not prescribed here, just needs to land somewhere.)

### `LapHud` → `RunHud` (`scripts/lap_hud.gd` → `scripts/run_hud.gd`)

- `class_name LapHud` → `RunHud`, `director_path` typed as `RunDirector`.
- `_director.lap_completed.connect(...)` → `run_completed`.
- `current_lap_time` → `run_clock`, `lap_earnings` references if any → `run_earnings` (currently none are read directly — only `earn_rate`, `record_earn_rate`, `checkpoint_index`/`checkpoint_count`, all of which keep their names).
- Remove the `LAP %d/%d` suffix block (`lap_hud.gd:78-80`) and `_director.laps_required` reference — `laps_required` no longer exists.
- Consider whether the top line (`_current_label`, today "the lap clock") should show elapsed or remaining time. Nothing in the grilling session settled this either way — `run_clock` counts up in the data model regardless (see above); whether the label computes `run_duration_seconds - run_clock` for display is a presentation choice, not a data model one.

## Wiring (`scripts/race.gd`)

Alongside the existing:
```gdscript
lap_director.ghost_line_path = circuit.ghost_line_path
```
add:
```gdscript
run_director.run_duration_seconds = circuit.run_duration_seconds
```
and update the `lap_director` local/export name, its type annotation, and `lap_completed.connect(_on_lap_completed)` → `run_completed.connect(_on_run_completed)` (rename the handler too; its body — `if is_record: IncomeRunner.reseat(_circuit)` — is unchanged).

`@export var lap_director_path: NodePath = NodePath("LapDirector")` → `run_director_path` / `NodePath("RunDirector")`, which also means renaming the node in `race.tscn` (and `circuit3.tscn` / `circuit4.tscn` if they reference it directly — check).

## Renames to sweep for (grep-driven, not exhaustively enumerated here)

Search the whole `scripts/` and `scenes/`(`.tscn`) trees for each of these and update every hit, not just the files named above:

- `LapDirector` (type name, in `@onready`/`get_node_or_null(...) as LapDirector` casts, doc comments)
- `LapPhase`, `.COUNTDOWN` / `.RACING` / `.FINISHED` usages
- `lap_completed`, `lap_started`, `lap_aborted`, `lap_director_path`
- `current_lap_time`, `lap_earnings`, `lap_count`, `laps_required`
- The string `"LapDirector"` inside any `.tscn` (node names / `NodePath` literals)

Known hits from a prior grep (not necessarily complete): `purse_hud.gd`, `purse.gd`, `kart.gd`, `income_runner.gd`, `race.gd`, `lap_director.gd`, `coin_field.gd`, `inert_circuit.gd`, `loadout_holder.gd`, `hazard_ghost_field.gd`, `gate_dimming.gd`, `circuit.gd`, `boost_ghost_field.gd`, `checkpoint_prism.gd`, `circuit_entry_trigger.gd`, `circuit_session.gd`, `lap_hud.gd`, `ghost_line.gd`, `pace_ghost.gd`, `countdown_hud.gd`. Most of these will only need a type-annotation rename (e.g. a `LapDirector` cast) with no behavior change — re-verify each rather than assuming from this list alone, it was taken before this spec existed.

## Suggested implementation order

1. `Circuit.run_duration_seconds` (additive, no breakage).
2. `RunDirector` rewrite (rename + the three behavior changes: wrap without ending, Timeout-driven `complete_run`, `RESULTS` waiting on input).
3. `race.gd` wiring.
4. `CountdownHud` / `LapHud`→`RunHud`.
5. Sweep the remaining renames (step 6 in the grep list) — mechanical, do last so the compiler/editor surfaces every remaining `LapDirector` reference as a hard error rather than a silent stale name.
6. Manual playtest: confirm a Run ends cleanly at Timeout mid-checkpoint, Results waits for input, `reset` still aborts correctly during Countdown/Racing and does *not* abort during Results, and a Circuit's `run_duration_seconds` actually gates the Timeout.

## Explicitly unresolved (carried over from the ADR, not blocking this spec)

- Whether the ghost/pace/boost/hazard/income systems need rework for a much longer multi-wrap recording. Left unchanged per scope above; revisit if it plays badly.
- Which control triggers a new Run from Results (`reset` reused vs. a dedicated action) — flagged inline above, pick during implementation.
- Whether the HUD's top line shows elapsed or remaining time — a presentation choice, pick during implementation.
