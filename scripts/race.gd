extends Node3D

## Instances the circuit this race is run on as a child named "Circuit", at identity, reading
## which circuit that is from [member CircuitSession.pending_circuit] — the [class Circuit] the
## world's entry trigger carried across the scene swap.
##
## Done in [method _enter_tree] rather than authored into the scene: _enter_tree fires top-down as
## a scene is added to the tree, and this node's fires before any of its siblings' _ready — in
## particular before LapDirector._ready resolves NodePaths like "../Circuit/StartLine" and reads
## its ghost_line_path. Since this node is already inside the tree by the time its own _enter_tree
## runs, add_child here cascades the new child's _enter_tree immediately, ahead of the siblings
## still waiting their turn in the same top-down pass — and get_node("LapDirector") already
## resolves, because the whole scene's node structure exists before any of it enters the tree.
##
## At identity: [member GhostLine.positions] are recorded in the circuit's own coordinates, and any
## transform applied here would invalidate every recorded ghost line. world_transform is the
## world's concern alone (spec: open-world.md).
##
## Falls back to circuit3 when nothing is pending — running race.tscn directly, outside the
## world's entry flow, still plays a circuit rather than nothing.
##
## Also owns exit_circuit: live in any lap phase, deliberately separate from LapDirector's own
## reset/abort handling. Exiting discards the in-progress lap exactly as an abort does — but there
## is nothing to explicitly discard here, since a lap only ever reaches the ghost line and the
## record earn rate through [method LapDirector.complete_lap], and this scene tearing down takes
## the unpromoted recording with it. [autoload CircuitSession]'s return pose was set once, at
## entry, and is left untouched — it is the pose this race is exited back to.

const FALLBACK_CIRCUIT_SCENE: PackedScene = preload("res://scenes/circuit3.tscn")
const FALLBACK_GHOST_LINE_PATH: String = "res://ghost_lines/circuit3.tres"
const WORLD_SCENE_PATH: String = "res://main.tscn"

@export var kart_path: NodePath = NodePath("Kart")
@export var lap_director_path: NodePath = NodePath("LapDirector")

var _kart: Kart
var _exiting: bool = false


func _enter_tree() -> void:
	# Falls back to circuit3 as one atomic unit, geometry and ghost line together: a Circuit with
	# geometry but no matching line, or vice versa, is exactly the "circuit4's geometry running
	# circuit3's recorded line" bug issue 08 found in the code this replaced, and treating the two
	# fallback fields independently below would have been able to reintroduce it.
	var pending: Circuit = CircuitSession.pending_circuit
	var have_pending: bool = pending != null and pending.circuit_scene != null
	var circuit_scene: PackedScene = pending.circuit_scene if have_pending else FALLBACK_CIRCUIT_SCENE
	var ghost_line_path: String = pending.ghost_line_path if have_pending else FALLBACK_GHOST_LINE_PATH

	var circuit: Node3D = circuit_scene.instantiate() as Node3D
	circuit.name = "Circuit"
	add_child(circuit)

	var lap_director: LapDirector = get_node_or_null(lap_director_path) as LapDirector
	if lap_director != null:
		lap_director.ghost_line_path = ghost_line_path


func _ready() -> void:
	_kart = get_node_or_null(kart_path) as Kart


func _physics_process(_delta: float) -> void:
	if _exiting or not Input.is_action_just_pressed("exit_circuit"):
		return

	_exiting = true
	if _kart != null:
		_kart.frozen = true

	# A failed swap fades back into this same race, still running: undo the one-shot latch so
	# exit_circuit is not left permanently dead and the kart is not left permanently frozen.
	var err: Error = await SceneFade.to_scene(get_tree(), WORLD_SCENE_PATH)
	if err != OK:
		_exiting = false
		if _kart != null:
			_kart.frozen = false
