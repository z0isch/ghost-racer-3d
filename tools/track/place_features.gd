extends SceneTree

## Places a circuit's Checkpoints and Coins evenly around a road-generator loop.
##
##   godot --headless --path . --script res://tools/track/place_features.gd -- \
##       --scene res://scenes/circuit3.tscn --checkpoints 6 --coins 14
##
## (tools/track/place_features.ps1 and .sh wrap that line; use those.)
##
## A Godot script rather than a Python one because the road exists only as RoadPoints and the
## Curve3Ds the addon bakes from them, and the frame a gate needs — the one its ±4 m prism must lie
## flat on — is defined by the addon's own interpolation. See _sample_road(), which reproduces
## RoadSegment._top_side_normal_for_offset_eased exactly rather than trusting Curve3D's baked up
## vector, which the addon itself declines to use for the road surface. Because the frame is the
## road's actual one, a gate can land anywhere on the loop — banked, cresting or flat — and its
## prism still lies on the surface, so even spacing can be genuinely even.
##
## It touches only the Checkpoints and Coins subtrees, and the sub-resources those subtrees are the
## last user of. The scene file is rewritten by surgery on its text: instantiating a RoadContainer
## and packing it back would bake the addon's generated RoadSegment meshes into the scene as real
## nodes. Every other block — the road, the ground, the StartLine, node order, unique_ids — comes
## through byte for byte.

# The prism's ceiling (RunDirector.checkpoint_ceiling), so the gate draws the rule rather than
# approximating it.
const GATE_HEIGHT := 5.0
const GATE_POST_THICKNESS := 0.4
const GATE_BAR_THICKNESS := 0.4
const GATE_START_SECOND_BAR := 0.9

const COIN_MESH_RADIUS := 0.35
const COIN_THICKNESS := 0.04
const COIN_HEIGHT := 0.4 ## hover above the road surface, measured along the road's own up
const COIN_SPIN_PHASE_DEG := 37.0 ## per-coin yaw offset so the field does not turn in lockstep
const COIN_SPIN_SCRIPT := "res://scripts/track/coin_spin.gd"

const CHECKPOINTS_NODE := "Checkpoints"
const COINS_NODE := "Coins"
const START_LINE_NODE := "StartLine"

## Step for the coarse walk that projects the StartLine onto the loop. Fine enough that the
## refinement pass either side of the winner lands on the right lobe where the track crosses
## over itself — the projection is 3D, so the upper and lower roadways are never confused.
const PROJECTION_STEP := 0.25

## Finite-difference span for the tangent, in metres of arclength. Large enough to be free of
## baked-polyline noise, small enough that the tangent is local.
const TANGENT_SPAN := 0.05


## One RoadPoint-to-next-RoadPoint span of the loop, flattened into the scene root's space.
class Span extends RefCounted:
	var curve: Curve3D
	var to_root: Transform3D ## curve space -> scene root space
	var start_up: Vector3 ## the span's start RoadPoint's up, in root space
	var end_up: Vector3
	var length: float
	var start_s: float ## arclength of this span's start, measured around the whole loop
	var name: String


## A parsed `[...]` block of the .tscn, kept as its original text so untouched blocks round-trip
## byte for byte.
class Block extends RefCounted:
	var kind: String ## "gd_scene", "ext_resource", "sub_resource", "node", or whatever else
	var attrs: Dictionary = {}
	var text: String


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var opts: Dictionary = _parse_args(args)
	if opts.is_empty():
		quit(2)
		return
	var code: int = _run(opts)
	# The instantiated circuit is never in a tree, so nothing else frees it and Godot reports every
	# node and RID it owns as a leak. Freed here, not at each of _run's exits, so a new early return
	# cannot reintroduce the leak errors.
	if _instantiated != null:
		_instantiated.free()
	quit(code)


var _instantiated: Node = null


