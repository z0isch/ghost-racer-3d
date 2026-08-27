class_name RunHud
extends CanvasLayer

## The racing readout. A separate CanvasLayer from DebugHud, which reads Kart rather than
## RunDirector and is disposable, so it can be switched off or deleted without touching this.
##
## A clock, two rate lines and a checkpoint counter:
##
##   the run clock   — centred at the top, in the largest face on screen, counted down: what you
##                     are feeling is how much time is left to earn in, not how much has gone. It
##                     sits in the middle because it is the one thing read under pressure, and it
##                     is read there without looking away from the road. Nothing on screen ranks
##                     it. For the last [member urgency_seconds] it is replaced entirely — see
##                     [method _apply_urgency].
##   RATE            — top-right, the live cumulative average the completed Run will be judged on.
##                     Neither windowed nor smoothed: see [member RunDirector.earn_rate]. Tinted by
##                     [member RunDirector.ahead_of_pace] while Racing — the promotion test is now
##                     track position, not this figure, so RATE alone can no longer tell a driver
##                     whether they are on course to take the record.
##   RECORD          — the bar to beat, which is also the pace ghost's rate.
##
## There is no per-Run clock counter: it would disambiguate a good line from a good time, but the
## simpler screen wins. One Label beside CP if a playtest ever wants it.
##
## Read-only and polled each _process, except the record flash, a discrete edge that comes in on the
## director's run_completed signal.

@export var director_path: NodePath

## How long the RECORD line stays lit after a Run beats it.
@export var record_flash_duration: float = 2.0

## The money green, the same value PickupPopups and PurseHud use. Shared so that green means money
## everywhere on screen, and a new record is a money event.
@export var record_flash_color: Color = Color(0.29, 0.93, 0.42)

## RATE's tint while [member RunDirector.ahead_of_pace] is true — the same green as a record flash,
## so "ahead" reads as the good thing it is before the Run even ends.
@export var ahead_of_pace_color: Color = Color(0.29, 0.93, 0.42)
## RATE's tint while racing behind the pace ghost. Not [member urgency_color]'s red: that colour is
## reserved for the clock running out, a harder and more urgent fact than merely trailing the ghost.
@export var behind_pace_color: Color = Color(0.95, 0.65, 0.25)

## When the clock stops being a clock: the last stretch of a Run, where a clock two corners away has
## stopped being worth going for. The hundredths in the corner have nothing left to say here — what
## is left is a small integer — so the readout is swapped for the whole second, thrown into the
## middle of the screen, over the road, where it cannot be missed and costs no glance away.
@export var urgency_seconds: float = 5.0

## What the last seconds are drawn in. Red rather than the money green, which everywhere else on
## screen means something was gained.
@export var urgency_color: Color = Color(0.94, 0.24, 0.24)

## How long each second stays up. Shorter than a second on purpose: the gap is the point, since a
## number that never leaves is a display, and one that arrives is an alarm.
@export var urgency_flash_seconds: float = 0.45

## How far the flash swells over its life, as a fraction of its size — 0.25 = a quarter bigger at
## the instant it lands.
@export var urgency_pulse_scale: float = 0.25

## How long into a Run the live rate stays blank: the first fraction of a second is a genuine 0/0 and
## the tenth is a wild number off a tiny denominator. Gated on elapsed time rather than on the first
## checkpoint, which would blink between blank and live and would spell "nothing yet" and "nothing
## earned" the same way.
const RATE_BLANK_SECONDS: float = 1.0

## "No number yet" reads as blanks in the shape of one, never as 0.00, which for a rate would claim
## you are earning nothing.
const UNSET_TEXT: String = "--.--"

var _director: RunDirector
var _record_base_color: Color
var _record_flash: float = 0.0
var _rate_base_color: Color

@onready var _current_label: Label = $CurrentLabel
@onready var _final_seconds_label: Label = $FinalSecondsLabel
@onready var _rate_label: Label = $RateLabel
@onready var _record_label: Label = $RecordLabel
@onready var _checkpoint_label: Label = $CheckpointLabel


func _ready() -> void:
	_director = get_node(director_path) as RunDirector

	_record_base_color = _record_label.modulate
	_rate_base_color = _rate_label.modulate
	# Set from the export rather than authored in the scene, so the one place that says what the last
	# seconds look like is the one place that decides when they start.
	_final_seconds_label.add_theme_color_override("font_color", urgency_color)
	_director.run_completed.connect(_on_run_completed)


## is_record comes off the signal rather than being re-derived here: the value it would be compared
## against has just been overwritten by the director.
func _on_run_completed(_time: float, is_record: bool) -> void:
	if is_record:
		_record_flash = record_flash_duration


