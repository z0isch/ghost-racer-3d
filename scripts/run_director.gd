class_name RunDirector
extends Node

## The single owner of all mutable Run state: the Run phase, the Run clock, checkpoint progress,
## the Run's earnings and the record earn rate, and the ghost line — both the in-progress recording
## and the promoted line the pace ghost and the boost ghosts stand on.
##
## Run earnings live here rather than on ClockField because they are the numerator of the earn rate
## and the Run clock is the denominator; splitting a fraction across two owners is how the two come
## to disagree. The purse is the mirror-image call and sits in scripts/purse.gd: a session total is
## not Run state, and housing it behind _begin_countdown's per-Run reset would eventually clear it.
##
## Kart knows nothing about Runs — the director drives it through Kart.frozen and Kart.reset_to().

signal run_started()
## [param is_record] means this Run set a new record earn rate. Carried on the signal rather than
## left for listeners to derive, since deriving it means comparing against a value the director has
## just overwritten.
signal run_completed(run_time: float, is_record: bool)
signal run_aborted()
## Fired as the kart is teleported to the start line, so anything holding a swept previous-position
## sample or per-Run state can invalidate it. [signal run_started] is a frame too late — the clock
## field must already be whole while the driver looks at it during the countdown — and
## run_completed/run_aborted miss the scene load between them.
signal countdown_started()

## Fired the instant the checkpoint sequence wraps back to the first checkpoint. What the countdown
## used to be for the boost and hazard fields: they restore and re-roll on this, so a long Run is
## not one live wrap followed by an empty circuit. The clock field pointedly does not listen — it is
## per-Run (CONTEXT.md's **Clock field**).
signal wrapped()

## One checkpoint payment, the instant the checkpoint is taken. The value is this Run's current
## ladder rung times base_checkpoint_value; the position is the checkpoint marker's own origin, so a
## popup traces where the money was; the direction is the swept segment's own travel direction, for
## ClockField.clock_taken's identical reason — "which way is ahead" arrives with the report rather
## than being looked up from a kart, which is what lets one popup serve both this and an income
## ghost's pickup out in the world.
##
## unbind(2) applies here exactly as it did on ClockField.clock_taken: a one-argument handler connected bare
## fails at emit time and the symptom is a purse that silently stops earning.
signal checkpoint_paid(value: int, position: Vector3, direction: Vector3)

enum RunPhase {
	COUNTDOWN,
	RACING,
	RESULTS,
}

@export var kart_path: NodePath
@export var chase_camera_path: NodePath
## A Marker3D on the circuit: the track owns the start line.
@export var start_line_path: NodePath
## The Checkpoints node: one inert Marker3D each, node order = circuit order.
@export var checkpoints_path: NodePath
## The ClockField whose pickups extend [member run_budget].
@export var clock_field_path: NodePath

## Where the ghost line is persisted. Loaded on [method _ready] if the file exists, and overwritten
## every time a Run promotes a new record — so the "drive one Run to get ghosts" tax is paid once,
## by whoever commits the file, not every session. Empty disables persistence entirely: the line
## behaves exactly as before, session-scoped and lost on exit.
@export_file("*.tres") var ghost_line_path: String = ""

## How long a Run lasts before any clock is taken. Set by race.gd from the circuit's own
## run_duration_seconds, the same way ghost_line_path is set today — RunDirector doesn't know what a
## Circuit is, only the number.
@export var run_duration_seconds: float = 90.0

## What the circuit's first checkpoint pays. Set by race.gd from Circuit.base_checkpoint_value, the
## same way run_duration_seconds is — the director doesn't know what a Circuit is, only the number.
@export var base_checkpoint_value: int = 1

## The checkpoint prism, in each marker's own frame: the road and nothing but the road, from 1 m
## below the surface to 5 m above, which is where the gate's posts and crossbar are. Exported so the
## pair can be pushed apart in a playtest, but meant to match the gate geometry.
@export var checkpoint_half_width: float = 4.0
@export var checkpoint_floor: float = -1.0
@export var checkpoint_ceiling: float = 5.0

