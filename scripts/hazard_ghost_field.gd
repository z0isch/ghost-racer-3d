class_name HazardGhostField
extends Node

## Owner of the hazard ghosts: where they are, which are currently taken, and the swept test that
## takes them. Modelled on BoostGhostField, with two differences that follow from being oncoming
## traffic rather than a pickup: a hazard ghost stands on its own lane, a two-harmonic sine wander
## across the road's own centreline arclength, drawn once at spawn and kept for its whole life, and
## it moves, backward along that lane, rather than standing still.
##
## The slow-down lives on the field, not on the ghost, for BoostGhostField's reason: every hazard
## on a circuit costs the same, so there is one multiplier here rather than per-ghost metadata.
##
## Placed at runtime along the circuit's own road centreline ([method _build_centreline], via
## [RoadCentreline]) — a genuine closed loop, unlike the driver's own recorded lap, so a circuit
## nobody has driven yet still has traffic. Re-placed at every countdown; a re-place first frees
## whatever stood there before. A *wrap* does nothing at all to the field — unlike the boost ghosts,
## hazards are neither restored nor re-placed there: a hit is cleared for the rest of the Run, and
## the traffic still standing (including anything only ever jumped, never hit) keeps driving
## straight through the wrap boundary.
##
## Each hazard trails a short ribbon down its own lane ahead of itself ([method _update_ribbons]),
## rather than the field painting the whole wrap red: under Runs the same wrap is driven over and
## over, so a wrap-long ribbon is permanent scenery, where a per-hazard one is a warning about
## traffic that is actually coming.

## One ghost, the instant it is hit head-on. Carries [member hit_time_bonus], on the trial basis
## that member's doc describes, so RunDirector can bank the seconds the same way it banks a clock,
## and position/direction in ClockField.clock_taken's own shape, so PickupPopups can spawn a popup
## for it exactly as it does for that one. There is no companion signal for a hop: clearing a
## hazard cleanly costs nothing and pays nothing, so there is nothing to report.
signal hazard_hit(seconds: float, position: Vector3, direction: Vector3)

## The same imported model every ghost in this game uses. No hazard_car.tscn: the field instances
## this directly, one per placement.
const GHOST_MODEL: PackedScene = preload("res://cars/FBX/SportsCar.fbx")

## The model scale the FBX's own axis correction ([method _spawn_ghost]) is built from, per unit
## of a hazard's own drawn car scale, for BoostGhostField.MODEL_SCALE_PER_FRACTION's identical
## reason and identical derivation.
const MODEL_SCALE_PER_FRACTION: Vector3 = Vector3(-0.1375, 0.15, -0.1)

## 175-350 m wavelength on a ~700 m lap: the broad drift across the road, roughly one visible per
## straight.
const WANDER_SLOW_HARMONIC_MIN: int = 2
const WANDER_SLOW_HARMONIC_MAX: int = 4
## 50-90 m wavelength: a lane-change-scale twitch, roughly one per corner.
const WANDER_FAST_HARMONIC_MIN: int = 9
const WANDER_FAST_HARMONIC_MAX: int = 13
## The fast harmonic carries ~4x the gradient per metre of amplitude, so 25% of the width costs
## about half the gradient budget. A 50/50 split would put the cap in play on almost every circuit
## and make the degradation path below the normal case rather than the edge case.
const WANDER_SLOW_SHARE: float = 0.75

@export var kart_path: NodePath
@export var director_path: NodePath
## The circuit's RoadContainer, whose RoadSegments' curves are walked into the centreline the lanes
## are measured from. Mirrors BoostGhostField's export of the same name.
@export var road_container_path: NodePath
## The same start-line Marker3D the RunDirector teleports the kart onto, for BoostGhostField's
## identical reason: the loop has no inherent start, and this is where arclength 0.0 is measured from.
@export var start_line_path: NodePath
## The circuit's HazardGhosts node: an empty runtime spawn parent. The field owns what stands under
## it; nothing is authored there.
@export var ghosts_path: NodePath
## The scene's ChaseCamera, shaken on a hit ([member hit_shake_trauma]). Left unset, a hit simply
## doesn't shake — matching this field's behaviour before shake existed, the same fallback
## kart_path/director_path leaving unset gets elsewhere in this class.
@export var camera_path: NodePath

## Hazard ghosts on the circuit. Setting it re-places the whole field immediately, for
## BoostGhostField.ghost_count's reason: the door the dev input and any later system both go
## through.
@export var ghost_count: int = 3:
	set(value):
		ghost_count = maxi(value, 0)
		_place_ghosts()

## Seconds of Racing time between each hazard added on top of the standing field — a circuit's
## own traffic can thicken as a Run goes on, rather than staying fixed at [member ghost_count] for
## the whole Run. Per-circuit, set by race.gd from [member Circuit.hazard_spawn_interval_seconds],
## the same way [member ghost_count] is seeded from the loadout. 0.0 (or below) disables
## thickening entirely, reproducing this field's behaviour before it existed.
##
## Counted only while [member RunDirector.phase] is RACING ([method _physics_process]), and not
## reset by [signal RunDirector.wrapped], for the class doc's reason: nothing about standing
## hazards resets on a wrap. Reset only at [method _on_countdown_started], alongside the field
## itself.
@export var spawn_interval_seconds: float = 0.0

## The circuit's own loadout, for BoostGhostField.loadout's identical reason: the dev keys ([method
## _physics_process]) raise or lower its hazard_ghost_count directly. Set by race.gd alongside
## [member ghost_count] itself. Left null, the dev keys fall back to editing [member ghost_count]
## alone.
var loadout: CircuitLoadout = null
## Persists [member loadout] after a dev-key change, for BoostGhostField.save_loadout's identical
## reason. Set by race.gd, bound to the resolved Circuit.
var save_loadout: Callable = Callable()

## Metres of ghost line kept clear either side of the kart's own current position, for
## BoostGhostField.kart_clearance's identical reason: a hazard is never handed right off the kart's
## nose (nor right behind it), including at the moment a Run starts when the kart sits at arclength
## 0.0. Applies to [method _spawn_extra_ghosts] too, not just the field's initial placement — traffic
## thickening off a checkpoint is no less a surprise than traffic at the start would be.
@export var kart_clearance: float = 10.0

## Fraction of its own slot a hazard may wander across at spawn, for BoostGhostField's reason. It
## still drives the whole line afterward — this only varies where in its lap the traffic starts out.
@export_range(0.0, 1.0) var placement_jitter: float = 0.3

