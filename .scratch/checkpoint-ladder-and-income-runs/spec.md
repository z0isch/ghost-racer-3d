# Spec: Checkpoint ladder, clocks, and income Runs

Implements the model recorded in `CONTEXT.md` (the **Money**, **Income** and **Roles** sections, as
revised) and `docs/adr/0002-checkpoint-ladder-and-income-runs.md`. Read both before implementing —
this spec assumes their vocabulary (checkpoint ladder, clock, clock field, wrap, income ghost) and
doesn't re-derive it.

Follows `docs/adr/0001-timed-circuit-runs.md` and `.scratch/timed-circuit-runs/spec.md`, which
turned laps into Runs and deliberately left every ghost consumer pointed at a recording that had
grown from one short lap into a long multi-wrap line. This is the answer to that open question, plus
the economy rewrite that goes with it.

## Summary of the behavior change

Today: coins stand off the road and pay a flat per-coin value into `run_earnings` and the purse.
Checkpoints pay nothing. A Run's length is exactly `Circuit.run_duration_seconds`. Income ghosts walk
the ghost line, sweep it against the circuit's *currently bought* coins, and pay each coin's value,
resetting their taken-set every time the recording loops.

After this change:

- **Coins are gone.** `CoinField`, `CoinOrigins`, `coin_spin.gd`, `PurseLink`'s coin wiring and every
  `Coins` node are deleted. Nothing stands off the road to be collected for money.
- **Checkpoints pay**, on the **checkpoint ladder**: the *n*th checkpoint taken in a Run pays
  `n × Circuit.base_checkpoint_value`, counted from the Run's first checkpoint and running straight
  through every wrap without resetting. Reset only at Countdown.
- **A new pickup, the clock**, takes the coin field's exact shape but pays in *seconds added to the
  Run's time budget* — never in money, never into the purse. Per-clock value (`seconds`), bought via
  the loadout's renamed `clock_count`, restored at Countdown and **not** on a wrap.
- **A Run's length is no longer fixed**: the Timeout fires at `run_duration_seconds + earned_seconds`.
- **Boost and hazard fields restore and re-roll at every wrap** rather than only at every Countdown.
- **Income ghosts run Runs**: they replay the whole recording end to end, paying the ladder at the
  crossings that recording made, then pop back to sample 0 and restart the ladder at rung 1. Income
  becomes *exactly the record earn rate, per ghost*.

## Scope

**In scope:**

- `CoinField` → `ClockField` (rename + payout-unit change); `CoinOrigins`, `coin_spin.gd`,
  `coin_pickup_test.gd`, `coin_origins_test.gd` deleted or retargeted.
- `RunDirector`: the ladder, checkpoint payment + its pickup signal, the extendable time budget, the
  `wrapped` signal, and recording wrap/crossing indices into the ghost line.
- `GhostLine`: new per-recording index array(s) + migration of lines saved without them.
- `Circuit`: `base_checkpoint_value`.
- `CircuitLoadout`: `coin_count` → `clock_count`.
- `IncomeGhostSweep` / `IncomeRunner`: ladder payouts on precomputed crossings, no sweep.
- `HazardGhostField`, `BoostGhostField`: per-wrap restore/re-roll.
- `PickupPopups`, `PurseLink`, `InertCircuit`, `IncomeGhostView`: retargeting to the new signals and
  the clock's non-green `+10s` popup.
- `race.gd`, `race.tscn`, `main.tscn`: wiring.
- `tools/track/place_features.gd`: `--coins` → `--clocks`, and regenerating both circuits.

**Explicitly out of scope:**

- **The shop.** `Purse.spend` still has no caller (`purse.gd:86`), and nothing in this change adds
  one. The loadout counts stay editable only via the `.tres` files and the existing dev keys.
- **Moving boost ghost placement onto the ghost line.** See *Flagged: boost ghosts stand on the road
  centreline, not the ghost line* below — the per-wrap re-roll is in scope, relocating the field is
  not.
- **Retuning `Circuit.run_duration_seconds`** (currently the 10.0 default on both circuits, unset in
  the `.tres` files). Clocks make Run length variable; picking new base durations is a playtest job.
- **A HUD readout of the ladder rung.** CONTEXT.md's **Pickup popup**: "It is now the only place the
  ladder is legible while driving." Don't add a second one.
