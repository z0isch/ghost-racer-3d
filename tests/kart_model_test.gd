class_name KartModelTest
extends TestCase

## The feel model, tested.
##
## KartModel is a pure function of input and state precisely so questions like "did that change
## make a full-lock flick at 12 m/s rotate more or less?" are answered here rather than by driving.

const DELTA: float = 1.0 / 60.0


func suite_name() -> String:
	return "KartModelTest"


func _fresh() -> KartModel:
	return KartModel.new(KartTuning.new())


# Holds one stick position for a stretch of time and returns the last frame's motion.
func _hold(model: KartModel, steer: float, slip: float, seconds: float, surface: float = 1.0) -> KartMotion:
	var input: KartInput = KartInput.new()
	input.steer = steer
	input.slip = slip
	var motion: KartMotion = KartMotion.new()
	for i: int in range(roundi(seconds / DELTA)):
		motion = model.step(input, surface, DELTA)
	return motion


# Runs the auto-throttle straight ahead until the kart is up to `target`. Bounded, so a tuning
# change can never hang the suite.
func _accelerate_to(model: KartModel, target: float) -> void:
	var input: KartInput = KartInput.new()
	for i: int in range(6000):
		if model.speed >= target:
			return
		var _motion: KartMotion = model.step(input, 1.0, DELTA)
	fail("could not reach %.1f m/s" % target)


# Where the instantaneous centre of rotation sits along the kart's own X axis, in metres ahead of
# the body origin. The point with zero lateral velocity is at x = -w / psi.
#
# The number the two-axle model exists to control, and the one a single commanded slip angle cannot
# control at any tuning: driving both w and psi from one angle puts the ICR at L / sin(beta) off to
# the side — 5.4 m at 30 degrees of slip, a wide arc with no planted point on the car.
func _icr_ahead_of_origin(model: KartModel) -> float:
	return -model.lateral_speed / model.yaw_rate


# The counter-steer row of the hands table, swept for rather than assumed: the ceiling is
# speed-dependent, so "how much opposite lock cancels this slide" is not a fixed stick position.
# Twenty-one steps, because a coarse sweep straddles the null and reports whichever side it landed
# nearer.
func _best_counter_steer(speed: float, slip: float, seconds: float) -> KartModel:
	var best: KartModel = null
	for step: int in range(21):
		# Same sign as the slip: cancelling means the two axle angles agree, which on the sticks
		# reads as turning the front into the slide.
		var steer: float = signf(slip) * (float(step) / 20.0)
		var model: KartModel = _fresh()
		_accelerate_to(model, speed)
		var _motion: KartMotion = _hold(model, steer, slip, seconds)
		if best == null or absf(model.yaw_rate) < absf(best.yaw_rate):
			best = model
	return best


# --- The acceptance target: four hands, four distinguishable motions -------------------------
# One row per test. What separates them is not the yaw sign — rows two and three both rotate left
# — but where the kart is pivoting, and whether it is pivoting at all.

func test_hands_centred_centred_goes_straight() -> void:
	var model: KartModel = _fresh()
	_accelerate_to(model, 10.0)
	var motion: KartMotion = _hold(model, 0.0, 0.0, 0.5)

	check_near(motion.yaw_delta, 0.0, 1e-6, "both ends centred must not rotate the kart")
	check_near(motion.lateral_speed, 0.0, 1e-6, "both ends centred must not slide the kart")
	check_greater(motion.forward_speed, 9.0, "and it should still be driving forward")


func test_hands_turned_centred_is_a_grip_corner() -> void:
	var model: KartModel = _fresh()
	_accelerate_to(model, 10.0)
	var motion: KartMotion = _hold(model, 1.0, 0.0, 0.5)

	check_greater(motion.yaw_delta, 0.0, "full left lock must rotate the kart left")
	# The rear axle is the planted end, so the pivot sits on it, 1.7 m behind the origin. Nothing
	# authors that: it is what the solve degenerates to when one of the two angles is zero.
	check_near(_icr_ahead_of_origin(model), -1.7, 0.01,
		"a grip corner must pivot about the rear axle — the rear follows the front around")


