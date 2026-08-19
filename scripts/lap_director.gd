class_name LapDirector
extends Node

## The single owner of all mutable lap state: the lap phase, the lap clock, checkpoint progress, the
## lap's earnings and the record earn rate, and the ghost line — both the in-progress recording and
## the promoted line the pace ghost and the boost ghosts stand on.
##
## Lap earnings live here rather than on CoinField because they are the numerator of the earn rate
## and the lap clock is the denominator; splitting a fraction across two owners is how the two come
## to disagree. The purse is the mirror-image call and sits in scripts/purse.gd: a session total is
## not lap state, and housing it behind _begin_countdown's per-lap reset would eventually clear it.
##
## Kart knows nothing about laps — the director drives it through Kart.frozen and Kart.reset_to().

signal lap_started()
## [param is_record] means this lap set a new record earn rate. Carried on the signal rather than
## left for listeners to derive, since deriving it means comparing against a value the director has
## just overwritten.
signal lap_completed(lap_time: float, is_record: bool)
signal lap_aborted()
## Fired as the kart is teleported to the start line, so anything holding a swept previous-position
## sample or per-lap state can invalidate it. [signal lap_started] is a frame too late — the coin
## field must already be whole while the driver looks at it during the countdown — and
## lap_completed/lap_aborted miss the scene load between them.
signal countdown_started()

enum LapPhase {
	COUNTDOWN,
	RACING,
	FINISHED,
}

@export var kart_path: NodePath
@export var chase_camera_path: NodePath
## A Marker3D on the circuit: the track owns the start line.
@export var start_line_path: NodePath
## The Checkpoints node: one inert Marker3D each, node order = lap order.
@export var checkpoints_path: NodePath
## The CoinField whose pickups feed [member lap_earnings].
@export var coin_field_path: NodePath

## Where the ghost line is persisted. Loaded on [method _ready] if the file exists, and overwritten
## every time a lap promotes a new record — so the "drive one lap to get ghosts" tax is paid once,
## by whoever commits the file, not every session. Empty disables persistence entirely: the line
## behaves exactly as before, session-scoped and lost on exit.
@export_file("*.tres") var ghost_line_path: String = ""

## The checkpoint prism, in each marker's own frame: the road and nothing but the road, from 1 m
## below the surface to 5 m above, which is where the gate's posts and crossbar are. Exported so the
## pair can be pushed apart in a playtest, but meant to match the gate geometry.
@export var checkpoint_half_width: float = 4.0
@export var checkpoint_floor: float = -1.0
@export var checkpoint_ceiling: float = 5.0

## Non-pending gates dim to this alpha rather than vanish, so the field stays visible as a preview
## of the lap ahead.
@export var inactive_gate_alpha: float = 0.15

## The first countdown is the conventional 3-2-1-GO; the lap is short and restarts forever, so
## restarts get a shorter beat.
@export var first_countdown_seconds: float = 3.0
@export var restart_countdown_seconds: float = 2.0

## Finished is a phase with duration: the completed time hangs on screen before the teleport, rather
## than the lap ending and restarting on the same frame.
@export var finished_hold_seconds: float = 1.5

## How many times the start/finish gate must be taken before it actually ends the lap. Below this
## count, taking it advances the kart back onto checkpoint 1 instead — same clock, same earnings,
## same recording — so a multi-circuit lap is scored and ghosted as one continuous line rather than
## as several short ones. Adjustable live, via dev_laps_more/dev_laps_fewer, exactly as the boost
## and hazard ghost counts are; clamped to at least 1 so the gate always ends something.
@export var laps_required: int = 1:
	set(value):
		laps_required = maxi(value, 1)

var _kart: Kart
var _camera: ChaseCamera
var _start_line: Node3D
var _fallback_start_pose: Transform3D = Transform3D.IDENTITY
var _phase: LapPhase = LapPhase.COUNTDOWN
var _current_lap_time: float = 0.0
var _lap_earnings: int = 0
var _record_earn_rate: float = -1.0 # <0 until a lap has actually been completed
var _phase_remaining: float = 0.0
var _checkpoint_index: int = 0
var _checkpoint_count: int = 0
## Which trip around the circuit this is, within the current lap; resets to 1 at every countdown.
## Only ever meaningful against [member laps_required]: at the default 1 it never leaves 1.
var _lap_count: int = 1
var _checkpoints: Array[Checkpoint] = []
var _last_kart_position: Vector3 = Vector3.ZERO
var _has_last_kart_position: bool = false

