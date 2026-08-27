# Spec: Tune

Settled in a grilling session. Implements a new `CONTEXT.md` concept — **Tune** — whose glossary
entry is drafted in *Appendix: CONTEXT.md entry* below and is **not yet written into `CONTEXT.md`**.
Write it before or alongside the code; this spec assumes its vocabulary (Tune, Run, record earn
rate, pace ghost, ghost line, circuit loadout, slipstream ghost) and does not re-derive it.

No ADR. The decision record lives in the glossary entry and in this file — a deliberate call, not an
omission. The one ADR-shaped consequence (compounding income) is called out under *Accepted warts*.

## Summary of the behaviour change

Today: the kart's top speed ceiling is `min(tuning.max_speed + _top_speed_bonus, tuning.max_top_speed)`
— `min(10 + bonus, 16)` under `tuning/default.tres`. `_top_speed_bonus` is **per-Run**: banked by
slipstream catches (`SlipstreamGhostField.top_speed_bump`, `1.0` in `race.tscn`) and zeroed by
`KartModel._reset` at every Countdown. Nothing about top speed survives a Run.

After this change: a **Tune** is a permanent, per-circuit top-speed gain the player earns by taking
the record earn rate off a standing pace ghost. It persists in the circuit's `CircuitLoadout`,
survives Runs, scene swaps and the process, and is added into the ceiling alongside the per-Run
bonus:

    min(tuning.max_speed + tune + _top_speed_bonus, tuning.max_top_speed)

**+0.5 m/s per award.** Awarded on `run_completed` when `is_record` is true **and** the Run had an
incumbent pace ghost to take the record from (`RunDirector.raced_ghost != null`). Clamped at the
award site to the ceiling's headroom, `tuning.max_top_speed - tuning.max_speed` (`6.0` today), so a
circuit reaches a full Tune in **12 awarding Runs** and awards nothing thereafter.

## Scope

**In scope**

- `CircuitLoadout`: a sixth field, `tune`, and a widened class doc.
- `KartModel`: a `_tune` term in `_effective_top_speed()`, a setter, a `tune_headroom` read.
- `Kart`: pass-through for both, plus a `tune` read for the debug HUD.
- `race.gd`: seed the kart's tune from the loadout at `_enter_tree`; award, clamp, save and push
  the award to the results screen in the existing `_on_run_completed`.
- `countdown_hud.gd` + `race.tscn`: a gold, non-pulsing subtitle under the Results headline.
- `debug_hud.gd` + `race.tscn`: a `TuneLabel` readout.
- `CONTEXT.md`: a **Tune** entry (drafted below, not yet written).

**Out of scope**

- **Any change to `max_top_speed`, `max_speed`, or `SlipstreamGhostField.top_speed_bump`.** The
  shared ceiling and its current occupants stand exactly as authored. See *Accepted warts*.
- **Automated tests.** Verification is by playtest, which is what the debug HUD readout is for.
- **The open world.** `main.tscn`'s kart is never given a tune and drives at a flat `max_speed`.
- **Income.** `IncomeRunner` and the record earn rate are untouched; income moves only as a
  second-order consequence of records being easier to set.
- **Spending, refunding or displaying the Tune in a shop.** There is no shop UI in this codebase.
- **`GhostLine` format.** Unchanged on disk. A ghost line records positions, not the car that drove
  them.
- **The rewind snapshot.** Deliberately untouched — see *Why `_tune` is not `_top_speed_bonus`*.
- **`CountdownHud/Results/Caption`.** An orphan node in `race.tscn`, referenced by no script. Left
  alone; the new subtitle is a separate node, not a repurposing of it.

## The model

### Trigger

The award fires from `race.gd`'s existing `_on_run_completed(run_time, is_record)` handler, which is
already connected to `RunDirector.run_completed` in `_enter_tree`. Two conditions:

1. `is_record` — the Run took the record. This is the game's only existing meaning of beating the
   pace ghost, it is computed in exactly one place (`RunDirector.complete_run`), and it fires once
   per Run at a well-defined instant.
2. `_director.raced_ghost != null` — there was an incumbent to beat. `complete_run` promotes
   unconditionally when `_record_totals == null`, so **a circuit's first completed Run is a record
   with no pace ghost on the track**. Nothing was beaten, so nothing is awarded. The earliest
   possible award is a circuit's second completed Run.

**Wrecked and rewound Runs award like any other.** `CONTEXT.md` states twice that a rewound Run is
record-eligible like any other and that a Run that wrecks *and* records is headlined as the record;
the earn rate has already priced both. Building an exception here would contradict a stated design
position.

An **Abort** cannot reach this: it never calls `complete_run`.

### Why `race.gd` and not `RunDirector`