func test_hands_centred_out_pivots_about_the_nose() -> void:
	var model: KartModel = _fresh()
	_accelerate_to(model, 10.0)
	var motion: KartMotion = _hold(model, 0.0, -1.0, 0.5)

	check_greater(motion.yaw_delta, 0.0, "the rear breaking away right must rotate the kart left")
	# The property a single commanded angle cannot produce: the front axle is the planted end, 1.0 m
	# ahead of the origin, and the rear swings around a planted nose.
	check_near(_icr_ahead_of_origin(model), 1.0, 0.01,
		"rear out against no steer must pivot about the FRONT axle, not somewhere off to the side")


func test_hands_turned_into_the_slide_cancels_rotation() -> void:
	var pivoting: KartModel = _fresh()
	_accelerate_to(pivoting, 10.0)
	var _motion: KartMotion = _hold(pivoting, 0.0, -0.6, 0.4)

	var holding: KartModel = _best_counter_steer(10.0, -0.6, 0.4)

	# The fourth row is the reason for the scheme: in a one-stick drift game "how sideways" and "how
	# much I'm rotating" are one number. Here the rotation goes away while the angle does not.
	check_less(absf(holding.yaw_rate), 0.15,
		"counter-steer must cancel rotation: the two ends agree, so there is nothing to rotate")
	check_greater(absf(pivoting.yaw_rate), 4.0 * absf(holding.yaw_rate),
		"...and the same slide without the counter-steer must rotate far harder")
	check_greater(absf(holding.lateral_speed), 2.0,
		"...while the kart is emphatically still crabbing sideways")


func test_full_commitment_outruns_the_steering_lock() -> void:
	# Pinned because it constrains how the slip ceiling and the steering lock may be retuned against
	# each other. The ceiling at the speeds a full-commitment slide decays to is wider than the lock
	# there, so the fourth row of the hands table is not available at full right-stick: the front
	# cannot be turned far enough to match the rear, and the best available is most of the rotation
	# out, not all of it.
	#
	# The rule the two curves have to satisfy:
	#
	#     counter-steer can fully cancel a slide only where max_steer_angle >= slip_ceiling.
	#
	# The lock falls 32 -> 12 while the ceiling falls 60 -> 20, so flat out the lock is the narrower
	# of the two. To make the fourth row available there, max_steer_angle_high_speed_degrees wants to
	# sit at or above slip_ceiling_high_speed_degrees.
	var holding: KartModel = _best_counter_steer(10.0, -1.0, 0.4)

	check_greater(absf(holding.steer_fraction), 0.99,
		"the best available answer to a full-commitment slide is full opposite lock")
	check_greater(absf(holding.rear_slip_degrees), holding.steer_ceiling_degrees,
		"...because the rear is further out than the front can be pointed")
	check_greater(absf(holding.yaw_rate), 0.15, "...so some rotation survives")

	var pivoting: KartModel = _fresh()
	_accelerate_to(pivoting, 10.0)
	var _motion: KartMotion = _hold(pivoting, 0.0, -1.0, 0.4)
	# Measured at 2.01x on the tuning table as written: opposite lock takes about half the rotation
	# out at speed rather than all of it, which is the trade the steering taper buys.
	check_greater(absf(pivoting.yaw_rate), 1.9 * absf(holding.yaw_rate),
		"but it still takes most of the rotation out, so the technique reads even where it "
		+ "cannot fully cancel")


