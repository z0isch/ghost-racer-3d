class_name GateDimming
extends RefCounted

## The duplicate-and-alpha technique shared by every gate-dimming path in the game: [class
## LapDirector] dims every gate but the pending one during a race, and [class InertCircuit] dims
## every gate in the open world, where there is no pending one at all. One implementation, so a
## change to how a gate's material is dimmed — a transparency mode fix, a second material surface
## — reaches both rather than only whichever copy someone remembered to update.


## Duplicates [param gate_mesh]'s surface-0 override material and returns a copy at [param alpha],
## or null if the mesh has no override to dim. Never mutates the mesh or the material it reads —
## callers decide when, or whether, to apply the result — so the shared resource multiple gates
## point at is never touched.
static func dim_material(gate_mesh: MeshInstance3D, alpha: float) -> StandardMaterial3D:
	var active_material: StandardMaterial3D = gate_mesh.get_surface_override_material(0) as StandardMaterial3D
	if active_material == null:
		return null

	var dim: StandardMaterial3D = active_material.duplicate() as StandardMaterial3D
	var c: Color = dim.albedo_color
	dim.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dim.albedo_color = Color(c.r, c.g, c.b, alpha)
	return dim
