class_name PaceGhost
extends Node3D

## The pace ghost: a translucent replay of the line you drove on your highest earn rate lap this
## session, running beside you from the moment the countdown ends.
##
## It owns the two sample buffers; the director has authority over the ghost's lifecycle — when a
## lap starts, completes and aborts — not over where the arrays live.
##
## There is no frozen flag and no state machine: the ghost has no physics to freeze, and its pose is
## a pure function of the director's lap clock.

@export var kart_path: NodePath
@export var director_path: NodePath

## Settings, not mechanism: nothing below branches on the look.
@export var ghost_color: Color = Color(0.55, 0.85, 1.0, 0.35)
## Under the scene's single OmniLight, a shaded ghost reads as a dark smear across the circuit.
@export var unshaded: bool = true
## Stops the ghost's own faces blending over each other, so it reads as one body.
@export var depth_write: bool = true
## no_depth_test: an always-visible silhouette through barriers and crests.
@export var visible_through_geometry: bool = false

var _kart: Kart
var _director: LapDirector

# The kart body's pose is exactly position + Y-yaw (rotate_y is the only write to its basis; bank,
# cant and squash live on the Visual child), so these 16 bytes are exact rather than an
# approximation. Paired packed arrays cost 16 bytes/sample against 48 for typed Arrays and 944 for a
# RefCounted sample class; the price is lockstep, so append, clear and duplicate always come in
# pairs, confined to _append_sample / _on_lap_completed / _on_lap_aborted.
#
# Double-buffered: the lap being driven is written while the record lap is read, and the two are
# usually not adjacent laps. Promotion happens on lap_completed and only there, so no partial
# recording has a path to the playing buffer.
var _recording_positions: PackedVector3Array = PackedVector3Array()
var _recording_yaws: PackedFloat32Array = PackedFloat32Array()
var _playing_positions: PackedVector3Array = PackedVector3Array()
var _playing_yaws: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	_kart = get_node_or_null(kart_path) as Kart
	_director = get_node_or_null(director_path) as LapDirector

	if _director != null:
		_director.lap_completed.connect(_on_lap_completed)
		_director.lap_aborted.connect(_on_lap_aborted)

	_apply_ghost_material(self)
	visible = false # lap 1 has no ghost


# Appended once per physics frame, uncapped: ~1000 samples for a 16 s lap, ~16 KB. Any coarser rate
# visibly cuts corners at the distance per frame the kart covers at top speed.
#
# Queued, not taken here: the sample must be the pose the kart finishes the frame at. The director
# increments the clock at the head of the frame and the kart then moves, so sampling here would pair
# the new clock with the previous frame's pose, laying the ghost a frame behind the line driven.
func _physics_process(_delta: float) -> void:
	if _kart == null or _director == null or _director.phase != LapDirector.LapPhase.RACING:
		return
	_append_sample.call_deferred()


# Driven from _process, not _physics_process: the ghost is a pace reference you stare at, so it
# moves at display rate rather than stepping at 60 Hz.
func _process(_delta: float) -> void:
	if _director == null or _playing_positions.is_empty():
		visible = false
		return

	match _director.phase:
		LapDirector.LapPhase.COUNTDOWN:
			# Pinned to sample 0: the clock is zero and stays there, so you and the ghost share
			# the start line until either of you moves.
			visible = true
			_apply(0, 0, 0.0)
			return

		LapDirector.LapPhase.FINISHED:
			# Hidden, and this is the uncontended window _on_lap_completed's buffer swap lands in.
			visible = false
			return

	# Racing: a pure function of the lap clock. The director accumulates the clock on the same tick
	# the sample is appended, so sample i sits at exactly i x dt — no stored timestamps.
	var t: float = _director.current_lap_time * Engine.physics_ticks_per_second
	var index: int = int(t)
	if index >= _playing_positions.size() - 1:
		# Out of samples: the ghost finished before you did. Hidden rather than parked on the
		# line, where it would be a fake obstacle to flinch at.
		visible = false
		return

	visible = true
	_apply(index, index + 1, t - index)


func _append_sample() -> void:
	# Re-checked: the director's deferred checkpoint sweep runs first and can end the lap, swapping
	# the buffers underneath this call and leaving a stray sample in the next lap's recording.
	if _director.phase != LapDirector.LapPhase.RACING:
		return

	_recording_positions.append(_kart.global_position)
	_recording_yaws.append(_kart.global_rotation.y)


# Takes indices rather than samples: split across two packed arrays, there is no single value to
# hand over.
func _apply(index: int, next_index: int, weight: float) -> void:
	global_position = _playing_positions[index].lerp(_playing_positions[next_index], weight)
	# lerp_angle, not lerp: the yaw wraps, and a plain lerp spins the ghost a full turn at pi.
	rotation = Vector3(0.0, lerp_angle(_playing_yaws[index], _playing_yaws[next_index], weight), 0.0)


# The ghost is told whether the lap set a record rather than deciding: the director owns the record,
# and the same comparison in two places is how the ghost and the number on screen come to disagree.
#
# The clear is unconditional and the swap is not, so a losing lap's samples stay out of the next
# lap's recording and the ghost can stand unchanged for many laps.
func _on_lap_completed(_lap_time: float, is_record: bool) -> void:
	if is_record:
		# Packed arrays are copy-on-write, so duplicate() is ~1 µs and the copy is never
		# materialised: the recording is cleared on the next two lines.
		_playing_positions = _recording_positions.duplicate()
		_playing_yaws = _recording_yaws.duplicate()
	_recording_positions.clear()
	_recording_yaws.clear()


# An abort throws the partial recording away and leaves the playing buffer untouched, so a lap
# abandoned at 90% can never become a ghost.
func _on_lap_aborted() -> void:
	_recording_positions.clear()
	_recording_yaws.clear()


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