func test_the_four_rows_produce_four_distinguishable_motions() -> void:
	# The acceptance criterion for the scheme: 40 degrees of angle while rotating fast and 40 degrees
	# while rotating not at all have to be different techniques with different lines.
	var straight: KartModel = _fresh()
	var grip: KartModel = _fresh()
	var pivot: KartModel = _fresh()
	_accelerate_to(straight, 10.0)
	_accelerate_to(grip, 10.0)
	_accelerate_to(pivot, 10.0)

	var _a: KartMotion = _hold(straight, 0.0, 0.0, 0.4)
	var _b: KartMotion = _hold(grip, 1.0, 0.0, 0.4)
	var _c: KartMotion = _hold(pivot, 0.0, -1.0, 0.4)
	# 0.6 of right stick: see test_full_commitment_outruns_the_steering_lock for why the counter-steer
	# row is only available below full commitment.
	var counter: KartModel = _best_counter_steer(10.0, -0.6, 0.4)

	# Rotating? no, yes, yes, no.
	check_less(absf(straight.yaw_rate), 0.01, "straight does not rotate")
	check_greater(absf(grip.yaw_rate), 0.5, "a grip corner rotates")
	check_greater(absf(pivot.yaw_rate), 0.5, "a pivot rotates")
	check_less(absf(counter.yaw_rate), 0.15, "counter-steer does not rotate")

	# Sideways? no, barely, yes, yes — which is what tells the two non-rotating rows apart...
	check_less(absf(straight.lateral_speed), 0.01, "straight does not crab")
	check_greater(absf(counter.lateral_speed), 2.0, "counter-steer crabs hard")

	# ...and the two rotating rows by where the pivot sits, a whole wheelbase apart: rear axle for a
	# grip corner, front axle for a slide.
	check_near(_icr_ahead_of_origin(pivot) - _icr_ahead_of_origin(grip), grip.tuning.wheelbase(), 0.01,
		"the pivot must travel the whole wheelbase between a grip corner and a slide")


# --- Emergent properties ----------------------------------------------------------------------

func test_zero_rear_slip_collapses_to_the_bicycle_model() -> void:
	var model: KartModel = _fresh()
	_accelerate_to(model, 8.0)
	var _motion: KartMotion = _hold(model, 0.5, 0.0, 0.4)

	var expected: float = model.speed * tan(deg_to_rad(model.steer_degrees)) / model.tuning.wheelbase()
	check_near(model.yaw_rate, expected, 1e-4,
		"with the rear planted this must BE the textbook bicycle model, not an approximation of it")


func test_turn_rate_scales_with_speed_without_a_curve() -> void:
	# Speed-dependent turn rate falls out of the solve, yaw being proportional to u; there is no
	# turn-rate curve. Stated at a fixed angle rather than a fixed stick, which is the distinction the
	# lock's taper turns on: the taper changes how many degrees the stick buys and never touches the
	# solve. Scaling yaw_rate instead would reinvent a curve, and the ratio below would stop being 1.
	var slow: KartModel = _fresh()
	var fast: KartModel = _fresh()
	_accelerate_to(slow, 5.0)
	_accelerate_to(fast, 10.0)
	var _a: KartMotion = _hold(slow, 1.0, 0.0, 0.2)
	var _b: KartMotion = _hold(fast, 1.0, 0.0, 0.2)

	var slow_per_tan: float = slow.yaw_rate / (slow.speed * tan(deg_to_rad(slow.steer_degrees)))
	var fast_per_tan: float = fast.yaw_rate / (fast.speed * tan(deg_to_rad(fast.steer_degrees)))
	check_near(fast_per_tan / slow_per_tan, 1.0, 0.001,
		"yaw rate must be u*tan(steer)/L at every speed, with no turn-rate curve involved")

	# The taper flattens the growth without inverting it: a fast corner rotating less than the same
	# stick at half the speed would read as the steering giving up.
	check_greater(absf(fast.yaw_rate), absf(slow.yaw_rate),
		"...so more speed on the same stick must still be more rotation, taper and all")


func test_the_steering_lock_shrinks_with_speed() -> void:
	# The front's answer to the rear's slip ceiling: yaw is proportional to u*tan(steer), so one lock
	# across the range is either numb at parking speed or uncontrollable flat out.
	var slow: KartModel = _fresh()
	var fast: KartModel = _fresh()
	_accelerate_to(slow, 3.0)
	_accelerate_to(fast, 13.0)

	check_greater(slow.steer_ceiling_degrees, 26.0, "most of the lock available at a crawl")
	check_less(fast.steer_ceiling_degrees, 16.0, "and materially less of it flat out")

	# Rescaled into the lock, not clipped by it, so the whole travel of the stick stays live at every
	# speed. Same contract as the rear stick.
	for target: float in [4.0, 9.0, 13.0]:
		var model: KartModel = _fresh()
		_accelerate_to(model, target)
		var _motion: KartMotion = _hold(model, 1.0, 0.0, 0.3)
		check_near(model.steer_fraction, 1.0, 0.02,
			"full deflection must reach the lock from %.0f m/s" % target)