# The kart body's pose is exactly position + Y-yaw (rotate_y is the only write to its basis; bank,
# cant and squash live on the Visual child), so these 16 bytes are exact rather than an
# approximation. Paired packed arrays cost 16 bytes/sample against 48 for typed Arrays and 944 for a
# RefCounted sample class; the price is lockstep, so append, clear and duplicate always come in
# pairs, confined to _append_sample / complete_lap / lap abort.
#
# Double-buffered: the lap being driven is written while the record lap is read, and the two are
# usually not adjacent laps. Promotion happens in complete_lap and only there, so no partial
# recording has a path to the ghost line.
var _recording_positions: PackedVector3Array = PackedVector3Array()
var _recording_yaws: PackedFloat32Array = PackedFloat32Array()
var _ghost_line_positions: PackedVector3Array = PackedVector3Array()
var _ghost_line_yaws: PackedFloat32Array = PackedFloat32Array()

## Polled by the HUD each _process; a per-frame clock pushed through a signal would be a signal in
## name only. Discrete lap edges use the signals above.
var phase: LapPhase:
	get: return _phase

var current_lap_time: float:
	get: return _current_lap_time

## Money taken during this lap only, cleared with the lap clock in _begin_countdown. Distinct from
## the purse in every way except its unit (CONTEXT.md, **Lap earnings**).
var lap_earnings: int:
	get: return _lap_earnings

## The live figure, and the identical expression complete_lap judges the lap on, so the number you
## watched climb is the number you are scored on. A cumulative average over the whole lap, never
## windowed and never smoothed.
##
## Zero, not a divide-by-zero, at countdown-zero: LapHud shows "--.--" for the first second and
## gates on the clock rather than on this value.
var earn_rate: float:
	get: return 0.0 if _current_lap_time <= 0.0 else _lap_earnings / _current_lap_time

## The session's highest completed-lap earn rate, and the bar a lap must strictly beat to promote
## its recording to the pace ghost. Stored nowhere else: promotion is exactly "strictly higher rate"
## with no side conditions, so the ghost is the record-holding lap by construction.
var record_earn_rate: float:
	get: return _record_earn_rate

## Seconds left of Countdown / Finished; 0 while Racing.
var phase_remaining: float:
	get: return _phase_remaining

## The pending checkpoint: the single live one, and equally the count already taken this lap. Polled
## by LapHud for its "CP 3/5" readout, the only way the player can tell why a lap didn't complete.
var checkpoint_index: int:
	get: return _checkpoint_index

var checkpoint_count: int:
	get: return _checkpoint_count

## Which trip around the circuit is live, 1-indexed against [member laps_required]. Polled by
## LapHud alongside checkpoint_index/checkpoint_count for the same reason: it is the only way the
## player can tell how much of the lap is left.
var lap_count: int:
	get: return _lap_count

## The record lap's line. Copy-on-write, so reading is ~free and callers must not mutate. Two
## read-only getters rather than a sample_at(t) accessor: the boost ghost field walks the whole
## polyline summing segment lengths, which a per-sample accessor cannot serve without a second
## method — an interface that "hides" the arrays while exposing a raw-array escape hatch hides
## nothing.
var ghost_line_positions: PackedVector3Array:
	get: return _ghost_line_positions

var ghost_line_yaws: PackedFloat32Array:
	get: return _ghost_line_yaws


func _ready() -> void:
	_kart = get_node_or_null(kart_path) as Kart
	_camera = get_node_or_null(chase_camera_path) as ChaseCamera
	_start_line = get_node_or_null(start_line_path) as Node3D

	# The authored kart transform is editor convenience; the first countdown overwrites it. Kept so a
	# scene without a StartLine teleports somewhere sane rather than to the origin.
	_fallback_start_pose = _kart.global_transform if _kart != null else Transform3D.IDENTITY
	if _start_line == null:
		push_warning("LapDirector: no StartLine node — falling back to the kart's authored transform.")

	_resolve_checkpoints()

	# CoinField totals nothing, so the tally is made here, on the side that owns the clock it will be
	# divided by. A scene without a coin field earns nothing, as one without checkpoints completes no
	# lap; both keep this script runnable outside main.tscn.
	var coin_field: CoinField = get_node_or_null(coin_field_path) as CoinField
	if coin_field != null:
		# unbind(1) drops coin_taken's position argument. Godot does not drop surplus arguments by
		# itself: connected bare, every pickup would fail at emit time and no lap would earn.
		coin_field.coin_taken.connect(_on_coin_taken.unbind(1))
	else:
		push_warning("LapDirector: no CoinField — every lap earns nothing.")

	# The phase must resolve before Kart's physics step reads frozen, or the GO frame is spent still
	# frozen — a dead frame the driver feels as a hitch off the line. Checkpoint detection needs the
	# opposite, the kart's position after move_and_slide, hence the deferred swept test.
	process_physics_priority = -100

	_load_ghost_line()
	_begin_countdown(first_countdown_seconds)


