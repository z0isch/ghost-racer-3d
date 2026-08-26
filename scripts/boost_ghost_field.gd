class_name BoostGhostField
extends Node

## Owner of the boost ghosts: where they are, which are currently taken, and the swept test that
## takes them. The boost lives on the field, not on the ghost — every ghost on a circuit is worth
## exactly the same, which is the playtest's finding, not an implementation shortcut — so there is
## one bump and one bleed here rather than per-ghost metadata.
##
## Modelled on ClockField deliberately, down to the lifecycle: a ghost is taken once and stays taken
## until the field is next re-placed, exactly as a clock is, and the whole field is re-rolled at
## every countdown and every wrap — a boost taken on one lap is offered again, at fresh positions,
## on the next rather than the field thinning out to nothing over a long Run.
##
## Purely spatial: it emits [signal ghost_taken] and knows nothing about who listens —
## not the camera's FOV punch, not the kart's speed.
##
## Unlike ClockField's clocks, the ghosts are not authored into the circuit: they are placed at
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
## circuit's narrowest point), not something the field polices. See [method _lateral_placements].

## One ghost, the instant it is taken. Position only — there is no per-ghost value to report, since
## every ghost grants the same bump.
signal ghost_taken(position: Vector3)

## The same imported model the kart and pace ghost use. No boost_car.tscn: the field instances this
## directly, one per placement.
const GHOST_MODEL: PackedScene = preload("res://cars/FBX/SportsCar.fbx")

## The model scale the FBX's own axis correction ([method _spawn_ghost]) is built from, per unit of
## a ghost's own drawn car scale ([member min_car_scale] … [member max_car_scale]). At
## [constant Hitbox.KART_CAR_SCALE] this product is exactly the kart's own authored model scale,
## which is what makes that number mean "kart-sized" everywhere it is read.
const MODEL_SCALE_PER_FRACTION: Vector3 = Vector3(-0.1375, 0.15, -0.1)

@export var kart_path: NodePath
@export var director_path: NodePath
## The circuit's RoadContainer, whose generated RoadSegments' curves are walked into the
## centreline the field spawns ghosts along ([method _build_centreline]).
@export var road_container_path: NodePath
## The same start-line Marker3D the [RunDirector] teleports the kart onto. The centreline is a
## closed loop with no inherent start; this is where it is cut and which direction it is walked, so
## arclength distances (and [member kart_clearance]'s own exclusion band, measured from wherever the
## kart actually is) mean the same thing lap to lap rather than drifting with an arbitrary RoadPoint.
@export var start_line_path: NodePath
## The circuit's BoostGhosts node: an empty runtime spawn parent. The field owns what stands under
## it; nothing is authored there.
@export var ghosts_path: NodePath

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

## Metres of centreline kept clear either side of the kart's own current position, so a ghost is
## never handed right off the kart's nose (nor right behind it) — including the moment a Run starts,
## when the kart sits on the start line and this reproduces the field's old fixed start-of-lap
## margin. Symmetric rather than forward-only: the excluded band wraps both ways around the loop.
@export var kart_clearance: float = 10.0

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

## m/s the banked charge puts straight into forward speed, above the tuned ceiling, once spent.
## Every ghost on the circuit.
@export var bump: float = 10.0
## m/s^2 the overspeed comes back off at, once the charge is spent. Every ghost on the circuit.
@export var bleed: float = 5.0
## Range of car sizes this field spawns, in multiples of [member MODEL_SCALE_PER_FRACTION] —
## [constant Hitbox.KART_CAR_SCALE] is kart-sized, half that is a car half as long and half as wide.
##
## Each ghost draws its own scale from this range once, at spawn ([method _spawn_ghost]), and that
## one draw sizes both the model and the capsule it is taken by: the two cannot drift apart, because
## the hitbox is the model's own measured footprint under that scale ([method
## Hitbox.model_half_extents]). Setting min above max is not policed; the draw simply collapses to
## the smaller of the two.
@export var min_car_scale: float = 3.0
@export var max_car_scale: float = 5.0
## Generosity of the hitbox against the drawn car, for HazardGhostField.hitbox_scale's identical
## reason — except that this field's ghosts are rewards rather than obstacles, so >1.0 is the useful
## direction here: it forgives a near miss instead of punishing one.
@export var hitbox_scale: float = 1.0

