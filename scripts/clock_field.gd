class_name ClockField
extends Node

## Owner of the clock field: where the clocks are, which are currently taken, and the swept test
## that takes them. The clocks themselves are inert Marker3Ds under the circuit's Clocks node;
## everything mutable about them lives here.
##
## Purely spatial, the boundary CONTEXT.md records under **Clock field**: it emits
## [signal clock_taken] and knows nothing about who listens — not the Run budget it extends, not
## the Run clock, not the earn rate. Nothing is totalled here.
##
## Restores whole at every countdown and at every wrap, the same moments the boost and hazard ghost
## fields restore on: a clock taken on one lap is offered again on the next.

## One pickup, the instant it is taken. The value is the clock's own, read from the marker's
## metadata rather than assumed to be any particular number, in *seconds* rather than money. The
## position is the clock marker's origin: this node is the only one that knows where a clock was,
## and the pickup popup spawns from it. The direction is the swept segment's own travel direction —
## "which way is ahead" arrives with the pickup rather than being looked up afterwards from a kart,
## which is what lets the same signal serve a pickup with no kart involved at all (an income ghost's,
## in the open world).
##
## A listener that wants only the value must connect with [code].unbind(2)[/code]. Godot does not
## drop surplus signal arguments: a one-argument handler connected bare fails at emit time with
## "Method expected 1 argument(s), but called with 3", and since nothing checks a signal's emit
## result the symptom is a Run that silently stops being extendable.
signal clock_taken(seconds: float, position: Vector3, direction: Vector3)

@export var kart_path: NodePath
@export var director_path: NodePath
## The generated Clocks node: one inert Marker3D per clock, in arclength order.
@export var clocks_path: NodePath

## How many of the circuit's authored clocks are live, per the circuit's [CircuitLoadout] — the
## first `k` in authored node order, which is therefore a purchase order rather than an
## arbitrary one. Set by race.gd before [method _ready] runs (CONTEXT.md's **Clock field**).
## Defaults to 0 rather than a large number: an unwired clock field showing every clock would hide
## exactly the bug this feature exists to prevent.
@export var live_clock_count: int = 0

## The circuit's own loadout, for BoostGhostField.loadout's identical reason: the dev keys
## ([method _physics_process]) raise or lower its clock_count directly rather than only this
## field's own copy of it. Set by race.gd alongside [member live_clock_count] itself. Left null,
## the dev keys fall back to editing [member live_clock_count] alone.
var loadout: CircuitLoadout = null
## Persists [member loadout] after a dev-key change, for BoostGhostField.save_loadout's identical
## reason. Set by race.gd, bound to the resolved Circuit.
var save_loadout: Callable = Callable()

## Generously larger than the 0.6 m disc. The pickup is a horizontal test on banked and cresting
## road, where a clock's apparent position and its marker origin differ by up to a third of a metre;
## a radius smaller than the clock looks reads as theft. Reached from anywhere on the kart's own
## capsule, not from a point at its centre — a clock brushed by the front wing is taken.
@export var pickup_radius: float = 1.2

## Metres of vertical gap, beyond the horizontal sweep test, that still counts as the same road.
## [Hitbox] ignores height entirely so a clock up a banked sweeper or on a crest stays collectable,
## but that same leniency lets a clock be taken from a stretch of road that merely passes underneath
## or beside it at a different height. This caps how far that leniency reaches.
@export var max_vertical_gap: float = 5.0

## Below this planar speed the swept segment's own direction is noise (a near-stationary kart, e.g.
## parked on a clock during the countdown) and the kart's heading is used instead — the same
## fallback [class PickupPopups] used to compute for itself before this moved here.
const MIN_MEANINGFUL_SPEED: float = 1.0

## Bump/bleed a clock also banks as a boost charge, on top of the seconds it pays into the Run
## budget — BoostGhostField.bump/bleed's own default, so a clock's charge feels like the same
## pickup rather than a weaker or stronger one. Stored and spent through [method
## Kart.add_boost_charge] exactly as a boost ghost's is: banked rather than fired immediately,
## subject to the same [member KartTuning.store_boost_charges] switch.
@export var bump: float = 10.0
## m/s^2 the overspeed comes back off at, once the charge is spent — BoostGhostField.bleed's own
## default.
@export var bleed: float = 5.0