func _run(opts: Dictionary) -> int:
	var scene_path: String = opts["scene"]
	var checkpoint_count: int = opts["checkpoints"]
	var coin_count: int = opts["coins"]

	var packed: PackedScene = ResourceLoader.load(scene_path, "PackedScene") as PackedScene
	if packed == null:
		printerr("place_features: cannot load %s as a PackedScene" % scene_path)
		return 1

	# Deliberately not added to the SceneTree: RoadContainer rebuilds its road on entering one, which
	# costs seconds and produces nothing this tool reads — the edge curves are already in the file.
	_instantiated = packed.instantiate()
	var scene_root: Node3D = _instantiated as Node3D
	if scene_root == null:
		printerr("place_features: %s's root is not a Node3D" % scene_path)
		return 1

	var spans: Array[Span] = _build_loop(scene_root)
	if spans.is_empty():
		return 1

	var loop_length: float = 0.0
	for span: Span in spans:
		loop_length += span.length

	# Anchored to the StartLine rather than the loop's arbitrary first RoadPoint: the two have to
	# agree, and the start line is a property of the track this tool must not move.
	var start_line_s: float = 0.0
	var start_line: Node3D = scene_root.get_node_or_null(NodePath(START_LINE_NODE)) as Node3D
	if start_line == null:
		print("place_features: no %s marker — anchoring the start/finish gate at s=0." % START_LINE_NODE)
	else:
		var start_line_origin: Vector3 = _transform_to_root(start_line, scene_root).origin
		start_line_s = _project_onto_loop(spans, loop_length, start_line_origin)

	# Behind the start line, so a lap begins already clear of the gate that ends it and finishes with
	# the run from that gate up to the line — the arrangement CONTEXT.md records under **Start line**.
	# Nothing downstream cares which side it lands on, the start/finish being inert until every other
	# checkpoint has been taken. This is the only place the choice is made, hence a flag.
	var setback: float = opts["start_finish_setback"]
	var finish_s: float = fposmod(start_line_s - setback, loop_length)

	# Node order is lap order and the start/finish ends the lap, so it is emitted last. Counting from
	# i=1 puts the first gate one spacing past it and lands the i=count gate back on it exactly.
	var spacing: float = loop_length / float(checkpoint_count)
	var gate_s: Array[float] = []
	for i: int in range(1, checkpoint_count + 1):
		gate_s.append(fposmod(finish_s + float(i) * spacing, loop_length))

	var clearance: float = opts["gate_clearance"]
	var coin_s: Array[float] = []
	var crowded: int = 0
	if coin_count > 0:
		var coin_spacing: float = loop_length / float(coin_count)
		for j: int in coin_count:
			# The first defence against a coin landing in a gate: at equal counts every coin sits
			# exactly between two gates and nothing has to move.
			var s: float = fposmod(finish_s + (float(j) + 0.5) * coin_spacing, loop_length)
			var cleared: float = _clear_of_gates(s, gate_s, loop_length, clearance)
			if is_nan(cleared):
				crowded += 1
				cleared = s
			coin_s.append(cleared)

	if crowded > 0:
		push_warning(
			"place_features: %d coin(s) could not be moved %.1f m clear of every gate — "
			% [crowded, clearance]
			+ "the loop is too short for %d gates and %d coins at that clearance."
			% [checkpoint_count, coin_count]
		)

	var laterals: Array[float] = opts["coin_lateral"]
	var half_width: float = opts["half_width"]

	var report: PackedStringArray = PackedStringArray()
	report.append("loop: %.2f m over %d spans" % [loop_length, spans.size()])
	report.append(
		"start line at s=%.2f, start/finish gate %.1f m behind it at s=%.2f"
		% [start_line_s, setback, finish_s]
	)

	var checkpoint_text: String = ""
	if checkpoint_count > 0:
		checkpoint_text = "[node name=\"%s\" type=\"Node3D\" parent=\".\"]\n\n" % CHECKPOINTS_NODE
		for i: int in checkpoint_count:
			var frame: Transform3D = _sample_road(spans, loop_length, gate_s[i])
			var is_finish: bool = i == checkpoint_count - 1
			checkpoint_text += _checkpoint_block(i, frame, is_finish, half_width)
			report.append(
				"  Checkpoint%02d  s=%7.2f  %s%s"
				% [i, gate_s[i], _vec_str(frame.origin), "  (start/finish)" if is_finish else ""]
			)

	var coin_text: String = ""
	if coin_count > 0:
		coin_text = "[node name=\"%s\" type=\"Node3D\" parent=\".\"]\n\n" % COINS_NODE
		for j: int in coin_count:
			var lateral: float = laterals[j % laterals.size()]
			var frame: Transform3D = _sample_road(spans, loop_length, coin_s[j])
			coin_text += _coin_block(j, frame, lateral)
			report.append(
				"  Coin%02d        s=%7.2f  lateral %+5.1f  %s"
				% [j, coin_s[j], lateral, _vec_str(_coin_origin(frame, lateral))]
			)

	print("\n".join(report))

	var dry_run: bool = opts["dry_run"]
	if dry_run:
		print("place_features: --dry-run, %s not written" % scene_path)
		return 0

	var written: String = _rewrite_scene(scene_path, checkpoint_text, coin_text, coin_count > 0, half_width)
	if written.is_empty():
		return 1

	print(
		"place_features: wrote %s — %d checkpoints, %d coins"
		% [scene_path, checkpoint_count, coin_count]
	)
	return 0


