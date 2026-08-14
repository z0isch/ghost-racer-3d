class_name ChaseCamera
extends Camera3D

## Follows Target's position and heading with lag, from a standalone sibling node rather than a
## child of the kart — a camera welded to the kart's transform reads as rigidly attached and hides
## the rotation the whole feel model is built on.

@export var target_path: NodePath
@export var follow_distance: float = 1.5
@export var follow_height: float = 2.2
## Aim point height above the kart's ground-level origin.
@export var look_at_height_offset: float = 1.3
@export var position_smoothing: float = 40.0
## Deliberately softer than [member position_smoothing]: filters the rapid vertical bumps ground
## snap picks up on kerbs so they don't punch into camera height and look direction.
@export var height_smoothing: float = 10.0

## Dynamic FOV: widens with speed fraction.
@export var base_fov: float = 80.0
## FOV at [member Kart.speed] == [member Kart.max_speed].
@export var max_speed_fov: float = 90.0
@export var fov_smoothing: float = 12.0

# The speed fraction above saturates at max_speed, so without these the entire overspeed range
# renders identically to cruising and a boost reads as a number on the HUD rather than as speed.

## Degrees added on top of [member max_speed_fov] at [member boost_fov_reference] of overspeed.
@export var boost_fov_gain: float = 12.0
## The overspeed, in m/s, that earns the full [member boost_fov_gain].
@export var boost_fov_reference: float = 10.0
## Smoothing on the way *up* while boosting, deliberately far stiffer than [member fov_smoothing]:
## the punch is the whole point and a 12-rate ease spreads it over half a second, by which time the
## bleed has already taken some of it back. The decay keeps the soft rate, so the widen snaps and
## the settle does not.
@export var boost_fov_attack: float = 30.0

## Look-ahead leads the aim point toward the kart's movement direction ([member Kart.velocity])
## rather than its heading, so the camera tracks a drift's slide. Aim point only — leading the
## follow position too would swing the camera out with every slide.
@export var look_ahead_distance: float = 1.0
## Kept low: drift_lock_angle_degrees steps the movement direction the instant a drift starts, and
## a high value chases that step fast enough to read as a twitch.
@export var look_ahead_smoothing: float = 4.0

## Drift framing pulls back and shifts laterally to the outside of the drift while
## [member Kart.is_drifting], eased in/out via _drift_framing so entering or exiting doesn't pop.
@export var drift_pullback: float = 0.3
@export var drift_lateral_offset: float = 0.6
@export var drift_framing_smoothing: float = 6.0

var _target: Node3D
var _kart: Kart # null when target_path isn't a Kart; FOV and drift dynamics then don't apply
var _smoothed_target_y: float = 0.0
var _current_fov: float = 0.0
var _smoothed_move_dir: Vector3 = Vector3(0.0, 0.0, -1.0)
var _drift_framing: float = 0.0
var _last_drift_side: float = 1.0 # last nonzero side, so the lateral offset survives the ease-out


func _ready() -> void:
	_target = get_node(target_path) as Node3D
	_kart = _target as Kart
	_current_fov = base_fov
	fov = base_fov
	snap_to_target()


func _physics_process(delta: float) -> void:
	if _target == null:
		return

	_update_fov(delta)

	_smoothed_target_y = lerpf(_smoothed_target_y, _target.global_position.y, 1.0 - exp(-height_smoothing * delta))
	_update_drift_framing(delta)
	# Widening the FOV without pulling back is what stretches the kart: it sits close enough to the
	# lens that a wider angle reads as a wide-angle close-up on the car itself, not just a wider view
	# of the track. Scaling follow distance and height by the same factor that widens the FOV cancels
	# that — the kart keeps roughly the screen size and framing it had at base_fov, just from
	# farther away, which is what leaves the wide-angle distortion behind.
	var fov_pullback: float = _fov_distance_scale()
	var distance: float = (follow_distance + drift_pullback * _drift_framing) * fov_pullback
	var desired_position: Vector3 = (
		_flat_target_position()
		+ _flat_behind() * distance
		+ _flat_right() * _drift_outside_sign() * drift_lateral_offset * _drift_framing
		+ Vector3.UP * follow_height * fov_pullback
	)

	global_position = global_position.lerp(desired_position, 1.0 - exp(-position_smoothing * delta))
	_update_look_ahead(delta)
	look_at(_aim_point(), Vector3.UP)


