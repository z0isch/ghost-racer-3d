class_name BoostGhostField
extends Node

## Owner of the boost ghosts: where they are, which are currently taken, and the swept test that
## takes them. The boost lives on the field, not on the ghost — every ghost on a circuit is worth
## exactly the same, which is the playtest's finding, not an implementation shortcut — so there is
## one bump and one bleed here rather than per-ghost metadata.
##
## Modelled on CoinField deliberately, down to the lifecycle: a ghost is taken once and stays taken
## for the rest of the lap, exactly as a coin is, and the whole field is restored at every
## countdown. Purely spatial: it emits [signal ghost_taken] and knows nothing about who listens —
## not the camera's FOV punch, not the kart's speed.
##
## Unlike CoinField's coins, the ghosts are not authored into the circuit: they are placed at
## runtime along the road's own centreline (walked from the RoadContainer's RoadPoints, [method
## _build_centreline]), one per equal slot of it and jittered inside that slot, so a re-place first
## frees whatever stood there before rather than restoring a fixed set. The centreline is deliberately
## not the driver's fastest lap: a racing line hugs the apex through a corner rather than sitting in
## the middle of the road, and a circuit with no recorded lap yet still has a road. It only changes if
## the road geometry itself changes, so the jitter is the only thing standing between the driver and
## the identical field lap after lap.
##
## Each racing-line pose then fans out into a tuneable row of ghosts perpendicular to the road: one
## pinned to the line itself, the rest alternating either side of it at a fixed spacing — no check
## against the true road edge, so a wide fan on a narrow stretch of road can hang ghosts over the
## kerb or the grass; that's a tuning call (lateral_ghost_count/lateral_spacing against the
## circuit's narrowest point), not something the field polices — or snapped onto a nearby coin if
## one is close enough to hand the ghost to it instead of leaving two separate things to line up
## for. See [method _lateral_placements].

## One ghost, the instant it is taken. Position only — there is no per-ghost value to report, since
## every ghost grants the same bump.
signal ghost_taken(position: Vector3)

## The same imported model the kart and pace ghost use. No boost_car.tscn: the field instances this
## directly, one per placement.
const GHOST_MODEL: PackedScene = preload("res://cars/FBX/SportsCar.fbx")

## The model scale the FBX's own axis correction ([method _spawn_ghost]) is built from, per unit
## of [member pickup_radius_fraction] — i.e. the tuned look at the old fixed 2.0 m radius against
## a 0.5 m kart, divided by that 4.0 fraction.
const MODEL_SCALE_PER_FRACTION: Vector3 = Vector3(-0.1375, 0.15, -0.1)

## Not registered as a class_name by the addon itself (road_segment.gd's own reason), so accessed
## the same way road_point.gd accesses it: preloaded as a const, purely to type the segments
## [method _walk_road_loop] walks.
const RoadSegment = preload("res://addons/road-generator/nodes/road_segment.gd")

@export var kart_path: NodePath
@export var director_path: NodePath
## The circuit's RoadContainer, whose generated RoadSegments' curves are walked into the
## centreline the field spawns ghosts along ([method _build_centreline]).
@export var road_container_path: NodePath
## The same start-line Marker3D the [LapDirector] teleports the kart onto. The centreline is a
## closed loop with no inherent start; this is where it is cut and which direction it is walked, so
## [member start_margin]/[member end_margin] clear the same stretch of road the driver actually
## starts and finishes on rather than an arbitrary RoadPoint.
@export var start_line_path: NodePath
## The circuit's BoostGhosts node: an empty runtime spawn parent. The field owns what stands under
## it; nothing is authored there.
@export var ghosts_path: NodePath
## Optional. The circuit's CoinField, so a ghost that lands near a coin can snap onto it instead of
## sitting beside it as two separate things to line up for. Left unset, no snapping happens — a
## scene without a coin field places ghosts exactly as it always has.
@export var coin_field_path: NodePath

