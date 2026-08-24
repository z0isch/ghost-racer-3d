class_name SlipstreamGhostField
extends Node

## Owner of the slipstream ghosts: where they are, which are currently taken, and the swept test
## that takes them. Modelled on HazardGhostField, sharing most of its placement engine — the same
## per-lane sine wander, the same checkpoint-driven thickening — with the differences that follow
## from being friendly traffic going the driver's own way rather than oncoming: it is dealt into a
## window of road ahead of the kart rather than stratified over the whole lap ([method
## place_along]), a slipstream ghost drives forward along its own lane instead of backward, its hit
## costs no speed, and driving through it pays a boost charge (HazardGhostField's bump/bleed,
## BoostGhostField's own reward) plus a small permanent top-speed raise, on top of the seconds a
## hazard hop pays.
##
## The reward lives on the field, not on the ghost, for BoostGhostField's reason: every slipstream
## ghost on a circuit is worth the same, so there is one bump/bleed/bonus here rather than per-ghost
## metadata.
##
## Placed at runtime along the circuit's own road centreline ([method _build_centreline], via
## [RoadCentreline]) — a genuine closed loop, unlike the driver's own recorded lap, so a circuit
## nobody has driven yet still has traffic to draft. Re-placed at every countdown; a re-place first
## frees whatever stood there before. A *wrap* does nothing at all to the field, matching
## HazardGhostField's own reason: a slipstream ghost cleared on one wrap is cleared for the rest of
## the Run, and the traffic still standing keeps driving straight through the wrap boundary.
##
## Each ghost trails a short ribbon behind itself down its own lane ([method _update_ribbons]) — a
## motion trail rather than a warning, since there is nothing here to be warned about, but built off
## the identical geometry a hazard ribbon is.

## One ghost, the instant it is driven through. Carries the seconds it pays, in the same shape as
## ClockField.clock_taken and HazardGhostField.hazard_hit, so PickupPopups and RunDirector can
## treat it exactly the same way. The boost charge it also pays is applied directly to the kart
## ([method _take_ghost]) rather than carried on this signal, matching BoostGhostField.ghost_taken's
## own split between a spatial signal and a direct kart call.
signal slipstream_hit(seconds: float, position: Vector3, direction: Vector3)

## The same imported model every ghost in this game uses. No slipstream_car.tscn: the field
## instances this directly, one per placement.
const GHOST_MODEL: PackedScene = preload("res://cars/FBX/SportsCar.fbx")

## The model scale the FBX's own axis correction ([method _spawn_ghost]) is built from, per unit
## of a ghost's own drawn pickup fraction, for BoostGhostField.MODEL_SCALE_PER_FRACTION's identical
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
## are measured from. Mirrors HazardGhostField's export of the same name.
@export var road_container_path: NodePath
## The same start-line Marker3D the RunDirector teleports the kart onto, for HazardGhostField's
## identical reason: the loop has no inherent start, and this is where arclength 0.0 is measured from.
@export var start_line_path: NodePath
## The circuit's SlipstreamGhosts node: an empty runtime spawn parent. The field owns what stands
## under it; nothing is authored there.
@export var ghosts_path: NodePath

## Slipstream ghosts on the circuit. Setting it re-places the whole field immediately, for
## HazardGhostField.ghost_count's reason: the door the dev input and any later system both go
## through.
@export var ghost_count: int = 3:
	set(value):
		ghost_count = maxi(value, 0)
		_place_ghosts()

## Seconds of Racing time between each slipstream ghost added on top of the standing field, for
## HazardGhostField.spawn_interval_seconds's identical reason. Per-circuit, set by race.gd from
## [member Circuit.slipstream_spawn_interval_seconds].
##
## Counted only while [member RunDirector.phase] is RACING ([method _physics_process]), and not
## reset by [signal RunDirector.wrapped], for the class doc's reason: nothing about standing
## traffic resets on a wrap. Reset only at [method _on_countdown_started], alongside the field
## itself.
@export var spawn_interval_seconds: float = 0.0