- **A global income $/sec readout.** `IncomeRunner.income_rate` stays exposed with no reader, as
  today.

## Data model changes

### `Circuit` (`scripts/circuit.gd`)

Add, alongside `run_duration_seconds`:

```gdscript
## What the first checkpoint of a Run pays; the nth pays n times it (CONTEXT.md's **Checkpoint
## ladder**). One number for the whole circuit and deliberately not per-checkpoint: a checkpoint
## cannot be skipped, so its value can never be a decision. Value that varies is the clock's.
@export var base_checkpoint_value: int = 1
```

Authored content, so it belongs here and not in `CircuitLoadout` — it is not bought.

Both `circuits/circuit3.tres` and `circuits/circuit4.tres` should get an explicit value rather than
riding the default, the same way `run_duration_seconds` should (see out-of-scope note).

### `CircuitLoadout` (`scripts/circuit_loadout.gd`)

`coin_count` → `clock_count`, same setter, same `maxi(value, 0)` floor. Update the class docstring:
the cap is now the circuit's authored *clock* total, clamped in `ClockField._resolve_clocks`.

`loadouts/circuit3.tres` and `loadouts/circuit4.tres` carry `coin_count = 2` / `coin_count = 3` — a
property Godot will silently drop on load once the name changes. Edit both by hand to `clock_count`.

### `GhostLine` (`scripts/ghost_line.gd`)

The ADR calls for "the sample index of each wrap". **Recommended refinement — see *Flagged: how the
income runner finds checkpoint crossings* below**: store the crossings instead and derive wraps from
them, since income needs the crossings and the wraps are the every-*N*th subset of them.

```gdscript
## The sample index in [member positions] at which each checkpoint of the recorded Run was taken,
## in order — the whole Run's worth, running straight through every wrap. Written by RunDirector,
## which is the only thing that knows the moment.
##
## Two consumers, for two different reasons: HazardGhostField slices one wrap's worth of line out
## of it to place a field along, and IncomeRunner pays the checkpoint ladder at these indices
## rather than sweeping anything (CONTEXT.md's **Income**).
@export var checkpoint_samples: PackedInt32Array = PackedInt32Array()

## How many checkpoints the circuit had when this line was recorded, so a wrap boundary is
## checkpoint_samples[k * checkpoints_per_wrap - 1] without a second array that could disagree
## with the first.
@export var checkpoints_per_wrap: int = 0
```

**Migration.** A line saved before this existed has an empty `checkpoint_samples`. Per CONTEXT.md's
**Ghost line**, treat it as a circuit that has never been driven: discard `positions`, `yaws` *and*
`earn_rate` on load. Discarding the rate is required, not tidiness — a pre-ladder rate is a flat-coin
figure with no relationship to a ladder rate, and keeping it would set an unreachable bar that no new
Run could ever promote past.

The two committed lines under `ghost_lines/` will therefore clear themselves on first load. That is
correct and expected; both circuits play their first session with no pace ghost, no hazard ghosts and
no income, exactly as an undriven circuit does.

## `ClockField` (renamed from `CoinField`, `scripts/coin_field.gd` → `scripts/clock_field.gd`)

A rename plus a unit change, and nothing else structurally: the swept test, the `_resolve` /
`live_*_count` clamp, the countdown restore, the direction fallback and the `Coin` inner class all
survive intact. It stays purely spatial and stays ignorant of who listens.

| Old | New | Notes |
|---|---|---|
| `class_name CoinField` | `ClockField` | |
| `signal coin_taken(value: int, position, direction)` | `clock_taken(seconds: float, position, direction)` | **Float**, not int. Seconds, not dollars. Keep the `unbind(2)` warning verbatim in the docstring — it is still the trap. |
| `@export var coins_path` | `clocks_path` | Points at the circuit's `Clocks` node. |
| `@export var live_coin_count` | `live_clock_count` | Same 0 default and same reasoning. |
| `static func segment_takes_coin(...)` | `segment_takes_clock(...)` | Unchanged body. Still the seam the geometry suite tests. |
| `func coin_origins() -> PackedVector3Array` | `clock_origins()` | **Only caller was `BoostGhostField`'s coin-snapping**, which is deleted (below). Delete this method with it rather than leaving a public accessor nothing reads. |
| `_resolve_coins` / `_sweep_coins` | `_resolve_clocks` / `_sweep_clocks` | |
| `class Coin extends RefCounted` with `value: int` | `class Clock` with `seconds: float` | |
| marker metadata `value` | `seconds` | Read as `marker.get_meta("seconds", 10.0)`, assigned straight into the typed field for the same Variant reason the existing comment gives. |

