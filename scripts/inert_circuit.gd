class_name InertCircuit
extends Node

## Dims every gate on a circuit instance standing in the open world, and shows its loadout: bought
## clocks translucent, unbought clocks hidden entirely.
##
## No run director runs out here, so nothing would otherwise dim the intermediate gates the way
## [method RunDirector._update_gate_visibility] does inside a race — every gate would render at
## full brightness, reading as "every gate is the pending one", which is a lie with no Run in
## progress. Dimming itself is [class GateDimming], shared with the run director, so the shared
## resource authored into the circuit scene is never mutated, and a race scene loaded afterwards
## still sees the original, undimmed material.
##
## Clocks are shown the same way: [autoload LoadoutHolder]'s count for [member circuit] says how
## many are bought, the first that many (in authored node order, the purchase order) are shown
## translucent and uncollectible, and the rest are hidden entirely — a circuit with a bare loadout
## therefore stands with no clocks at all (CONTEXT.md's **Open world**).

@export var checkpoints_path: NodePath
## The circuit's Clocks node, whose first [member CircuitLoadout.clock_count] children (in authored
## order) are shown translucent.
@export var clocks_path: NodePath
## Which circuit this instance stands for — not otherwise knowable from here, exactly as
## [member CircuitEntryTrigger.circuit] is authored for the same reason. Set on both the circuit3
## and circuit4 instances in main.tscn.
@export var circuit: Circuit
@export var inactive_gate_alpha: float = 0.15
## Alpha a bought clock is shown at: visible enough to read as "advertised", low enough to still
## read as "not really here" the way an inactive gate does.
@export var bought_clock_alpha: float = 0.35


func _ready() -> void:
	_dim_gates()
	_apply_loadout()


func _dim_gates() -> void:
	var checkpoints: Node = get_node_or_null(checkpoints_path)
	if checkpoints == null:
		push_warning("InertCircuit: no Checkpoints node — nothing to dim.")
		return

	for checkpoint: Node in checkpoints.get_children():
		for gate_child: Node in checkpoint.get_children():
			var gate_mesh: MeshInstance3D = gate_child as MeshInstance3D
			if gate_mesh == null:
				continue
			var dim: StandardMaterial3D = GateDimming.dim_material(gate_mesh, inactive_gate_alpha)
			if dim != null:
				gate_mesh.set_surface_override_material(0, dim)


## Hides every clock marker past [member CircuitLoadout.clock_count] and makes the rest translucent,
## in authored node order — the same order [method ClockField._resolve_clocks] takes its live
## clocks in, so this always agrees with what a race on this circuit would actually offer.
func _apply_loadout() -> void:
	var clocks: Node = get_node_or_null(clocks_path)
	if clocks == null:
		push_warning("InertCircuit: no Clocks node — nothing to show a loadout with.")
		return

	var loadout: CircuitLoadout = LoadoutHolder.for_circuit(circuit)
	# Filtered before indexing, matching ClockField._resolve_clocks: indexing raw get_children()
	# directly would disagree with the race scene's own count the moment a Clocks node ever gained
	# a non-Node3D child, since that child would shift every index after it in one array but not
	# the other.
	var markers: Array[Node3D] = []
	for child: Node in clocks.get_children():
		var marker: Node3D = child as Node3D
		if marker != null:
			markers.append(marker)

	for i in markers.size():
		if i >= loadout.clock_count:
			markers[i].visible = false
			continue
		_make_translucent(markers[i])


func _make_translucent(marker: Node3D) -> void:
	for child: Node in marker.get_children():
		var mesh: MeshInstance3D = child as MeshInstance3D
		if mesh == null:
			continue
		var dim: StandardMaterial3D = GateDimming.dim_material(mesh, bought_clock_alpha)
		if dim != null:
			mesh.set_surface_override_material(0, dim)
