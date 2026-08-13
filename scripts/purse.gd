class_name Purse
extends Node

## The session's running money total, and nothing else.
##
## Not an autoload: an autoload earns its global by surviving a scene change, and this game has one
## scene it never reloads.
##
## Not on LapDirector either, a split recorded in CONTEXT.md under **Purse holder**. The director
## owns lap state and clears all of it in _begin_countdown, and a session-scoped total behind a
## per-lap reset eventually gets cleared by accident. Hence what is absent here: no connection to
## countdown_started and no reset path, so no lap boundary can reach in.
##
## The total only ever goes up. Nothing subtracts from it, coins are banked the instant they are
## touched, and an abort costs the abandoned lap its earnings but not its contribution here. It is a
## reward rather than a currency or a score: the pace ghost is promoted on the earn rate, not on
## this, and nothing is won or lost by having more.

## One pickup, banked. Carries the amount for the HUD to flash on, and the new total so a listener
## reacting to the edge does not have to poll in the same breath. The running total for the label
## itself is polled off `total`, matching every other HUD readout in the project.
signal gained(amount: int, total: int)

@export var coin_field_path: NodePath

var _total: int = 0

## Polled by the purse HUD layer each _process, as every other readout in the project is.
var total: int:
	get: return _total


func _ready() -> void:
	var coin_field: CoinField = get_node_or_null(coin_field_path) as CoinField
	# A scene without a coin field earns nothing, which keeps this script runnable outside main.tscn.
	if coin_field == null:
		push_warning("Purse: no CoinField — nothing can be earned.")
		return

	# unbind(1) drops coin_taken's position argument, which the purse has no use for. Godot does not
	# drop surplus arguments by itself: connected bare, every pickup would fail at emit time.
	coin_field.coin_taken.connect(_on_coin_taken.unbind(1))


## Banks the coin's own value rather than an assumed 1, so retuning what a coin is worth needs no
## change on either side of the signal.
func _on_coin_taken(value: int) -> void:
	_total += value
	gained.emit(value, _total)