## The circuit's own loadout, for HazardGhostField.loadout's identical reason: the dev keys ([method
## _physics_process]) raise or lower its slipstream_ghost_count directly. Set by race.gd alongside
## [member ghost_count] itself. Left null, the dev keys fall back to editing [member ghost_count]
## alone.
var loadout: CircuitLoadout = null
## Persists [member loadout] after a dev-key change, for HazardGhostField.save_loadout's identical
## reason. Set by race.gd, bound to the resolved Circuit.
var save_loadout: Callable = Callable()

## The window of ghost line, measured forward from the kart's own current position, a slipstream
## ghost may be placed in. Every ghost draws its own distance uniformly from between the two,
## in metres ahead of the kart ([method place_along]), rather than taking a stratified slot of the
## whole loop the way HazardGhostField does: friendly traffic is only worth anything where the
## driver will actually reach it, so it is dealt into the road ahead instead of spread over the
## lap. [member min_kart_distance] keeps a ghost from ever being handed
## right off the kart's nose (HazardGhostField.kart_clearance's own reason); [member
## max_kart_distance] keeps the rest of it from being dealt somewhere the driver never gets to.
##
## A window wider than the loop just wraps, so the far end can overlap the near end on a short
## circuit; a max at or below the min degenerates to every ghost landing at the min.
@export var min_kart_distance: float = 10.0
@export var max_kart_distance: float = 60.0

## m/s range a slipstream ghost may drive forward along the ghost line. Each ghost picks its own
## speed from this range at spawn ([method _spawn_ghost]), so the traffic doesn't read as a single
## repeating pace.
@export var min_speed: float = 4.0
@export var max_speed: float = 8.0

## How much of the road a lane may wander across, as a fraction of the width a car can legally
## occupy, for HazardGhostField.lane_wander's identical reason.
@export_range(0.0, 1.0) var lane_wander: float = 1.0

## Metres of lateral movement per metre of arclength a lane may ask for, for
## HazardGhostField.max_lane_gradient's identical reason.
@export var max_lane_gradient: float = 0.06

## Fraction of the half-band a lane's constant offset may reach, for HazardGhostField.lane_bias's
## identical reason and identical trade: road-edge traffic bought outside the gradient budget, paid
## for with the wander of the lanes nearest the kerb.
@export_range(0.0, 1.0) var lane_bias: float = 0.6

## m/s the banked charge puts straight into forward speed, above the tuned ceiling, once spent —
## BoostGhostField.bump's identical meaning, paid the instant a slipstream ghost is driven through
## rather than banked for later: there is no button press here, only the catch.
@export var bump: float = 10.0
## m/s^2 the overspeed comes back off at, once the charge is spent — BoostGhostField.bleed's
## identical meaning.
@export var bleed: float = 5.0
## m/s permanently added to the kart's top speed the instant a slipstream ghost is caught, on top
## of the bump/bleed charge above — [method Kart.add_top_speed_bonus], unconditional rather than
## gated on KartTuning.boost_raises_top_speed the way BoostGhostField's own ceiling raise is: that
## flag governs how a *boost pad* ghost's grant is spent (an instant boost vs. a permanent raise),
## a choice this field has no part in, so slipstream traffic always pays both.
@export var top_speed_bump: float = 0.3
## Seconds added to the Run when a slipstream ghost is driven through ([signal slipstream_hit]).
## Its own knob, separate from the boost: how much Run time a catch is worth is a different dial
## than how much speed it hands you.
@export var hit_time_bonus: float = 2.0
## Range of the kart's own collision radius ([member Kart.sphere_radius]) a ghost reaches out to,
## for HazardGhostField.min_pickup_radius_fraction's identical reason and identical defaults. Each
## ghost draws its own fraction from this range once, at spawn, and is modelled at that same scale,
## for BoostGhostField.min_pickup_radius_fraction's identical reason — traffic of assorted sizes,
## each car's silhouette the pickup it stands for. The lane band ([method _half_band]) is still
## sized off the max, so even the widest ghost has room in its own lane.
@export var min_pickup_radius_fraction: float = 3.0
@export var max_pickup_radius_fraction: float = 5.0

## Metres of vertical gap the swept test still counts as a hit, for ClockField.max_vertical_gap's
## identical reason.
@export var max_vertical_gap: float = 5.0