func _physics_process(delta: float) -> void:
	# The director owns "reset", and it means abort: discard the lap and re-run the countdown from
	# any phase, skipping Finished since there is no time to show.
	if Input.is_action_just_pressed("reset"):
		# The partial recording is thrown away here rather than left standing: a lap abandoned at
		# 90% can never become a ghost line, and the previous line is left untouched.
		_recording_positions.clear()
		_recording_yaws.clear()
		lap_aborted.emit()
		_begin_countdown(restart_countdown_seconds)
		return

	# Not gated on phase, for the dev inputs' own reason on the boost and hazard fields: the count
	# is director state regardless of what's currently live, and raising it mid-lap must still be in
	# effect when the gate that checks it is next reached.
	if Input.is_action_just_pressed("dev_laps_more"):
		laps_required += 1
	if Input.is_action_just_pressed("dev_laps_fewer"):
		laps_required -= 1

	match _phase:
		LapPhase.COUNTDOWN:
			_phase_remaining -= delta
			if _phase_remaining <= 0.0:
				_start_lap()

		LapPhase.RACING:
			_current_lap_time += delta
			# Queued, not called: this runs at the head of the physics frame, and the swept test
			# needs the position the kart ends the frame at. Sampling is queued after the sweep so a
			# lap-ending crossing in this same flush swaps the buffers before the sample is appended.
			_sweep_pending_checkpoint.call_deferred()
			_append_sample.call_deferred()

		LapPhase.FINISHED:
			_phase_remaining -= delta
			if _phase_remaining <= 0.0:
				_begin_countdown(restart_countdown_seconds)


## Called when the last checkpoint in the sequence — the start/finish — is taken. Holds the
## promotion rule, and the only copy of it.
##
## Called from the deferred checkpoint sweep, which is queued before CoinField's deferred sweep in
## the same flush; the field re-checks the phase and bails once the lap is over. That ordering is
## what makes _lap_earnings final by the time it is read here.
func complete_lap() -> void:
	var lap_time: float = _current_lap_time
	var rate: float = earn_rate

	# The negative sentinel is the "first completed lap promotes unconditionally" rule: an earn rate
	# is never negative, so a real lap can never sit at or below it, and a zero-coin opening lap
	# still promotes. The strict > is the rest: a tie does not displace the incumbent.
	var is_record: bool = _record_earn_rate < 0.0 or rate > _record_earn_rate
	if is_record:
		_record_earn_rate = rate
		# Packed arrays are copy-on-write, so duplicate() is ~1 µs and the copy is never
		# materialised: the recording is cleared on the next two lines regardless.
		_ghost_line_positions = _recording_positions.duplicate()
		_ghost_line_yaws = _recording_yaws.duplicate()
		_save_ghost_line()
	# Unconditional, so a losing lap's samples cannot leak into the next recording and the ghost
	# line can stand unchanged for many laps.
	_recording_positions.clear()
	_recording_yaws.clear()

	_phase = LapPhase.FINISHED
	_phase_remaining = finished_hold_seconds
	if _kart != null:
		_kart.frozen = true # held where it finished; the teleport is the next countdown's job
	lap_completed.emit(lap_time, is_record)


# No phase guard: CoinField sweeps only while Racing and re-checks the phase inside its own deferred
# callback, so a pickup cannot reach here outside a live lap.
func _on_coin_taken(value: int) -> void:
	_lap_earnings += value


