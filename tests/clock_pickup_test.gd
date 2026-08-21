class_name ClockPickupTest
extends TestCase

## The swept pickup test: ClockField.segment_takes_clock, and nothing else.
##
## This suite exists because the geometry is a quiet failure: a mis-projected axis or an unclamped
## parameter does not crash, it merely makes clocks slightly harder to collect, which reads as bad
## driving. The promotion rule fails loudly by comparison, and is not tested here.
##
## Every case is called statically, with no ClockField instance: a TestCase is a RefCounted that
## must not touch the scene tree. If a test in here ever needs a node, the fix belongs in
## clock_field.gd.

## The shipped pickup radius, hard-coded rather than read from a ClockField, so retuning the export
## moves the game's feel without moving what this file claims about the maths.
const RADIUS: float = 1.2

## A generously fast frame-to-frame travel distance, chosen larger than the narrow radius below
## so the clock sits meaningfully between two sampled positions — which is why this test is swept
## and not sampled.
const FRAME_AT_TOP_SPEED: float = 0.5


func suite_name() -> String:
	return "ClockPickupTest"


func _takes(start: Vector3, end: Vector3, clock: Vector3, radius: float = RADIUS) -> bool:
	return ClockField.segment_takes_clock(start, end, clock, radius)


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
