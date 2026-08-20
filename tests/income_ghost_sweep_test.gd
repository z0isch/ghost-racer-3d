class_name IncomeGhostSweepTest
extends TestCase

## IncomeGhostSweep.advance/seat/pose — the substance of issue 06's income runner, pinned exactly
## as CONTEXT.md's **Income** describes it: a coin pays once per lap and again after the wrap, the
## same elapsed time pays the same money regardless of how it is chopped into frames, and separate
## ghosts never compete for a coin.
##
## Every case runs against a plain static line with no scene tree at all, for CoinPickupTest's own
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


func test_no_line_advances_and_collects_nothing() -> void:
	var state := IncomeGhostSweep.State.new()
	var pickups: Array[IncomeGhostSweep.Pickup] = IncomeGhostSweep.advance(
		state, PackedVector3Array(), PackedVector3Array(), PackedInt32Array(), 10.0, SAMPLE_RATE)
	check(pickups.is_empty(), "an empty line collects nothing, however much time passes")
	check(state.segment_index == 0, "and leaves the ghost parked at the head of the (nonexistent) line")


func test_a_coin_on_the_line_is_taken_exactly_once() -> void:
	# A line much longer than the distance advanced below, so the ghost is nowhere near wrapping —
	# the wrap's own effect on the taken-set is test_the_wrap_clears_the_taken_set's to pin.
	var positions: PackedVector3Array = _straight_line(100)
	var coins := PackedVector3Array([Vector3(5.0, 0.0, 0.0)])
	var values := PackedInt32Array([1])
	var state: IncomeGhostSweep.State = IncomeGhostSweep.seat(0, 1, positions)

	# 10 samples' worth of elapsed time carries the ghost from x=0 to x=10, crossing the coin at x=5.
	var pickups: Array[IncomeGhostSweep.Pickup] = IncomeGhostSweep.advance(
		state, positions, coins, values, 10.0 / SAMPLE_RATE, SAMPLE_RATE)

	check(pickups.size() == 1, "the coin on the line is collected exactly once")
	if pickups.size() == 1:
		check(pickups[0].value == 1, "at its own value")

	var again: Array[IncomeGhostSweep.Pickup] = IncomeGhostSweep.advance(
		state, positions, coins, values, 1.0 / SAMPLE_RATE, SAMPLE_RATE)
	check(again.is_empty(), "and not a second time before the lap wraps")


func test_the_wrap_clears_the_taken_set_and_repays_the_coin() -> void:
	var positions: PackedVector3Array = _straight_line(4)
	var coins := PackedVector3Array([Vector3(1.0, 0.0, 0.0)])
	var values := PackedInt32Array([1])
	var state: IncomeGhostSweep.State = IncomeGhostSweep.seat(0, 1, positions)

	# One full lap (4 segments) plus a second lap's worth again, in one call: the coin near the
	# start of the line must be paid twice, once per lap, and not zero or thrice.
	var pickups: Array[IncomeGhostSweep.Pickup] = IncomeGhostSweep.advance(
		state, positions, coins, values, 8.0 / SAMPLE_RATE, SAMPLE_RATE)

	check(pickups.size() == 2, "a coin near the start of a short lap is paid once per lap crossed, not once total")
	check(state.segment_index == 0, "and the ghost sits back at the head of the line after two whole laps")


