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
## first ask. A fresh zeroed CircuitLoadout for a null circuit, an empty path, an absent file, or a
## file that fails to load as one — a bare circuit is a valid circuit, not an error.
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

	_cache[path] = loadout
	return loadout


## Writes the cached loadout for [param circuit] back to disk. No-op on a null circuit or an empty
## path, mirroring [method RunDirector._save_ghost_line].
func save(circuit: Circuit) -> void:
	if circuit == null or circuit.loadout_path.is_empty():
		return

	var loadout: CircuitLoadout = for_circuit(circuit)
	var error: Error = ResourceSaver.save(loadout, circuit.loadout_path)
	if error != OK:
		push_warning("LoadoutHolder: failed to save loadout to %s (%s)." % [circuit.loadout_path, error])
