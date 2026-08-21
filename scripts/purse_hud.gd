class_name PurseHud
extends CanvasLayer

## The purse on screen, top-centre and green.
##
## Its own CanvasLayer rather than a row in RunHud: a different place on screen, a different source
## object (Purse, not RunDirector), and a different lifetime — the purse outlives every Run and
## abort, and nothing here is ever reset. It is the reward number, not a racing stat.
##
## Read-only and polled each _process. The one discrete edge, the flash on pickup, comes in on
## [signal Purse.gained], since a per-frame poll cannot see an event that lasts one frame.
##
## Reads the Purse autoload directly rather than through an exported NodePath: the purse now
## outlives the scene, so there is no scene-local node to point at.

## How long the label stays lit after a pickup. Much shorter than the record flash next door:
## checkpoints arrive in bursts, and a long flash would stay lit through a good line and stop
## meaning "just now".
## At this length a swept run holds the label lit continuously, reading as one event.
@export var flash_duration: float = 0.25

## Multiplied over the label's green rather than replacing it, so the purse still reads as money
## while lit. Above 1.0 on every channel, brightening toward white-green.
@export var flash_modulate: Color = Color(1.7, 1.7, 1.7)

var _base_modulate: Color
var _flash: float = 0.0

@onready var _label: Label = $PurseLabel


func _ready() -> void:
	_base_modulate = _label.modulate
	Purse.gained.connect(_on_gained)


## Both arguments ignored: the label polls [member Purse.total] below, so the flash and the number
## cannot disagree about what is on screen.
func _on_gained(_amount: int, _total: int) -> void:
	_flash = flash_duration


func _process(delta: float) -> void:
	_label.text = _format_money(Purse.total)

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