# ------------------------------------------------------------------------------ the loop


## Walks the RoadPoints' next_pt_init chain into the ordered list of spans that makes up the loop.
## Fails loudly rather than silently producing a partial lap: a chain that does not come back to
## where it started, or that misses points, is a road this tool has no business placing gates on.
func _build_loop(scene_root: Node3D) -> Array[Span]:
	var empty: Array[Span] = []

	var points: Array[Node3D] = []
	_collect_road_points(scene_root, points)
	if points.is_empty():
		if not _instanced_scenes.is_empty():
			# Catches the tool being pointed at main.tscn, which instances a circuit: the road is
			# reachable, so the gates would be written beside the circuit rather than into it.
			printerr(
				"place_features: this scene has no road of its own. The road is inside the "
				+ "instanced scene %s — run the tool against that file instead." % _instanced_scenes[0]
			)
		else:
			printerr("place_features: no RoadPoints found — is there a RoadManager in this scene?")
		return empty

	var first: Node3D = points[0]
	var spans: Array[Span] = []
	var seen: Dictionary = {}
	var current: Node3D = first

	while true:
		if seen.has(current):
			break
		seen[current] = true

		var next_path: Variant = current.get("next_pt_init")
		if next_path == null:
			printerr("place_features: %s has no next_pt_init — the road is not a loop." % current.name)
			return empty
		var next_node_path: NodePath = next_path
		var next_point: Node3D = current.get_node_or_null(next_node_path) as Node3D
		if next_point == null:
			printerr("place_features: %s's next_pt_init does not resolve." % current.name)
			return empty

		var edge: Path3D = current.get_node_or_null(NodePath("edge_C")) as Path3D
		if edge == null or edge.curve == null:
			printerr(
				"place_features: %s has no edge_C curve. Open the scene in the editor with " % current.name
				+ "RoadContainer.create_edge_curves on and save it, so the centreline is in the file."
			)
			return empty

		var span := Span.new()
		span.name = current.name
		span.curve = edge.curve
		span.to_root = _transform_to_root(edge, scene_root)
		span.length = edge.curve.get_baked_length()
		span.start_up = _transform_to_root(current, scene_root).basis.y.normalized()
		span.end_up = _transform_to_root(next_point, scene_root).basis.y.normalized()

		# The addon parents each span's edge curves to the span's start point, so edge_C runs from this
		# point to its next. Checked, not assumed: a curve running the other way faces every gate
		# backwards, and a lap that cannot be completed is a quiet failure.
		var tail: Vector3 = span.to_root * span.curve.sample_baked(span.length, true)
		var expected: Vector3 = _transform_to_root(next_point, scene_root).origin
		if tail.distance_to(expected) > 0.5:
			printerr(
				"place_features: %s's edge_C ends %.2f m from %s, not on it — the centreline "
				% [current.name, tail.distance_to(expected), next_point.name]
				+ "is stale. Re-save the scene from the editor to rebuild it."
			)
			return empty

		spans.append(span)
		current = next_point

	if current != first:
		printerr("place_features: the next_pt_init chain rejoins itself at %s rather than closing the loop." % current.name)
		return empty
	if spans.size() != points.size():
		printerr(
			"place_features: the loop covers %d of %d RoadPoints — this road is not one closed loop."
			% [spans.size(), points.size()]
		)
		return empty

	var s: float = 0.0
	for span: Span in spans:
		span.start_s = s
		s += span.length
	return spans


## Sub-scenes this walk refused to descend into, for the error message in _build_loop.
var _instanced_scenes: PackedStringArray = PackedStringArray()


## Everything under an instanced sub-scene is out of bounds: this tool rewrites one file, and a node
## reached through an instance does not live in it. scene_file_path is set on the root of every such
## instance and empty everywhere else, which makes the boundary exact rather than a name guess.
func _collect_road_points(node: Node, into: Array[Node3D]) -> void:
	for child: Node in node.get_children():
		if not child.scene_file_path.is_empty():
			# Only worth naming if the road is actually in there: main.tscn instances the kart too.
			if _has_road_points(child):
				_instanced_scenes.append(child.scene_file_path)
			continue
		# Identified by the property rather than the class, so this works whether or not the addon's
		# class_name is registered in the environment the tool runs in.
		if child.get("next_pt_init") != null and child is Node3D:
			into.append(child as Node3D)
		_collect_road_points(child, into)


func _has_road_points(node: Node) -> bool:
	for child: Node in node.get_children():
		if child.get("next_pt_init") != null and child is Node3D:
			return true
		if _has_road_points(child):
			return true
	return false