func test_the_lock_tightens_under_an_angle_already_held() -> void:
	# The clamp, not the easing: the lock shrinks underneath an angle already established. Without it
	# the taper would apply only to new input, making a held stick the way to keep low-speed lock.
	var model: KartModel = _fresh()
	_accelerate_to(model, 3.0)
	var _turned_in: KartMotion = _hold(model, 1.0, 0.0, 0.3)
	var lock_at_low_speed: float = absf(model.steer_degrees)

	var _accelerating: KartMotion = _hold(model, 1.0, 0.0, 3.0)

	check_less(absf(model.steer_degrees), lock_at_low_speed - 5.0,
		"holding the stick through the acceleration must not preserve the low-speed lock")
	check_near(absf(model.steer_degrees), model.steer_ceiling_degrees, 0.01,
		"...it must sit exactly on today's lock")


func test_the_slip_ceiling_shrinks_with_speed() -> void:
	var slow: KartModel = _fresh()
	var fast: KartModel = _fresh()
	_accelerate_to(slow, 3.0)
	_accelerate_to(fast, 13.0)

	check_greater(slow.slip_ceiling_degrees, 45.0, "a long way round at low speed")
	check_less(fast.slip_ceiling_degrees, 26.0, "barely any swing flat out")


# One frame with the brake buried, from a matched speed, so the ceiling is read before the
# deceleration has moved the speed fraction the ceiling is interpolated on.
func _ceiling_after_one_frame(speed: float, brake: float) -> float:
	var model: KartModel = _fresh()
	_accelerate_to(model, speed)
	var input: KartInput = KartInput.new()
	input.brake = brake
	var _motion: KartMotion = model.step(input, 1.0, DELTA)
	return model.slip_ceiling_degrees


func test_braking_buys_rotation_back_at_speed() -> void:
	# The taper's cost is that the kart goes numb exactly where the driving is fastest. The brake is
	# the way back, and it has to be worth a lot to be worth the speed it costs.
	var coasting: float = _ceiling_after_one_frame(13.0, 0.0)
	var braking: float = _ceiling_after_one_frame(13.0, 1.0)

	check_greater(braking - coasting, 15.0,
		"burying the brake at speed must open the ceiling by a technique's worth of degrees")


func test_the_braking_bonus_is_scaled_by_the_speed_taper() -> void:
	# Only the high-speed end moves, so the bonus grows with speed: nothing at a crawl, everything
	# flat out. Without this the brake would be a flat "more angle" button and the taper would stop
	# meaning anything.
	var slow_gain: float = _ceiling_after_one_frame(2.0, 1.0) - _ceiling_after_one_frame(2.0, 0.0)
	var fast_gain: float = _ceiling_after_one_frame(13.0, 1.0) - _ceiling_after_one_frame(13.0, 0.0)

	check_less(slow_gain, 5.0, "at a crawl the ceiling is already generous and the brake adds little")
	check_greater(fast_gain - slow_gain, 10.0, "the payoff must grow with speed")


func test_releasing_the_brake_does_not_straighten_the_kart_in_one_frame() -> void:
	# The ceiling is a hard clamp, so collapsing the bonus the instant the brake comes off would
	# snap an established angle straight. Only the release is eased; application stays instant.
	var model: KartModel = _fresh()
	_accelerate_to(model, 13.0)

	var input: KartInput = KartInput.new()
	input.brake = 1.0
	var _braked: KartMotion = model.step(input, 1.0, DELTA)
	var braking_ceiling: float = model.slip_ceiling_degrees

	input.brake = 0.0
	var _released: KartMotion = model.step(input, 1.0, DELTA)

	check_greater(model.slip_ceiling_degrees, braking_ceiling - 5.0,
		"one frame off the brake must not take the ceiling with it")