## Alpha wobble, for HazardGhostField's identical reason.
@export var pulse_amplitude: float = 0.12
@export var pulse_hz: float = 1.1
## Green, deliberately apart from the pace ghost's blue and the hazard ghost's red: a slipstream
## ghost is caught, not dodged, and reads the same friendly colour as a boost ghost — the two share
## a colour on purpose, since neither is ever mistaken for the other once you know a boost ghost
## stands still and a slipstream ghost drives (CONTEXT.md, **Pace ghost**'s colour-and-motion rule).
@export var ghost_color: Color = Color(0.15, 0.85, 0.35, 0.5)

## Whether the slipstream ribbons are drawn at all. A setter, for ghost_count's reason.
@export var line_visible: bool = true:
	set(value):
		line_visible = value
		_update_ribbons()
## Metres wide a ribbon is painted, square across the line.
@export var line_width: float = 0.6
## Lifted this far above the recorded line, so a ribbon doesn't z-fight the road it was recorded
## driving on.
@export var line_height_offset: float = 0.05
## Deliberately its own colour rather than a read of [member ghost_color], for
## HazardGhostField.line_color's identical reason.
@export var line_color: Color = Color(0.15, 0.85, 0.35, 0.2)
## Metres of trail a slipstream ghost leaves behind itself — *behind*, back the way it came, since
## unlike a hazard ghost this one drives the same way the driver does. It is a motion trail rather
## than a warning: there is nothing here to be warned about, only where the ghost has just been.
@export var line_lead_length: float = 40.0
## Metres from the kart a ghost's ribbon is drawn within, for HazardGhostField's identical reason.
@export var line_visible_distance: float = 120.0

var _kart: Kart
var _director: RunDirector
var _ghosts_root: Node3D
var _ghosts: Array[Slipstream] = []
var _last_kart_position: Vector3 = Vector3.ZERO
var _has_last_kart_position: bool = false
var _elapsed: float = 0.0
var _road_container: RoadContainer
var _start_line: Node3D
## Seconds of Racing time accumulated toward the next interval spawn ([member
## spawn_interval_seconds]), for HazardGhostField._spawn_timer's identical reason.
var _spawn_timer: float = 0.0
## The road's own centreline, walked once at the first re-place ([method _build_centreline]) and
## reused at every one after, for HazardGhostField._centreline_positions's identical reason.
var _centreline_positions: PackedVector3Array = PackedVector3Array()
var _centreline_yaws: PackedFloat32Array = PackedFloat32Array()
## Cumulative arc length of [member _centreline_positions] and its own last entry, cached alongside
## it in [method _build_centreline], for HazardGhostField._centreline_cumulative's identical reason.
var _centreline_cumulative: PackedFloat32Array = PackedFloat32Array()
var _centreline_length: float = 0.0
# Seeded randomly on creation by Godot and never re-seeded, for HazardGhostField._rng's reason.
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_kart = get_node_or_null(kart_path) as Kart
	_director = get_node_or_null(director_path) as RunDirector
	_ghosts_root = get_node_or_null(ghosts_path) as Node3D
	if _director != null:
		# countdown_started only: a wrap deliberately leaves the field alone (see class doc).
		_director.countdown_started.connect(_on_countdown_started)

	if _ghosts_root == null:
		push_warning("SlipstreamGhostField: no SlipstreamGhosts node — nothing to spawn traffic into.")

	_road_container = get_node_or_null(road_container_path) as RoadContainer
	_start_line = get_node_or_null(start_line_path) as Node3D
	if _road_container == null:
		push_warning("SlipstreamGhostField: no RoadContainer — nothing to spawn traffic along.")

	# Deferred, for HazardGhostField._ready's identical reason: the RoadSegments the centreline is
	# walked from are built by the RoadManager's own _ready, so the first countdown_started has
	# already fired by the time any road exists.
	_place_ghosts.call_deferred()


## Deferred for ClockField's reason: the director runs at the head of the physics frame and the kart
## moves after it. Ghosts are advanced inline, ahead of the sweep, so the sweep tests the position a
## ghost actually occupies this frame rather than last frame's.
##
## The dev inputs live here, not gated on phase, for HazardGhostField's identical reason.
func _physics_process(delta: float) -> void:
	if _director != null and _director.phase == RunDirector.RunPhase.RACING:
		_advance_ghosts(delta)
		_advance_spawn_timer(delta)
		if _kart != null:
			_sweep_ghosts.call_deferred()

	if Input.is_action_just_pressed("dev_slipstream_more"):
		_adjust_ghost_count(1)
	if Input.is_action_just_pressed("dev_slipstream_fewer"):
		_adjust_ghost_count(-1)


