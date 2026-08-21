class_name KartModel
extends RefCounted

## The whole feel of the kart, as a pure function of input and state.
##
## The core idea: you are not steering a car, you are holding each end of it. The left stick says
## where the front is pointed; the right stick says where the rear is going. Rotation is what
## happens when the two ends disagree — yaw is never commanded here, it is solved from the geometry.
##
## Aim both ends the same way and the kart crabs. Diverge them and it spins, harder the wider the
## divergence. Steer while the rear is out and rotation cancels: the kart holds an attitude. That
## last case is the point of the scheme — "how sideways" and "how fast I'm rotating" become two
## numbers rather than one dial with two labels.
##
## Hard constraints, and the point of the boundary:
##
##   - No reference to Input, Node, Transform3D, global_position or any Godot node type.
##   - No _physics_process. It is stepped by its owner, with a caller-supplied delta.
##   - Same inputs and deltas in, same outputs out. Deterministic and headless.
##
## That is what makes "a full-lock flick at 12 m/s rotates N degrees in 0.5 s" a test rather than a
## playtest. See tests/kart_model_test.gd.

var tuning: KartTuning

# --- Driving state --------------------------------------------------------------------------
# Forward speed is the only integrated velocity here. Lateral speed is not state: it is solved
# fresh each frame from the two angles. Momentum lives in the angles, via grip latency.
var _forward_speed: float = 0.0
var _steer_angle: float = 0.0 # radians, positive = left
var _rear_slip_angle: float = 0.0 # radians, positive = left

var _frozen: bool = false
var _brake_strength: float = 0.0
# How much of the braking slip bonus is currently live, 0..1. Distinct from _brake_strength because
# it is asymmetric in time: it takes the brake's value the instant the brake is applied, and eases
# back out when it is released. See tuning.brake_slip_release_rate for why only one direction eases.
var _brake_slip_influence: float = 0.0

# The boost seam: forward speed is clamped to the tuned maximum every step, so nothing outside this
# file can push the kart past it. apply_boost is the only way in.
#
# A boost is a one-shot injection of m/s and nothing else — no duration and no envelope. What ends
# it is the kart bleeding the overspeed back down to its ceiling at _boost_bleed, so "how long the
# boost lasts" is emergent (bump / bleed) rather than a second authored number that can disagree
# with the first.
#
# _boost_credit is how much of the current overspeed a boost is still owed, and it exists to keep
# this rule off normal driving: speed above the ceiling with no credit — driving onto grass — is
# clamped hard, exactly as before, because an instant grass penalty is what makes the racing line
# worth anything. Only credited overspeed bleeds.
var _boost_bleed: float = DEFAULT_BOOST_BLEED
var _boost_credit: float = 0.0

## m/s^2 the kart sheds boost overspeed at when a pad does not name its own rate.
const DEFAULT_BOOST_BLEED: float = 3.0

# A ghost no longer boosts on contact: it banks a charge, and apply_boost only fires when the
# driver spends one. Bump/bleed are stored rather than re-derived, because the recipe a charge was
# earned with is the recipe it is spent with — a boost ghost field could vary its bump/bleed over a
# session even though today's does not, and a charge should not silently start paying out at
# whatever rate the field happens to be offering when the button is pressed rather than when the
# ghost was taken.
var _boost_charges: int = 0
var _charge_bump: float = 0.0
var _charge_bleed: float = 0.0

## Permanent top-speed gain banked so far this Run, under tuning.boost_raises_top_speed. Added
## straight onto tuning.max_speed wherever the ceiling is computed ([method _effective_top_speed]),
## rather than living as its own separate ceiling, so surface multipliers and every other consumer
## of "the kart's top speed" see the raised number without a second code path.
var _top_speed_bonus: float = 0.0

# The hop's whole state: whether a window is open, and how far into it. Two fields rather than
# folding "open" into a sign or sentinel on the elapsed time, for reset()'s reason: both go back to
# their plain zero values together.
var _hop_active: bool = false
var _hop_elapsed: float = 0.0

