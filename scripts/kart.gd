class_name Kart
extends CharacterBody3D

## The kart's body. Deliberately thin: it owns the Godot node, the world queries and the lifecycle,
## and nothing at all about how the kart feels to drive. That lives in KartModel, which is a
## RefCounted with no idea this file exists.
##
## Per physics frame: classify the surface from the ground ray, build the input, step the model,
## rotate by the yaw it solved, compose velocity from its forward/lateral speeds against the
## current basis, snap to ground or fall, move_and_slide, feed barrier impacts back into the
## model, hand a snapshot to the cosmetics.
##
## Two rules that are easy to break and expensive to debug:
##
##   - Translation comes from velocity/move_and_slide() ONLY. Nudging global_position to "pivot"
##     visually is a second independent source of translation, and it walks the kart across the
##     track a little more every frame.
##   - Surface classification HOLDS the last known surface when the ray misses (airborne, off the
##     world edge) rather than flickering or inventing an airborne state.
##
## The ground is the ray's job and the sphere's job is barriers — the body's collision mask carries
## no ground layer at all. Two independent things holding the kart up is what makes edges violent:
## the ray and the sphere disagree about where the surface is within half a metre of any boundary,
## and the sphere wins by depenetrating sideways off a zero-thickness road ribbon or straight up out
## of the grass slab the road dips below. Held apart, running out of road is a plain fall.

enum SurfaceType {
	ROAD,
	KERB,
	GRASS,
}

# Road carries no tag of its own: it is whatever GroundRay hits that is neither Kerb nor Grass.
# Bit 2 (layer 2) belongs to the barriers.
const GRASS_LAYER_BIT: int = 1 << 3
const KERB_LAYER_BIT: int = 1 << 2

## Every number the feel model runs on. Left null in the scene, so the defaults in KartTuning are
## the tuning of record and there is exactly one place to read them from; assign a KartTuning
## resource here to override per-scene.
@export var tuning: KartTuning

# --- The body's own numbers -------------------------------------------------------------------
# How a sphere on a raycast sits on a mesh, not how the kart feels; hence here, not in KartTuning.
@export var gravity: float = 20.0
@export var ground_snap_strength: float = 40.0
## Ceiling on the m/s the snap may command, in either direction. The ray's hit height is a
## discontinuous signal — a road edge, a kerb lip, a seam between two containers — and an unclamped
## proportional snap turns any step into an instantaneous launch of step * strength m/s. Bounded, a
## step is climbed over a few frames instead.
@export var ground_snap_max_speed: float = 6.0
@export var sphere_radius: float = 0.5

## A *driver-input* concept, not a lap concept: Kart names no lap phase and holds no reference to
## LapDirector. While set, the physics step still runs surface classification,
## gravity, ground snap and cosmetics; what it suppresses is throttle/brake/steer/slip, and it
## pins forward speed, yaw and lateral speed at zero.
##
## Deliberately not set_physics_process(false)/process_mode: both stop ground snap, and the
## countdown relies on ground snap settling the kart onto the road after the teleport.
var frozen: bool = false:
	set(value):
		frozen = value
		# LapDirector freezes the kart from its own _ready, which may run before this node's;
		# _ready re-applies whatever was set in the meantime.
		if _model != null:
			_model.freeze(value)

var _model: KartModel
var _input: KartInput = KartInput.new()
var _state: KartState = KartState.new()
var _current_surface: SurfaceType = SurfaceType.ROAD

@onready var _ground_ray: RayCast3D = $GroundRay
@onready var _cosmetics: KartCosmetics = $Cosmetics


func _ready() -> void:
	# Assigned back so the inspector shows the resource the kart is actually running on.
	_model = KartModel.new(tuning)
	tuning = _model.tuning
	_model.freeze(frozen)


# The "reset" action is read by LapDirector alone; two readers of one action in one frame is a race.
func _physics_process(delta: float) -> void:
	_classify_surface()

	# Gated on frozen like the rest of the driver's hands: spending a charge into a kart pinned at
	# zero during the countdown would just waste it for no visible effect.
	if Input.is_action_just_pressed("use_boost") and not frozen:
		_model.consume_boost_charge()

	var motion: KartMotion = _model.step(
		_input.poll(_model.tuning, delta, frozen),
		_surface_multiplier(),
		delta)

	rotate_y(motion.yaw_delta)

	# Lateral speed is positive to the LEFT, agreeing with yaw_delta's sign, which puts it along -X.
	var forward: Vector3 = -global_transform.basis.z
	var left: Vector3 = -global_transform.basis.x
	var planar: Vector3 = forward * motion.forward_speed + left * motion.lateral_speed

	var is_grounded: bool = _ground_ray.is_colliding()
	var vertical: float = velocity.y
	if is_grounded:
		# Without the radius the sphere embeds in the mesh and every bump becomes a wall.
		var target_y: float = _ground_ray.get_collision_point().y + sphere_radius
		vertical = clampf(
			(target_y - global_position.y) * ground_snap_strength,
			-ground_snap_max_speed,
			ground_snap_max_speed)
	else:
		vertical -= gravity * delta

	velocity = Vector3(planar.x, vertical, planar.z)
	move_and_slide()
	_apply_barrier_impacts()

	_model.snapshot_into(_state)
	_state.is_grounded = is_grounded
	_cosmetics.update_view(_state, delta)