## Raises or lowers [member ghost_count] by [param delta], for
## HazardGhostField._adjust_ghost_count's identical reason and identical shape.
func _adjust_ghost_count(delta: int) -> void:
	if loadout == null:
		ghost_count += delta
		return

	loadout.slipstream_ghost_count += delta
	ghost_count = loadout.slipstream_ghost_count
	if save_loadout.is_valid():
		save_loadout.call()


## The pulse runs at display rate, for HazardGhostField's identical reason.
func _process(delta: float) -> void:
	_elapsed += delta
	var alpha_scale: float = 1.0 + sin(_elapsed * TAU * pulse_hz) * pulse_amplitude
	var color: Color = ghost_color
	color.a = clampf(color.a * alpha_scale, 0.0, 1.0)

	for ghost: Slipstream in _ghosts:
		if not ghost.taken:
			ghost.material.albedo_color = color


## Starting arclength distances for [param count] slipstream ghosts along a line of [param
## total_length] metres: each drawn uniformly from the [param min_distance]..[param max_distance]
## window ahead of [param kart_distance] and wrapped onto the loop, for [member
## min_kart_distance]'s reason. Unlike HazardGhostField.place_along there is no stratification —
## the ghosts are free to bunch inside the window, which is what traffic ahead of the driver looks
## like anyway.
##
## Static, and not shared with the hazard field it once copied, for BoostGhostField.place_along's
## identical reason: called with no instance, from a TestCase that cannot touch either field.
##
## Parameters named min_distance/max_distance rather than after the exported members (whose names
## this class already claims), for BoostGhostField.place_along's identical reason.
static func place_along(
	total_length: float,
	count: int,
	kart_distance: float,
	min_distance: float,
	max_distance: float,
	rng: RandomNumberGenerator,
) -> Array[float]:
	var result: Array[float] = []
	if count <= 0 or total_length <= 0.0:
		return result

	var near: float = maxf(min_distance, 0.0)
	var far: float = maxf(max_distance, near)
	for _i in count:
		result.append(fposmod(kart_distance + rng.randf_range(near, far), total_length))

	return result


## The arclength on [member _centreline_cumulative] nearest [param point], for the [member
## min_kart_distance] window it is measured from. HazardGhostField._kart_arclength's identical
## search.
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


## The index of the sample [param distance] metres along the line falls on, capped so the sample
## after it always exists. Shared by the pose walk and the ribbon slice, for
## HazardGhostField._sample_index_at's identical reason.
static func _sample_index_at(cumulative: PackedFloat32Array, distance: float) -> int:
	var index: int = 0
	while index < cumulative.size() - 2 and cumulative[index + 1] < distance:
		index += 1
	return index


## [param from_index] walked back down the line until it reaches [param distance], or the line's
## start, for HazardGhostField._sample_index_back_from's identical reason.
static func _sample_index_back_from(
	cumulative: PackedFloat32Array,
	from_index: int,
	distance: float,
) -> int:
	var index: int = from_index
	while index > 0 and cumulative[index] > distance:
		index -= 1
	return index


## The pose a ghost driving forward along the line shows at arclength [param distance] — unlike
## HazardGhostField._pose_at, no pi is added to the yaw: a slipstream ghost drives the lap's own
## forward, so the line's own tangent already faces the direction it is travelling.
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
	var yaw: float = lerp_angle(yaws[index], yaws[index + 1], weight)
	return Transform3D(Basis(Vector3.UP, yaw), position)


## One ghost's drawn lane wander: two sine harmonics over the centreline's own arclength, for
## HazardGhostField.Wander's identical reason.
class Wander extends RefCounted:
	var bias: float = 0.0 # constant metres right of the centreline, before either harmonic
	var slow_amplitude: float = 0.0
	var slow_harmonic: int = 0
	var slow_phase: float = 0.0
	var fast_amplitude: float = 0.0
	var fast_harmonic: int = 0
	var fast_phase: float = 0.0


