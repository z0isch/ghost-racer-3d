class_name HazardGhostField
extends Node

## Owner of the hazard ghosts: where they are, which are currently taken, and the swept test that
## takes them. Modelled on BoostGhostField, with two differences that follow from being oncoming
## traffic rather than a pickup: a hazard ghost stands on its own lane, a continuous offset measured
## across the road's own centreline, drawn once at spawn and kept for its whole life, and it moves,
## backward along that lane, rather than standing still.
##
## The slow-down lives on the field, not on the ghost, for BoostGhostField's reason: every hazard
## on a circuit costs the same, so there is one multiplier here rather than per-ghost metadata.
##
## Placed at runtime along the circuit's own road centreline ([method _build_centreline], via
## [RoadCentreline]) — a genuine closed loop, unlike the driver's own recorded lap, so a circuit
## nobody has driven yet still has traffic. Re-placed at every countdown; a re-place first frees
## whatever stood there before. A *wrap* does nothing at all to the field — unlike the boost ghosts,
## hazards are neither restored nor re-placed there: cleared is cleared for the rest of the Run, and
## the traffic still standing keeps driving straight through the wrap boundary.
##
## Each hazard trails a short ribbon down its own lane ahead of itself ([method _update_ribbons]),
## rather than the field painting the whole wrap red: under Runs the same wrap is driven over and
## over, so a wrap-long ribbon is permanent scenery, where a per-hazard one is a warning about
## traffic that is actually coming.

## One ghost, the instant it is hit head-on. Position only, for BoostGhostField's reason.
signal hazard_hit(position: Vector3)
## One ghost, the instant it is cleared by a hop instead. Carries the seconds the jump is worth, so
## RunDirector can bank them the same way it banks a clock, and position/direction in ClockField.
## clock_taken's own shape, so PickupPopups can spawn a popup for this pickup exactly as it does
## for that one.
signal hazard_jumped(seconds: float, position: Vector3, direction: Vector3)

## The same imported model every ghost in this game uses. No hazard_car.tscn: the field instances
## this directly, one per placement.
const GHOST_MODEL: PackedScene = preload("res://cars/FBX/SportsCar.fbx")

## The model scale the FBX's own axis correction ([method _spawn_ghost]) is built from, per unit
## of [member pickup_radius_fraction], for BoostGhostField.MODEL_SCALE_PER_FRACTION's identical
## reason and identical derivation.
const MODEL_SCALE_PER_FRACTION: Vector3 = Vector3(-0.1375, 0.15, -0.1)

@export var kart_path: NodePath
@export var director_path: NodePath
## The circuit's RoadContainer, whose RoadSegments' curves are walked into the centreline the lanes
## are measured from. Mirrors BoostGhostField's export of the same name.
@export var road_container_path: NodePath
## The same start-line Marker3D the RunDirector teleports the kart onto, for BoostGhostField's
## identical reason: the loop has no inherent start, and this is where start_margin is measured from.
@export var start_line_path: NodePath
## The circuit's HazardGhosts node: an empty runtime spawn parent. The field owns what stands under
## it; nothing is authored there.
@export var ghosts_path: NodePath

## Hazard ghosts on the circuit. Setting it re-places the whole field immediately, for
## BoostGhostField.ghost_count's reason: the door the dev input and any later system both go
## through.
@export var ghost_count: int = 3:
	set(value):
		ghost_count = maxi(value, 0)
		_place_ghosts()

## The circuit's own loadout, for BoostGhostField.loadout's identical reason: the dev keys ([method
## _physics_process]) raise or lower its hazard_ghost_count directly. Set by race.gd alongside
## [member ghost_count] itself. Left null, the dev keys fall back to editing [member ghost_count]
## alone.
var loadout: CircuitLoadout = null
## Persists [member loadout] after a dev-key change, for BoostGhostField.save_loadout's identical
## reason. Set by race.gd, bound to the resolved Circuit.
var save_loadout: Callable = Callable()

