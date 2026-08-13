class_name KartInput
extends RefCounted

## One frame of driver intent, and the only thing in the module that reads Input.
##
## Both a struct and its own reader. Tests construct one and set the three fields directly; Kart
## constructs one in _ready and calls poll() each physics frame. KartModel only sees the fields, so
## it cannot tell the difference, which is the point of the seam.
##
## Four actions, no more: left stick X steers, right stick X slips, one analog brake. There is no
## throttle action (auto-throttle) and no drift button — the right stick at rest is the grip state.

## Where the front of the kart is pointed, -1..1. Positive = left.
var steer: float = 0.0

## Where the rear of the kart is going, -1..1, as a fraction of today's slip ceiling rather than a
## number of degrees. Positive = left.
var slip: float = 0.0

## Brake strength, 0..1. Analog on a trigger, full-on from a key.
var brake: float = 0.0

# Ramp state for keyboard parity. A key gives a digital ±1; a stick gives travel. The ramp turns
# the former into the latter so the model sees one control scheme, never two.
var _steer_ramp: float = 0.0
var _slip_ramp: float = 0.0

# Below this an axis reads as centred, matching the 0.2 deadzone on every action in project.godot.
const _DEADZONE: float = 0.2
# How close to full deflection counts as saturated. See _ramped() for why the distinction matters.
const _SATURATED: float = 0.98


## Reads this frame's actions into the three fields and returns self, so the call site reads as
## `_model.step(_input.poll(...), ...)`.
##
## `suppressed` is the frozen case: the driver's hands are taken away, but the caller still wants
## the ramp state zeroed rather than left mid-travel, so GO doesn't inherit half a slip command.
func poll(tuning: KartTuning, delta: float, suppressed: bool) -> KartInput:
	if suppressed:
		steer = 0.0
		slip = 0.0
		brake = 0.0
		_steer_ramp = 0.0
		_slip_ramp = 0.0
		return self

	_steer_ramp = _ramped(_steer_ramp, Input.get_axis("steer_right", "steer_left"), tuning.keyboard_steer_ramp_rate, delta)
	_slip_ramp = _ramped(_slip_ramp, Input.get_axis("slip_right", "slip_left"), tuning.keyboard_slip_ramp_rate, delta)
	steer = _steer_ramp
	slip = _slip_ramp
	brake = Input.get_action_strength("brake")
	return self


## Clears the ramp state without reading Input. For reset_to, which must not leave a keyboard
## player's half-travelled axis alive across a teleport.
func clear() -> void:
	steer = 0.0
	slip = 0.0
	brake = 0.0
	_steer_ramp = 0.0
	_slip_ramp = 0.0


# The action API has no per-device query — get_axis() fuses keyboard and stick into one number — so
# the ramp infers from the value whether it is looking at travel or at a digital edge.
#
# A magnitude strictly between the deadzone and full deflection can only be a stick part-way over,
# where a ramp would be added latency on an input that already carries its own travel: snap.
# Dead centre and hard-over ramp, which covers both edges of a key press. A stick barely notices: it
# passes through the snapping band on the way out, saturating from ~0.98.
static func _ramped(current: float, raw: float, rate: float, delta: float) -> float:
	var magnitude: float = absf(raw)
	if magnitude > _DEADZONE and magnitude < _SATURATED:
		return raw
	return move_toward(current, raw, rate * delta)
