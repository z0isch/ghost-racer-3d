# Spec: Hazard Ghost Lanes

Settled in a grilling session. Hazard ghosts stop following the player's recorded lap and start
driving fixed lanes measured across the road's own centreline. Each hazard draws a lane once at
spawn and keeps it for its whole life — "one part of the track, driven the whole circuit".

Nothing about hazard *behaviour* changes: same backward-driving oncoming traffic, same swept hit
test, same hop-clears-it immunity, same `hit_slow_multiplier` and `jump_time_bonus`. Only the line
they stand on changes, and the ribbon that warns about it.

## Behaviour change

Today: `HazardGhostField` places hazards along `RunDirector.ghost_line_positions`, sliced by
`_field_range()` to one wrap of the recorded Run, exactly on that line with no lateral offset. A
circuit with no recorded Run gets no hazards.

After: hazards are placed along the road centreline walked out of the circuit's `RoadContainer`,
each offset laterally into one of N evenly-spaced lanes. A circuit with no recorded Run still has a
road, so hazards appear on a circuit's **first ever Run**.

## Scope

**In scope**
- New `RoadCentreline` helper — the road-loop walk extracted out of `BoostGhostField`, plus a road
  width read.
- `BoostGhostField`: switched over to the helper. No behaviour change.
- `HazardGhostField`: centreline instead of ghost line; lane derivation; stratified lane deal;
  per-ghost lane polyline and per-ghost ribbon; `_field_range` and friends deleted.
- `race.tscn`: two new NodePath exports wired on `HazardGhostField`.
- `tests/hazard_ghost_placement_test.gd`: cases for the two new statics.
- Doc comments in `ghost_line.gd` and `run_director.gd` that name `HazardGhostField` as a ghost-line
  consumer.

**Out of scope**
- Hazard driving direction. They still drive the wrap backward, toward the driver. "Traffic to
  overtake" was raised and deliberately not taken.
- Any correlation between a hazard's lane and its speed. The two draws stay independent (grilling
  Q13): a correlated lane becomes a speed signal the player reads instead of reading the car.
- Any change to `place_along`'s arclength stratification, `start_margin`, or `placement_jitter`
  semantics.
- Retuning `pickup_radius_fraction` or `placement_jitter` in `race.tscn`. Both are editor dials and
  the user tunes them after playing (see **Known consequences**).
- Policing lanes against the *true* road edge per sample — the width is read once for the circuit,
  not interpolated per sample (grilling Q7).

## New: `RoadCentreline`

New file, `scripts/road_centreline.gd`, `class_name RoadCentreline`, static functions only. Moved
verbatim out of `boost_ghost_field.gd` — **including their doc comments**, which carry findings that
must not be re-derived:

- `_walk_road_loop` → `walk_loop(road_container) -> PackedVector3Array`. Its comment records why the
  RoadSegment's own curve is walked and *not* the RoadPoint's generated `edge_C` path: `edge_C` is
  re-derived through `RoadSegment.offset_curve`, whose near-90-degree fallback branch hands back a
  handle in the wrong space, bowing the line ~20 m off the tarmac on circuit3's RP_004 corner. This
  comment is the single most valuable thing being moved. One copy, in the helper.
- `_cut_and_orient_loop` → `cut_and_orient(loop, start_line)`.
- `_yaws_from_positions` → `yaws_from_positions(positions)`.
- The `RoadSegment` preload const moves too (it is not registered as a `class_name` by the addon).

New function:

```gdscript
## The circuit's road width in metres, read off an arbitrary RoadPoint as lane_width times its lane
## count. One read for the whole circuit, deliberately not interpolated per sample: width is
## authored per RoadPoint and could in principle vary, but carrying it through the walk means
## plumbing a width array alongside every position. A circuit that narrows mid-lap merely gets lanes
## that are too wide on the narrow stretch — which is exactly BoostGhostField's stated stance on
## hanging ghosts over the kerb. Returns 0.0 where there is no road to measure.
static func width(road_container: RoadContainer) -> float
```

Both circuits today author `lane_width = 8.0`, `lanes = [0]` (one lane), zero shoulders, on every
RoadPoint — so this returns 8.0 uniformly. Shoulders are deliberately excluded: they are 0.0 here
and a shoulder is not road you want traffic parked on.

`BoostGhostField._build_centreline` then calls the helper instead of its own privates, and the four
moved functions are deleted from it. `_lateral_placements` / `_lateral_offset` stay where they are —
they are the boost fan, not centreline machinery, and the hazard lanes are a different rule.

## New statics on `HazardGhostField`

