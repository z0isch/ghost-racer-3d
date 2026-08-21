class_name CoinField
extends Node

## Owner of the coin field: where the coins are, which are currently taken, and the swept test that
## takes them. The coins themselves are inert Marker3Ds under the circuit's Coins node; everything
## mutable about them lives here.
##
## Purely spatial, the boundary CONTEXT.md records under **Coin field**: it emits
## [signal coin_taken] and knows nothing about who listens — not the purse it feeds, not the lap
## earnings, not the earn rate. Nothing is totalled here.

## One pickup, the instant it is taken. The value is the coin's own, read from the marker's
## metadata rather than assumed to be 1. The position is the coin marker's origin: this node is the
## only one that knows where a coin was, and the pickup popup spawns from it. The direction is the
## swept segment's own travel direction — "which way is ahead" arrives with the pickup rather than
## being looked up afterwards from a kart, which is what lets the same signal serve a pickup with no
## kart involved at all (an income ghost's, in the open world).
##
## A listener that wants only the value must connect with [code].unbind(2)[/code]. Godot does not
## drop surplus signal arguments: a one-argument handler connected bare fails at emit time with
## "Method expected 1 argument(s), but called with 3", and since nothing checks a signal's emit
## result the symptom is a purse that silently stops earning.
signal coin_taken(value: int, position: Vector3, direction: Vector3)

@export var kart_path: NodePath
@export var director_path: NodePath
## The generated Coins node: one inert Marker3D per coin, in arclength order.
@export var coins_path: NodePath

## How many of the circuit's authored coins are live, per the circuit's [CircuitLoadout] — the
## first `k` in authored node order, which is therefore a purchase order rather than an
## arbitrary one. Set by race.gd before [method _ready] runs (CONTEXT.md's **Coin field**).
## Defaults to 0 rather than a large number: an unwired coin field showing every coin would hide
## exactly the bug this feature exists to prevent.
@export var live_coin_count: int = 0

## Generously larger than the 0.6 m disc. The pickup is a horizontal test on banked and cresting
## road, where a coin's apparent position and its marker origin differ by up to a third of a metre;
## a radius smaller than the coin looks reads as theft.
@export var pickup_radius: float = 1.2

## Metres of vertical gap, beyond the horizontal sweep test, that still counts as the same road.
## segment_takes_coin ignores height entirely so a coin up a banked sweeper or on a crest stays
## collectable, but that same leniency lets a coin be taken from a stretch of road that merely
## passes underneath or beside it at a different height. This caps how far that leniency reaches.
@export var max_vertical_gap: float = 5.0

## Below this planar speed the swept segment's own direction is noise (a near-stationary kart, e.g.
## parked on a coin during the countdown) and the kart's heading is used instead — the same fallback
## [class PickupPopups] used to compute for itself before this moved here.
const MIN_MEANINGFUL_SPEED: float = 1.0

var _kart: Kart
var _director: RunDirector
var _coins: Array[Coin] = []
var _last_kart_position: Vector3 = Vector3.ZERO
var _has_last_kart_position: bool = false


func _ready() -> void:
	_kart = get_node_or_null(kart_path) as Kart
	_director = get_node_or_null(director_path) as RunDirector

	if _director != null:
		_director.countdown_started.connect(_on_countdown_started)

	_resolve_coins()


## Sweeps the segment the kart travelled this frame against every untaken coin. Deferred because
## the director runs at the head of the physics frame (process_physics_priority = -100) and the
## kart moves after it: the position the kart finishes the frame at only exists after the flush.
func _physics_process(_delta: float) -> void:
	if _kart == null or _director == null or _director.phase != RunDirector.RunPhase.RACING:
		return
	_sweep_coins.call_deferred()


## Where every coin on the circuit stands, in arclength order. Built per call rather than kept
## beside [member _coins]: a second copy of the placement is a second thing to keep true, and the
## only caller reads it once per countdown.
##
## Taken-ness is deliberately not filtered. The callers place things against the field's shape, and
## the shape is what the countdown restores — a coin that was taken last Run is standing again by
## the time anything acts on this.
func coin_origins() -> PackedVector3Array:
	var origins := PackedVector3Array()
	for coin: Coin in _coins:
		origins.append(coin.origin)
	return origins


