class_name PickupPopups
extends Node3D

## Floating money you drive through when you take a coin.
##
## It listens for pickups and knows nothing about totals: not the purse, not the lap earnings, not
## the earn rate. Like CoinField, it is purely spatial.
##
## Purely cosmetic, and that is a rule rather than an observation, as it is for CoinSpin. Nothing
## here is read back by the pickup test, the purse or the promotion rule, and a popup that failed to
## spawn would cost only the feedback. The moment one is load-bearing, the value it displays has two
## owners.
##
## Each popup is a Label3D spawned as a child of this node and freed by its own tween. No pool and
## no cap: at 0.8 s a live one is a rare handful of nodes.
##
## No reference to Kart of any kind: which way "ahead" is arrives with the pickup report itself
## ([signal CoinField.coin_taken]'s direction argument), because out in the open world a pickup can
## come from an income ghost with no kart involved at all. That is what lets this one node serve
## both a race's pickups and the open world's.

## The coin field whose pickups become popups. The position on `coin_taken` is the coin marker's
## own — the popup traces where the coins were, not where the kart happened to be.
@export var coin_field_path: NodePath

## How far in front of the coin the text appears, along the pickup's own travel direction: far
## enough that you drive through it, close enough that it still belongs to the coin you took. At
## racing speed a metre is most of a chassis length ahead, and much more reads as belonging to the
## next coin.
@export var lead_distance: float = 1.0

## How far the text drifts upward over its life, in metres.
@export var rise: float = 1.5

## Seconds from spawn to freed. Rise and fade run in parallel over exactly this, so the text is
## fully faded at the moment it is released.
@export var lifetime: float = 0.8

## The money green, shared with the purse readout: the popup and the total it feeds are connected by
## colour rather than by an arrow.
@export var money_color: Color = Color(0.29, 0.93, 0.42)

## With [member pixel_size], sizes the text in metres rather than pixels: 64 * 0.005 = 0.32 m tall,
## about half the height of the 0.6 m disc it came from.
@export var font_size: int = 64
@export var pixel_size: float = 0.005


func _ready() -> void:
	var coin_field: CoinField = get_node_or_null(coin_field_path) as CoinField
	# A scene without a coin field pops nothing up, which keeps this script runnable outside main.tscn.
	if coin_field == null:
		push_warning("PickupPopups: no CoinField — no pickup feedback.")
		return

	coin_field.coin_taken.connect(_on_coin_taken)


## One popup per pickup, with no stacking logic. Sweeping three coins in half a second leaves three
## separate labels standing in space, reading as a trail of income along the line you took.
func _on_coin_taken(value: int, coin_position: Vector3, direction: Vector3) -> void:
	var label := Label3D.new()
	label.text = "$%d" % value
	label.modulate = money_color
	label.font_size = font_size
	label.pixel_size = pixel_size
	# Required, not decoration: the popup is beside you as you pass it, and text read edge-on is
	# invisible.
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)

	var spawn: Vector3 = coin_position + direction * lead_distance
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
