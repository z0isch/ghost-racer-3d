class_name KartMotion
extends RefCounted

## What KartModel.step() hands back: a description of this frame's motion, which the body then
## applies. Not a command and not a transform — three numbers in the kart's own frame.
##
## The model has no idea where the kart is or which way it is facing; the body has no idea how any
## of these were arrived at. Everything the seam carries is here.

## Radians to rotate the body about Y this frame. Positive = left, matching Godot's rotate_y(),
## so the body's whole rotation step is `rotate_y(motion.yaw_delta)`.
##
## Never assigned by anything: it is solved from the disagreement between the two axle angles.
var yaw_delta: float = 0.0

## Speed along the kart's heading. Metres per second.
var forward_speed: float = 0.0

## Speed across the kart's heading, positive = left, agreeing with [member yaw_delta]'s sign; the
## body composes velocity as [code]forward * forward_speed + left * lateral_speed[/code].
##
## Solved fresh every frame from the two axle angles, never integrated state: the car's momentum
## lives in the angles, via grip latency, not in a lateral velocity accumulator.
var lateral_speed: float = 0.0