## Boost ghosts on the circuit. Setting it re-places the whole field immediately — the door the dev
## input and any later system (a difficulty curve, a purse spend) both go through, rather than the
## dev input having a private path a future system arrives to find. No cap and no minimum spacing:
## a high count on a short line overlaps the ghosts, which is the setter doing what it was told.
@export var ghost_count: int = 5:
	set(value):
		ghost_count = maxi(value, 0)
		_place_ghosts()

## The circuit's own loadout, so the dev keys ([method _physics_process]) can raise or lower its
## boost_ghost_count directly rather than only this field's own copy of it. Set by race.gd
## alongside [member ghost_count] itself. Left null, the dev keys fall back to editing
## [member ghost_count] alone — the field's old behaviour, for a scene with no loadout wired up.
var loadout: CircuitLoadout = null
## Persists [member loadout] after a dev-key change. A Callable rather than a reference to
## [autoload LoadoutHolder] itself, so the field can save without growing a dependency on the
## autoload — the field owns the input that changes its own count (see [member ghost_count]'s dev
## keys), and that includes what happens after the count changes. Set by race.gd, bound to the
## resolved Circuit.
var save_loadout: Callable = Callable()

## Metres of centreline left clear at the start, so a ghost is never handed before the driver has
## picked up speed off the line.
@export var start_margin: float = 10.0
## Metres of centreline left clear at the end, so a ghost is never handed right before the final
## gate.
@export var end_margin: float = 10.0

## Fraction of its own slot a ghost may wander across. 0.0 pins every ghost to its slot's midpoint,
## which is a fixed field for as long as the road stands; 1.0 lets a ghost reach the slot edge it
## shares with its neighbour.
@export_range(0.0, 1.0) var placement_jitter: float = 0.3

## How many ghosts fan out perpendicular to the road at each centreline slot: one pinned to the
## line itself, the rest alternating either side of it. Every one of them is placed regardless of
## the road's actual width at that point — no off-road check — so a high count or wide spacing on a
## narrow stretch of road hangs ghosts over the kerb or the grass.
@export var lateral_ghost_count: int = 3
## Metres between adjacent ghosts in the perpendicular fan.
@export var lateral_spacing: float = 3.0

## Metres within which a placed ghost snaps onto a coin instead of standing near one. 0 turns
## snapping off entirely.
@export var coin_snap_radius: float = 2.5

## m/s the banked charge puts straight into forward speed, above the tuned ceiling, once spent.
## Every ghost on the circuit.
@export var bump: float = 10.0
## m/s^2 the overspeed comes back off at, once the charge is spent. Every ghost on the circuit.
@export var bleed: float = 5.0
## Fraction of the kart's own collision radius ([member Kart.sphere_radius]) a ghost reaches out
## to. Wider than a coin's: the ghost is a car-sized silhouette, and clipping its wing should
## count. 4.0 against the kart's default 0.5 m sphere_radius reproduces the old fixed 2.0 m
## radius. [member _spawn_ghost] scales the model by this same fraction, so a wider pickup always
## shows as a visually bigger ghost rather than the two drifting apart.
@export var pickup_radius_fraction: float = 4.0

## Metres of vertical gap the swept test still counts as a hit, for CoinField.max_vertical_gap's
## identical reason: the horizontal-only sweep would otherwise let a ghost be taken from a stretch
## of road that merely passes underneath or beside it at a different height.
@export var max_vertical_gap: float = 5.0

## Alpha wobble, so a ghost reads as a ghost standing there rather than a parked car to swerve
## around.
@export var pulse_amplitude: float = 0.12
@export var pulse_hz: float = 1.1
## Warm amber, deliberately not the pace ghost's blue: the two now share a model, a line and a
## translucency, so colour is the tell rather than a decoration (CONTEXT.md, **Pace ghost**).
@export var ghost_color: Color = Color(1.0, 0.65, 0.2, 0.35)

