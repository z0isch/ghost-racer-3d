class_name KartCosmetics
extends Node3D

## The kart's view. Owns the Chassis child — the mesh and the two smoke emitters both hang off it —
## reads a read-only KartState snapshot, and holds no reference back to the model or the body.
##
## "Cosmetics never write physics" is structural rather than a rule held up by care: there is
## nothing to write back to. update_view() takes a snapshot by value and this node cannot reach the
## kart at all.
##
## Bank, chassis yaw and smoke density are continuous functions of rear-slip magnitude, so the
## whole cosmetic layer follows the slide rather than snapping between two states.
##
## The yaw is a rotation about the front axle, by the rear's actual solved angle: the tail swings
## and the nose stays put, matching the picture the two-axle solve produces.

## Visual roll at full lock / full slip.
@export var bank_angle_max_degrees: float = 5.0
## Degrees per second the visual bank may change by.
@export var bank_smoothing: float = 13.0
## How much harder a slide leans than a grip corner at the same fraction.
@export var drift_bank_strength: float = 1.4
## Multiplier on the rear's solved angle; 1.0 shows exactly what the model solved.
@export var drift_yaw_strength: float = 1.0
## Degrees per second the visual yaw cant may change by.
@export var yaw_smoothing: float = 360.0

## Fractional Y-scale dip on landing; XZ widens to compensate.
@export var squash_amount: float = 0.25
## Fractional Y-scale stretch on leaving the ground.
@export var stretch_amount: float = 0.15
@export var squash_recovery_speed: float = 6.0

## Emission ratio the instant the tyres start scrubbing at all.
@export var smoke_min_ratio: float = 0.4
## Forward speed the brake must be scrubbing off before it smokes: below this it is a gentle stop,
## not a lock-up.
@export var brake_smoke_min_speed: float = 4.0
@export var smoke_color: Color = Color(196.0 / 255.0, 196.0 / 255.0, 196.0 / 255.0, 0.3)

## Low-frequency motor magnitude at full slip.
@export var drift_vibration_weak: float = 0.05
## High-frequency motor magnitude at full slip.
@export var drift_vibration_strong: float = 0.15

## Overspeed at which the boost flames reach full size/density. Matches BoostPadField's default
## bump, so a fresh pad reads as a full flame rather than a partial one.
@export var boost_flame_max_overspeed: float = 10.0
## Emission ratio the instant any overspeed is present, so the flame snaps visible rather than
## fading in from nothing.
@export var boost_flame_min_ratio: float = 0.5

## How far the nose lifts at the peak of a boost wheelie.
@export var wheelie_angle_max_degrees: float = 10.0
## Seconds to snap up to the peak angle. Short: this is a pop, not a climb.
@export var wheelie_rise_time: float = 0.3
## Seconds to drop back to level once at the peak. Short and accelerating: a slam, not a settle.
@export var wheelie_slam_time: float = 0.5

var _bank_degrees: float = 0.0
var _yaw_degrees: float = 0.0
var _squash_impulse: float = 0.0 # >0 stretched, <0 squashed; decays to 0
var _was_grounded: bool = true

enum _WheeliePhase {INACTIVE, RISING, SLAMMING}

var _prev_overspeed: float = 0.0
var _wheelie_phase: int = _WheeliePhase.INACTIVE
var _wheelie_slam_elapsed: float = 0.0
var _wheelie_pitch_degrees: float = 0.0

var _smoke_material_left: ParticleProcessMaterial
var _smoke_material_right: ParticleProcessMaterial

# Chassis carries the pose (yaw and bank) and everything bolted to the car. Visual carries the
# squash alone, one level down, because a GPUParticles3D reads its own scale into emission shape and
# initial velocity: inheriting the squash would puff the smoke on every landing.
@onready var _chassis: Node3D = $Chassis
@onready var _visual: Node3D = $Chassis/Visual
@onready var _smoke_left: GPUParticles3D = $Chassis/DriftSmokeLeft
@onready var _smoke_right: GPUParticles3D = $Chassis/DriftSmokeRight
@onready var _boost_flame_left: GPUParticles3D = $Chassis/BoostFlameLeft
@onready var _boost_flame_right: GPUParticles3D = $Chassis/BoostFlameRight


func _ready() -> void:
	_smoke_material_left = _smoke_left.process_material as ParticleProcessMaterial
	_smoke_material_right = _smoke_right.process_material as ParticleProcessMaterial


## One frame of view, driven entirely by the snapshot. Called by Kart at the end of its physics
## step, after move_and_slide, so it is reading settled state rather than mid-frame state.
func update_view(state: KartState, delta: float) -> void:
	_update_lean(state, delta)
	_update_squash(state, delta)
	_update_smoke(state)
	_update_boost_flames(state)
	_update_wheelie(state, delta)
	_update_vibration(state)