`RunDirector` owns Run state and must not learn about autoloads — `race.gd`'s own comments establish
that the scene is the place where circuit-scoped, `LoadoutHolder`-owned data is wired in, so fields
"go on taking their counts from whoever owns them rather than each growing its own dependency on
`LoadoutHolder`". The Tune is exactly such a value. `race.gd` already holds `_circuit`, the
`CircuitLoadout`, the `save_loadout` callable, the `Kart` and the director.

`run_completed` is emitted synchronously from the tail of `complete_run`, so awarding in this handler
*is* awarding at `complete_run` — the ghost line and the Tune become durable in the same frame, and
a crash between Results and leaving the circuit cannot cost the player one but not the other.

### Award, clamp, save

In `race.gd._on_run_completed`, before the existing `IncomeRunner.reseat` branch:

- Bail unless `is_record and run_director.raced_ghost != null`.
- `var headroom: float = _kart.tune_headroom` — `tuning.max_top_speed - tuning.max_speed`, read
  through the kart so `KartTuning` stays the kart's own knowledge and nothing else in the scene
  learns the resource.
- `var awarded: float = minf(TUNE_AWARD, headroom - loadout.tune)` where `TUNE_AWARD` is `0.5`.
- If `awarded <= 0.0`, the circuit is fully tuned: **no award, no save, no subtitle**, and the
  record headline shows alone.
- Otherwise `loadout.tune += awarded`, `save_loadout.call()`, `_kart.tune = loadout.tune`, and push
  `awarded` to the results screen.

The clamp lives here, not in a `CircuitLoadout` setter, because the ceiling is *derived* from
`KartTuning` (`max_top_speed - max_speed`) and `CircuitLoadout` has no way to know that resource —
the same reason its own doc gives for `clock_count` carrying no upper clamp.

The loadout and the `save_loadout` callable are resolved in `_enter_tree` today and used only there;
both need holding on the node so the completion handler can reach them.

`_kart.tune` is updated immediately even though the current Run is over: the ceiling is read every
frame, the kart is frozen in Results, and the next Countdown must start from the new value. Setting
it here means nothing has to remember to re-seed on the way into the next Run.

### Applying it

`KartModel` gains:

    var _tune: float = 0.0

summed in `_effective_top_speed()`:

    func _effective_top_speed() -> float:
        return minf(tuning.max_speed + _tune + _top_speed_bonus, tuning.max_top_speed)

`tune` gets a setter (`maxf(value, 0.0)`) and `tune_headroom` is a read-only
`tuning.max_top_speed - tuning.max_speed`. `Kart` mirrors both as pass-throughs in the style of
`add_top_speed_bonus` / `max_speed`.

Because everything already reads the ceiling through `_effective_top_speed()`, the Tune reaches every
consumer with no further plumbing: the speed clamp in the model's integration step,
`KartState.max_speed`, the `speed_fraction` the HUD bars use, and `ChaseCamera`'s FOV fraction — so a
tuned car sits at a slightly wider FOV from the Countdown, which is correct and is the one place the
Tune is visible before the car has moved.

### Why `_tune` is not `_top_speed_bonus`

Seeding `_top_speed_bonus` from the Tune in `_reset` is a smaller diff and would inherit the rewind
snapshot for free. Rejected: the two quantities have different lifetimes. `_top_speed_bonus` is
"banked so far this Run", is rewindable, and is zeroed at every Countdown; the Tune is constant for
the whole Run and permanent across Runs. Collapsing them makes that field's doc false and makes
`_reset` depend on an externally-injected value, so every future reader has to know that resetting to
zero sometimes doesn't mean zero.

Kept separate, `_tune` is **deliberately absent from `KartModel.capture_state` /
`restore_state`**. It cannot change during a Run, so there is nothing to restore, and adding it to
the snapshot would imply it varies. The rewind spec's state table stays correct as written.

### Results subtitle

`race.gd` calls a new `CountdownHud.set_tune_award(amount)` in the same handler. The hud stores it,
draws it as part of the existing `_draw_results()` reveal, and clears it at the top of its own
`_on_run_completed` so a later non-awarding Run cannot show a stale figure.

Pushed explicitly rather than read off the loadout, so the subtitle does not depend on which
`run_completed` handler ran first — both run inside the same synchronous emit, and the reveal is
drawn from `_process` afterwards, so a push from either order lands before the frame is drawn.

The node is a new `Label`, `CountdownHud/Results/TuneAward`, sitting under the headline (which ends
at `offset_top = -180.0`): full width, centred, font size ~28, the headline's outline treatment,
`record_color` gold, `visible` only when an award was pushed. It does **not** pulse and does **not**
take the headline's pop scale — the headline's own doc argues it must be the single big statement
that outranks four green deltas, so the Tune reads as its consequence rather than as a competitor.
Text: `TUNE +0.5 TOP SPEED`.

### Debug HUD