## Draws one ghost's wander, fitted to the road and capped for readability —
## HazardGhostField.draw_wander's identical construction and identical reasoning, duplicated here
## for the same reason [method place_along] is.
static func draw_wander(half_band: float, loop_length: float, max_gradient: float,
		slow_phase: float, bias_fraction: float, rng: RandomNumberGenerator) -> Wander:
	var wander := Wander.new()
	if half_band <= 0.0 or loop_length <= 0.0:
		return wander

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


## [param wander] evaluated at [param s] metres along the centreline, for
## HazardGhostField.wander_offset_at's identical reason.
static func wander_offset_at(wander: Wander, s: float, loop_length: float) -> float:
	if loop_length <= 0.0:
		return 0.0
	return (wander.bias
		+ wander.slow_amplitude
			* sin(TAU * wander.slow_harmonic * s / loop_length + wander.slow_phase)
		+ wander.fast_amplitude
			* sin(TAU * wander.fast_harmonic * s / loop_length + wander.fast_phase))


## One slow-harmonic phase per ghost, stratified around the circle, for
## HazardGhostField.deal_phases's identical reason.
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


## One constant lane offset per ghost, as a fraction of the half-band in [-1, 1], stratified across
## the road, for HazardGhostField.deal_biases's identical reason.
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


## Frees the standing field and places a fresh one on the road's centreline, for
## HazardGhostField._place_ghosts's identical reason.
func _place_ghosts() -> void:
	for ghost: Slipstream in _ghosts:
		ghost.node.queue_free()
		# Freed alongside its ghost rather than with it: a ribbon is a sibling of the wrapper, not a
		# child ([method _spawn_ghost]), so nothing else would take it down.
		ghost.ribbon.queue_free()
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
		min_kart_distance,
		max_kart_distance,
		_rng,
	)
	for i in distances.size():
		_ghosts.append(_spawn_ghost(phases[i], biases[i] * lane_bias, distances[i],
			_centreline_length, _centreline_cumulative))


## The kart's own current arclength along the centreline, for HazardGhostField's identical reason.
func _current_kart_distance() -> float:
	if _kart == null or _centreline_cumulative.is_empty():
		return 0.0
	return _kart_arclength(_centreline_positions, _centreline_cumulative, _kart.global_position)


## The lateral room one ghost has, given [param pickup_radius], for HazardGhostField._half_band's
## identical reason: per-ghost rather than one band sized off the widest possible draw, which is
## what left the kerbs uncoverable.
func _half_band(pickup_radius: float) -> float:
	return maxf(RoadCentreline.width(_road_container) * 0.5 - pickup_radius, 0.0) * lane_wander


## Adds [param count] ghosts to the standing field without disturbing it, for
## HazardGhostField._spawn_extra_ghosts's identical reason. Straight through [method place_along]
## rather than the hazard field's rejection-sampled draw: the same window ahead of the kart serves
## a mid-Run arrival as well as it serves the opening deal, and lands it where the driver is headed.
func _spawn_extra_ghosts(count: int) -> void:
	if count <= 0 or _ghosts_root == null or _centreline_length <= 0.0:
		return

	var kart_distance: float = _current_kart_distance()
	var distances: Array[float] = place_along(
		_centreline_length,
		count,
		kart_distance,
		min_kart_distance,
		max_kart_distance,
		_rng,
	)
	for distance: float in distances:
		var phase: float = _rng.randf_range(0.0, TAU)
		var bias: float = _rng.randf_range(-1.0, 1.0)
		_ghosts.append(_spawn_ghost(phase, bias * lane_bias, distance,
			_centreline_length, _centreline_cumulative))


## Advances [member _spawn_timer] and spawns one ghost per full [member spawn_interval_seconds]
## crossed, for HazardGhostField._advance_spawn_timer's identical reason.
func _advance_spawn_timer(delta: float) -> void:
	if spawn_interval_seconds <= 0.0:
		return
	_spawn_timer += delta
	while _spawn_timer >= spawn_interval_seconds:
		_spawn_timer -= spawn_interval_seconds
		_spawn_extra_ghosts(1)