func test_the_kart_cannot_spin_out_while_working_the_brake() -> void:
	# The brake moves the cap; it must never let the driver escape it. Same thrash as
	# test_the_kart_cannot_spin_out, with the brake stabbed in and out against the sticks.
	var model: KartModel = _fresh()
	var input: KartInput = KartInput.new()
	var worst_ceiling_overshoot: float = 0.0
	for i: int in range(1800):
		input.steer = signf(sin(i * 0.11))
		input.slip = signf(sin(i * 0.037))
		input.brake = 1.0 if sin(i * 0.019) > 0.0 else 0.0
		var _motion: KartMotion = model.step(input, 1.0, DELTA)
		worst_ceiling_overshoot = maxf(worst_ceiling_overshoot,
			absf(model.rear_slip_degrees) - model.slip_ceiling_degrees)

	check_less(worst_ceiling_overshoot, 1e-6,
		"the rear slip angle must never exceed the ceiling, brake or no brake")


func test_full_deflection_always_commands_exactly_todays_ceiling() -> void:
	# The stick is rescaled into the ceiling, not clipped by it, so the whole travel stays live at
	# every speed. The trade is the second assertion: a stick position is a different number of
	# degrees at 6 m/s than at 12.
	var degrees_by_speed: PackedFloat32Array = PackedFloat32Array()
	for target: float in [6.0, 9.0, 12.0]:
		var model: KartModel = _fresh()
		_accelerate_to(model, target)
		var _motion: KartMotion = _hold(model, 0.0, 1.0, 0.35)
		check_near(model.rear_slip_fraction, 1.0, 0.05,
			"full deflection must reach the ceiling from %.0f m/s" % target)
		var _appended: bool = degrees_by_speed.append(model.rear_slip_degrees)

	check_greater(degrees_by_speed[0] - degrees_by_speed[2], 5.0,
		"the same full deflection must be materially fewer degrees at speed")


func test_the_kart_cannot_spin_out() -> void:
	# There is no loss-of-control state to recover from, and the ceiling has to be an invariant
	# rather than a tendency, so: thrash both sticks against each other for thirty seconds.
	var model: KartModel = _fresh()
	var input: KartInput = KartInput.new()
	var worst_ceiling_overshoot: float = 0.0
	var worst_body_overshoot: float = 0.0
	for i: int in range(1800):
		input.steer = signf(sin(i * 0.11))
		input.slip = signf(sin(i * 0.037))
		var _motion: KartMotion = model.step(input, 1.0, DELTA)

		worst_ceiling_overshoot = maxf(worst_ceiling_overshoot,
			absf(model.rear_slip_degrees) - model.slip_ceiling_degrees)
		# Heading and travel diverge by at most the larger of the two commanded angles: tan(body
		# slip) is a wheelbase-weighted average of the two axle tangents, and an average cannot
		# leave the interval. That bound is why the camera needs no spin case.
		var bound: float = maxf(model.steer_ceiling_degrees, model.slip_ceiling_degrees)
		worst_body_overshoot = maxf(worst_body_overshoot, absf(model.body_slip_degrees) - bound)

	check_less(worst_ceiling_overshoot, 1e-6, "the rear slip angle must never exceed the ceiling")
	check_less(worst_body_overshoot, 1e-6, "and travel must never leave the two commanded angles")


func test_no_standstill_pirouettes() -> void:
	var model: KartModel = _fresh()
	var _motion: KartMotion = _hold(model, 1.0, 1.0, 0.05) # from rest, both sticks buried

	# Three degrees a second, at a kart that has crawled forward a centimetre. Not zero, because
	# auto-throttle means "parked" lasts one frame; nowhere near a pirouette, because every term in
	# the solve is proportional to forward speed.
	check_less(absf(model.yaw_rate), 0.05,
		"a kart at a standstill must not rotate")
	check_less(model.rear_slip_fraction, 0.35,
		"and the commanded angle must fade toward zero below min_slip_speed rather than winding "
		+ "up while parked and then biting on launch")


