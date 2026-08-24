extends Node3D

## Instances the circuit this race is run on as a child named "Circuit", at identity, reading
## which circuit that is from [member CircuitSession.pending_circuit] — the [class Circuit] the
## world's entry trigger carried across the scene swap.
##
## Done in [method _enter_tree] rather than authored into the scene: _enter_tree fires top-down as
## a scene is added to the tree, and this node's fires before any of its siblings' _ready — in
## particular before RunDirector._ready resolves NodePaths like "../Circuit/StartLine" and reads
## its ghost_line_path. Since this node is already inside the tree by the time its own _enter_tree
## runs, add_child here cascades the new child's _enter_tree immediately, ahead of the siblings
## still waiting their turn in the same top-down pass — and get_node("RunDirector") already
## resolves, because the whole scene's node structure exists before any of it enters the tree.
##
## At identity: [member GhostLine.positions] are recorded in the circuit's own coordinates, and any
## transform applied here would invalidate every recorded ghost line. Where a circuit stands in the
## world is main.tscn's own concern, authored into that circuit instance's transform there.
##
## Falls back to circuit3 when nothing is pending — running race.tscn directly, outside the
## world's entry flow, still plays a circuit rather than nothing.
##
## Also owns exit_circuit: live in any Run phase, deliberately separate from RunDirector's own
## reset/abort handling. Exiting discards the in-progress Run exactly as an abort does — but there
## is nothing to explicitly discard here, since a Run only ever reaches the ghost line and the
## record earn rate through [method RunDirector.complete_run], and this scene tearing down takes
## the unpromoted recording with it. [autoload CircuitSession]'s return pose was set once, at
## entry, and is left untouched — it is the pose this race is exited back to.

## The whole fallback Circuit, not just its scene: geometry, ghost line and loadout fall back as
## one atomic unit. A Circuit with circuit4's geometry but circuit3's ghost line (or loadout) is
## exactly the "circuit4's geometry running circuit3's recorded line" bug issue 08 found in the
## code this replaced — resolving the three fallback fields independently below could reintroduce
## it.
const FALLBACK_CIRCUIT: Circuit = preload("res://circuits/circuit3.tres")
const WORLD_SCENE_PATH: String = "res://main.tscn"

@export var kart_path: NodePath = NodePath("Kart")
@export var run_director_path: NodePath = NodePath("RunDirector")
@export var clock_field_path: NodePath = NodePath("ClockField")
@export var boost_ghost_field_path: NodePath = NodePath("BoostGhostField")
@export var hazard_ghost_field_path: NodePath = NodePath("HazardGhostField")
@export var slipstream_ghost_field_path: NodePath = NodePath("SlipstreamGhostField")

var _kart: Kart
var _exiting: bool = false
var _circuit: Circuit


func _enter_tree() -> void:
	var pending: Circuit = CircuitSession.pending_circuit
	var have_pending: bool = pending != null and pending.circuit_scene != null
	var circuit: Circuit = pending if have_pending else FALLBACK_CIRCUIT
	_circuit = circuit

	var circuit_node: Node3D = circuit.circuit_scene.instantiate() as Node3D
	circuit_node.name = "Circuit"
	add_child(circuit_node)

	var run_director: RunDirector = get_node_or_null(run_director_path) as RunDirector
	if run_director != null:
		run_director.ghost_line_path = circuit.ghost_line_path
		run_director.run_duration_seconds = circuit.run_duration_seconds
		run_director.base_checkpoint_value = circuit.base_checkpoint_value
		run_director.wrap_bonus_seconds = circuit.wrap_bonus_seconds
		run_director.max_wraps = circuit.max_wraps
		run_director.slipstream_bar_target = circuit.slipstream_bar_target
		# The reverse edge of the wiring this scene already does: it hands the circuit's ghost line
		# to the director, so it is also the natural place to forward a promoted one back out to
		# [autoload IncomeRunner], which sits inside no scene and has no connection of its own to the
		# director. RunDirector must not learn about the runner — it owns Run state and knows nothing
		# about autoloads.
		run_director.run_completed.connect(_on_run_completed)

	# Resolved once, in the same breath as the ghost line, and pushed into the clock field and the
	# two ghost fields — so those fields go on taking their counts from whoever owns them rather
	# than each growing its own dependency on [autoload LoadoutHolder] (CONTEXT.md's **Loadout
	# holder**).
	var loadout: CircuitLoadout = LoadoutHolder.for_circuit(circuit)
	var save_loadout: Callable = LoadoutHolder.save.bind(circuit)

	var clock_field: ClockField = get_node_or_null(clock_field_path) as ClockField
	if clock_field != null:
		clock_field.loadout = loadout
		clock_field.save_loadout = save_loadout
		clock_field.live_clock_count = loadout.clock_count

	var boost_field: BoostGhostField = get_node_or_null(boost_ghost_field_path) as BoostGhostField
	if boost_field != null:
		boost_field.loadout = loadout
		boost_field.save_loadout = save_loadout
		boost_field.ghost_count = loadout.boost_ghost_count

	var hazard_field: HazardGhostField = get_node_or_null(hazard_ghost_field_path) as HazardGhostField
	if hazard_field != null:
		hazard_field.loadout = loadout
		hazard_field.save_loadout = save_loadout
		hazard_field.ghost_count = loadout.hazard_ghost_count
		hazard_field.spawn_interval_seconds = circuit.hazard_spawn_interval_seconds

	var slipstream_field: SlipstreamGhostField = (
		get_node_or_null(slipstream_ghost_field_path) as SlipstreamGhostField)
	if slipstream_field != null:
		slipstream_field.loadout = loadout
		slipstream_field.save_loadout = save_loadout
		slipstream_field.ghost_count = loadout.slipstream_ghost_count
		slipstream_field.spawn_interval_seconds = circuit.slipstream_spawn_interval_seconds


func _ready() -> void:
	_kart = get_node_or_null(kart_path) as Kart


func _physics_process(_delta: float) -> void:
	if _exiting or not Input.is_action_just_pressed("exit_circuit"):
		return

	_exiting = true
	if _kart != null:
		_kart.frozen = true

	# A failed swap fades back into this same race, still running: undo the one-shot latch so
	# exit_circuit is not left permanently dead and the kart is not left permanently frozen.
	var err: Error = await SceneFade.to_scene(get_tree(), WORLD_SCENE_PATH)
	if err != OK:
		_exiting = false
		if _kart != null:
			_kart.frozen = false


## A completed Run that set no record changed nothing this circuit's income ghosts run on; only a
## promotion needs forwarding. The re-seat is invisible when it happens — income ghosts are hidden
## inside a race — so there is no visual cost to snapping it immediately rather than waiting for the
## player to leave.
func _on_run_completed(_run_time: float, is_record: bool) -> void:
	if is_record:
		IncomeRunner.reseat(_circuit)