# Solved outputs, kept for the readouts. Not inputs to anything.
var _yaw_rate: float = 0.0
var _lateral_speed: float = 0.0
# Radians. One cap per end, recomputed every step, both shrinking with speed.
var _slip_ceiling: float = 0.0
var _steer_ceiling: float = 0.0


func _init(kart_tuning: KartTuning = null) -> void:
	tuning = kart_tuning if kart_tuning != null else KartTuning.new()
	_slip_ceiling = deg_to_rad(tuning.slip_ceiling_low_speed_degrees)
	_steer_ceiling = deg_to_rad(tuning.max_steer_angle_low_speed_degrees)


## One physics frame. `surface_multiplier` is the world's only say in the feel model: it scales
## max speed, acceleration and — the interesting one — rear grip, so grass is greasy rather than
## merely slow.
func step(input: KartInput, surface_multiplier: float, delta: float) -> KartMotion:
	_brake_strength = input.brake
	# maxf, so applying the brake is instant and only the release is eased.
	_brake_slip_influence = maxf(
		_brake_strength,
		move_toward(_brake_slip_influence, 0.0, tuning.brake_slip_release_rate * delta))

	_integrate_forward_speed(input, surface_multiplier, delta)
	_slip_ceiling = _current_slip_ceiling()
	_steer_ceiling = _current_steer_ceiling()
	_ease_axle_angles(input, surface_multiplier, delta)
	_scrub_for_angle(delta)
	_update_hop(delta)

	return _solve(delta)


# --- The solve ------------------------------------------------------------------------------
# Two points, each travelling in its own direction, on one rigid body. With u = forward speed,
# w = lateral speed at the body origin, psi = yaw rate, a/b = front/rear axle offsets, L = a + b:
#
#     front axle:  w + a*psi = u * tan(steer_angle)
#     rear axle:   w - b*psi = u * tan(rear_slip_angle)
#
#  =>  psi = u * (tan(steer) - tan(rear_slip)) / L
#      w   = u * (b*tan(steer) + a*tan(rear_slip)) / L
#
# psi depends on the DIFFERENCE between the axles: the disagreement rule, stated arithmetically.
# Three properties this is required to have:
#
#   - With rear_slip = 0 it collapses to the textbook bicycle model, so speed-dependent turn rate
#     is emergent. There is no turn-rate curve anywhere in the physics.
#   - With a large rear_slip against a small steer, the instantaneous centre of rotation sits near
#     the front axle: the rear swings around a planted nose. A single commanded slip angle cannot
#     produce this at any tuning, hence two.
#   - The axle offsets are the most expressive tuning pair here: their sum is the wheelbase, their
#     ratio the weight bias, moving the pivot fore or aft.
func _solve(delta: float) -> KartMotion:
	var motion: KartMotion = KartMotion.new()
	var wheelbase: float = tuning.wheelbase()
	if wheelbase <= 0.0:
		return motion

	var u: float = _forward_speed
	var tan_front: float = tan(_steer_angle)
	var tan_rear: float = tan(_rear_slip_angle)

	_yaw_rate = u * (tan_front - tan_rear) / wheelbase
	_lateral_speed = u * (tuning.rear_axle_offset * tan_front + tuning.front_axle_offset * tan_rear) / wheelbase

	motion.yaw_delta = _yaw_rate * delta
	motion.forward_speed = _forward_speed
	motion.lateral_speed = _lateral_speed
	return motion