var _kart: Kart
var _director: LapDirector
var _coin_field: CoinField
var _ghosts_root: Node3D
var _ghosts: Array[Ghost] = []
var _last_kart_position: Vector3 = Vector3.ZERO
var _has_last_kart_position: bool = false
var _elapsed: float = 0.0
## The road's own centreline, walked once at the first re-place ([method _build_centreline]) and
## reused at every one after: the road doesn't change shape mid-session, so re-walking it at every
## countdown would be pure waste. Empty until the walk succeeds, in which case [method
## _place_ghosts] places nothing rather than falling back to some other line.
var _centreline_positions: PackedVector3Array = PackedVector3Array()
var _centreline_yaws: PackedFloat32Array = PackedFloat32Array()
var _road_container: RoadContainer
var _start_line: Node3D
## pickup_radius_fraction resolved against the kart's sphere_radius. Resolved once in _ready
## rather than read every sweep: sphere_radius is a body constant, not something that changes
## mid-race.
var _pickup_radius: float = 0.0
# Seeded randomly on creation by Godot and never re-seeded: a fresh draw at every countdown is the
# whole point, so there is no layout worth reproducing.
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_kart = get_node_or_null(kart_path) as Kart
	_director = get_node_or_null(director_path) as LapDirector
	_coin_field = get_node_or_null(coin_field_path) as CoinField
	_ghosts_root = get_node_or_null(ghosts_path) as Node3D
	if _kart != null:
		_pickup_radius = pickup_radius_fraction * _kart.sphere_radius

	if _director != null:
		_director.countdown_started.connect(_on_countdown_started)

	if _ghosts_root == null:
		push_warning("BoostGhostField: no BoostGhosts node — nothing to boost off.")

	_road_container = get_node_or_null(road_container_path) as RoadContainer
	_start_line = get_node_or_null(start_line_path) as Node3D
	if _road_container == null:
		push_warning("BoostGhostField: no RoadContainer — nothing to spawn ghosts along.")

	# Deferred, and not left to the first countdown: the RoadSegments the centreline is walked from
	# are built by the RoadManager's own _ready, and the circuit is the last child of main.tscn — so
	# the first countdown_started has already been emitted by the time any road exists. A deferred
	# call flushes after every _ready in the tree, which is the earliest point the road is there to
	# walk.
	_place_ghosts.call_deferred()


## Deferred for CoinField's reason: the director runs at the head of the physics frame and the kart
## moves after it, so the position the kart finishes the frame at only exists after the flush.
##
## The dev inputs live here, not gated on phase or on whether a centreline exists: the field owns
## the count, so the field owns the input that changes it, and pressing `]` on lap 1 must still
## raise the count that lap 2 opens with.
func _physics_process(_delta: float) -> void:
	if _kart != null and _director != null and _director.phase == LapDirector.LapPhase.RACING:
		_sweep_ghosts.call_deferred()

	if Input.is_action_just_pressed("dev_boost_more"):
		_adjust_ghost_count(1)
	if Input.is_action_just_pressed("dev_boost_fewer"):
		_adjust_ghost_count(-1)


## Raises or lowers [member ghost_count] by [param delta]. With a loadout wired up ([member
## loadout]), the loadout's own boost_ghost_count is the thing raised — [member ghost_count] is
## then set to match, so the re-place still happens exactly as it did before there was a loadout —
## and the change is saved via [member save_loadout] so it survives the scene swap. Without a
## loadout, [member ghost_count] alone is edited, matching the field's behaviour before this
## existed.
func _adjust_ghost_count(delta: int) -> void:
	if loadout == null:
		ghost_count += delta
		return

	loadout.boost_ghost_count += delta
	ghost_count = loadout.boost_ghost_count
	if save_loadout.is_valid():
		save_loadout.call()


## The pulse runs at display rate: it is not load-bearing and is never read back by the take test.
func _process(delta: float) -> void:
	_elapsed += delta
	var alpha_scale: float = 1.0 + sin(_elapsed * TAU * pulse_hz) * pulse_amplitude
	var color: Color = ghost_color
	color.a = clampf(color.a * alpha_scale, 0.0, 1.0)

	for ghost: Ghost in _ghosts:
		if not ghost.taken:
			ghost.material.albedo_color = color