## m/s range a hazard ghost may drive backward along the ghost line. Each hazard picks its own
## speed from this range at spawn ([method _spawn_ghost]), so traffic doesn't read as a single
## repeating pace.
@export var min_speed: float = 4.0
@export var max_speed: float = 8.0

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

## Fraction of the half-band a lane's *constant* offset may reach, dealt stratified across the road
## by [method deal_biases] so the field spreads over the full width instead of every lane
## oscillating about the centreline. A constant offset has zero slope, so this buys road-edge
## traffic out of [member max_lane_gradient]'s budget for free — the swerve rate the ribbon has to
## warn about is untouched. What it costs is wander: a lane biased b metres out keeps only
## half_band - |b| to wander within, so the ghosts nearest the kerb hold the straightest lines. That
## is the intended trade — a kerb-hugging lane that also swerved would be the one thing the gradient
## cap exists to forbid. 0.0 is the field's behaviour before biased lanes, every lane centred on the
## centreline, which makes it a direct in-editor A/B against the change.
@export_range(0.0, 1.0) var lane_bias: float = 0.6

## Fraction the kart's forward speed is scrubbed by on a hit. 1.0 stops the kart dead; 0.0 does
## nothing. Kept separate from the ghost's own driving speed: how hard a hit costs you is a
## different dial than how fast the traffic comes at you.
@export var hit_slow_multiplier: float = 0.5
## Seconds added to the Run when a hazard is cleared by driving straight through it ([signal
## hazard_hit]). Paying anything at all for a hit is a trial: it turns every hazard into free time
## rather than a threat to dodge, and whether that reads as generous or as removing the hazard's
## whole point is the thing being tested — its own dial makes that easy to tune down or zero.
## A hop pays nothing at all, by design: clearing a hazard cleanly is the whole reward for it.
@export var hit_time_bonus: float = 0.0
## Trauma ([method ChaseCamera.add_trauma]) added to the camera on a hit. 0.0 disables shake outright
## rather than adding a zero-strength one every hit. Not added on a hop: a hazard cleared cleanly is
## not an impact, so there is nothing for the camera to react to.
@export_range(0.0, 1.0) var hit_shake_trauma: float = 0.4
## Range of car sizes this field spawns, for BoostGhostField.min_car_scale's identical reason and
## identical defaults. Each hazard draws its own scale from this range once, at spawn, and is
## modelled at that same scale — traffic of assorted sizes, each car's silhouette the hitbox it
## stands for.
@export var min_car_scale: float = 3.0
@export var max_car_scale: float = 5.0
## Shrinks the hitbox below the visible model, leaving [member min_car_scale]/[member max_car_scale]
## alone since those also size the model's own scale ([method _spawn_ghost]) and its lane room
## ([method _half_band]). 1.0 makes the capsule exactly the car's measured silhouette; lower values
## give the driver room to graze a hazard's visible edges without being counted as hit.
@export_range(0.0, 1.0) var hitbox_scale: float = 0.7

## Metres of vertical gap the swept test still counts as a hit, for ClockField.max_vertical_gap's
## identical reason: the horizontal-only sweep would otherwise let a hazard be taken from a stretch
## of road that merely passes underneath or beside it at a different height.
@export var max_vertical_gap: float = 5.0

## Alpha wobble, for BoostGhostField's reason: a hazard reads as a ghost rather than traffic to
## swerve for a photo of.
@export var pulse_amplitude: float = 0.12
@export var pulse_hz: float = 1.1
## Warm red, deliberately apart from the pace ghost's blue and the boost ghost's amber/green: three
## ghosts sharing a model and a line, so colour alone tells them apart (CONTEXT.md, **Pace ghost**).
@export var ghost_color: Color = Color(0.95, 0.1, 0.1, 0.55)

## Whether the hazard ribbons are drawn at all. A setter, for ghost_count's reason: one door,
## rather than each segment's own visible flag becoming a second place this can be toggled.
@export var line_visible: bool = true:
	set(value):
		line_visible = value
		_update_ribbons()
## How wide a ribbon is painted, square across the line, as a fraction of its own hazard's hitbox
## width (twice [member Hazard.half_width]) rather than metres: the hazards are traffic of assorted
## sizes ([member min_car_scale]), so a fixed width had the smallest car and the largest trailing
## the same thread, and the ribbon's width said nothing about how much road the thing coming at you
## actually covers. Scaling it off the hitbox rather than the model means the warning tracks what
## the swept test will actually take you on ([member hitbox_scale]).
@export var line_width_fraction: float = 0.25
## Lifted this far above the recorded line, so a ribbon doesn't z-fight the road it was recorded
## driving on.
@export var line_height_offset: float = 0.05
## Deliberately its own colour rather than a read of [member ghost_color]: a ribbon is the stretch
## of line one hazard is about to cover, not the hazard itself, so it is tuned apart. Its alpha is
## the ribbon's overall strength; the fade along the ribbon's own length is the mesh's.
@export var line_color: Color = Color(0.95, 0.1, 0.1, 0.2)
## Metres of line a hazard trails ahead of itself — *down* the line, toward the driver, since a
## hazard drives the wrap backward. This is the whole warning: where the oncoming traffic is and
## which way it is coming. A Run is many wraps long now, so the alternative — the wrap painted red
## end to end — is permanent scenery that says nothing about where a hazard actually is.
@export var line_lead_length: float = 40.0
## Metres from the kart a hazard's ribbon is drawn within. Past it the ribbon is hidden: traffic
## half a circuit away is not a warning, and every hazard showing one at once is the wrap-long
## ribbon again in pieces.
@export var line_visible_distance: float = 120.0

