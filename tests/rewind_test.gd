class_name RewindTest
extends TestCase

## The Rewind mechanic's contract (CONTEXT.md's **Rewind**), tested at the seam that makes it
## testable headlessly at all: capture_state()/restore_state() on Kart, ClockField, BoostGhostField,
## HazardGhostField, SlipstreamGhostField and RunDirector never touch the scene tree or Input, so
## every one of them (Kart excepted — see below) can be built bare and driven directly.
##
## Kart itself is left out: its @onready fields ($GroundRay, $Cosmetics, $CollisionShape3D) only
## resolve once it is added to a tree, which this suite deliberately never does (see
## tests/run_tests.gd's own doc). KartModel — the RefCounted half of the pair Kart's own
## capture_state/restore_state delegate to — carries the whole of the interesting logic and is
## covered fully below.
##
## The four things spec.md calls out as failing *silently*: a capture that leaks a Node/RefCounted/
## Resource reference, a round-trip that doesn't restore exactly, a truncation that leaves a stale
## checkpoint index, and a ladder that doesn't roll back. A fifth test covers un-spawning interval
## traffic. Not tested here, deliberately: the scrub rate, the cap, and how any of it feels — those
## are playtest.


func suite_name() -> String:
	return "RewindTest"


# --- Fixtures ------------------------------------------------------------------------------------

func _fresh_clock(taken: bool = false) -> ClockField.Clock:
	var clock := ClockField.Clock.new()
	clock.node = Node3D.new()
	clock.taken = taken
	clock.node.visible = not taken
	return clock


func _fresh_boost_ghost(taken: bool = false) -> BoostGhostField.Ghost:
	var ghost := BoostGhostField.Ghost.new()
	ghost.node = Node3D.new()
	ghost.taken = taken
	ghost.node.visible = not taken
	return ghost


func _fresh_hazard(distance: float, taken: bool = false) -> HazardGhostField.Hazard:
	var hazard := HazardGhostField.Hazard.new()
	hazard.node = Node3D.new()
	hazard.ribbon = MeshInstance3D.new()
	hazard.distance = distance
	hazard.taken = taken
	hazard.node.visible = not taken
	hazard.ribbon.visible = false
	hazard.lane_positions = PackedVector3Array([Vector3.ZERO, Vector3(10.0, 0.0, 0.0)])
	hazard.lane_yaws = PackedFloat32Array([0.0, 0.0])
	hazard.lane_cumulative = PackedFloat32Array([0.0, 10.0])
	hazard.lane_length = 10.0
	return hazard


func _fresh_slipstream(distance: float, taken: bool = false) -> SlipstreamGhostField.Slipstream:
	var ghost := SlipstreamGhostField.Slipstream.new()
	ghost.node = Node3D.new()
	ghost.ribbon = MeshInstance3D.new()
	ghost.distance = distance
	ghost.taken = taken
	ghost.node.visible = not taken
	ghost.ribbon.visible = false
	ghost.lane_positions = PackedVector3Array([Vector3.ZERO, Vector3(10.0, 0.0, 0.0)])
	ghost.lane_yaws = PackedFloat32Array([0.0, 0.0])
	ghost.lane_cumulative = PackedFloat32Array([0.0, 10.0])
	ghost.lane_length = 10.0
	return ghost


# --- 1. Capture round-trip is pure data -----------------------------------------------------------
# The constraint the whole testable design rests on: no capture may hold a Node, RefCounted or
# Resource reference, recursively through every Dictionary/Array it contains.

func _is_plain_data(value: Variant) -> bool:
	match typeof(value):
		TYPE_OBJECT:
			return false
		TYPE_DICTIONARY:
			# Assigned straight into the typed local rather than an inline "as Dictionary" cast:
			# match on typeof() already proves this at runtime, but the static checker cannot see
			# that, and this project's warnings table makes a hard "as" cast here an error.
			var dict: Dictionary = value
			for key: Variant in dict.keys():
				if not _is_plain_data(key) or not _is_plain_data(dict[key]):
					return false
			return true
		TYPE_ARRAY:
			var arr: Array = value
			for item: Variant in arr:
				if not _is_plain_data(item):
					return false
			return true
		_:
			return true