## Metres of ghost line left clear at the start, for BoostGhostField.start_margin's identical
## reason: a hazard is never handed before the driver has picked up speed off the line. Nothing
## clears the end, for the same reason BoostGhostField clears none either: a Run wraps rather than
## finishing at a gate.
@export var start_margin: float = 10.0

## Fraction of its own slot a hazard may wander across at spawn, for BoostGhostField's reason. It
## still drives the whole line afterward — this only varies where in its lap the traffic starts out.
@export_range(0.0, 1.0) var placement_jitter: float = 0.3

## m/s range a hazard ghost may drive backward along the ghost line. Each hazard picks its own
## speed from this range at spawn ([method _spawn_ghost]), so traffic doesn't read as a single
## repeating pace.
@export var min_speed: float = 4.0
@export var max_speed: float = 8.0

## Fraction the kart's forward speed is scrubbed by on a hit. 1.0 stops the kart dead; 0.0 does
## nothing. Kept separate from the ghost's own driving speed: how hard a hit costs you is a
## different dial than how fast the traffic comes at you.
@export var hit_slow_multiplier: float = 0.5
## Seconds added to the Run when a hazard is cleared by a hop instead of hit, via [signal
## hazard_jumped]. Tunable independently of a clock's own seconds — a dodge is a smaller, riskier
## trick than driving over an authored clock, so this defaults lower.
@export var jump_time_bonus: float = 0.0
## Fraction of the kart's own collision radius ([member Kart.sphere_radius]) a hazard reaches out
## to, for BoostGhostField.pickup_radius_fraction's identical reason and identical default.
@export var pickup_radius_fraction: float = 4.0

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
## Metres wide a ribbon is painted, square across the line.
@export var line_width: float = 0.6
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
var _ghosts_root: Node3D
var _ghosts: Array[Hazard] = []
var _last_kart_position: Vector3 = Vector3.ZERO
var _has_last_kart_position: bool = false
var _elapsed: float = 0.0
var _road_container: RoadContainer
var _start_line: Node3D
## The road's own centreline, walked once at the first re-place ([method _build_centreline]) and
## reused at every one after, for BoostGhostField._centreline_positions's identical reason.
var _centreline_positions: PackedVector3Array = PackedVector3Array()
var _centreline_yaws: PackedFloat32Array = PackedFloat32Array()
## pickup_radius_fraction resolved against the kart's sphere_radius, for
## BoostGhostField._pickup_radius's identical reason.
var _pickup_radius: float = 0.0
# Seeded randomly on creation by Godot and never re-seeded, for BoostGhostField._rng's reason.
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_kart = get_node_or_null(kart_path) as Kart
	_director = get_node_or_null(director_path) as RunDirector
	_ghosts_root = get_node_or_null(ghosts_path) as Node3D
	if _kart != null:
		_pickup_radius = pickup_radius_fraction * _kart.sphere_radius

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
## metres, one per equal slot of the span left by [param margin_start] — BoostGhostField.place_along's
## stratification, minus the pose resolution: called once against the centreline's own length, with
## each hazard's chosen distance later converted into its own lane's arclength ([method
## _spawn_ghost]), so the arclength stratification and [member start_margin] stay comparable between
## lanes.
static func place_along(
	total_length: float,
	count: int,
	margin_start: float,
	rng: RandomNumberGenerator,
	jitter: float,
) -> Array[float]:
	var result: Array[float] = []
	if count <= 0 or total_length <= 0.0:
		return result

	var usable: float = total_length - margin_start
	if usable <= 0.0:
		return result

	var slot: float = usable / count
	for i in count:
		var centre: float = margin_start + (i + 0.5) * slot
		var target: float = centre + rng.randf_range(-0.5, 0.5) * jitter * slot
		result.append(target)

	return result


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