## Horizontal distance from a swept segment to a coin. Static and free of node access: it is the
## seam the geometry suite tests, and a TestCase is a RefCounted that cannot touch the scene tree.
##
## Y is ignored entirely, which is what lets a coin sit up the banked sweeper or out on the crest
## and still be collectable from the road it belongs to.
##
## The clamp to [0, 1] makes this a segment rather than an infinite line, and covers the degenerate
## zero-length case: a stationary kart inside the radius still collects.
static func segment_takes_coin(
	segment_start: Vector3, segment_end: Vector3, coin_position: Vector3, radius: float
) -> bool:
	var start := Vector2(segment_start.x, segment_start.z)
	var end := Vector2(segment_end.x, segment_end.z)
	var coin := Vector2(coin_position.x, coin_position.z)

	var travelled := end - start
	var length_squared := travelled.length_squared()
	var along := 0.0
	if length_squared > 0.0:
		along = clampf((coin - start).dot(travelled) / length_squared, 0.0, 1.0)

	return (start + travelled * along).distance_squared_to(coin) <= radius * radius


## Resolved once, as RunDirector._resolve_checkpoints does, so the physics step performs no node
## lookups. A scene without a generated Coins node has no coins, which keeps this script runnable
## outside main.tscn.
##
## Only the first [member live_coin_count] markers, in authored node order, become coins — the
## rest are hidden here and never appended to [member _coins] at all, so an unbought coin cannot be
## swept by [method _sweep_coins], resurrected by [method _on_countdown_started], or handed to a
## boost ghost by [method coin_origins]. [member live_coin_count] is clamped to the number of
## markers actually authored: buying past a circuit's total is impossible by construction rather
## than by silent overflow.
func _resolve_coins() -> void:
	var root: Node3D = get_node_or_null(coins_path) as Node3D
	if root == null:
		push_warning("CoinField: no Coins node — nothing can be collected.")
		return

	var markers: Array[Node3D] = []
	for child: Node in root.get_children():
		var marker: Node3D = child as Node3D
		if marker != null:
			markers.append(marker)

	var live_count: int = clampi(live_coin_count, 0, markers.size())
	var found: Array[Coin] = []
	for i in markers.size():
		var marker: Node3D = markers[i]
		if i >= live_count:
			marker.visible = false
			continue
		var coin := Coin.new()
		coin.node = marker
		coin.origin = marker.global_position
		# Assigned straight into the typed field, not via int(): metadata is a Variant, and
		# int(Variant) is a hard error under this project's warnings table.
		coin.value = marker.get_meta("value", 1)
		found.append(coin)

	_coins = found


func _sweep_coins() -> void:
	# Re-checked: the director's sweep is queued first and can end the Run inside this same flush.
	# Without the guard a coin taken on the finishing frame lands in the next Run's earnings.
	if _director.phase != RunDirector.RunPhase.RACING:
		return

	var position: Vector3 = _kart.global_position
	# The first Racing frame after a teleport records a position and tests nothing: a segment
	# spanning the teleport would sweep half the circuit.
	if not _has_last_kart_position:
		_last_kart_position = position
		_has_last_kart_position = true
		return

	var previous: Vector3 = _last_kart_position
	_last_kart_position = position
	var direction: Vector3 = _sweep_direction(previous, position)

	for coin: Coin in _coins:
		if coin.taken:
			continue
		if not segment_takes_coin(previous, position, coin.origin, pickup_radius):
			continue
		if absf(position.y - coin.origin.y) > max_vertical_gap:
			continue
		coin.taken = true
		coin.node.visible = false
		coin_taken.emit(coin.value, coin.origin, direction)


## Which way "ahead" is for a pickup swept between [param previous] and [param position]: the
## segment's own travel direction, flattened to the horizontal so a popup on the crest or the banked
## sweeper rises out of the road rather than along the climb. Falls back to the kart's own heading
## below [constant MIN_MEANINGFUL_SPEED], for the near-stationary case the segment's direction
## cannot answer.
func _sweep_direction(previous: Vector3, position: Vector3) -> Vector3:
	var travel := Vector3(position.x - previous.x, 0.0, position.z - previous.z)
	var min_segment_length: float = MIN_MEANINGFUL_SPEED / Engine.physics_ticks_per_second
	if travel.length() >= min_segment_length:
		return travel.normalized()

	var heading: Vector3 = -_kart.global_transform.basis.z
	return Vector3(heading.x, 0.0, heading.z).normalized()


## Restores the field whole at every countdown — scene load, lap completion and abort alike — so
## each lap is offered an identical maximum, without which two laps' earn rates are not comparable.
## Driven by the director's signal rather than by watching the phase: the teleport and the restore
## are the same moment.
func _on_countdown_started() -> void:
	_has_last_kart_position = false
	for coin: Coin in _coins:
		coin.taken = false
		coin.node.visible = true


## One coin, resolved once from its marker. RefCounted for the same reason RunDirector.Checkpoint
## is: built in _ready, never allocated in the physics step. The origin is the centre of the disc.
class Coin extends RefCounted:
	var node: Node3D = null
	var origin: Vector3 = Vector3.ZERO
	var value: int = 1
	var taken: bool = false
