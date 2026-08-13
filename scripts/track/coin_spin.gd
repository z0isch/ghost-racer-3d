class_name CoinSpin
extends MeshInstance3D

## Turns a coin slowly on the spot so it catches the eye at racing speed.
##
## Cosmetic only, and that is a rule rather than an observation. CoinField's pickup test is a
## horizontal distance from the kart's swept segment to the coin marker's origin and never consults
## this rotation, which would otherwise make a pickup depend on when in the cycle you arrived.
##
## It lives on the mesh rather than on CoinField because the spin is part of what a coin looks like,
## not what a coin is: a circuit scene spins correctly opened on its own.
##
## The rotation is about Vector3.UP in the parent's space. Coin markers are placed level and
## yaw-only so that stays world up, including up a banked sweeper where a coin rolled with the road
## would lie over on its side.

## Slow enough to read as a turning coin rather than a strobe: a full turn every four seconds.
@export var degrees_per_second: float = 90.0


func _process(delta: float) -> void:
	rotate(Vector3.UP, deg_to_rad(degrees_per_second) * delta)
