class_name HazardGhostField
extends Node

## Owner of the hazard ghosts: where they are, which are currently taken, and the swept test that
## takes them. Modelled on BoostGhostField, with two differences that follow from being oncoming
## traffic rather than a pickup: a hazard ghost stands exactly on the ghost line (no lateral
## jitter — "the line you set" is the line, not beside it) and it moves, backward along that line,
## rather than standing still.
##
## The slow-down lives on the field, not on the ghost, for BoostGhostField's reason: every hazard
## on a circuit costs the same, so there is one multiplier here rather than per-ghost metadata.
##
## Placed at runtime along the lap director's ghost line exactly as boost ghosts are: the line only
## changes when a lap takes the record, and a re-place first frees whatever stood there before.

## One ghost, the instant it is taken. Position only, for BoostGhostField's reason.
signal hazard_hit(position: Vector3)

## The same imported model every ghost in this game uses. No hazard_car.tscn: the field instances
## this directly, one per placement.
const GHOST_MODEL: PackedScene = preload("res://cars/FBX/SportsCar.fbx")

## The model scale the FBX's own axis correction ([method _spawn_ghost]) is built from, per unit
## of [member pickup_radius_fraction], for BoostGhostField.MODEL_SCALE_PER_FRACTION's identical
## reason and identical derivation.
const MODEL_SCALE_PER_FRACTION: Vector3 = Vector3(-0.1375, 0.15, -0.1)

@export var kart_path: NodePath
@export var director_path: NodePath
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

## Metres of ghost line left clear at the start and end, for BoostGhostField's reason: a hazard is
## never handed before the driver has picked up speed off the line, nor right before the final
## gate.
@export var start_margin: float = 10.0
@export var end_margin: float = 10.0

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
## Fraction of the kart's own collision radius ([member Kart.sphere_radius]) a hazard reaches out
## to, for BoostGhostField.pickup_radius_fraction's identical reason and identical default.
@export var pickup_radius_fraction: float = 4.0

## Metres of vertical gap the swept test still counts as a hit, for CoinField.max_vertical_gap's
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

## Whether the path preview ribbon is drawn at all. A setter, for ghost_count's reason: one door,
## rather than the mesh instance's own visible flag becoming a second place this can be toggled.
@export var line_visible: bool = true:
	set(value):
		line_visible = value
		if _line_mesh_instance != null:
			_line_mesh_instance.visible = value
## Metres wide the ribbon is painted, square across the line.
@export var line_width: float = 0.6
## Lifted this far above the recorded line, so the ribbon doesn't z-fight the road it was recorded
## driving on.
@export var line_height_offset: float = 0.05
## Deliberately its own colour rather than a read of [member ghost_color]: the ribbon is the whole
## line every hazard on the circuit will eventually reach, not any one hazard, so it is tuned apart.
@export var line_color: Color = Color(0.95, 0.1, 0.1, 0.2)

var _kart: Kart
var _director: RunDirector
var _ghosts_root: Node3D
var _ghosts: Array[Hazard] = []
var _cumulative: PackedFloat32Array = PackedFloat32Array()
var _total_length: float = 0.0
var _last_kart_position: Vector3 = Vector3.ZERO
var _has_last_kart_position: bool = false
var _elapsed: float = 0.0
## pickup_radius_fraction resolved against the kart's sphere_radius, for
## BoostGhostField._pickup_radius's identical reason.
var _pickup_radius: float = 0.0
# Seeded randomly on creation by Godot and never re-seeded, for BoostGhostField._rng's reason.
var _rng := RandomNumberGenerator.new()
var _line_mesh_instance: MeshInstance3D


func _ready() -> void:
	_kart = get_node_or_null(kart_path) as Kart
	_director = get_node_or_null(director_path) as RunDirector
	_ghosts_root = get_node_or_null(ghosts_path) as Node3D
	if _kart != null:
		_pickup_radius = pickup_radius_fraction * _kart.sphere_radius

	if _director != null:
		_director.countdown_started.connect(_on_countdown_started)

	if _ghosts_root == null:
		push_warning("HazardGhostField: no HazardGhosts node — nothing to spawn traffic into.")
		return

	_line_mesh_instance = MeshInstance3D.new()
	_line_mesh_instance.visible = line_visible
	_line_mesh_instance.material_override = _build_line_material()
	_ghosts_root.add_child(_line_mesh_instance)


## Deferred for CoinField's reason: the director runs at the head of the physics frame and the kart
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
## metres, one per equal slot of the span left by the margins — BoostGhostField.place_along's
## stratification, minus the pose resolution and the lateral offset: a hazard has no side to stand
## on, only a place in the line to start driving from.
static func place_along(
	total_length: float,
	count: int,
	margin_start: float,
	margin_end: float,
	rng: RandomNumberGenerator,
	jitter: float,
) -> Array[float]:
	var result: Array[float] = []
	if count <= 0 or total_length <= 0.0:
		return result

	var usable: float = total_length - margin_start - margin_end
	if usable <= 0.0:
		return result

	var slot: float = usable / count
	for i in count:
		var centre: float = margin_start + (i + 0.5) * slot
		var target: float = centre + rng.randf_range(-0.5, 0.5) * jitter * slot
		result.append(target)

	return result


## The pose a hazard driving backward along the line shows at arclength [param distance]:
## BoostGhostField._pose_at's walk, with pi added to the yaw so the ghost faces the direction it is
## actually travelling rather than the lap's own forward.
static func _pose_at(
	positions: PackedVector3Array,
	yaws: PackedFloat32Array,
	cumulative: PackedFloat32Array,
	distance: float,
) -> Transform3D:
	var index: int = 0
	while index < cumulative.size() - 2 and cumulative[index + 1] < distance:
		index += 1

	var segment_length: float = cumulative[index + 1] - cumulative[index]
	var weight: float = 0.0
	if segment_length > 0.0:
		weight = clampf((distance - cumulative[index]) / segment_length, 0.0, 1.0)

	var position: Vector3 = positions[index].lerp(positions[index + 1], weight)
	var yaw: float = lerp_angle(yaws[index], yaws[index + 1], weight) + PI
	return Transform3D(Basis(Vector3.UP, yaw), position)


