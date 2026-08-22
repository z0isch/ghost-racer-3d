# Spec: Hazard Ghost Lanes — Organic Lines

Settled in a grilling session. Supersedes the previous spec at this path (fixed lanes,
`lane_offsets`), which was already stale: `deal_offsets` had replaced `lane_offsets` without the
spec following.

A hazard's lane stops being a constant offset from the road centreline and becomes a *function of
arclength* — a two-harmonic sine wander drawn once per hazard at spawn. The lane weaves across the
road instead of running perfectly parallel to it.

Nothing about hazard *behaviour* changes: same backward-driving oncoming traffic, same swept hit
test, same hop-clears-it immunity, same `hit_slow_multiplier` and `jump_time_bonus`, same
place-once-at-countdown lifecycle. Only the shape of the line changes.

## The problem

`_spawn_ghost` calls `_offset_positions(offset)` with a single scalar held for the hazard's whole
life, so its lane is a perfect equidistant parallel of the centreline. It never crosses the road and
never looks driven.

This is **not** a wrap-to-wrap repetition complaint. The field is boring on the first wrap. That
matters: the lane polyline stays precomputed-once-at-spawn, and the whole cheap architecture
(`lane_positions` / `lane_yaws` / `lane_cumulative` / `ribbon_vertices` built once in
`_spawn_ghost`, sliced per frame) survives untouched.

## Scope

**In scope**
- `HazardGhostField`: new `Wander` inner class, `draw_wander` and `wander_offset_at` statics,
  `deal_phases` replacing `deal_offsets`, `lane_capacity` deleted, `_offset_positions` reshaped, two
  new exports.
- `race.tscn`: `min_speed` and `placement_jitter` retuned on `HazardGhostField`.
- `tests/hazard_ghost_placement_test.gd`: seven new cases.
- Doc corrections listed under **Docs to correct**.

**Out of scope**
- `BoostGhostField` and `RoadCentreline`: untouched. The boost fan (`_lateral_placements` /
  `_lateral_offset`) is a deliberately different rule and stays where it is.
- Hazard driving direction. Still backward, toward the driver.
- Speed variation along the lap. Speed stays one draw per hazard at spawn (see **Rejected**).
- `place_along`'s arclength stratification and `start_margin` semantics.

## Rejected, with reasons

Both of these sound like improvements and are not. Recorded so they are not re-proposed.

- **Curvature-driven lanes or speeds** — hazards cutting apexes, or slowing for corners. Makes every
  hazard's line *correlated*: they all take the same racing line, or they all brake at the same
  corner. A correlated field is a pattern the player learns, which is the opposite of what was asked
  for. Same reasoning as the previous spec's rejection of lane-to-speed correlation.
- **Wander confined to the dealt band** — keeping `deal_offsets`' non-overlap guarantee by letting
  each hazard wander only inside its own band. The guarantee stopped meaning anything the moment
  hazards started moving at different speeds: they already converge and separate longitudinally
  every lap. Keeping the corridor buys a promise already broken, at the cost of most of the effect —
  with `ghost_count = 3` the bands are ~2.7 m wide and the wander would be nearly invisible.

## The wander

### Form

```
offset(s) = a_slow * sin(TAU * n_slow * s / L + phi_slow)
          + a_fast * sin(TAU * n_fast * s / L + phi_fast)
```

`n_slow` and `n_fast` are **integers**, so the wander is periodic in both value and slope over the
loop — no seam handling, no taper, and the start line (where the player looks most) gets no
artificially flattened stretch. It also makes the gradient analytic:

```
max |offset'(s)|  =  (a_slow * n_slow + a_fast * n_fast) * TAU / L
```

which turns the fairness cap below into a scaling factor rather than a clamp pass.

### `s` is centreline arclength

`s` is measured along `centreline_cumulative`, **not** along the hazard's own lane — the lane does
not exist until the offsets have been applied. The lane still closes correctly because centreline
sample 0 and sample N-1 receive the same offset. `_spawn_ghost` therefore needs
`centreline_cumulative` passed in, which it currently is not.

`cut_and_orient` returns the loop *open*: its last sample and its first are ~0.2 m apart and that
gap is not in `lane_cumulative`. The residual seam is sub-metre and is accepted, as it already is
today.

### Sampling resolution is not a concern