`pickup_radius` and `max_vertical_gap` keep their values and their docstrings, with "coin" swapped for
"clock" — a clock hovers over the road the same way, and the horizontal-only test has the same
leniency to cap.

Fix the two stale-vocabulary docstrings while you're in here: `_on_countdown_started`'s comment still
says "lap completion" and "each lap is offered an identical maximum". It is a Run.

**`CoinOrigins` (`scripts/coin_origins.gd`) is deleted** with no replacement — see *Flagged* below for
why no `CheckpointOrigins` takes its place.

## `RunDirector` (`scripts/run_director.gd`)

The largest set of changes. Four separate things land here.

### 1. The checkpoint ladder

New state and accessor:

```gdscript
## Which rung the next checkpoint pays: 1 for the Run's first, rising by one at every checkpoint
## taken and running straight through every wrap. Reset only in _begin_countdown, alongside
## _run_earnings (CONTEXT.md's **Checkpoint ladder**).
var _ladder_rung: int = 1

## What the circuit's first checkpoint pays. Set by race.gd from Circuit.base_checkpoint_value, the
## same way run_duration_seconds is — the director doesn't know what a Circuit is, only the number.
@export var base_checkpoint_value: int = 1
```

New signal, replacing the director's role as a *listener* on `coin_taken` with its role as the
*emitter* of every payment:

```gdscript
## One checkpoint payment, the instant the checkpoint is taken. The value is this Run's current
## ladder rung times base_checkpoint_value; the position is the checkpoint marker's own origin, so a
## popup traces where the money was; the direction is the swept segment's own travel direction, for
## CoinField.coin_taken's identical reason — "which way is ahead" arrives with the report rather
## than being looked up from a kart, which is what lets one popup serve both this and an income
## ghost's pickup out in the world.
##
## unbind(2) applies here exactly as it did on coin_taken: a one-argument handler connected bare
## fails at emit time and the symptom is a purse that silently stops earning.
signal checkpoint_paid(value: int, position: Vector3, direction: Vector3)
```

`_sweep_pending_checkpoint` needs the segment's travel direction, which it currently computes nothing
of. Lift `CoinField._sweep_direction` into a shared place rather than writing it twice — the simplest
honest move is to make it a static on `ClockField` taking the kart heading as a fallback argument,
and call it from both. Then, in the crossing branch:

```gdscript
	var checkpoint: Checkpoint = _checkpoints[_checkpoint_index]
	...
	var value: int = _ladder_rung * base_checkpoint_value
	_run_earnings += value
	_ladder_rung += 1
	checkpoint_paid.emit(value, checkpoint.origin, direction)

	_checkpoint_index += 1
	if _checkpoint_index >= _checkpoints.size():
		_checkpoint_index = 0 # wrap — a Run only ends by Timeout or Abort, never here
		_recording_wraps.append(_recording_positions.size())
		wrapped.emit()
	_update_gate_visibility()
```

Delete `_on_coin_taken` and the `coin_field_path` export with it. The director no longer needs a
handle on the pickup field at all: the clock field reports to it (below) but the money now originates
here.

### 2. The extendable time budget

```gdscript
## Seconds added to this Run by the clocks taken so far. Cleared at Countdown with everything else.
var _earned_seconds: float = 0.0

## The Run's whole time budget: the circuit's configured duration plus every clock taken so far.
## Not known at Countdown and rises mid-Run, which is exactly what the HUD readout jumping *up*
## is (CONTEXT.md's **Run clock**).
var run_budget: float:
	get: return run_duration_seconds + _earned_seconds
```

`run_remaining` becomes `maxf(0.0, run_budget - _run_clock)`; the Timeout check in `_physics_process`
becomes `if _run_clock >= run_budget:`. `_begin_countdown` clears `_earned_seconds` alongside
`_run_clock` and `_run_earnings`.