## Non-pending gates dim to this alpha rather than vanish, so the field stays visible as a preview
## of the circuit ahead.
@export var inactive_gate_alpha: float = 0.15

## The first countdown is the conventional 3-2-1-GO; restarts get a shorter beat.
@export var first_countdown_seconds: float = 3.0
@export var restart_countdown_seconds: float = 2.0

var _kart: Kart
var _camera: ChaseCamera
var _start_line: Node3D
var _fallback_start_pose: Transform3D = Transform3D.IDENTITY
var _phase: RunPhase = RunPhase.COUNTDOWN
var _run_clock: float = 0.0
var _run_earnings: int = 0
var _record_earn_rate: float = -1.0 # <0 until a Run has actually been completed
var _phase_remaining: float = 0.0
var _checkpoint_index: int = 0
var _checkpoint_count: int = 0
var _checkpoints: Array[Checkpoint] = []
var _last_kart_position: Vector3 = Vector3.ZERO
var _has_last_kart_position: bool = false

## Which rung the next checkpoint pays: 1 for the Run's first, rising by one at every checkpoint
## taken and running straight through every wrap. Reset only in _begin_countdown, alongside
## _run_earnings (CONTEXT.md's **Checkpoint ladder**).
var _ladder_rung: int = 1

## Seconds added to this Run by the clocks taken so far. Cleared at Countdown with everything else.
var _earned_seconds: float = 0.0

# The kart body's pose is exactly position + Y-yaw (rotate_y is the only write to its basis; bank,
# cant and squash live on the Visual child), so these 16 bytes are exact rather than an
# approximation. Paired packed arrays cost 16 bytes/sample against 48 for typed Arrays and 944 for a
# RefCounted sample class; the price is lockstep, so append, clear and duplicate always come in
# threes, confined to _append_sample / complete_run / Run abort.
#
# Double-buffered: the Run being driven is written while the record Run is read, and the two are
# usually not adjacent Runs. Promotion happens in complete_run and only there, so no partial
# recording has a path to the ghost line.
var _recording_positions: PackedVector3Array = PackedVector3Array()
var _recording_yaws: PackedFloat32Array = PackedFloat32Array()
var _recording_checkpoints: PackedInt32Array = PackedInt32Array()
var _ghost_line_positions: PackedVector3Array = PackedVector3Array()
var _ghost_line_yaws: PackedFloat32Array = PackedFloat32Array()
var _ghost_line_checkpoints: PackedInt32Array = PackedInt32Array()

## Polled by the HUD each _process; a per-frame clock pushed through a signal would be a signal in
## name only. Discrete Run edges use the signals above.
var phase: RunPhase:
	get: return _phase

var run_clock: float:
	get: return _run_clock

## Money taken during this Run only, cleared with the Run clock in _begin_countdown. Distinct from
## the purse in every way except its unit (CONTEXT.md, **Run earnings**).
var run_earnings: int:
	get: return _run_earnings

## The live figure, and the identical expression complete_run judges the Run on, so the number you
## watched climb is the number you are scored on. A cumulative average over the whole Run, never
## windowed and never smoothed.
##
## Zero, not a divide-by-zero, at countdown-zero: RunHud shows "--.--" for the first second and
## gates on the clock rather than on this value.
var earn_rate: float:
	get: return 0.0 if _run_clock <= 0.0 else _run_earnings / _run_clock

## The session's highest completed-Run earn rate, and the bar a Run must strictly beat to promote
## its recording to the pace ghost. Stored nowhere else: promotion is exactly "strictly higher rate"
## with no side conditions, so the ghost is the record-holding Run by construction.
var record_earn_rate: float:
	get: return _record_earn_rate

## The Run's whole time budget: the circuit's configured duration plus every clock taken so far.
## Not known at Countdown and rises mid-Run, which is exactly what the HUD readout jumping *up*
## is (CONTEXT.md's **Run clock**).
var run_budget: float:
	get: return run_duration_seconds + _earned_seconds

