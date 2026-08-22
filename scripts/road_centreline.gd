class_name RoadCentreline
extends RefCounted

## The road-loop walk shared by every field that places things along a circuit's own centreline
## rather than a recorded lap. Extracted out of BoostGhostField, which was the first and, until
## HazardGhostField, the only consumer — static functions only, so both fields call the same walk
## rather than each keeping its own copy to drift out of sync.

## Not registered as a class_name by the addon itself, so accessed the same way road_point.gd and
## BoostGhostField access it: preloaded as a const, purely to type the segments [method walk_loop]
## walks.
const RoadSegment = preload("res://addons/road-generator/nodes/road_segment.gd")


## One full circuit of [param road_container]'s RoadPoints, concatenating each RoadPoint's next
## RoadSegment's own curve in "next" order ([method RoadPoint.get_next_road_node]) starting from an
## arbitrary RoadPoint and stopping once the walk returns to it. A RoadPoint with no next segment
## ends the walk short rather than looping forever chasing a null.
##
## The segment's curve, deliberately, and not the RoadPoint's generated edge_C path. edge_C is
## nominally the same line, but the addon re-derives it through RoadSegment.offset_curve rather than
## reusing the curve it just built, and that derivation has a near-90-degree fallback branch that
## hands back a handle in the segment's local space to a curve being built in the RoadPoint's — so
## on any corner sharp enough to trip it, edge_C bows clean off the tarmac (circuit3's RP_004
## corner, by ~20 m). The segment's curve is what the road mesh's own loops are placed along, so it
## is the road's true middle by construction.
static func walk_loop(road_container: RoadContainer) -> PackedVector3Array:
	var positions: PackedVector3Array = PackedVector3Array()
	var roadpoints: Array[RoadPoint] = road_container.get_roadpoints()
	if roadpoints.is_empty():
		return positions

	var start_point: RoadPoint = roadpoints[0]
	var point: RoadPoint = start_point
	# +1: every RoadPoint visited once, plus the one extra step back onto start_point that closes
	# the loop and ends the walk.
	var guard: int = roadpoints.size() + 1
	while guard > 0:
		guard -= 1
		var segment: RoadSegment = point.next_seg
		if segment == null or not is_instance_valid(segment) or segment.curve == null:
			break
		var local_points: PackedVector3Array = segment.curve.get_baked_points()
		# next_seg is the segment on the point's "next" side, but the point is not always that
		# segment's start_point — reached from its far end, its samples run backwards.
		var forward: bool = segment.start_point == point
		# Segment boundaries duplicate a point (this segment's last sample is the next RoadPoint,
		# which is also that next segment's first sample), so every walk after the first skips its
		# own first sample.
		var skip: int = 1 if not positions.is_empty() else 0
		for i in range(skip, local_points.size()):
			var index: int = i if forward else local_points.size() - 1 - i
			positions.append(segment.to_global(local_points[index]))

		var next_point: RoadPoint = point.get_next_road_node() as RoadPoint
		if next_point == null or next_point == start_point:
			break
		point = next_point

	return positions


## Cuts the closed [param loop] into an open line starting at whichever of its samples sits nearest
## [param start_line], and walks it in whichever direction — [param loop]'s own order, or reversed —
## matches [param start_line]'s own forward facing (`-basis.z`, [member Kart]'s own forward
## convention). Without this the loop's cut point and direction are whatever [method walk_loop]
## happened to start and walk from, which has no reason to land anywhere near where the driver
## actually starts a lap.
static func cut_and_orient(loop: PackedVector3Array, start_line: Node3D) -> PackedVector3Array:
	var count: int = loop.size()
	var cut: int = _nearest_index(loop, start_line.global_position)

	var facing: Vector3 = -start_line.global_transform.basis.z
	var travel: Vector3 = loop[(cut + 1) % count] - loop[cut]
	if travel.dot(facing) < 0.0:
		loop.reverse()
		cut = count - 1 - cut

	var oriented: PackedVector3Array = PackedVector3Array()
	oriented.resize(count)
	for i in count:
		oriented[i] = loop[(cut + i) % count]
	return oriented


## The index into [param positions] closest to [param point], by squared distance (monotonic with
## distance, cheaper to compare) — the seam [method cut_and_orient] cuts the loop at.
static func _nearest_index(positions: PackedVector3Array, point: Vector3) -> int:
	var best_index: int = 0
	var best_distance: float = INF
	for i in positions.size():
		var distance: float = positions[i].distance_squared_to(point)
		if distance < best_distance:
			best_distance = distance
			best_index = i
	return best_index


## One yaw per position in [param positions], each the heading of the step into the next position
## (`-atan2(dir.x, dir.z)`'s convention inverted to match [member Kart]'s own `forward =
## -basis.z`— see [member RunDirector._recording_yaws], which records `global_rotation.y` off that
## same basis). The last position has no "next" step of its own, so it repeats the step before it
## rather than wrapping onto the first — the walk is an open line by the time this runs, not the
## closed loop it started as.
static func yaws_from_positions(positions: PackedVector3Array) -> PackedFloat32Array:
	var yaws: PackedFloat32Array = PackedFloat32Array()
	yaws.resize(positions.size())
	for i in positions.size() - 1:
		var dir: Vector3 = (positions[i + 1] - positions[i]).normalized()
		yaws[i] = atan2(-dir.x, -dir.z)
	if positions.size() > 1:
		yaws[positions.size() - 1] = yaws[positions.size() - 2]
	return yaws


## The circuit's road width in metres, read off an arbitrary RoadPoint as lane_width times its lane
## count. One read for the whole circuit, deliberately not interpolated per sample: width is
## authored per RoadPoint and could in principle vary, but carrying it through the walk means
## plumbing a width array alongside every position. A circuit that narrows mid-lap merely gets lanes
## that are too wide on the narrow stretch — which is exactly BoostGhostField's stated stance on
## hanging ghosts over the kerb. Returns 0.0 where there is no road to measure.
static func width(road_container: RoadContainer) -> float:
	var roadpoints: Array[RoadPoint] = road_container.get_roadpoints()
	if roadpoints.is_empty():
		return 0.0
	var point: RoadPoint = roadpoints[0]
	return point.lane_width * point.lanes.size()