# Resolved once. The markers are inert Marker3Ds in lap order under a Checkpoints node; everything
# mutable about them lives here.
func _resolve_checkpoints() -> void:
	var root: Node3D = get_node_or_null(checkpoints_path) as Node3D
	if root == null:
		push_warning("LapDirector: no Checkpoints node — no lap can complete.")
		return

	var found: Array[Checkpoint] = []
	for child: Node in root.get_children():
		var marker: Node3D = child as Node3D
		if marker == null:
			continue
		var frame: Transform3D = marker.global_transform
		var checkpoint := Checkpoint.new()
		checkpoint.node = marker
		# The gate meshes' surface overrides point at materials shared across every checkpoint, so
		# each is duplicated into a dimmed instance here and swapped per-mesh at runtime; mutating
		# the shared resource would dim the whole field at once.
		for gate_child: Node in marker.get_children():
			var gate_mesh: MeshInstance3D = gate_child as MeshInstance3D
			if gate_mesh == null:
				continue
			var active_material: StandardMaterial3D = gate_mesh.get_surface_override_material(0) as StandardMaterial3D
			if active_material == null:
				continue
			var dim_material: StandardMaterial3D = active_material.duplicate() as StandardMaterial3D
			dim_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			var c: Color = dim_material.albedo_color
			dim_material.albedo_color = Color(c.r, c.g, c.b, inactive_gate_alpha)
			checkpoint.gate_meshes.append(gate_mesh)
			checkpoint.active_materials.append(active_material)
			checkpoint.dim_materials.append(dim_material)
		checkpoint.origin = frame.origin
		# Basis Z points backwards, so the road's forward is -Z. The crossing test is
		# direction-agnostic, so only the sign convention matters.
		checkpoint.forward = -frame.basis.z.normalized()
		checkpoint.right = frame.basis.x.normalized()
		checkpoint.up = frame.basis.y.normalized()
		found.append(checkpoint)

	_checkpoints = found
	_checkpoint_count = _checkpoints.size()
	_update_gate_visibility()


func _update_gate_visibility() -> void:
	for i in _checkpoints.size():
		var checkpoint: Checkpoint = _checkpoints[i]
		var materials: Array[StandardMaterial3D] = checkpoint.active_materials if i == _checkpoint_index else checkpoint.dim_materials
		for j in checkpoint.gate_meshes.size():
			checkpoint.gate_meshes[j].set_surface_override_material(0, materials[j])


# Tests the segment the kart travelled this frame against the pending checkpoint's plane; a crossing
# inside the prism takes the checkpoint. A swept segment rather than a sampled position, so
# tunnelling is impossible at any speed.
#
# Only _checkpoints[_checkpoint_index] is ever tested, which is strict-next-only ordering, monotonic
# progress and "missing one changes nothing", all at once.
func _sweep_pending_checkpoint() -> void:
	if _phase != LapPhase.RACING or _kart == null or _checkpoint_index >= _checkpoints.size():
		return

	var position: Vector3 = _kart.global_position
	# The first Racing frame after a teleport records a position and tests nothing: a segment
	# spanning the teleport would sweep half the circuit and take every plane it crossed.
	if not _has_last_kart_position:
		_last_kart_position = position
		_has_last_kart_position = true
		return

	var previous: Vector3 = _last_kart_position
	_last_kart_position = position

	var checkpoint: Checkpoint = _checkpoints[_checkpoint_index]
	var before: float = (previous - checkpoint.origin).dot(checkpoint.forward)
	var after: float = (position - checkpoint.origin).dot(checkpoint.forward)

	# Either sign counts: monotonic progress already means a backwards crossing gains nothing.
	var crossed: bool = (before <= 0.0 and after > 0.0) or (before >= 0.0 and after < 0.0)
	if not crossed:
		return

	# Where on the plane the segment crossed, in the checkpoint's own camber-tilted frame.
	var local: Vector3 = previous.lerp(position, before / (before - after)) - checkpoint.origin
	var lateral: float = local.dot(checkpoint.right)
	var height: float = local.dot(checkpoint.up)
	if absf(lateral) > checkpoint_half_width:
		return
	if height < checkpoint_floor or height > checkpoint_ceiling:
		return

	_checkpoint_index += 1
	if _checkpoint_index >= _checkpoints.size():
		if _lap_count >= laps_required:
			complete_lap()
		else:
			# One circuit down, more to go: back to checkpoint 1 with the clock, the earnings and
			# the recording all left running, so the multiple circuits score and ghost as the one
			# continuous lap they are, not as several short laps back to back.
			_lap_count += 1
			_checkpoint_index = 0
	_update_gate_visibility()