Both pure, both tested (see **Tests**).

```gdscript
## Evenly-spaced lane offsets in metres, signed across the road: as many lanes as fit at one
## car-width apart, spread across the span a car can occupy with all four wheels on tarmac
## (road_half_width - car_radius).
##
## Lane count is derived from car width rather than exported, so the lanes are always exactly as
## separated as the cars are wide. An exported count could be set to 7 on an 8 m road and nothing in
## the code would object to seven overlapping cars reading as a wall.
##
## Consequence, accepted: pickup_radius_fraction now does two jobs — it sets the hit radius and it
## sets the lane layout. Shrinking hazards to get more lanes also makes them easier to miss.
static func lane_offsets(road_width: float, car_width: float) -> Array[float]
```

Arithmetic: `usable = road_width - car_width`; `count = floori(usable / car_width) + 1`; offsets
span `[-usable * 0.5, +usable * 0.5]` at `count` even steps (a single lane sits at 0.0). Guard
`road_width <= 0.0`, `car_width <= 0.0`, and `usable <= 0.0` (a car wider than the road) — each
returns a single centre lane `[0.0]` rather than an empty array, so a hazard always has somewhere to
stand.

`car_width` at the call site is `2.0 * _pickup_radius`, i.e. `2 * pickup_radius_fraction *
kart.sphere_radius`. At today's `pickup_radius_fraction = 3.0` and `sphere_radius = 0.5`: a 3.0 m car
on an 8.0 m road → `usable = 5.0`, `count = 2`, offsets `[-2.5, +2.5]`.

```gdscript
## One lane index per hazard, dealt from a shuffled lane list without replacement and reshuffled
## whenever it runs out. Guarantees no two hazards share a lane while count <= lane_count, and stays
## evenly balanced past it — independent draws would put two of three hazards in the same lane more
## often than not.
static func deal_lanes(count: int, lane_count: int, rng: RandomNumberGenerator) -> Array[int]
```

## `HazardGhostField` changes

### Added exports

```gdscript
## The circuit's RoadContainer, whose RoadSegments' curves are walked into the centreline the lanes
## are measured from. Mirrors BoostGhostField's export of the same name.
@export var road_container_path: NodePath
## The same start-line Marker3D the RunDirector teleports the kart onto, for BoostGhostField's
## identical reason: the loop has no inherent start, and this is where start_margin is measured from.
@export var start_line_path: NodePath
```

Wired in `race.tscn` on the `HazardGhostField` node, to the same paths `BoostGhostField` already
uses: `../Circuit/RoadManager/RoadContainer` and `../Circuit/StartLine`.

### Deleted

- `_field_range()`, `_field_positions()`, `_field_yaws()` — and the whole "one wrap, or the whole
  recording if no wrap finished" concept with them. The centreline is a genuine closed loop; there
  is nothing left to decide.
- `_ribbon_vertices` and `_build_ribbon_vertices()` — the shared, whole-slice vertex array. Replaced
  by a per-hazard one (below).