New export `clock_field_path` (replacing `coin_field_path`), wired the same way, with the handler:

```gdscript
# No phase guard: ClockField sweeps only while Racing and re-checks the phase inside its own
# deferred callback, so a pickup cannot reach here outside a live Run.
func _on_clock_taken(seconds: float) -> void:
	_earned_seconds += seconds
```

connected as `clock_field.clock_taken.connect(_on_clock_taken.unbind(2))`.

The `push_warning` for a missing field changes meaning: "no ClockField — no Run can be extended", not
"every Run earns nothing". A scene with no clock field still earns fine now.

### 3. The `wrapped` signal and wrap/crossing recording

```gdscript
## Fired the instant the checkpoint sequence wraps back to the first checkpoint. What the countdown
## used to be for the boost and hazard fields: they restore and re-roll on this, so a long Run is
## not one live wrap followed by an empty circuit. The clock field pointedly does not listen — it is
## per-Run (CONTEXT.md's **Clock field**).
signal wrapped()
```

Recording, alongside `_recording_positions` / `_recording_yaws` and subject to the same
"append/clear/duplicate always come in threes" lockstep discipline the existing comment describes:

```gdscript
var _recording_checkpoints: PackedInt32Array = PackedInt32Array()
var _ghost_line_checkpoints: PackedInt32Array = PackedInt32Array()
```

At each crossing, before the ladder lines above, append `_recording_positions.size()` — the index the
*next* sample will occupy, which is the sample taken at the end of the frame the crossing was
detected on. (`_sweep_pending_checkpoint` is queued before `_append_sample` in the same deferred
flush, `run_director.gd:216-217`, so this ordering is already guaranteed.)

`complete_run` promotes all three arrays; the abort branch in `_physics_process` clears all three;
`_save_ghost_line` writes `checkpoint_samples` and `checkpoints_per_wrap = _checkpoint_count`.

New getter `ghost_line_checkpoints`, matching the existing `ghost_line_positions` / `ghost_line_yaws`
pair and their copy-on-write / do-not-mutate contract.

### 4. Ghost line load migration

```gdscript
func _load_ghost_line() -> void:
	...
	# A line recorded before checkpoint_samples existed has no wrap structure and no ladder-era
	# earn rate, so it is treated as a circuit that has never been driven rather than half-loaded:
	# a pre-ladder rate is a flat-coin figure no ladder Run could be ranked against.
	if ghost_line.checkpoint_samples.is_empty():
		return
	_ghost_line_positions = ghost_line.positions
	_ghost_line_yaws = ghost_line.yaws
	_ghost_line_checkpoints = ghost_line.checkpoint_samples
	_record_earn_rate = ghost_line.earn_rate
```

## Boost and hazard fields

### Both

Connect to `wrapped` in addition to `countdown_started`, and re-place on it:

```gdscript
	_director.countdown_started.connect(_on_countdown_started)
	_director.wrapped.connect(_place_ghosts)
```

`_on_countdown_started` keeps its extra job of invalidating `_has_last_kart_position` (the countdown
teleport is what invalidates the swept segment; a wrap is not a teleport, so `wrapped` must **not**
clear it — doing so would drop one frame of sweep at every wrap).

### `HazardGhostField` (`scripts/hazard_ghost_field.gd`)

It already places along `_director.ghost_line_positions`, so this only becomes per-wrap once it slices
one wrap out of that line. `_build_cumulative` and `_rebuild_line_mesh` currently walk the whole
recording — under Runs that is the entire multi-wrap line, which would ribbon the whole Run's path
over itself and spread `ghost_count` hazards across all of it.

Add a wrap slice, derived from the director's checkpoint samples:

```gdscript
## The sample range of one wrap of the ghost line: the first wrap recorded in it, or the whole line
## if the recording holds no complete wrap. The hazards are a per-wrap field, so the ribbon and the
## cumulative table are one wrap's worth and no more (CONTEXT.md's **Wrap**).
func _wrap_range() -> Vector2i:
```

Returning `Vector2i(0, 0)` — no complete wrap — must place no ghosts and draw no ribbon, exactly as an
empty ghost line does today: it is the "no complete wrap recorded" case CONTEXT.md's **Boost ghost**
calls out, and it is not a warning.