# --- Longitudinal ---------------------------------------------------------------------------
# Auto-throttle: full throttle unless the brake is held, so the brake is the only longitudinal
# input, scaled by its analog strength.
#
# frozen pins speed at exactly zero rather than coasting to it: with auto-throttle there is no
# neutral, so anything short of a hard zero creeps the kart off the line during the countdown.
func _integrate_forward_speed(input: KartInput, surface_multiplier: float, delta: float) -> void:
	if _frozen:
		_forward_speed = 0.0
		return

	var effective_max: float = _effective_top_speed() * surface_multiplier
	var effective_acceleration: float = tuning.acceleration * surface_multiplier
	var throttle: float = - input.brake if input.brake > 0.01 else 1.0

	# Above the ceiling on boost credit, the kart is coasting down off a boost rather than driving.
	# The throttle is deliberately inert here — it cannot hold the overspeed up, which is what makes
	# the bleed a decay the driver watches rather than a tug-of-war they can win. The brake still
	# bites, so a boost into a corner is a real choice.
	#
	# The credit is re-clamped to the overspeed actually present, so braking off a boost spends it
	# rather than banking it for after the corner. It is also re-clamped when the CEILING drops
	# instead — driving onto grass mid-boost — which can leave overspeed above what is credited;
	# that excess is uncredited by definition and gets the instant grass clamp, not the bleed.
	#
	# Placed before the normal integration and returning, rather than correcting after it, so the
	# bleed rate is a literal m/s^2 instead of the rate net of whatever acceleration just added.
	_boost_credit = minf(_boost_credit, maxf(_forward_speed - effective_max, 0.0))
	_forward_speed = minf(_forward_speed, effective_max + _boost_credit)
	if _boost_credit > 0.0:
		if throttle < -0.01:
			_forward_speed += tuning.brake_deceleration * throttle * delta
		var shed: float = _boost_bleed * delta
		_boost_credit = maxf(0.0, _boost_credit - shed)
		_forward_speed = maxf(effective_max, _forward_speed - shed)
		return

	if throttle > 0.01:
		_forward_speed += effective_acceleration * throttle * delta
	elif throttle < -0.01:
		_forward_speed += tuning.brake_deceleration * throttle * delta
	else:
		_forward_speed = move_toward(_forward_speed, 0.0, tuning.coast_deceleration * delta)

	_forward_speed = clampf(_forward_speed, -tuning.reverse_max_speed, effective_max)


# --- Grip is latency, not force ---------------------------------------------------------------
# No tyre model, no forces, no friction coefficients, no RigidBody3D. "Grip" means one thing: how
# fast an end obeys its stick, in degrees per second. Low grip lags, and that lag is the car's
# weight and momentum. Intent registers instantly; only the body takes time.
#
# The rear angle is capped, and the cap shrinks with speed. Because the cap is an invariant, the
# kart cannot spin out: there is no loss-of-control state here, and so no recovery state and no
# camera unlock. Overcooking a corner is paid for in speed and line (see _scrub_for_angle), and the
# ceiling is felt as the angle refusing to grow.
func _ease_axle_angles(input: KartInput, surface_multiplier: float, delta: float) -> void:
	var speed_fraction: float = _speed_fraction()

	# Fades the commanded rear angle toward zero below min_slip_speed. Yaw is proportional to u, so a
	# parked kart cannot rotate anyway; this stops the angle winding up and biting on launch.
	var launch_fade: float = 1.0
	if tuning.min_slip_speed > 0.0:
		launch_fade = clampf(absf(_forward_speed) / tuning.min_slip_speed, 0.0, 1.0)

	# Both sticks are rescaled into their own ceiling rather than clipped by it, so full deflection
	# commands exactly what is available now and the whole travel stays live at every speed. The
	# trade: a stick position is a different number of degrees at 5 m/s than at 14.
	var target_steer: float = input.steer * _steer_ceiling
	var target_rear: float = input.slip * _slip_ceiling * launch_fade

	var front_rate: float = deg_to_rad(tuning.front_grip_degrees_per_second)
	var rear_rate: float = deg_to_rad(lerpf(
		tuning.rear_grip_low_speed_degrees_per_second,
		tuning.rear_grip_high_speed_degrees_per_second,
		speed_fraction)) * surface_multiplier
	# TODO: steering makes the rear answer its own stick faster, re-coupling two sticks whose
	# independence is the premise, and faking a pivot the two-axle solve produces for real.
	# tuning.steer_grip_boost = 1.0 disables it; open until a playtest decides.
	rear_rate *= lerpf(1.0, tuning.steer_grip_boost, absf(input.steer))

	# Clamped as well as eased: accelerating out of a corner shrinks the lock underneath an
	# established angle, and without the clamp the taper would only apply to new steering input.
	_steer_angle = clampf(
		move_toward(_steer_angle, target_steer, front_rate * delta),
		- _steer_ceiling, _steer_ceiling)
	# Likewise: the clamp is what makes "rear slip never exceeds the ceiling" an invariant.
	_rear_slip_angle = clampf(
		move_toward(_rear_slip_angle, target_rear, rear_rate * delta),
		- _slip_ceiling, _slip_ceiling)