- The seam clamp in `_update_ribbons` (`_sample_index_back_from`'s clamp-at-slice-start) and its
  comment about the slice's two ends being "metres and a gap apart at best". Ribbons now wrap.

### `_ready`

Gains a deferred `_place_ghosts.call_deferred()`, for `BoostGhostField._ready`'s identical reason:
the RoadSegments are built by the RoadManager's own `_ready`, so the first `countdown_started` has
already fired by the time any road exists.

`_director` is kept, now for `phase` and `countdown_started` only. Nothing reads
`ghost_line_positions` / `ghost_line_yaws` / `checkpoint_count` from this file any more.

### Per-hazard lane polyline

`_place_ghosts` walks the centreline once via `RoadCentreline`, computes `lane_offsets` once, deals
lanes via `deal_lanes`, then for each hazard builds **its own** offset polyline: every centreline
sample pushed along that sample's own right vector (`Basis(Vector3.UP, yaw).x`) by the lane's
offset — the same per-sample right vector `_build_ribbon_vertices` already used, so a lane leans with
the road through a corner instead of staying world-axis-aligned.

Each hazard then carries, on `Hazard`:

```gdscript
var lane_positions: PackedVector3Array  # the centreline offset into this hazard's lane
var lane_yaws: PackedFloat32Array       # re-derived from lane_positions, not copied from the centreline
var lane_cumulative: PackedFloat32Array # arclength along lane_positions
var lane_length: float                  # lane_cumulative's last entry
var ribbon_vertices: PackedVector3Array # two per lane sample, square across the lane
```

Yaws are **re-derived** from the offset polyline rather than copied off the centreline: an outer lane
through a corner turns through the same angle over a longer arc, and copying would leave a hazard's
nose pointing subtly off its own path.

The per-lane `cumulative` is the point of this (grilling Q12): `_advance_ghosts` steps `distance`
against the hazard's own `lane_cumulative`, not a shared centreline one, so `min_speed`/`max_speed`
mean true metres per second in every lane. `_total_length` and the shared `_cumulative` are replaced
by these per-hazard fields.

**Accepted consequence:** an outer-lane hazard's lap is longer than an inner-lane one's, so two
hazards spawned with identical speeds drift out of phase over a Run. This is the chosen trade — the
alternative keeps hazards in phase but makes `min_speed`/`max_speed` mean something different per
lane, at which point they would need renaming.

`place_along` is called once against a representative length. Use the **centreline** length for
placement so the arclength stratification and `start_margin` stay comparable between lanes, then
convert each hazard's chosen distance into its own lane's arclength by the ratio
`lane_length / centreline_length`. This keeps `start_margin = 15.0` meaning roughly the same stretch
of road in every lane.

### Ribbons

`_update_ribbons` slices each hazard's **own** `ribbon_vertices` rather than a shared array, and
wraps the seam: `low` may now run past the start of the lane and continue from its end, via
`fposmod` on the distance. A hazard rounding the start line no longer loses its warning.

The rest is unchanged: solid at the hazard's nose, faded out over `line_lead_length` metres down the
line toward the driver, hidden past `line_visible_distance` or once taken, drawn as a
`PRIMITIVE_TRIANGLE_STRIP` for the GL-Compatibility line-width reason already documented.

Cost: `ghost_count × lane_samples × 2` vertices held, rebuilt only on a re-place — not per frame.

## Tests

`tests/hazard_ghost_placement_test.gd`, to the standard the existing 12 cases already set (pure
statics only; the centreline walk stays untested because it needs a live `RoadContainer`).

`lane_offsets`:
- A 3 m car on an 8 m road gives exactly 2 lanes at ±2.5.
- A 2 m car on an 8 m road gives 4 lanes; a 1.5 m car gives 5.
- Lanes are symmetric about zero and evenly spaced.
- No lane's outer edge passes the road edge: `abs(offset) + car_width * 0.5 <= road_width * 0.5`.
- A car wider than the road, a zero road width, and a zero car width each give a single `[0.0]`.
- An odd lane count includes a lane at exactly 0.0.

`deal_lanes`:
- `count <= lane_count` never repeats a lane.
- `count > lane_count` stays balanced — no lane used more than one time above any other.
- Every dealt index is in range.
- Two different rng seeds produce different deals (the "moves between rolls" invariant the jitter
  tests already assert).
- `count <= 0` or `lane_count <= 0` gives an empty array.

## Docs to correct

- `scripts/ghost_line.gd:27` — names `HazardGhostField` as one of the ghost line's two consumers,
  slicing one wrap out of it. False after this; `PaceGhost` is left as the consumer.
- `scripts/run_director.gd:232` — "Read by HazardGhostField to slice one wrap's worth of line and by
  IncomeRunner to pay the ladder." Drop the hazard half.
- `HazardGhostField`'s class doc — the "stands exactly on the ghost line (no lateral jitter — 'the
  line you set' is the line, not beside it)" paragraph is now the opposite of the truth, as is the
  `_field_range` paragraph. Rewritten to describe lanes on the road centreline.
- `place_along`'s doc says "minus the pose resolution and the lateral offset: a hazard has no side to
  stand on". It now has one. Corrected.

## Known consequences

- **Hazards on a circuit's first Run.** Today a circuit nobody has driven has no hazards, because it
  has no ghost line. It has a road, so it now has traffic. This is the change a playtester notices
  first.
- **2 lanes at today's tuning.** `pickup_radius_fraction = 3.0` in `race.tscn` gives lanes at ±2.5
  only, so with `ghost_count = 3` a Run is always two hazards on one edge and one on the other — the
  dice only choose which edge gets two. `placement_jitter` is `0.0` there too, so the arclength
  spacing is fixed as well. The user intends hazards to be smaller than 3.0 normally; dropping the
  fraction to 2.0 gives 4 lanes with no code change, and raising `placement_jitter` off 0.0 is worth
  doing in the same tuning pass.
- **One dial, two jobs.** `pickup_radius_fraction` sets both the hit radius and the lane layout.
  Chosen deliberately so the lanes cannot disagree with the cars, but it means hazard size can no
  longer be changed for looks alone.
