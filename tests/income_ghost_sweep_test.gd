class_name IncomeGhostSweepTest
extends TestCase

## IncomeGhostSweep.advance/seat/pose — the substance of the income runner, pinned exactly as
## CONTEXT.md's **Income** describes it: rung n is paid at crossing n, the ladder restarts at rung 1
## when the recording pops back to the start, the same elapsed time pays the same money regardless
## of how it is chopped into frames, and separate ghosts never compete for a crossing.
##
## Every case runs against a plain static line with no scene tree at all, for ClockPickupTest's own
## reason: this is the seam a TestCase can reach.

const SAMPLE_RATE: float = 60.0


func suite_name() -> String:
	return "IncomeGhostSweepTest"


## A straight line along +X, [param length] samples apart by [param spacing], so a segment is
## [param spacing] metres long and advancing SAMPLE_RATE seconds' worth of samples per second
## crosses exactly one segment per (1.0 / SAMPLE_RATE) seconds of simulated time — the sample rate
## the line was "recorded" at.
func _straight_line(length: int, spacing: float = 1.0) -> PackedVector3Array:
	var positions := PackedVector3Array()
	for i in length + 1:
		positions.append(Vector3(float(i) * spacing, 0.0, 0.0))
	return positions


func _yaws(count: int) -> PackedFloat32Array:
	var yaws := PackedFloat32Array()
	for i in count:
		yaws.append(0.0)
	return yaws


func test_no_line_advances_and_pays_nothing() -> void:
	var state := IncomeGhostSweep.State.new()
	var pickups: Array[IncomeGhostSweep.Pickup] = IncomeGhostSweep.advance(
		state, PackedVector3Array(), PackedInt32Array(), 1, 10.0, SAMPLE_RATE)
	check(pickups.is_empty(), "an empty line pays nothing, however much time passes")
	check(state.segment_index == 0, "and leaves the ghost parked at the head of the (nonexistent) line")


func test_rung_n_is_paid_at_crossing_n() -> void:
	var positions: PackedVector3Array = _straight_line(100)
	var crossings := PackedInt32Array([5, 20, 40])
	var state: IncomeGhostSweep.State = IncomeGhostSweep.seat(0, 1, positions, crossings)

	# 45 samples' worth of elapsed time carries the ghost past every crossing above.
	var pickups: Array[IncomeGhostSweep.Pickup] = IncomeGhostSweep.advance(
		state, positions, crossings, 1, 45.0 / SAMPLE_RATE, SAMPLE_RATE)

	check(pickups.size() == 3, "every crossing reached this call is paid")
	if pickups.size() == 3:
		check(pickups[0].value == 1, "the first crossing pays rung 1")
		check(pickups[1].value == 2, "the second crossing pays rung 2")
		check(pickups[2].value == 3, "the third crossing pays rung 3")


func test_the_ladder_scales_with_base_value() -> void:
	var positions: PackedVector3Array = _straight_line(100)
	var crossings := PackedInt32Array([5, 10])
	var state: IncomeGhostSweep.State = IncomeGhostSweep.seat(0, 1, positions, crossings)

	var pickups: Array[IncomeGhostSweep.Pickup] = IncomeGhostSweep.advance(
		state, positions, crossings, 3, 15.0 / SAMPLE_RATE, SAMPLE_RATE)

	check(pickups.size() == 2, "both crossings are reached")
	if pickups.size() == 2:
		check(pickups[0].value == 3, "rung 1 at base value 3 pays 3")
		check(pickups[1].value == 6, "rung 2 at base value 3 pays 6")


func test_the_recording_popping_restarts_the_ladder_at_rung_one() -> void:
	var positions: PackedVector3Array = _straight_line(4)
	var crossings := PackedInt32Array([1])
	var state: IncomeGhostSweep.State = IncomeGhostSweep.seat(0, 1, positions, crossings)

	# One full pass of the recording (4 segments) plus a second pass's worth again, in one call: the
	# crossing near the start of the line must be paid twice, at rung 1 both times, and not zero,
	# thrice, or at a rung that kept climbing across the pop.
	var pickups: Array[IncomeGhostSweep.Pickup] = IncomeGhostSweep.advance(
		state, positions, crossings, 1, 8.0 / SAMPLE_RATE, SAMPLE_RATE)

	check(pickups.size() == 2, "a crossing near the start of a short recording is paid once per pass, not once total")
	if pickups.size() == 2:
		check(pickups[0].value == 1, "the first pass pays rung 1")
		check(pickups[1].value == 1, "and so does the second — the ladder restarts, it does not keep climbing")
	check(state.segment_index == 0, "and the ghost sits back at the head of the line after two whole passes")