var _kart: Kart
var _director: RunDirector
var _camera: ChaseCamera
var _ghosts_root: Node3D
var _ghosts: Array[Hazard] = []
var _last_kart_centre: Vector3 = Vector3.ZERO
var _last_kart_yaw: float = 0.0
var _has_last_kart_pose: bool = false
## Built once and re-aimed every frame rather than rebuilt, for [Hitbox.Sweep]'s own reason.
var _sweep := Hitbox.Sweep.new()
var _elapsed: float = 0.0
var _road_container: RoadContainer
var _start_line: Node3D
## Seconds of Racing time accumulated toward the next interval spawn ([member
## spawn_interval_seconds]). Reset at every countdown ([method _on_countdown_started]), matching
## [method _place_ghosts]'s own re-place there.
var _spawn_timer: float = 0.0
## The road's own centreline, walked once at the first re-place ([method _build_centreline]) and
## reused at every one after, for BoostGhostField._centreline_positions's identical reason.
var _centreline_positions: PackedVector3Array = PackedVector3Array()
var _centreline_yaws: PackedFloat32Array = PackedFloat32Array()
## Cumulative arc length of [member _centreline_positions] and its own last entry, cached
## alongside it in [method _build_centreline] rather than recomputed by both [method _place_ghosts]
## and [method _spawn_extra_ghosts] — the latter runs off a checkpoint crossing, not once per
## countdown, so recomputing per call would redo the same walk every checkpoint of a Run.
var _centreline_cumulative: PackedFloat32Array = PackedFloat32Array()
var _centreline_length: float = 0.0
# Seeded randomly on creation by Godot and never re-seeded, for BoostGhostField._rng's reason.
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_kart = get_node_or_null(kart_path) as Kart
	_director = get_node_or_null(director_path) as RunDirector
	_camera = get_node_or_null(camera_path) as ChaseCamera
	_ghosts_root = get_node_or_null(ghosts_path) as Node3D
	if _director != null:
		# countdown_started only: a wrap deliberately leaves the field alone (see class doc).
		_director.countdown_started.connect(_on_countdown_started)

	if _ghosts_root == null:
		push_warning("HazardGhostField: no HazardGhosts node — nothing to spawn traffic into.")

	_road_container = get_node_or_null(road_container_path) as RoadContainer
	_start_line = get_node_or_null(start_line_path) as Node3D
	if _road_container == null:
		push_warning("HazardGhostField: no RoadContainer — nothing to spawn traffic along.")

	# Deferred, for BoostGhostField._ready's identical reason: the RoadSegments the centreline is
	# walked from are built by the RoadManager's own _ready, so the first countdown_started has
	# already fired by the time any road exists.
	_place_ghosts.call_deferred()


## Deferred for ClockField's reason: the director runs at the head of the physics frame and the kart
## moves after it. Ghosts are advanced inline, ahead of the sweep, so the sweep tests the position
## a hazard actually occupies this frame rather than last frame's.
##
## The dev inputs live here, not gated on phase, for BoostGhostField's identical reason.
func _physics_process(delta: float) -> void:
	if _director != null and _director.phase == RunDirector.RunPhase.RACING:
		_advance_ghosts(delta)
		_advance_spawn_timer(delta)
		if _kart != null:
			_sweep_ghosts.call_deferred()

	if Input.is_action_just_pressed("dev_hazard_more"):
		_adjust_ghost_count(1)
	if Input.is_action_just_pressed("dev_hazard_fewer"):
		_adjust_ghost_count(-1)


## Raises or lowers [member ghost_count] by [param delta], for BoostGhostField._adjust_ghost_count's
## identical reason and identical shape — the loadout's hazard_ghost_count is the thing raised when
## a loadout is wired up, saved via [member save_loadout], with [member ghost_count] alone edited
## otherwise.
func _adjust_ghost_count(delta: int) -> void:
	if loadout == null:
		ghost_count += delta
		return

	loadout.hazard_ghost_count += delta
	ghost_count = loadout.hazard_ghost_count
	if save_loadout.is_valid():
		save_loadout.call()


## The pulse runs at display rate, for BoostGhostField's identical reason.
func _process(delta: float) -> void:
	_elapsed += delta
	var alpha_scale: float = 1.0 + sin(_elapsed * TAU * pulse_hz) * pulse_amplitude
	var color: Color = ghost_color
	color.a = clampf(color.a * alpha_scale, 0.0, 1.0)

	for hazard: Hazard in _ghosts:
		if not hazard.taken:
			hazard.material.albedo_color = color


## Starting arclength distances for [param count] hazard ghosts along a line of [param total_length]
## metres, one per equal slot of the span left once [param kart_clearance] metres either side of
## [param kart_distance] are excluded — BoostGhostField.place_along's stratification and wraparound
## exclusion, minus the pose resolution: called once against the centreline's own length, with each
## hazard's chosen distance later converted into its own lane's arclength ([method _spawn_ghost]), so
## the arclength stratification and [member kart_clearance] stay comparable between lanes.
##
## Parameter named clearance rather than kart_clearance (which the exported [member kart_clearance]
## already claims on this class), for BoostGhostField.place_along's identical reason.
static func place_along(
	total_length: float,
	count: int,
	kart_distance: float,
	clearance: float,
	rng: RandomNumberGenerator,
	jitter: float,
) -> Array[float]:
	var result: Array[float] = []
	if count <= 0 or total_length <= 0.0:
		return result

	var usable: float = total_length - 2.0 * clearance
	if usable <= 0.0:
		return result

	var slot: float = usable / count
	for i in count:
		var centre: float = kart_distance + clearance + (i + 0.5) * slot
		var target: float = fposmod(centre + rng.randf_range(-0.5, 0.5) * jitter * slot, total_length)
		result.append(target)

	return result


## The arclength on [member _centreline_cumulative] nearest [param point], for [member
## kart_clearance]'s exclusion band. BoostGhostField._kart_arclength's identical squared-distance
## search, duplicated for the same reason it is there: RoadCentreline carries no cumulative array to
## resolve its own nearest index into an arclength.
static func _kart_arclength(
	positions: PackedVector3Array, cumulative: PackedFloat32Array, point: Vector3
) -> float:
	var best_index: int = 0
	var best_distance: float = INF
	for i in positions.size():
		var distance: float = positions[i].distance_squared_to(point)
		if distance < best_distance:
			best_distance = distance
			best_index = i
	return cumulative[best_index]


## The shorter arclength gap between [param a] and [param b] on a closed loop of [param
## total_length] metres — the distance [method _spawn_extra_ghosts] checks a candidate placement
## against, since a hazard exactly opposite the kart across the seam is exactly as far from it as one
## the same distance away without wrapping.
static func _circular_distance(a: float, b: float, total_length: float) -> float:
	var diff: float = absf(fposmod(a - b, total_length))
	return minf(diff, total_length - diff)


## The index of the sample [param distance] metres along the line falls on, capped so the sample
## after it always exists. Shared by the pose walk and the ribbon slice, so a hazard and its own
## ribbon can never disagree about where on the line it is.
static func _sample_index_at(cumulative: PackedFloat32Array, distance: float) -> int:
	var index: int = 0
	while index < cumulative.size() - 2 and cumulative[index + 1] < distance:
		index += 1
	return index


## [param from_index] walked back down the line until it reaches [param distance], or the line's
## start. Backward from a known index rather than [method _sample_index_at]'s scan from zero, since
## the ribbon's two ends are only [member line_lead_length] metres apart while the line itself can
## be minutes of recording long, and this runs per hazard per physics frame.
static func _sample_index_back_from(
	cumulative: PackedFloat32Array,
	from_index: int,
	distance: float,
) -> int:
	var index: int = from_index
	while index > 0 and cumulative[index] > distance:
		index -= 1
	return index