# --- The economy ------------------------------------------------------------------------------
# Angle costs speed.
#
# Proportional to how much of the ceiling the rear is using, not to the raw angle: 30 degrees is
# total commitment at 14 m/s and a half-measure at 4 m/s. With no spin-out to fall into, this is the
# only cost of overcommitment, and the first thing to sharpen if the model reads as too safe.
func _scrub_for_angle(delta: float) -> void:
	if _frozen or _slip_ceiling <= 0.0:
		return
	var ceiling_usage: float = clampf(absf(_rear_slip_angle) / _slip_ceiling, 0.0, 1.0)
	_forward_speed = maxf(0.0, _forward_speed - tuning.drift_speed_scrub * ceiling_usage * delta)


# --- Hop -----------------------------------------------------------------------------------
# Counts the open window down to hop_duration and closes it there. frozen is not checked here —
# trigger_hop already refuses to open a window while frozen, and there is no way to freeze mid-hop
# in practice, so this only ever runs a window that was legitimately opened.
func _update_hop(delta: float) -> void:
	if not _hop_active:
		return
	_hop_elapsed += delta
	if _hop_elapsed >= tuning.hop_duration:
		_hop_active = false
		_hop_elapsed = 0.0


# --- Events the world does to the kart -------------------------------------------------------
# Explicit methods rather than the body reaching into private state, so the seam holds in both
# directions.

## A barrier hit. `strength` is how head-on it was: 0 = pure graze, 1 = square into the wall.
## Scrubs forward speed in proportion; past a threshold also cancels the rear angle outright,
## rather than letting a slid-along drift continue post-impact.
func apply_impact(strength: float) -> void:
	var impact: float = clampf(strength, 0.0, 1.0)
	if impact <= 0.0:
		return
	_forward_speed *= 1.0 - tuning.barrier_speed_scrub_strength * impact
	if impact >= tuning.barrier_drift_cancel_threshold:
		_rear_slip_angle = 0.0


## Puts `bump` m/s straight into forward speed, above the tuned ceiling, and sets the rate the
## overspeed then bleeds back down at. Nothing here has a duration: how long the boost is felt for
## is `bump / bleed`, and it shortens by itself if the driver brakes it away.
##
## Tops the overspeed UP TO the pad's own bump rather than adding to what is already there, so a
## pad is a ceiling on how far above top speed it can put you and chained pads refresh the boost
## instead of compounding it. Stacking reads fine for two pads and turns a pad run into a runaway.
##
## Never reduces: taking a weak pad while carrying a strong boost leaves the strong one alone, so no
## pad is ever a thing to swerve around.
func apply_boost(bump: float, bleed: float) -> void:
	if bump <= 0.0:
		return
	var gain: float = maxf(bump - _boost_credit, 0.0)
	if gain <= 0.0:
		# A pad that grants nothing changes nothing. Without this, a weak pad with a slow bleed taken
		# during a strong fast-bleeding boost would hand the strong boost the slow rate and stretch
		# it — chaining by the back door, which is the thing the cap above exists to stop.
		return
	_forward_speed += gain
	_boost_credit += gain
	_boost_bleed = bleed if bleed > 0.0 else DEFAULT_BOOST_BLEED


