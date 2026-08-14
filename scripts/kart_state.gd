class_name KartState
extends RefCounted

## A read-only snapshot of the kart, for the view.
##
## KartCosmetics is handed one of these each frame and holds no reference to the model or the body,
## which is what makes "cosmetics never write physics" structural: there is nothing to write back to.
## Filled by KartModel.snapshot_into(), plus the two world facts (grounded, frozen) the body owns.

## Absolute forward speed, and the tuned ceiling it is measured against.
var speed: float = 0.0
var max_speed: float = 14.0

## How far the rear is out, in degrees. Positive = left. What every drift and cosmetic
## predicate reads.
var rear_slip_degrees: float = 0.0

## |rear slip| as a fraction of today's ceiling, 0..1. The continuous "how committed am I" number the
## bank, the yaw cant and the smoke density are all functions of.
var rear_slip_fraction: float = 0.0

## Steer angle as a signed fraction of full lock, -1..1. Positive = left.
var steer_fraction: float = 0.0

## How far ahead of the body origin the front axle sits, in metres. Geometry rather than motion, and
## here for one reason: the view pivots the chassis about the axle the solve is using, rather than a
## hardcoded guess that stops matching the moment the tuning pair is dialled.
var front_axle_offset: float = 1.0

## How far behind the body origin the rear axle sits, in metres. Same role as front_axle_offset,
## but for the wheelie pivot: rearing up hinges on the rear tyres, not the body centre.
var rear_axle_offset: float = 3.0

## Direction the body origin travels relative to heading, in degrees: a wheelbase-weighted blend of
## the two axle angles. Derived output, never an input, and not the rear slip angle.
var body_slip_degrees: float = 0.0

var is_drifting: bool = false
var drift_side: float = 0.0

## Raw brake strength, 0..1, rather than an "is locking up" boolean: the speed at which a brake
## starts smoking the tyres is a cosmetic threshold, and lives in KartCosmetics.
var brake_strength: float = 0.0

## The two facts the body owns rather than the model: whether the ground ray found anything, and
## whether the driver's hands have been taken away.
var is_grounded: bool = true
var frozen: bool = false

## Speed currently owed to a boost, above the tuned ceiling. 0 when no boost is live; what the
## flame effect reads to know it should be burning. See KartModel.overspeed.
var overspeed: float = 0.0