## The pose a hazard driving backward along the line shows at arclength [param distance]:
## BoostGhostField._pose_at's walk, with pi added to the yaw so the ghost faces the direction it is
## actually travelling rather than the lap's own forward.
static func _pose_at(
	positions: PackedVector3Array,
	yaws: PackedFloat32Array,
	cumulative: PackedFloat32Array,
	distance: float,
) -> Transform3D:
	var index: int = _sample_index_at(cumulative, distance)

	var segment_length: float = cumulative[index + 1] - cumulative[index]
	var weight: float = 0.0
	if segment_length > 0.0:
		weight = clampf((distance - cumulative[index]) / segment_length, 0.0, 1.0)

	var position: Vector3 = positions[index].lerp(positions[index + 1], weight)
	var yaw: float = lerp_angle(yaws[index], yaws[index + 1], weight) + PI
	return Transform3D(Basis(Vector3.UP, yaw), position)


## One hazard's drawn lane wander: two sine harmonics over the centreline's own arclength.
## Transient — consumed by _offset_positions at spawn and deliberately not stored on Hazard, since
## the lane polyline it produces is precomputed and the wander is never re-evaluated afterward.
class Wander extends RefCounted:
	var bias: float = 0.0 # constant metres right of the centreline, before either harmonic
	var slow_amplitude: float = 0.0
	var slow_harmonic: int = 0
	var slow_phase: float = 0.0
	var fast_amplitude: float = 0.0
	var fast_harmonic: int = 0
	var fast_phase: float = 0.0


## Draws one hazard's wander, fitted to the road and capped for readability. [param half_band] is
## the metres either side of the centreline a car may occupy with all four wheels on tarmac, already
## scaled by lane_wander; [param loop_length] is the centreline's own arclength; [param slow_phase]
## comes from deal_phases so no two hazards drift in sync; [param bias_fraction] comes from
## deal_biases scaled by lane_bias, and is the share of half_band this lane spends on a constant
## offset before either harmonic gets any.
##
## The bias is taken off the top and the harmonics are fitted to what is left, so bias plus both
## amplitudes never exceeds half_band and a biased lane stays on tarmac by construction rather than
## by a clamp downstream. It is deliberately free of the gradient budget: a constant offset has no
## slope, so pushing traffic to the kerb this way never shortens the warning [member
## max_lane_gradient] is sized against.
##
## Amplitudes are scaled to fit, never clamped — a clamped sine spends real stretches flat against
## the limit, which reintroduces the parallel-to-the-road straight line this exists to remove, just
## at the kerb instead of the centre. When the gradient cap binds, only the fast harmonic shrinks:
## it carries most of the slope and least of the visible width, so the budget goes to the effect you
## can actually see, and a short circuit degrades to a pure slow drift rather than a shrunken version
## of everything.
##
## Returns an all-zero Wander — a constant, centreline-following lane, this field's behaviour before
## wandering lanes — where half_band <= 0.0 or loop_length <= 0.0.
static func draw_wander(half_band: float, loop_length: float, max_gradient: float,
		slow_phase: float, bias_fraction: float, rng: RandomNumberGenerator) -> Wander:
	var wander := Wander.new()
	if half_band <= 0.0 or loop_length <= 0.0:
		return wander

	# Assigned before the harmonics because it is what they are fitted around: a lane that spends
	# all of half_band on its bias is a pure kerb-parallel line, which is the correct degenerate
	# case rather than a missing one.
	wander.bias = half_band * clampf(bias_fraction, -1.0, 1.0)
	half_band = maxf(half_band - absf(wander.bias), 0.0)

	wander.slow_harmonic = rng.randi_range(WANDER_SLOW_HARMONIC_MIN, WANDER_SLOW_HARMONIC_MAX)
	wander.fast_harmonic = rng.randi_range(WANDER_FAST_HARMONIC_MIN, WANDER_FAST_HARMONIC_MAX)
	wander.slow_phase = slow_phase
	wander.fast_phase = rng.randf_range(0.0, TAU)

	var budget: float = max_gradient * loop_length / TAU
	var a_slow: float = half_band * WANDER_SLOW_SHARE
	var a_fast: float = half_band * (1.0 - WANDER_SLOW_SHARE)

	# Only bites if the slow harmonic alone already exceeds the budget.
	a_fast = clampf((budget - a_slow * wander.slow_harmonic) / wander.fast_harmonic, 0.0, a_fast)
	a_slow = minf(a_slow, budget / wander.slow_harmonic)

	wander.slow_amplitude = a_slow
	wander.fast_amplitude = a_fast
	return wander


## [param wander] evaluated at [param s] metres along the centreline. Periodic over
## [param loop_length] in both value and slope by construction (integer harmonics), so a lane built
## from this closes on itself with no seam.
static func wander_offset_at(wander: Wander, s: float, loop_length: float) -> float:
	if loop_length <= 0.0:
		return 0.0
	return (wander.bias
		+ wander.slow_amplitude
			* sin(TAU * wander.slow_harmonic * s / loop_length + wander.slow_phase)
		+ wander.fast_amplitude
			* sin(TAU * wander.fast_harmonic * s / loop_length + wander.fast_phase))


## One slow-harmonic phase per hazard, stratified around the circle: [0, TAU) is cut into [param
## count] equal bands, the bands are dealt shuffled and without replacement, and each hazard takes a
## uniform phase within its own band. The same shuffled-pool shape deal_offsets used, for the same
## reason — independent draws let two hazards drift in near-lockstep more often than not.
##
## The slow phase only. The fast harmonic's phase is drawn uniformly: its n already differs per
## hazard (9..13), so two of them cannot stay in sync for more than a fraction of a lap regardless
## of where they start. Sharing one phase across both harmonics would be worse than not stratifying
## at all — every hazard's line would be the same shape, merely rotated around the lap.
static func deal_phases(count: int, rng: RandomNumberGenerator) -> Array[float]:
	var result: Array[float] = []
	if count <= 0:
		return result

	var band_width: float = TAU / count
	var pool: Array[int] = []
	for _i in count:
		if pool.is_empty():
			for band in count:
				pool.append(band)
		var index: int = rng.randi_range(0, pool.size() - 1)
		var band: int = pool[index]
		pool.remove_at(index)
		result.append(band * band_width + rng.randf_range(0.0, band_width))

	return result


