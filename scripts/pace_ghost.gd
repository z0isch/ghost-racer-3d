class_name PaceGhost
extends Node3D

## The pace ghost: a translucent replay of the ghost line — the highest earn rate Run driven this
## session — running beside you from the moment the countdown ends.
##
## Pure playback: the director owns the ghost line itself, both the in-progress recording and the
## promoted line. This node only reads it.
##
## There is no frozen flag and no state machine: the ghost has no physics to freeze, and its pose is
## a pure function of the director's Run clock.

@export var kart_path: NodePath
@export var director_path: NodePath

## Settings, not mechanism: nothing below branches on the look.
@export var ghost_color: Color = Color(0.55, 0.85, 1.0, 0.35)
## Under the scene's single key light, a shaded ghost reads as a dark smear across the circuit.
@export var unshaded: bool = true
## Stops the ghost's own faces blending over each other, so it reads as one body.
@export var depth_write: bool = true
## no_depth_test: an always-visible silhouette through barriers and crests.
@export var visible_through_geometry: bool = false

var _director: RunDirector


func _ready() -> void:
	_director = get_node_or_null(director_path) as RunDirector

	_apply_ghost_material(self)
	visible = false # no Run has completed yet, so there is no ghost


# Driven from _process, not _physics_process: the ghost is a pace reference you stare at, so it
# moves at display rate rather than stepping at 60 Hz.
func _process(_delta: float) -> void:
	if _director == null or _director.ghost_line_positions.is_empty():
		visible = false
		return

	match _director.phase:
		RunDirector.RunPhase.COUNTDOWN:
			# Pinned to sample 0: the clock is zero and stays there, so you and the ghost share
			# the start line until either of you moves.
			visible = true
			_apply(0, 0, 0.0)
			return

		RunDirector.RunPhase.RESULTS:
			# Hidden, and this is the uncontended window _on_run_completed's buffer swap lands in.
			visible = false
			return

	# Racing: a pure function of the Run clock. The director accumulates the clock on the same tick
	# the sample is appended, so sample i sits at exactly i x dt — no stored timestamps.
	var t: float = _director.run_clock * Engine.physics_ticks_per_second
	var index: int = int(t)
	if index >= _director.ghost_line_positions.size() - 1:
		# Out of samples: the ghost finished before you did. Hidden rather than parked on the
		# line, where it would be a fake obstacle to flinch at.
		visible = false
		return

	visible = true
	_apply(index, index + 1, t - index)


# Takes indices rather than samples: split across two packed arrays, there is no single value to
# hand over.
func _apply(index: int, next_index: int, weight: float) -> void:
	var positions: PackedVector3Array = _director.ghost_line_positions
	var yaws: PackedFloat32Array = _director.ghost_line_yaws
	global_position = positions[index].lerp(positions[next_index], weight)
	# lerp_angle, not lerp: the yaw wraps, and a plain lerp spins the ghost a full turn at pi.
	rotation = Vector3(0.0, lerp_angle(yaws[index], yaws[next_index], weight), 0.0)


# Built here rather than authored on the mesh: the ghost instances the same imported FBX as the
# kart, whose internal node structure belongs to the importer, so the tree is walked instead.
func _apply_ghost_material(node: Node) -> void:
	var mesh: MeshInstance3D = node as MeshInstance3D
	if mesh != null:
		mesh.material_override = _build_ghost_material()
	for child: Node in node.get_children():
		_apply_ghost_material(child)


func _build_ghost_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = ghost_color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS if depth_write else BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	material.no_depth_test = visible_through_geometry
	return material
