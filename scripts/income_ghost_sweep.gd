class_name IncomeGhostSweep
extends RefCounted

## The income runner's per-ghost advance-and-sweep: where one ghost has got to along its recorded
## line, and what it collects getting there. Pulled out of [autoload IncomeRunner] so a TestCase — a
## RefCounted that cannot touch the scene tree — can call it directly, [class BoostGhostField]'s own
## reason for keeping `place_along` a static function.
##
## Walks every recorded segment crossed one at a time rather than jumping to wherever the clock
## says the ghost should be — never one chord from wherever it started to wherever it ends up. A
## chord across a hairpin would cut the inside of the corner and collect a coin the recorded line
## never approached, which would make income framerate-dependent and farmable by tanking the frame
## rate. Walking whole segments means the same elapsed time produces the same income whether it
## arrives in one frame or sixty: [method advance] only ever pays out at a whole-segment crossing,
## and the number of those crossed over a stretch of time depends on the time, not on how it was
## chopped into frames.

## The pickup radius and vertical gap CoinField.segment_takes_coin is swept with, matching the race
## defaults ([member CoinField.pickup_radius], [member CoinField.max_vertical_gap]) so an income
## ghost collects exactly what a kart driving the same line would.
const PICKUP_RADIUS: float = 1.2
const MAX_VERTICAL_GAP: float = 5.0

## Where one ghost has got to along a recorded line, and which coins it has already taken this lap.
## RefCounted rather than a value type, which GDScript lacks: one instance per ghost, mutated in
## place every frame by [method advance].
class State extends RefCounted:
	## The recorded segment (positions[segment_index] -> positions[segment_index + 1]) the ghost is
	## currently inside of.
	var segment_index: int = 0
	## How far through that segment, in whole-segment units, in [0, 1). Also what a view interpolates
	## the ghost's drawn pose by ([method pose]).
	var segment_progress: float = 0.0
	## One flag per coin, cleared whenever the ghost wraps back to segment 0 — CONTEXT.md's **Income**:
	## "each ghost carries its own idea of which coins it has taken".
	var taken: Array[bool] = []

	func reset_taken(coin_count: int) -> void:
		taken.resize(coin_count)
		taken.fill(false)


## One coin taken during an [method advance] call: which coin (by index into the coin arrays
## [method advance] was given), and what to report onward for a pickup popup.
class Pickup extends RefCounted:
	var index: int = 0
	var position: Vector3 = Vector3.ZERO
	var direction: Vector3 = Vector3.FORWARD
	var value: int = 0


## Advances [param state] by [param delta] seconds along a line recorded at [param sample_rate]
## samples/second, sweeping every whole recorded segment of [param positions] crossed along the way
## against every untaken coin in [param coin_positions]/[param coin_values]. Returns the coins taken
## this call, in the order they were crossed — never a repeat within a lap, since a taken coin is
## skipped for the rest of it.
##
## Wraps the instant the last recorded segment is crossed: back to segment 0, with a fresh
## taken-set, matching a lap's own pop from the start/finish gate back to the start line rather than
## a blended loop — CONTEXT.md's **Income ghost**, "not blended". A line shorter than two samples
## (no ghost line recorded yet) advances nothing and collects nothing.
static func advance(
	state: State,
	positions: PackedVector3Array,
	coin_positions: PackedVector3Array,
	coin_values: PackedInt32Array,
	delta: float,
	sample_rate: float,
) -> Array[Pickup]:
	var pickups: Array[Pickup] = []
	var segment_count: int = positions.size() - 1
	if segment_count <= 0:
		return pickups

	if state.taken.size() != coin_positions.size():
		state.reset_taken(coin_positions.size())

	state.segment_progress += delta * sample_rate
	while state.segment_progress >= 1.0:
		var start: Vector3 = positions[state.segment_index]
		var end: Vector3 = positions[state.segment_index + 1]
		_sweep_segment(state, start, end, coin_positions, coin_values, pickups)

		state.segment_progress -= 1.0
		state.segment_index += 1
		if state.segment_index >= segment_count:
			state.segment_index = 0
			state.reset_taken(coin_positions.size())

	return pickups


static func _sweep_segment(
	state: State,
	start: Vector3,
	end: Vector3,
	coin_positions: PackedVector3Array,
	coin_values: PackedInt32Array,
	pickups: Array[Pickup],
) -> void:
	var direction := Vector3(end.x - start.x, 0.0, end.z - start.z)
	var travel_direction: Vector3 = direction.normalized() if direction.length_squared() > 0.0 else Vector3.FORWARD

	for c in coin_positions.size():
		if state.taken[c]:
			continue
		if not CoinField.segment_takes_coin(start, end, coin_positions[c], PICKUP_RADIUS):
			continue
		if absf(end.y - coin_positions[c].y) > MAX_VERTICAL_GAP:
			continue

		state.taken[c] = true
		var pickup := Pickup.new()
		pickup.index = c
		pickup.position = coin_positions[c]
		pickup.direction = travel_direction
		pickup.value = coin_values[c]
		pickups.append(pickup)


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
## "the ith a fraction i/N of the way through it".
static func seat(index: int, count: int, positions: PackedVector3Array) -> State:
	var state := State.new()
	var segment_count: int = positions.size() - 1
	if count <= 0 or segment_count <= 0:
		return state

	var offset: float = float(index) / float(count) * float(segment_count)
	state.segment_index = mini(int(offset), segment_count - 1)
	state.segment_progress = offset - state.segment_index
	return state