var _kart: Kart
var _director: RunDirector
var _clocks: Array[Clock] = []
var _last_kart_centre: Vector3 = Vector3.ZERO
var _last_kart_yaw: float = 0.0
var _has_last_kart_pose: bool = false
## Built once and re-aimed every frame rather than rebuilt, for [Hitbox.Sweep]'s own reason.
var _sweep := Hitbox.Sweep.new()


func _ready() -> void:
	_kart = get_node_or_null(kart_path) as Kart
	_director = get_node_or_null(director_path) as RunDirector

	if _director != null:
		_director.countdown_started.connect(_on_countdown_started)
		_director.wrapped.connect(_on_wrapped)

	_resolve_clocks()


## Sweeps the segment the kart travelled this frame against every untaken clock. Deferred because
## the director runs at the head of the physics frame (process_physics_priority = -100) and the
## kart moves after it: the position the kart finishes the frame at only exists after the flush.
##
## The dev inputs live here, not gated on phase, for BoostGhostField._physics_process's identical
## reason: the field owns the count, so pressing the dev keys before any Run has completed must
## still raise the count the next Run opens with.
func _physics_process(_delta: float) -> void:
	if _kart != null and _director != null and _director.phase == RunDirector.RunPhase.RACING:
		_sweep_clocks.call_deferred()

	if Input.is_action_just_pressed("dev_clock_more"):
		_adjust_live_clock_count(1)
	if Input.is_action_just_pressed("dev_clock_fewer"):
		_adjust_live_clock_count(-1)


## Raises or lowers [member live_clock_count] by [param delta], for
## BoostGhostField._adjust_ghost_count's identical reason and identical shape — the loadout's
## clock_count is the thing raised when a loadout is wired up, then [method _resolve_clocks] is
## re-run so the change is visible immediately rather than waiting for the next countdown, and the
## change is saved via [member save_loadout]. Without a loadout, [member live_clock_count] alone
## is edited.
func _adjust_live_clock_count(delta: int) -> void:
	if loadout == null:
		live_clock_count += delta
		_resolve_clocks()
		return

	loadout.clock_count += delta
	live_clock_count = loadout.clock_count
	_resolve_clocks()
	if save_loadout.is_valid():
		save_loadout.call()


## Which way "ahead" is for a pickup swept between [param previous] and [param position]: the
## segment's own travel direction, flattened to the horizontal so a popup on the crest or the banked
## sweeper rises out of the road rather than along the climb. Falls back to [param kart_basis]'s own
## heading below [constant MIN_MEANINGFUL_SPEED], for the near-stationary case the segment's
## direction cannot answer. Static and shared with RunDirector's checkpoint payments — "which way is
## ahead" means the same thing for both, and one segment-to-direction seam is enough for both to
## call.
static func sweep_direction(previous: Vector3, position: Vector3, kart_basis: Basis) -> Vector3:
	var travel := Vector3(position.x - previous.x, 0.0, position.z - previous.z)
	var min_segment_length: float = MIN_MEANINGFUL_SPEED / Engine.physics_ticks_per_second
	if travel.length() >= min_segment_length:
		return travel.normalized()

	var heading: Vector3 = -kart_basis.z
	return Vector3(heading.x, 0.0, heading.z).normalized()


## Resolved once, as RunDirector._resolve_checkpoints does, so the physics step performs no node
## lookups. A scene without a generated Clocks node has no clocks, which keeps this script runnable
## outside main.tscn.
##
## Only the first [member live_clock_count] markers, in authored node order, become clocks — the
## rest are hidden here and never appended to [member _clocks] at all, so an unbought clock cannot
## be swept by [method _sweep_clocks] or resurrected by [method _on_countdown_started].
## [member live_clock_count] is clamped to the number of markers actually authored: buying past a
## circuit's total is impossible by construction rather than by silent overflow.
##
## Explicitly re-shows every included marker rather than assuming it already is: called again from
## [method _adjust_live_clock_count], where a marker just bought back in was left hidden by an
## earlier, smaller live_clock_count.
func _resolve_clocks() -> void:
	var root: Node3D = get_node_or_null(clocks_path) as Node3D
	if root == null:
		push_warning("ClockField: no Clocks node — nothing can be collected.")
		return

	var markers: Array[Node3D] = []
	for child: Node in root.get_children():
		var marker: Node3D = child as Node3D
		if marker != null:
			markers.append(marker)

	var live_count: int = clampi(live_clock_count, 0, markers.size())
	var found: Array[Clock] = []
	for i in markers.size():
		var marker: Node3D = markers[i]
		if i >= live_count:
			marker.visible = false
			continue
		marker.visible = true
		var clock := Clock.new()
		clock.node = marker
		clock.origin = marker.global_position
		# Assigned straight into the typed field, not via int()/float(): metadata is a Variant, and
		# a hard cast is an error under this project's warnings table.
		clock.seconds = marker.get_meta("seconds", 10.0)
		found.append(clock)

	_clocks = found


