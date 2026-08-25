class_name ClockPickupTest
extends TestCase

## The swept pickup test as a CLOCK sees it: a round pickup of a tuned radius, against the kart's
## own swept hitbox. The geometry underneath is [Hitbox]'s and is tested on its own terms in
## HitboxTest; what this file owns is what a clock is, and how much of the kart may take one.
##
## This suite exists because the geometry is a quiet failure: a mis-projected axis or an unclamped
## parameter does not crash, it merely makes clocks slightly harder to collect, which reads as bad
## driving. The promotion rule fails loudly by comparison, and is not tested here.
##
## Nothing here touches a ClockField instance: a TestCase is a RefCounted that must not touch the
## scene tree. If a test in here ever needs a node, the fix belongs in clock_field.gd.

## The shipped pickup radius, hard-coded rather than read from a ClockField, so retuning the export
## moves the game's feel without moving what this file claims about the maths.
const RADIUS: float = 1.2

## A generously fast frame-to-frame travel distance, chosen larger than the narrow radius below
## so the clock sits meaningfully between two sampled positions — which is why this test is swept
## and not sampled.
const FRAME_AT_TOP_SPEED: float = 0.5


func suite_name() -> String:
	return "ClockPickupTest"


## The kart's own hitbox, as scenes/kart.tscn authors it: the SportsCar's measured footprint under
## the chassis' scale. Hard-coded for RADIUS's reason.
const KART_HALF_LENGTH: float = 0.79375
const KART_HALF_WIDTH: float = 0.495


## A point-sized kart, which is what every case below the drift ones is written against: with both
## extents zero the kart's capsule collapses to its centre and the sweep is exactly the segment-
## versus-circle test, so those assertions stay about the clock's own radius and nothing else.
func _takes(start: Vector3, end: Vector3, clock: Vector3, radius: float = RADIUS) -> bool:
	return _swept(start, end, 0.0, 0.0, 0.0).takes(clock, 0.0, radius, radius)


func _swept(
	start: Vector3, end: Vector3, yaw: float, half_length: float, half_width: float
) -> Hitbox.Sweep:
	var sweep := Hitbox.Sweep.new()
	sweep.moved(start, yaw, end, yaw, half_length, half_width)
	return sweep


func test_a_segment_through_the_clock_takes_it() -> void:
	check(_takes(Vector3(0.0, 0.0, -2.0), Vector3(0.0, 0.0, 2.0), Vector3.ZERO),
		"a segment straight through the centre collects")
	check(_takes(Vector3(-3.0, 0.0, -3.0), Vector3(3.0, 0.0, 3.0), Vector3(0.5, 0.0, 0.5)),
		"...and so does one crossing it diagonally, off-axis")


func test_the_radius_is_a_boundary_in_both_directions() -> void:
	# Both sides, so a sign flip or a stray radius*radius cannot pass by being uniformly generous.
	var start := Vector3(-5.0, 0.0, 0.0)
	var end := Vector3(5.0, 0.0, 0.0)

	check(_takes(start, end, Vector3(0.0, 0.0, RADIUS - 0.01)),
		"a pass just inside the pickup radius collects")
	check(not _takes(start, end, Vector3(0.0, 0.0, RADIUS + 0.01)),
		"and one just outside it does not")


func test_a_segment_that_ends_short_is_not_a_pickup() -> void:
	# The off-by-one an infinite-line distance gets wrong: without the clamp to [0, 1] this collects
	# a clock two metres in front of the bonnet.
	check(not _takes(Vector3(0.0, 0.0, -10.0), Vector3(0.0, 0.0, -3.0), Vector3.ZERO),
		"stopping three metres short of a clock does not collect it")


func test_a_segment_that_starts_past_it_is_not_a_pickup() -> void:
	# The same error in the other direction: an unclamped projection would hand over a clock already
	# driven past, on every subsequent frame of the straight.
	check(not _takes(Vector3(0.0, 0.0, 3.0), Vector3(0.0, 0.0, 10.0), Vector3.ZERO),
		"a segment beginning three metres beyond a clock does not collect it")