## Node3D.global_transform is only defined inside a SceneTree, and this tree is deliberately not in
## one, so the chain is walked by hand.
func _transform_to_root(node: Node3D, scene_root: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != scene_root:
		var current_3d: Node3D = current as Node3D
		if current_3d != null:
			result = current_3d.transform * result
		current = current.get_parent()
	return result


## The road's own frame at arclength `s`: origin on the centreline, -Z along the direction of
## travel, Y the road's up and X the driver's right — exactly the basis RunDirector reads a
## checkpoint's prism out of (`forward = -basis.z`, `right = basis.x`, `up = basis.y`).
##
## The up vector is a plain lerp of the span's two RoadPoints' up vectors, not a simplification: it
## is what RoadSegment._top_side_normal_for_offset_eased does to build the road surface itself.
## Curve3D's baked up vector is not used — the addon corrects the edge curves' tilts after the fact
## to match, so sampling the corrected curve would read the correction rather than the thing
## corrected.
func _sample_road(spans: Array[Span], loop_length: float, s: float) -> Transform3D:
	var wrapped: float = fposmod(s, loop_length)
	var span: Span = spans[spans.size() - 1]
	for candidate: Span in spans:
		if wrapped < candidate.start_s + candidate.length:
			span = candidate
			break

	var u: float = clampf(wrapped - span.start_s, 0.0, span.length)
	var t: float = u / span.length if span.length > 0.0 else 0.0

	var origin: Vector3 = span.to_root * span.curve.sample_baked(u, true)
	var behind: Vector3 = span.curve.sample_baked(maxf(u - TANGENT_SPAN, 0.0), true)
	var ahead: Vector3 = span.curve.sample_baked(minf(u + TANGENT_SPAN, span.length), true)
	var forward: Vector3 = (span.to_root.basis * (ahead - behind)).normalized()

	var up: Vector3 = span.start_up.lerp(span.end_up, t).normalized()
	var z_axis: Vector3 = -forward
	var x_axis: Vector3 = up.cross(z_axis).normalized()
	var y_axis: Vector3 = z_axis.cross(x_axis).normalized()
	return Transform3D(Basis(x_axis, y_axis, z_axis), origin)


## Arclength of the point on the loop closest to `target`, in 3D rather than plan-view: circuit3
## loops under itself, and a horizontal projection would snap the start line to the roadway above.
func _project_onto_loop(spans: Array[Span], loop_length: float, target: Vector3) -> float:
	var best_s: float = 0.0
	var best_distance: float = INF
	var s: float = 0.0
	while s < loop_length:
		var distance: float = _sample_road(spans, loop_length, s).origin.distance_to(target)
		if distance < best_distance:
			best_distance = distance
			best_s = s
		s += PROJECTION_STEP

	# Refine inside the winning step so the anchor is exact rather than quantised to 25 cm.
	var low: float = best_s - PROJECTION_STEP
	var high: float = best_s + PROJECTION_STEP
	for _i: int in 40:
		var mid_low: float = low + (high - low) / 3.0
		var mid_high: float = high - (high - low) / 3.0
		var d_low: float = _sample_road(spans, loop_length, mid_low).origin.distance_to(target)
		var d_high: float = _sample_road(spans, loop_length, mid_high).origin.distance_to(target)
		if d_low < d_high:
			high = mid_high
		else:
			low = mid_low
	return fposmod((low + high) * 0.5, loop_length)


## Pushes `s` along the loop until it is at least `clearance` from every gate, keeping the direction
## it was already leaning. Returns NAN when no such position exists nearby, which is the answer for a
## loop with more gates than it has room for.
##
## A coin sitting in a gate is not a bug — the pickup test ignores Y and never consults the gate —
## but the driver reads the gate as the thing to aim at and the coin as the thing to detour for, and
## overlapping them collapses the choice the earn rate is built on.
func _clear_of_gates(s: float, gate_s: Array[float], loop_length: float, clearance: float) -> float:
	var current: float = s
	for _pass: int in 8:
		var worst_shift: float = 0.0
		for gate: float in gate_s:
			var delta: float = current - gate
			delta -= loop_length * roundf(delta / loop_length) # to [-L/2, L/2]
			if absf(delta) >= clearance:
				continue
			var direction: float = 1.0 if delta >= 0.0 else -1.0
			var shift: float = (clearance - absf(delta)) * direction
			if absf(shift) > absf(worst_shift):
				worst_shift = shift
		if worst_shift == 0.0:
			return fposmod(current, loop_length)
		current = fposmod(current + worst_shift, loop_length)
	return NAN


# ------------------------------------------------------------------------------ node text


func _checkpoint_block(index: int, frame: Transform3D, is_finish: bool, half_width: float) -> String:
	var material: String = "Material_gate_start" if is_finish else "Material_gate"
	# Post centres, so the inner faces land on ±half_width — the prism's own edge.
	var gate_half: float = half_width + GATE_POST_THICKNESS * 0.5
	var marker: String = "%s/Checkpoint%02d" % [CHECKPOINTS_NODE, index]

	var text: String = (
		"[node name=\"Checkpoint%02d\" type=\"Marker3D\" parent=\"%s\"]\ntransform = %s\n\n"
		% [index, CHECKPOINTS_NODE, var_to_str(frame)]
	)
	text += _mesh_child("GatePostLeft", marker, Vector3(-gate_half, GATE_HEIGHT * 0.5, 0.0), "BoxMesh_gate_post", material)
	text += _mesh_child("GatePostRight", marker, Vector3(gate_half, GATE_HEIGHT * 0.5, 0.0), "BoxMesh_gate_post", material)
	text += _mesh_child("GateBar", marker, Vector3(0.0, GATE_HEIGHT + GATE_BAR_THICKNESS * 0.5, 0.0), "BoxMesh_gate_bar", material)
	if is_finish:
		# The start/finish is told apart by geometry and colour rather than a texture: a second
		# crossbar above the first.
		text += _mesh_child("GateBarUpper", marker, Vector3(0.0, GATE_HEIGHT + GATE_START_SECOND_BAR, 0.0), "BoxMesh_gate_bar", material)
	return text


func _mesh_child(name: String, parent: String, origin: Vector3, mesh_id: String, material_id: String) -> String:
	return (
		"[node name=\"%s\" type=\"MeshInstance3D\" parent=\"%s\"]\n" % [name, parent]
		+ "transform = %s\n" % var_to_str(Transform3D(Basis.IDENTITY, origin))
		+ "mesh = SubResource(\"%s\")\n" % mesh_id
		+ "surface_material_override/0 = SubResource(\"%s\")\n\n" % material_id
	)


func _coin_origin(frame: Transform3D, lateral: float) -> Vector3:
	# Lateral is metres to the driver's right and the hover is along the road's own up, so a coin out
	# on the banking stands off the surface it belongs to rather than off world level.
	return frame.origin + frame.basis.x * lateral + frame.basis.y * COIN_HEIGHT


## A coin marker is level and yaw-only, unlike a checkpoint's, and that is a requirement:
## coin_spin.gd turns the disc about Vector3.UP in the marker's parent space, so a marker rolled with
## the banking would lay the coin on its side. It costs nothing, the pickup test being a horizontal
## distance to this origin that consults no basis.
func _coin_block(index: int, frame: Transform3D, lateral: float) -> String:
	var forward: Vector3 = -frame.basis.z
	var level_forward: Vector3 = Vector3(forward.x, 0.0, forward.z).normalized()
	if level_forward.length_squared() < 0.5:
		level_forward = Vector3.FORWARD # a vertical tangent has no yaw to keep; any is as good
	var z_axis: Vector3 = -level_forward
	var basis := Basis(Vector3.UP.cross(z_axis).normalized(), Vector3.UP, z_axis)

	# The disc stands on edge, face square to the road. R_y(phase) * R_x(90): the X rotation lays
	# CylinderMesh's axis of symmetry into the marker's +Z, the Y rotation is the per-coin phase.
	var angle: float = deg_to_rad(float(index) * COIN_SPIN_PHASE_DEG)
	var mesh_basis := Basis(
		Vector3(cos(angle), 0.0, -sin(angle)),
		Vector3(sin(angle), 0.0, cos(angle)),
		Vector3(0.0, -1.0, 0.0)
	)

	return (
		"[node name=\"Coin%02d\" type=\"Marker3D\" parent=\"%s\"]\n" % [index, COINS_NODE]
		+ "transform = %s\n" % var_to_str(Transform3D(basis, _coin_origin(frame, lateral)))
		# Value rides on the marker so CoinField needs no second table. Flat $1: what a coin is worth
		# is a balance decision this tool does not make.
		+ "metadata/value = 1\n\n"
		+ "[node name=\"Mesh\" type=\"MeshInstance3D\" parent=\"%s/Coin%02d\"]\n" % [COINS_NODE, index]
		+ "transform = %s\n" % var_to_str(Transform3D(mesh_basis, Vector3.ZERO))
		+ "mesh = SubResource(\"CylinderMesh_coin\")\n"
		# A placeholder resolved to the scene's real ext_resource id in _rewrite_scene, which is not
		# known until the file is parsed. The token carries @ so it cannot collide with a real id.
		+ "script = ExtResource(\"%s\")\n\n" % COIN_SCRIPT_TOKEN
	)


# ------------------------------------------------------------------------------ scene surgery

const COIN_SCRIPT_TOKEN := "@coin_spin@"


## Rewrites the .tscn in place, replacing the Checkpoints and Coins subtrees and nothing else.
## Returns the written text, or "" on failure.
func _rewrite_scene(
	scene_path: String, checkpoint_text: String, coin_text: String, needs_coin_script: bool, half_width: float
) -> String:
	var source: String = FileAccess.get_file_as_string(scene_path)
	if source.is_empty():
		printerr("place_features: could not read %s" % scene_path)
		return ""

	var blocks: Array[Block] = _parse_blocks(source)
	var header: Block = null
	var ext: Array[Block] = []
	var subs: Array[Block] = []
	var nodes: Array[Block] = []
	var trailing: Array[Block] = []
	for block: Block in blocks:
		match block.kind:
			"gd_scene": header = block
			"ext_resource": ext.append(block)
			"sub_resource": subs.append(block)
			"node":
				if not _is_generated_node(block):
					nodes.append(block)
			_: trailing.append(block) # connections, editable, anything else: kept as-is

	if header == null:
		printerr("place_features: %s has no [gd_scene] header — is it a text scene?" % scene_path)
		return ""

	# Sub-resources orphaned by the removal go with it, but only if nothing else points at them.
	# Reference counted rather than matched by name, so a shared Material_gate survives.
	_drop_orphaned_subs(subs, nodes)

	if needs_coin_script:
		var coin_script_id: String = _ensure_ext_resource(ext, COIN_SPIN_SCRIPT, "Script")
		coin_text = coin_text.replace(
			"ExtResource(\"%s\")" % COIN_SCRIPT_TOKEN, "ExtResource(\"%s\")" % coin_script_id
		)

	var taken: Dictionary = {}
	for sub: Block in subs:
		taken[sub.attrs.get("id", "")] = true
	var ids: Dictionary = {}
	for wanted: String in [
		"BoxMesh_gate_post", "BoxMesh_gate_bar", "Material_gate", "Material_gate_start",
		"Material_coin", "CylinderMesh_coin",
	]:
		var id: String = wanted
		var suffix: int = 1
		while taken.has(id):
			id = "%s_%d" % [wanted, suffix]
			suffix += 1
		taken[id] = true
		ids[wanted] = id

	var generated_subs: String = ""
	if not checkpoint_text.is_empty():
		var bar_length: float = 2.0 * (half_width + GATE_POST_THICKNESS * 0.5) + GATE_POST_THICKNESS
		generated_subs += (
			"[sub_resource type=\"BoxMesh\" id=\"%s\"]\nsize = Vector3(%s, %s, %s)\n\n"
			% [ids["BoxMesh_gate_post"], GATE_POST_THICKNESS, GATE_HEIGHT, GATE_POST_THICKNESS]
			+ "[sub_resource type=\"BoxMesh\" id=\"%s\"]\nsize = Vector3(%s, %s, %s)\n\n"
			% [ids["BoxMesh_gate_bar"], bar_length, GATE_BAR_THICKNESS, GATE_BAR_THICKNESS]
			+ "[sub_resource type=\"StandardMaterial3D\" id=\"%s\"]\nalbedo_color = Color(0.15, 0.45, 0.9, 1)\n\n"
			% ids["Material_gate"]
			+ "[sub_resource type=\"StandardMaterial3D\" id=\"%s\"]\nalbedo_color = Color(0.95, 0.95, 0.95, 1)\n\n"
			% ids["Material_gate_start"]
		)
		checkpoint_text = checkpoint_text.replace(
			"SubResource(\"BoxMesh_gate_post\")", "SubResource(\"%s\")" % ids["BoxMesh_gate_post"]
		).replace(
			"SubResource(\"BoxMesh_gate_bar\")", "SubResource(\"%s\")" % ids["BoxMesh_gate_bar"]
		).replace(
			"SubResource(\"Material_gate\")", "SubResource(\"%s\")" % ids["Material_gate"]
		).replace(
			"SubResource(\"Material_gate_start\")", "SubResource(\"%s\")" % ids["Material_gate_start"]
		)
	if not coin_text.is_empty():
		generated_subs += (
			"[sub_resource type=\"StandardMaterial3D\" id=\"%s\"]\nalbedo_color = Color(0.95, 0.78, 0.18, 1)\n\n"
			% ids["Material_coin"]
			+ "[sub_resource type=\"CylinderMesh\" id=\"%s\"]\n" % ids["CylinderMesh_coin"]
			+ "material = SubResource(\"%s\")\n" % ids["Material_coin"]
			+ "top_radius = %s\nbottom_radius = %s\nheight = %s\nradial_segments = 20\nrings = 0\n\n"
			% [COIN_MESH_RADIUS, COIN_MESH_RADIUS, COIN_THICKNESS]
		)
		coin_text = coin_text.replace(
			"SubResource(\"CylinderMesh_coin\")", "SubResource(\"%s\")" % ids["CylinderMesh_coin"]
		)

	var sub_count: int = subs.size() + generated_subs.count("[sub_resource")
	var out: String = _header_text(header, ext.size(), sub_count)
	for block: Block in ext:
		out += block.text
	for block: Block in subs:
		out += block.text
	out += generated_subs
	for block: Block in nodes:
		out += block.text
	out += checkpoint_text
	out += coin_text
	for block: Block in trailing:
		out += block.text

	var file: FileAccess = FileAccess.open(scene_path, FileAccess.WRITE)
	if file == null:
		printerr("place_features: could not write %s (%s)" % [scene_path, error_string(FileAccess.get_open_error())])
		return ""
	file.store_string(out)
	file.close()
	return out


## True for the nodes this tool owns: the two roots, and everything under them.
func _is_generated_node(block: Block) -> bool:
	var parent: String = str(block.attrs.get("parent", ""))
	var name: String = str(block.attrs.get("name", ""))
	if parent == "." and (name == CHECKPOINTS_NODE or name == COINS_NODE):
		return true
	for root_name: String in [CHECKPOINTS_NODE, COINS_NODE]:
		if parent == root_name or parent.begins_with(root_name + "/"):
			return true
	return false


func _drop_orphaned_subs(subs: Array[Block], nodes: Array[Block]) -> void:
	var dropping: bool = true
	while dropping:
		dropping = false
		for i: int in range(subs.size() - 1, -1, -1):
			var needle: String = "SubResource(\"%s\")" % subs[i].attrs.get("id", "")
			var references: int = 0
			for node: Block in nodes:
				references += node.text.count(needle)
			for j: int in subs.size():
				if j != i:
					references += subs[j].text.count(needle)
			if references == 0:
				subs.remove_at(i)
				dropping = true


## Returns the id of the ext_resource for `path`, adding the block if the scene has none. The uid
## is read from the sidecar .uid file rather than invented: a wrong uid resolves by path with a
## warning today and breaks the day the file moves.
func _ensure_ext_resource(ext: Array[Block], path: String, type: String) -> String:
	for block: Block in ext:
		if str(block.attrs.get("path", "")) == path:
			return str(block.attrs.get("id", ""))

	var taken: Dictionary = {}
	for block: Block in ext:
		taken[str(block.attrs.get("id", ""))] = true
	var id: String = "1_gen_" + path.get_file().get_basename()
	var suffix: int = 1
	while taken.has(id):
		id = "%d_gen_%s" % [suffix, path.get_file().get_basename()]
		suffix += 1

	var uid: String = FileAccess.get_file_as_string(path + ".uid").strip_edges()
	var uid_attr: String = " uid=\"%s\"" % uid if uid.begins_with("uid://") else ""
	var block := Block.new()
	block.kind = "ext_resource"
	block.attrs = {"path": path, "id": id, "type": type}
	block.text = "[ext_resource type=\"%s\"%s path=\"%s\" id=\"%s\"]\n\n" % [type, uid_attr, path, id]
	ext.append(block)
	return id


## Rebuilds the [gd_scene] line with a corrected load_steps, preserving the uid and format. Godot
## tolerates a stale load_steps, but a file this tool just rewrote should not carry a wrong one.
func _header_text(header: Block, ext_count: int, sub_count: int) -> String:
	var parts: PackedStringArray = PackedStringArray(["[gd_scene"])
	var steps: int = ext_count + sub_count + 1
	if steps > 1:
		parts.append("load_steps=%d" % steps)
	if header.attrs.has("format"):
		parts.append("format=%s" % header.attrs["format"])
	if header.attrs.has("uid"):
		parts.append("uid=\"%s\"" % header.attrs["uid"])
	return " ".join(parts) + "]\n\n"


## Splits the file into `[...]`-headed blocks, each keeping its own trailing blank line so
## reassembly is a plain concatenation.
func _parse_blocks(source: String) -> Array[Block]:
	var blocks: Array[Block] = []
	var current: Block = null
	var attr_re := RegEx.new()
	# Two alternatives, because .tscn mixes quoted values (name="X") with bare ones (format=3).
	var compiled: Error = attr_re.compile("(\\w+)=(?:\"([^\"]*)\"|([^\\s\\]]+))")
	if compiled != OK:
		printerr("place_features: internal regex failure")
		return blocks

	for line: String in source.split("\n"):
		if line.begins_with("["):
			current = Block.new()
			var space: int = line.find(" ")
			var close: int = line.find("]")
			var kind_end: int = mini(space if space >= 0 else line.length(), close if close >= 0 else line.length())
			current.kind = line.substr(1, kind_end - 1)
			for found: RegExMatch in attr_re.search_all(line):
				var value: String = found.get_string(2)
				if value.is_empty() and not found.get_string(3).is_empty():
					value = found.get_string(3)
				current.attrs[found.get_string(1)] = value
			current.text = line + "\n"
			blocks.append(current)
		elif current != null:
			current.text += line + "\n"
	# split("\n") on a trailing newline leaves an empty final element, adding a spurious "\n" to the
	# last block. Trimmed back to exactly one blank separator.
	if not blocks.is_empty():
		var last: Block = blocks[blocks.size() - 1]
		last.text = last.text.rstrip("\n") + "\n\n"
	return blocks


# ------------------------------------------------------------------------------ arguments


const USAGE := """usage: place_features --scene <path> --checkpoints <n> --coins <n> [options]

  --scene PATH             the circuit scene to rewrite (res:// or project-relative)
  --checkpoints N          number of checkpoints; the last is the start/finish gate
  --coins N                number of coins
  --start-finish-setback M  metres the start/finish gate sits BEHIND the StartLine (default 8)
  --gate-clearance M       minimum arclength between a coin and any gate (default 4)
  --coin-lateral A,B,..    metres right of the centreline, cycled per coin (default 0)
  --half-width M           road half width the prism and gate are built to (default 4)
  --dry-run                report the placement without writing the scene"""


func _parse_args(args: PackedStringArray) -> Dictionary:
	var opts: Dictionary = {
		"scene": "",
		"checkpoints": -1,
		"coins": -1,
		"start_finish_setback": 8.0,
		"gate_clearance": 4.0,
		"coin_lateral": [0.0] as Array[float],
		"half_width": 4.0,
		"dry_run": false,
	}
	var i: int = 0
	while i < args.size():
		var arg: String = args[i]
		var value: String = args[i + 1] if i + 1 < args.size() else ""
		match arg:
			"--scene":
				opts["scene"] = _to_res_path(value)
				i += 1
			"--checkpoints":
				opts["checkpoints"] = value.to_int()
				i += 1
			"--coins":
				opts["coins"] = value.to_int()
				i += 1
			"--start-finish-setback":
				opts["start_finish_setback"] = value.to_float()
				i += 1
			"--gate-clearance":
				opts["gate_clearance"] = value.to_float()
				i += 1
			"--half-width":
				opts["half_width"] = value.to_float()
				i += 1
			"--coin-lateral":
				var laterals: Array[float] = []
				for piece: String in value.split(",", false):
					laterals.append(piece.strip_edges().to_float())
				opts["coin_lateral"] = laterals
				i += 1
			"--dry-run":
				opts["dry_run"] = true
			"--help", "-h":
				print(USAGE)
				return {}
			_:
				printerr("place_features: unknown argument %s\n" % arg)
				print(USAGE)
				return {}
		i += 1

	var problems: PackedStringArray = PackedStringArray()
	if str(opts["scene"]).is_empty():
		problems.append("--scene is required")
	elif not FileAccess.file_exists(str(opts["scene"])):
		problems.append("no such scene: %s" % opts["scene"])
	var checkpoint_count: int = opts["checkpoints"]
	if checkpoint_count < 1:
		problems.append("--checkpoints must be at least 1")
	var coin_count: int = opts["coins"]
	if coin_count < 0:
		problems.append("--coins is required and cannot be negative")
	var chosen_laterals: Array[float] = opts["coin_lateral"]
	if chosen_laterals.is_empty():
		problems.append("--coin-lateral needs at least one offset")
	if not problems.is_empty():
		for problem: String in problems:
			printerr("place_features: %s" % problem)
		print(USAGE)
		return {}
	return opts


func _to_res_path(path: String) -> String:
	if path.begins_with("res://"):
		return path
	var normalised: String = path.replace("\\", "/")
	var project_root: String = ProjectSettings.globalize_path("res://")
	if normalised.begins_with(project_root):
		return "res://" + normalised.substr(project_root.length())
	return "res://" + normalised.trim_prefix("./")


func _vec_str(v: Vector3) -> String:
	return "(%7.2f,%7.2f,%7.2f)" % [v.x, v.y, v.z]
