class_name BoostGhostPlacementTest
extends TestCase

## The placement rule: BoostGhostField.place_along, and nothing else.
##
## Every case here is a boundary the eye cannot check from the driver's seat — a division by zero
## on a duplicate sample, an off-by-one at the margins, a yaw that spins the wrong way at pi, a
## jitter that lets one ghost stray into a neighbour's slot.
##
## place_along returns racing-line poses only: fanning a pose out perpendicular to the road is
## BoostGhostField._lateral_placements's job and needs the scene tree this suite cannot touch. That
## behaviour is exercised by the field's own runtime behaviour, not here.
##
## The randomised cases assert the bounds the draw must respect rather than the values it produced,
## and roll many times: a case that pinned a seed's exact output would fail on any change to the
## order the draws are taken in, which is not a behaviour worth freezing.
##
## Every case is called statically, with no BoostGhostField instance: a TestCase is a RefCounted
## that must not touch the scene tree.

const START_MARGIN: float = 10.0
const END_MARGIN: float = 10.0
## Enough rolls that a bound broken in one draw out of a handful still shows up every run.
const ROLLS: int = 200


func suite_name() -> String:
	return "BoostGhostPlacementTest"


## One sample per metre along +X, yaw a constant facing +X throughout, so any test that doesn't
## care about yaw can ignore it. RefCounted rather than a two-element Array: GDScript has no tuple,
## and an untyped Array degrades both fields to Variant at every call site that unpacks it.
class Line extends RefCounted:
	var positions: PackedVector3Array
	var yaws: PackedFloat32Array


## 100 m of straight line along +X: 0, 0, 0 .. 100, 0, 0, at a constant [param yaw].
func _straight_line(length: int, yaw: float = 0.0) -> Line:
	var line := Line.new()
	for i in length + 1:
		line.positions.append(Vector3(float(i), 0.0, 0.0))
		line.yaws.append(yaw)
	return line


## Defaults to the unjittered field: every case that predates the randomisation still asserts exact
## slot midpoints, so the skeleton the jitter perturbs stays pinned.
func _place(positions: PackedVector3Array, yaws: PackedFloat32Array, count: int,
		start_margin: float = START_MARGIN, end_margin: float = END_MARGIN,
		jitter: float = 0.0,
		rng: RandomNumberGenerator = RandomNumberGenerator.new()) -> Array[Transform3D]:
	return BoostGhostField.place_along(
		positions, yaws, count, start_margin, end_margin, rng, jitter
	)


func test_count_zero_is_empty() -> void:
	var line: Line = _straight_line(100)
	check(_place(line.positions, line.yaws, 0).is_empty(), "no ghosts requested, none placed")


func test_count_one_sits_dead_centre_of_the_usable_span() -> void:
	var line: Line = _straight_line(100)
	var poses: Array[Transform3D] = _place(line.positions, line.yaws, 1)

	check(poses.size() == 1, "exactly one ghost placed")
	# Usable span is [10, 90], 80 m long; its centre is 50.
	check(absf(poses[0].origin.x - 50.0) < 1e-4, "a single ghost centres the usable span")


func test_margins_summing_past_the_line_length_are_empty() -> void:
	var line: Line = _straight_line(15) # shorter than the 10+10 margins leave usable
	var poses: Array[Transform3D] = _place(line.positions, line.yaws, 3)
	check(poses.is_empty(), "margins that consume the whole line place nothing, not negative spacing")


func test_an_empty_line_is_empty() -> void:
	var positions := PackedVector3Array()
	var yaws := PackedFloat32Array()
	check(_place(positions, yaws, 3).is_empty(), "no line, no ghosts")


func test_a_one_sample_line_is_empty() -> void:
	var positions := PackedVector3Array([Vector3.ZERO])
	var yaws := PackedFloat32Array([0.0])
	check(_place(positions, yaws, 3).is_empty(), "a single point has no length to place along")


func test_duplicate_consecutive_samples_do_not_crash_or_nan() -> void:
	# The kart is frozen on the start line through the countdown, so the first samples of every lap
	# are identical points. A handful of them sit at the head of an otherwise ordinary line.
	var positions := PackedVector3Array()
	var yaws := PackedFloat32Array()
	for i in 5:
		positions.append(Vector3.ZERO)
		yaws.append(0.0)
	var line: Line = _straight_line(100)
	for i in line.positions.size():
		positions.append(line.positions[i])
		yaws.append(line.yaws[i])

	var poses: Array[Transform3D] = _place(positions, yaws, 5)
	check(poses.size() == 5, "duplicate samples at the head still yield the requested count")
	for pose: Transform3D in poses:
		check(not is_nan(pose.origin.x) and not is_nan(pose.origin.y) and not is_nan(pose.origin.z),
			"no NaN leaks out of a zero-length segment")