func test_the_same_elapsed_time_pays_the_same_income_in_one_frame_or_sixty() -> void:
	var positions: PackedVector3Array = _straight_line(120)
	var coins := PackedVector3Array()
	var values := PackedInt32Array()
	for i in 20:
		coins.append(Vector3(float(i) * 5.0 + 2.5, 0.0, 0.0))
		values.append(1)

	var total_seconds: float = 2.0 # a deliberate frame-hitch's worth

	var one_frame := IncomeGhostSweep.State.new()
	var earned_one_frame: int = 0
	for p: IncomeGhostSweep.Pickup in IncomeGhostSweep.advance(
			one_frame, positions, coins, values, total_seconds, SAMPLE_RATE):
		earned_one_frame += p.value

	var sixty_frames := IncomeGhostSweep.State.new()
	var earned_sixty_frames: int = 0
	var per_frame: float = total_seconds / 60.0
	for _i in 60:
		for p: IncomeGhostSweep.Pickup in IncomeGhostSweep.advance(
				sixty_frames, positions, coins, values, per_frame, SAMPLE_RATE):
			earned_sixty_frames += p.value

	check(earned_one_frame == earned_sixty_frames,
		"the same 2 s of income arrives whether delivered as one frame or sixty")
	check(one_frame.segment_index == sixty_frames.segment_index,
		"...and both ghosts end up at exactly the same point on the line")


func test_two_ghosts_at_different_offsets_both_collect_the_same_coin() -> void:
	# Spacing wider than 2x the pickup radius, so the coin sits inside exactly one segment's reach
	# rather than two — a coin straddling a sample vertex would otherwise be caught by whichever of
	# its two neighbouring segments a ghost happens to sweep first, and this suite is not the place
	# to pin that boundary case.
	var positions: PackedVector3Array = _straight_line(10, 5.0)
	var coins := PackedVector3Array([Vector3(22.5, 0.0, 0.0)])
	var values := PackedInt32Array([1])

	var first: IncomeGhostSweep.State = IncomeGhostSweep.seat(0, 2, positions)
	var second: IncomeGhostSweep.State = IncomeGhostSweep.seat(1, 2, positions)

	# A full lap for each, independently: neither ghost's pass should be blocked by the other's.
	var first_pickups: Array[IncomeGhostSweep.Pickup] = IncomeGhostSweep.advance(
		first, positions, coins, values, 10.0 / SAMPLE_RATE, SAMPLE_RATE)
	var second_pickups: Array[IncomeGhostSweep.Pickup] = IncomeGhostSweep.advance(
		second, positions, coins, values, 10.0 / SAMPLE_RATE, SAMPLE_RATE)

	check(first_pickups.size() == 1, "the first ghost collects the coin on its own pass")
	check(second_pickups.size() == 1, "and the second ghost collects it too — ghosts never compete for a coin")


func test_seat_distributes_ghosts_evenly_along_the_line() -> void:
	var positions: PackedVector3Array = _straight_line(100)

	var ghost_0: IncomeGhostSweep.State = IncomeGhostSweep.seat(0, 4, positions)
	var ghost_1: IncomeGhostSweep.State = IncomeGhostSweep.seat(1, 4, positions)
	var ghost_2: IncomeGhostSweep.State = IncomeGhostSweep.seat(2, 4, positions)
	var ghost_3: IncomeGhostSweep.State = IncomeGhostSweep.seat(3, 4, positions)

	check(ghost_0.segment_index == 0, "ghost 0 of 4 starts at the head of the line")
	check_near(float(ghost_1.segment_index) + ghost_1.segment_progress, 25.0, 1e-4, "ghost 1 of 4 starts a quarter of the way in")
	check_near(float(ghost_2.segment_index) + ghost_2.segment_progress, 50.0, 1e-4, "ghost 2 of 4 starts halfway in")
	check_near(float(ghost_3.segment_index) + ghost_3.segment_progress, 75.0, 1e-4, "ghost 3 of 4 starts three-quarters in")


func test_pose_interpolates_between_whole_samples() -> void:
	var positions: PackedVector3Array = _straight_line(10)
	var yaws: PackedFloat32Array = _yaws(11)

	var state := IncomeGhostSweep.State.new()
	state.segment_index = 3
	state.segment_progress = 0.5

	var pose: Transform3D = IncomeGhostSweep.pose(state, positions, yaws)
	check_near(pose.origin.x, 3.5, 1e-4, "a ghost mid-segment is drawn halfway between its two samples")
