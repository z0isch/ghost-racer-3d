extends Node3D

## The open world: drivable ground with every circuit standing on it, each an entrance rather than
## a place you race. Holds nothing lap-shaped — no lap director, no checkpoints, no ghosts.
##
## Each circuit in [member circuits] is instanced at its own [member Circuit.world_transform],
## dimmed by a spawned [InertCircuit] and watched by a spawned [CircuitEntryTrigger] — nothing
## about a circuit's presence in the world is authored into main.tscn directly, so adding a
## circuit is "add a Circuit resource to the array", not "hand-wire three more nodes".
##
## `reset` here means "return the kart to a sane world spawn", not abort — there is no lap to abort
## out here (CONTEXT.md, **Abort**, is a lap-scoped concept and does not apply in the world).

@export var kart_path: NodePath
@export var circuits: Array[Circuit] = []

## How long the kart must stand clear of an entry prism before that circuit's trigger arms.
## Forwarded to every spawned CircuitEntryTrigger.
@export var entry_rearm_seconds: float = 0.5

## How high above the entry line a circuit's name label stands.
@export var name_label_height: float = 4.0

var _kart: Kart
var _spawn_pose: Transform3D = Transform3D.IDENTITY
var _entry_triggers: Array[Node] = []


func _ready() -> void:
	_kart = get_node_or_null(kart_path) as Kart
	if _kart == null:
		return

	_spawn_pose = _kart.global_transform
	if CircuitSession.has_return_pose:
		CircuitSession.has_return_pose = false
		_kart.reset_to(CircuitSession.return_pose)

	for circuit_resource: Circuit in circuits:
		_spawn_circuit(circuit_resource)


func _physics_process(_delta: float) -> void:
	if _kart == null or not Input.is_action_just_pressed("reset"):
		return

	_kart.reset_to(_spawn_pose)
	# Every armed trigger is mid-way through its own swept-segment test; left alone, the segment
	# from the kart's pre-teleport position to _spawn_pose could span half the world and spuriously
	# cross a start line it never actually drove through — the same hazard LapDirector and
	# BoostGhostField already guard their own teleports against.
	for trigger: Node in _entry_triggers:
		(trigger as CircuitEntryTrigger).invalidate()


## Scripts and exported properties must be set before a node enters the tree: [method Node._ready]
## fires exactly once, when a node's current script first sees NOTIFICATION_READY, and neither a
## later set_script nor a later property write reruns it. So every dynamically spawned node here is
## fully configured — script attached, NodePaths and Circuit assigned — before its one add_child.
func _spawn_circuit(circuit_resource: Circuit) -> void:
	if circuit_resource == null or circuit_resource.circuit_scene == null:
		push_warning("World: a Circuit entry has no circuit_scene — skipped.")
		return

	var circuit: Node3D = circuit_resource.circuit_scene.instantiate() as Node3D
	var checkpoints: Node = circuit.get_node_or_null("Checkpoints")
	var start_line: Node = circuit.get_node_or_null("StartLine")

	# get_path_to across circuit's own freshly instantiated subtree needs no tree membership: both
	# nodes already share the parent chain instantiate() built, whether or not that subtree has
	# been added anywhere yet.
	if checkpoints != null:
		circuit.set_script(preload("res://scripts/inert_circuit.gd"))
		circuit.set("checkpoints_path", circuit.get_path_to(checkpoints))
	else:
		push_warning("World: a circuit has no Checkpoints — its gates will not dim.")

	circuit.transform = circuit_resource.world_transform
	add_child(circuit)

	if _kart == null or start_line == null:
		push_warning("World: a circuit has no StartLine, or there is no Kart — left un-enterable.")
		return

	# Computed now, with circuit already added and self (World) already in the tree, then
	# re-rooted one level deeper with "../" — trigger's parent will be self too, once it is added
	# below, so a path valid from World is valid from trigger with exactly that one prefix.
	var kart_from_world: NodePath = get_path_to(_kart)
	var start_line_from_world: NodePath = get_path_to(start_line)

	var trigger: Node = Node.new()
	trigger.set_script(preload("res://scripts/circuit_entry_trigger.gd"))
	trigger.set("kart_path", NodePath("../%s" % kart_from_world))
	trigger.set("start_line_path", NodePath("../%s" % start_line_from_world))
	trigger.set("circuit", circuit_resource)
	trigger.set("rearm_seconds", entry_rearm_seconds)
	add_child(trigger)
	_entry_triggers.append(trigger)

	_spawn_name_label(circuit_resource, start_line as Node3D)


## A world-space name over the entry line: useful while deciding where to drive, which is well
## before a proximity-gated HUD prompt would have fired (spec: open-world.md, issue 09).
func _spawn_name_label(circuit_resource: Circuit, start_line: Node3D) -> void:
	if circuit_resource.display_name.is_empty() or start_line == null:
		return

	var label := Label3D.new()
	label.text = circuit_resource.display_name
	label.font_size = 96
	label.pixel_size = 0.02
	# Required, not decoration, exactly as PickupPopups notes: read edge-on, text is invisible.
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
	label.global_position = start_line.global_position + Vector3.UP * name_label_height