`_advance_ghosts` walks the same sliced range, so a hazard that runs off the end of one wrap wraps
back to the start of that wrap rather than the start of the recording.

### `BoostGhostField` (`scripts/boost_ghost_field.gd`)

Two deletions plus the re-roll:

- Delete `coin_field_path`, `coin_snap_radius`, `_coin_field`, `_nearest_coin_within`, and the
  `_lateral_placements` branch that calls it (`boost_ghost_field.gd:486`). `race.tscn:141` already
  sets `coin_snap_radius = 0.0`, so this is dead code today; with coins gone it has nothing to snap
  to. Update the class docstring's "or snapped onto a nearby coin" clause and `place_along`'s, which
  repeats it.
- `_place_ghosts` on `wrapped` gives the re-roll for free — the field is already stratified and
  re-drawn from `_rng` on every call, so a wrap re-rolls it exactly as a countdown does.

`_build_centreline` stays a no-op after its first success, so re-placing per wrap costs one
`place_along` walk, not a road re-walk.

## Income

### `IncomeGhostSweep` (`scripts/income_ghost_sweep.gd`)

The coin sweep goes entirely. `PICKUP_RADIUS` / `MAX_VERTICAL_GAP` go with it — nothing here tests
geometry any more, which is the ADR's "cheaper than a swept test".

```gdscript
class State extends RefCounted:
	var segment_index: int = 0
	var segment_progress: float = 0.0
	## The next entry of the recording's checkpoint_samples this ghost has yet to reach. Reset to 0
	## when the recording pops back to the start — a Timeout followed by a Countdown, which is
	## exactly what restarts the ladder at rung 1 (CONTEXT.md's **Income ghost**).
	var next_crossing: int = 0
```

`advance()` takes `crossings: PackedInt32Array` and `base_value: int` in place of
`coin_positions` / `coin_values`. Inside the whole-segment walk, after `segment_index` advances:

```gdscript
		while (state.next_crossing < crossings.size()
				and crossings[state.next_crossing] <= state.segment_index):
			var pickup := Pickup.new()
			# Rung n at crossing n, one-based: the recording's first checkpoint paid 1 × base and
			# so does the ghost's, which is what makes income exactly the record earn rate.
			pickup.value = (state.next_crossing + 1) * base_value
			# The recorded pose at the crossing — the ghost is standing on the checkpoint prism at
			# that sample, so the popup lands where the money was without this ever needing to know
			# where a checkpoint is.
			pickup.position = positions[crossings[state.next_crossing]]
			pickup.direction = travel_direction
			pickups.append(pickup)
			state.next_crossing += 1
```

and at the recording's end, replacing `state.reset_taken(...)`:

```gdscript
		if state.segment_index >= segment_count:
			state.segment_index = 0
			state.next_crossing = 0
```

`Pickup.index` loses its meaning (it indexed the coin arrays) — drop the field.

`seat()` is unchanged in shape but must also seat `next_crossing` past every crossing the offset
already skipped, or a ghost seated 3/4 of the way through a recording pays rungs 1, 2, 3… for
checkpoints it never crossed. Count the entries of `crossings` at or below the seated `segment_index`.

Update the class docstring: the "chord across a hairpin would collect a coin the recorded line never
approached" paragraph is now about crossings rather than coins, but the same framerate-independence
claim holds and is still worth stating — `advance` still only pays at a whole-segment boundary.

### `IncomeRunner` (`scripts/income_runner.gd`)

- Delete `_coin_origins` and the `CoinOrigins` import.
- `CircuitIncome`: `coin_positions` / `coin_values` → `crossings: PackedInt32Array` and
  `base_value: int`.
- `reseat` reads `ghost_line.checkpoint_samples` into `income.crossings` and
  `circuit.base_checkpoint_value` into `income.base_value`; the whole `loadout.coin_count` clamp block
  goes. What a circuit's income ghosts pay is now a function of the recording and the circuit alone —
  the loadout's only remaining say is `income_ghost_count`.
- The `pickup` signal keeps its `(circuit, position, direction, value)` shape; only what fills it
  changes. `IncomeGhostView._on_pickup` needs no change at all.