## Frees the standing field and places a fresh one on the director's current ghost line. An empty
## ghost line yields no ghosts and is not a warning, for BoostGhostField's reason: it is lap 1.
func _place_ghosts() -> void:
	for hazard: Hazard in _ghosts:
		hazard.node.queue_free()
	_ghosts.clear()

	if _ghosts_root == null or _director == null:
		return

	_build_cumulative()
	_rebuild_line_mesh()
	if _total_length <= 0.0:
		return

	var distances: Array[float] = place_along(
		_total_length,
		ghost_count,
		start_margin,
		end_margin,
		_rng,
		placement_jitter,
	)
	for distance: float in distances:
		_ghosts.append(_spawn_ghost(distance))


## Cumulative arc length at each ghost-line sample, rebuilt whenever the line itself changes
## (a re-place). Kept rather than recomputed every frame: _advance_ghosts walks it every physics
## tick for every hazard, and the line stands unchanged for many laps at a time.
func _build_cumulative() -> void:
	_cumulative = PackedFloat32Array()
	_total_length = 0.0

	var positions: PackedVector3Array = _director.ghost_line_positions
	if positions.size() < 2:
		return

	_cumulative.append(0.0)
	for i in range(1, positions.size()):
		_cumulative.append(_cumulative[i - 1] + positions[i - 1].distance_to(positions[i]))
	_total_length = _cumulative[_cumulative.size() - 1]


## Redraws the path-preview ribbon from the whole ghost line, not just the hazards placed on it: the
## line is what every hazard drives, and stays true even at ghost_count == 0. Called wherever the
## line itself is rebuilt, alongside [method _build_cumulative].
func _rebuild_line_mesh() -> void:
	if _line_mesh_instance == null:
		return

	var positions: PackedVector3Array = _director.ghost_line_positions
	var yaws: PackedFloat32Array = _director.ghost_line_yaws
	if positions.size() < 2:
		_line_mesh_instance.mesh = null
		return

	# A quad strip, not a PRIMITIVE_LINE_STRIP: line primitives render at a fixed 1 px under the GL
	# Compatibility renderer this project targets, which [member line_width] could not affect at all.
	var vertices := PackedVector3Array()
	var half_width: float = line_width * 0.5
	var lift: Vector3 = Vector3.UP * line_height_offset
	for i in positions.size():
		# The sample's own right vector, for BoostGhostField.place_along's identical reason: the
		# ribbon leans with the line through a corner instead of staying world-axis-aligned.
		var right: Vector3 = Basis(Vector3.UP, yaws[i]).x
		var centre: Vector3 = positions[i] + lift
		vertices.append(centre + right * half_width)
		vertices.append(centre - right * half_width)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, arrays)
	mesh.surface_set_material(0, _line_mesh_instance.material_override)
	_line_mesh_instance.mesh = mesh


func _build_line_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = line_color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Both faces: the ribbon is walked in the line's own direction, so a kart looking back along it
	# would otherwise see the strip vanish from the back.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _spawn_ghost(distance: float) -> Hazard:
	var wrapper := Node3D.new()
	_ghosts_root.add_child(wrapper)
	wrapper.global_transform = _pose_at(
		_director.ghost_line_positions, _director.ghost_line_yaws, _cumulative, distance)

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
	hazard.origin = wrapper.global_position
	hazard.speed = _rng.randf_range(min_speed, max_speed)
	hazard.material = _build_ghost_material()
	_apply_material(model, hazard.material)
	return hazard


## Steps every untaken hazard backward along the line by its own speed, wrapping past the start
## back to the end — continuous oncoming traffic rather than a single pass.
func _advance_ghosts(delta: float) -> void:
	if _total_length <= 0.0:
		return

	var positions: PackedVector3Array = _director.ghost_line_positions
	var yaws: PackedFloat32Array = _director.ghost_line_yaws

	for hazard: Hazard in _ghosts:
		if hazard.taken:
			continue
		var step: float = hazard.speed * delta
		hazard.distance = fposmod(hazard.distance - step, _total_length)
		var pose: Transform3D = _pose_at(positions, yaws, _cumulative, hazard.distance)
		hazard.node.global_transform = pose
		hazard.origin = pose.origin


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

	for hazard: Hazard in _ghosts:
		if hazard.taken:
			continue
		if not CoinField.segment_takes_coin(previous, position, hazard.origin, _pickup_radius):
			continue
		if absf(position.y - hazard.origin.y) > max_vertical_gap:
			continue
		# The swept test itself ignores height (see class doc), so a hop dodges by immunity rather
		# than clearance: the hazard is not taken and the driver keeps whatever position the hop
		# was spent avoiding, rather than banking a free hit for landing back on the line.
		if _kart.is_hopping:
			continue
		hazard.taken = true
		hazard.node.visible = false
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


## One hazard, resolved at spawn. RefCounted for CoinField.Coin's reason.
class Hazard extends RefCounted:
	var node: Node3D = null # the wrapper; visibility toggles here
	var distance: float = 0.0 # arclength along the ghost line, decreasing as it drives
	var speed: float = 0.0 # m/s, picked once at spawn from [min_speed, max_speed]
	var origin: Vector3 = Vector3.ZERO
	var material: StandardMaterial3D = null
	var taken: bool = false