# --- The economy --------------------------------------------------------------------------------

func test_angle_costs_speed_and_grip_cornering_does_not() -> void:
	var straight: KartModel = _fresh()
	var cornering: KartModel = _fresh()
	var sliding: KartModel = _fresh()
	var _a: KartMotion = _hold(straight, 0.0, 0.0, 4.0)
	var _b: KartMotion = _hold(cornering, 1.0, 0.0, 4.0)
	var _c: KartMotion = _hold(sliding, 0.0, 1.0, 4.0)

	check_near(cornering.speed, straight.speed, 0.01,
		"hard grip cornering must not understeer or cost speed — one unknown at a time")
	check_less(sliding.speed, straight.speed - 3.0,
		"the scrub is the module's only teacher, so it had better bite")


# --- The world's say ------------------------------------------------------------------------------

func test_grass_is_greasy_not_merely_slow() -> void:
	# The surface multiplier hits rear grip as well as max speed and acceleration, so on grass the
	# slide you asked for arrives later and wider than you wanted.
	var road: KartModel = _fresh()
	var grass: KartModel = _fresh()
	_accelerate_to(road, 6.0)
	_accelerate_to(grass, 6.0)
	var _a: KartMotion = _hold(road, 0.0, 1.0, 0.12, 1.0)
	var _b: KartMotion = _hold(grass, 0.0, 1.0, 0.12, grass.tuning.grass_multiplier)

	check_greater(road.rear_slip_degrees, grass.rear_slip_degrees + 2.0,
		"the same flick must take longer to arrive on grass")


func test_barrier_impact_scrubs_and_a_square_hit_cancels_everything() -> void:
	var graze: KartModel = _fresh()
	_accelerate_to(graze, 12.0)
	var speed_before: float = graze.speed
	graze.apply_impact(0.1) # a tangent graze, below barrier_drift_cancel_threshold
	check_less(graze.speed, speed_before, "even a graze costs speed")

	var square: KartModel = _fresh()
	_accelerate_to(square, 12.0)
	var _hold_slip: KartMotion = _hold(square, 0.0, 1.0, 0.5)
	var square_before: float = square.speed
	square.apply_impact(1.0)
	check_less(square.speed, 0.25 * square_before, "a square hit scrubs nearly all the speed")
	check_near(square.rear_slip_degrees, 0.0, 1e-6, "and cancels the angle")


# --- Lifecycle ---------------------------------------------------------------------------------

func test_freeze_pins_speed_yaw_and_lateral_speed_at_zero() -> void:
	var model: KartModel = _fresh()
	_accelerate_to(model, 12.0)

	model.freeze(true)
	# Sticks still buried: frozen has to hold against a driver who has not let go.
	var motion: KartMotion = _hold(model, 1.0, 1.0, 0.5)

	check_near(motion.forward_speed, 0.0, 1e-6, "speed pinned at exactly zero, not decayed to it")
	check_near(motion.yaw_delta, 0.0, 1e-6, "no yaw while frozen")
	check_near(motion.lateral_speed, 0.0, 1e-6, "no lateral drift while frozen")

	model.freeze(false)
	var after: KartMotion = _hold(model, 0.0, 0.0, 0.5)
	check_greater(after.forward_speed, 1.0, "and the auto-throttle picks straight back up on GO")


func test_reset_clears_everything() -> void:
	var model: KartModel = _fresh()
	_accelerate_to(model, 12.0)
	model.reset()

	check_near(model.speed, 0.0, 1e-6, "speed cleared")
	check_near(model.rear_slip_degrees, 0.0, 1e-6, "rear angle cleared")
	check_near(model.steer_degrees, 0.0, 1e-6, "steer angle cleared")
	check(not model.is_drifting, "not drifting")