func test_the_same_elapsed_time_pays_the_same_income_in_one_frame_or_sixty() -> void:
	var positions: PackedVector3Array = _straight_line(120)
	var crossings := PackedInt32Array()
	for i in 20:
		crossings.append(i * 6 + 3)

	var total_seconds: float = 2.0 # a deliberate frame-hitch's worth

	var one_frame := IncomeGhostSweep.State.new()
	var earned_one_frame: int = 0
	for p: IncomeGhostSweep.Pickup in IncomeGhostSweep.advance(
			one_frame, positions, crossings, 1, total_seconds, SAMPLE_RATE):
		earned_one_frame += p.value

	var sixty_frames := IncomeGhostSweep.State.new()
	var earned_sixty_frames: int = 0
	var per_frame: float = total_seconds / 60.0
	for _i in 60:
		for p: IncomeGhostSweep.Pickup in IncomeGhostSweep.advance(
				sixty_frames, positions, crossings, 1, per_frame, SAMPLE_RATE):
			earned_sixty_frames += p.value

	check(earned_one_frame == earned_sixty_frames,
		"the same 2 s of income arrives whether delivered as one frame or sixty")
	check(one_frame.segment_index == sixty_frames.segment_index,
		"...and both ghosts end up at exactly the same point on the line")


func test_two_ghosts_at_different_offsets_both_pay_the_same_crossing() -> void:
	var positions: PackedVector3Array = _straight_line(10, 5.0)
	var crossings := PackedInt32Array([5])

	var first: IncomeGhostSweep.State = IncomeGhostSweep.seat(0, 2, positions, crossings)
	var second: IncomeGhostSweep.State = IncomeGhostSweep.seat(1, 2, positions, crossings)

	# A full pass for each, independently: neither ghost's pass should be blocked by the other's.
	var first_pickups: Array[IncomeGhostSweep.Pickup] = IncomeGhostSweep.advance(
		first, positions, crossings, 1, 10.0 / SAMPLE_RATE, SAMPLE_RATE)
	var second_pickups: Array[IncomeGhostSweep.Pickup] = IncomeGhostSweep.advance(
		second, positions, crossings, 1, 10.0 / SAMPLE_RATE, SAMPLE_RATE)

	check(first_pickups.size() == 1, "the first ghost pays the crossing on its own pass")
	check(second_pickups.size() == 1, "and the second ghost pays it too — ghosts never compete for a crossing")


func test_seat_distributes_ghosts_evenly_along_the_line() -> void:
	var positions: PackedVector3Array = _straight_line(100)
	var crossings := PackedInt32Array()

	var ghost_0: IncomeGhostSweep.State = IncomeGhostSweep.seat(0, 4, positions, crossings)
	var ghost_1: IncomeGhostSweep.State = IncomeGhostSweep.seat(1, 4, positions, crossings)
	var ghost_2: IncomeGhostSweep.State = IncomeGhostSweep.seat(2, 4, positions, crossings)
	var ghost_3: IncomeGhostSweep.State = IncomeGhostSweep.seat(3, 4, positions, crossings)

	check(ghost_0.segment_index == 0, "ghost 0 of 4 starts at the head of the line")
	check_near(float(ghost_1.segment_index) + ghost_1.segment_progress, 25.0, 1e-4, "ghost 1 of 4 starts a quarter of the way in")
	check_near(float(ghost_2.segment_index) + ghost_2.segment_progress, 50.0, 1e-4, "ghost 2 of 4 starts halfway in")
	check_near(float(ghost_3.segment_index) + ghost_3.segment_progress, 75.0, 1e-4, "ghost 3 of 4 starts three-quarters in")


func test_seat_skips_crossings_already_passed_by_its_offset() -> void:
	var positions: PackedVector3Array = _straight_line(100)
	# Seating ghost 2 of 4 lands it at segment 50 (see the placement test above); every crossing at
	# or before that must not be paid again the instant this ghost starts running.
	var crossings := PackedInt32Array([10, 30, 50, 70, 90])

	var state: IncomeGhostSweep.State = IncomeGhostSweep.seat(2, 4, positions, crossings)
	check(state.next_crossing == 3, "seat() skips every crossing at or before the seated offset")

	var pickups: Array[IncomeGhostSweep.Pickup] = IncomeGhostSweep.advance(
		state, positions, crossings, 1, 1.0 / SAMPLE_RATE, SAMPLE_RATE)
	check(pickups.is_empty(), "and the next single-segment step does not immediately re-pay one of them")


func test_pose_interpolates_between_whole_samples() -> void:
	var positions: PackedVector3Array = _straight_line(10)
	var yaws: PackedFloat32Array = _yaws(11)

	var state := IncomeGhostSweep.State.new()
	state.segment_index = 3
	state.segment_progress = 0.5

	var pose: Transform3D = IncomeGhostSweep.pose(state, positions, yaws)
	check_near(pose.origin.x, 3.5, 1e-4, "a ghost mid-segment is drawn halfway between its two samples")
