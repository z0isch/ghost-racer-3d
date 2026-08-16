class_name MoebiusEffect
extends MeshInstance3D

## The Moebius pass: one full-screen quad, parented to the camera, that reads the frame back and
## redraws it as an inked comic panel — outlines off depth and reconstructed normals, posterised
## flats, crosshatched shadow.
##
## Render order is the whole contract, and it is what keeps the pass off the things it must not
## touch. The quad is a transparent surface at RENDER_PRIORITY, so it draws first in the transparent
## pass: the screen and depth textures it samples hold opaque geometry alone, and every transparent
## surface queued behind it — the pace ghost, the boost ghosts, drift smoke, boost flame — lands on
## the finished panel untouched. The HUD is a CanvasLayer and never enters this viewport at all.
##
## Consequently nothing here needs to know what those things are: they are excluded by where they
## sit in the queue, not by a layer mask this node would have to keep in step with the scene.
##
## The look lives in the material's uniforms; nothing in this script reads them.

## Under every other material in the scene. Held here rather than on the material because the
## exclusions above are silently lost if it drifts, and a scene file is an easy place to lose it.
const RENDER_PRIORITY: int = -128

## Vertices land on +/-1, which the vertex stage hands straight to clip space as the viewport
## corners.
const CLIP_QUAD_SIZE: Vector2 = Vector2(2.0, 2.0)


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = CLIP_QUAD_SIZE
	mesh = quad

	# The vertex stage writes POSITION outright, so the node's transform never reaches the geometry
	# and the bounds the renderer culls against describe nothing. A margin this size keeps the pass
	# out of the culler's hands; the transform is left to sorting alone.
	extra_cull_margin = 16384.0
	cast_shadow = SHADOW_CASTING_SETTING_OFF
	gi_mode = GI_MODE_DISABLED

	var shader_material: ShaderMaterial = material_override as ShaderMaterial
	if shader_material == null:
		push_error("MoebiusEffect expects the Moebius ShaderMaterial in material_override.")
		return
	shader_material.render_priority = RENDER_PRIORITY