func _sweep_clocks() -> void:
	# Re-checked: the director's sweep is queued first and can end the Run inside this same flush.
	# Without the guard a clock taken on the finishing frame lands in the next Run's budget.
	if _director.phase != RunDirector.RunPhase.RACING:
		return

	var centre: Vector3 = _kart.hitbox_centre
	var yaw: float = _kart.hitbox_yaw
	# The first Racing frame after a teleport records a position and tests nothing: a segment
	# spanning the teleport would sweep half the circuit.
	if not _has_last_kart_pose:
		_last_kart_centre = centre
		_last_kart_yaw = yaw
		_has_last_kart_pose = true
		return

	var previous: Vector3 = _last_kart_centre
	var previous_yaw: float = _last_kart_yaw
	_last_kart_centre = centre
	_last_kart_yaw = yaw
	_sweep.moved(previous, previous_yaw, centre, yaw,
		_kart.hitbox_half_length, _kart.hitbox_half_width)
	var direction: Vector3 = sweep_direction(previous, centre, _kart.global_transform.basis)

	for clock: Clock in _clocks:
		if clock.taken:
			continue
		# A clock is round, so both of its extents are the one radius and its capsule collapses to
		# the disc it is drawn as. The kart's, by then, has not.
		if not _sweep.takes(clock.origin, 0.0, pickup_radius, pickup_radius):
			continue
		if absf(centre.y - clock.origin.y) > max_vertical_gap:
			continue
		clock.taken = true
		clock.node.visible = false
		_kart.add_boost_charge(bump, bleed)
		clock_taken.emit(clock.seconds, clock.origin, direction)


## Restores the field whole at every countdown — scene load, Run completion and abort alike — so
## each Run opens on an identical maximum. Driven by the director's signal rather than by watching
## the phase: the teleport and the restore are the same moment.
func _on_countdown_started() -> void:
	_has_last_kart_pose = false
	_respawn_clocks()


## Restores the field whole at every wrap too ([signal RunDirector.wrapped]), the same as the boost
## and hazard ghost fields: a clock taken on one lap is offered again on the next rather than the
## field thinning out to nothing over a long Run. No teleport happens on a wrap, so unlike [method
## _on_countdown_started] this leaves [member _has_last_kart_pose] alone — the swept segment
## carries straight through the wrap.
func _on_wrapped() -> void:
	_respawn_clocks()


func _respawn_clocks() -> void:
	for clock: Clock in _clocks:
		clock.taken = false
		clock.node.visible = true


## Everything a Rewind must put back, as plain data: each clock's own taken flag and the swept
## previous-pose the field tracks between frames. Not the clocks' node references — [member
## Clock.node] stays put; only [member Clock.taken] and its derived visibility change.
func capture_state() -> Dictionary:
	var taken: PackedByteArray = PackedByteArray()
	taken.resize(_clocks.size())
	for i in _clocks.size():
		taken[i] = 1 if _clocks[i].taken else 0
	return {
		"taken": taken,
		"last_kart_centre": _last_kart_centre,
		"last_kart_yaw": _last_kart_yaw,
		"has_last_kart_pose": _has_last_kart_pose,
	}


## Puts back exactly what [method capture_state] produced. A clock's node.visible is derived from
## its taken flag here rather than carried separately, since the two never disagree ([method
## _sweep_clocks] sets both in the same breath).
func restore_state(state: Dictionary) -> void:
	var taken: PackedByteArray = state["taken"]
	for i in mini(taken.size(), _clocks.size()):
		var clock: Clock = _clocks[i]
		clock.taken = taken[i] != 0
		clock.node.visible = not clock.taken
	_last_kart_centre = state["last_kart_centre"]
	_last_kart_yaw = state["last_kart_yaw"]
	_has_last_kart_pose = state["has_last_kart_pose"]


## One clock, resolved once from its marker. RefCounted for the same reason RunDirector.Checkpoint
## is: built in _ready, never allocated in the physics step. The origin is the centre of the disc.
class Clock extends RefCounted:
	var node: Node3D = null
	var origin: Vector3 = Vector3.ZERO
	var seconds: float = 10.0
	var taken: bool = false
