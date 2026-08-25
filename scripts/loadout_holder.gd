extends Node

## Owner of every circuit's loadout, and the only thing that reads or writes them to disk.
##
## An autoload for the same reason [autoload Purse] is one: the state must outlive both the scene
## swap between the open world and a race scene, and the process itself. Separate from Purse for
## the reason CONTEXT.md's **Loadout holder** entry gives — a keyed, persisted collection buys
## nothing by merging into a single unkeyed total with no persistence of its own.
##
## Cached by [member Circuit.loadout_path], not by the Circuit instance: the open world and the
## race scene resolve the same .tres for the same circuit and must not end up mutating two copies
## that can drift apart.
##
## Null-tolerant throughout — race.gd already has a path where no circuit is pending, and a broken
## save must not take the game down.

var _cache: Dictionary[String, CircuitLoadout] = {}


## Returns the cached loadout for [param circuit], loading it from [member Circuit.loadout_path] on
## first ask. A null circuit or an empty path gets a bare zeroed CircuitLoadout — nothing to author
## a clock count from. An absent file or a file that fails to load as one gets a fresh
## CircuitLoadout instead, its clock_count seeded to [method _authored_clock_count] rather than
## left at 0 — a bare circuit is a valid circuit, not an error, and one nobody has bought into yet
## should still show every clock it authors.
func for_circuit(circuit: Circuit) -> CircuitLoadout:
	if circuit == null or circuit.loadout_path.is_empty():
		return CircuitLoadout.new()

	var path: String = circuit.loadout_path
	if _cache.has(path):
		return _cache[path]

	var loadout: CircuitLoadout = null
	if ResourceLoader.exists(path):
		loadout = load(path) as CircuitLoadout
		if loadout == null:
			push_warning("LoadoutHolder: %s did not load as a CircuitLoadout." % path)

	if loadout == null:
		loadout = CircuitLoadout.new()
		loadout.clock_count = _authored_clock_count(circuit)

	_cache[path] = loadout
	return loadout


## How many clocks [param circuit]'s scene actually authors under its root "Clocks" node — the
## same count [method ClockField._resolve_clocks] and [method InertCircuit._apply_loadout] arrive
## at once the scene is live, read here from an instance that is never added to the tree (so no
## _ready fires and nothing else about the scene runs). Seeds a brand-new loadout's clock_count so
## a circuit nobody has bought into yet starts with every authored clock live rather than none —
## CircuitLoadout itself has no way to know this number (its own doc), so the one caller that
## creates a fresh loadout is the one caller that resolves it.
func _authored_clock_count(circuit: Circuit) -> int:
	if circuit == null or circuit.circuit_scene == null:
		return 0
	var instance: Node = circuit.circuit_scene.instantiate()
	var clocks: Node = instance.get_node_or_null("Clocks")
	var count: int = 0
	if clocks != null:
		for child: Node in clocks.get_children():
			if child is Node3D:
				count += 1
	instance.free()
	return count


## Writes the cached loadout for [param circuit] back to disk. No-op on a null circuit or an empty
## path, mirroring [method RunDirector._save_ghost_line].
func save(circuit: Circuit) -> void:
	if circuit == null or circuit.loadout_path.is_empty():
		return

	var loadout: CircuitLoadout = for_circuit(circuit)
	var error: Error = ResourceSaver.save(loadout, circuit.loadout_path)
	if error != OK:
		push_warning("LoadoutHolder: failed to save loadout to %s (%s)." % [circuit.loadout_path, error])