## Walks [member _road_container]'s RoadPoints into the circuit's centreline positions/yaws, for
## HazardGhostField._build_centreline's identical reason.
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


## Cumulative arc length at each sample of [param positions], for
## HazardGhostField._cumulative_lengths's identical reason.
static func _cumulative_lengths(positions: PackedVector3Array) -> PackedFloat32Array:
	var cumulative: PackedFloat32Array = PackedFloat32Array()
	cumulative.append(0.0)
	for i in range(1, positions.size()):
		cumulative.append(cumulative[i - 1] + positions[i - 1].distance_to(positions[i]))
	return cumulative


## [member _centreline_positions] pushed sideways by [param wander], for
## HazardGhostField._offset_positions's identical reason.
func _offset_positions(wander: Wander, cumulative: PackedFloat32Array) -> PackedVector3Array:
	var loop_length: float = cumulative[cumulative.size() - 1]
	var result: PackedVector3Array = PackedVector3Array()
	result.resize(_centreline_positions.size())
	for i in _centreline_positions.size():
		var right: Vector3 = Basis(Vector3.UP, _centreline_yaws[i]).x
		var offset: float = wander_offset_at(wander, cumulative[i], loop_length)
		result[i] = _centreline_positions[i] + right * offset
	return result


## Two vertices per sample of [param positions], square across it, for
## HazardGhostField._build_ribbon_vertices's identical reason.
func _build_ribbon_vertices(
	positions: PackedVector3Array, yaws: PackedFloat32Array
) -> PackedVector3Array:
	var vertices: PackedVector3Array = PackedVector3Array()
	if positions.size() < 2:
		return vertices

	var half_width: float = line_width * 0.5
	var lift: Vector3 = Vector3.UP * line_height_offset
	for i in positions.size():
		var right: Vector3 = Basis(Vector3.UP, yaws[i]).x
		var centre: Vector3 = positions[i] + lift
		vertices.append(centre + right * half_width)
		vertices.append(centre - right * half_width)
	return vertices


## Redraws every ghost's ribbon: the stretch of its own lane just behind it, solid at its own tail
## and faded out [member line_lead_length] metres back, hidden once the ghost is taken or further
## off than [member line_visible_distance] — HazardGhostField._update_ribbons's identical slicing,
## reused as a motion trail rather than a warning since [method _advance_ghosts] increases distance
## instead of decreasing it, which alone turns "the stretch it is about to cover" into "the stretch
## it has just covered".
func _update_ribbons() -> void:
	for ghost: Slipstream in _ghosts:
		if ghost.ribbon == null:
			continue
		if not line_visible or ghost.taken or ghost.ribbon_vertices.size() < 4:
			ghost.ribbon.visible = false
			continue
		if (_kart != null
				and _kart.global_position.distance_to(ghost.origin) > line_visible_distance):
			ghost.ribbon.visible = false
			continue

		var span: float = minf(line_lead_length, ghost.lane_length)
		if span <= 0.0:
			ghost.ribbon.visible = false
			continue

		var low_distance: float = fposmod(ghost.distance - span, ghost.lane_length)
		var high: int = _sample_index_at(ghost.lane_cumulative, ghost.distance)
		var low: int = _sample_index_at(ghost.lane_cumulative, low_distance)

		var sample_count: int = high - low + 1 if low <= high \
			else (ghost.lane_positions.size() - low) + (high + 1)
		if sample_count < 2:
			ghost.ribbon.visible = false
			continue

		var vertices: PackedVector3Array
		if low <= high:
			vertices = ghost.ribbon_vertices.slice(low * 2, (high + 1) * 2)
		else:
			# Wraps past the seam: the tail of the lane's own vertex array, then its head.
			var tail: PackedVector3Array = ghost.ribbon_vertices.slice(
				low * 2, ghost.lane_positions.size() * 2)
			var head: PackedVector3Array = ghost.ribbon_vertices.slice(0, (high + 1) * 2)
			vertices = tail + head

		var colors := PackedColorArray()
		var span_samples: float = float(sample_count - 1)
		for i in sample_count:
			# Alpha only; solid at the ghost (the last sample here) and gone at the trailing end
			# (the first), so the ribbon reads as a trail behind the ghost rather than a lane
			# painted on the road.
			var fade: float = float(i) / span_samples
			colors.append(Color(1.0, 1.0, 1.0, fade))
			colors.append(Color(1.0, 1.0, 1.0, fade))

		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		# A quad strip, not a PRIMITIVE_LINE_STRIP: line primitives render at a fixed 1 px under the
		# GL Compatibility renderer this project targets, which [member line_width] could not affect.
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_COLOR] = colors

		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, arrays)
		mesh.surface_set_material(0, ghost.ribbon.material_override)
		ghost.ribbon.mesh = mesh
		ghost.ribbon.visible = true


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


