class_name HitboxTest
extends TestCase

## [Hitbox]: the segment-to-segment distance every car-versus-car test is built on, the capsule that
## test stands for, and the sweep that carries a capsule through one frame of travel.
##
## Here for ClockPickupTest's reason — this geometry fails quietly. A capsule half a metre too wide
## does not crash; it takes the driver out on air beside a hazard, which reads as the game being
## unfair. The cases below are all closed-form, so every expected number is arithmetic rather than
## a value read back off a previous run.

## A kart-sized car, from Hitbox.MODEL_LENGTH/MODEL_WIDTH under the kart's own chassis scale.
const HALF_LENGTH: float = 0.79375
const HALF_WIDTH: float = 0.495


func suite_name() -> String:
	return "HitboxTest"


func _distance(a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3) -> float:
	return sqrt(Hitbox.segments_distance_squared(a0, a1, b0, b1))


func test_crossing_segments_are_touching() -> void:
	check_near(_distance(
		Vector3(-1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0),
		Vector3(0.0, 0.0, -1.0), Vector3(0.0, 0.0, 1.0)), 0.0, 0.0001,
		"two segments crossing at the origin are zero apart")


func test_parallel_segments_measure_across_the_gap() -> void:
	# The denominator is zero here, which is the branch a naive solve divides by.
	check_near(_distance(
		Vector3(-5.0, 0.0, 0.0), Vector3(5.0, 0.0, 0.0),
		Vector3(-5.0, 0.0, 3.0), Vector3(5.0, 0.0, 3.0)), 3.0, 0.0001,
		"two parallel segments are their perpendicular separation apart")

	# Parallel and disjoint along their own direction: the answer is now end-to-end, not
	# perpendicular, and pinning only one parameter would return the perpendicular 3.0.
	check_near(_distance(
		Vector3(-5.0, 0.0, 0.0), Vector3(-1.0, 0.0, 0.0),
		Vector3(3.0, 0.0, 3.0), Vector3(7.0, 0.0, 3.0)), 5.0, 0.0001,
		"...and end to end once they no longer overlap along their length")


func test_the_ends_are_ends_and_not_an_infinite_line() -> void:
	# The off-by-infinity an unclamped solve gets wrong: these two lines intersect, the segments
	# do not.
	check_near(_distance(
		Vector3(0.0, 0.0, -10.0), Vector3(0.0, 0.0, -6.0),
		Vector3(-2.0, 0.0, 0.0), Vector3(2.0, 0.0, 0.0)), 6.0, 0.0001,
		"a segment stopping six metres short of another is six metres from it")


func test_a_zero_length_segment_is_a_point() -> void:
	# Both the parked kart and every round pickup arrive here, so the degenerate case is the
	# common one rather than the exotic one.
	var point := Vector3(0.0, 0.0, 2.0)
	check_near(_distance(point, point, Vector3(-3.0, 0.0, 0.0), Vector3(3.0, 0.0, 0.0)), 2.0, 0.0001,
		"a point two metres off a segment is two metres from it")
	check_near(_distance(point, point, point, point), 0.0, 0.0001,
		"and two coincident points are not a division by zero")


func test_height_is_ignored() -> void:
	# Asserted rather than left to the class doc: the vertical gap is each caller's own check, and
	# a Y term creeping in here would silently un-collect every pickup on a banked sweeper.
	check_near(_distance(
		Vector3(-1.0, 40.0, 0.0), Vector3(1.0, 40.0, 0.0),
		Vector3(0.0, -7.0, 0.0), Vector3(0.0, -7.0, 0.0)), 0.0, 0.0001,
		"forty-seven metres of height between two crossing segments changes nothing")


func test_the_measured_footprint_survives_a_mirrored_scale() -> void:
	# Every car in the project mirrors the model on X and Z to face it down the road. A negative
	# scale is not a negative car, and an unsigned read here would hand out negative half-extents
	# that make every hitbox inside out.
	var mirrored: Vector2 = Hitbox.model_half_extents(Vector3(-0.55, 0.8, -0.4))
	check_near(mirrored.x, Hitbox.MODEL_LENGTH * 0.4 * 0.5, 0.0001,
		"half the length is half the model's length under the Z scale")
	check_near(mirrored.y, Hitbox.MODEL_WIDTH * 0.55 * 0.5, 0.0001,
		"half the width is half the model's width under the X scale")


