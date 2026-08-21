class_name CheckpointPrism
extends RefCounted

## The swept-plane crossing test shared by every checkpoint prism in the game — CONTEXT.md,
## **Checkpoint prism**: bounded laterally and vertically, no thickness, crossed rather than
## entered. [class RunDirector] tests a Run's checkpoints against it.


## True if the segment [param previous] -> [param position] crosses the plane through [param
## origin] with normal [param forward], inside the cross-section bounded by [param right] /
## [param up] out to [param half_width] and between [param floor] and [param ceiling].
static func crossed(previous: Vector3, position: Vector3, origin: Vector3, forward: Vector3,
		right: Vector3, up: Vector3, half_width: float, floor: float, ceiling: float) -> bool:
	var before: float = (previous - origin).dot(forward)
	var after: float = (position - origin).dot(forward)

	# Either sign counts: a caller enforcing monotonic progress already means a backwards crossing
	# gains nothing, and one that does not (a circuit entry) wants either direction anyway.
	var crossed_plane: bool = (before <= 0.0 and after > 0.0) or (before >= 0.0 and after < 0.0)
	if not crossed_plane:
		return false

	var local: Vector3 = previous.lerp(position, before / (before - after)) - origin
	var lateral: float = local.dot(right)
	var height: float = local.dot(up)
	if absf(lateral) > half_width:
		return false
	if height < floor or height > ceiling:
		return false

	return true