## A hazard ghost hit: scrubs forward speed by `multiplier`, the same shape as [method apply_impact]
## but driven by the hazard field's own swept test rather than a barrier collision. Instant and
## one-shot, for apply_impact's reason: no duration and no envelope, so nothing here can disagree
## with the speed a repeated hit would scrub next.
func apply_hazard_slow(multiplier: float) -> void:
	var scrub: float = clampf(multiplier, 0.0, 1.0)
	if scrub <= 0.0:
		return
	_forward_speed *= 1.0 - scrub


## Banks one boost charge, taken from a ghost but not yet spent. Stores the bump/bleed it was
## earned with, overwriting whatever an earlier charge stored: every ghost on today's field is
## worth the same (BoostGhostField's finding), so there is one recipe live at a time rather than a
## queue of them, and the newest ghost taken is the one that sets it.
##
## With tuning.store_boost_charges false, there is nothing to bank: the ghost's grant fires
## straight through to apply_boost, the pad's own behaviour, and boost_charges stays 0 for the
## life of the run.
##
## With tuning.boost_raises_top_speed true, neither of those happens: the ghost never charges and
## never fires an instant boost, it just raises _top_speed_bonus by tuning.top_speed_bump — checked
## first, so it overrides store_boost_charges rather than the two stacking.
func add_boost_charge(bump: float, bleed: float) -> void:
	if bump <= 0.0:
		return
	if tuning.boost_raises_top_speed:
		_top_speed_bonus += tuning.top_speed_bump
		return
	if not tuning.store_boost_charges:
		apply_boost(bump, bleed)
		return
	_boost_charges += 1
	_charge_bump = bump
	_charge_bleed = bleed


## Spends one banked charge as an ordinary boost, on the driver's own timing rather than the
## ghost's. False and a no-op with nothing banked, so the caller can fire this on every press of
## the button without first checking [member boost_charges].
func consume_boost_charge() -> bool:
	if _boost_charges <= 0:
		return false
	_boost_charges -= 1
	apply_boost(_charge_bump, _charge_bleed)
	return true


## Opens the hop's immunity window, on the driver's own timing, off the right trigger. A no-op
## while frozen (nothing to dodge during the countdown) or mid-hop — the button doesn't re-arm or
## extend an already-open window, so mashing it cannot chain immunity.
func trigger_hop() -> void:
	if _frozen or _hop_active:
		return
	_hop_active = true
	_hop_elapsed = 0.0


## Takes the driver's hands away. A driver-input concept, not a lap concept: the model names no lap
## phase and holds no director reference. The step still runs while frozen; it suppresses
## throttle/brake/steer/slip and pins forward speed at zero, which pins yaw and lateral speed at
## zero too, every term in the solve being proportional to u.
func freeze(value: bool) -> void:
	_frozen = value


## Clears every scrap of motion and drift state. Called by the body's reset_to().
func reset() -> void:
	_forward_speed = 0.0
	_steer_angle = 0.0
	_rear_slip_angle = 0.0
	_brake_strength = 0.0
	_brake_slip_influence = 0.0
	_yaw_rate = 0.0
	_lateral_speed = 0.0
	_slip_ceiling = deg_to_rad(tuning.slip_ceiling_low_speed_degrees)
	_steer_ceiling = deg_to_rad(tuning.max_steer_angle_low_speed_degrees)
	_boost_credit = 0.0
	_boost_bleed = DEFAULT_BOOST_BLEED
	_boost_charges = 0
	_charge_bump = 0.0
	_charge_bleed = 0.0
	_top_speed_bonus = 0.0
	_hop_active = false
	_hop_elapsed = 0.0


## Fills a caller-owned KartState. The view gets a copy of the numbers and no handle on the model.
func snapshot_into(state: KartState) -> void:
	state.speed = speed
	state.max_speed = _effective_top_speed()
	state.rear_slip_degrees = rear_slip_degrees
	state.rear_slip_fraction = rear_slip_fraction
	state.steer_fraction = steer_fraction
	state.front_axle_offset = tuning.front_axle_offset
	state.rear_axle_offset = tuning.rear_axle_offset
	state.body_slip_degrees = body_slip_degrees
	state.is_drifting = is_drifting
	state.drift_side = drift_side
	state.brake_strength = _brake_strength
	state.frozen = _frozen
	state.overspeed = overspeed
	state.boost_charges = _boost_charges
	state.hop_fraction = hop_fraction
	state.hop_height = tuning.hop_height