## Back to neutral, for the body's reset_to().
func reset() -> void:
	_bank_degrees = 0.0
	_yaw_degrees = 0.0
	_squash_impulse = 0.0
	_was_grounded = true
	_prev_overspeed = 0.0
	_wheelie_phase = _WheeliePhase.INACTIVE
	_wheelie_slam_elapsed = 0.0
	_wheelie_pitch_degrees = 0.0
	_chassis.rotation = Vector3.ZERO
	_chassis.position = Vector3.ZERO
	_visual.scale = Vector3.ONE
	# restart() clears world-space particles left at the pre-teleport position, and re-enables
	# emitting, hence the _set_smoke(false) below.
	_smoke_left.restart()
	_smoke_right.restart()
	_set_smoke(false, 0.0)
	_set_smoke_color(smoke_color)
	_boost_flame_left.restart()
	_boost_flame_right.restart()
	_set_boost_flames(false, 0.0)
	_stop_vibration()


# Two lean sources, added rather than switched between, so nothing here reads an on/off drift flag.
# A grip corner banks with the front axle; a slide banks with the rear, and harder.
#
# Rear slip is positive to the LEFT, so a left-hand slide carries a negative rear fraction and the
# term is subtracted. Both terms then push the same way through a normal drift, hardest under
# counter-steer. A pure crab cancels the bank to level, since nothing is rotating; the yaw is
# rear-only and still shows a pose through a crab.
func _update_lean(state: KartState, delta: float) -> void:
	# Signed off rear_slip_degrees, not state.drift_side, which is epsilon-gated and would step.
	var rear: float = signf(state.rear_slip_degrees) * state.rear_slip_fraction
	var lean: float = clampf(state.steer_fraction - rear * drift_bank_strength, -1.0, 1.0)
	var target_bank: float = 0.0 if state.frozen else lean * bank_angle_max_degrees
	# The rear's real angle, not a fraction scaled into a cosmetic cap, so retuning the slip ceiling
	# is visible without a matching cosmetic knob. Negated: rear slip is positive to the left while
	# a positive yaw turns the nose left, and it is the tail that follows the rear.
	var target_yaw: float = 0.0 if state.frozen else -state.rear_slip_degrees * drift_yaw_strength

	_bank_degrees = move_toward(_bank_degrees, target_bank, bank_smoothing * delta)
	_yaw_degrees = move_toward(_yaw_degrees, target_yaw, yaw_smoothing * delta)
	_chassis.rotation = Vector3(0.0, deg_to_rad(_yaw_degrees), deg_to_rad(_bank_degrees))
	_chassis.position = _pivot_correction(state.front_axle_offset, deg_to_rad(_yaw_degrees))


# Node3D spins about its own origin, the body centre, which would swing the nose out as far as the
# tail. `p - R*p` is the translation that puts point p back where it started after the rotation, and
# the node transform applies it after the spin (T * R * S), making the yaw a rotation about the
# front axle instead. Forward is -Z, so the axle sits at -front_axle_offset.
#
# Cosmetic only: no collider, ray or barrier contact moves with it. Bank is excluded, staying a roll
# about the chassis' long axis; the difference is millimetre-scale at a ten-degree lean.
func _pivot_correction(front_axle_offset: float, yaw: float) -> Vector3:
	var pivot: Vector3 = Vector3(0.0, 0.0, -front_axle_offset)
	return pivot - Basis(Vector3.UP, yaw) * pivot


# Any overspeed increase — the initial pickup, or a fresh pad landing on top of a boost already in
# progress — kicks (or re-kicks) the nose into RISING. Re-triggering mid-slam does not reset to 0
# first: RISING approaches wheelie_angle_max_degrees at a constant rate from wherever the pitch
# currently sits, so a re-boost reads as the nose catching a second wind, not a stutter. Not tied
# to overspeed's magnitude or decay — bleed is gradual and would never read as a pop — just onset.
#
# Runs after _update_lean, which overwrites rotation/position outright, so this only ever adds a
# pitch component and an additional pivot offset on top of whatever the lean pass produced.
func _update_wheelie(state: KartState, delta: float) -> void:
	var boost_started: bool = not state.frozen and state.overspeed > _prev_overspeed
	_prev_overspeed = state.overspeed

	if state.frozen:
		_wheelie_phase = _WheeliePhase.INACTIVE
		_wheelie_pitch_degrees = 0.0
	else:
		if boost_started:
			_wheelie_phase = _WheeliePhase.RISING

		match _wheelie_phase:
			_WheeliePhase.RISING:
				var rise_speed: float = wheelie_angle_max_degrees / maxf(wheelie_rise_time, 0.001)
				_wheelie_pitch_degrees = move_toward(_wheelie_pitch_degrees, wheelie_angle_max_degrees, rise_speed * delta)
				if _wheelie_pitch_degrees >= wheelie_angle_max_degrees:
					_wheelie_phase = _WheeliePhase.SLAMMING
					_wheelie_slam_elapsed = 0.0
			_WheeliePhase.SLAMMING:
				_wheelie_slam_elapsed += delta
				# Cubic ease-in: slow to leave the peak, accelerating into the slam.
				var t: float = clampf(_wheelie_slam_elapsed / wheelie_slam_time, 0.0, 1.0)
				_wheelie_pitch_degrees = wheelie_angle_max_degrees * (1.0 - t * t * t)
				if t >= 1.0:
					_wheelie_phase = _WheeliePhase.INACTIVE
					_wheelie_pitch_degrees = 0.0
			_WheeliePhase.INACTIVE:
				_wheelie_pitch_degrees = 0.0

	if _wheelie_pitch_degrees == 0.0:
		return
	var pitch: float = deg_to_rad(_wheelie_pitch_degrees)
	_chassis.rotation.x = pitch
	_chassis.position += _rear_pivot_correction(state.rear_axle_offset, pitch)