func test_every_owners_capture_is_pure_data() -> void:
	var model := KartModel.new(KartTuning.new())
	check(_is_plain_data(model.capture_state()),
		"KartModel.capture_state must hold no Node/RefCounted/Resource reference")

	var clock_field := ClockField.new()
	clock_field._clocks.append(_fresh_clock())
	check(_is_plain_data(clock_field.capture_state()),
		"ClockField.capture_state must hold no Node/RefCounted/Resource reference")

	var boost_field := BoostGhostField.new()
	boost_field._ghosts.append(_fresh_boost_ghost())
	check(_is_plain_data(boost_field.capture_state()),
		"BoostGhostField.capture_state must hold no Node/RefCounted/Resource reference")

	var hazard_field := HazardGhostField.new()
	hazard_field._ghosts.append(_fresh_hazard(0.0))
	check(_is_plain_data(hazard_field.capture_state()),
		"HazardGhostField.capture_state must hold no Node/RefCounted/Resource reference")

	var slipstream_field := SlipstreamGhostField.new()
	slipstream_field._ghosts.append(_fresh_slipstream(0.0))
	check(_is_plain_data(slipstream_field.capture_state()),
		"SlipstreamGhostField.capture_state must hold no Node/RefCounted/Resource reference")

	var director := RunDirector.new()
	check(_is_plain_data(director.capture_state()),
		"RunDirector.capture_state must hold no Node/RefCounted/Resource reference")


# --- 2. Round-trip fidelity -----------------------------------------------------------------------
# capture -> mutate -> restore -> capture must yield an equal Dictionary, per owner.

func test_kart_model_round_trips_exactly() -> void:
	var model := KartModel.new(KartTuning.new())
	model._forward_speed = 12.0
	model._steer_angle = 0.3
	model._rear_slip_angle = -0.2
	model._boost_charges = 2
	model._hop_active = true
	model._hop_elapsed = 0.05
	var before: Dictionary = model.capture_state()

	model._forward_speed = 99.0
	model._boost_charges = 0
	model._hop_active = false

	model.restore_state(before)
	check(model.capture_state() == before, "KartModel must round-trip exactly")


func test_clock_field_round_trips_exactly() -> void:
	var field := ClockField.new()
	field._clocks.append(_fresh_clock(false))
	field._clocks.append(_fresh_clock(true))
	field._last_kart_centre = Vector3(1.0, 2.0, 3.0)
	field._last_kart_yaw = 0.7
	field._has_last_kart_pose = true
	var before: Dictionary = field.capture_state()

	field._clocks[0].taken = true
	field._clocks[0].node.visible = false
	field._clocks[1].taken = false
	field._clocks[1].node.visible = true
	field._has_last_kart_pose = false

	field.restore_state(before)
	check(field.capture_state() == before, "ClockField must round-trip exactly")
	check(not field._clocks[0].taken and field._clocks[0].node.visible,
		"an untaken clock's node is visible again after restore")
	check(field._clocks[1].taken and not field._clocks[1].node.visible,
		"a taken clock's node stays hidden after restore")


func test_boost_ghost_field_round_trips_exactly() -> void:
	var field := BoostGhostField.new()
	field._ghosts.append(_fresh_boost_ghost(false))
	field._ghosts.append(_fresh_boost_ghost(true))
	field._elapsed = 3.5
	var before: Dictionary = field.capture_state()

	field._ghosts[0].taken = true
	field._elapsed = 99.0

	field.restore_state(before)
	check(field.capture_state() == before, "BoostGhostField must round-trip exactly")


func test_hazard_ghost_field_round_trips_exactly() -> void:
	var field := HazardGhostField.new()
	field._ghosts.append(_fresh_hazard(2.0, false))
	field._ghosts.append(_fresh_hazard(4.0, true))
	field._elapsed = 1.2
	field._spawn_timer = 0.4
	var before: Dictionary = field.capture_state()

	field._ghosts[0].distance = 8.0
	field._ghosts[0].taken = true
	field._ghosts[0].node.visible = false
	field._spawn_timer = 0.0

	field.restore_state(before)
	check(field.capture_state() == before, "HazardGhostField must round-trip exactly")
	check_near(field._ghosts[0].distance, 2.0, 1e-6, "distance restored")
	check(not field._ghosts[0].taken, "taken flag restored via node.visible")


func test_slipstream_ghost_field_round_trips_exactly() -> void:
	var field := SlipstreamGhostField.new()
	field._ghosts.append(_fresh_slipstream(2.0, false))
	field._ghosts.append(_fresh_slipstream(4.0, true))
	field._elapsed = 1.2
	field._spawn_timer = 0.4
	var before: Dictionary = field.capture_state()

	field._ghosts[0].distance = 8.0
	field._ghosts[0].taken = true

	field.restore_state(before)
	check(field.capture_state() == before, "SlipstreamGhostField must round-trip exactly")


func test_run_director_round_trips_exactly() -> void:
	var director := RunDirector.new()
	director._run_earnings = 40
	director._run_checkpoints_taken = 6
	director._earned_seconds = 12.5
	director._ladder_rung = 7
	director._checkpoint_index = 2
	director._wrap_start_clock = 3.0
	director._wraps_completed = 1
	director._condition = 2
	director._slipstream_taken = 4
	var before: Dictionary = director.capture_state()

	director._run_earnings = 0
	director._ladder_rung = 1
	director._condition = 0

	director.restore_state(before)
	check(director.capture_state() == before, "RunDirector must round-trip exactly")
	check(director._condition == 2, "condition rolled back to its pre-hit value")