## One lane offset per hazard, in metres, signed across the road: a continuous position rather than
## one of a handful of fixed lanes, so a field never reads as cars parked on a grid.
##
## Stratified rather than independently drawn, for deal_lanes' old reason — independent uniform
## draws put two of three hazards nearly on top of each other more often than not. The road is cut
## into [param count] equal bands (never more than the [method lane_capacity] that fit side by
## side), the bands are dealt out shuffled and without replacement, and each hazard then takes a
## uniform position *within* its own band. Spread stays even; the exact offset does not repeat.
##
## The jitter inside a band is the band's width less a car's, so a car never overhangs its own band
## and two hazards in neighbouring bands never overlap. A road packed to capacity has no slack left
## and collapses back to the evenly-spaced grid, which is the only layout that fits.
##
## Consequence, carried over from the lane version: pickup_radius_fraction still does two jobs — it
## sets the hit radius and, through the car width, the band layout.
static func deal_offsets(count: int, road_width: float, car_width: float,
		rng: RandomNumberGenerator) -> Array[float]:
	var result: Array[float] = []
	if count <= 0:
		return result

	var capacity: int = lane_capacity(road_width, car_width)
	if capacity <= 1:
		for _i in count:
			result.append(0.0)
		return result

	var bands: int = mini(count, capacity)
	var band_width: float = road_width / bands
	var jitter: float = maxf(band_width - car_width, 0.0)

	# Dealt from a shuffled pool, reshuffled whenever it runs out: no band is used twice while
	# count <= bands, and past it the uses stay within one of each other.
	var pool: Array[int] = []
	for _i in count:
		if pool.is_empty():
			for band in bands:
				pool.append(band)
		var index: int = rng.randi_range(0, pool.size() - 1)
		var band: int = pool[index]
		pool.remove_at(index)

		var centre: float = -road_width * 0.5 + band_width * (band + 0.5)
		result.append(centre + rng.randf_range(-jitter * 0.5, jitter * 0.5))

	return result


## How many cars fit across the road side by side without overlapping, at least one. Derived from
## car width rather than exported so the bands are always exactly as separated as the cars are wide:
## an exported count could be set to 7 on an 8 m road and nothing in the code would object to seven
## overlapping cars reading as a wall.
static func lane_capacity(road_width: float, car_width: float) -> int:
	if road_width <= 0.0 or car_width <= 0.0:
		return 1
	return maxi(floori(road_width / car_width), 1)


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
	var centreline_cumulative: PackedFloat32Array = _cumulative_lengths(_centreline_positions)
	var centreline_length: float = centreline_cumulative[centreline_cumulative.size() - 1]
	if centreline_length <= 0.0:
		return

	var road_width: float = RoadCentreline.width(_road_container)
	var car_width: float = 2.0 * _pickup_radius
	var offsets: Array[float] = deal_offsets(ghost_count, road_width, car_width, _rng)

	var distances: Array[float] = place_along(
		centreline_length,
		ghost_count,
		start_margin,
		_rng,
		placement_jitter,
	)
	for i in distances.size():
		_ghosts.append(_spawn_ghost(offsets[i], distances[i], centreline_length))


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


## [member _centreline_positions] pushed sideways by [param offset] metres along each sample's own
## right vector ([method Basis(Vector3.UP, yaw).x]), so a hazard's lane leans with the road through a
## corner instead of staying world-axis-aligned — the same construction [method _build_ribbon_vertices]
## uses for the ribbon's own two edges.
func _offset_positions(offset: float) -> PackedVector3Array:
	var result: PackedVector3Array = PackedVector3Array()
	result.resize(_centreline_positions.size())
	for i in _centreline_positions.size():
		var right: Vector3 = Basis(Vector3.UP, _centreline_yaws[i]).x
		result[i] = _centreline_positions[i] + right * offset
	return result


## Two vertices per sample of [param positions], square across it via [param yaws]' own right
## vector — one hazard's own ribbon geometry, built once at spawn and sliced (with the seam wrapped)
## by [method _update_ribbons] every physics tick rather than rebuilt.
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
		# GL Compatibility renderer this project targets, which [member line_width] could not affect.
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


