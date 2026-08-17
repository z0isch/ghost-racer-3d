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

## One ghost, the instant it is taken. Position only — there is no per-ghost value to report, since
## every ghost grants the same bump.
signal ghost_taken(position: Vector3)

## The same imported model the kart and pace ghost use. No boost_car.tscn: the field instances this
## directly, one per placement.
const GHOST_MODEL: PackedScene = preload("res://cars/FBX/SportsCar.fbx")

@export var kart_path: NodePath
@export var director_path: NodePath
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

## Metres a ghost stands off the racing line, to one side or the other. Nothing here knows the
## circuit's width, so this is kept inside the narrowest part of the track by hand — the same
## judgement [member ghost_count] is set by.
@export var placement_lateral: float = 1.0

## m/s the banked charge puts straight into forward speed, above the tuned ceiling, once spent.
## Every ghost on the circuit.
@export var bump: float = 10.0
## m/s^2 the overspeed comes back off at, once the charge is spent. Every ghost on the circuit.
@export var bleed: float = 5.0
## Wider than a coin's: the ghost is a car-sized silhouette, and clipping its wing should count.
@export var pickup_radius: float = 2.0

## Alpha wobble, so a ghost reads as a ghost standing there rather than a parked car to swerve
## around.
@export var pulse_amplitude: float = 0.12
@export var pulse_hz: float = 1.1
## Warm amber, deliberately not the pace ghost's blue: the two now share a model, a line and a
## translucency, so colour is the tell rather than a decoration (CONTEXT.md, **Pace ghost**).
@export var ghost_color: Color = Color(1.0, 0.65, 0.2, 0.35)

var _kart: Kart
var _director: LapDirector
var _ghosts_root: Node3D
var _ghosts: Array[Ghost] = []
var _last_kart_position: Vector3 = Vector3.ZERO
var _has_last_kart_position: bool = false
var _elapsed: float = 0.0
# Seeded randomly on creation by Godot and never re-seeded: a fresh draw at every countdown is the
# whole point, so there is no layout worth reproducing.
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_kart = get_node_or_null(kart_path) as Kart
	_director = get_node_or_null(director_path) as LapDirector
	_ghosts_root = get_node_or_null(ghosts_path) as Node3D

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


## Poses for [param count] boost ghosts along the ghost line, one per equal slot of the span left
## by [param margin_start] / [param margin_end]. Empty for a count of zero or a line too short to
## hold the margins.
##
## Stratified rather than uniformly random: a ghost is drawn inside its own slot, never across the
## whole line, so a field re-rolled at every countdown can neither clump three ghosts into one
## corner nor leave a quarter of the lap bare. [param jitter] is the fraction of its slot a ghost
## may cross; at 0.0 every ghost sits exactly on its slot's midpoint.
##
## [param lateral] is the metres a ghost stands off the line, and is the half of this that makes a
## ghost a decision rather than something the line hands you: the side is a coin flip and the
## magnitude is half the value to all of it, so a nonzero setting never quietly puts a ghost back on
## the racing line the driver is already taking.
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
	lateral: float,
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
		var pose: Transform3D = _pose_at(positions, yaws, cumulative, target)

		var side: float = 1.0 if rng.randf() < 0.5 else -1.0
		var offset: float = side * rng.randf_range(0.5, 1.0) * lateral
		# basis.x is the pose's own right vector, so the offset leans with the line through a corner
		# instead of being re-derived from the yaw here. translated, not translated_local: the vector
		# is already in the line's space.
		result.append(pose.translated(pose.basis.x * offset))

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
		placement_lateral,
	)
	for pose: Transform3D in poses:
		_ghosts.append(_spawn_ghost(pose))


func _spawn_ghost(pose: Transform3D) -> Ghost:
	var wrapper := Node3D.new()
	_ghosts_root.add_child(wrapper)
	wrapper.global_transform = pose

	var model: Node3D = GHOST_MODEL.instantiate() as Node3D
	wrapper.add_child(model)
	# The FBX's own axes don't match the road's forward/up/scale; this is the same corrective local
	# transform authored on every hand-placed pad's Ghost child and on PaceGhost's SportsCar child.
	model.transform = Transform3D(Basis().scaled(Vector3(-0.55, 0.6, -0.4)), Vector3(0.0, 0.1, 0.0))

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
		if not CoinField.segment_takes_coin(previous, position, ghost.origin, pickup_radius):
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
