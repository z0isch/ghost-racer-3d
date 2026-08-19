class_name CircuitEntryTrigger
extends Node

## Watches for the kart's swept path crossing a circuit's StartLine marker, in either direction,
## and sends the kart into the race scene to run that circuit.
##
## The crossing test is [class CheckpointPrism], shared with [method
## LapDirector._sweep_pending_checkpoint]: a plane crossing bounded laterally and vertically so it
## cannot be tunnelled at any speed, carried in the start line marker's own frame so it rolls with
## the road exactly as a checkpoint prism does.
##
## Starts disarmed and stays that way until the kart has stood clear of the start line continuously
## for [member rearm_seconds] — clear meaning either [member rearm_clear_distance] along the plane's
## forward axis, or outside the crossable lateral/vertical bounds. The prism itself has no depth
## along the road — CONTEXT.md, **Checkpoint prism**, "it is crossed, not entered" — so a kart
## returned to the exact entry pose sits with before/after both ~0 and would re-cross on the very
## first metre driven forward; the forward-axis leg of the clearance test is what survives that.
## The lateral/vertical leg is what survives the opposite case: a kart parked or crawling beside
## the gate, near-zero forward offset the whole time, which the forward-axis test alone would never
## call clear.

const RACE_SCENE_PATH: String = "res://scenes/race.tscn"

@export var kart_path: NodePath
@export var start_line_path: NodePath
## The circuit this entrance guards. Carried into [autoload CircuitSession] on crossing, so
## race.tscn knows which geometry and ghost line to load without either scene hardcoding a path.
@export var circuit: Circuit

@export var checkpoint_half_width: float = 4.0
@export var checkpoint_floor: float = -1.0
@export var checkpoint_ceiling: float = 5.0

## How far along the start line's forward axis counts as "clear" while disarmed.
@export var rearm_clear_distance: float = 2.0
## How long the kart must stand clear before the trigger arms.
@export var rearm_seconds: float = 0.5

var _kart: Kart
var _origin: Vector3 = Vector3.ZERO
var _forward: Vector3 = Vector3.ZERO
var _right: Vector3 = Vector3.ZERO
var _up: Vector3 = Vector3.ZERO

var _armed: bool = false
var _clear_seconds: float = 0.0
var _entering: bool = false

var _last_kart_position: Vector3 = Vector3.ZERO
var _has_last_kart_position: bool = false


func _ready() -> void:
	_kart = get_node_or_null(kart_path) as Kart
	var start_line: Node3D = get_node_or_null(start_line_path) as Node3D
	if _kart == null or start_line == null:
		push_warning("CircuitEntryTrigger: missing Kart or StartLine — this entrance is dead.")
		return

	var frame: Transform3D = start_line.global_transform
	_origin = frame.origin
	_forward = -frame.basis.z.normalized()
	_right = frame.basis.x.normalized()
	_up = frame.basis.y.normalized()


func _physics_process(delta: float) -> void:
	if _kart == null or _entering:
		return

	if not _armed:
		_update_rearm(delta)
		return

	_sweep(delta)


func _update_rearm(delta: float) -> void:
	var local: Vector3 = _kart.global_position - _origin
	var signed_forward: float = local.dot(_forward)
	var lateral: float = local.dot(_right)
	var height: float = local.dot(_up)
	var clear: bool = (absf(signed_forward) > rearm_clear_distance
			or absf(lateral) > checkpoint_half_width
			or height < checkpoint_floor or height > checkpoint_ceiling)

	_clear_seconds = _clear_seconds + delta if clear else 0.0
	if _clear_seconds >= rearm_seconds:
		_armed = true
		_has_last_kart_position = false


## Called by [World] when it teleports the kart directly (the `reset` action, not a countdown or a
## circuit entry): the swept segment this trigger is tracking would otherwise span the teleport and
## could spuriously cross this plane, exactly the failure [method LapDirector._begin_countdown] and
## [method BoostGhostField._on_countdown_started] already guard their own teleports against.
## Disarming rather than just dropping the sample: a kart reset onto or near a start line should be
## re-measured for clearance before this trigger can fire again, the same as a return from a race.
func invalidate() -> void:
	_armed = false
	_clear_seconds = 0.0
	_has_last_kart_position = false


func _sweep(_delta: float) -> void:
	var position: Vector3 = _kart.global_position

	# The first armed frame records a position and tests nothing: a segment spanning the rearm
	# would sweep back through space the kart never actually crossed this pass.
	if not _has_last_kart_position:
		_last_kart_position = position
		_has_last_kart_position = true
		return

	var previous: Vector3 = _last_kart_position
	_last_kart_position = position

	var crossed: bool = CheckpointPrism.crossed(previous, position, _origin, _forward, _right, _up,
			checkpoint_half_width, checkpoint_floor, checkpoint_ceiling)
	if crossed:
		_enter()


func _enter() -> void:
	_entering = true
	CircuitSession.pending_circuit = circuit
	CircuitSession.return_pose = _kart.global_transform
	CircuitSession.has_return_pose = true
	_kart.frozen = true

	# A failed swap fades back into the world that is still standing here: undo the one-shot latch
	# so this entrance is not left permanently dead and the kart is not left permanently frozen.
	var err: Error = await SceneFade.to_scene(get_tree(), RACE_SCENE_PATH)
	if err != OK:
		_entering = false
		_kart.frozen = false
