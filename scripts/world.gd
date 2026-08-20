extends Node3D

## The open world: drivable ground with every circuit standing on it, each an entrance rather than
## a place you race. Holds nothing lap-shaped — no lap director, no checkpoints, no ghosts.
##
## Circuits are authored directly into main.tscn — a circuit scene instance carrying an
## [InertCircuit] script to dim its gates, plus a sibling [CircuitEntryTrigger] node wired to its
## StartLine and a name [Label3D] — rather than spawned here from data. Adding a circuit is
## "place its nodes in main.tscn", not "add an array entry and trust generated wiring".
##
## `reset` here means "return the kart to a sane world spawn", not abort — there is no lap to abort
## out here (CONTEXT.md, **Abort**, is a lap-scoped concept and does not apply in the world).

@export var kart_path: NodePath

var _kart: Kart
var _spawn_pose: Transform3D = Transform3D.IDENTITY


func _ready() -> void:
	_kart = get_node_or_null(kart_path) as Kart
	if _kart == null:
		return

	_spawn_pose = _kart.global_transform
	if CircuitSession.has_return_pose:
		CircuitSession.has_return_pose = false
		_kart.reset_to(CircuitSession.return_pose)


func _physics_process(_delta: float) -> void:
	if _kart == null or not Input.is_action_just_pressed("reset"):
		return

	_kart.reset_to(_spawn_pose)
	# Every armed trigger is mid-way through its own swept-segment test; left alone, the segment
	# from the kart's pre-teleport position to _spawn_pose could span half the world and spuriously
	# cross a start line it never actually drove through — the same hazard LapDirector and
	# BoostGhostField already guard their own teleports against.
	for trigger: Node in get_tree().get_nodes_in_group(CircuitEntryTrigger.GROUP_NAME):
		(trigger as CircuitEntryTrigger).invalidate()