## One constant lane offset per hazard, as a fraction of the half-band in [-1, 1], stratified across
## the road exactly as deal_phases stratifies the circle: [-1, 1] is cut into [param count] equal
## bands, the bands are dealt shuffled and without replacement, and each hazard takes a uniform
## fraction within its own band. Independent draws would cluster traffic near the centreline —
## the mean of a uniform draw — which is the whole thing spreading lanes across the road is meant
## to stop.
##
## Signed rather than absolute: the two sides of the road are different lanes, and dealing one band
## set across both is what guarantees a field of two spreads to opposite kerbs rather than doubling
## up on one.
static func deal_biases(count: int, rng: RandomNumberGenerator) -> Array[float]:
	var result: Array[float] = []
	if count <= 0:
		return result

	var band_width: float = 2.0 / count
	var pool: Array[int] = []
	for _i in count:
		if pool.is_empty():
			for band in count:
				pool.append(band)
		var index: int = rng.randi_range(0, pool.size() - 1)
		var band: int = pool[index]
		pool.remove_at(index)
		result.append(-1.0 + band * band_width + rng.randf_range(0.0, band_width))

	return result


## Frees the standing field and places a fresh one on the road's centreline. An empty centreline —
## no RoadContainer wired up, or the walk in [method _build_centreline] failed — yields no ghosts
## rather than a warning here, for BoostGhostField's reason: that warning already fired once, in
## [method _ready].
func _place_ghosts() -> void:
	for hazard: Hazard in _ghosts:
		hazard.node.queue_free()
		# Freed alongside its hazard rather than with it: a ribbon is a sibling of the wrapper, not
		# a child ([method _spawn_ghost]), so nothing else would take it down.
		hazard.ribbon.queue_free()
	_ghosts.clear()

	if _ghosts_root == null or _director == null:
		return

	_build_centreline()
	if _centreline_length <= 0.0:
		return

	var phases: Array[float] = deal_phases(ghost_count, _rng)
	var biases: Array[float] = deal_biases(ghost_count, _rng)
	var kart_distance: float = _current_kart_distance()

	var distances: Array[float] = place_along(
		_centreline_length,
		ghost_count,
		kart_distance,
		kart_clearance,
		_rng,
		placement_jitter,
	)
	for i in distances.size():
		_ghosts.append(_spawn_ghost(phases[i], biases[i] * lane_bias, distances[i],
			_centreline_length, _centreline_cumulative))


## The kart's own current arclength along the centreline, or 0.0 (the start line) with no kart wired
## up or no centreline built yet — [method _place_ghosts]'s and [method _spawn_extra_ghosts]'s
## shared resolution of [member kart_clearance]'s exclusion band.
func _current_kart_distance() -> float:
	if _kart == null or _centreline_cumulative.is_empty():
		return 0.0
	return _kart_arclength(_centreline_positions, _centreline_cumulative, _kart.global_position)


## The lateral room one hazard has, given [param car_half_width] — the road's half-width less half
## its own body, so its silhouette stays on tarmac either way.
##
## Per-hazard, not one band shared by the field. Sizing the band off the widest car scale the field
## could draw confined every narrow hazard to the widest one's lane, which left a margin of road at
## each kerb no hazard could reach and the driver could sit on untouched. A narrow hazard may sit
## further out precisely because it is narrow; a wide one covers the kerb from further in.
##
## Half the car's WIDTH, not half its length: a capsule turns with its lane, so what can hang over
## the kerb is the door, never the nose.
func _half_band(car_half_width: float) -> float:
	return maxf(RoadCentreline.width(_road_container) * 0.5 - car_half_width, 0.0) * lane_wander


## Adds [param count] hazards to the standing field without disturbing it, for [signal
## RunDirector.checkpoint_paid] — unlike [method _place_ghosts] this never frees what is already
## out on the road. Each new hazard's start distance and slow-harmonic phase are drawn uniformly
## rather than through [method place_along]'s stratified slots or [method deal_phases]'ing
## dealt-without-replacement bands: both of those stratify a fixed-size field placed all at once,
## and this is neither — the field it is joining already has hazards out there driving, with no
## span or band count left to stratify around them.
##
## The distance draw is still rejection-sampled against [member kart_clearance]: a checkpoint can
## fire with the kart anywhere on the lap, and traffic thickening is no less a surprise appearing
## right on top of the driver than it would be at the start. A capped retry count rather than an
## unbounded loop, since a clearance wider than the whole lap would otherwise spin forever; the last
## draw is kept regardless, on the same logic [method place_along] uses to hand back nothing rather
## than raise an error when a margin can't be honoured.
func _spawn_extra_ghosts(count: int) -> void:
	if count <= 0 or _ghosts_root == null or _centreline_length <= 0.0:
		return

	const MAX_DRAWS: int = 20
	var kart_distance: float = _current_kart_distance()
	for _i in count:
		var distance: float = _rng.randf_range(0.0, _centreline_length)
		for _draw in MAX_DRAWS - 1:
			if _circular_distance(distance, kart_distance, _centreline_length) >= kart_clearance:
				break
			distance = _rng.randf_range(0.0, _centreline_length)
		var phase: float = _rng.randf_range(0.0, TAU)
		var bias: float = _rng.randf_range(-1.0, 1.0)
		_ghosts.append(_spawn_ghost(phase, bias * lane_bias, distance,
			_centreline_length, _centreline_cumulative))


## Advances [member _spawn_timer] by [param delta] and spawns one hazard for every full [member
## spawn_interval_seconds] it crosses — a while loop rather than a single if, so a stalled frame
## (or an interval shorter than a physics tick) still spawns the right count rather than losing
## the remainder. Disabled outright by a non-positive interval, matching [member
## spawn_interval_seconds]'s own doc.
func _advance_spawn_timer(delta: float) -> void:
	if spawn_interval_seconds <= 0.0:
		return
	_spawn_timer += delta
	while _spawn_timer >= spawn_interval_seconds:
		_spawn_timer -= spawn_interval_seconds
		_spawn_extra_ghosts(1)


## Walks [member _road_container]'s RoadPoints into the circuit's centreline positions/yaws and
## caches them into [member _centreline_positions]/[member _centreline_yaws], for
## BoostGhostField._build_centreline's identical reason and identical shape — a no-op once the walk
## has succeeded once, since the road doesn't change shape mid-session.
func _build_centreline() -> void:
	if not _centreline_positions.is_empty() or _road_container == null:
		return

	var loop: PackedVector3Array = RoadCentreline.walk_loop(_road_container)
	if loop.size() < 2:
		return

	if _start_line != null:
		loop = RoadCentreline.cut_and_orient(loop, _start_line)

	_centreline_positions = loop
	_centreline_yaws = RoadCentreline.yaws_from_positions(loop)
	_centreline_cumulative = _cumulative_lengths(loop)
	_centreline_length = _centreline_cumulative[_centreline_cumulative.size() - 1]