# --- Readouts ---------------------------------------------------------------------------------
# GDScript has no `private set`, so the read-only surface is getters over the backing vars above.

## Absolute forward speed.
var speed: float:
	get: return absf(_forward_speed)

## Rear slip angle in degrees, positive = left: how far the rear is out, and what every drift
## and cosmetic predicate reads.
var rear_slip_degrees: float:
	get: return rad_to_deg(_rear_slip_angle)

## |rear slip| as a fraction of today's ceiling, 0..1 — "how committed am I", speed-independent.
var rear_slip_fraction: float:
	get: return clampf(absf(_rear_slip_angle) / _slip_ceiling, 0.0, 1.0) if _slip_ceiling > 0.0 else 0.0

## Steer angle in degrees, and as a signed fraction of full lock. Positive = left.
var steer_degrees: float:
	get: return rad_to_deg(_steer_angle)

## Measured against today's lock rather than the low-speed one, so it stays "how much of the
## steering I have am I using" at every speed — the question [member rear_slip_fraction] answers for
## the other end, and what the cosmetics want for the bank.
var steer_fraction: float:
	get: return clampf(_steer_angle / _steer_ceiling, -1.0, 1.0) if _steer_ceiling > 0.0 else 0.0

## Direction the body origin travels relative to heading, in degrees: a wheelbase-weighted blend of
## the two axle angles. Derived, never an input, and not the rear slip angle — a rear held out
## against opposite steer spins the kart with very little body-level divergence.
var body_slip_degrees: float:
	get: return rad_to_deg(atan2(_lateral_speed, absf(_forward_speed))) if absf(_forward_speed) > 0.001 else 0.0

## Today's cap on the rear slip angle, in degrees. The entire safety model.
var slip_ceiling_degrees: float:
	get: return rad_to_deg(_slip_ceiling)

## Today's steering lock, in degrees. Shrinks with speed; read by tests and the debug HUD.
var steer_ceiling_degrees: float:
	get: return rad_to_deg(_steer_ceiling)

## Solved yaw rate in radians per second, positive = left. Exposed for tests and tuning; nothing
## in the game reads it, and nothing anywhere assigns it.
var yaw_rate: float:
	get: return _yaw_rate

## Solved lateral speed at the body origin, positive = left.
var lateral_speed: float:
	get: return _lateral_speed

var is_drifting: bool:
	get: return absf(rear_slip_degrees) > tuning.drift_epsilon_degrees

## +1 (left) or -1 (right); 0 when not drifting.
var drift_side: float:
	get: return signf(_rear_slip_angle) if is_drifting else 0.0

var frozen: bool:
	get: return _frozen

## tuning.max_speed plus any permanent bonus banked via boost_raises_top_speed ghosts ([method
## _effective_top_speed]). What Kart.max_speed reads for ChaseCamera's FOV fraction, so a raised
## ceiling shows up there too rather than only in how the kart actually drives.
var top_speed: float:
	get: return _effective_top_speed()

## m/s the kart is currently carrying above its ceiling on boost credit, 0.0 when not boosting. Not
## a stored "boost amount" — it is the overspeed itself, so it cannot disagree with the speed on
## screen.
var overspeed: float:
	get: return _boost_credit

## Seconds until the overspeed is gone at the current bleed rate, assuming no braking. Derived
## rather than counted down: there is no timer to drift.
var boost_remaining: float:
	get: return _boost_credit / _boost_bleed if _boost_bleed > 0.0 else 0.0

## Boost charges currently banked, waiting on a press of the boost button. Read by the HUD.
var boost_charges: int:
	get: return _boost_charges