## Seconds left of the Run, clamped at 0. The Run clock counted the other way, so that the HUD and
## the Timeout rule read off one number rather than each subtracting the budget for themselves.
## Full duration during Countdown, since a Run that has not started has spent nothing.
var run_remaining: float:
	get: return maxf(0.0, run_budget - _run_clock)

## Seconds left of Countdown; 0 while Racing or Results.
var phase_remaining: float:
	get: return _phase_remaining

## The pending checkpoint: the single live one, and equally the count already taken since the last
## wrap. Polled by RunHud for its "CP 3/5" readout.
var checkpoint_index: int:
	get: return _checkpoint_index

var checkpoint_count: int:
	get: return _checkpoint_count

## The record Run's line. Copy-on-write, so reading is ~free and callers must not mutate. Two
## read-only getters rather than a sample_at(t) accessor: the boost ghost field walks the whole
## polyline summing segment lengths, which a per-sample accessor cannot serve without a second
## method — an interface that "hides" the arrays while exposing a raw-array escape hatch hides
## nothing.
var ghost_line_positions: PackedVector3Array:
	get: return _ghost_line_positions

var ghost_line_yaws: PackedFloat32Array:
	get: return _ghost_line_yaws

## The record Run's checkpoint-crossing sample indices, matching [member GhostLine.checkpoint_samples].
## Read by HazardGhostField to slice one wrap's worth of line and by IncomeRunner to pay the ladder.
var ghost_line_checkpoints: PackedInt32Array:
	get: return _ghost_line_checkpoints


func _ready() -> void:
	_kart = get_node_or_null(kart_path) as Kart
	_camera = get_node_or_null(chase_camera_path) as ChaseCamera
	_start_line = get_node_or_null(start_line_path) as Node3D

	# The authored kart transform is editor convenience; the first countdown overwrites it. Kept so a
	# scene without a StartLine teleports somewhere sane rather than to the origin.
	_fallback_start_pose = _kart.global_transform if _kart != null else Transform3D.IDENTITY
	if _start_line == null:
		push_warning("RunDirector: no StartLine node — falling back to the kart's authored transform.")

	_resolve_checkpoints()

	var clock_field: ClockField = get_node_or_null(clock_field_path) as ClockField
	if clock_field != null:
		# unbind(2) drops clock_taken's position and direction arguments. Godot does not drop surplus
		# arguments by itself: connected bare, every pickup would fail at emit time and no Run could
		# ever be extended.
		clock_field.clock_taken.connect(_on_clock_taken.unbind(2))
	else:
		push_warning("RunDirector: no ClockField — no Run can be extended.")

	# The phase must resolve before Kart's physics step reads frozen, or the GO frame is spent still
	# frozen — a dead frame the driver feels as a hitch off the line. Checkpoint detection needs the
	# opposite, the kart's position after move_and_slide, hence the deferred swept test.
	process_physics_priority = -100

	_load_ghost_line()
	_begin_countdown(first_countdown_seconds)


func _physics_process(delta: float) -> void:
	# The director owns "reset". During Countdown/Racing it means Abort: discard the Run and
	# re-run the countdown. During Results it starts a new Run instead — there is no in-progress Run
	# left to discard, so it must not fall into the Abort branch below.
	if _phase != RunPhase.RESULTS and Input.is_action_just_pressed("reset"):
		# The partial recording is thrown away here rather than left standing: a Run abandoned at
		# 90% can never become a ghost line, and the previous line is left untouched.
		_recording_positions.clear()
		_recording_yaws.clear()
		_recording_checkpoints.clear()
		run_aborted.emit()
		_begin_countdown(restart_countdown_seconds)
		return

	match _phase:
		RunPhase.COUNTDOWN:
			_phase_remaining -= delta
			if _phase_remaining <= 0.0:
				_start_run()

		RunPhase.RACING:
			_run_clock += delta
			if _run_clock >= run_budget:
				complete_run()
			else:
				# Queued, not called: this runs at the head of the physics frame, and the swept test
				# needs the position the kart ends the frame at. Sampling is queued after the sweep so
				# a Run-ending crossing in this same flush swaps the buffers before the sample is
				# appended.
				_sweep_pending_checkpoint.call_deferred()
				_append_sample.call_deferred()

		RunPhase.RESULTS:
			if Input.is_action_just_pressed("reset"):
				_begin_countdown(restart_countdown_seconds)


