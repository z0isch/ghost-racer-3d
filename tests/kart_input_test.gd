class_name KartInputTest
extends TestCase

## The keyboard ramp.
##
## Tested against KartInput._ramped directly rather than through poll(), which reads Input and has
## no devices attached headless. The ramp is the whole of the interesting behaviour anyway.
##
## Worth testing because the ramp rate is the keyboard player's entire handling model: they can only
## command zero or the ceiling, so how fast they move between the two is all the expression they
## have. A live tuning target, not a constant to pick once.

const DELTA: float = 1.0 / 60.0
# 6/s rather than the tuning's 4/s, only so the durations below land on whole physics frames and the
# assertions can be exact.
const RATE: float = 6.0


func suite_name() -> String:
	return "KartInputTest"


# Steps the ramp toward a fixed raw value for a stretch of time.
func _ramp_for(start: float, raw: float, seconds: float) -> float:
	var value: float = start
	for i: int in range(roundi(seconds / DELTA)):
		value = KartInput._ramped(value, raw, RATE, DELTA)
	return value


func test_a_key_press_travels_rather_than_snapping() -> void:
	# A key gives a digital 1 the instant it goes down; without the ramp the keyboard player would
	# have exactly two slip angles available.
	var early: float = _ramp_for(0.0, 1.0, 0.05)
	check_greater(early, 0.0, "the ramp starts moving immediately")
	check_less(early, 0.5, "...but full deflection is not instant")

	check_near(_ramp_for(0.0, 1.0, 1.0 / RATE), 1.0, 1e-5,
		"and 1/rate seconds of holding the key reaches full travel exactly")


func test_a_key_release_travels_too() -> void:
	# Snapping back to centre would make every keyboard slide end in a jolt.
	var half_way: float = _ramp_for(1.0, 0.0, 0.5 / RATE)
	check_near(half_way, 0.5, 1e-5, "releasing travels back at the same rate")


func test_an_analog_stick_is_not_delayed_by_the_ramp() -> void:
	# A stick carries its own travel, so ramping it would be added latency. Anything strictly between
	# the deadzone and full deflection can only be a stick, and passes straight through.
	check_near(KartInput._ramped(0.0, 0.6, RATE, DELTA), 0.6, 1e-6,
		"a part-way stick reads through untouched, from a standing start")
	check_near(KartInput._ramped(-1.0, 0.35, RATE, DELTA), 0.35, 1e-6,
		"...and from the opposite extreme, with no history to catch up on")


func test_a_stick_slammed_to_full_lock_is_barely_delayed() -> void:
	# The case the two branches share: a stick reaching hard-over has passed through the snapping
	# band, so the ramp is only asked for the last couple of percent.
	var value: float = KartInput._ramped(0.0, 0.97, RATE, DELTA) # still analog: snaps
	check_near(value, 0.97, 1e-6, "0.97 is inside the analog band")

	value = KartInput._ramped(value, 1.0, RATE, DELTA) # now saturated: ramps
	check_greater(value, 0.99, "and the remaining travel to full lock costs one frame, not a ramp")


func test_crossing_from_one_side_to_the_other_passes_through_centre() -> void:
	# A -> D flips the raw value from -1 to +1 with nothing in between; the ramp has to walk it
	# across, or the kart teleports from full left to full right.
	var value: float = -1.0
	var seen_near_centre: bool = false
	for i: int in range(roundi(2.0 / RATE / DELTA)):
		value = KartInput._ramped(value, 1.0, RATE, DELTA)
		if absf(value) < 0.05:
			seen_near_centre = true

	check(seen_near_centre, "the ramp must pass through centre rather than jumping sides")
	check_near(value, 1.0, 1e-5, "and arrive at the far side in 2/rate seconds")


func test_the_ramp_rate_is_what_the_keyboard_player_actually_tunes() -> void:
	# Same key, same hold, two rates: strictly more travel from the faster one.
	var slow: float = 0.0
	var fast: float = 0.0
	for i: int in range(roundi(0.1 / DELTA)):
		slow = KartInput._ramped(slow, 1.0, 2.0, DELTA)
		fast = KartInput._ramped(fast, 1.0, 8.0, DELTA)

	check_greater(fast, slow * 3.0, "four times the rate, four times the travel")
	check_less(fast, 1.0, "neither has saturated yet, so the comparison is of the ramp itself")
