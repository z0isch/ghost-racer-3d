class_name BoostPadField
extends Node

## Owner of the boost pads: where they are, which are currently taken, and the swept test that
## takes them. The boost lives on the field, not on the pads — every pad on a circuit is worth
## exactly the same, which is the playtest's finding, not an implementation shortcut — so there is
## one bump and one bleed here rather than per-pad metadata.
##
## Modelled on CoinField deliberately, down to the lifecycle: a pad is taken once and stays taken
## for the rest of the lap, exactly as a coin is, and the whole field is restored at every
## countdown. Purely spatial: it emits [signal pad_taken] and knows nothing about who listens — not
## the camera's FOV punch, not the kart's speed.

## One pad, the instant it is taken. Position only — there is no per-pad value to report, since
## every pad grants the same bump.
signal pad_taken(position: Vector3)

@export var kart_path: NodePath
@export var director_path: NodePath
## The circuit's BoostPads node: one Marker3D per pad, each with a Ghost model child.
@export var pads_path: NodePath

## m/s put straight into forward speed, above the tuned ceiling. Every pad on the circuit.
@export var bump: float = 10.0
## m/s^2 the overspeed comes back off at. Every pad on the circuit.
@export var bleed: float = 5.0
## Wider than a coin's: the pad is a car-sized silhouette, and clipping its wing should count.
@export var pickup_radius: float = 2.0

## Alpha wobble, so a pad reads as a ghost standing there rather than a parked car to swerve
## around.
@export var pulse_amplitude: float = 0.12
@export var pulse_hz: float = 1.1
@export var ghost_color: Color = Color(0.55, 0.85, 1.0, 0.35)

var _kart: Kart
var _director: LapDirector
var _pads: Array[Pad] = []
var _last_kart_position: Vector3 = Vector3.ZERO
var _has_last_kart_position: bool = false
var _elapsed: float = 0.0


func _ready() -> void:
	_kart = get_node_or_null(kart_path) as Kart
	_director = get_node_or_null(director_path) as LapDirector

	if _director != null:
		_director.countdown_started.connect(_on_countdown_started)

	_resolve_pads()


## Deferred for CoinField's reason: the director runs at the head of the physics frame and the kart
## moves after it, so the position the kart finishes the frame at only exists after the flush.
func _physics_process(_delta: float) -> void:
	if _kart == null or _director == null or _director.phase != LapDirector.LapPhase.RACING:
		return
	_sweep_pads.call_deferred()


## The pulse runs at display rate: it is not load-bearing and is never read back by the take test.
func _process(delta: float) -> void:
	_elapsed += delta
	var alpha_scale: float = 1.0 + sin(_elapsed * TAU * pulse_hz) * pulse_amplitude
	var color: Color = ghost_color
	color.a = clampf(color.a * alpha_scale, 0.0, 1.0)

	for pad: Pad in _pads:
		if not pad.taken:
			pad.material.albedo_color = color


func _resolve_pads() -> void:
	var root: Node3D = get_node_or_null(pads_path) as Node3D
	if root == null:
		push_warning("BoostPadField: no BoostPads node — nothing to boost off.")
		return

	var found: Array[Pad] = []
	for child: Node in root.get_children():
		var marker: Node3D = child as Node3D
		if marker == null:
			continue
		var pad := Pad.new()
		pad.node = marker
		pad.origin = marker.global_position
		pad.material = _build_ghost_material()
		_apply_material(marker, pad.material)
		found.append(pad)

	_pads = found


func _sweep_pads() -> void:
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

	for pad: Pad in _pads:
		if pad.taken:
			continue
		if not CoinField.segment_takes_coin(previous, position, pad.origin, pickup_radius):
			continue
		pad.taken = true
		pad.node.visible = false
		_kart.apply_boost(bump, bleed)
		pad_taken.emit(pad.origin)


## Restores every pad at every countdown, as the coin field does, so two laps are offered the same
## track. No respawn timer of any kind — a taken flag and this restore are the whole lifecycle.
func _on_countdown_started() -> void:
	_has_last_kart_position = false
	for pad: Pad in _pads:
		pad.taken = false
		pad.node.visible = true


# Built here rather than authored on the mesh, for PaceGhost's reason: the pad instances the same
# imported FBX as the kart, whose internal node structure belongs to the importer.
func _build_ghost_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = ghost_color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Stops the pad's own faces blending over each other, so it reads as one body.
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	return material


func _apply_material(node: Node, material: StandardMaterial3D) -> void:
	var mesh: MeshInstance3D = node as MeshInstance3D
	if mesh != null:
		mesh.material_override = material
	for child: Node in node.get_children():
		_apply_material(child, material)


## One pad, resolved once from its marker. RefCounted for CoinField.Coin's reason: built in
## _ready, never allocated in the physics step.
class Pad extends RefCounted:
	var node: Node3D = null
	var origin: Vector3 = Vector3.ZERO
	var material: StandardMaterial3D = null
	var taken: bool = false