## Builds one hazard standing in its own lane: [param offset] metres across the road from the
## centreline, starting at the point [param centreline_distance] metres along [param
## centreline_length] converts to along that lane's own (generally different) length.
##
## Yaws are re-derived from the offset polyline rather than copied off the centreline
## ([RoadCentreline.yaws_from_positions]): an outer lane through a corner turns through the same
## angle over a longer arc, and copying would leave a hazard's nose pointing subtly off its own
## path.
func _spawn_ghost(offset: float, centreline_distance: float, centreline_length: float) -> Hazard:
	var lane_positions: PackedVector3Array = _offset_positions(offset)
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
	# identical reason and identical correction, scaled by pickup_radius_fraction for the same
	# reason as there too.
	model.transform = Transform3D(
		Basis().scaled(MODEL_SCALE_PER_FRACTION * pickup_radius_fraction), Vector3(0.0, 0.1, 0.0))

	var hazard := Hazard.new()
	hazard.node = wrapper
	hazard.distance = distance
	hazard.lane_positions = lane_positions
	hazard.lane_yaws = lane_yaws
	hazard.lane_cumulative = lane_cumulative
	hazard.lane_length = lane_length
	hazard.ribbon_vertices = _build_ribbon_vertices(lane_positions, lane_yaws)
	hazard.origin = wrapper.global_position
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

	_update_ribbons()


func _sweep_ghosts() -> void:
	# Re-checked: the director's sweep is queued first and can end the Run inside this same flush.
	if _director.phase != RunDirector.RunPhase.RACING:
		return

	var position: Vector3 = _kart.global_position
	# The first Racing frame after a teleport records a position and tests nothing, for
	# BoostGhostField's identical reason.
	if not _has_last_kart_position:
		_last_kart_position = position
		_has_last_kart_position = true
		return

	var previous: Vector3 = _last_kart_position
	_last_kart_position = position
	var direction: Vector3 = ClockField.sweep_direction(previous, position, _kart.global_transform.basis)

	for hazard: Hazard in _ghosts:
		if hazard.taken:
			continue
		if not ClockField.segment_takes_clock(previous, position, hazard.origin, _pickup_radius):
			continue
		if absf(position.y - hazard.origin.y) > max_vertical_gap:
			continue
		hazard.taken = true
		hazard.node.visible = false
		# Here rather than left to the next [method _update_ribbons]: the sweep is deferred and the
		# ribbons were already updated this frame, so waiting would leave a warning hanging in the
		# air for a frame after the thing it warned about was hit.
		hazard.ribbon.visible = false
		# The swept test itself ignores height (see class doc), so a hop clears a hazard by immunity
		# rather than clearance — the hazard still disappears exactly as a hit one does, but instead
		# of costing speed it pays out jump_time_bonus, rewarding the trick rather than merely
		# forgiving it.
		if _kart.is_hopping:
			hazard_jumped.emit(jump_time_bonus, hazard.origin, direction)
		else:
			_kart.apply_hazard_slow(hit_slow_multiplier)
			hazard_hit.emit(hazard.origin)


## Re-places the whole field at every countdown, for BoostGhostField._on_countdown_started's
## identical reason.
func _on_countdown_started() -> void:
	_has_last_kart_position = false
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


## One hazard, resolved at spawn. RefCounted for ClockField.Clock's reason.
class Hazard extends RefCounted:
	var node: Node3D = null # the wrapper; visibility toggles here
	var distance: float = 0.0 # arclength along this hazard's own lane, decreasing as it drives
	var speed: float = 0.0 # m/s, picked once at spawn from [min_speed, max_speed]
	var origin: Vector3 = Vector3.ZERO
	var material: StandardMaterial3D = null
	## The centreline offset into this hazard's own lane, drawn once at spawn and kept for its
	## whole life — "one part of the track, driven the whole circuit".
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
