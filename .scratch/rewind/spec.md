# Spec: Rewind

Settled in a grilling session. Implements the model recorded in `CONTEXT.md`'s **Rewind** entry and
the revisions to **Run phase**, **Racing**, **Results**, **Condition**, **Wreck** and **Run clock**
that landed alongside it. Read those first — this spec assumes their vocabulary (Rewind, Wreck,
Condition, Run clock, earn rate, ghost line) and does not re-derive it.

No ADR. The decision record lives in the glossary entries above; a deliberate call, not an omission.

## Summary of the behaviour change

Today: a **hazard hit** that takes Condition to zero sets `_wrecked` and calls `complete_run()`
immediately, and the Run is over.

After this change: Condition reaching zero enters a fourth run phase, **`REWIND`**. Everything
freezes — the Run clock, the traffic, the kart. The driver holds an input to scrub the world
backward in real time, up to `max_rewind_seconds` (8.0) or back to the Run's start, whichever comes
first. Releasing the scrub hold resumes `RACING` from the scrubbed-to instant with the whole Run
rolled back to it — there is no separate accept input. Declining takes the Wreck exactly as today.

**The Run clock does not rewind.** That is the entire price of the mechanic: the seconds are spent,
the pace ghost has walked on, and the earn rate absorbs the loss. Consequently:

- Rewinds are **unlimited**. There is no count, no purchase, no HUD budget, and no cap on how many a
  Run may take. A Run that rewinds ten times is a bad Run, not an impossible one.
- The Run stays **the same Run** and remains **fully record-eligible**. No second class of Run.
- Nothing reports it afterwards. Results is untouched, the ghost line stores nothing about it.

## Scope

**In scope**

- `RunDirector`: `RunPhase.REWIND`, the ring buffer, capture/restore orchestration, the scrub,
  recording truncation, `max_rewind_seconds`.
- A duck-typed `capture_state()` / `restore_state()` pair on `Kart`, `ClockField`,
  `BoostGhostField`, `HazardGhostField`, `SlipstreamGhostField`.
- `KartModel`: a state snapshot pair the `Kart` pair delegates to.
- `project.godot`: three new input actions.
- A rewind readout — scrub depth, large, over the road — and the prompt line.
- `race.tscn` / `race.gd`: registering the rewindables with the director.
- `tests/`: a new `rewind_test.gd`.
- `CONTEXT.md`: **done** — the entries listed at the top of this file are already written.

**Out of scope**

- **Rewind outside a Wreck.** No voluntary mid-corner rewind, no rewind on a Timeout or an Abort.
  Deliberate: rewind-anytime changes what driving *is*, and the ghost you are chasing was set under
  the other rules. Left as a separate decision rather than a side effect of this one.
- **RNG reproducibility.** A rewind across a wrap boundary re-deals clock and boost placement rather
  than restoring the deal it rewound past. See *Accepted wart* below.
- **Any Results-screen change.** No rewind count, no headline change, no fifth row.
- **`GhostLine` format.** Unchanged on disk. The recording is truncated in memory, which needs no
  format change.
- **Persistence.** A rewind is entirely per-Run. Nothing new is written to disk.

## The rewindable contract

Duck-typed, `has_method`-checked at resolve time — GDScript has no interfaces, and a base class
would force `ClockField` and the three ghost fields into a shared ancestor they otherwise have no
reason to share.

```gdscript
## Everything mutable this owner holds that a Rewind must be able to put back, as plain data.
func capture_state() -> Dictionary

## Puts back exactly what capture_state() produced. Must tolerate being handed a capture taken
## before nodes were spawned or freed since.
func restore_state(state: Dictionary) -> void
```

**Hard constraint: the returned `Dictionary` must hold no `Node`, `RefCounted` or `Resource`
references — only `bool`, `int`, `float`, `String`, `Vector3`, and packed/typed arrays of those.**
Two reasons, both real: (1) it is what makes every one of these testable headlessly against
`tests/test_case.gd`, which has no scene; (2) a capture that holds a reference to a hazard freed
between capture and restore is a dangling read that will present as an intermittent crash months
later. Enforce it in the test, not with a comment.