## Poses for [param count] boost ghosts along [param positions]/[param yaws], one per equal slot of
## the span left by [param margin_start] / [param margin_end]. Empty for a count of zero or a line
## too short to hold the margins.
##
## Stratified rather than uniformly random: a ghost is drawn inside its own slot, never across the
## whole line, so a field re-rolled at every countdown can neither clump three ghosts into one
## corner nor leave a quarter of the lap bare. [param jitter] is the fraction of its slot a ghost
## may cross; at 0.0 every ghost sits exactly on its slot's midpoint.
##
## Purely a walk along the given line: it knows nothing about the road's actual width, so it
## returns the line pose only. Moving a ghost off that pose — to anywhere still on the road,
## or onto a nearby coin — needs the physics world and is [method _lateral_placements]'s job, not this
## static function's; a TestCase is a RefCounted that cannot touch the scene tree, and this is the
## seam the geometry suite tests.
##
## Parameters named margin_start/margin_end rather than start_margin/end_margin (which the
## exported [member start_margin]/[member end_margin] already claim on this class): GDScript's
## shadowed_variable check fires on a static function parameter reusing an instance member's name,
## even though the two never interact.
static func place_along(
	positions: PackedVector3Array,
	yaws: PackedFloat32Array,
	count: int,
	margin_start: float,
	margin_end: float,
	rng: RandomNumberGenerator,
	jitter: float,
) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	if count <= 0 or positions.size() < 2:
		return result

	# Cumulative arc length at each sample, so a target distance can be found by walking forward
	# rather than re-summing per ghost.
	var cumulative: PackedFloat32Array = PackedFloat32Array()
	cumulative.append(0.0)
	for i in range(1, positions.size()):
		cumulative.append(cumulative[i - 1] + positions[i - 1].distance_to(positions[i]))

	var total: float = cumulative[cumulative.size() - 1]
	var usable: float = total - margin_start - margin_end
	if usable <= 0.0:
		return result

	# Slot midpoints, not endpoints: i * usable / (count - 1) divides by zero at count == 1 and puts
	# ghosts hard against the margins they were just told to respect.
	var slot: float = usable / count
	for i in count:
		var centre: float = margin_start + (i + 0.5) * slot
		var target: float = centre + rng.randf_range(-0.5, 0.5) * jitter * slot
		result.append(_pose_at(positions, yaws, cumulative, target))

	return result


static func _pose_at(
	positions: PackedVector3Array,
	yaws: PackedFloat32Array,
	cumulative: PackedFloat32Array,
	target: float,
) -> Transform3D:
	var index: int = 0
	while index < cumulative.size() - 2 and cumulative[index + 1] < target:
		index += 1

	# Duplicate consecutive samples (the kart frozen on the start line through the countdown) give a
	# zero-length segment here; the guard below keeps that a plain 0.0 weight rather than a NaN.
	var segment_length: float = cumulative[index + 1] - cumulative[index]
	var weight: float = 0.0
	if segment_length > 0.0:
		weight = clampf((target - cumulative[index]) / segment_length, 0.0, 1.0)

	var position: Vector3 = positions[index].lerp(positions[index + 1], weight)
	# lerp_angle, not lerp: the yaw wraps, and a plain lerp spins the ghost a full turn at pi
	# (pace_ghost.gd's reason, and the same one here).
	var yaw: float = lerp_angle(yaws[index], yaws[index + 1], weight)
	return Transform3D(Basis(Vector3.UP, yaw), position)


## Frees the standing field and places a fresh one on the road's centreline. An empty centreline —
## no RoadContainer wired up, or the walk in [method _build_centreline] failed — yields no ghosts
## rather than a warning here; that warning already fired once, in [method _ready].
func _place_ghosts() -> void:
	for ghost: Ghost in _ghosts:
		ghost.node.queue_free()
	_ghosts.clear()

	if _ghosts_root == null or _director == null:
		return

	_build_centreline()

	var poses: Array[Transform3D] = place_along(
		_centreline_positions,
		_centreline_yaws,
		ghost_count,
		start_margin,
		end_margin,
		_rng,
		placement_jitter,
	)
	for pose: Transform3D in poses:
		for lateral: Transform3D in _lateral_placements(pose):
			_ghosts.append(_spawn_ghost(lateral))