## Called when the Run clock reaches [member run_budget] — a Timeout, the only way a Run ends with
## a result. Holds the promotion rule, and the only copy of it.
func complete_run() -> void:
	var run_time: float = _run_clock
	var rate: float = earn_rate

	# The negative sentinel is the "first completed Run promotes unconditionally" rule: an earn rate
	# is never negative, so a real Run can never sit at or below it, and a zero-earning opening Run
	# still promotes. The strict > is the rest: a tie does not displace the incumbent.
	var is_record: bool = _record_earn_rate < 0.0 or rate > _record_earn_rate
	if is_record:
		_record_earn_rate = rate
		# Packed arrays are copy-on-write, so duplicate() is ~1 µs and the copy is never
		# materialised: the recording is cleared on the next lines regardless.
		_ghost_line_positions = _recording_positions.duplicate()
		_ghost_line_yaws = _recording_yaws.duplicate()
		_ghost_line_checkpoints = _recording_checkpoints.duplicate()
		_save_ghost_line()
	# Unconditional, so a losing Run's samples cannot leak into the next recording and the ghost
	# line can stand unchanged for many Runs.
	_recording_positions.clear()
	_recording_yaws.clear()
	_recording_checkpoints.clear()

	_phase = RunPhase.RESULTS
	if _kart != null:
		_kart.frozen = true # held wherever the Run ended, not teleported
	run_completed.emit(run_time, is_record)


# No phase guard: ClockField sweeps only while Racing and re-checks the phase inside its own
# deferred callback, so a pickup cannot reach here outside a live Run.
func _on_clock_taken(seconds: float) -> void:
	_earned_seconds += seconds


# Resolved once. The markers are inert Marker3Ds in circuit order under a Checkpoints node;
# everything mutable about them lives here.
func _resolve_checkpoints() -> void:
	var root: Node3D = get_node_or_null(checkpoints_path) as Node3D
	if root == null:
		push_warning("RunDirector: no Checkpoints node — no Run can complete.")
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
			var dim_material: StandardMaterial3D = GateDimming.dim_material(gate_mesh, inactive_gate_alpha)
			checkpoint.gate_meshes.append(gate_mesh)
			checkpoint.active_materials.append(active_material)
			checkpoint.dim_materials.append(dim_material)
		checkpoint.origin = frame.origin
		# Basis Z points backwards, so the road's forward is -Z. The crossing test is
		# direction-agnostic, so only the sign convention matters.
		checkpoint.forward = - frame.basis.z.normalized()
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
	if _phase != RunPhase.RACING or _kart == null or _checkpoint_index >= _checkpoints.size():
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
	# Monotonic progress already means a backwards crossing gains nothing, which is why
	# CheckpointPrism's either-direction test is safe to reuse unguarded here.
	var crossed: bool = CheckpointPrism.crossed(previous, position, checkpoint.origin, checkpoint.forward,
			checkpoint.right, checkpoint.up, checkpoint_half_width, checkpoint_floor, checkpoint_ceiling)
	if not crossed:
		return

	var direction: Vector3 = ClockField.sweep_direction(previous, position, _kart.global_transform.basis)
	var value: int = _ladder_rung * base_checkpoint_value
	_run_earnings += value
	_ladder_rung += 1
	checkpoint_paid.emit(value, checkpoint.origin, direction)

	# The index the *next* sample will occupy — the sample taken at the end of this same frame's
	# deferred flush, since _sweep_pending_checkpoint is queued before _append_sample.
	_recording_checkpoints.append(_recording_positions.size())

	_checkpoint_index += 1
	if _checkpoint_index >= _checkpoints.size():
		_checkpoint_index = 0 # wrap — a Run only ends by Timeout or Abort, never here
		wrapped.emit()
	_update_gate_visibility()


