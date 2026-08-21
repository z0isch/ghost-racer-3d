class_name IncomeGhostSweep
extends RefCounted

## The income runner's per-ghost advance: where one ghost has got to along its recorded line, and
## what it pays reaching the checkpoint crossings that recording made. Pulled out of [autoload
## IncomeRunner] so a TestCase — a RefCounted that cannot touch the scene tree — can call it
## directly, [class BoostGhostField]'s own reason for keeping `place_along` a static function.
##
## Walks every recorded segment crossed one at a time rather than jumping to wherever the clock
## says the ghost should be — never one chord from wherever it started to wherever it ends up.
## Walking whole segments means the same elapsed time produces the same income whether it arrives
## in one frame or sixty: [method advance] only ever pays out at a whole-segment crossing, and the
## number of those crossed over a stretch of time depends on the time, not on how it was chopped
## into frames.
##
## No sweep against any spatial pickup any more — a recording's checkpoint crossings are fully
## determined by the recording itself, so they are precomputed once (by RunDirector, into
## [member GhostLine.checkpoint_samples]) and this pays rung n the instant segment n's crossing
## sample is reached.

## Where one ghost has got to along a recorded line, and which rung of the checkpoint ladder it is
## on. RefCounted rather than a value type, which GDScript lacks: one instance per ghost, mutated in
## place every frame by [method advance].
class State extends RefCounted:
	## The recorded segment (positions[segment_index] -> positions[segment_index + 1]) the ghost is
	## currently inside of.
	var segment_index: int = 0
	## How far through that segment, in whole-segment units, in [0, 1). Also what a view interpolates
	## the ghost's drawn pose by ([method pose]).
	var segment_progress: float = 0.0
	## The next entry of the recording's checkpoint_samples this ghost has yet to reach. Reset to 0
	## when the recording pops back to the start — a Timeout followed by a Countdown, which is
	## exactly what restarts the ladder at rung 1 (CONTEXT.md's **Income ghost**).
	var next_crossing: int = 0


## One checkpoint paid during an [method advance] call: which rung paid it, and what to report
## onward for a pickup popup.
class Pickup extends RefCounted:
	var position: Vector3 = Vector3.ZERO
	var direction: Vector3 = Vector3.FORWARD
	var value: int = 0


## Advances [param state] by [param delta] seconds along a line recorded at [param sample_rate]
## samples/second, paying [param base_value] times the rung reached at every entry of [param
## crossings] crossed along the way. Returns the checkpoints paid this call, in the order they were
## crossed.
##
## Wraps the instant the last recorded segment is crossed: back to segment 0 with the ladder back at
## its first rung, matching a Run's own pop from wherever the Timeout left it back to the start line
## rather than a blended loop — CONTEXT.md's **Income ghost**, "not blended". A line shorter than
## two samples (no ghost line recorded yet) advances nothing and pays nothing.
static func advance(
	state: State,
	positions: PackedVector3Array,
	crossings: PackedInt32Array,
	base_value: int,
	delta: float,
	sample_rate: float,
) -> Array[Pickup]:
	var pickups: Array[Pickup] = []
	var segment_count: int = positions.size() - 1
	if segment_count <= 0:
		return pickups

	state.segment_progress += delta * sample_rate
	while state.segment_progress >= 1.0:
		state.segment_progress -= 1.0
		state.segment_index += 1

		while (state.next_crossing < crossings.size()
				and crossings[state.next_crossing] <= state.segment_index):
			var crossing: int = crossings[state.next_crossing]
			var pickup := Pickup.new()
			# Rung n at crossing n, one-based: the recording's first checkpoint paid 1 × base and
			# so does the ghost's, which is what makes income exactly the record earn rate.
			pickup.value = (state.next_crossing + 1) * base_value
			# The recorded pose at the crossing — the ghost is standing on the checkpoint prism at
			# that sample, so the popup lands where the money was without this ever needing to know
			# where a checkpoint is.
			pickup.position = positions[crossing]
			pickup.direction = _segment_direction(positions, crossing)
			pickups.append(pickup)
			state.next_crossing += 1

		if state.segment_index >= segment_count:
			state.segment_index = 0
			state.next_crossing = 0

	return pickups


## The travel direction into recorded sample [param index] — from the sample before it, flattened
## to the horizontal, for RunDirector.checkpoint_paid's identical "which way is ahead" reason.
static func _segment_direction(positions: PackedVector3Array, index: int) -> Vector3:
	var start: Vector3 = positions[maxi(index - 1, 0)]
	var end: Vector3 = positions[index]
	var direction := Vector3(end.x - start.x, 0.0, end.z - start.z)
	return direction.normalized() if direction.length_squared() > 0.0 else Vector3.FORWARD


## The pose [param state] should be drawn at: the recorded pose at [member State.segment_index]
## lerped toward the next by [member State.segment_progress] — the same sub-sample interpolation
## [method PaceGhost._apply] does, so a ghost reads exactly where the simulation has it between
## whole recorded samples rather than snapping once per segment.
static func pose(state: State, positions: PackedVector3Array, yaws: PackedFloat32Array) -> Transform3D:
	var last: int = positions.size() - 1
	var index: int = mini(state.segment_index, last)
	var next_index: int = mini(index + 1, last)
	var position: Vector3 = positions[index].lerp(positions[next_index], state.segment_progress)
	# lerp_angle, not lerp: the yaw wraps, and a plain lerp spins the ghost a full turn at pi
	# (pace_ghost.gd's identical reason).
	var yaw: float = lerp_angle(yaws[index], yaws[next_index], state.segment_progress)
	return Transform3D(Basis(Vector3.UP, yaw), position)


## A fresh ghost seated at slot [param index] of [param count]: `index / count` of the way along
## [param positions], in whole-and-fractional recorded segments — CONTEXT.md's **Income ghost**,
## "the ith a fraction i/N of the way through it". [member State.next_crossing] is seated to match:
## every entry of [param crossings] the offset already skipped past must not be paid again the
## instant the ghost starts running.
static func seat(index: int, count: int, positions: PackedVector3Array, crossings: PackedInt32Array) -> State:
	var state := State.new()
	var segment_count: int = positions.size() - 1
	if count <= 0 or segment_count <= 0:
		return state

	var offset: float = float(index) / float(count) * float(segment_count)
	state.segment_index = mini(int(offset), segment_count - 1)
	state.segment_progress = offset - state.segment_index

	var skipped: int = 0
	for crossing: int in crossings:
		if crossing <= state.segment_index:
			skipped += 1
	state.next_crossing = skipped

	return state