- `_advance` passes the new arguments through. Everything else — the per-sample walk, `Purse.add_income`,
  the `earned_since_reseat` / `elapsed_since_reseat` rate — is unchanged.
- Fix the stale docstrings: "which coins it has taken" (class header), "there are no boost ghosts on
  lap 1" (`reseat`).

## Pickup popups, purse link, HUD, open world

### `PickupPopups` (`scripts/pickup_popups.gd`)

Now serves two signals from two nodes:

```gdscript
@export var director_path: NodePath   ## checkpoint_paid → "$12", money green
@export var clock_field_path: NodePath ## clock_taken   → "+10s", pointedly not green
```

Both spawn the same billboarded Label3D with the same lead/rise/lifetime; only the text and colour
differ. Add `clock_color` beside `money_color`, with the reason stated in the docstring: green is the
purse's colour and a clock is not money (CONTEXT.md's **Pickup popup**). **See *Open* below — the
actual colour is undecided.**

`"$%d"` still formats an int. The clock label is `"+%ds"` on a rounded `seconds`, or `"+%.1fs"` if
authored clock values end up fractional — pick when `place_features` authors the first ones.

### `PurseLink` (`scripts/purse_link.gd`)

`coin_field_path` → `director_path`, typed `RunDirector`, connecting
`checkpoint_paid.connect(_on_checkpoint_paid.unbind(2))`. The class docstring's reasoning survives
verbatim with one word swapped: the director cannot reach an autoload without its own ignorance
costing something, so a scene that wants its checkpoints to pay places one of these.

Nothing connects the clock field to the purse. That absence is the point — a clock pays in seconds and
never in money — and is worth a line in the docstring so nobody "fixes" it later.

### `RunHud` (`scripts/run_hud.gd`) and `CountdownHud`

No changes required. `run_remaining` already drives both the top readout and the final-seconds
urgency flash, and both simply follow the budget up when a clock is taken — the readout jumping *up*
is CONTEXT.md's stated intent, not a glitch to smooth.

### `InertCircuit` (`scripts/inert_circuit.gd`)

`coins_path` → `clocks_path`, `bought_coin_alpha` → `bought_clock_alpha`, `loadout.coin_count` →
`loadout.clock_count`, and `_apply_loadout`'s comment retargeted at `ClockField._resolve_clocks`. The
translucent-and-uncollectible treatment is unchanged; a bought clock stands as "a window onto what has
been paid for rather than time lying on the ground" (CONTEXT.md's **Open world**).

### `race.gd` (`scripts/race.gd`)

```gdscript
		run_director.base_checkpoint_value = circuit.base_checkpoint_value
```

alongside the existing `ghost_line_path` / `run_duration_seconds` pair, and

```gdscript
	var clock_field: ClockField = get_node_or_null(clock_field_path) as ClockField
	if clock_field != null:
		clock_field.live_clock_count = loadout.clock_count
```

replacing the coin-field block. `boost_field.loadout` / `save_loadout` / `ghost_count` wiring is
unchanged. `_on_run_completed`'s `IncomeRunner.reseat(_circuit)` is unchanged and now matters more:
a promotion changes the crossings and the rate every income ghost is paid at.

## Scenes and generated content

### `scenes/race.tscn`

- `CoinField` node → `ClockField`, script path and `coins_path` → `clocks_path = NodePath("../Circuit/Clocks")`.
- `BoostGhostField`: drop `coin_field_path` and `coin_snap_radius`.
- `PurseLink`: `coin_field_path` → `director_path = NodePath("../RunDirector")`.
- `PickupPopups`: `coin_field_path` → `director_path` + `clock_field_path`.
- `RunDirector`: `coin_field_path` → `clock_field_path = NodePath("../ClockField")`.

`PurseLink` and `PickupPopups` are authored *above* `RunDirector` in the scene file, so their `_ready`
runs first. That is fine and needs no reordering: both only resolve a NodePath and connect a signal,
neither of which requires the director's own `_ready` to have run. Nothing about `checkpoint_paid`
exists only after `_ready`, unlike `ClockField`'s clock list. Verify rather than assume.

### `main.tscn`

Both `InertCircuit` instances: `coins_path = NodePath("Coins")` → `clocks_path = NodePath("Clocks")`.

