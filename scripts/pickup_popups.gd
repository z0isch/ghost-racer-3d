class_name PickupPopups
extends Node3D

## Floating text you drive through when you take a checkpoint or a clock.
##
## It listens for pickups and knows nothing about totals: not the purse, not the run earnings, not
## the earn rate. Like ClockField, it is purely spatial.
##
## Purely cosmetic, and that is a rule rather than an observation, as it is for ClockSpin. Nothing
## here is read back by any test, the purse or the promotion rule, and a popup that failed to spawn
## would cost only the feedback. The moment one is load-bearing, the value it displays has two
## owners.
##
## Each popup is a Label3D spawned as a child of this node and freed by its own tween. No pool and
## no cap: at 0.8 s a live one is a rare handful of nodes.
##
## No reference to Kart of any kind: which way "ahead" is arrives with the pickup report itself
## ([signal RunDirector.checkpoint_paid]/[signal ClockField.clock_taken]'s direction argument),
## because out in the open world a pickup can come from an income ghost with no kart involved at
## all. That is what lets this one node serve both a race's pickups and the open world's.

## checkpoint_paid → "$12", money green.
## wrap_bonus_paid → "+10s", clock_color — a wrap bonus is a time award, not a checkpoint payout.
@export var director_path: NodePath
## clock_taken → "+10s", pointedly not green.
@export var clock_field_path: NodePath
## hazard_hit → "+2s", for the bonus a hit pays on trial — its own colour, not clock_color, so a
## run-clock popup and a hazard's own never read as the same pickup. A hop pays nothing and pops
## nothing up.
@export var hazard_ghost_field_path: NodePath
## slipstream_hit → "+2s", its own colour so a catch never reads as a hazard's own bonus.
@export var slipstream_ghost_field_path: NodePath

## How far in front of the pickup the text appears, along the pickup's own travel direction: far
## enough that you drive through it, close enough that it still belongs to the pickup you took. At
## racing speed a metre is most of a chassis length ahead, and much more reads as belonging to the
## next pickup.
@export var lead_distance: float = 1.0

## How far the text drifts upward over its life, in metres.
@export var rise: float = 1.5

## Seconds from spawn to freed. Rise and fade run in parallel over exactly this, so the text is
## fully faded at the moment it is released.
@export var lifetime: float = 0.8

## The money green, shared with the purse readout: the popup and the total it feeds are connected by
## colour rather than by an arrow.
@export var money_color: Color = Color(0.29, 0.93, 0.42)

## The clock's own colour, deliberately not green: green is the purse's, and a clock is not money
## (CONTEXT.md's **Pickup popup**). Blue-white, apart from the run clock's plain white and the
## final-seconds urgency red already spoken for elsewhere on screen.
@export var clock_color: Color = Color(0.4, 0.75, 1.0)

## The hazard bonus's own colour: not a clock, and not the hazard ghost's own red either — a bright
## lime so "+2s" for a hazard never gets mistaken for either.
@export var hazard_color: Color = Color(0.6, 1.0, 0.2)

## The slipstream catch's own colour — green, matching the ghost itself (CONTEXT.md's **Pickup
## popup**, "tied together by colour"), and apart from money_color so a catch's seconds are never
## mistaken for a checkpoint's dollars.
@export var slipstream_color: Color = Color(0.15, 0.85, 0.35)

## With [member pixel_size], sizes the text in metres rather than pixels: 64 * 0.005 = 0.32 m tall,
## about half the height of the 0.6 m disc it came from.
@export var font_size: int = 64
@export var pixel_size: float = 0.005


func _ready() -> void:
	var director: RunDirector = get_node_or_null(director_path) as RunDirector
	if director != null:
		director.checkpoint_paid.connect(_on_checkpoint_paid)
		director.wrap_bonus_paid.connect(_on_clock_taken)
	else:
		push_warning("PickupPopups: no RunDirector — no checkpoint feedback.")

	var clock_field: ClockField = get_node_or_null(clock_field_path) as ClockField
	if clock_field != null:
		clock_field.clock_taken.connect(_on_clock_taken)
	else:
		push_warning("PickupPopups: no ClockField — no clock feedback.")

	var hazard_field: HazardGhostField = get_node_or_null(hazard_ghost_field_path) as HazardGhostField
	if hazard_field != null:
		# On trial alongside HazardGhostField.hit_time_bonus's own payout: a hit is the only way a
		# hazard pays anything, so it is the only thing that pops up here.
		hazard_field.hazard_hit.connect(_on_hazard_hit)

	var slipstream_field: SlipstreamGhostField = (
		get_node_or_null(slipstream_ghost_field_path) as SlipstreamGhostField)
	if slipstream_field != null:
		slipstream_field.slipstream_hit.connect(_on_slipstream_hit)


func _on_checkpoint_paid(value: int, pickup_position: Vector3, direction: Vector3) -> void:
	_spawn("$%d" % value, money_color, pickup_position, direction)


func _on_clock_taken(seconds: float, pickup_position: Vector3, direction: Vector3) -> void:
	_spawn("+%ds" % roundi(seconds), clock_color, pickup_position, direction)


func _on_hazard_hit(seconds: float, pickup_position: Vector3, direction: Vector3) -> void:
	_spawn("+%ds" % roundi(seconds), hazard_color, pickup_position, direction)


func _on_slipstream_hit(seconds: float, pickup_position: Vector3, direction: Vector3) -> void:
	_spawn("+%ds" % roundi(seconds), slipstream_color, pickup_position, direction)


## One popup per pickup, with no stacking logic. Sweeping three checkpoints in half a second leaves
## three separate labels standing in space, reading as a trail of income along the line you took.
func _spawn(text: String, color: Color, pickup_position: Vector3, direction: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.modulate = color
	label.font_size = font_size
	label.pixel_size = pixel_size
	# Required, not decoration: the popup is beside you as you pass it, and text read edge-on is
	# invisible.
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)

	var spawn: Vector3 = pickup_position + direction * lead_distance
	label.global_position = spawn

	# One tween owning the whole life, parented to the label so a popup freed for any other reason
	# takes its tween with it.
	var tween: Tween = label.create_tween()
	tween.set_parallel(true)
	# Label3D outlines carry a separate colour; a fade that missed it would leave a black ghost of
	# the number in the air.
	@warning_ignore_start("return_value_discarded")
	tween.tween_property(label, "global_position:y", spawn.y + rise, lifetime)
	tween.tween_property(label, "modulate:a", 0.0, lifetime)
	tween.tween_property(label, "outline_modulate:a", 0.0, lifetime)
	tween.chain().tween_callback(label.queue_free)
	@warning_ignore_restore("return_value_discarded")