# Appended once per physics frame, uncapped: ~1000 samples for a 16 s lap, ~16 KB. Any coarser rate
# visibly cuts corners at the distance per frame the kart covers at top speed.
#
# Queued, not taken inline: the sample must be the pose the kart finishes the frame at, and the
# kart moves after the director in the same frame, so sampling inline would pair the new clock with
# the previous frame's pose and lay the whole line one frame behind what was driven.
func _append_sample() -> void:
	# Re-checked: the checkpoint sweep is queued first in the same flush and can complete the lap,
	# swapping the buffers underneath this call and leaving a stray sample at the head of the next
	# lap's recording.
	if _phase != LapPhase.RACING or _kart == null:
		return

	_recording_positions.append(_kart.global_position)
	_recording_yaws.append(_kart.global_rotation.y)


# Populates the ghost line from disk before the first countdown, so ghosts stand on the circuit
# from the session's first lap rather than only after one is driven and promoted. Silent on a
# missing or unreadable file: an unset path or a track that has never been recorded is not an
# error, just an empty ghost line, exactly as before this existed.
func _load_ghost_line() -> void:
	if ghost_line_path.is_empty() or not ResourceLoader.exists(ghost_line_path):
		return
	var ghost_line: GhostLine = load(ghost_line_path) as GhostLine
	if ghost_line == null:
		push_warning("LapDirector: %s did not load as a GhostLine." % ghost_line_path)
		return
	_ghost_line_positions = ghost_line.positions
	_ghost_line_yaws = ghost_line.yaws
	_record_earn_rate = ghost_line.earn_rate


# Mirrors the promotion in complete_lap to disk, so the next session's _load_ghost_line picks up
# today's record without a driver having to export or commit anything by hand.
func _save_ghost_line() -> void:
	if ghost_line_path.is_empty():
		return
	var ghost_line := GhostLine.new()
	ghost_line.positions = _ghost_line_positions
	ghost_line.yaws = _ghost_line_yaws
	ghost_line.earn_rate = _record_earn_rate
	var error: Error = ResourceSaver.save(ghost_line, ghost_line_path)
	if error != OK:
		push_warning("LapDirector: failed to save ghost line to %s (%s)." % [ghost_line_path, error])


# The one entry point into Countdown: scene load, lap completion and abort all come through here,
# so the three read identically to the driver.
func _begin_countdown(seconds: float) -> void:
	_phase = LapPhase.COUNTDOWN
	_phase_remaining = seconds
	_current_lap_time = 0.0
	_lap_earnings = 0
	_checkpoint_index = 0
	_lap_count = 1
	_update_gate_visibility()
	_has_last_kart_position = false # the teleport below invalidates the swept segment

	if _kart != null:
		# Frozen before the teleport, so no physics step can run between the two and re-accelerate
		# from the new pose.
		_kart.frozen = true
		_kart.reset_to(_start_pose())

	# Without this the camera flies the length of the circuit to catch up, every lap.
	if _camera != null:
		_camera.snap_to_target()

	# Emitted last, after the teleport: a listener invalidating a swept sample wants the kart
	# already standing on the start line.
	countdown_started.emit()


func _start_lap() -> void:
	_phase = LapPhase.RACING
	_phase_remaining = 0.0
	_current_lap_time = 0.0
	if _kart != null:
		_kart.frozen = false
	lap_started.emit()


func _start_pose() -> Transform3D:
	return _start_line.global_transform if _start_line != null else _fallback_start_pose


## One checkpoint, resolved once from its marker so the physics step does no node lookups. A plane
## (origin, forward) carrying a bounded cross-section measured along right and up — the marker's own
## axes, which are the road's axes where it stands, so the prism rolls with the camber.
##
## RefCounted rather than a value type, which GDScript lacks: a handful of instances built in
## _ready, never allocated in the physics step.
class Checkpoint extends RefCounted:
	var node: Node3D = null # the marker; dimming acts on gate_meshes directly
	var gate_meshes: Array[MeshInstance3D] = []
	var active_materials: Array[StandardMaterial3D] = [] # this gate's original override, one per mesh
	var dim_materials: Array[StandardMaterial3D] = [] # duplicates at inactive_gate_alpha
	var origin: Vector3 = Vector3.ZERO
	var forward: Vector3 = Vector3.ZERO
	var right: Vector3 = Vector3.ZERO
	var up: Vector3 = Vector3.ZERO