### `tools/track/place_features.gd` and the circuits

`--coins N` → `--clocks N`; `COINS_NODE` → `"Clocks"`; `COIN_MESH_RADIUS` / `COIN_THICKNESS` /
`COIN_HEIGHT` / `COIN_SPIN_PHASE_DEG` renamed; `coin_spin.gd` → `scripts/track/clock_spin.gd`; the
marker's `metadata/value = 1` becomes `metadata/seconds` at whatever the authored default is.

Everything the tool does *geometrically* is unchanged and should stay unchanged: the arclength
spacing, the lateral offset, the "clear of every gate" pass, the level yaw-only marker frame (still
required — the spin script turns the mesh about `Vector3.UP` in the marker's parent space, so a marker
rolled with the banking would lay the pickup on its side).

Give the clock a visually distinct mesh from the retired coin disc. A disc that reads as a coin but
pays seconds is exactly the confusion CONTEXT.md's colour rules exist to prevent, and it costs one
`SubResource` block in `_rewrite_scene` to avoid.

**Neither `scenes/circuit3.tscn` nor `scenes/circuit4.tscn` currently has a `Coins` node at all** — the
last generator run placed zero. So there is nothing to migrate, and equally: **until the tool is rerun
with a real `--clocks` count, every Run's budget is exactly `run_duration_seconds` and the whole
clock mechanic is inert.** Rerunning `place_features` on both circuits is part of this change, not a
follow-up.

## Tests

- `tests/coin_pickup_test.gd` → `clock_pickup_test.gd`, `CoinField.segment_takes_coin` →
  `ClockField.segment_takes_clock`. The geometry is untouched, so every existing case stands; the
  docstring's "makes coins slightly harder to collect" reasoning holds verbatim for clocks.
- `tests/coin_origins_test.gd` **deleted** with `CoinOrigins`.
- `tests/income_ghost_sweep_test.gd` rewritten against the new seam: rung *n* at crossing *n*; the
  ladder restarting at 1 when the recording pops; the same elapsed time paying the same money however
  it is chopped into frames (the existing framerate-independence case, retargeted); two ghosts on the
  same recording paying independently; `seat()` skipping the crossings its offset already passed.
- `tests/ghost_line_test.gd`: extend the round trip to cover `checkpoint_samples` and
  `checkpoints_per_wrap` — a `PackedInt32Array` is a new packed type through
  `ResourceSaver`/`ResourceLoader` and is exactly the kind of silent reshaping this suite exists for.
- **New `tests/checkpoint_ladder_test.gd`**: the ladder arithmetic as a static seam — `N` checkpoints
  over `T` seconds is `base·N(N+1)/(2T)`, strictly increasing in `N` at fixed `T` and in `T` at a
  fixed checkpoint interval. This is the ADR's central claim and the only thing in the change that is
  a *formula* rather than a wiring. It needs the rung computation extracted somewhere a `RefCounted`
  TestCase can reach — a static `ladder_value(rung, base)` on `RunDirector` is enough.
- `tests/run_tests.gd`: update the suite list.

## Suggested implementation order

Ordered so the compiler surfaces the next step as a hard error rather than a silent stale name.

1. `Circuit.base_checkpoint_value`, `CircuitLoadout.clock_count`, `GhostLine`'s new arrays, and the
   two `loadouts/*.tres` edits. All additive or trivially mechanical.
2. `RunDirector`: ladder + `checkpoint_paid`, the budget, `wrapped`, crossing recording, load
   migration. Verify in isolation with the coin field still wired — the director's own payments are
   independent of it.
3. `CoinField` → `ClockField` and delete `CoinOrigins` / `coin_spin.gd`. Everything downstream breaks
   loudly at this point, which is the intent.
4. `PurseLink`, `PickupPopups`, `InertCircuit`, `race.gd`, `race.tscn`, `main.tscn`.
5. `IncomeGhostSweep` / `IncomeRunner`.
6. `HazardGhostField` wrap slicing, then `BoostGhostField` coin-snap removal + per-wrap re-roll.
7. `place_features.gd` and regenerate both circuits with a real clock count.
8. Tests.
9. Manual playtest: a Run's purse climbing faster over its length; the clock readout jumping *up* on a
   pickup; boost and hazard fields visibly re-rolling at each wrap while clocks stay taken; the open
   world showing bought clocks translucent; income ghosts leaving a rising trail of popups and popping
   to the start line at staggered moments.

