class_name InertCircuit
extends Node

## Dims every gate on a circuit instance standing in the open world.
##
## No lap director runs out here, so nothing would otherwise dim the intermediate gates the way
## [method LapDirector._update_gate_visibility] does inside a race — every gate would render at
## full brightness, reading as "every gate is the pending one", which is a lie with no lap in
## progress. Dimming itself is [class GateDimming], shared with the lap director, so the shared
## resource authored into the circuit scene is never mutated, and a race scene loaded afterwards
## still sees the original, undimmed material.
##
## Dims gates only. Coins are left alone — they stay visible and standing, uncollectible with no
## CoinField present, and that is exactly what advertises a circuit pays (spec: open-world.md).

@export var checkpoints_path: NodePath
@export var inactive_gate_alpha: float = 0.15


func _ready() -> void:
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
