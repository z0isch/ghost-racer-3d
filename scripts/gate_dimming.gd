class_name GateDimming
extends RefCounted

## The duplicate-and-alpha technique shared by every material-dimming path in the game: [class
## LapDirector] dims every gate but the pending one during a race, [class InertCircuit] dims every
## gate in the open world, where there is no pending one at all, and also translucences a circuit's
## bought coins out there. One implementation, so a change to how a material is dimmed — a
## transparency mode fix, a second material surface — reaches all three rather than only whichever
## copy someone remembered to update.


## Duplicates [param mesh]'s active surface-0 material ([method MeshInstance3D.get_active_material]
## — its own override if one is set, otherwise the material authored on the mesh resource itself,
## which is how a gate's material and a coin's are respectively found) and returns a copy at [param
## alpha], or null if the surface has no material to dim. Never mutates the mesh, the mesh
## resource, or the material it reads — callers decide when, or whether, to apply the result via
## [method MeshInstance3D.set_surface_override_material] — so a resource shared across many meshes
## (a gate's own override, or the [CylinderMesh] every coin in a circuit points at) is never
## touched.
static func dim_material(mesh: MeshInstance3D, alpha: float) -> StandardMaterial3D:
	var active_material: StandardMaterial3D = mesh.get_active_material(0) as StandardMaterial3D
	if active_material == null:
		return null

	var dim: StandardMaterial3D = active_material.duplicate() as StandardMaterial3D
	var c: Color = dim.albedo_color
	dim.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dim.albedo_color = Color(c.r, c.g, c.b, alpha)
	return dim