## Walks [member _road_container]'s RoadPoints into one lap's worth of centreline positions/yaws
## and caches them into [member _centreline_positions]/[member _centreline_yaws]. A no-op once the
## walk has succeeded once: the road doesn't change shape mid-session.
##
## Called from [method _place_ghosts] rather than [method _ready] because the RoadSegments it walks
## are built by the RoadManager's own _ready, which has no ordering guarantee against this node's.
## An unsuccessful walk caches nothing, so the next re-place simply tries again rather than pinning
## the field to whatever the road looked like before it existed.
##
## [member _start_line], when set, is where the loop is cut into an open line and which direction it
## is walked: without it the loop is cut at an arbitrary RoadPoint and walked in that RoadPoint's
## own "next" direction, which still yields a driveable centreline but no longer lines up
## [member start_margin]/[member end_margin] with where the driver actually starts and finishes.
func _build_centreline() -> void:
	if not _centreline_positions.is_empty() or _road_container == null:
		return

	var loop: PackedVector3Array = _walk_road_loop(_road_container)
	if loop.size() < 2:
		return

	if _start_line != null:
		loop = _cut_and_orient_loop(loop, _start_line)

	_centreline_positions = loop
	_centreline_yaws = _yaws_from_positions(loop)


## One full circuit of [param road_container]'s RoadPoints, concatenating each RoadPoint's next
## RoadSegment's own curve in "next" order ([method RoadPoint.get_next_road_node]) starting from an
## arbitrary RoadPoint and stopping once the walk returns to it. A RoadPoint with no next segment
## ends the walk short rather than looping forever chasing a null.
##
## The segment's curve, deliberately, and not the RoadPoint's generated edge_C path. edge_C is
## nominally the same line, but the addon re-derives it through RoadSegment.offset_curve rather than
## reusing the curve it just built, and that derivation has a near-90-degree fallback branch that
## hands back a handle in the segment's local space to a curve being built in the RoadPoint's — so
## on any corner sharp enough to trip it, edge_C bows clean off the tarmac (circuit3's RP_004
## corner, by ~20 m). The segment's curve is what the road mesh's own loops are placed along, so it
## is the road's true middle by construction.
func _walk_road_loop(road_container: RoadContainer) -> PackedVector3Array:
	var positions: PackedVector3Array = PackedVector3Array()
	var roadpoints: Array[RoadPoint] = road_container.get_roadpoints()
	if roadpoints.is_empty():
		return positions

	var start_point: RoadPoint = roadpoints[0]
	var point: RoadPoint = start_point
	# +1: every RoadPoint visited once, plus the one extra step back onto start_point that closes
	# the loop and ends the walk.
	var guard: int = roadpoints.size() + 1
	while guard > 0:
		guard -= 1
		var segment: RoadSegment = point.next_seg
		if segment == null or not is_instance_valid(segment) or segment.curve == null:
			break
		var local_points: PackedVector3Array = segment.curve.get_baked_points()
		# next_seg is the segment on the point's "next" side, but the point is not always that
		# segment's start_point — reached from its far end, its samples run backwards.
		var forward: bool = segment.start_point == point
		# Segment boundaries duplicate a point (this segment's last sample is the next RoadPoint,
		# which is also that next segment's first sample), so every walk after the first skips its
		# own first sample.
		var skip: int = 1 if not positions.is_empty() else 0
		for i in range(skip, local_points.size()):
			var index: int = i if forward else local_points.size() - 1 - i
			positions.append(segment.to_global(local_points[index]))

		var next_point: RoadPoint = point.get_next_road_node() as RoadPoint
		if next_point == null or next_point == start_point:
			break
		point = next_point

	return positions