# Appended once per physics frame, uncapped. Any coarser rate visibly cuts corners at the distance
# per frame the kart covers at top speed.
#
# Queued, not taken inline: the sample must be the pose the kart finishes the frame at, and the
# kart moves after the director in the same frame, so sampling inline would pair the new clock with
# the previous frame's pose and lay the whole line one frame behind what was driven.
func _append_sample() -> void:
	# Re-checked: the checkpoint sweep is queued first in the same flush and can complete the Run via
	# Timeout on the next frame's head, so this guards against a stray sample landing after Results.
	if _phase != RunPhase.RACING or _kart == null:
		return

	_recording_positions.append(_kart.global_position)
	_recording_yaws.append(_kart.global_rotation.y)


# Populates the ghost line from disk before the first countdown, so ghosts stand on the circuit
# from the session's first Run rather than only after one is driven and promoted. Silent on a
# missing or unreadable file: an unset path or a track that has never been recorded is not an
# error, just an empty ghost line, exactly as before this existed.
func _load_ghost_line() -> void:
	if ghost_line_path.is_empty() or not ResourceLoader.exists(ghost_line_path):
		return
	var ghost_line: GhostLine = load(ghost_line_path) as GhostLine
	if ghost_line == null:
		push_warning("RunDirector: %s did not load as a GhostLine." % ghost_line_path)
		return
	# A line recorded before checkpoint_samples existed has no wrap structure and no ladder-era
	# earn rate, so it is treated as a circuit that has never been driven rather than half-loaded:
	# a pre-ladder rate is a flat-coin figure no ladder Run could be ranked against.
	if ghost_line.checkpoint_samples.is_empty():
		return
	_ghost_line_positions = ghost_line.positions
	_ghost_line_yaws = ghost_line.yaws
	_ghost_line_checkpoints = ghost_line.checkpoint_samples
	_record_earn_rate = ghost_line.earn_rate


# Mirrors the promotion in complete_run to disk, so the next session's _load_ghost_line picks up
# today's record without a driver having to export or commit anything by hand.
func _save_ghost_line() -> void:
	if ghost_line_path.is_empty():
		return
	var ghost_line := GhostLine.new()
	ghost_line.positions = _ghost_line_positions
	ghost_line.yaws = _ghost_line_yaws
	ghost_line.earn_rate = _record_earn_rate
	ghost_line.checkpoint_samples = _ghost_line_checkpoints
	ghost_line.checkpoints_per_wrap = _checkpoint_count
	var error: Error = ResourceSaver.save(ghost_line, ghost_line_path)
	if error != OK:
		push_warning("RunDirector: failed to save ghost line to %s (%s)." % [ghost_line_path, error])


# The one entry point into Countdown: scene load, Timeout and Abort all come through here, so the
# three read identically to the driver.
func _begin_countdown(seconds: float) -> void:
	_phase = RunPhase.COUNTDOWN
	_phase_remaining = seconds
	_run_clock = 0.0
	_run_earnings = 0
	_earned_seconds = 0.0
	_ladder_rung = 1
	_checkpoint_index = 0
	_update_gate_visibility()
	_has_last_kart_position = false # the teleport below invalidates the swept segment

	if _kart != null:
		# Frozen before the teleport, so no physics step can run between the two and re-accelerate
		# from the new pose.
		_kart.frozen = true
		_kart.reset_to(_start_pose())

	# Without this the camera flies the length of the circuit to catch up, every Run.
	if _camera != null:
		_camera.snap_to_target()

	# Emitted last, after the teleport: a listener invalidating a swept sample wants the kart
	# already standing on the start line.
	countdown_started.emit()


func _start_run() -> void:
	_phase = RunPhase.RACING
	_phase_remaining = 0.0
	_run_clock = 0.0
	if _kart != null:
		_kart.frozen = false
	run_started.emit()


func _start_pose() -> Transform3D:
	return _start_line.global_transform if _start_line != null else _fallback_start_pose


## What rung [param rung] of the checkpoint ladder pays at [param base] per rung — the ladder's
## whole arithmetic, extracted so a RefCounted TestCase can reach it without a scene tree.
static func ladder_value(rung: int, base: int) -> int:
	return rung * base


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
