class_name Hitbox
extends RefCounted

## The shape every car in this game is tested as, and the swept test that does the testing.
##
## A car is a capsule lying flat in the XZ plane: a spine segment along the car's own heading, with
## a radius equal to half the car's width. Not a sphere — the SportsCar everything here drives is
## 2.2 times longer than it is wide, and one circle around it either lets you drive through the nose
## or takes you on air beside the door. Two capsules overlap exactly when the distance between their
## spines is at most the sum of their radii, which is one segment-to-segment distance and no case
## analysis.
##
## Height is ignored, as it is everywhere else in this project's pickups: callers pair this with
## their own vertical-gap check so a car on a banked sweeper or a crest still reads as being on the
## same road ([member ClockField.max_vertical_gap]).
##
## Everything here is static or lives on [Sweep], and nothing touches the scene tree: this is the
## seam the geometry suite tests.

## The SportsCar model's own footprint at scale 1, in metres, measured off the meshes in
## `cars/FBX/SportsCar.fbx`. Every car in the game — the kart and all three ghost fields — is that
## one model under a scale, so a hitbox matching what the player can see is this footprint under the
## same scale ([method model_half_extents]). Re-measure both if the model is ever replaced.
const MODEL_LENGTH: float = 3.97
const MODEL_WIDTH: float = 1.80

## The multiplier on a ghost field's MODEL_SCALE_PER_FRACTION at which its car comes out exactly
## kart-sized. Not used by the geometry: it is the number the fields' own size ranges are read
## against, and it was implicit in three files before it was written down here.
const KART_CAR_SCALE: float = 4.0

const _EPSILON: float = 0.000001


## Half the footprint — (half length, half width), metres — of the shared SportsCar model drawn at
## [param model_scale]. The model's nose points along its local Z and its width lies along local X;
## the scales are taken absolute because every car in the project mirrors the model on both of those
## axes to face it down the road, and a mirrored car is not a negatively sized one.
static func model_half_extents(model_scale: Vector3) -> Vector2:
	return Vector2(absf(model_scale.z) * MODEL_LENGTH, absf(model_scale.x) * MODEL_WIDTH) * 0.5


## The world yaw a pose faces, in the convention [method spine_offset] reads. Derived from the
## forward vector rather than from Euler angles, so a basis also carrying bank or pitch — the kart's
## start pose on a banked road does — still yields the heading alone.
static func yaw_of(basis: Basis) -> float:
	var forward: Vector3 = -basis.z
	return atan2(-forward.x, -forward.z)


## The vector from a car's centre to the end of its spine: [param reach] metres along [param yaw].
static func spine_offset(yaw: float, reach: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw)) * reach


## The spine half-length of the capsule standing for a car [param half_length] by
## [param half_width]. Shorter than the car by its half-width, because the capsule's round caps are
## what cover the last half-width of nose and of tail. Clamped at zero: a car drawn wider than it is
## long degenerates to a plain circle rather than turning its capsule inside out.
static func half_spine(half_length: float, half_width: float) -> float:
	return maxf(half_length - half_width, 0.0)


## Shortest distance between two segments, squared, ignoring Y — the whole of the overlap test.
##
## Solves the unconstrained minimum of |(a0 - b0) + s*u - t*v|, then clamps s and t back into [0, 1]
## one after the other, re-solving each against the other's clamped value. Clamping the two
## independently is the classic wrong version: it returns the distance between a pair of points that
## are not the closest pair, whenever the unconstrained minimum falls outside the unit square.
##
## The degenerate cases fall out of the epsilon guards rather than being branched on: a zero-length
## segment is a point, and two parallel segments pin s at 0 and let the second pass find the pair.
static func segments_distance_squared(a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3) -> float:
	var u := Vector2(a1.x - a0.x, a1.z - a0.z)
	var v := Vector2(b1.x - b0.x, b1.z - b0.z)
	var w := Vector2(a0.x - b0.x, a0.z - b0.z)

	var a: float = u.dot(u)
	var b: float = u.dot(v)
	var c: float = v.dot(v)
	var d: float = u.dot(w)
	var e: float = v.dot(w)

	var denominator: float = a * c - b * b
	var s: float = 0.0
	if denominator > _EPSILON:
		s = clampf((b * e - c * d) / denominator, 0.0, 1.0)

	var t: float = 0.0
	if c > _EPSILON:
		t = clampf((b * s + e) / c, 0.0, 1.0)
	if a > _EPSILON:
		s = clampf((b * t - d) / a, 0.0, 1.0)

	return (w + u * s - v * t).length_squared()


## One frame of one car's motion, as four edges: the spine where the frame began, the spine where it
## ended, and the straight paths the nose and the tail took between the two. Together they bound the
## region the car swept — exactly under pure travel, and closely enough under the two or three
## degrees of turn a frame at 60 Hz actually contains. This is what lets a capsule be swept without
## being stepped; it is not a general swept-rotation test, and a car spun through a large angle in
## one frame would leave gaps between the chords and the arc its nose really took.
##
## Mutable and reused: a field builds one in _ready, calls [method moved] once per physics frame and
## [method takes] once per car it tests against, so sweeping allocates nothing in the physics step —
## the rule [ClockField.Clock] and every ghost record already follow.
class Sweep extends RefCounted:
	var half_width: float = 0.0
	var nose_from: Vector3 = Vector3.ZERO
	var nose_to: Vector3 = Vector3.ZERO
	var tail_from: Vector3 = Vector3.ZERO
	var tail_to: Vector3 = Vector3.ZERO

	## Re-aims this sweep at one frame of travel, from [param previous_centre] facing
	## [param previous_yaw] to [param centre] facing [param yaw]. The extents are passed in every
	## frame rather than held, so a caller is free to resize its car between frames.
	func moved(
		previous_centre: Vector3, previous_yaw: float,
		centre: Vector3, yaw: float,
		car_half_length: float, car_half_width: float,
	) -> void:
		half_width = car_half_width
		var reach: float = Hitbox.half_spine(car_half_length, car_half_width)
		var was: Vector3 = Hitbox.spine_offset(previous_yaw, reach)
		var now: Vector3 = Hitbox.spine_offset(yaw, reach)
		nose_from = previous_centre + was
		tail_from = previous_centre - was
		nose_to = centre + now
		tail_to = centre - now

	## True when the car standing at [param centre] facing [param yaw] overlaps this sweep anywhere.
	## A clock, or any other round pickup, is the case where the two extents are equal: the spine
	## collapses to a point and this is a circle test.
	##
	## Measured to the swept region's boundary rather than its interior, so a spine lying wholly
	## inside the swept quad would read as a miss. It cannot: the quad is only ever as wide as one
	## frame of travel — a third of a metre at the top speeds this game reaches — and that is always
	## less than the two half-widths being summed.
	func takes(
		centre: Vector3, yaw: float, other_half_length: float, other_half_width: float
	) -> bool:
		var spine: Vector3 = Hitbox.spine_offset(
			yaw, Hitbox.half_spine(other_half_length, other_half_width))
		var front: Vector3 = centre + spine
		var back: Vector3 = centre - spine

		var limit: float = half_width + other_half_width
		var nearest: float = Hitbox.segments_distance_squared(nose_from, tail_from, front, back)
		nearest = minf(nearest, Hitbox.segments_distance_squared(nose_to, tail_to, front, back))
		nearest = minf(nearest, Hitbox.segments_distance_squared(nose_from, nose_to, front, back))
		nearest = minf(nearest, Hitbox.segments_distance_squared(tail_from, tail_to, front, back))
		return nearest <= limit * limit