# Same trick as _pivot_correction, hinged on the rear axle instead of the front: the nose swings
# up while the rear tyres' contact point stays put, rather than the whole chassis rising from its
# centre. Forward is -Z, so the rear sits at +rear_axle_offset.
func _rear_pivot_correction(rear_axle_offset: float, pitch: float) -> Vector3:
	var pivot: Vector3 = Vector3(0.0, 0.0, rear_axle_offset)
	return pivot - Basis(Vector3.RIGHT, pitch) * pivot


# Roughly volume-preserving: a negative impulse dips Y and widens XZ, a positive one the opposite.
#
# A teleport drops the kart onto the road, which reads as a ground transition here; frozen
# suppresses the resulting visual, not the settle itself.
func _update_squash(state: KartState, delta: float) -> void:
	if state.is_grounded and not _was_grounded:
		_squash_impulse = -1.0
	elif not state.is_grounded and _was_grounded:
		_squash_impulse = 1.0
	_was_grounded = state.is_grounded

	_squash_impulse = move_toward(_squash_impulse, 0.0, squash_recovery_speed * delta)
	if state.frozen:
		_squash_impulse = 0.0

	var squash: float = _squash_impulse * (stretch_amount if _squash_impulse > 0.0 else squash_amount)
	_visual.scale = Vector3(1.0 - squash * 0.5, 1.0 + squash, 1.0 - squash * 0.5)


# Density tracks whichever source scrubs harder, slide or brake, and is continuous in both, so the
# plume thickens with the angle rather than snapping on with a drift flag. Grounded only: an
# airborne tyre has nothing to scrub against.
func _update_smoke(state: KartState) -> void:
	var slide: float = state.rear_slip_fraction
	var brake_span: float = maxf(0.001, state.max_speed - brake_smoke_min_speed)
	var braking: float = 0.0
	if state.brake_strength > 0.01:
		braking = clampf((state.speed - brake_smoke_min_speed) / brake_span, 0.0, 1.0)

	var intensity: float = maxf(slide, braking)
	var is_emitting: bool = state.is_grounded and not state.frozen and intensity > 0.01
	_set_smoke(is_emitting, lerpf(smoke_min_ratio, 1.0, intensity) if is_emitting else 0.0)


func _set_smoke(is_emitting: bool, ratio: float) -> void:
	_smoke_left.emitting = is_emitting
	_smoke_right.emitting = is_emitting
	_smoke_left.amount_ratio = ratio
	_smoke_right.amount_ratio = ratio


# Fires purely off state.overspeed, so it tracks whatever pad or source credited the boost rather
# than duplicating BoostPadField's bump/bleed bookkeeping here. Not grounded-gated, unlike smoke:
# a boost taken airborne should still show flame.
func _update_boost_flames(state: KartState) -> void:
	var is_emitting: bool = not state.frozen and state.overspeed > 7.0
	var ratio: float = 0.0
	if is_emitting:
		var fraction: float = clampf(state.overspeed / boost_flame_max_overspeed, 0.0, 1.0)
		ratio = lerpf(boost_flame_min_ratio, 1.0, fraction)
	_set_boost_flames(is_emitting, ratio)


func _set_boost_flames(is_emitting: bool, ratio: float) -> void:
	_boost_flame_left.emitting = is_emitting
	_boost_flame_right.emitting = is_emitting
	_boost_flame_left.amount_ratio = ratio
	_boost_flame_right.amount_ratio = ratio


# Both emitters share one ParticleProcessMaterial in kart.tscn, so this usually writes the same
# instance twice; harmless, and correct if they are ever given separate materials.
func _set_smoke_color(color: Color) -> void:
	if _smoke_material_left != null:
		_smoke_material_left.color = color
	if _smoke_material_right != null:
		_smoke_material_right.color = color


# Re-issued every frame rather than started once: start_joy_vibration's duration is only a safety
# cutoff for update_view going quiet mid-drift, and re-calling keeps the magnitude live.
func _update_vibration(state: KartState) -> void:
	if state.frozen or not state.is_grounded:
		_stop_vibration()
		return

	var intensity: float = state.rear_slip_fraction
	if intensity <= 0.01:
		_stop_vibration()
		return

	var weak: float = intensity * drift_vibration_weak
	var strong: float = intensity * drift_vibration_strong
	for device: int in Input.get_connected_joypads():
		Input.start_joy_vibration(device, weak, strong, 0.2)


func _stop_vibration() -> void:
	for device: int in Input.get_connected_joypads():
		Input.stop_joy_vibration(device)