## Cuts the closed [param loop] into an open line starting at whichever of its samples sits nearest
## [param start_line], and walks it in whichever direction — [param loop]'s own order, or reversed —
## matches [param start_line]'s own forward facing (`-basis.z`, [member Kart]'s own forward
## convention). Without this the loop's cut point and direction are whatever [method
## _walk_road_loop] happened to start and walk from, which has no reason to land anywhere near where
## the driver actually starts a lap.
func _cut_and_orient_loop(loop: PackedVector3Array, start_line: Node3D) -> PackedVector3Array:
	var count: int = loop.size()
	var cut: int = _nearest_index(loop, start_line.global_position)

	var facing: Vector3 = -start_line.global_transform.basis.z
	var travel: Vector3 = loop[(cut + 1) % count] - loop[cut]
	if travel.dot(facing) < 0.0:
		loop.reverse()
		cut = count - 1 - cut

	var oriented: PackedVector3Array = PackedVector3Array()
	oriented.resize(count)
	for i in count:
		oriented[i] = loop[(cut + i) % count]
	return oriented


## The index into [param positions] closest to [param point], by squared distance (monotonic with
## distance, cheaper to compare) — the seam [method _cut_and_orient_loop] cuts the loop at.
func _nearest_index(positions: PackedVector3Array, point: Vector3) -> int:
	var best_index: int = 0
	var best_distance: float = INF
	for i in positions.size():
		var distance: float = positions[i].distance_squared_to(point)
		if distance < best_distance:
			best_distance = distance
			best_index = i
	return best_index


## One yaw per position in [param positions], each the heading of the step into the next position
## (`-atan2(dir.x, dir.z)`'s convention inverted to match [member Kart]'s own `forward =
## -basis.z`— see [member LapDirector._recording_yaws], which records `global_rotation.y` off that
## same basis). The last position has no "next" step of its own, so it repeats the step before it
## rather than wrapping onto the first — the walk is an open line by the time this runs, not the
## closed loop it started as.
func _yaws_from_positions(positions: PackedVector3Array) -> PackedFloat32Array:
	var yaws: PackedFloat32Array = PackedFloat32Array()
	yaws.resize(positions.size())
	for i in positions.size() - 1:
		var dir: Vector3 = (positions[i + 1] - positions[i]).normalized()
		yaws[i] = atan2(-dir.x, -dir.z)
	if positions.size() > 1:
		yaws[positions.size() - 1] = yaws[positions.size() - 2]
	return yaws


## Fans [param pose] out into [member lateral_ghost_count] ghosts perpendicular to the road: the
## first stays pinned to the centreline itself, and the rest alternate right/left of it at
## increasing multiples of [member lateral_spacing] ([method _lateral_offset]). No check against
## the true road edge — every one of the fan is placed, so a wide fan on a narrow stretch of road
## can hang ghosts over the kerb or the grass; that's on whoever tunes lateral_ghost_count and
## lateral_spacing, not something placement polices. A placed ghost lands on a nearby coin instead
## if one stands close enough to hand it to.
func _lateral_placements(pose: Transform3D) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	var right: Vector3 = pose.basis.x

	for i in lateral_ghost_count:
		var offset: float = _lateral_offset(i)
		# basis.x is the pose's own right vector, so the offset leans with the line through a
		# corner instead of being re-derived from the yaw here. translated, not translated_local:
		# the vector is already in the line's space.
		var placed: Transform3D = pose.translated(right * offset)
		placed.origin = _nearest_coin_within(placed.origin, coin_snap_radius)
		result.append(placed)
	return result


## The signed lateral offset, in [member lateral_spacing] units, of the [param index]-th ghost in a
## perpendicular fan: 0.0 for the first (the ghost that stays on the centreline), then alternating
## right (positive) and left (negative) at increasing multiples — index 1 one spacing right, index 2
## one spacing left, index 3 two spacings right, and so on — so the fan grows evenly outward from the
## centre ghost regardless of how many of [member lateral_ghost_count] end up placed.
func _lateral_offset(index: int) -> float:
	if index == 0:
		return 0.0
	@warning_ignore("integer_division")
	var rung: int = (index + 1) / 2
	var side: float = 1.0 if index % 2 == 1 else -1.0
	return side * rung * lateral_spacing


