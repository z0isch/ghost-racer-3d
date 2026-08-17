class_name HazardGhostPlacementTest
extends TestCase

## The placement rule: HazardGhostField.place_along, and nothing else.
##
## Unlike BoostGhostPlacementTest this rule works purely in arclength — no line, no yaw, no lateral
## offset — because a hazard has nowhere to stand but the line itself; the pose resolution and the
## backward-facing yaw live in _pose_at, exercised instead by the field's own runtime behaviour.

const START_MARGIN: float = 10.0
const END_MARGIN: float = 10.0
## Enough rolls that a bound broken in one draw out of a handful still shows up every run.
const ROLLS: int = 200
const LINE_LENGTH: float = 100.0


func suite_name() -> String:
	return "HazardGhostPlacementTest"


func _place(total_length: float, count: int,
		start_margin: float = START_MARGIN, end_margin: float = END_MARGIN,
		jitter: float = 0.0,
		rng: RandomNumberGenerator = RandomNumberGenerator.new()) -> Array[float]:
	return HazardGhostField.place_along(total_length, count, start_margin, end_margin, rng, jitter)


func test_count_zero_is_empty() -> void:
	check(_place(LINE_LENGTH, 0).is_empty(), "no hazards requested, none placed")


func test_zero_length_line_is_empty() -> void:
	check(_place(0.0, 3).is_empty(), "no line, no hazards")


func test_count_one_sits_dead_centre_of_the_usable_span() -> void:
	var distances: Array[float] = _place(LINE_LENGTH, 1)
	check(distances.size() == 1, "exactly one hazard placed")
	# Usable span is [10, 90], 80 m long; its centre is 50.
	check_near(distances[0], 50.0, 1e-4, "a single hazard centres the usable span")


func test_margins_summing_past_the_line_length_are_empty() -> void:
	var distances: Array[float] = _place(15.0, 3) # shorter than the 10+10 margins leave usable
	check(distances.is_empty(), "margins that consume the whole line place nothing, not negative spacing")


func test_a_straight_line_of_known_length_places_exact_midpoint_distances() -> void:
	var distances: Array[float] = _place(LINE_LENGTH, 4)
	check(distances.size() == 4, "four hazards requested, four placed")
	# Usable span [10, 90], 80 m long, quarters of 20 m, midpoints at 10 + 10, 30, 50, 70.
	var expected: Array[float] = [20.0, 40.0, 60.0, 80.0]
	for i in expected.size():
		check_near(distances[i], expected[i], 1e-4,
			"hazard %d sits at its exact midpoint distance along the line" % i)


func test_full_jitter_never_leaves_a_hazard_s_own_slot() -> void:
	# Usable span [10, 90], four 20 m slots, so hazard i lives in [10 + 20i, 30 + 20i].
	var rng := RandomNumberGenerator.new()

	for roll in ROLLS:
		var distances: Array[float] = _place(LINE_LENGTH, 4, START_MARGIN, END_MARGIN, 1.0, rng)
		check(distances.size() == 4, "four hazards requested, four placed")
		for i in distances.size():
			var low: float = 10.0 + 20.0 * i
			check(distances[i] >= low - 1e-4 and distances[i] <= low + 20.0 + 1e-4,
				"hazard %d stays inside its own slot" % i)


func test_jitter_moves_the_field_between_rolls() -> void:
	# The ghost line only changes on a record lap, so without jitter two consecutive countdowns
	# rebuild the identical field.
	var rng := RandomNumberGenerator.new()

	var first: Array[float] = _place(LINE_LENGTH, 5, START_MARGIN, END_MARGIN, 0.8, rng)
	var second: Array[float] = _place(LINE_LENGTH, 5, START_MARGIN, END_MARGIN, 0.8, rng)

	var moved: bool = false
	for i in first.size():
		if absf(first[i] - second[i]) > 1e-4:
			moved = true
	check(moved, "a second roll of the same line is not the first one again")


func test_zero_jitter_reproduces_the_fixed_field() -> void:
	var rng := RandomNumberGenerator.new()
	var expected: Array[float] = [20.0, 40.0, 60.0, 80.0]
	for roll in ROLLS:
		var distances: Array[float] = _place(LINE_LENGTH, 4, START_MARGIN, END_MARGIN, 0.0, rng)
		for i in distances.size():
			check_near(distances[i], expected[i], 1e-4, "hazard %d is pinned to its midpoint" % i)