func _process(delta: float) -> void:
	if _director == null:
		return

	# Counted down, not up: the number under time pressure is the time left.
	var remaining: float = _director.run_remaining
	_current_label.text = _format_time(remaining)
	_apply_urgency(remaining, _director.phase == RunDirector.RunPhase.RACING)
	# Polled, never cached: earn_rate is a computed property over the expression complete_run judges
	# the Run on, so the number watched climbing is the number scored.
	_rate_label.text = "RATE  %s" % _format_rate(_director.earn_rate, _director.run_clock)
	_rate_label.modulate = _pace_color(_director.phase, _director.pace_gap_meters)
	# The record needs no blanking window: it is either set or not, and its sentinel says which. A
	# session's first Run runs against RECORD --.--/s and promotes whatever it manages.
	_record_label.text = "RECORD  %s" % _format_rate(_director.record_earn_rate, INF)
	_checkpoint_label.text = "CP %d/%d" % [_director.checkpoint_index, _director.checkpoint_count]

	_record_flash = maxf(0.0, _record_flash - delta)
	_record_label.modulate = record_flash_color if _record_flash > 0.0 else _record_base_color


# Which clock is on screen, and what the middle one is doing this frame. Exactly one is visible at a
# time: the corner clock and a five in the middle of the road are the same fact twice, and the second
# copy is the one that would be read.
#
# Everything is written every frame rather than on the crossing edge, so an Abort or a new Run —
# which jump the clock back over the threshold without passing through it — cannot leave a flash
# stranded on screen or the top clock hidden behind one.
#
# Gated on Racing as well as on the threshold: at Timeout the middle of the screen belongs to
# CountdownHud's Results prompt, and a "1" fading over it is a Run that has already ended still
# counting.
func _apply_urgency(remaining: float, is_racing: bool) -> void:
	var urgent: bool = is_racing and remaining <= urgency_seconds
	_current_label.visible = not urgent
	_final_seconds_label.visible = urgent
	if not urgent:
		return

	# Ceil, so the second being driven is the one on screen: 4.99 s left is "5", and stays 5 until
	# the clock actually passes 4. maxi(1, ...) keeps the last moment from flashing a "0" — 0 is
	# what the Run ends at, not a second anyone gets to drive.
	_final_seconds_label.text = str(maxi(1, ceili(remaining)))

	# Seconds since this digit landed. fposmod rather than subtracting floorf, so the arithmetic
	# still holds at exactly 0.0 remaining.
	var since_tick: float = 1.0 - fposmod(remaining, 1.0)
	# Squared, so the digit reads at full strength for most of its life and then goes quickly. A
	# linear fade spends its whole time half-lit and blurs one second into the next.
	var flash: float = 1.0 - pow(minf(since_tick / urgency_flash_seconds, 1.0), 2.0)
	_final_seconds_label.modulate = Color(1.0, 1.0, 1.0, flash)
	# The label is the whole screen, so its centre is the screen's: the swell stays put instead of
	# walking the digit across the road.
	_final_seconds_label.pivot_offset = _final_seconds_label.size * 0.5
	_final_seconds_label.scale = Vector2.ONE * (1.0 + urgency_pulse_scale * flash)


# One decimal: enough motion to read as a clock running down, without the two digits of noise that
# hundredths are at this size. The last five seconds — the only place a finer figure would change a
# decision — have their own whole-second readout (see [method _apply_urgency]).
#
# Floored to the tenth rather than rounded, so the clock never claims time that is gone: 45.96 s
# left reads 45.9, and 0.0 is not shown until the Run has actually reached it. The minute field
# appears only once earned, so a short Run carries no permanent "0:".
static func _format_time(seconds: float) -> String:
	var tenths: int = floori(seconds * 10.0)
	var minutes: int = floori(tenths / 600.0)
	var remainder: float = (tenths - minutes * 600) / 10.0
	if minutes > 0:
		return "%d:%04.1f" % [minutes, remainder]
	return "%.1f" % remainder


# Both rate lines go through here, so the live figure and the record cannot read as different
# quantities. Two decimals: at a base checkpoint value of $1 the interesting range is small, and
# tenths would flatten most of a Run's progress into one digit.
#
# The record passes INF for `elapsed`: it has no blanking window, and its negative sentinel is what
# keeps it blank until a Run sets it.
static func _format_rate(rate: float, elapsed: float) -> String:
	if rate < 0.0 or elapsed < RATE_BLANK_SECONDS:
		return "%s/s" % UNSET_TEXT
	return "$%.2f/s" % rate


## RATE's colour for this frame, off [member RunDirector.pace_gap_meters]. Read here rather than
## cached on the director's own edge: unlike the record flash, ahead/behind is not an event, it is a
## standing fact this frame either does or doesn't hold, and a fact like that belongs polled.
func _pace_color(phase: RunDirector.RunPhase, gap_meters: float) -> Color:
	if phase != RunDirector.RunPhase.RACING or is_nan(gap_meters):
		return _rate_base_color
	return ahead_of_pace_color if gap_meters > 0.0 else behind_pace_color