func test_the_model_is_deterministic() -> void:
	var a: KartModel = _fresh()
	var b: KartModel = _fresh()
	var input: KartInput = KartInput.new()
	for i: int in range(600):
		input.steer = sin(i * 0.07)
		input.slip = cos(i * 0.031)
		input.brake = 0.5 if (i % 97) < 12 else 0.0
		var _ma: KartMotion = a.step(input, 1.0, DELTA)
		var _mb: KartMotion = b.step(input, 1.0, DELTA)

	check_near(a.speed, b.speed, 0.0, "same inputs and deltas, same speed, bit for bit")
	check_near(a.rear_slip_degrees, b.rear_slip_degrees, 0.0, "same rear angle")
	check_near(a.yaw_rate, b.yaw_rate, 0.0, "same yaw rate")


# --- Boost -------------------------------------------------------------------------------------
# Rules 3 and 4 of apply_boost are both invisible until someone breaks them: nothing on screen
# distinguishes "topped up" from "added" until a second pad is taken, and nothing distinguishes
# "clamped" from "bled" until a driver cuts a corner mid-boost.

func test_a_bump_lands_instantly_and_is_gone_after_bump_over_bleed_seconds() -> void:
	var model: KartModel = _fresh()
	_accelerate_to(model, model.tuning.max_speed)
	var before: float = model.speed

	model.apply_boost(7.0, 3.5)
	check_near(model.speed, before + 7.0, 1e-6, "the bump lands in the same frame it is applied")
	check_near(model.overspeed, 7.0, 1e-6, "and is read back as overspeed, not a hidden counter")

	var _during: KartMotion = _hold(model, 0.0, 0.0, 7.0 / 3.5 - 0.05)
	check_greater(model.overspeed, 0.0, "still bleeding a moment before bump / bleed seconds is up")

	var _after: KartMotion = _hold(model, 0.0, 0.0, 0.2)
	check_near(model.overspeed, 0.0, 1e-6, "and gone once bump / bleed seconds have passed")
	check_near(model.speed, model.tuning.max_speed, 0.05, "settled back on the tuned ceiling")


func test_throttle_cannot_hold_overspeed_up_and_the_brake_spends_it_faster() -> void:
	# Auto-throttle means "no input" is already full throttle; the case this guards against is that
	# full throttle's acceleration leaks into the overspeed and slows the bleed below the authored
	# rate. It must not: the bleed is exactly bump - bleed * t regardless.
	var throttled: KartModel = _fresh()
	_accelerate_to(throttled, throttled.tuning.max_speed)
	throttled.apply_boost(7.0, 2.0)
	var _t: KartMotion = _hold(throttled, 0.0, 0.0, 0.5) # full auto-throttle, no brake

	check_near(throttled.overspeed, 7.0 - 2.0 * 0.5, 1e-4,
		"under full throttle the overspeed bleeds at exactly the authored rate, no faster or slower")

	var braking: KartModel = _fresh()
	_accelerate_to(braking, braking.tuning.max_speed)
	braking.apply_boost(7.0, 2.0)
	var brake_input: KartInput = KartInput.new()
	brake_input.brake = 1.0
	for i: int in range(roundi(0.5 / DELTA)):
		var _b: KartMotion = braking.step(brake_input, 1.0, DELTA)

	check_less(braking.overspeed, throttled.overspeed, "braking spends the boost faster than the bleed alone")


func test_three_chained_pads_leave_the_same_overspeed_as_one() -> void:
	var single: KartModel = _fresh()
	_accelerate_to(single, single.tuning.max_speed)
	single.apply_boost(7.0, 2.0)

	var chained: KartModel = _fresh()
	_accelerate_to(chained, chained.tuning.max_speed)
	chained.apply_boost(7.0, 2.0)
	chained.apply_boost(7.0, 2.0)
	chained.apply_boost(7.0, 2.0)

	check_near(chained.overspeed, single.overspeed, 1e-6,
		"a pad tops the overspeed up to its own bump rather than adding to it")