The director does **not** reach into field internals. Each field owns its own capture, which is the
same boundary the fields already keep ("it reports each pickup and knows nothing about who cares").

### What each owner captures

| Owner | Captured |
| --- | --- |
| `Kart` | `global_position`, `global_rotation.y`, `_is_jumping`, `_current_surface`, and the whole `KartModel` snapshot below. Not `_current_ground_collider` (a node reference — re-derived by the ground ray on the next frame). |
| `KartModel` | `_forward_speed`, `_steer_angle`, `_rear_slip_angle`, `_brake_strength`, `_brake_slip_influence`, `_boost_credit`, `_boost_bleed`, `_boost_charges`, `_charge_bump`, `_charge_bleed`, `_top_speed_bonus`, `_hop_active`, `_hop_elapsed`, `_yaw_rate`, `_lateral_speed`. Not `_slip_ceiling` / `_steer_ceiling` (derived from tuning each frame) and not `tuning`. |
| `ClockField` | Per clock: `taken`. Plus `_last_kart_centre`, `_last_kart_yaw`, `_has_last_kart_pose`. |
| `BoostGhostField` | Per ghost: `taken`. Plus `_elapsed` and the swept-pose triple. |
| `HazardGhostField` | Per hazard: `distance`, `node.visible` (which is how a hit is marked today — see `_sweep_ghosts`), `ribbon.visible`. Plus `_ghosts.size()`, `_elapsed`, the spawn timer, and the swept-pose triple. |
| `SlipstreamGhostField` | Same shape as `HazardGhostField`. |
| `RunDirector` | `_run_clock` is **excluded by design**. Everything else per-Run: `_run_earnings`, `_run_checkpoints_taken`, `_earned_seconds`, `_ladder_rung`, `_checkpoint_index`, `_wrap_start_clock`, `_wraps_completed`, `_condition`, `_slipstream_taken`, and the recording lengths (see *Recording truncation*). |

**Un-spawning interval traffic.** `HazardGhostField` and `SlipstreamGhostField` append to `_ghosts`
when `spawn_interval_seconds` fires, so a capture's `_ghosts.size()` is a spawn-order watermark. On
restore, `queue_free()` the node and ribbon of every entry past that index and truncate the array.
Without this, each rewind leaves the circuit slightly more crowded than the instant it returns to,
and repeated rewinds make the Run monotonically harder — the exact inverse of what a rewind is for.

Restoring a capture with **more** cars than are currently live cannot happen: cars are only ever
added by the spawn timer and only ever removed by a restore, both of which the director orders.
Assert it rather than handling it.

## The ring buffer

Lives on `RunDirector`. One entry per physics frame while `RACING`:

```gdscript
## Frames of whole-world state, one per physics frame of Racing, oldest first. Bounded by
## max_rewind_seconds — a rewind can never reach past the newest ceil(max_rewind_seconds /
## physics_tick) frames, so nothing older is worth the memory.
var _rewind_frames: Array[Array] = []
```

Each entry is an `Array` of `Dictionary`, positionally matched to `_rewindables` — the resolved,
ordered list of everything implementing the contract, director included.

**Capture point: queued deferred, last in the frame** — after `_sweep_pending_checkpoint` and after
`_append_sample`. This is the single ordering fact most likely to be got wrong and least likely to
be noticed. A capture taken inline, or queued before the sweep, stores a frame in which a clock has
been marked `taken` by the field but the director's `_earned_seconds` has not yet been raised —
restore that and the seconds are gone while the clock stays taken. It presents as "money and time
occasionally vanish on rewind," months later, with no reproduction. Comment it at the call site.

**Cleared in `_begin_countdown`**, alongside `_recording_*`.

