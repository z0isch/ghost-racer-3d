class_name PurseLink
extends Node

## Connects a scene's CoinField to the Purse autoload.
##
## CoinField stays ignorant of who consumes its pickups (CONTEXT.md, **Coin field**) — it cannot
## itself reach across to an autoload without that ignorance costing something, so a scene that
## wants its coins to pay places one of these instead.

@export var coin_field_path: NodePath


func _ready() -> void:
	var coin_field: CoinField = get_node_or_null(coin_field_path) as CoinField
	if coin_field == null:
		push_warning("PurseLink: no CoinField — nothing can be earned.")
		return

	# unbind(1) drops coin_taken's position argument, which the purse has no use for. Godot does
	# not drop surplus arguments by itself: connected bare, every pickup would fail at emit time.
	coin_field.coin_taken.connect(_on_coin_taken.unbind(1))


func _on_coin_taken(value: int) -> void:
	Purse.add(value)
