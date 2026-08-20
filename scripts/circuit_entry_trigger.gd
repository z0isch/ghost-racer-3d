class_name CircuitEntryTrigger
extends Node

## Watches whether the kart is standing on this circuit's own track and, while it is, lets the
## player press the `enter_circuit` action to send the kart into the race scene to run that
## circuit.
##
## "Standing on this circuit's track" is inferred rather than authored: [member Kart.
## current_ground_collider] is whatever node the kart's ground ray is resting on, and that node
## is a descendant of this circuit's own scene subtree if and only if the kart is on this
## circuit's road — no separate track-area volume needs to be authored per circuit, and the test
## stays correct if a circuit's road geometry changes shape.

const RACE_SCENE_PATH: String = "res://scenes/race.tscn"

## [CircuitEntryHud] polls every eligible trigger through this group rather than a hand-kept list,
## so a trigger placed straight into main.tscn is found without the HUD needing to know it exists.
const GROUP_NAME: String = "circuit_entry_triggers"

@export var kart_path: NodePath
## The circuit's own StartLine marker. Its parent is the circuit's scene root, which is what
## [member eligible] tests the kart's ground collider against — the start line itself is not
## otherwise used, since entry no longer depends on crossing it.
@export var start_line_path: NodePath
## The circuit this entrance guards. Carried into [autoload CircuitSession] on entry, so race.tscn
## knows which geometry and ghost line to load without either scene hardcoding a path.
@export var circuit: Circuit

var _kart: Kart
var _circuit_root: Node
var _entering: bool = false


func _ready() -> void:
	add_to_group(GROUP_NAME)

	_kart = get_node_or_null(kart_path) as Kart
	var start_line: Node3D = get_node_or_null(start_line_path) as Node3D
	if _kart == null or start_line == null:
		push_warning("CircuitEntryTrigger: missing Kart or StartLine — this entrance is dead.")
		return

	_circuit_root = start_line.get_parent()


## True while the kart is standing on this circuit's own track and free to be sent into it.
var eligible: bool:
	get:
		if _kart == null or _circuit_root == null or _entering:
			return false
		var collider: Node = _kart.current_ground_collider
		return collider != null and _circuit_root.is_ancestor_of(collider)


func _physics_process(_delta: float) -> void:
	if not eligible:
		return
	if Input.is_action_just_pressed("enter_circuit"):
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
