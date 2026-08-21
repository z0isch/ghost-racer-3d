class_name CoinOriginsTest
extends TestCase

## CoinOrigins.for_circuit against the real circuit3/circuit4 resources: pins that the scene-state
## walk agrees with the circuit's authored .tscn to the float, and in the same order the .tscn
## authors it in — CoinField._resolve_coins and InertCircuit._apply_loadout's own order, which this
## must never disagree with (issue 04's "load-bearing" authoring rules).
##
## The oracle is the scene INSTANTIATED, compared against CoinOrigins reading the same scene's
## packed state without instantiating. Coin positions are authored by dragging markers in the
## editor, so hand-copied literals here would go stale on every nudge and the suite would fail for a
## move that broke nothing. Two independent readings of the same file cannot: they disagree only
## when the walk itself is wrong — a bad parentage filter, a dropped Node3D check, a reordering, a
## missed value metadata — which is the thing actually worth guarding.
##
## Instancing is exactly what CoinOrigins exists to avoid at runtime ([autoload IncomeRunner] has no
## scene tree), and that constraint still holds for the code under test. It does not bind the test:
## instantiate() builds a detached node that is freed here and never enters a tree, so this suite
## stays the RefCounted TestCase it has to be.

const CIRCUIT3_PATH: String = "res://circuits/circuit3.tres"
const CIRCUIT4_PATH: String = "res://circuits/circuit4.tres"
const VALUE_META: StringName = &"value"


func suite_name() -> String:
	return "CoinOriginsTest"


func test_circuit3_coin_origins_match_the_authored_transforms() -> void:
	_check_circuit(CIRCUIT3_PATH, "circuit3")


func test_circuit4_coin_origins_match_the_authored_transforms() -> void:
	_check_circuit(CIRCUIT4_PATH, "circuit4")


func test_a_circuit_with_no_scene_has_no_coins() -> void:
	var circuit := Circuit.new()
	var layout: CoinOrigins.Layout = CoinOrigins.new().for_circuit(circuit)
	check(layout.positions.is_empty(), "a circuit with no circuit_scene yields no coins, not an error")


func test_results_are_cached_per_scene() -> void:
	var circuit: Circuit = load(CIRCUIT3_PATH) as Circuit
	var origins := CoinOrigins.new()
	var first: CoinOrigins.Layout = origins.for_circuit(circuit)
	var second: CoinOrigins.Layout = origins.for_circuit(circuit)
	check(first == second, "a second ask for the same circuit returns the cached layout")


## The whole comparison for one circuit: walk vs instance, position by position and value by value.
func _check_circuit(path: String, label: String) -> void:
	var circuit: Circuit = load(path) as Circuit
	check(circuit != null, "%s.tres loads as a Circuit" % label)
	if circuit == null or circuit.circuit_scene == null:
		return

	var root: Node = circuit.circuit_scene.instantiate()
	var coins: Node = root.get_node_or_null(NodePath(CoinOrigins.COINS_NODE_NAME))
	if coins == null:
		fail("%s's scene has a Coins node" % label)
		root.free()
		return

	# Load-bearing authoring rule 1 (CoinOrigins' own docstring): the walk reads marker transforms
	# as circuit-root-local, which is only true while Coins itself sits at identity. Dragging the
	# Coins node in the editor would offset every income coin and nothing else would notice.
	var coins_spatial: Node3D = coins as Node3D
	if coins_spatial != null:
		check(coins_spatial.transform.is_equal_approx(Transform3D.IDENTITY),
			"%s's Coins node sits at identity, so marker transforms are circuit-root-local" % label)

	var expected_positions: Array[Vector3] = []
	var expected_values: Array[int] = []
	for child: Node in coins.get_children():
		var marker: Node3D = child as Node3D
		if marker == null:
			continue
		expected_positions.append(marker.transform.origin)
		expected_values.append(_meta_value(marker))
	root.free()

	var layout: CoinOrigins.Layout = CoinOrigins.new().for_circuit(circuit)

	# Guards the comparison against passing vacuously: two empty readings agree about nothing.
	check(not expected_positions.is_empty(), "%s authors at least one coin" % label)
	check(layout.positions.size() == expected_positions.size(),
		"%s's walk finds every authored coin (authored %d, walked %d)"
			% [label, expected_positions.size(), layout.positions.size()])

	for i in mini(layout.positions.size(), expected_positions.size()):
		check(layout.positions[i].distance_to(expected_positions[i]) < 1e-4,
			"%s coin %d's origin matches its authored transform, in authored order (authored %v, walked %v)"
				% [label, i, expected_positions[i], layout.positions[i]])
		check(layout.values[i] == expected_values[i],
			"%s coin %d's value matches its authored metadata (authored %d, walked %d)"
				% [label, i, expected_values[i], layout.values[i]])


## Mirrors CoinOrigins._coin_value, including its reason for not calling int(): metadata is a
## Variant and int(Variant) is a hard error under this project's warnings table.
func _meta_value(marker: Node3D) -> int:
	var value: int = CoinOrigins.DEFAULT_VALUE
	if marker.has_meta(VALUE_META):
		value = marker.get_meta(VALUE_META)
	return value