## Builds one ghost standing in its own lane, for HazardGhostField._spawn_ghost's identical
## construction — everything but the yaw (unmodified here: this ghost's nose already points the
## direction it drives, [method _pose_at]).
func _spawn_ghost(slow_phase: float, bias_fraction: float,
		centreline_distance: float, centreline_length: float,
		centreline_cumulative: PackedFloat32Array) -> Slipstream:
	# Drawn before the lane, because it is what the lane is sized against: this ghost's own
	# reach decides how far out it may sit ([method _half_band]).
	var fraction: float = _rng.randf_range(
		min_pickup_radius_fraction, maxf(min_pickup_radius_fraction, max_pickup_radius_fraction))
	var pickup_radius: float = fraction * (_kart.sphere_radius if _kart != null else 0.0)
	var wander: Wander = draw_wander(_half_band(pickup_radius), centreline_length,
		max_lane_gradient, slow_phase, bias_fraction, _rng)
	var lane_positions: PackedVector3Array = _offset_positions(wander, centreline_cumulative)
	var lane_yaws: PackedFloat32Array = RoadCentreline.yaws_from_positions(lane_positions)
	var lane_cumulative: PackedFloat32Array = _cumulative_lengths(lane_positions)
	var lane_length: float = lane_cumulative[lane_cumulative.size() - 1]
	# An outer-lane ghost's lap is longer than an inner-lane one's, so two ghosts spawned with
	# identical speeds drift out of phase over a Run, for HazardGhostField._spawn_ghost's identical
	# reason.
	var distance: float = centreline_distance * (lane_length / centreline_length)

	var wrapper := Node3D.new()
	_ghosts_root.add_child(wrapper)
	wrapper.global_transform = _pose_at(lane_positions, lane_yaws, lane_cumulative, distance)

	var model: Node3D = GHOST_MODEL.instantiate() as Node3D
	wrapper.add_child(model)
	# The FBX's own axes don't match the road's forward/up/scale, for
	# HazardGhostField._spawn_ghost's identical reason and identical correction, scaled by this
	# ghost's own drawn fraction so the silhouette tracks the pickup radius it stands for.
	model.transform = Transform3D(
		Basis().scaled(MODEL_SCALE_PER_FRACTION * fraction), Vector3(0.0, 0.1, 0.0))

	var ghost := Slipstream.new()
	ghost.node = wrapper
	ghost.distance = distance
	ghost.lane_positions = lane_positions
	ghost.lane_yaws = lane_yaws
	ghost.lane_cumulative = lane_cumulative
	ghost.lane_length = lane_length
	ghost.ribbon_vertices = _build_ribbon_vertices(lane_positions, lane_yaws)
	ghost.origin = wrapper.global_position
	ghost.pickup_radius = pickup_radius
	ghost.speed = _rng.randf_range(min_speed, max_speed)
	ghost.material = _build_ghost_material()
	# A sibling of the wrapper, not a child of it, for HazardGhostField._spawn_ghost's identical
	# reason.
	ghost.ribbon = MeshInstance3D.new()
	ghost.ribbon.visible = false
	ghost.ribbon.material_override = _build_line_material()
	_ghosts_root.add_child(ghost.ribbon)
	_apply_material(model, ghost.material)
	return ghost