`RoadCentreline.walk_loop` uses `Curve3D.get_baked_points()`, whose default bake interval is 0.2 m.
On a ~700 m lap an `n = 13` harmonic has a ~54 m wavelength — roughly 270 samples per period. No
aliasing risk at any harmonic in the ranges below.

### Constants

Consts on `HazardGhostField`, not exports (see **Exports** for why).

| Const | Value | Why |
| --- | --- | --- |
| `WANDER_SLOW_HARMONICS` | `2..4` | 175-350 m wavelength on a ~700 m lap: the broad drift across the road, roughly one visible per straight. |
| `WANDER_FAST_HARMONICS` | `9..13` | 50-90 m: a lane-change-scale twitch, roughly one per corner. |
| `WANDER_SLOW_SHARE` | `0.75` | The fast harmonic carries ~4x the gradient per metre of amplitude, so 25% of the width costs about half the gradient budget. A 50/50 split would put the cap in play on almost every circuit and make the degradation path below the normal case rather than the edge case. |

### Amplitude fit

The half-band is `max((road_width - car_width) * 0.5, 0.0)`, scaled by `lane_wander`. At the scene's
`pickup_radius_fraction = 1.5` and `sphere_radius = 0.5`, `car_width` is 1.5 m, so on an 8 m road the
half-band is **±3.25 m**. Plenty of room; `max_lane_gradient` is the binding constraint, not width.

Amplitudes are **scaled to fit**, never clamped. A clamped sine spends real stretches flat against
the limit, which reintroduces exactly the parallel-to-the-road straight line this change exists to
remove — just at the kerb instead of the centre.

`a_slow + a_fast <= half_band` is an upper bound, not an equality: when the gradient cap bites, the
peak simply does not reach the edge.

### Gradient cap

`max_lane_gradient` is metres of lateral movement per metre of arclength, default **0.06**.

Sized against the *real* warning window, not the ribbon's length. `line_lead_length = 40.0` is 40 m
of lane, consumed at closing speed: a kart at ~30 m/s meeting a hazard at 6 m/s closes at 36 m/s, so
the ribbon is about **1.1 seconds** of warning. At `g = 0.06` the lane moves at most 2.4 m across
during that whole window, so an edge-to-edge traverse always takes longer than one warning length —
the hazard cannot arrive somewhere other than where the ribbon read.

Deliberately an explicit export rather than derived from `line_lead_length` and the half-band:
deriving it means anyone changing the ribbon length for looks silently re-tunes fairness.

The cap also bounds the yaw deviation. `atan(0.06)` is ~3.4 degrees, so a lane-following nose can
never fishtail. If the cars ever *do* look twitchy, that is evidence the cap is too loose, and
fixing it there fixes the path too.

### When the cap binds: shrink the fast harmonic only

```gdscript
var budget: float = max_gradient * loop_length / TAU
var a_slow: float = half_band * WANDER_SLOW_SHARE
var a_fast: float = half_band * (1.0 - WANDER_SLOW_SHARE)

a_fast = clampf((budget - a_slow * n_slow) / n_fast, 0.0, a_fast)
# Only bites if the slow harmonic alone already exceeds the budget.
a_slow = minf(a_slow, budget / n_slow)
```

The gradient sum is dominated by the fast harmonic — its `n` is 3-5x the slow one's, so it
contributes most of the slope and least of the visible width. Spending the budget on the effect you
can actually see is the right trade, and it degrades gracefully: a short circuit gets a pure slow
drift rather than a shrunken version of everything.

**This choice is only visible in one place**, which is why the tests assert it explicitly.

## New API on `HazardGhostField`

```gdscript
## One hazard's drawn lane wander: two sine harmonics over the centreline's own arclength.
## Transient — consumed by _offset_positions at spawn and deliberately not stored on Hazard, since
## the lane polyline it produces is precomputed and the wander is never re-evaluated afterward.
class Wander extends RefCounted:
	var slow_amplitude: float = 0.0
	var slow_harmonic: int = 0
	var slow_phase: float = 0.0
	var fast_amplitude: float = 0.0
	var fast_harmonic: int = 0
	var fast_phase: float = 0.0
```

