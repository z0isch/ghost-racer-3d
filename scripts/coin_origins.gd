class_name CoinOrigins
extends RefCounted

## Coin positions and values for a circuit, read from its [PackedScene]'s [SceneState] without
## instantiating anything.
##
## [class CoinField]'s own resolution ([method CoinField._resolve_coins]) needs a live scene tree —
## it reads `marker.global_position` off nodes already in the tree. [autoload IncomeRunner] has no
## scene tree at all: during a race the open world does not exist, and income has to keep accruing
## regardless. This walks the circuit's authored scene data directly instead of instancing it, which
## would load every road mesh, barrier and gate to read a handful of Vector3s on a resource that
## then stays loaded for the process.
##
## Cached per circuit's scene on first ask, the way [autoload LoadoutHolder] caches loadouts.
##
## Two things that were incidental in a race scene and the open world are now load-bearing here and
## will break silently if violated:
## 1. A circuit's Coins node sits at identity under the circuit root — these are local origins, and
##    a Coins node with a transform of its own would need it applied on top.
## 2. Marker order under Coins is the purchase order — the same order [method
##    CoinField._resolve_coins] and [method InertCircuit._apply_loadout] already take their live
##    coins in. All three must agree or the runner earns from coins the player did not buy.

const COINS_NODE_NAME: StringName = &"Coins"
const TRANSFORM_PROPERTY: StringName = &"transform"
const VALUE_META_PROPERTY: StringName = &"metadata/value"
const DEFAULT_VALUE: int = 1

## One circuit's coins, in Coins-node (== circuit-root, by construction) local space, in authored
## order. Parallel arrays rather than a class per coin: the runner sweeps both together every frame
## and a RefCounted-per-coin would be allocated once and then only ever read.
class Layout extends RefCounted:
	var positions: PackedVector3Array = PackedVector3Array()
	var values: PackedInt32Array = PackedInt32Array()

var _cache: Dictionary[PackedScene, Layout] = {}


## The coin layout for [param circuit], loading it from [member Circuit.circuit_scene]'s packed
## state on first ask. An empty layout for a null circuit, a null scene, or a scene with no Coins
## node — a circuit with no coins is not an error.
func for_circuit(circuit: Circuit) -> Layout:
	if circuit == null or circuit.circuit_scene == null:
		return Layout.new()

	var scene: PackedScene = circuit.circuit_scene
	if _cache.has(scene):
		return _cache[scene]

	var layout: Layout = _resolve(scene)
	_cache[scene] = layout
	return layout


func _resolve(scene: PackedScene) -> Layout:
	var layout := Layout.new()
	var state: SceneState = scene.get_state()

	if _find_coins_node(state) == -1:
		return layout

	# SceneState exposes each node's own root-relative path rather than a parent index, always
	# rooted at the implicit "." segment — so a direct child of Coins is exactly a three-segment
	# path (".", "Coins", "<name>"), which is how its parentage is read.
	for i in state.get_node_count():
		var path: NodePath = state.get_node_path(i)
		if path.get_name_count() != 3 or path.get_name(1) != COINS_NODE_NAME:
			continue
		# Filtered to Node3D-derived, matching CoinField._resolve_coins and
		# InertCircuit._apply_loadout: a stray non-spatial child would otherwise shift every index
		# after it in this array but not in theirs.
		if not ClassDB.is_parent_class(state.get_node_type(i), "Node3D"):
			continue
		layout.positions.append(_local_origin(state, i))
		layout.values.append(_coin_value(state, i))

	return layout


func _find_coins_node(state: SceneState) -> int:
	for i in state.get_node_count():
		var path: NodePath = state.get_node_path(i)
		if path.get_name_count() == 2 and path.get_name(1) == COINS_NODE_NAME:
			return i
	return -1


func _local_origin(state: SceneState, node_index: int) -> Vector3:
	for p in state.get_node_property_count(node_index):
		if state.get_node_property_name(node_index, p) != TRANSFORM_PROPERTY:
			continue
		var value: Variant = state.get_node_property_value(node_index, p)
		if value is Transform3D:
			# Assigned into a typed local rather than cast with `as`: the latter is a hard error
			# under this project's warnings table even immediately after an `is` check.
			var transform: Transform3D = value
			return transform.origin
	return Vector3.ZERO


## Assigned straight into the typed return, not via int(): metadata is a Variant, and int(Variant)
## is a hard error under this project's warnings table (coin_field.gd's identical reason).
func _coin_value(state: SceneState, node_index: int) -> int:
	var value: int = DEFAULT_VALUE
	for p in state.get_node_property_count(node_index):
		if state.get_node_property_name(node_index, p) == VALUE_META_PROPERTY:
			value = state.get_node_property_value(node_index, p)
			break
	return value