func test_the_spine_is_the_car_less_its_caps() -> void:
	check_near(Hitbox.half_spine(HALF_LENGTH, HALF_WIDTH), HALF_LENGTH - HALF_WIDTH, 0.0001,
		"the spine is shorter than the car by the radius that caps each end")
	check_near(Hitbox.half_spine(0.3, 0.9), 0.0, 0.0001,
		"a car drawn wider than it is long collapses to a circle rather than inverting")


func test_the_yaw_of_a_banked_pose_is_still_its_heading() -> void:
	# The kart's start pose on this project's road carries bank and pitch, and Euler extraction
	# would fold those into the heading the hitbox is aimed along.
	var heading: float = PI * 0.25
	var basis: Basis = Basis(Vector3.UP, heading) * Basis(Vector3(0.0, 0.0, 1.0), 0.3)
	check_near(Hitbox.yaw_of(basis), heading, 0.0001,
		"a pose rolled thirty degrees still reports the heading alone")


func _parked(yaw: float, half_length: float, half_width: float) -> Hitbox.Sweep:
	var sweep := Hitbox.Sweep.new()
	sweep.moved(Vector3.ZERO, yaw, Vector3.ZERO, yaw, half_length, half_width)
	return sweep


func test_a_capsule_is_longer_than_it_is_wide() -> void:
	# The whole point of the shape, and the one thing no sphere of any radius can do: one car, one
	# separation, a hit ahead and a miss abeam.
	var kart: Hitbox.Sweep = _parked(0.0, HALF_LENGTH, HALF_WIDTH)
	var gap: float = HALF_LENGTH + HALF_WIDTH

	check(kart.takes(Vector3(0.0, 0.0, -gap), 0.0, HALF_LENGTH, HALF_WIDTH),
		"a car that far up the road is touching, nose to nose")
	check(not kart.takes(Vector3(gap, 0.0, 0.0), 0.0, HALF_LENGTH, HALF_WIDTH),
		"the same car the same distance abeam is nowhere near, door to door")


func test_the_other_car_is_a_capsule_too() -> void:
	# Not just the kart. Both spines are real, so how much road the far car covers depends on which
	# way it is pointing — a hazard turned across the road is a shorter reach dead ahead and a
	# longer one across.
	var kart: Hitbox.Sweep = _parked(0.0, HALF_LENGTH, HALF_WIDTH)
	var nose_to_nose: float = HALF_LENGTH + HALF_LENGTH

	check(kart.takes(Vector3(0.0, 0.0, -(nose_to_nose - 0.01)), 0.0, HALF_LENGTH, HALF_WIDTH),
		"two cars end to end touch at exactly the sum of their half-lengths")
	check(not kart.takes(Vector3(0.0, 0.0, -(nose_to_nose + 0.01)), 0.0, HALF_LENGTH, HALF_WIDTH),
		"and are clear a centimetre past it")
	check(not kart.takes(Vector3(0.0, 0.0, -nose_to_nose), PI * 0.5, HALF_LENGTH, HALF_WIDTH),
		"the same car slewed across the road presents its width there instead, and is clear")


func test_a_car_passed_between_two_frames_is_still_hit() -> void:
	# What the sweep is for, at the speeds this game reaches: at 60 Hz a kart doing 40 m/s covers
	# two-thirds of a metre a frame, and a sampled test would drive the nose straight through a
	# hazard standing between the two samples.
	var narrow: float = 0.02
	var hazard := Vector3.ZERO
	var start := Vector3(0.0, 0.0, 2.0)
	var end := Vector3(0.0, 0.0, -2.0)

	var sweep := Hitbox.Sweep.new()
	sweep.moved(start, 0.0, end, 0.0, narrow, narrow)
	check(sweep.takes(hazard, 0.0, narrow, narrow),
		"a hazard between two frames' positions is taken by the travel between them")

	sweep.moved(start, 0.0, Vector3(0.0, 0.0, 1.0), 0.0, narrow, narrow)
	check(not sweep.takes(hazard, 0.0, narrow, narrow),
		"and one a metre beyond where the frame ended is not")


func test_the_pose_the_frame_began_at_counts_too() -> void:
	# Both spines bound the swept region, not only the one the frame ended on. Without the opening
	# pose a pickup the car was sitting on when the frame started, and had driven off by the end of
	# it, would be skipped — which at speed is most of them.
	var sweep := Hitbox.Sweep.new()
	sweep.moved(Vector3.ZERO, 0.0, Vector3(0.0, 0.0, -3.0), 0.0, HALF_LENGTH, HALF_WIDTH)

	check(sweep.takes(Vector3(0.0, 0.0, HALF_LENGTH - 0.05), 0.0, 0.02, 0.02),
		"a pickup under the tail where the frame opened is taken, three metres later")