`DebugHud` gains an optional `TuneLabel`, resolved with `get_node_or_null` and hidden when absent —
the same treatment `_spawn_interval_label` already gets, and for the same reason: this HUD runs in
the open world too, where there is no Tune. Authored into `race.tscn`'s HUD only. Reads
`_target.tune` each frame: `"Tune: +%.1f"`.

This is load-bearing rather than a nicety. With no automated tests, it is the only way to see that
the Tune is accumulating, clamping and surviving a save/load.

## Edge cases

- **First completed Run on a circuit** — record, no ghost, no award. The earliest award is Run two.
- **A record on a fully tuned circuit** — headline alone, no subtitle, no save.
- **An award when less than `TUNE_AWARD` of headroom remains** — awards the remainder, and the
  subtitle reports the awarded amount, not `TUNE_AWARD`. (Does not arise at `0.5` into `6.0`, but
  the code must not assume the division is exact.)
- **A loadout `.tres` saved before this change** — `tune` is absent from the file and takes the
  `@export` default `0.0`. No migration.
- **Running `race.tscn` directly** — falls back to `circuit3` and its real loadout, so the Tune
  behaves exactly as it does through the world's entry flow.
- **A circuit with an empty `loadout_path`** — `LoadoutHolder.for_circuit` hands back a throwaway
  `CircuitLoadout` and `save` is a no-op, so the Tune accumulates in memory for the session and is
  discarded. Matches how every other loadout count already behaves there.
- **The open world** — `main.tscn` never sets `tune`, so it stays `0.0` and the world kart's ceiling
  is unchanged.

## Accepted warts

- **On a well-invested circuit the Tune is close to imperceptible.** `SlipstreamGhostField.top_speed_bump`
  is `1.0` and `Circuit.slipstream_bar_target` is `6`, so a well-driven Run already saturates the
  entire `10 → 16` headroom on catches alone. Sharing that ceiling means a tuned car does not go
  faster — it reaches the same 16 sooner. **Decided deliberately**, with the alternatives (lift the
  ceiling with the Tune, raise `max_top_speed`, cut the slipstream bump) all considered and
  rejected in favour of keeping one shared ceiling. It bites least where it matters most:
  `slipstream_ghost_count` starts at `0`, so on a bare or lightly-invested circuit there are few
  catches and the Tune is fully visible.
- **Income compounds permanently.** Income ghosts pay exactly the record earn rate
  (`docs/adr/0002`), and this makes records easier to set, which raises income, which is never spent
  back. This is the real balance risk in the feature and the one part of it that modifies what
  `0002` established. Accepted rather than decoupled, because "the two dollars-per-second numbers in
  the game agree by construction" is the property that ADR was written to buy.
- **The standing ghost line was driven in a slower car.** The first Run after an award races a
  handicapped ghost — the bar drops the moment it is cleared. Accepted: the ghost visibly falling
  behind *is* the reward. The line is not cleared on award; throwing away the player's recording as
  a prize would be perverse.
- **The Tune's ceiling is derived, not authored.** It moves whenever `max_speed` or `max_top_speed`
  moves. Correct under one shared ceiling, but it means raising `max_top_speed` later silently
  grants every existing save more room to earn into.

## Appendix: CONTEXT.md entry

To be written into `CONTEXT.md` alongside the circuit-loadout entries. `CircuitLoadout`'s own class
doc needs widening from "what one player has **bought**" to cover an earned value, and the **Circuit
loadout** glossary entry needs the same, plus a note that a fifth quantity there is not a count.

> **Tune**:
> The permanent gain in the kart's top speed a circuit has earned, in m/s. Awarded when a Run takes
> the **record earn rate** off a standing **pace ghost** — and only then: a circuit's first
> completed Run sets a record with no ghost on the track, and beats nothing, so it earns nothing. A
> **Wreck** and a **Rewind** are no bar to it, exactly as they are no bar to the record itself.
> Per circuit, and kept in the **circuit loadout** beside the four bought counts, though it is the
> one thing there that was driven for rather than paid for. It has no effect in the **open world**,
> which has no circuit to have earned one.
> It is added onto the same ceiling a **slipstream ghost** catch raises and is clamped by the same
> `max_top_speed`, which means the two share one pool: on a circuit with slipstream ghosts bought,
> a Tune reads as reaching top speed sooner rather than as a faster car, and it is at its most
> visible on a circuit nothing has been bought for yet. Deliberate — one ceiling, one number, and
> the Tune stops being awarded once it fills the room it has.
> Said out loud exactly once, in a gold line under the record headline on **Results**, on the Runs
> that earn one. Never a fifth ranked figure: it is a consequence of the record, not a measurement
> of the Run.
> _Avoid_: Tuning (`KartTuning` and `tuning/default.tres` are authored dials, identical on every
> machine; a Tune is one player's earnings on one circuit), upgrade (nothing is bought), boost,
> top speed bonus (that is the per-Run gain a slipstream catch banks, which a Tune stands beside).
