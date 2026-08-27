extends Node

## The session's running money total, and nothing else.
##
## An autoload: it must survive the scene swap between the open world and a race scene, and an
## autoload is the only thing in Godot that does. A regular node dies with the scene that owned it,
## which would zero the purse every time the kart crosses a start line.
##
## Not on RunDirector either, a split recorded in CONTEXT.md under **Purse holder**. The director
## owns Run state and clears all of it in _begin_countdown, and a session-scoped total behind a
## per-Run reset eventually gets cleared by accident. Hence what is absent here: no connection to
## countdown_started and no reset path, so no Run boundary can reach in.
##
## The total only ever goes up. Nothing subtracts from it, checkpoints are banked the instant they
## are taken, and an abort costs the abandoned Run its earnings but not its contribution here. It is a
## reward rather than a currency or a score: the pace ghost is promoted on track position, not on
## this, and nothing is won or lost by having more.
##
## Persisted to [constant SAVE_PATH], the first thing in the game that has to be: an income ghost
## earns while nobody is looking, and a purse that forgot that money on every quit would quietly
## delete exactly what this feature exists to produce. Written on an interval, on
## NOTIFICATION_WM_CLOSE_REQUEST, and (via the public [method save]) at any future spend — interval
## alone loses a clean quit that beats the timer, events alone lose everything to a hard kill.

const SAVE_PATH: String = "user://purse.tres"
## ~10 s: a rounding error against a passive earner, and infrequent enough that a purse rising
## several times a second from income ghosts does not thrash the disk.
const AUTOSAVE_INTERVAL_SECONDS: float = 10.0

## One pickup, banked by driving through it. Carries the amount for the HUD to flash on, and the
## new total so a listener reacting to the edge does not have to poll in the same breath. The
## running total for the label itself is polled off `total`, matching every other HUD readout in
## the project.
signal gained(amount: int, total: int)

## One income accrual, banked by an income ghost. Deliberately a separate signal from [signal
## gained] rather than a flag on it: PurseHud's flash means "you took a checkpoint", and CONTEXT.md's
## **Purse readout** calls firing it on income "a flash that fires whether or not the player did
## anything" — meaningless feedback. The total is the same purse either way; this is a second door
## into it, not a second purse.
signal income_gained(amount: int, total: int)

var _total: int = 0
var _autosave_elapsed: float = 0.0

## Polled by the purse HUD layer each _process, as every other readout in the project is.
var total: int:
	get: return _total


func _ready() -> void:
	_load()


func _process(delta: float) -> void:
	_autosave_elapsed += delta
	if _autosave_elapsed >= AUTOSAVE_INTERVAL_SECONDS:
		_autosave_elapsed = 0.0
		save()


## The engine notifies every node before honouring a close request, which is what makes a
## synchronous save here safe: this runs before the process actually exits.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save()


## Banks the checkpoint's own ladder value rather than an assumed 1, so retuning the ladder needs no
## change on either side of the signal. Called by [class PurseLink], which a scene places to connect
## a RunDirector's checkpoint_paid signal here — this autoload has no NodePath into any scene's
## RunDirector.
func add(value: int) -> void:
	_total += value
	gained.emit(value, _total)


## The income runner's door into the purse ([autoload IncomeRunner]), banking exactly like [method
## add] but through the silent signal rather than the flash-worthy one.
func add_income(value: int) -> void:
	_total += value
	income_gained.emit(value, _total)


## Writes the total to [constant SAVE_PATH]. Public so a future spend can force a write in the same
## breath as the purchase, rather than trusting the next autosave tick — there is no spend path yet
## (no shop), so this is a call site with no callers today.
func save() -> void:
	var data := PurseSave.new()
	data.total = _total
	var error: Error = ResourceSaver.save(data, SAVE_PATH)
	if error != OK:
		push_warning("Purse: failed to save purse to %s (%s)." % [SAVE_PATH, error])


## A missing or unloadable save file means a zero purse, not an error — same null-tolerance as
## [method LoadoutHolder.for_circuit].
func _load() -> void:
	if not ResourceLoader.exists(SAVE_PATH):
		return
	var data: PurseSave = load(SAVE_PATH) as PurseSave
	if data == null:
		push_warning("Purse: %s did not load as a PurseSave." % SAVE_PATH)
		return
	_total = data.total