## Steps every untaken ghost forward along its own lane by its own speed, wrapping past the end of
## the lane and back round to its start — the sign HazardGhostField._advance_ghosts flips, since
## this traffic drives the lap's own way rather than against it.
func _advance_ghosts(delta: float) -> void:
	for ghost: Slipstream in _ghosts:
		if ghost.taken or ghost.lane_length <= 0.0:
			continue
		var step: float = ghost.speed * delta
		ghost.distance = fposmod(ghost.distance + step, ghost.lane_length)
		var pose: Transform3D = _pose_at(
			ghost.lane_positions, ghost.lane_yaws, ghost.lane_cumulative, ghost.distance)
		ghost.node.global_transform = pose
		ghost.origin = pose.origin

	_update_ribbons()


func _sweep_ghosts() -> void:
	# Re-checked: the director's sweep is queued first and can end the Run inside this same flush.
	if _director.phase != RunDirector.RunPhase.RACING:
		return

	var position: Vector3 = _kart.global_position
	# The first Racing frame after a teleport records a position and tests nothing, for
	# HazardGhostField's identical reason.
	if not _has_last_kart_position:
		_last_kart_position = position
		_has_last_kart_position = true
		return

	var previous: Vector3 = _last_kart_position
	_last_kart_position = position
	var direction: Vector3 = ClockField.sweep_direction(previous, position, _kart.global_transform.basis)

	for ghost: Slipstream in _ghosts:
		if ghost.taken:
			continue
		if not ClockField.segment_takes_clock(previous, position, ghost.origin, ghost.pickup_radius):
			continue
		if absf(position.y - ghost.origin.y) > max_vertical_gap:
			continue
		_take_ghost(ghost, direction)


## Takes [param ghost]: unlike HazardGhostField's swept test, there is no hop-immunity branch here
## — this ghost costs nothing to touch, so however the kart reaches it, contact alone pays the
## reward and clears it.
func _take_ghost(ghost: Slipstream, direction: Vector3) -> void:
	ghost.taken = true
	ghost.node.visible = false
	# Here rather than left to the next [method _update_ribbons]: the sweep is deferred and the
	# ribbons were already updated this frame, for HazardGhostField's identical reason.
	ghost.ribbon.visible = false
	_kart.add_boost_charge(bump, bleed)
	_kart.add_top_speed_bonus(top_speed_bump)
	slipstream_hit.emit(hit_time_bonus, ghost.origin, direction)


## Re-places the whole field at every countdown, for HazardGhostField._on_countdown_started's
## identical reason.
func _on_countdown_started() -> void:
	_has_last_kart_position = false
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


## One ghost, resolved at spawn. RefCounted for ClockField.Clock's reason.
class Slipstream extends RefCounted:
	var node: Node3D = null # the wrapper; visibility toggles here
	var distance: float = 0.0 # arclength along this ghost's own lane, increasing as it drives
	var speed: float = 0.0 # m/s, picked once at spawn from [min_speed, max_speed]
	## Metres this ghost reaches out to, drawn once at spawn from the field's own fraction range
	## and matched by the scale of the model driving here; see [method
	## SlipstreamGhostField._spawn_ghost].
	var pickup_radius: float = 0.0
	var origin: Vector3 = Vector3.ZERO
	var material: StandardMaterial3D = null
	## This ghost's own lane, drawn once at spawn from a wander across the centreline and kept for
	## its whole life, for HazardGhostField.Hazard.lane_positions's identical reason.
	var lane_positions: PackedVector3Array = PackedVector3Array()
	## Re-derived from [member lane_positions], for HazardGhostField.Hazard.lane_yaws's identical
	## reason.
	var lane_yaws: PackedFloat32Array = PackedFloat32Array()
	## Arclength along [member lane_positions], stepped by [method
	## SlipstreamGhostField._advance_ghosts] instead of a shared centreline cumulative, so
	## min_speed/max_speed mean true metres per second in every lane.
	var lane_cumulative: PackedFloat32Array = PackedFloat32Array()
	var lane_length: float = 0.0 # lane_cumulative's last entry
	## Two vertices per sample of [member lane_positions], square across the lane, for
	## HazardGhostField.Hazard.ribbon_vertices's identical reason.
	var ribbon_vertices: PackedVector3Array = PackedVector3Array()
	## This ghost's own stretch of ribbon, a sibling of [member node] rather than a child; see
	## SlipstreamGhostField._spawn_ghost.
	var ribbon: MeshInstance3D = null
	var taken: bool = false