## True for the whole open window a right-trigger press starts. What HazardGhostField reads to
## wave a swept hit through rather than applying it — the entire gameplay effect of the hop.
var is_hopping: bool:
	get: return _hop_active

## 0..1 across the open window, 0 at both ends and 1 at the midpoint — a half-sine pop-and-settle,
## not a jump's velocity-then-gravity curve, because there is no vertical velocity here to give
## one: the hop never touches forward/lateral speed or move_and_slide. Purely a cosmetic input;
## nothing here reads it back.
var hop_fraction: float:
	get:
		if not _hop_active or tuning.hop_duration <= 0.0:
			return 0.0
		return sin(clampf(_hop_elapsed / tuning.hop_duration, 0.0, 1.0) * PI)


# Speed as a 0..1 fraction of the tuned maximum. Both the ceiling and the rear grip interpolate
# against it, which is what makes the same flick a snap at 4 m/s and a long committed arc at 12.
func _speed_fraction() -> float:
	var effective_top_speed: float = _effective_top_speed()
	return clampf(absf(_forward_speed) / effective_top_speed, 0.0, 1.0) if effective_top_speed > 0.0 else 0.0


## tuning.max_speed plus whatever [member _top_speed_bonus] a boost-raises-top-speed ghost has
## banked so far this Run. The single source every consumer of "the kart's top speed" — the
## longitudinal ceiling, the speed-fraction taper, KartState.max_speed — reads through, so the
## bonus shows up everywhere top_speed already did rather than needing its own plumbing.
func _effective_top_speed() -> float:
	return tuning.max_speed + _top_speed_bonus


# A long way round at low speed, barely any swing flat out. Too steep and fast corners go numb, too
# shallow and the cap stops being felt at all.
#
# The brake raises the HIGH-SPEED END and nothing else, so the speed taper survives intact and the
# bonus is scaled by the same speed fraction as everything else: nothing at a crawl, everything flat
# out. That shape is the point. The taper exists because a fixed ceiling cannot be right across the
# range, but its cost is that the kart goes numb exactly where the driving is fastest; braking is
# the way back, paid for in the speed the brake is already taking.
#
# Two consequences worth naming. The ceiling remains a hard cap and the kart still cannot spin out —
# the driver moves the cap, never escapes it. And _scrub_for_angle bills ceiling *usage*, so the same
# held angle scrubs less under braking; the brake is already shedding speed far faster than the
# scrub, so this is a discount on a bill the driver is paying twice over.
func _current_slip_ceiling() -> float:
	var high_speed_end: float = lerpf(
		tuning.slip_ceiling_high_speed_degrees,
		tuning.slip_ceiling_high_speed_braking_degrees,
		_brake_slip_influence)
	return deg_to_rad(lerpf(
		tuning.slip_ceiling_low_speed_degrees,
		high_speed_end,
		_speed_fraction()))


# The same shape read from the front end. Yaw is proportional to u * tan(steer), so a fixed lock
# rotates the kart three or four times harder at top speed than at a crawl; the taper makes the two
# ends of the speed range tunable separately.
#
# This puts no curve in the physics: the solve reads _steer_angle and applies u*tan(steer)/L, the
# same arithmetic at 2 m/s as at 14. The taper limits the driver's authority, upstream of the model.
func _current_steer_ceiling() -> float:
	var tapered_degrees: float = lerpf(
		tuning.max_steer_angle_low_speed_degrees,
		tuning.max_steer_angle_high_speed_degrees,
		_speed_fraction())
	# Gated on is_drifting rather than eased like _brake_slip_influence is: once the tail is out the
	# bonus must not fight the rear-slip solve, and the drift threshold is already an instant flip
	# everywhere else it's read (see drift_side). Only the blend toward the bonus is eased.
	var braking_target_degrees: float = (
		tuning.max_steer_angle_braking_degrees if not is_drifting else tapered_degrees)
	return deg_to_rad(lerpf(tapered_degrees, braking_target_degrees, _brake_slip_influence))
