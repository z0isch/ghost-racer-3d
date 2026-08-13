class_name PurseHud
extends CanvasLayer

## The purse on screen, top-centre and green.
##
## Its own CanvasLayer rather than a row in LapHud: a different place on screen, a different source
## object (Purse, not LapDirector), and a different lifetime — the purse outlives every lap and
## abort, and nothing here is ever reset. It is the reward number, not a racing stat.
##
## Read-only and polled each _process. The one discrete edge, the flash on pickup, comes in on
## [signal Purse.gained], since a per-frame poll cannot see an event that lasts one frame.

## The purse to read. Polled for `total`, listened to for `gained`.
@export var purse_path: NodePath

## How long the label stays lit after a pickup. Much shorter than the record flash next door: coins
## arrive in bursts, and a long flash would stay lit through a good line and stop meaning "just now".
## At this length a swept run holds the label lit continuously, reading as one event.
@export var flash_duration: float = 0.25

## Multiplied over the label's green rather than replacing it, so the purse still reads as money
## while lit. Above 1.0 on every channel, brightening toward white-green.
@export var flash_modulate: Color = Color(1.7, 1.7, 1.7)

var _purse: Purse
var _base_modulate: Color
var _flash: float = 0.0

@onready var _label: Label = $PurseLabel


func _ready() -> void:
	_base_modulate = _label.modulate

	_purse = get_node_or_null(purse_path) as Purse
	# A scene without a purse shows nothing, which keeps this script runnable outside main.tscn.
	if _purse == null:
		push_warning("PurseHud: no Purse — the purse readout is dead.")
		return

	_purse.gained.connect(_on_gained)


## Both arguments ignored: the label polls [member Purse.total] below, so the flash and the number
## cannot disagree about what is on screen.
func _on_gained(_amount: int, _total: int) -> void:
	_flash = flash_duration


func _process(delta: float) -> void:
	if _purse == null:
		return

	_label.text = _format_money(_purse.total)

	_flash = maxf(0.0, _flash - delta)
	_label.modulate = flash_modulate if _flash > 0.0 else _base_modulate


## Thousands separated: [code]$1,234[/code], not [code]$1234[/code]. Four figures arrives inside an
## hour of driving, by which point the number is read at a glance mid-corner. No sign handling and no
## negative branch: the purse only ever goes up (scripts/purse.gd).
static func _format_money(amount: int) -> String:
	var digits: String = str(amount)
	var grouped: String = ""
	var placed: int = 0
	for index: int in range(digits.length() - 1, -1, -1):
		grouped = digits[index] + grouped
		placed += 1
		if placed % 3 == 0 and index > 0:
			grouped = "," + grouped
	return "$" + grouped
