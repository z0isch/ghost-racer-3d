extends Node

## The session's running money total, and nothing else.
##
## An autoload: it must survive the scene swap between the open world and a race scene, and an
## autoload is the only thing in Godot that does. A regular node dies with the scene that owned it,
## which would zero the purse every time the kart crosses a start line.
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

var _total: int = 0

## Polled by the purse HUD layer each _process, as every other readout in the project is.
var total: int:
	get: return _total


## Banks the coin's own value rather than an assumed 1, so retuning what a coin is worth needs no
## change on either side of the signal. Called by [class PurseLink], which a scene places to connect
## a CoinField's coin_taken signal here — this autoload has no NodePath into any scene's CoinField.
func add(value: int) -> void:
	_total += value
	gained.emit(value, _total)