# --- 3. Truncation lockstep -----------------------------------------------------------------------
# The crash-shaped one: a rewind accepted before a checkpoint crossing must drop that crossing's
# index, or a promoted line reads out of bounds the moment the income runner walks it.

func test_truncation_drops_every_checkpoint_index_past_the_rewound_to_sample_count() -> void:
	var director := RunDirector.new()
	for i in 5:
		director._recording_positions.append(Vector3(float(i), 0.0, 0.0))
		director._recording_yaws.append(0.0)
	director._recording_checkpoints.append(3) # survives: 3 < 5

	var snapshot: Dictionary = director.capture_state() # recording_length == 5

	# Drive on past the rewound-to instant: more samples, and a checkpoint crossing that only
	# exists in the future this rewind is about to erase.
	for i in range(5, 10):
		director._recording_positions.append(Vector3(float(i), 0.0, 0.0))
		director._recording_yaws.append(0.0)
	director._recording_checkpoints.append(7) # must be dropped: 7 >= 5

	director.restore_state(snapshot)
	director._truncate_recording()

	check(director._recording_positions.size() == 5, "positions truncated to the captured sample count")
	check(director._recording_yaws.size() == 5, "yaws truncated in lockstep with positions")
	check(director._recording_checkpoints.size() == 1,
		"the checkpoint crossing past the truncation point is dropped")
	check(director._recording_checkpoints[0] == 3, "the checkpoint crossing before it survives")


# --- 4. Ladder rollback --------------------------------------------------------------------------
# Without this, retaking a checkpoint after a rewind pays rung n+1 instead of rung n again — an
# unbounded money exploit for anyone who notices a rewind can be taken right before every gate.

func test_retaking_a_checkpoint_after_a_rewind_pays_the_same_rung_again() -> void:
	var director := RunDirector.new()
	director._run_earnings = 100
	director._ladder_rung = 5
	director._run_checkpoints_taken = 4
	var snapshot: Dictionary = director.capture_state()

	var base: int = 3
	var paid_first: int = RunDirector.ladder_value(director._ladder_rung, base)
	director._run_earnings += paid_first
	director._ladder_rung += 1
	director._run_checkpoints_taken += 1
	check(director._ladder_rung == 6, "the ladder rung advances when a checkpoint is taken")

	director.restore_state(snapshot)
	check(director._ladder_rung == 5, "a rewind rolls the ladder rung back to its pre-hit value")

	var paid_second: int = RunDirector.ladder_value(director._ladder_rung, base)
	director._run_earnings += paid_second
	director._ladder_rung += 1

	check(paid_second == paid_first,
		"retaking the same checkpoint after a rewind must pay rung n again, not n+1")


# --- 5. Interval traffic un-spawns ------------------------------------------------------------
# Without this, every rewind leaves the circuit slightly more crowded than the instant it returns
# to, and repeated rewinds make the Run monotonically harder — the inverse of what a rewind is for.

func test_hazard_field_un_spawns_traffic_thickened_after_the_capture() -> void:
	var field := HazardGhostField.new()
	for i in 3:
		field._ghosts.append(_fresh_hazard(float(i)))
	var snapshot: Dictionary = field.capture_state()

	var extra_a: HazardGhostField.Hazard = _fresh_hazard(5.0)
	var extra_b: HazardGhostField.Hazard = _fresh_hazard(6.0)
	field._ghosts.append(extra_a)
	field._ghosts.append(extra_b)
	check(field._ghosts.size() == 5, "the field thickened to 5 cars via spawn-interval traffic")

	field.restore_state(snapshot)

	check(field._ghosts.size() == 3, "restore un-spawns back to the captured count")
	check(extra_a.node.is_queued_for_deletion(), "the extra car's node is freed")
	check(extra_b.ribbon.is_queued_for_deletion(), "the extra car's ribbon is freed")


func test_slipstream_field_un_spawns_traffic_thickened_after_the_capture() -> void:
	var field := SlipstreamGhostField.new()
	for i in 2:
		field._ghosts.append(_fresh_slipstream(float(i)))
	var snapshot: Dictionary = field.capture_state()

	var extra: SlipstreamGhostField.Slipstream = _fresh_slipstream(9.0)
	field._ghosts.append(extra)
	check(field._ghosts.size() == 3, "the field thickened to 3 cars via spawn-interval traffic")

	field.restore_state(snapshot)

	check(field._ghosts.size() == 2, "restore un-spawns back to the captured count")
	check(extra.node.is_queued_for_deletion(), "the extra car's node is freed")
