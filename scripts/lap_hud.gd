class_name LapHud
extends CanvasLayer

## The racing block, top-right. A separate CanvasLayer from DebugHud, which reads Kart rather than
## LapDirector and is disposable, so it can be switched off or deleted without touching this.
##
## Three lines and a checkpoint counter:
##
##   the lap clock   — at the top, being the denominator you are feeling. Nothing on screen ranks it.
##   RATE            — the live cumulative average the completed lap will be judged on. Neither
##                     windowed nor smoothed: see [member LapDirector.earn_rate].
##   RECORD          — the bar to beat, which is also the pace ghost's rate.
##
## There is no per-lap coin counter: it would disambiguate a good line from a good time, but the
## simpler screen wins. One Label beside CP if a playtest ever wants it.
##
## Read-only and polled each _process, except the record flash, a discrete edge that comes in on the
## director's lap_completed signal.

@export var director_path: NodePath

## How long the RECORD line stays lit after a lap beats it. Sized to outlast the Finished hold, so
## the line is still lit while the rate that earned it is on screen.
@export var record_flash_duration: float = 2.0

## The money green, the same value PickupPopups and PurseHud use. Shared so that green means money
## everywhere on screen, and a new record is a money event.
@export var record_flash_color: Color = Color(0.29, 0.93, 0.42)

## How long into a lap the live rate stays blank: the first fraction of a second is a genuine 0/0 and
## the tenth is a wild number off a tiny denominator. Gated on elapsed time rather than on the first
## coin, which would blink between blank and live and would spell "nothing yet" and "nothing earned"
## the same way.
const RATE_BLANK_SECONDS: float = 1.0

## "No number yet" reads as blanks in the shape of one, never as 0.00, which for a rate would claim
## you are earning nothing.
const UNSET_TEXT: String = "--.--"

var _director: LapDirector
var _record_base_color: Color
var _record_flash: float = 0.0

@onready var _current_label: Label = $CurrentLabel
@onready var _rate_label: Label = $RateLabel
@onready var _record_label: Label = $RecordLabel
@onready var _checkpoint_label: Label = $CheckpointLabel


func _ready() -> void:
	_director = get_node(director_path) as LapDirector

	_record_base_color = _record_label.modulate
	_director.lap_completed.connect(_on_lap_completed)


## is_record comes off the signal rather than being re-derived here: the value it would be compared
## against has just been overwritten by the director.
func _on_lap_completed(_time: float, is_record: bool) -> void:
	if is_record:
		_record_flash = record_flash_duration


func _process(delta: float) -> void:
	if _director == null:
		return

	_current_label.text = _format_time(_director.current_lap_time)
	# Polled, never cached: earn_rate is a computed property over the expression complete_lap judges
	# the lap on, so the number watched climbing is the number scored.
	_rate_label.text = "RATE  %s" % _format_rate(_director.earn_rate, _director.current_lap_time)
	# The record needs no blanking window: it is either set or not, and its sentinel says which. A
	# session's first lap runs against RECORD --.--/s and promotes whatever it manages.
	_record_label.text = "RECORD  %s" % _format_rate(_director.record_earn_rate, INF)
	# No "LAP i/N" suffix at the default laps_required of 1: a single-circuit lap has nothing for it
	# to disambiguate, and the readout should look exactly as it always has until the dev input is
	# actually used.
	var lap_suffix: String = ""
	if _director.laps_required > 1:
		lap_suffix = "   LAP %d/%d" % [_director.lap_count, _director.laps_required]
	_checkpoint_label.text = "CP %d/%d%s" % [_director.checkpoint_index, _director.checkpoint_count, lap_suffix]

	_record_flash = maxf(0.0, _record_flash - delta)
	_record_label.modulate = record_flash_color if _record_flash > 0.0 else _record_base_color


# Two decimals: hundredths still separate two laps of a ~16 s circuit and tick slowly enough to
# read. The running clock and the recorded time share the formatter. The minute field appears only
# once earned, so a short lap carries no permanent "0:".
static func _format_time(seconds: float) -> String:
	var minutes: int = floori(seconds / 60.0)
	var remainder: float = seconds - minutes * 60.0
	if minutes > 0:
		return "%d:%05.2f" % [minutes, remainder]
	return "%.2f" % remainder


# Both rate lines go through here, so the live figure and the record cannot read as different
# quantities. Two decimals: at $1 a coin over a ~16 s lap the interesting range is $0 to $2 per
# second, and tenths would flatten most of a lap's progress into one digit.
#
# The record passes INF for `elapsed`: it has no blanking window, and its negative sentinel is what
# keeps it blank until a lap sets it.
static func _format_rate(rate: float, elapsed: float) -> String:
	if rate < 0.0 or elapsed < RATE_BLANK_SECONDS:
		return "%s/s" % UNSET_TEXT
	return "$%.2f/s" % rate