## Cumulative arc length at each sample of [param positions]. Shared by the centreline (once, to
## place hazards) and by every hazard's own lane polyline (once each, at spawn) — [method
## _advance_ghosts] and [method _update_ribbons] walk a hazard's own [member Hazard.lane_cumulative]
## every physics tick, so it is built once here rather than recomputed per frame.
static func _cumulative_lengths(positions: PackedVector3Array) -> PackedFloat32Array:
	var cumulative: PackedFloat32Array = PackedFloat32Array()
	cumulative.append(0.0)
	for i in range(1, positions.size()):
		cumulative.append(cumulative[i - 1] + positions[i - 1].distance_to(positions[i]))
	return cumulative


## [member _centreline_positions] pushed sideways by [param wander] evaluated at each sample's own
## centreline arclength ([param cumulative]), along that sample's own right vector ([method
## Basis(Vector3.UP, yaw).x]) — so a hazard's lane leans with the road through a corner instead of
## staying world-axis-aligned, the same construction [method _build_ribbon_vertices] uses for the
## ribbon's own two edges.
func _offset_positions(wander: Wander, cumulative: PackedFloat32Array) -> PackedVector3Array:
	var loop_length: float = cumulative[cumulative.size() - 1]
	var result: PackedVector3Array = PackedVector3Array()
	result.resize(_centreline_positions.size())
	for i in _centreline_positions.size():
		var right: Vector3 = Basis(Vector3.UP, _centreline_yaws[i]).x
		var offset: float = wander_offset_at(wander, cumulative[i], loop_length)
		result[i] = _centreline_positions[i] + right * offset
	return result


## Two vertices per sample of [param positions], square across it via [param yaws]' own right
## vector — one hazard's own ribbon geometry, built once at spawn and sliced (with the seam wrapped)
## by [method _update_ribbons] every physics tick rather than rebuilt. [param car_half_width] is
## that hazard's own hitbox half-width, which sizes the ribbon ([member line_width_fraction]); half
## the ribbon width is therefore that half-width times the fraction, the fraction being of the car's
## full width.
func _build_ribbon_vertices(
	positions: PackedVector3Array, yaws: PackedFloat32Array, car_half_width: float
) -> PackedVector3Array:
	var vertices: PackedVector3Array = PackedVector3Array()
	if positions.size() < 2:
		return vertices

	var half_width: float = car_half_width * line_width_fraction
	var lift: Vector3 = Vector3.UP * line_height_offset
	for i in positions.size():
		var right: Vector3 = Basis(Vector3.UP, yaws[i]).x
		var centre: Vector3 = positions[i] + lift
		vertices.append(centre + right * half_width)
		vertices.append(centre - right * half_width)
	return vertices


## Redraws every hazard's ribbon: the stretch of its own lane between it and the driver, solid at
## its own nose and faded out [member line_lead_length] metres down the lane, hidden once the hazard
## is taken or further off than [member line_visible_distance].
##
## The lane is a genuine closed loop, so the lead may run past the start of it and continue from its
## end — [param low_distance] wraps via [method fposmod] rather than clamping at the seam the way a
## slice of a one-off recording had to.
##
## Runs at physics rate off the back of [method _advance_ghosts] rather than at display rate with
## the alpha pulse, because it follows the hazards' own motion and a ribbon a frame behind its car
## reads as a gap between the two.
func _update_ribbons() -> void:
	for hazard: Hazard in _ghosts:
		if hazard.ribbon == null:
			continue
		if not line_visible or hazard.taken or hazard.ribbon_vertices.size() < 4:
			hazard.ribbon.visible = false
			continue
		if (_kart != null
				and _kart.global_position.distance_to(hazard.origin) > line_visible_distance):
			hazard.ribbon.visible = false
			continue

		var span: float = minf(line_lead_length, hazard.lane_length)
		if span <= 0.0:
			hazard.ribbon.visible = false
			continue

		var low_distance: float = fposmod(hazard.distance - span, hazard.lane_length)
		var high: int = _sample_index_at(hazard.lane_cumulative, hazard.distance)
		var low: int = _sample_index_at(hazard.lane_cumulative, low_distance)

		var sample_count: int = high - low + 1 if low <= high \
			else (hazard.lane_positions.size() - low) + (high + 1)
		if sample_count < 2:
			hazard.ribbon.visible = false
			continue

		var vertices: PackedVector3Array
		if low <= high:
			vertices = hazard.ribbon_vertices.slice(low * 2, (high + 1) * 2)
		else:
			# Wraps past the seam: the tail of the lane's own vertex array, then its head.
			var tail: PackedVector3Array = hazard.ribbon_vertices.slice(
				low * 2, hazard.lane_positions.size() * 2)
			var head: PackedVector3Array = hazard.ribbon_vertices.slice(0, (high + 1) * 2)
			vertices = tail + head

		var colors := PackedColorArray()
		var span_samples: float = float(sample_count - 1)
		for i in sample_count:
			# Alpha only; the hue and the overall strength are line_color's, applied once by the
			# material and multiplied in. Solid at the hazard (the last sample here) and gone at the
			# far end (the first), so a ribbon reads as something arriving rather than as a lane
			# painted on the road.
			var fade: float = float(i) / span_samples
			colors.append(Color(1.0, 1.0, 1.0, fade))
			colors.append(Color(1.0, 1.0, 1.0, fade))

		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		# A quad strip, not a PRIMITIVE_LINE_STRIP: line primitives render at a fixed 1 px under the
		# GL Compatibility renderer this project targets, which a line width could not affect.
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_COLOR] = colors

		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, arrays)
		mesh.surface_set_material(0, hazard.ribbon.material_override)
		hazard.ribbon.mesh = mesh
		hazard.ribbon.visible = true


func _build_line_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = line_color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# The fade along a ribbon's length is the mesh's own vertex alpha ([method _update_ribbons]);
	# line_color supplies the hue and the overall strength, and the two multiply together.
	material.vertex_color_use_as_albedo = true
	# Both faces: the ribbon is walked in the line's own direction, so a kart looking back along it
	# would otherwise see the strip vanish from the back.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


