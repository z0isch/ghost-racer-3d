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
## runtime along the lap director's ghost line, one per equal slot of it and jittered inside that
## slot, so a re-place first frees whatever stood there before rather than restoring a fixed set.
## The ghost line only changes when a lap takes the record, so the jitter is the only thing standing
## between the driver and the identical field lap after lap.
##
## Each ghost then moves off that racing-line pose to wherever it actually stands: anywhere across
## the drivable road, found by probing the real road edge rather than a hand-tuned offset, or onto a
## nearby coin if one is close enough to hand the ghost to it instead of leaving two separate things
## to line up for. See [method _place_off_line].

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

@export var kart_path: NodePath
@export var director_path: NodePath
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

## Metres of ghost line left clear at the start, so a ghost is never handed before the driver has
## picked up speed off the line.
@export var start_margin: float = 10.0
## Metres of ghost line left clear at the end, so a ghost is never handed right before the final
## gate.
@export var end_margin: float = 10.0

## Fraction of its own slot a ghost may wander across. 0.0 pins every ghost to its slot's midpoint,
## which is a fixed field for as long as the ghost line stands; 1.0 lets a ghost reach the slot edge
## it shares with its neighbour.
@export_range(0.0, 1.0) var placement_jitter: float = 0.3

## Metres kept clear of the true road edge when a ghost is placed off the racing line, so its
## silhouette never hangs its outside wheels over the kerb or onto the grass.
@export var edge_clearance: float = 1.0
## How far out, in metres, the road-edge probe searches from the racing line before giving up.
## Bounds the cost of a placement's probe rather than describing any real track width; it only needs
## to clear the widest shoulder on the circuit.
@export var edge_probe_range: float = 15.0
## Step size, in metres, the road-edge probe walks outward while it is still finding road. Smaller
## is a more exact edge and a slower probe; this only runs once per ghost at every countdown, so it
## is kept small rather than tuned for speed.
@export var edge_probe_step: float = 0.25

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


## Deferred for CoinField's reason: the director runs at the head of the physics frame and the kart
## moves after it, so the position the kart finishes the frame at only exists after the flush.
##
## The dev inputs live here, not gated on phase or on whether a ghost line exists: the field owns
## the count, so the field owns the input that changes it, and pressing `]` on lap 1 must still
## raise the count that lap 2 opens with.
func _physics_process(_delta: float) -> void:
	if _kart != null and _director != null and _director.phase == LapDirector.LapPhase.RACING:
		_sweep_ghosts.call_deferred()

	if Input.is_action_just_pressed("dev_boost_more"):
		ghost_count += 1
	if Input.is_action_just_pressed("dev_boost_fewer"):
		ghost_count -= 1


## The pulse runs at display rate: it is not load-bearing and is never read back by the take test.
func _process(delta: float) -> void:
	_elapsed += delta
	var alpha_scale: float = 1.0 + sin(_elapsed * TAU * pulse_hz) * pulse_amplitude
	var color: Color = ghost_color
	color.a = clampf(color.a * alpha_scale, 0.0, 1.0)

	for ghost: Ghost in _ghosts:
		if not ghost.taken:
			ghost.material.albedo_color = color


## Centreline poses for [param count] boost ghosts along the ghost line, one per equal slot of the
## span left by [param margin_start] / [param margin_end]. Empty for a count of zero or a line too
## short to hold the margins.
##
## Stratified rather than uniformly random: a ghost is drawn inside its own slot, never across the
## whole line, so a field re-rolled at every countdown can neither clump three ghosts into one
## corner nor leave a quarter of the lap bare. [param jitter] is the fraction of its slot a ghost
## may cross; at 0.0 every ghost sits exactly on its slot's midpoint.
##
## Purely a walk along the recorded line: it knows nothing about the road's actual width, so it
## returns the racing-line pose only. Moving a ghost off that pose — to anywhere still on the road,
## or onto a nearby coin — needs the physics world and is [method _place_off_line]'s job, not this
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


