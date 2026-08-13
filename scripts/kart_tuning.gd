class_name KartTuning
extends Resource

## Every number the feel model runs on, in one place.
##
## A Resource rather than @export vars on Kart, for two reasons: Kart is the body, while these
## numbers belong to the model, which is a RefCounted and cannot export anything; and a test wants
## [code]KartTuning.new()[/code] — defaults, no scene, no inspector.

# --- Longitudinal ---------------------------------------------------------------------------
## Auto-throttle: full throttle unless the brake is held, so the brake is the only longitudinal
## input. No reverse — [member reverse_max_speed] is the clamp's lower bound and is 0.
@export var max_speed: float = 14.0
@export var reverse_max_speed: float = 0.0
@export var acceleration: float = 7.0
@export var brake_deceleration: float = 15.0
@export var coast_deceleration: float = 10.0

# --- Front axle -----------------------------------------------------------------------------
## The lock shrinks with speed, the same shape as the rear's slip ceiling. Yaw is proportional to
## u * tan(steer), so one lock cannot be right across the range: 32° is a tidy parking-speed turn
## and, at 14 m/s, 186 °/s. Tapering buys back a roughly flat yaw rate above half speed.
##
## A cap on the lock the driver is handed, not a scale on the rotation the solve produces — yaw
## stays u*tan(steer)/L at every speed. tests/kart_model_test.gd pins both halves of that.
@export var max_steer_angle_low_speed_degrees: float = 32.0
@export var max_steer_angle_high_speed_degrees: float = 12.0
## A degrees-per-second easing rate, not a force: how fast the steer angle moves toward what the
## left stick asks. 360 °/s is a tenth of a second to full lock.
@export var front_grip_degrees_per_second: float = 360.0

# --- Geometry -------------------------------------------------------------------------------
## The most expressive tuning pair here. Their sum is the wheelbase (smaller = faster rotation for a
## given pair of angles); their ratio is the weight bias, moving the pivot fore or aft.
@export var front_axle_offset: float = 1.0
@export var rear_axle_offset: float = 1.7

# --- Rear axle ------------------------------------------------------------------------------
## The slip ceiling is the entire safety model: a long way round at low speed, barely any swing flat
## out. The stick is rescaled into the ceiling rather than clipped by it, so full deflection always
## commands exactly today's ceiling and the whole travel of the stick stays live.
@export var slip_ceiling_low_speed_degrees: float = 60.0
@export var slip_ceiling_high_speed_degrees: float = 20.0
## The high-speed end of the ceiling while the brake is buried — the driver's way of buying rotation
## back at the speeds the taper takes it away at.
##
## Only the high-speed end moves, which is the whole design: at low speed the ceiling is already
## generous and the brake changes nothing, so the technique's payoff grows with speed and is largest
## exactly where the kart is otherwise numb. It replaces no part of the safety model — the ceiling is
## still a hard cap, just a cap the driver can raise at a price, and that price is the deceleration
## they asked for to raise it.
@export var slip_ceiling_high_speed_braking_degrees: float = 45.0
## How fast the braking bonus fades once the brake is released, in influence per second.
##
## Not symmetric with the application, which is instant: releasing the brake shrinks the ceiling, and
## the ceiling is a hard clamp, so an instant release would straighten an established angle in a
## single frame. This is the rate that snap is spread over.
@export var brake_slip_release_rate: float = 3.0
## Rear grip falls off with speed, making the same flick a snap at 4 m/s and a long committed arc
## at 12 m/s.
@export var rear_grip_low_speed_degrees_per_second: float = 360.0
@export var rear_grip_high_speed_degrees_per_second: float = 50.0
## Below this the commanded rear angle fades toward zero rather than snapping: no standstill
## pirouettes.
@export var min_slip_speed: float = 1.5
## Suspect: re-couples two sticks whose independence is the premise, and fakes a pivot-about-the-
## front that the two-axle geometry produces for real. 1.0 disables it.
@export var steer_grip_boost: float = 3.0

# --- The economy ----------------------------------------------------------------------------
## Angle costs speed. With no spin-out to fall into, the scrub is the only cost of overcommitment,
## which makes it the most important number in this table.
@export var drift_speed_scrub: float = 15.0

# --- Surfaces -------------------------------------------------------------------------------
## One multiplier per surface, applied to max speed, acceleration and rear grip. Grass is greasy,
## not merely slow: you get the slide you asked for, later and wider than you wanted.
@export var road_multiplier: float = 1.0
@export var kerb_multiplier: float = 0.8
@export var grass_multiplier: float = 0.5

# --- Barriers -------------------------------------------------------------------------------
## Impact strength is how head-on the hit was: 0 graze, 1 square into the wall.
@export var barrier_speed_scrub_strength: float = 0.8
@export var barrier_drift_cancel_threshold: float = 0.25

# --- Readouts -------------------------------------------------------------------------------
## Rear slip magnitude above which is_drifting reads true, for the camera and the cosmetics. Purely
## a reporting threshold: nothing in the physics branches on it.
@export var drift_epsilon_degrees: float = 2.0

# --- Keyboard -------------------------------------------------------------------------------
## The ramp rate is the keyboard player's entire handling model: they can only command zero or the
## ceiling, so how fast they move between the two is all the expression they have.
@export var keyboard_steer_ramp_rate: float = 6.0
@export var keyboard_slip_ramp_rate: float = 4.0


## Wheelbase. The sum of the two axle offsets, and the denominator of the whole solve.
##
## The surface multipliers above are not resolved here: which surface the kart is on is a fact about
## the world, so Kart matches its own SurfaceType and hands the model a plain float. Neither
## KartTuning nor KartModel ever names a type that lives on the body.
func wheelbase() -> float:
	return front_axle_offset + rear_axle_offset