## Flagged: how the income runner finds checkpoint crossings

**Refines ADR-0002.** The ADR says `GhostLine` gains "the sample index of each wrap … read by the
boost and hazard fields for per-wrap placement — income does not need it", and that income's crossings
"are precomputed once at reseat". It does not say *from what*. `IncomeRunner` is an autoload with no
scene tree — during a race the open world does not exist — which is precisely the constraint
`CoinOrigins` was written to satisfy, by walking a circuit's `PackedScene` state without instantiating
it. Recomputing crossings at reseat would need a `CheckpointOrigins` doing the same walk for the
`Checkpoints` node (reading each marker's full `Transform3D`, not just its origin, since the prism
needs forward/right/up), plus a copy of `RunDirector`'s three prism export values, plus
`CheckpointPrism.crossed` replayed over every recorded segment.

This spec recommends the alternative: **the run director writes the crossings into the ghost line**,
since it already knows each one exactly, for free, at the moment it happens. That deletes
`CoinOrigins` with no successor, removes two sources that could drift out of agreement with what the
Run actually drove, and makes the wrap indices a derived subset rather than a second array. The cost
is that income now reads an array the ADR said it would not need.

If that trade is rejected, the fallback is a `CheckpointOrigins` modelled on `CoinOrigins` and a
`GhostLine.wrap_samples` array exactly as the ADR describes — everything else in this spec is
unaffected either way.

## Flagged: boost ghosts stand on the road centreline, not the ghost line

**Contradicts CONTEXT.md's `Boost ghost`, and predates this change.** CONTEXT.md says boost ghosts are
"placed automatically along one wrap's worth of the ghost line", that "improving your line moves the
boost with you", and that there are "no boost ghosts before any Run has completed … there is no line
yet". `BoostGhostField` does none of this: it walks the `RoadContainer`'s own centreline
(`_build_centreline`, `_walk_road_loop`) and its docstring argues the case explicitly — "The
centreline is deliberately not the driver's fastest lap: a racing line hugs the apex through a corner
rather than sitting in the middle of the road, and a circuit with no recorded lap yet still has a
road."

Two live positions, and the code's is the one that ships today. This spec **keeps the centreline** and
takes only the per-wrap re-roll, because moving the field onto the ghost line is a real gameplay
change with a real loss (no boost ghosts at all on a circuit's first Run, on top of no pace ghost and
no hazards) and it is not what this ADR is about. That means the ADR's "read by the boost and hazard
fields" is, in practice, read by the hazard field alone.

Whoever picks this up should resolve it in one direction and edit the loser: either move the field
onto the ghost line as its own change, or amend CONTEXT.md's **Boost ghost** entry to describe the
centreline. Leaving the glossary describing code that does not exist is the worst of the three.

## Open, and deliberately not decided here

- **What colour a clock's pickup popup is.** ADR-0002 leaves it open and constrains it only
  negatively: not green, because green is the purse's and a clock is not money. The run clock's own
  white and the final-seconds urgency red are both already spoken for on screen; something in the
  clock's own family that is neither is the obvious direction. Pick during implementation and record
  it in CONTEXT.md's **Pickup popup**.
- **What `base_checkpoint_value` and the authored clock seconds actually are.** Both are balance
  numbers, and the ladder makes them interact: a Run's earnings go as `N²`, so a clock's seconds buy
  progressively more money the later they are taken. Ship the defaults, then tune from a playtest.
- **Whether the recording should stop being appended once a Run's samples exceed some ceiling.** A
  clock-extended Run has no fixed length, and the recording is 16 bytes per physics tick per Run,
  persisted per circuit. At 60 Hz that is ~1 MB per half hour of Run — not a problem yet, and not
  worth solving before clocks exist to make Runs long.

Two of ADR-0002's own open questions are **already settled by CONTEXT.md** and need no decision here:
the Run clock starts at countdown-zero (**Run clock**: "started at countdown-zero"), and the boost and
hazard fields are re-rolled at every wrap rather than merely restored (**Boost ghost**: "restored —
and **re-rolled** — at every wrap").
