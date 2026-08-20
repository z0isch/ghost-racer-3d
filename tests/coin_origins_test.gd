class_name CoinOriginsTest
extends TestCase

## CoinOrigins.for_circuit against the real circuit3/circuit4 resources: pins that the scene-state
## walk agrees with the circuit's authored .tscn to the float, and in the same order the .tscn
## authors it in — CoinField._resolve_coins and InertCircuit._apply_loadout's own order, which this
## must never disagree with (issue 04's "load-bearing" authoring rules).
##
## The circuit resources are loaded straight off disk rather than instanced, which is the whole
## point: this suite is a TestCase, a RefCounted that cannot touch the scene tree, and CoinOrigins is
## built to answer without one.

const CIRCUIT3_PATH: String = "res://circuits/circuit3.tres"
const CIRCUIT4_PATH: String = "res://circuits/circuit4.tres"


func suite_name() -> String:
	return "CoinOriginsTest"


func test_circuit3_coin_origins_match_the_authored_transforms() -> void:
	var circuit: Circuit = load(CIRCUIT3_PATH) as Circuit
	check(circuit != null, "circuit3.tres loads as a Circuit")
	if circuit == null:
		return

	var layout: CoinOrigins.Layout = CoinOrigins.new().for_circuit(circuit)
	# Coin00..Coin04's authored transform origins, read straight from scenes/circuit3.tscn.
	var expected: Array[Vector3] = [
		Vector3(-1.9372711, 0.39994302, -33.871544),
		Vector3(-26.987043, 0.3001237, -66.0735),
		Vector3(13.472787, 0.73255396, -60.485466),
		Vector3(0.006517104, 6.3984494, -14.247054),
		Vector3(19.87526, 0.40206668, -12.818832),
	]

	check(layout.positions.size() == expected.size(),
		"circuit3 has %d coins" % expected.size())
	for i in mini(layout.positions.size(), expected.size()):
		check(layout.positions[i].distance_to(expected[i]) < 1e-4,
			"coin %d's origin matches its authored transform, in authored order" % i)
		check(layout.values[i] == 1, "coin %d's value matches its authored metadata" % i)


func test_circuit4_coin_origins_match_the_authored_transforms() -> void:
	var circuit: Circuit = load(CIRCUIT4_PATH) as Circuit
	check(circuit != null, "circuit4.tres loads as a Circuit")
	if circuit == null:
		return

	var layout: CoinOrigins.Layout = CoinOrigins.new().for_circuit(circuit)
	var expected: Array[Vector3] = [
		Vector3(-26.10599, 0.4, -0.61165994),
		Vector3(-22.995726, 0.4, -36.574642),
		Vector3(25.658426, 0.4, -18.427837),
	]

	check(layout.positions.size() == expected.size(),
		"circuit4 has %d coins" % expected.size())
	for i in mini(layout.positions.size(), expected.size()):
		check(layout.positions[i].distance_to(expected[i]) < 1e-4,
			"coin %d's origin matches its authored transform, in authored order" % i)


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