```gdscript
## Draws one hazard's wander, fitted to the road and capped for readability. [param half_band] is
## the metres either side of the centreline a car may occupy with all four wheels on tarmac, already
## scaled by lane_wander; [param loop_length] is the centreline's own arclength; [param slow_phase]
## comes from deal_phases so no two hazards drift in sync.
##
## Returns an all-zero Wander — a constant, centreline-following lane, this field's behaviour before
## wandering lanes — where half_band <= 0.0 or loop_length <= 0.0.
static func draw_wander(half_band: float, loop_length: float, max_gradient: float,
		slow_phase: float, rng: RandomNumberGenerator) -> Wander
```

```gdscript
## [param wander] evaluated at [param s] metres along the centreline. Periodic over
## [param loop_length] in both value and slope by construction (integer harmonics), so a lane built
## from this closes on itself with no seam.
static func wander_offset_at(wander: Wander, s: float, loop_length: float) -> float
```

```gdscript
## One slow-harmonic phase per hazard, stratified around the circle: [0, TAU) is cut into [param
## count] equal bands, the bands are dealt shuffled and without replacement, and each hazard takes a
## uniform phase within its own band. The same shuffled-pool shape deal_offsets used, for the same
## reason — independent draws let two hazards drift in near-lockstep more often than not.
##
## The slow phase only. The fast harmonic's phase is drawn uniformly: its n already differs per
## hazard (9..13), so two of them cannot stay in sync for more than a fraction of a lap regardless
## of where they start. Sharing one phase across both harmonics would be worse than not stratifying
## at all — every hazard's line would be the same shape, merely rotated around the lap.
static func deal_phases(count: int, rng: RandomNumberGenerator) -> Array[float]
```

## Changes to existing code

### Deleted

- **`deal_offsets`** — replaced by `deal_phases`. Its band machinery existed for the non-overlap
  guarantee, which is being dropped (see **Rejected**).
- **`lane_capacity`** — its entire body is `floori(road_width / car_width)`, and nothing counts cars
  across the road any more. The half-band is computed inline at the call site. Its doc comment's
  warning about "seven overlapping cars reading as a wall" moves onto `max_lane_gradient`'s doc,
  which is where the equivalent trap now lives.

### `_offset_positions`

Takes a `Wander` and the centreline's cumulative instead of a scalar offset:

```gdscript
func _offset_positions(wander: Wander, cumulative: PackedFloat32Array) -> PackedVector3Array
```

Per sample `i`:
`_centreline_positions[i] + Basis(Vector3.UP, _centreline_yaws[i]).x * wander_offset_at(wander, cumulative[i], L)`.
The per-sample right vector is unchanged — a lane still leans with the road through a corner.

### `_place_ghosts`

Replaces the `deal_offsets` call with:

```gdscript
var car_width: float = 2.0 * _pickup_radius
var half_band: float = maxf((RoadCentreline.width(_road_container) - car_width) * 0.5, 0.0) * lane_wander
var phases: Array[float] = deal_phases(ghost_count, _rng)
```

and passes `centreline_cumulative` through to `_spawn_ghost`.

### `_spawn_ghost`

Signature gains `slow_phase` and `centreline_cumulative`; draws its own `Wander` via `draw_wander`
and feeds it to `_offset_positions`. Everything downstream — `lane_yaws` re-derived from
`lane_positions`, `lane_cumulative`, `lane_length`, the
`centreline_distance * (lane_length / centreline_length)` conversion, `ribbon_vertices` — is
unchanged.

Yaws keep following the lane (nothing to change): with a wandering lane this now reads as a driver
actually changing lanes, and the gradient cap bounds it to ~3.4 degrees.

### Exports

```gdscript
## How much of the road a lane may wander across, as a fraction of the width a car can legally
## occupy. 0.0 is a constant-offset lane — a perfect parallel of the centreline, this field's
## behaviour before wandering lanes — which makes it a direct in-editor A/B against the change.
@export_range(0.0, 1.0) var lane_wander: float = 1.0

## Metres of lateral movement per metre of arclength a lane may ask for. Sized against the ~1.1 s of
## real warning a ribbon gives at closing speed, not against its 40 m of length: raising it makes
## traffic swerve into you faster than the ribbon can warn about. It is also the only thing keeping
## the lane layout honest now that nothing counts cars across the road — the old lane_capacity
## comment's "seven overlapping cars reading as a wall" trap lives here instead.
@export var max_lane_gradient: float = 0.06
```