## Metres of vertical gap the swept test still counts as a hit, for ClockField.max_vertical_gap's
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
var _director: RunDirector
var _ghosts_root: Node3D
var _ghosts: Array[Ghost] = []
var _last_kart_centre: Vector3 = Vector3.ZERO
var _last_kart_yaw: float = 0.0
var _has_last_kart_pose: bool = false
## Built once and re-aimed every frame rather than rebuilt, for [Hitbox.Sweep]'s own reason.
var _sweep := Hitbox.Sweep.new()
var _elapsed: float = 0.0
## The road's own centreline, walked once at the first re-place ([method _build_centreline]) and
## reused at every one after: the road doesn't change shape mid-session, so re-walking it at every
## countdown would be pure waste. Empty until the walk succeeds, in which case [method
## _place_ghosts] places nothing rather than falling back to some other line.
var _centreline_positions: PackedVector3Array = PackedVector3Array()
var _centreline_yaws: PackedFloat32Array = PackedFloat32Array()
## Cumulative arc length of [member _centreline_positions], cached alongside it so [member
## kart_clearance]'s exclusion band can be measured from the kart's own current arclength ([method
## _kart_arclength]) without re-walking the line at every re-place.
var _centreline_cumulative: PackedFloat32Array = PackedFloat32Array()
var _road_container: RoadContainer
var _start_line: Node3D
# Seeded randomly on creation by Godot and never re-seeded: a fresh draw at every countdown is the
# whole point, so there is no layout worth reproducing.
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_kart = get_node_or_null(kart_path) as Kart
	_director = get_node_or_null(director_path) as RunDirector
	_ghosts_root = get_node_or_null(ghosts_path) as Node3D

	if _director != null:
		_director.countdown_started.connect(_on_countdown_started)
		_director.wrapped.connect(_on_wrapped)

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


