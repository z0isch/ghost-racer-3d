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

## Grow at the same rate: the two dial down independently in [class Circuit], but the dev keys
## ([method _adjust_spawn_intervals]) treat them as one traffic-thickening knob, since a playtest
## almost always wants both sides busier or both quieter together rather than retuning them one at
## a time.
const DEV_SPAWN_INTERVAL_STEP_SECONDS: float = 1.0

## m/s of Tune awarded per record-taking Run (CONTEXT.md's **Tune**). Clamped at the award site to
## the ceiling's remaining headroom, so a circuit reaches a full Tune in a fixed number of awarding
## Runs and awards nothing thereafter.
const TUNE_AWARD: float = 0.5

@export var kart_path: NodePath = NodePath("Kart")
@export var run_director_path: NodePath = NodePath("RunDirector")
@export var countdown_hud_path: NodePath = NodePath("CountdownHud")
@export var clock_field_path: NodePath = NodePath("ClockField")
@export var boost_ghost_field_path: NodePath = NodePath("BoostGhostField")
@export var hazard_ghost_field_path: NodePath = NodePath("HazardGhostField")
@export var slipstream_ghost_field_path: NodePath = NodePath("SlipstreamGhostField")

var _kart: Kart
var _countdown_hud: CountdownHud
var _director: RunDirector
var _exiting: bool = false
var _circuit: Circuit

## Resolved once in _enter_tree, alongside the ghost line, and held here so the completion handler
## can reach them without re-resolving from [autoload LoadoutHolder] itself — see the comment on
## their resolution below.
var _loadout: CircuitLoadout
var _save_loadout: Callable


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
	_director = run_director

	# Resolved once, in the same breath as the ghost line, and pushed into the clock field and the
	# two ghost fields — so those fields go on taking their counts from whoever owns them rather
	# than each growing its own dependency on [autoload LoadoutHolder] (CONTEXT.md's **Loadout
	# holder**). Held on the node (not just local) so _on_run_completed can reach them too.
	var loadout: CircuitLoadout = LoadoutHolder.for_circuit(circuit)
	var save_loadout: Callable = LoadoutHolder.save.bind(circuit)
	_loadout = loadout
	_save_loadout = save_loadout

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

	# Seeded here rather than in _ready: this Tune is permanent and circuit-scoped, not Run state,
	# so nothing has to remember to re-seed it on the way into the next Run.
	var kart: Kart = get_node_or_null(kart_path) as Kart
	if kart != null:
		kart.tune = loadout.tune


func _ready() -> void:
	_kart = get_node_or_null(kart_path) as Kart
	_countdown_hud = get_node_or_null(countdown_hud_path) as CountdownHud

	# Connected here rather than in _enter_tree, deliberately: _ready propagates bottom-up, so this
	# root's own _ready runs after every child's, including CountdownHud's — which connects its own
	# run_completed handler from its _ready. That ordering is load-bearing for the Tune award: this
	# handler pushes the award to CountdownHud.set_tune_award, and CountdownHud's own handler clears
	# any award left over from the Run before. Connecting here, after CountdownHud has already
	# connected, is what guarantees this handler's push lands after that clear rather than before it.
	if _director != null:
		_director.run_completed.connect(_on_run_completed)


func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("dev_spawn_interval_more"):
		_adjust_spawn_intervals(DEV_SPAWN_INTERVAL_STEP_SECONDS)
	if Input.is_action_just_pressed("dev_spawn_interval_fewer"):
		_adjust_spawn_intervals(-DEV_SPAWN_INTERVAL_STEP_SECONDS)

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
##
## The Tune award lives in this same handler rather than in RunDirector (CONTEXT.md's **Tune**):
## RunDirector owns Run state and must not learn about [autoload LoadoutHolder], where this scene
## already holds the circuit's loadout and its save callable. Awarded only when the Run took the
## record AND had an incumbent pace ghost to take it from — a circuit's first completed Run is a
## record with nothing on the track yet, so it beats nothing and earns nothing.
func _on_run_completed(_run_time: float, is_record: bool) -> void:
	if is_record and _kart != null and _director != null and _director.raced_ghost != null:
		var headroom: float = _kart.tune_headroom
		var awarded: float = minf(TUNE_AWARD, headroom - _loadout.tune)
		if awarded > 0.0:
			_loadout.tune += awarded
			_save_loadout.call()
			_kart.tune = _loadout.tune
			if _countdown_hud != null:
				_countdown_hud.set_tune_award(awarded)

	if is_record:
		IncomeRunner.reseat(_circuit)


## Raises or lowers both spawn intervals by [param delta_seconds] and pushes the result straight
## into the live fields, for HazardGhostField._adjust_ghost_count's identical reason: the door the
## dev keys go through is the field's own exported property, not the [class Circuit] alone, since
## _enter_tree only reads the circuit once, at race setup. Floored at 0.0, spawn_interval_seconds's
## own "0.0 (or below) disables thickening" meaning: a negative interval would be a distinct,
## unintended state rather than just "more thickening than 0.0".
func _adjust_spawn_intervals(delta_seconds: float) -> void:
	_circuit.hazard_spawn_interval_seconds = maxf(
		_circuit.hazard_spawn_interval_seconds + delta_seconds, 0.0)
	_circuit.slipstream_spawn_interval_seconds = maxf(
		_circuit.slipstream_spawn_interval_seconds + delta_seconds, 0.0)

	var hazard_field: HazardGhostField = get_node_or_null(hazard_ghost_field_path) as HazardGhostField
	if hazard_field != null:
		hazard_field.spawn_interval_seconds = _circuit.hazard_spawn_interval_seconds

	var slipstream_field: SlipstreamGhostField = (
		get_node_or_null(slipstream_ghost_field_path) as SlipstreamGhostField)
	if slipstream_field != null:
		slipstream_field.spawn_interval_seconds = _circuit.slipstream_spawn_interval_seconds