Cost: at 60 Hz an 8 s cap is 480 frames. Each frame is ~6 small dictionaries; the two moving fields
dominate at one float and two bools per car. Trivial, and bounded — but bound it explicitly rather
than relying on the cap, because a `spawn_interval_seconds` circuit grows its car count over a Run.

## The phase

```gdscript
enum RunPhase {
	COUNTDOWN,
	RACING,
	REWIND,
	RESUMING,
	RESULTS,
}
```

`REWIND` and `RESUMING` are added **before** `RESULTS` so the enum reads in run order. Each shift
changes the integer value of `RESULTS`, which is fine — nothing serialises a `RunPhase`. Grep for
`RunPhase.` and confirm.

`RESUMING` is a short held beat (`rewind_resume_pause_seconds`, 0.5s) between accepting a Rewind and
Racing actually starting back up — the world is already restored to the accepted instant by the time
this phase begins, so it does nothing but hold everything frozen (kart included) for one more moment
before `RACING`'s own per-frame work resumes. Added as its own phase rather than a timer bolted onto
`RACING`, for the same reason `REWIND` itself is a phase and not a flag: every field already guards
its per-frame work on `phase == RunPhase.RACING`, so a fifth phase stops the run clock, the sweep and
the recording for free, with no per-field change needed.