## Deferred for ClockField's reason: the director runs at the head of the physics frame and the kart
## moves after it, so the position the kart finishes the frame at only exists after the flush.
##
## The dev inputs live here, not gated on phase or on whether a centreline exists: the field owns
## the count, so the field owns the input that changes it, and pressing `]` before any Run has
## completed must still raise the count the next Run opens with.
func _physics_process(_delta: float) -> void:
	if _kart != null and _director != null and _director.phase == RunDirector.RunPhase.RACING:
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
## the loop's span left once [param kart_clearance] metres either side of [param kart_distance] (the
## kart's own current arclength along the same line) are excluded. Empty for a count of zero or a
## line too short to hold the excluded band.
##
## Stratified rather than uniformly random: a ghost is drawn inside its own slot, never across the
## whole line, so a field re-rolled at every countdown can neither clump three ghosts into one
## corner nor leave a quarter of the lap bare. [param jitter] is the fraction of its slot a ghost
## may cross; at 0.0 every ghost sits exactly on its slot's midpoint.
##
## The excluded band wraps rather than clamping at the line's own ends: the line is a full lap cut
## open at the start line, so "behind" the kart's arclength position is the tail end of the same
## lap, not off the line entirely. [param kart_distance] of 0.0 reproduces the field's old
## behaviour at the moment a Run starts, when the kart sits at that same cut point.
##
## Purely a walk along the given line: it knows nothing about the road's actual width, so it
## returns the line pose only. Fanning a ghost out to either side of that pose needs [method
## _lateral_placements], not this static function; a TestCase is a RefCounted that cannot touch the
## scene tree, and this is the seam the geometry suite tests.
##
## Parameter named clearance rather than kart_clearance (which the exported [member kart_clearance]
## already claims on this class): GDScript's shadowed_variable check fires on a static function
## parameter reusing an instance member's name, even though the two never interact.
static func place_along(
	positions: PackedVector3Array,
	yaws: PackedFloat32Array,
	count: int,
	kart_distance: float,
	clearance: float,
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
	var usable: float = total - 2.0 * clearance
	if usable <= 0.0:
		return result

	# Slot midpoints, not endpoints: i * usable / (count - 1) divides by zero at count == 1 and puts
	# ghosts hard against the margins they were just told to respect.
	var slot: float = usable / count
	for i in count:
		var centre: float = kart_distance + clearance + (i + 0.5) * slot
		var target: float = fposmod(
			centre + rng.randf_range(-0.5, 0.5) * jitter * slot, total)
		result.append(_pose_at(positions, yaws, cumulative, target))

	return result


## The nearest centreline sample to [param point], returned as that sample's own arclength — where
## along the line the kart currently is, for [member kart_clearance]'s exclusion band.
## RoadCentreline._nearest_index's identical squared-distance search, duplicated here since
## RoadCentreline carries no cumulative array of its own to resolve the index into an arclength.
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

	var kart_distance: float = 0.0
	if _kart != null and not _centreline_cumulative.is_empty():
		kart_distance = _kart_arclength(
			_centreline_positions, _centreline_cumulative, _kart.global_position)

	var poses: Array[Transform3D] = place_along(
		_centreline_positions,
		_centreline_yaws,
		ghost_count,
		kart_distance,
		kart_clearance,
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
## own "next" direction, which still yields a driveable centreline but no longer lines up arclength
## 0.0 with where the driver actually starts.
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

	_centreline_cumulative = PackedFloat32Array()
	_centreline_cumulative.append(0.0)
	for i in range(1, loop.size()):
		_centreline_cumulative.append(
			_centreline_cumulative[i - 1] + loop[i - 1].distance_to(loop[i]))


## Fans [param pose] out into [member lateral_ghost_count] ghosts perpendicular to the road: the
## first stays pinned to the centreline itself, and the rest alternate right/left of it at
## increasing multiples of [member lateral_spacing] ([method _lateral_offset]). No check against
## the true road edge — every one of the fan is placed, so a wide fan on a narrow stretch of road
## can hang ghosts over the kerb or the grass; that's on whoever tunes lateral_ghost_count and
## lateral_spacing, not something placement polices.
func _lateral_placements(pose: Transform3D) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	var right: Vector3 = pose.basis.x

	for i in lateral_ghost_count:
		var offset: float = _lateral_offset(i)
		# basis.x is the pose's own right vector, so the offset leans with the line through a
		# corner instead of being re-derived from the yaw here. translated, not translated_local:
		# the vector is already in the line's space.
		result.append(pose.translated(right * offset))
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


func _spawn_ghost(pose: Transform3D) -> Ghost:
	var wrapper := Node3D.new()
	_ghosts_root.add_child(wrapper)
	wrapper.global_transform = pose

	var model: Node3D = GHOST_MODEL.instantiate() as Node3D
	wrapper.add_child(model)
	# The FBX's own axes don't match the road's forward/up/scale; this is the same corrective local
	# transform authored on every hand-placed pad's Ghost child and on PaceGhost's SportsCar child,
	# scaled by this ghost's own drawn car scale, which is also what its capsule is measured from —
	# the silhouette IS the hitbox. 0.02, not PaceGhost's 0.0: just enough lift to keep the belly off
	# the road mesh without floating it visibly above the ground the way the old 0.1 did.
	var car_scale: float = _rng.randf_range(min_car_scale, maxf(min_car_scale, max_car_scale))
	var model_scale: Vector3 = MODEL_SCALE_PER_FRACTION * car_scale
	model.transform = Transform3D(Basis().scaled(model_scale), Vector3(0.0, 0.02, 0.0))

	var half_extents: Vector2 = Hitbox.model_half_extents(model_scale) * hitbox_scale
	var ghost := Ghost.new()
	ghost.node = wrapper
	ghost.origin = pose.origin
	ghost.yaw = Hitbox.yaw_of(pose.basis)
	ghost.half_length = half_extents.x
	ghost.half_width = half_extents.y
	ghost.material = _build_ghost_material()
	_apply_material(model, ghost.material)
	return ghost


func _sweep_ghosts() -> void:
	# Re-checked: the director's sweep is queued first and can end the Run inside this same flush.
	if _director.phase != RunDirector.RunPhase.RACING:
		return

	var centre: Vector3 = _kart.hitbox_centre
	var yaw: float = _kart.hitbox_yaw
	# The first Racing frame after a teleport records a position and tests nothing: a segment
	# spanning the teleport would sweep half the circuit.
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

	for ghost: Ghost in _ghosts:
		if ghost.taken:
			continue
		if not _sweep.takes(ghost.origin, ghost.yaw, ghost.half_length, ghost.half_width):
			continue
		if absf(centre.y - ghost.origin.y) > max_vertical_gap:
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
## during the countdown — the signal that exists precisely for this. Not called on run_completed:
## rearranging the circuit while the player is still reading the Results screen.
func _on_countdown_started() -> void:
	_has_last_kart_pose = false
	_place_ghosts()


## Re-places the whole field at every wrap too ([signal RunDirector.wrapped]), the same as
## ClockField: a boost taken on one lap is offered again on the next, at freshly rolled positions,
## rather than the field thinning out over a long Run. No teleport happens on a wrap, so unlike
## [method _on_countdown_started] this leaves [member _has_last_kart_pose] alone — the swept
## segment carries straight through the wrap.
func _on_wrapped() -> void:
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


## Everything a Rewind must put back, as plain data, for ClockField.capture_state's identical
## reason and identical shape — plus [member _elapsed], the pulse's own clock, so a restored ghost's
## alpha wobble does not visibly jump.
func capture_state() -> Dictionary:
	var taken: PackedByteArray = PackedByteArray()
	taken.resize(_ghosts.size())
	for i in _ghosts.size():
		taken[i] = 1 if _ghosts[i].taken else 0
	return {
		"taken": taken,
		"elapsed": _elapsed,
		"last_kart_centre": _last_kart_centre,
		"last_kart_yaw": _last_kart_yaw,
		"has_last_kart_pose": _has_last_kart_pose,
	}


## Puts back exactly what [method capture_state] produced, for ClockField.restore_state's identical
## reason: a ghost's node.visible is derived from its taken flag.
func restore_state(state: Dictionary) -> void:
	var taken: PackedByteArray = state["taken"]
	for i in mini(taken.size(), _ghosts.size()):
		var ghost: Ghost = _ghosts[i]
		ghost.taken = taken[i] != 0
		ghost.node.visible = not ghost.taken
	_elapsed = state["elapsed"]
	_last_kart_centre = state["last_kart_centre"]
	_last_kart_yaw = state["last_kart_yaw"]
	_has_last_kart_pose = state["has_last_kart_pose"]


## One ghost, resolved at spawn. RefCounted for ClockField.Clock's reason: no allocation in the
## physics step, only at a re-place.
class Ghost extends RefCounted:
	var node: Node3D = null # the wrapper; visibility toggles here
	var origin: Vector3 = Vector3.ZERO
	## Which way this ghost's capsule lies. Fixed at spawn: a boost ghost stands still.
	var yaw: float = 0.0
	## Half this ghost's capsule, nose to tail and kerb to kerb. The model's own footprint under the
	## scale it was drawn at, times [member BoostGhostField.hitbox_scale]; see [method
	## BoostGhostField._spawn_ghost].
	var half_length: float = 0.0
	var half_width: float = 0.0
	var material: StandardMaterial3D = null
	var taken: bool = false