## Frees the standing field and places a fresh one on the director's current ghost line. An empty
## ghost line yields no ghosts and is not a warning — it is lap 1, and it is the designed state.
func _place_ghosts() -> void:
	for ghost: Ghost in _ghosts:
		ghost.node.queue_free()
	_ghosts.clear()

	if _ghosts_root == null or _director == null:
		return

	var poses: Array[Transform3D] = place_along(
		_director.ghost_line_positions,
		_director.ghost_line_yaws,
		ghost_count,
		start_margin,
		end_margin,
		_rng,
		placement_jitter,
	)
	for pose: Transform3D in poses:
		_ghosts.append(_spawn_ghost(_place_off_line(pose)))


## Moves a centreline pose to where it actually stands: somewhere across the drivable road rather
## than pinned to the racing line, unless a coin stands close enough to hand the ghost to it
## instead.
##
## The road's true width is not known data anywhere on the circuit (CoinField and the checkpoints
## are the only other things that care, and both were hand-tuned rather than measured) so it is
## probed the same way [member Kart._classify_surface] tells road from grass under the kart: a ray
## straight down, read for the collider's own layer bits. [method _road_half_width_at] walks that
## probe outward until it leaves the road, which is the road's actual edge on a corner exactly as
## much as on a straight, camber and kerb included.
func _place_off_line(pose: Transform3D) -> Transform3D:
	var half_width: float = _road_half_width_at(pose.origin, pose.basis.x)
	var offset: float = _rng.randf_range(-half_width, half_width)
	# basis.x is the pose's own right vector, so the offset leans with the line through a corner
	# instead of being re-derived from the yaw here. translated, not translated_local: the vector is
	# already in the line's space.
	var off_line: Transform3D = pose.translated(pose.basis.x * offset)

	var snap: Vector3 = _nearest_coin_within(off_line.origin, coin_snap_radius)
	if snap != off_line.origin:
		off_line.origin = snap
	return off_line


## Metres a ghost may stand either side of [param position] along [param right] before it leaves the
## road, less [member edge_clearance] so its silhouette clears the true edge. Symmetric bound: the
## smaller of the two sides, so a ghost drawn anywhere in [-half_width, half_width] is on the road
## whichever side of the line it lands on.
func _road_half_width_at(position: Vector3, right: Vector3) -> float:
	var left_extent: float = _probe_edge(position, -right)
	var right_extent: float = _probe_edge(position, right)
	return maxf(0.0, minf(left_extent, right_extent) - edge_clearance)


## Walks outward from [param origin] in [param direction] in [member edge_probe_step] increments,
## stopping at the first step that is no longer road (grass, or nothing under it at all) or at
## [member edge_probe_range], whichever comes first.
func _probe_edge(origin: Vector3, direction: Vector3) -> float:
	var distance: float = 0.0
	while distance < edge_probe_range:
		var next_distance: float = distance + edge_probe_step
		if not _is_on_road(origin + direction * next_distance):
			break
		distance = next_distance
	return distance


## The same test [member Kart._classify_surface] runs on the kart's own ground ray, aimed instead at
## an arbitrary point: a downward ray read for the collider's layer bits, grass excluded and
## everything else (road, kerb) counted as road. Kerb counts as road here because it does for the
## kart: the ghost may stand on it exactly as the driver may drive over it.
func _is_on_road(position: Vector3) -> bool:
	# get_world_3d() is a Node3D method; the field is a plain Node, so the world comes from the
	# viewport instead.
	var space_state: PhysicsDirectSpaceState3D = get_viewport().get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		position + Vector3.UP * 2.0, position + Vector3.DOWN * 4.0)
	# Matches GroundRay's own mask (kart.tscn): the general ground layer plus grass, which is enough
	# to tell "off the road" from "on it" without also needing the barrier layer.
	query.collision_mask = 9
	var hit: Dictionary = space_state.intersect_ray(query)
	if hit.is_empty():
		return false

	var collider: Object = hit["collider"]
	var layer: int = -1
	if collider is CSGShape3D:
		layer = (collider as CSGShape3D).collision_layer
	elif collider is CollisionObject3D:
		layer = (collider as CollisionObject3D).collision_layer
	if layer < 0:
		return false

	return (layer & Kart.GRASS_LAYER_BIT) == 0


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