**Wart this introduced, and the fix**: `Kart.frozen` pins `KartModel._forward_speed` at `0.0` every
physics frame it is held (`_integrate_forward_speed`'s frozen branch) — that is exactly what keeps
the kart visibly still through the pause, but held for `rewind_resume_pause_seconds`' worth of frames
it also silently re-zeroes whatever speed the accepted frame restored. Left alone, every Rewind would
resume from a standstill regardless of what the kart was doing the instant it was accepted. Fixed by
calling `_restore_rewind_frame` on the same accepted frame a second time, the instant before
unfreezing — the world hasn't moved since accept (nothing ticks outside `RACING`), so this is a
no-op everywhere except `_forward_speed`, which it puts back to the accepted value just before the
model is allowed to act on it again.

Every field already guards its per-frame work on `phase == RunPhase.RACING`, so a fourth phase stops
all of them for free — hazards stop advancing, spawn timers stop, sweeps stop, the recording stops.
That is exactly why `REWIND` is a real phase rather than a flag or a reuse of `RESULTS`: reusing
`RESULTS` would stop the world correctly but also put `CountdownHud`'s results screen on the screen.

### Transitions

```
RACING    --Condition hits 0-------->  REWIND
REWIND    --rewind_scrub released-->  RESUMING      (state restored, recording truncated)
RESUMING  --pause elapses----------->  RACING
REWIND    --rewind_decline--------->  RESULTS       (a Wreck: _wrecked = true, complete_run())
REWIND    --reset------------------>  COUNTDOWN     (an Abort — already correct, see below)
RESUMING  --reset------------------>  COUNTDOWN     (an Abort — same guard, see below)
```

`_on_hazard_hit` stops calling `complete_run()`. It sets the phase to `REWIND`, seeds the scrub at
zero depth, and returns. `_wrecked` is set on the **decline** path only.

`reset` needs **no change**: the director's guard is `if _phase != RunPhase.RESULTS and
Input.is_action_just_pressed("reset")`, so `REWIND` and `RESUMING` both fall into the Abort branch
already, discard the partial recording, and re-run the countdown. That is the correct behaviour — a
Run gone badly enough to wreck is often one you would rather restart than salvage, and the same holds
for the brief window after accepting, before Racing has actually resumed. **Add a one-line comment
saying the inclusion is deliberate**, or someone will "fix" it.

`RunPhase.REWIND` and `RunPhase.RESUMING` must both be added to `_physics_process`'s `match`. Neither
ticks the Run clock.

## The scrub

Frozen world, driver-controlled depth.

- `rewind_scrub` held: depth advances at **1× realtime** — one second of holding walks one second
  back. Walk the buffer backward one frame per physics frame and `restore_state` the whole world at
  that frame, so the world genuinely plays backward on screen. This is not a preview: the state is
  live at every step, and accepting is a no-op beyond the phase change.
- Depth clamps at `min(max_rewind_seconds, run_clock)` — the buffer's own length expresses both.
- There is no accept input. **Releasing `rewind_scrub` is the accept**, the instant it happens — the
  world is already live at the scrubbed-to instant, so letting go commits it and resumes `RACING`.
  There is no forward scrub and no re-press-to-continue in v1: once the driver lets go, the Rewind is
  over; over-scrubbing is corrected by driving from there, which is cheap.
- No expiry. The world is frozen, so a timer would be the only clock still running — and charging
  deliberation prices hesitation rather than the mistake.
- Depth **may cross a wrap boundary**. `_wraps_completed`, `_wrap_start_clock` and the un-banked
  wrap bonus (which lives in `_earned_seconds`) all roll back with everything else, so re-crossing
  the line re-fires `wrapped`, `wrap_completed` and `wrap_bonus_paid` legitimately. The wrap readout
  appearing twice for the same wrap number, the second time with a worse time, is correct: the wrap
  really did take longer.

### Accepted wart: the re-dealt wrap

`wrapped` makes `ClockField` and `BoostGhostField` restore and re-roll their placement. Rewinding
past a wrap close restores the pre-wrap placement from the capture; re-crossing the line then rolls
a **fresh** placement rather than the one just rewound past. Pickups visibly move on a stretch of
circuit already driven this wrap.

Accepted rather than fixed. The fix is to capture each field's `_rng.state` (a `u64`, so it drops
into the plain-data contract unchanged) and restore it, making the deal reproducible. Rejected for
v1 as not worth the reach; **do not** instead floor the rewind at the wrap boundary, which was
considered and rejected — a rewind that refuses to work near the start/finish is worse than one that
re-deals. If the re-deal reads badly in play, capturing `_rng.state` is the fix, and it is small.

## Recording truncation

The Run stays record-eligible, so its recording can be promoted to the ghost line — a line the pace
ghost follows, the hazard field seeds itself along, and income ghosts replay as a Run. Untruncated,
a promoted line would contain the drive into the wreck *and* the re-drive.

On accept, truncate to the sample count captured at the rewound-to frame:

- `_recording_positions.resize(n)` and `_recording_yaws.resize(n)` — **always in lockstep**, per the
  existing comment on those fields ("append, clear and duplicate always come in threes").
- `_recording_checkpoints`: drop every trailing entry `>= n`. These are sample indices into
  `_recording_positions`, so a stale one is not a cosmetic bug — it is an out-of-bounds read in
  `_ghost_wrap_time` and in the income runner the moment that line is promoted and reseated.

Capture `_recording_positions.size()` per frame in the director's own `capture_state()`; that single
integer is the truncation point. `_recording_checkpoints` is monotonic, so the drop is a `resize` to
the first index whose value is `>= n`.

## Input

Two new actions in `project.godot`:

| Action | Keyboard | Gamepad | Meaning in `REWIND` |
| --- | --- | --- | --- |
| `rewind_scrub` | same key as `brake` | dedicated face button (`button_index` 2, X/Square) | hold to walk backward; release to commit and resume Racing |
| `rewind_decline` | same key as `use_boost` | same button as `use_boost` | take the Wreck |

The keyboard side still shares physical keys with distinct action names, per the codebase's existing
pattern (the whole `dev_*` block does the same) — one keyboard, one hand on it, no ambiguity about
which action a key means at a given phase. The gamepad side is different: `brake` and `rewind_scrub`
were originally bound to the same face button (`button_index` 1), which on a controller reads as one
physical button meaning two unrelated things depending on phase, in a way a keyboard's much larger
key space does not force. `rewind_scrub` was moved to its own face button (`button_index` 2) to
avoid that overload; `brake` keeps `button_index` 1. `rewind_decline` still shares `use_boost`'s
button — declining only matters in `REWIND`, where boosting has no meaning, so there is no phase
where the shared button is ambiguous. `rewind_decline` must **not** share a key/button with `reset`:
declining keeps the Run's earnings and produces a result, aborting throws both away.

No `rewind_accept` action: releasing `rewind_scrub` is the accept (see **The scrub**).

## On screen

The world is frozen, so this screen competes with nothing.

- **The depth, large, in the middle of the road** — `-3.4s`, updating live as the scrub walks. Drawn
  in the same place and at the same weight as `RunHud`'s final-seconds digit, which is free by
  definition here. This is the number the whole mechanic is variable in, and after this screen it is
  never shown again anywhere.
- **A small instruction line** under it: hold / release to resume / decline. Fine to leave up
  permanently.
- Nothing else. The beat the Wreck already specified — kart frozen where it stopped, nothing else
  drawn — is now this screen's opening.
- **RESUMING** keeps this same screen up, with `"GO!"` standing in for the depth reading — the world
  is still frozen for that one beat, so dropping the screen the instant the scrub is released would
  leave a frozen frame with nothing on it to explain why.

Which node owns it is an implementation call. `CountdownHud` documents itself as owning "what the
middle of the screen says between Runs" and is strictly exclusive between countdown and results —
a rewind is a third exclusive occupant of that same space, so extending it is defensible; a separate
`RewindHud` is equally defensible and keeps that class's stated invariant intact. Pick one and say
why in the class doc.

## Tuning

Two constants on `RunDirector`, both exported:

- `max_rewind_seconds: float = 8.0` — the cap. One number for the game, **not** per-circuit. A dial
  nobody varies is a dial that can disagree with itself; promote it to `Circuit` if a circuit ever
  actually needs a different one.
- `rewind_resume_pause_seconds: float = 0.5` — how long `RESUMING` holds before `RACING` restarts.
  Short on purpose: it is a beat to register the wreck was avoided, not a second countdown.
- No minimum-depth threshold. Wrecking a fraction of a second into a Run offers a rewind with almost
  nothing behind it; that is a degenerate case nobody will hit, and guarding it costs a constant and
  a branch.

## Tests — `tests/rewind_test.gd`

Headless, against `tests/test_case.gd`. The four things that fail *silently*:

1. **Capture round-trip is pure data.** For each rewindable: `capture_state()` returns a Dictionary
   whose values are recursively free of `Node`/`Object` references. This is the constraint the whole
   testable design rests on, so assert it directly rather than trusting review.
2. **Round-trip fidelity.** `capture` → mutate → `restore` → `capture` yields an equal Dictionary,
   per owner.
3. **Truncation lockstep.** Drive a synthetic recording past a checkpoint crossing, rewind to before
   it, truncate, then promote: `_recording_checkpoints` holds no index `>= _recording_positions
   .size()`. This is the crash-shaped one.
4. **Ladder rollback.** Take a checkpoint at rung *n*, rewind past it, retake it: it pays *n* again,
   not *n+1*. Without the rollback this is an unbounded money exploit for anyone who notices.
5. **Interval traffic un-spawns.** Capture at *k* cars, spawn to *k+2*, restore: `_ghosts.size() ==
   k` and the two extra nodes are freed.

Not tested, deliberately: the scrub rate, the cap, and how any of it feels. Those are playtest.

## Flagged

**A rewind leaves no trace after the Run ends.** Results says nothing, the ghost line stores nothing.
A player whose earn rate dropped has no on-screen explanation beyond having been there at the time.
Settled deliberately — the earn rate is the honest report and a fifth Results row ranks nothing —
but it is the one part of this design with no legibility, and it is the first thing to revisit if
players report the rate feeling arbitrary.

**Condition returns as 1, not full.** Accepting a rewind puts Condition back to what it was before
the fatal hit, which is one segment. The very next hazard re-opens the rewind. That is intended and
self-limiting: each loop costs real Run-clock seconds, and the Timeout still ends the Run. Worth
watching in play — if it reads as a death spiral rather than a cost, the lever to reach for is
`max_rewind_seconds`, not a Condition refund.