## The nearest coin to [param position] within [param radius], or [param position] itself if none
## stands that close — the "no snap" case as a same-value return rather than a second output
## channel, since every caller only ever compares the result back against what it passed in.
## Deliberately not gated on taken-ness (CoinField.coin_origins' own reason): a ghost should stand on
## the coin's slot in the field's shape, not chase whichever coins happen to still be up this lap.
func _nearest_coin_within(position: Vector3, radius: float) -> Vector3:
	if _coin_field == null or radius <= 0.0:
		return position

	var nearest: Vector3 = position
	var nearest_distance_squared: float = radius * radius
	for coin: Vector3 in _coin_field.coin_origins():
		var distance_squared: float = position.distance_squared_to(coin)
		if distance_squared <= nearest_distance_squared:
			nearest = coin
			nearest_distance_squared = distance_squared
	return nearest


func _spawn_ghost(pose: Transform3D) -> Ghost:
	var wrapper := Node3D.new()
	_ghosts_root.add_child(wrapper)
	wrapper.global_transform = pose

	var model: Node3D = GHOST_MODEL.instantiate() as Node3D
	wrapper.add_child(model)
	# The FBX's own axes don't match the road's forward/up/scale; this is the same corrective local
	# transform authored on every hand-placed pad's Ghost child and on PaceGhost's SportsCar child,
	# scaled by pickup_radius_fraction so the silhouette tracks the pickup radius it stands for.
	# 0.02, not PaceGhost's 0.0: just enough lift to keep the model's belly off the road mesh
	# without floating it visibly above the ground the way the old 0.1 did.
	model.transform = Transform3D(
		Basis().scaled(MODEL_SCALE_PER_FRACTION * pickup_radius_fraction), Vector3(0.0, 0.02, 0.0))

	var ghost := Ghost.new()
	ghost.node = wrapper
	ghost.origin = pose.origin
	ghost.material = _build_ghost_material()
	_apply_material(model, ghost.material)
	return ghost


func _sweep_ghosts() -> void:
	# Re-checked: the director's sweep is queued first and can end the lap inside this same flush.
	if _director.phase != LapDirector.LapPhase.RACING:
		return

	var position: Vector3 = _kart.global_position
	# The first Racing frame after a teleport records a position and tests nothing: a segment
	# spanning the teleport would sweep half the circuit.
	if not _has_last_kart_position:
		_last_kart_position = position
		_has_last_kart_position = true
		return

	var previous: Vector3 = _last_kart_position
	_last_kart_position = position

	for ghost: Ghost in _ghosts:
		if ghost.taken:
			continue
		if not CoinField.segment_takes_coin(previous, position, ghost.origin, _pickup_radius):
			continue
		if absf(position.y - ghost.origin.y) > max_vertical_gap:
			continue
		_take_ghost(ghost)


## Takes [param ghost] alone: each ghost in a fan is its own boost opportunity now, so collecting
## one leaves its neighbours standing for a separate pass.
func _take_ghost(ghost: Ghost) -> void:
	ghost.taken = true
	ghost.node.visible = false
	_kart.add_boost_charge(bump, bleed)
	ghost_taken.emit(ghost.origin)


## Re-places the whole field so it is exactly whole at the moment the driver looks at the track
## during the countdown — the signal that exists precisely for this. Not called on lap_completed:
## rearranging the circuit while the player is still reading their lap time during the Finished
## hold.
func _on_countdown_started() -> void:
	_has_last_kart_position = false
	_place_ghosts()


# Built here rather than authored on the mesh, for PaceGhost's reason: the ghost instances the same
# imported FBX as the kart, whose internal node structure belongs to the importer.
func _build_ghost_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = ghost_color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Stops the ghost's own faces blending over each other, so it reads as one body.
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	return material


func _apply_material(node: Node, material: StandardMaterial3D) -> void:
	var mesh: MeshInstance3D = node as MeshInstance3D
	if mesh != null:
		mesh.material_override = material
	for child: Node in node.get_children():
		_apply_material(child, material)


## One ghost, resolved at spawn. RefCounted for CoinField.Coin's reason: no allocation in the
## physics step, only at a re-place.
class Ghost extends RefCounted:
	var node: Node3D = null # the wrapper; visibility toggles here
	var origin: Vector3 = Vector3.ZERO
	var material: StandardMaterial3D = null
	var taken: bool = false