## Teleports to a caller-supplied pose, clearing every scrap of motion, drift and cosmetic
## state. The start line is a property of the track, so the pose is an argument rather than
## remembered state.
func reset_to(pose: Transform3D) -> void:
	global_transform = pose
	velocity = Vector3.ZERO
	_model.reset()
	_input.clear()
	_model.snapshot_into(_state)
	_state.is_grounded = true
	_cosmetics.reset()


# Holds the last known surface when the ray has no hit, rather than flickering or introducing a
# distinct airborne state.
#
# CSGShape3D exposes collision_layer without inheriting CollisionObject3D, so a
# CollisionObject3D-only test never matches the CSG road and the kart reads grass everywhere. Both
# kinds are checked; `match` has no type patterns, hence the is/as chain, and ints are not nullable,
# hence the -1 sentinel.
func _classify_surface() -> void:
	if not _ground_ray.is_colliding():
		return

	var collider: Object = _ground_ray.get_collider()
	var layer: int = -1
	if collider is CSGShape3D:
		layer = (collider as CSGShape3D).collision_layer
	elif collider is CollisionObject3D:
		layer = (collider as CollisionObject3D).collision_layer
	if layer < 0:
		return

	if (layer & GRASS_LAYER_BIT) != 0:
		_current_surface = SurfaceType.GRASS
	elif (layer & KERB_LAYER_BIT) != 0:
		_current_surface = SurfaceType.KERB
	else:
		_current_surface = SurfaceType.ROAD


# The surface is a fact about the world, so it is resolved here and the model is handed a plain
# float. The multiplier scales max speed, acceleration and rear grip — grass is greasy, not slow.
func _surface_multiplier() -> float:
	var t: KartTuning = _model.tuning
	match _current_surface:
		SurfaceType.KERB:
			return t.kerb_multiplier
		SurfaceType.GRASS:
			return t.grass_multiplier
		_:
			return t.road_multiplier


# move_and_slide only redirects velocity along the wall, leaving speed and drift untouched, so the
# impact is fed back to the model here. Strength is how head-on the hit was: 0 graze, 1 square on.
func _apply_barrier_impacts() -> void:
	var travel: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	if travel.length_squared() < 0.0001:
		return
	travel = travel.normalized()

	var max_impact: float = 0.0
	for i: int in range(get_slide_collision_count()):
		var collision: KinematicCollision3D = get_slide_collision(i)
		var collider: Node = collision.get_collider() as Node
		if collider == null or not collider.is_in_group("barrier"):
			continue

		var normal: Vector3 = collision.get_normal()
		normal.y = 0.0
		if normal.length_squared() < 0.0001:
			continue

		max_impact = maxf(max_impact, clampf(-travel.dot(normal.normalized()), 0.0, 1.0))

	if max_impact > 0.0:
		_model.apply_impact(max_impact)


# --- Public surface ---------------------------------------------------------------------------

## A world event done to the kart, alongside the barrier impact the model already takes: the ghost
## field decides a ghost was taken, the model owns what a boost does. Banks a charge rather than
## boosting immediately — see [method use_boost_charge] for the button that spends it.
func add_boost_charge(bump: float, bleed: float) -> void:
	_model.add_boost_charge(bump, bleed)


## m/s currently carried above the ceiling on boost credit, 0.0 when not boosting. Read by
## ChaseCamera for the FOV punch.
var overspeed: float:
	get: return _model.overspeed

## Seconds of boost left at the current bleed rate.
var boost_remaining: float:
	get: return _model.boost_remaining

## Boost charges banked and waiting on a press of the boost button. Read by the HUD.
var boost_charges: int:
	get: return _model.boost_charges


## Absolute forward speed. Read by DebugHud and ChaseCamera.
var speed: float:
	get: return _model.speed

## The tuned speed ceiling, for consumers that want a 0..1 fraction of it (ChaseCamera's FOV).
var max_speed: float:
	get: return _model.tuning.max_speed

## Rear slip magnitude above an epsilon. Read by the camera and the cosmetics.
##
## The camera needs no spin case: heading and velocity never diverge by more than the slip
## ceiling, so it keeps following the heading and its existing lag makes the angle read.
var is_drifting: bool:
	get: return _model.is_drifting

## +1 (left) or -1 (right); 0 when not drifting. Read by the camera for its framing.
var drift_side: float:
	get: return _model.drift_side

var current_surface: SurfaceType:
	get: return _current_surface

## How far the rear is out, in degrees. Tuning and debug.
var rear_slip_degrees: float:
	get: return _model.rear_slip_degrees

## Derived travel-vs-heading divergence, in degrees. Tuning and debug. NOT the rear slip angle:
## the two diverge most exactly when the driving is most interesting.
var body_slip_degrees: float:
	get: return _model.body_slip_degrees
