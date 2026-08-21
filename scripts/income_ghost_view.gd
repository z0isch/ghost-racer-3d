class_name IncomeGhostView
extends Node3D

## Draws one circuit's income ghosts: what [autoload IncomeRunner] is already simulating, standing
## inside that circuit's own instance in the open world so a line recorded in the circuit's
## coordinates applies directly with no arithmetic — this node is authored at identity under the
## circuit root.
##
## A pure view: it owns no money and no progress — not where a ghost has got to, not which rung of
## the ladder it is on. Each frame it asks the runner where this circuit's ghosts are and moves cars
## there; the runner is never told whether anything is drawing it, so a hidden ghost still earns
## (CONTEXT.md's **Income ghost view**).
##
## Not a job for InertCircuit — that node renders things authored into the circuit that stand still.
## Income ghosts are spawned cars driven by an autoload on a per-frame update, which is a different
## shape of problem entirely.

## Same imported model every ghost in this game uses.
const GHOST_MODEL: PackedScene = preload("res://cars/FBX/SportsCar.fbx")

## The FBX's own axis/scale correction, authored on [PaceGhost]'s SportsCar child in race.tscn and
## reproduced here in code since this view spawns its models at runtime rather than having them
## authored into a scene.
const MODEL_TRANSFORM: Transform3D = Transform3D(
	Vector3(-0.55, 0.0, 3.4969112e-08),
	Vector3(0.0, 0.6, 0.0),
	Vector3(-4.8082526e-08, 0.0, -0.4),
	Vector3(0.0, -0.4, 0.0),
)

## Which circuit this instance draws — not otherwise knowable from here, exactly as [member
## InertCircuit.circuit] and [member CircuitEntryTrigger.circuit] are authored for the same reason.
@export var circuit: Circuit

## Money green — the one car in the game that *is* the money (CONTEXT.md's **Income ghost**), shared
## with the purse readout and the pickup popups.
@export var ghost_color: Color = Color(0.29, 0.93, 0.42, 0.4)
@export var unshaded: bool = true
@export var depth_write: bool = true

## Declarative, engine-handled culling — no per-frame distance code, and it has a fade mode so
## ghosts do not blink in. A car silhouette reads much further out than a popup's billboarded text,
## so the two get separate ranges.
@export var car_visibility_range_end: float = 150.0
@export var popup_visibility_range_end: float = 60.0

## How far in front of a paid checkpoint the popup appears, along the pickup's own travel direction —
## matching [member PickupPopups.lead_distance].
@export var popup_lead_distance: float = 1.0
@export var popup_rise: float = 1.5
@export var popup_lifetime: float = 0.8
@export var popup_money_color: Color = Color(0.29, 0.93, 0.42)
@export var popup_font_size: int = 64
@export var popup_pixel_size: float = 0.005

var _wrappers: Array[Node3D] = []
var _material: StandardMaterial3D


func _ready() -> void:
	_material = _build_ghost_material()
	IncomeRunner.register_circuit(circuit)
	IncomeRunner.pickup.connect(_on_pickup)


func _process(_delta: float) -> void:
	var transforms: Array[Transform3D] = IncomeRunner.ghost_transforms(circuit)
	_sync_wrapper_count(transforms.size())
	for i in transforms.size():
		_wrappers[i].transform = transforms[i]


func _sync_wrapper_count(count: int) -> void:
	while _wrappers.size() > count:
		var wrapper: Node3D = _wrappers.pop_back()
		wrapper.queue_free()
	while _wrappers.size() < count:
		_wrappers.append(_spawn_ghost())


func _spawn_ghost() -> Node3D:
	var wrapper := Node3D.new()
	add_child(wrapper)

	var model: Node3D = GHOST_MODEL.instantiate() as Node3D
	wrapper.add_child(model)
	model.transform = MODEL_TRANSFORM
	_apply_material(model, _material)
	_apply_visibility_range(model, car_visibility_range_end)

	return wrapper


## Circuit-local, exactly as [signal IncomeRunner.pickup] reports it: converted to world space by
## the fact of standing in this circuit's own coordinate frame ([method Node3D.to_global]), the same
## turn CONTEXT.md's **Income ghost view** entry describes.
func _on_pickup(pickup_circuit: Circuit, checkpoint_position: Vector3, direction: Vector3, value: int) -> void:
	if pickup_circuit != circuit:
		return

	var local_spawn: Vector3 = checkpoint_position + direction * popup_lead_distance
	_spawn_popup(value, to_global(local_spawn))


func _spawn_popup(value: int, world_position: Vector3) -> void:
	var label := Label3D.new()
	label.text = "$%d" % value
	label.modulate = popup_money_color
	label.font_size = popup_font_size
	label.pixel_size = popup_pixel_size
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.visibility_range_end = popup_visibility_range_end
	label.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(label)
	label.global_position = world_position

	var tween: Tween = label.create_tween()
	tween.set_parallel(true)
	@warning_ignore_start("return_value_discarded")
	tween.tween_property(label, "global_position:y", world_position.y + popup_rise, popup_lifetime)
	tween.tween_property(label, "modulate:a", 0.0, popup_lifetime)
	tween.tween_property(label, "outline_modulate:a", 0.0, popup_lifetime)
	tween.chain().tween_callback(label.queue_free)
	@warning_ignore_restore("return_value_discarded")


# Built here rather than authored on the mesh, for PaceGhost's identical reason: the ghost instances
# the same imported FBX as the kart, whose internal node structure belongs to the importer.
func _apply_material(node: Node, material: StandardMaterial3D) -> void:
	var mesh: MeshInstance3D = node as MeshInstance3D
	if mesh != null:
		mesh.material_override = material
	for child: Node in node.get_children():
		_apply_material(child, material)


func _apply_visibility_range(node: Node, range_end: float) -> void:
	var mesh: MeshInstance3D = node as MeshInstance3D
	if mesh != null:
		mesh.visibility_range_end = range_end
		mesh.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	for child: Node in node.get_children():
		_apply_visibility_range(child, range_end)


func _build_ghost_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = ghost_color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS if depth_write else BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	return material