## Builds one hazard standing in its own lane: a wander drawn from [param half_band], [param
## slow_phase] and [param bias_fraction] ([method draw_wander]) pushes the centreline sideways as a
## function of its own arclength, and the hazard starts at the point [param centreline_distance]
## metres along [param centreline_length] converts to along that lane's own (generally different)
## length. [param bias_fraction] arrives already scaled by [member lane_bias].
##
## Yaws are re-derived from the offset polyline rather than copied off the centreline
## ([RoadCentreline.yaws_from_positions]): an outer lane through a corner turns through the same
## angle over a longer arc, and copying would leave a hazard's nose pointing subtly off its own
## path.
func _spawn_ghost(slow_phase: float, bias_fraction: float,
		centreline_distance: float, centreline_length: float,
		centreline_cumulative: PackedFloat32Array) -> Hazard:
	# Drawn before the lane, because it is what the lane is sized against: how wide this hazard's
	# own body is decides how far out it may sit ([method _half_band]). The lane is sized off the
	# drawn car, the capsule off the hitbox_scale'd one — a hazard forgiven a graze still may not
	# park a wheel off the tarmac.
	var car_scale: float = _rng.randf_range(min_car_scale, maxf(min_car_scale, max_car_scale))
	var model_scale: Vector3 = MODEL_SCALE_PER_FRACTION * car_scale
	var drawn: Vector2 = Hitbox.model_half_extents(model_scale)
	var half_extents: Vector2 = drawn * hitbox_scale
	var wander: Wander = draw_wander(_half_band(drawn.y), centreline_length,
		max_lane_gradient, slow_phase, bias_fraction, _rng)
	var lane_positions: PackedVector3Array = _offset_positions(wander, centreline_cumulative)
	var lane_yaws: PackedFloat32Array = RoadCentreline.yaws_from_positions(lane_positions)
	var lane_cumulative: PackedFloat32Array = _cumulative_lengths(lane_positions)
	var lane_length: float = lane_cumulative[lane_cumulative.size() - 1]
	# An outer-lane hazard's lap is longer than an inner-lane one's, so two hazards spawned with
	# identical speeds drift out of phase over a Run — the chosen trade (see spec's Known
	# consequences): the alternative keeps hazards in phase but makes min_speed/max_speed mean a
	# different true speed per lane.
	var distance: float = centreline_distance * (lane_length / centreline_length)

	var wrapper := Node3D.new()
	_ghosts_root.add_child(wrapper)
	wrapper.global_transform = _pose_at(lane_positions, lane_yaws, lane_cumulative, distance)

	var model: Node3D = GHOST_MODEL.instantiate() as Node3D
	wrapper.add_child(model)
	# The FBX's own axes don't match the road's forward/up/scale, for BoostGhostField._spawn_ghost's
	# identical reason and identical correction, scaled by this hazard's own drawn car scale for the
	# same reason as there too.
	model.transform = Transform3D(Basis().scaled(model_scale), Vector3(0.0, 0.1, 0.0))

	var hazard := Hazard.new()
	hazard.node = wrapper
	hazard.distance = distance
	hazard.lane_positions = lane_positions
	hazard.lane_yaws = lane_yaws
	hazard.lane_cumulative = lane_cumulative
	hazard.lane_length = lane_length
	hazard.ribbon_vertices = _build_ribbon_vertices(lane_positions, lane_yaws, half_extents.y)
	hazard.origin = wrapper.global_position
	hazard.yaw = Hitbox.yaw_of(wrapper.global_transform.basis)
	hazard.half_length = half_extents.x
	hazard.half_width = half_extents.y
	hazard.speed = _rng.randf_range(min_speed, max_speed)
	hazard.material = _build_ghost_material()
	# A sibling of the wrapper, not a child of it: the ribbon's vertices are the lane's own, already
	# in the space _ghosts_root stands in, and parenting them under a wrapper that moves every frame
	# would carry them along with it.
	hazard.ribbon = MeshInstance3D.new()
	hazard.ribbon.visible = false
	hazard.ribbon.material_override = _build_line_material()
	_ghosts_root.add_child(hazard.ribbon)
	_apply_material(model, hazard.material)
	return hazard


## Steps every untaken hazard backward along its own lane by its own speed, past the start of the
## lane and back round to its end — continuous oncoming traffic rather than a single pass, stepped
## against each hazard's own [member Hazard.lane_cumulative] rather than a shared one ([member
## Hazard.lane_length]'s doc), so min_speed/max_speed mean true metres per second in every lane.
func _advance_ghosts(delta: float) -> void:
	for hazard: Hazard in _ghosts:
		if hazard.taken or hazard.lane_length <= 0.0:
			continue
		var step: float = hazard.speed * delta
		hazard.distance = fposmod(hazard.distance - step, hazard.lane_length)
		var pose: Transform3D = _pose_at(
			hazard.lane_positions, hazard.lane_yaws, hazard.lane_cumulative, hazard.distance)
		hazard.node.global_transform = pose
		hazard.origin = pose.origin
		hazard.yaw = Hitbox.yaw_of(pose.basis)

	_update_ribbons()


func _sweep_ghosts() -> void:
	# Re-checked: the director's sweep is queued first and can end the Run inside this same flush.
	if _director.phase != RunDirector.RunPhase.RACING:
		return

	var centre: Vector3 = _kart.hitbox_centre
	var yaw: float = _kart.hitbox_yaw
	# The first Racing frame after a teleport records a position and tests nothing, for
	# BoostGhostField's identical reason.
	if not _has_last_kart_pose:
		_last_kart_centre = centre
		_last_kart_yaw = yaw
		_has_last_kart_pose = true
		return

	var previous: Vector3 = _last_kart_centre
	var previous_yaw: float = _last_kart_yaw
	_last_kart_centre = centre
	_last_kart_yaw = yaw
	_sweep.moved(previous, previous_yaw, centre, yaw,
		_kart.hitbox_half_length, _kart.hitbox_half_width)
	var direction: Vector3 = ClockField.sweep_direction(previous, centre, _kart.global_transform.basis)

	for hazard: Hazard in _ghosts:
		if hazard.taken:
			continue
		if not _sweep.takes(hazard.origin, hazard.yaw, hazard.half_length, hazard.half_width):
			continue
		if absf(centre.y - hazard.origin.y) > max_vertical_gap:
			continue
		# The swept test itself ignores height (see class doc), so a hop clears a hazard by immunity
		# rather than clearance — unlike a hit, the hazard is not taken: it stays on its lane and
		# keeps coming. A hop costs nothing and pays nothing; the obstacle is simply passed, not
		# removed for the next lap around.
		if _kart.is_hopping:
			continue
		hazard.taken = true
		hazard.node.visible = false
		# Here rather than left to the next [method _update_ribbons]: the sweep is deferred and the
		# ribbons were already updated this frame, so waiting would leave a warning hanging in the
		# air for a frame after the thing it warned about was hit.
		hazard.ribbon.visible = false
		_kart.apply_hazard_slow(hit_slow_multiplier)
		if _camera != null and hit_shake_trauma > 0.0:
			_camera.add_trauma(hit_shake_trauma)
		hazard_hit.emit(hit_time_bonus, hazard.origin, direction)