func test_a_straight_line_of_known_length_places_exact_midpoint_distances() -> void:
	var line: Line = _straight_line(100)
	var poses: Array[Transform3D] = _place(line.positions, line.yaws, 4)

	check(poses.size() == 4, "four ghosts requested, four placed")
	# Usable span [10, 90], 80 m long, quarters of 20 m, midpoints at 10 + 10, 30, 50, 70.
	var expected: Array[float] = [20.0, 40.0, 60.0, 80.0]
	for i in expected.size():
		check_near(poses[i].origin.x, expected[i], 1e-4,
			"ghost %d sits at its exact midpoint distance along the line" % i)


func test_yaw_wraps_the_short_way_across_pi() -> void:
	# Two samples straddling the wrap: just under +pi and just under -pi, a hair apart in angle but
	# far apart as plain numbers. A plain lerp would spin the long way round.
	var positions := PackedVector3Array([Vector3.ZERO, Vector3(10.0, 0.0, 0.0)])
	var near_pi: float = PI - 0.1
	var near_negative_pi: float = -PI + 0.1
	var yaws := PackedFloat32Array([near_pi, near_negative_pi])

	var poses: Array[Transform3D] = _place(positions, yaws, 1, 0.0, 0.0)
	var yaw: float = poses[0].basis.get_euler().y

	check_near(absf(angle_difference(yaw, PI)), 0.0, 1e-3,
		"the short way across the wrap lands near +/- pi, not near 0")


func test_full_jitter_never_leaves_a_ghost_s_own_slot() -> void:
	# The stratification claim, and the reason the field can re-roll every lap without clumping: at
	# the loosest setting a ghost may reach its slot's edge and no further. Usable span [10, 90],
	# four 20 m slots, so ghost i lives in [10 + 20i, 30 + 20i].
	var line: Line = _straight_line(100)
	var rng := RandomNumberGenerator.new()

	for roll in ROLLS:
		var poses: Array[Transform3D] = _place(line.positions, line.yaws, 4, START_MARGIN, END_MARGIN,
			1.0, rng)
		check(poses.size() == 4, "four ghosts requested, four placed")
		for i in poses.size():
			var low: float = 10.0 + 20.0 * i
			check(poses[i].origin.x >= low - 1e-4 and poses[i].origin.x <= low + 20.0 + 1e-4,
				"ghost %d stays inside its own slot" % i)


func test_jitter_moves_the_field_between_rolls() -> void:
	# The complaint the jitter exists to answer: the ghost line only changes on a record lap, so
	# without this two consecutive countdowns rebuild the identical field.
	var line: Line = _straight_line(100)
	var rng := RandomNumberGenerator.new()

	var first: Array[Transform3D] = _place(line.positions, line.yaws, 5, START_MARGIN, END_MARGIN,
		0.8, rng)
	var second: Array[Transform3D] = _place(line.positions, line.yaws, 5, START_MARGIN, END_MARGIN,
		0.8, rng)

	var moved: bool = false
	for i in first.size():
		if absf(first[i].origin.x - second[i].origin.x) > 1e-4:
			moved = true
	check(moved, "a second roll of the same line is not the first one again")


func test_zero_jitter_reproduces_the_fixed_field() -> void:
	# The knob turned off is the old behaviour exactly, so a circuit can opt out of the
	# randomisation without opting out of the placement.
	var line: Line = _straight_line(100)
	var rng := RandomNumberGenerator.new()

	var expected: Array[float] = [20.0, 40.0, 60.0, 80.0]
	for roll in ROLLS:
		var poses: Array[Transform3D] = _place(line.positions, line.yaws, 4, START_MARGIN, END_MARGIN,
			0.0, rng)
		for i in poses.size():
			check_near(poses[i].origin.x, expected[i], 1e-4, "ghost %d is pinned to its midpoint" % i)
			check_near(poses[i].origin.z, 0.0, 1e-4, "ghost %d sits on the line" % i)