func test_a_clock_between_two_frames_is_still_taken() -> void:
	# The case the swept approach exists for. Radius shrunk to 0.2 m so the clock fits between two
	# consecutive fast-travel positions: each endpoint is 0.25 m away, so a sampled test misses.
	var start := Vector3(0.0, 0.0, -FRAME_AT_TOP_SPEED * 0.5)
	var end := Vector3(0.0, 0.0, FRAME_AT_TOP_SPEED * 0.5)
	var narrow: float = 0.2

	check(start.distance_to(Vector3.ZERO) > narrow and end.distance_to(Vector3.ZERO) > narrow,
		"the case is only meaningful if both endpoints really are clear of the clock")
	check(_takes(start, end, Vector3.ZERO, narrow),
		"a clock passed between two physics frames is still collected")

	# The shipped numbers have room to spare: at 1.2 m a 0.5 m frame cannot straddle a clock at all.
	check(_takes(start, end, Vector3.ZERO),
		"at the shipped radius the same pass is nowhere near tunnelling")


func test_vertical_separation_is_ignored_entirely() -> void:
	# Horizontal-plane only by design, asserted rather than left to a comment: it is what lets a
	# clock sit up a banked sweeper or out on a crest and stay collectable from the road it belongs
	# to.
	check(_takes(Vector3(0.0, 0.0, -2.0), Vector3(0.0, 0.0, 2.0), Vector3(0.0, 3.0, 0.0)),
		"a clock three metres overhead is collected")
	check(_takes(Vector3(0.0, 12.0, -2.0), Vector3(0.0, 12.0, 2.0), Vector3(0.0, -3.0, 0.0)),
		"...and one three metres below, from a kart on the climb")
	check(not _takes(Vector3(0.0, 0.0, -2.0), Vector3(0.0, 0.0, 2.0), Vector3(4.0, 0.0, 0.0)),
		"height buys nothing horizontally: four metres to the side is still a miss")


func test_a_stationary_kart_still_collects() -> void:
	# Zero-length segment: the kart sits still on the grid and at every abort, and dividing by a zero
	# length would be a NaN reading as "clocks near the start line don't work".
	var parked := Vector3(1.0, 0.0, 0.0)
	check(_takes(parked, parked, Vector3(1.0, 0.0, 0.5)),
		"a parked kart inside the radius collects")
	check(not _takes(parked, parked, Vector3(1.0, 0.0, 5.0)),
		"and a parked kart outside it does not, rather than collecting everything")


func test_the_whole_car_collects_a_clock_not_just_its_centre() -> void:
	# The kart is a capsule now, so a clock the bonnet reaches is taken even though the centre of
	# the car never comes within the pickup radius of it. Parked, so nothing here is the sweep's
	# doing: this is the body's own extent.
	var parked: Hitbox.Sweep = _swept(
		Vector3.ZERO, Vector3.ZERO, 0.0, KART_HALF_LENGTH, KART_HALF_WIDTH)

	# Forward is -Z, so the nose reaches KART_HALF_LENGTH ahead and the clock's own radius beyond.
	var nose_reach: float = KART_HALF_LENGTH + RADIUS
	check(parked.takes(Vector3(0.0, 0.0, -(nose_reach - 0.01)), 0.0, RADIUS, RADIUS),
		"a clock just inside the reach of the bonnet is collected by a parked kart")
	check(not parked.takes(Vector3(0.0, 0.0, -(nose_reach + 0.01)), 0.0, RADIUS, RADIUS),
		"and one just beyond it is not: the car is longer than a point, not unbounded")

	# Across the car it reaches only its own half-width, which is what makes the hitbox a capsule
	# rather than a circle as long as the car.
	check(not parked.takes(Vector3(nose_reach - 0.01, 0.0, 0.0), 0.0, RADIUS, RADIUS),
		"the same distance out to the side is a miss — the car is not as wide as it is long")


func test_the_hitbox_swings_with_the_drift_cant() -> void:
	# The confusion this shape exists to remove: with the tail hung out, what hits the car has to be
	# what the car looks like it is covering. A quarter turn is past any real slip angle, and is
	# chosen because it makes the claim unambiguous rather than marginal.
	var clock := Vector3(KART_HALF_LENGTH - 0.05, 0.0, 0.0)
	var narrow: float = 0.05

	var square: Hitbox.Sweep = _swept(
		Vector3.ZERO, Vector3.ZERO, 0.0, KART_HALF_LENGTH, KART_HALF_WIDTH)
	check(not square.takes(clock, 0.0, narrow, narrow),
		"abeam the door, just past the car's half-width, is a miss when the car points straight")

	var canted: Hitbox.Sweep = _swept(
		Vector3.ZERO, Vector3.ZERO, PI * 0.5, KART_HALF_LENGTH, KART_HALF_WIDTH)
	check(canted.takes(clock, 0.0, narrow, narrow),
		"and a hit once the car is canted to point at it — the box turned with the car")
