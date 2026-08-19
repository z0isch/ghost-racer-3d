class_name SceneFade
extends CanvasLayer

## A full-screen fade wrapped around a scene swap: fades to black, swaps the scene, fades back in,
## then frees itself.
##
## Not an autoload. The open-world spec adds exactly two — Purse and CircuitSession — so this lives
## as a node any script spawns for the span of one swap, added under the tree root rather than the
## current scene so [method SceneTree.change_scene_to_file] freeing that scene does not take the
## fade with it.

const FADE_SECONDS: float = 0.3

var _rect: ColorRect


## Fades out, swaps to [param scene_path], then fades back in. Callers do not need to await this —
## it is meant to run as a detached coroutine alongside whatever else the caller does after firing
## the swap (typically nothing, since the calling node is about to be replaced).
static func to_scene(tree: SceneTree, scene_path: String) -> void:
	var fade: SceneFade = SceneFade.new()
	fade.layer = 4096 # above every other CanvasLayer in either scene
	tree.root.add_child(fade)

	await fade._fade(1.0)
	var err: Error = tree.change_scene_to_file(scene_path)
	if err != OK:
		push_warning("SceneFade: change_scene_to_file(%s) failed: %s" % [scene_path, err])
	await tree.process_frame
	await fade._fade(0.0)
	fade.queue_free()


func _init() -> void:
	_rect = ColorRect.new()
	_rect.color = Color(0, 0, 0, 0)
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)


func _fade(target_alpha: float) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(_rect, "color:a", target_alpha, FADE_SECONDS)
	await tween.finished