func test_a_pad_taken_mid_boost_tops_up_rather_than_adding() -> void:
	var model: KartModel = _fresh()
	_accelerate_to(model, model.tuning.max_speed)
	model.apply_boost(7.0, 2.0)
	var _partial: KartMotion = _hold(model, 0.0, 0.0, 0.5) # bleeds some of it off
	var mid_overspeed: float = model.overspeed
	check_less(mid_overspeed, 7.0, "the boost must have bled down some before the second pad")

	model.apply_boost(7.0, 2.0)
	check_near(model.overspeed, 7.0, 1e-6,
		"a same-strength pad taken mid-boost tops back up to its bump, not mid_overspeed + bump")


func test_a_weak_pad_during_a_strong_boost_changes_neither_overspeed_nor_bleed() -> void:
	var model: KartModel = _fresh()
	_accelerate_to(model, model.tuning.max_speed)
	model.apply_boost(10.0, 6.0) # strong, fast-bleeding
	var overspeed_before: float = model.overspeed

	model.apply_boost(3.0, 0.5) # weak, slow-bleeding — grants nothing, since 3.0 < 10.0
	check_near(model.overspeed, overspeed_before, 1e-6, "a weaker pad leaves the overspeed alone")

	var _during: KartMotion = _hold(model, 0.0, 0.0, 0.2)
	# If the weak pad's bleed rate had been adopted, 0.2 s at 0.5 m/s^2 would barely have moved the
	# overspeed; at the strong 6.0 m/s^2 it drops by about 1.2 m/s.
	check_less(model.overspeed, overspeed_before - 0.5,
		"and the strong bleed rate must still be the one running, not the weak pad's slow one")


func test_a_ceiling_drop_mid_boost_clamps_the_uncredited_excess_instantly() -> void:
	# Driving onto grass while carrying a boost drops the ceiling out from under the credited
	# overspeed. Only the credited portion may still bleed; the newly-uncredited excess above it
	# is exactly the grass case rule_4 protects and must clamp in the same frame, not decay.
	var model: KartModel = _fresh()
	_accelerate_to(model, model.tuning.max_speed)
	model.apply_boost(7.0, 2.0) # credit = 7, speed = max_speed + 7

	var grass_ceiling: float = model.tuning.max_speed * model.tuning.grass_multiplier
	var expected_cap: float = grass_ceiling + 7.0
	var input: KartInput = KartInput.new()
	var _motion: KartMotion = model.step(input, model.tuning.grass_multiplier, DELTA)

	check(model.speed <= expected_cap + 1e-4,
		"speed must not exceed the new ceiling plus the still-credited overspeed")
	check_near(model.overspeed, 7.0, 0.5,
		"the credited 7 m/s of boost is untouched by the ceiling drop itself")


func test_the_first_grass_frame_with_no_boost_still_clamps_instantly() -> void:
	var model: KartModel = _fresh()
	_accelerate_to(model, model.tuning.max_speed)

	var input: KartInput = KartInput.new()
	var _motion: KartMotion = model.step(input, model.tuning.grass_multiplier, DELTA)

	check_near(model.speed, model.tuning.max_speed * model.tuning.grass_multiplier, 1e-6,
		"uncredited overspeed — driving onto grass — clamps hard and instantly, not gradually")
	check_near(model.overspeed, 0.0, 1e-6, "no boost credit was ever granted")


# --- Regression tripwire --------------------------------------------------------------------------

func test_full_lock_flick_at_12_ms_rotates_within_the_tuned_band() -> void:
	# The band below is a tripwire, not a specification: it exists to fail when the feel changes, so
	# re-pinning it is a deliberate act with a tuning change attached. Widening it to turn a red
	# build green defeats the point.
	var model: KartModel = _fresh()
	_accelerate_to(model, 12.0)

	var input: KartInput = KartInput.new()
	input.slip = -1.0
	var heading: float = 0.0
	for i: int in range(roundi(0.5 / DELTA)):
		heading += model.step(input, 1.0, DELTA).yaw_delta

	# Measured at 43.8 degrees on the tuning table as written, banded at roughly +/- 15%.
	var degrees: float = absf(rad_to_deg(heading))
	check_greater(degrees, 37.0, "a full-lock flick at 12 m/s should commit properly")
	check_less(degrees, 51.0, "...but nowhere near spinning the kart round")