func _update_drift_framing(delta: float) -> void:
	var target: float = 1.0 if _kart != null and _kart.is_drifting else 0.0
	_drift_framing = lerpf(_drift_framing, target, 1.0 - exp(-drift_framing_smoothing * delta))

	if _kart != null and _kart.drift_side != 0.0:
		_last_drift_side = _kart.drift_side


# Reads _last_drift_side, not Kart.drift_side: the latter zeroes the instant the drift ends,
# before _drift_framing has eased back to 0.
func _drift_outside_sign() -> float:
	return -_last_drift_side


func _update_look_ahead(delta: float) -> void:
	var kart_velocity: Vector3 = _kart.velocity if _kart != null else Vector3.ZERO
	var flat_velocity := Vector3(kart_velocity.x, 0.0, kart_velocity.z)

	# Near-zero velocity normalizes to residual noise; hold the last direction instead.
	if flat_velocity.length_squared() > 0.01:
		var move_dir: Vector3 = flat_velocity.normalized()
		_smoothed_move_dir = _smoothed_move_dir.slerp(move_dir, 1.0 - exp(-look_ahead_smoothing * delta)).normalized()


func _aim_point() -> Vector3:
	var speed_fraction: float = 0.0
	if _kart != null and _kart.max_speed > 0.0:
		speed_fraction = clampf(_kart.speed / _kart.max_speed, 0.0, 1.0)
	return _flat_target_position() + Vector3.UP * look_at_height_offset + _smoothed_move_dir * (look_ahead_distance * speed_fraction)


func _update_fov(delta: float) -> void:
	if _kart == null:
		return

	var speed_fraction: float = clampf(_kart.speed / _kart.max_speed, 0.0, 1.0) if _kart.max_speed > 0.0 else 0.0
	var target_fov: float = lerpf(base_fov, max_speed_fov, speed_fraction)

	# Driven by the overspeed rather than by the speed, so the widen tracks the bleed — it opens on
	# the bump and closes as the boost is spent, which is the same curve the driver feels through
	# the wheels.
	var overspeed_fraction: float = clampf(_kart.overspeed / boost_fov_reference, 0.0, 1.0) if boost_fov_reference > 0.0 else 0.0
	target_fov += boost_fov_gain * overspeed_fraction

	# Gated on there being a boost at all, rather than on the target merely rising, so ordinary
	# acceleration keeps its existing ease and only the boost gets the snap.
	var smoothing: float = fov_smoothing
	if overspeed_fraction > 0.0 and target_fov > _current_fov:
		smoothing = boost_fov_attack

	_current_fov = lerpf(_current_fov, target_fov, 1.0 - exp(-smoothing * delta))
	fov = _current_fov


# tan(fov/2) is proportional to how much world space a unit of distance covers on screen, so its
# ratio against the base is exactly the pullback that keeps the kart's apparent size fixed as fov
# widens off base_fov. 1.0 at base_fov; grows smoothly with the same curve fov itself eases on.
func _fov_distance_scale() -> float:
	return tan(deg_to_rad(_current_fov) * 0.5) / tan(deg_to_rad(base_fov) * 0.5)


## Snaps to the target with no lag, so a teleport doesn't leave the camera catching up from across
## the track.
func snap_to_target() -> void:
	if _target == null:
		return

	_smoothed_target_y = _target.global_position.y
	_smoothed_move_dir = -_flat_behind() # velocity is zero right after a teleport
	_drift_framing = 0.0
	global_position = _flat_target_position() + _flat_behind() * follow_distance + Vector3.UP * follow_height
	look_at(_aim_point(), Vector3.UP)


func _flat_target_position() -> Vector3:
	var pos: Vector3 = _target.global_position
	pos.y = _smoothed_target_y
	return pos


# +Z is behind. Yaw only: ground-snap pitch/roll would otherwise shake follow distance on slopes.
func _flat_behind() -> Vector3:
	var behind: Vector3 = _target.global_transform.basis.z
	behind.y = 0.0
	return behind.normalized()


func _flat_right() -> Vector3:
	var right: Vector3 = _target.global_transform.basis.x
	right.y = 0.0
	return right.normalized()