Two exports and no more. The harmonic ranges and the amplitude split stay consts: four dials nobody
can hold in their head is worse than a code edit, and if the split turns out to need tuning that is
evidence it should have been derived, not exported.

Neither goes on `CircuitLoadout` — that is explicitly a record of what a player has *bought*, and
wander is not purchasable. Per-circuit authoring would belong on the circuit resource, and no
circuit has yet asked for a different value.

### `race.tscn` retune

In scope this time, not deferred as editor dials:

- **`min_speed: 0.0 -> 3.0`**. Zero is not a taste dial once lanes wander: a stationary hazard never
  traverses its lane, so the entire wander is invisible on that car — it just sits at one offset,
  identical on every wrap. A config that silently disables the feature for part of the traffic is
  the kind of thing that gets diagnosed as "the wander doesn't work" three sessions later. Not
  raised further: a 3-to-14 m/s spread is a genuinely varied field, and traffic you close on slowly
  is a different hazard from traffic that arrives fast.
- **`placement_jitter: 0.0 -> 0.5`**. At 0.0 three hazards spawn at exactly 1/3-lap spacing, every
  Run. `BoostGhostField` sits at `0.504` in the same scene; this matches it.

## Tests

`tests/hazard_ghost_placement_test.gd`, to the standard the existing cases set — pure statics only.
Seven cases:

1. **Seam** — `wander_offset_at(w, 0.0, L)` equals `wander_offset_at(w, L, L)` within epsilon.
2. **Fit** — `abs(offset(s)) <= half_band` for dense `s` across the loop.
3. **Cap** — max `abs(delta_offset / delta_s)` over dense `s` is at or under `max_gradient`. **Sample
   at 0.1 m**, well under the fast harmonic's wavelength; a coarser stride can miss a violation
   between samples and go quietly green.
4. **Inert at zero** — `half_band = 0.0` (i.e. `lane_wander = 0.0`) gives identically `0.0` at every
   `s`, reproducing the pre-change lane exactly.
5. **Cap binds fast-only** — on a loop short enough that the cap bites, `slow_amplitude` is still at
   its full `half_band * WANDER_SLOW_SHARE` share and only `fast_amplitude` has shrunk. This is the
   only place the shrink policy is observable; without this case, a later "simplification" to
   uniform scaling passes every other test.
6. **Determinism** — the same rng seed gives the same `Wander`; different seeds differ. (The "moves
   between rolls" invariant the jitter tests already assert.)
7. **Degenerate** — `half_band <= 0.0` and `loop_length <= 0.0` each give an all-zero `Wander`;
   `deal_phases` with `count <= 0` gives an empty array, every dealt phase is in `[0, TAU)`, and no
   two of `count` phases fall in the same band.

## Docs to correct

- `HazardGhostField`'s class doc — "a hazard ghost stands on its own lane, a continuous offset
  measured across the road's own centreline, drawn once at spawn" is now only half true. The offset
  is a function of arclength, not a constant. Rewritten.
- `Hazard.lane_positions`' comment — "the centreline offset into this hazard's own lane, drawn once
  at spawn and kept for its whole life — 'one part of the track, driven the whole circuit'". The
  quoted framing is exactly the thing being removed. Rewritten; the drawn-once-and-kept half is
  still true and stays.
- `Hazard.lane_yaws`' comment already explains why yaws are re-derived rather than copied. Still
  true, and much more load-bearing now — leave it.

## Known consequences

- **One dial, two jobs, still.** `pickup_radius_fraction` sets the hit radius and, through
  `car_width`, the half-band the wander fits into. Shrinking hazards widens their wander. Carried
  over unchanged from the previous spec.
- **Hazards can converge.** With the band guarantee gone, two hazards at similar arclengths can
  wander toward each other and briefly read as a rolling roadblock. Accepted: they are at different
  speeds and different arclengths, so it does not persist.
- **The wander is invisible in a screenshot.** It reads as motion across the road relative to the
  driver. Evaluating this change means driving it, and `lane_wander = 0.0` is the A/B.
- **Hazards on a circuit's first Run**, unchanged from the previous spec: the centreline is a real
  closed loop, so a circuit nobody has driven still has traffic.
