extends Node

## Owner of every circuit's income ghosts: where each one has got to along its line, which rung of
## the checkpoint ladder it is on, and what it has earned.
##
## An autoload for the reason [autoload Purse] and [autoload LoadoutHolder] are, and then harder:
## income has to go on accruing while the player is inside a race scene where none of it is
## visible, so the thing that computes it cannot live in any scene at all.
##
## Simulates every registered circuit every frame, whether or not anything is drawing it — [class
## IncomeGhostView] only ever reads [method ghost_transforms]/[member income_rate], never the
## reverse. Earning and drawing are one simulation seen from two distances (CONTEXT.md's **Income
## runner**), so a ghost too far away to draw goes on earning exactly as it did.
##
## Learns which circuits exist from the open world: each circuit's IncomeGhostView registers its
## Circuit on _ready ([method register_circuit]). Idempotent and outlives the scene swap — this
## autoload holds the Circuit references, and the freed world nodes do not matter. Running race.tscn
## directly earns nothing, matching race.gd's own FALLBACK_CIRCUIT as an editor-only path.
##
## It no longer sweeps anything: a recording's checkpoint crossings are fully determined by that
## recording, so they are found once at reseat and a ghost pays rung n on reaching crossing n.

## One checkpoint, paid by one circuit's income ghost. Circuit-local position and direction — this
## autoload never converts to world coordinates; the view stands in the circuit's frame and does
## that for free (CONTEXT.md's **Income ghost view**).
signal pickup(circuit: Circuit, position: Vector3, direction: Vector3, value: int)

## Ghost lines are recorded one sample per physics tick ([method RunDirector._append_sample]), so
## walking them at this same rate is what makes a ghost retrace exactly what was driven.
var _sample_rate: float:
	get: return Engine.physics_ticks_per_second

var _circuits: Dictionary[Circuit, CircuitIncome] = {}

## The summed instantaneous income rate across every registered circuit, in dollars per second.
## Exposed with nothing reading it yet — a global $/sec readout is wanted eventually and this is the
## number it will read. Never conflated with [member RunDirector.earn_rate]: that measures how well
## a Run was driven and is the only thing that can set a record; this measures what has been bought.
var income_rate: float:
	get:
		var total: float = 0.0
		for income: CircuitIncome in _circuits.values():
			total += income.income_rate
		return total


func _process(delta: float) -> void:
	for circuit: Circuit in _circuits:
		_advance(circuit, _circuits[circuit], delta)


## Registers [param circuit] if it is not already known, and seats its ghosts. Safe to call every
## time an IncomeGhostView enters the tree — a second registration of the same circuit is a no-op,
## since re-seating on every world load is [method reseat]'s job, done once here at first ask.
func register_circuit(circuit: Circuit) -> void:
	if circuit == null or _circuits.has(circuit):
		return
	_circuits[circuit] = CircuitIncome.new()
	reseat(circuit)


## Snaps every ghost of [param circuit] back to its i/N offset with its ladder back at rung 1, and
## re-reads the circuit's current ghost line and income_ghost_count from disk. Called on
## registration (world load), on an income ghost count change (the dev keys), and on a promoted
## ghost line (forwarded in by race.gd). Deferring the ghost-line case to the next world load would
## keep paying the old, worse rate for an unbounded stretch of a session.
func reseat(circuit: Circuit) -> void:
	var income: CircuitIncome = _circuits.get(circuit)
	if circuit == null or income == null:
		return

	var ghost_line: GhostLine = _load_ghost_line(circuit)
	income.positions = ghost_line.positions if ghost_line != null else PackedVector3Array()
	income.yaws = ghost_line.yaws if ghost_line != null else PackedFloat32Array()
	income.crossings = ghost_line.checkpoint_samples if ghost_line != null else PackedInt32Array()
	income.base_value = circuit.base_checkpoint_value

	var loadout: CircuitLoadout = LoadoutHolder.for_circuit(circuit)
	var count: int = loadout.income_ghost_count
	income.ghosts.clear()
	# A circuit with no ghost line (or too short a one) has nowhere to run a ghost — no error, no
	# special case, exactly as there are no boost ghosts before any Run has completed.
	if income.positions.size() >= 2:
		for i in count:
			income.ghosts.append(IncomeGhostSweep.seat(i, count, income.positions, income.crossings))

	income.earned_since_reseat = 0.0
	income.elapsed_since_reseat = 0.0


## The circuit-local pose of every income ghost currently running [param circuit], in ghost order —
## consumed directly by [class IncomeGhostView], which stands inside the circuit's own coordinate
## frame with no arithmetic needed.
func ghost_transforms(circuit: Circuit) -> Array[Transform3D]:
	var income: CircuitIncome = _circuits.get(circuit)
	var result: Array[Transform3D] = []
	if income == null:
		return result
	for ghost: IncomeGhostSweep.State in income.ghosts:
		result.append(IncomeGhostSweep.pose(ghost, income.positions, income.yaws))
	return result


func _advance(circuit: Circuit, income: CircuitIncome, delta: float) -> void:
	if income.ghosts.is_empty():
		return

	income.elapsed_since_reseat += delta
	for ghost: IncomeGhostSweep.State in income.ghosts:
		var pickups: Array[IncomeGhostSweep.Pickup] = IncomeGhostSweep.advance(
			ghost, income.positions, income.crossings, income.base_value, delta, _sample_rate)
		for p: IncomeGhostSweep.Pickup in pickups:
			income.earned_since_reseat += p.value
			Purse.add_income(p.value)
			pickup.emit(circuit, p.position, p.direction, p.value)


## Mirrors [method RunDirector._load_ghost_line]: a missing or unloadable file is not an error, just
## an empty ghost line.
func _load_ghost_line(circuit: Circuit) -> GhostLine:
	if circuit.ghost_line_path.is_empty() or not ResourceLoader.exists(circuit.ghost_line_path):
		return null
	var ghost_line: GhostLine = load(circuit.ghost_line_path) as GhostLine
	if ghost_line == null:
		push_warning("IncomeRunner: %s did not load as a GhostLine." % circuit.ghost_line_path)
	return ghost_line


## One circuit's whole income simulation: its cached ghost line and checkpoint crossings, its
## running ghosts, and enough history to report an instantaneous rate.
class CircuitIncome extends RefCounted:
	var positions: PackedVector3Array = PackedVector3Array()
	var yaws: PackedFloat32Array = PackedFloat32Array()
	var crossings: PackedInt32Array = PackedInt32Array()
	var base_value: int = 1
	var ghosts: Array[IncomeGhostSweep.State] = []

	## Reset at every reseat, so a stale rate from before a purchase or a promotion does not linger
	## averaged in with the new one.
	var earned_since_reseat: float = 0.0
	var elapsed_since_reseat: float = 0.0

	var income_rate: float:
		get: return earned_since_reseat / elapsed_since_reseat if elapsed_since_reseat > 0.0 else 0.0