## Re-places the whole field at every countdown, for BoostGhostField._on_countdown_started's
## identical reason.
func _on_countdown_started() -> void:
	_has_last_kart_pose = false
	_spawn_timer = 0.0
	_place_ghosts()


func _build_ghost_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = ghost_color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	return material


func _apply_material(node: Node, material: StandardMaterial3D) -> void:
	var mesh: MeshInstance3D = node as MeshInstance3D
	if mesh != null:
		mesh.material_override = material
	for child: Node in node.get_children():
		_apply_material(child, material)


## Everything a Rewind must put back, as plain data: each standing hazard's own position along its
## (fixed, never-re-evaluated) lane and whether it and its ribbon are visible — visible is how a hit
## is marked today ([method _sweep_ghosts]), so taken is derived from it on restore rather than
## carried separately. [member _ghosts].size() is the spawn-order watermark [method restore_state]
## un-spawns traffic against: interval thickening only ever appends, so a capture's own count is
## exactly how many of today's cars existed at that instant.
func capture_state() -> Dictionary:
	var distances: PackedFloat32Array = PackedFloat32Array()
	var node_visible: PackedByteArray = PackedByteArray()
	var ribbon_visible: PackedByteArray = PackedByteArray()
	distances.resize(_ghosts.size())
	node_visible.resize(_ghosts.size())
	ribbon_visible.resize(_ghosts.size())
	for i in _ghosts.size():
		var hazard: Hazard = _ghosts[i]
		distances[i] = hazard.distance
		node_visible[i] = 1 if hazard.node.visible else 0
		ribbon_visible[i] = 1 if hazard.ribbon.visible else 0
	return {
		"count": _ghosts.size(),
		"distances": distances,
		"node_visible": node_visible,
		"ribbon_visible": ribbon_visible,
		"elapsed": _elapsed,
		"spawn_timer": _spawn_timer,
		"last_kart_centre": _last_kart_centre,
		"last_kart_yaw": _last_kart_yaw,
		"has_last_kart_pose": _has_last_kart_pose,
	}


## Puts back exactly what [method capture_state] produced. Un-spawns every hazard past the
## captured count first — freeing its node and its ribbon, then truncating [member _ghosts] — since
## restoring a capture with MORE cars than are currently live cannot happen (traffic is only ever
## added by the spawn timer and only ever removed by a restore, both director-ordered); asserted
## rather than handled, per the spec this ships against.
func restore_state(state: Dictionary) -> void:
	var count: int = state["count"]
	assert(count <= _ghosts.size(),
		"HazardGhostField: rewind capture holds more cars than are currently live")
	for i in range(_ghosts.size() - 1, count - 1, -1):
		_ghosts[i].node.queue_free()
		_ghosts[i].ribbon.queue_free()
	_ghosts.resize(count)

	var distances: PackedFloat32Array = state["distances"]
	var node_visible: PackedByteArray = state["node_visible"]
	var ribbon_visible: PackedByteArray = state["ribbon_visible"]
	for i in count:
		var hazard: Hazard = _ghosts[i]
		hazard.distance = distances[i]
		hazard.node.visible = node_visible[i] != 0
		hazard.taken = not hazard.node.visible
		hazard.ribbon.visible = ribbon_visible[i] != 0
		if hazard.lane_length > 0.0:
			var pose: Transform3D = _pose_at(
				hazard.lane_positions, hazard.lane_yaws, hazard.lane_cumulative, hazard.distance)
			hazard.node.global_transform = pose
			hazard.origin = pose.origin
			hazard.yaw = Hitbox.yaw_of(pose.basis)

	_elapsed = state["elapsed"]
	_spawn_timer = state["spawn_timer"]
	_last_kart_centre = state["last_kart_centre"]
	_last_kart_yaw = state["last_kart_yaw"]
	_has_last_kart_pose = state["has_last_kart_pose"]
	_update_ribbons()


## One hazard, resolved at spawn. RefCounted for ClockField.Clock's reason.
class Hazard extends RefCounted:
	var node: Node3D = null # the wrapper; visibility toggles here
	var distance: float = 0.0 # arclength along this hazard's own lane, decreasing as it drives
	var speed: float = 0.0 # m/s, picked once at spawn from [min_speed, max_speed]
	var origin: Vector3 = Vector3.ZERO
	## Which way this hazard's capsule lies, re-read from its pose every time it is advanced: this
	## car drives, so its hitbox turns through every corner of its lane.
	var yaw: float = 0.0
	## Half this hazard's capsule, nose to tail and kerb to kerb — the model's own footprint under
	## the scale it was drawn at, times [member HazardGhostField.hitbox_scale]; see [method
	## HazardGhostField._spawn_ghost].
	var half_length: float = 0.0
	var half_width: float = 0.0
	var material: StandardMaterial3D = null
	## This hazard's own lane, drawn once at spawn from a wander across the centreline and kept for
	## its whole life — never re-evaluated afterward, even though the wander it came from is a
	## function of arclength rather than a constant offset.
	var lane_positions: PackedVector3Array = PackedVector3Array()
	## Re-derived from [member lane_positions], not copied from the centreline: an outer lane
	## through a corner turns through the same angle over a longer arc, and copying would leave a
	## hazard's nose pointing subtly off its own path.
	var lane_yaws: PackedFloat32Array = PackedFloat32Array()
	## Arclength along [member lane_positions], stepped by [method HazardGhostField._advance_ghosts]
	## instead of a shared centreline cumulative, so min_speed/max_speed mean true metres per second
	## in every lane regardless of how long that lane's own lap is.
	var lane_cumulative: PackedFloat32Array = PackedFloat32Array()
	var lane_length: float = 0.0 # lane_cumulative's last entry
	## Two vertices per sample of [member lane_positions], square across the lane. This hazard's
	## ribbon is a slice of this rather than geometry of its own: the lane does not move, so all
	## that changes per frame is which stretch of it is shown.
	var ribbon_vertices: PackedVector3Array = PackedVector3Array()
	## This hazard's own stretch of ribbon, a sibling of [member node] rather than a child; see
	## HazardGhostField._spawn_ghost. Its mesh is rebuilt every physics frame from a slice of
	## [member ribbon_vertices].
	var ribbon: MeshInstance3D = null
	var taken: bool = false
