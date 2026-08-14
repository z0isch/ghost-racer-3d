class_name BoostGhostPlacementTest
extends TestCase

## The placement rule: BoostGhostField.place_evenly, and nothing else.
##
## Every case here is a boundary the eye cannot check from the driver's seat — a division by zero
## on a duplicate sample, an off-by-one at the margins, a yaw that spins the wrong way at pi.
##
## Every case is called statically, with no BoostGhostField instance: a TestCase is a RefCounted
## that must not touch the scene tree.

const START_MARGIN: float = 10.0
const END_MARGIN: float = 10.0


func suite_name() -> String:
	return "BoostGhostPlacementTest"


## One sample per metre along +X, yaw a constant facing +X throughout, so any test that doesn't
## care about yaw can ignore it. RefCounted rather than a two-element Array: GDScript has no tuple,
## and an untyped Array degrades both fields to Variant at every call site that unpacks it.
class Line extends RefCounted:
	var positions: PackedVector3Array
	var yaws: PackedFloat32Array


## 100 m of straight line along +X: 0, 0, 0 .. 100, 0, 0.
func _straight_line(length: int) -> Line:
	var line := Line.new()
	for i in length + 1:
		line.positions.append(Vector3(float(i), 0.0, 0.0))
		line.yaws.append(0.0)
	return line


func _place(positions: PackedVector3Array, yaws: PackedFloat32Array, count: int,
		start_margin: float = START_MARGIN, end_margin: float = END_MARGIN) -> Array[Transform3D]:
	return BoostGhostField.place_evenly(positions, yaws, count, start_margin, end_margin)


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
