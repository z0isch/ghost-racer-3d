class_name WrapHud
extends CanvasLayer

## What a wrap just cost, thrown up in the middle of the screen the instant it closes: the wrap's
## time, how it compares with the pace ghost's own time on that same wrap, and the seconds the wrap
## itself banked.
##
## A separate CanvasLayer from CountdownHud, which owns the middle of the screen while nobody is
## driving. This is the opposite case — it only ever appears mid-Run, at speed — and the two are
## never up together: a wrap cannot close during a countdown or after a Timeout.
##
## It hangs from just under the purse readout and it is two lines: the wrap's time with its
## comparison beside it, and the seconds banked underneath. At this size the block is half again as
## tall as the gap between the purse readout and RunHud's final-seconds digit, so one of the two has
## to give. The purse is on screen every frame of every Run and the digit only in the last five
## seconds of one, so the block hangs clear of the purse and reaches down past centre into the
## digit's space: the collision left is rare, brief, and between two things that are never both
## being read.
##
## It carries no label of its own. A wrap readout only ever appears at the instant a wrap closes,
## with the start/finish gate going past, and what stands beside the time — a signed delta and the
## seconds just banked — says what kind of number it is; a word naming it would be read every time
## and needed none of them.
##
## Purely a readout, as PickupPopups is purely a popup: nothing here is read back by a test, the
## purse or the promotion rule. It knows one edge ([signal RunDirector.wrap_completed]) and a
## clock of its own, and no Run state at all.

@export var director_path: NodePath

## How long the banner holds at full strength before it begins to fade, and how long the fade takes.
## It is read at racing speed, over the road, so the hold is what has to be long enough to be caught
## on a glance and the fade is what keeps it from ever being the thing on screen.
@export var hold_seconds: float = 3
@export var fade_seconds: float = 2

## How long the banner takes to settle at full size, matching CountdownHud's headline pop — a wrap
## readout and a results headline are the same gesture, so they land the same way.
@export var pop_seconds: float = 0.22

## The time's own size, in points, against the label's authored size for everything beside and under
## it. Set here rather than in the scene because it is written as bbcode inside the text: the whole
## block is one label, so the time and its comparison share a baseline rather than merely sitting
## near each other, and the second line falls where the first one ends without a second node to keep
## in step with it. The size gap is what ranks them — the time is the report, the rest is the
## footnote — and with nothing labelling the banner it is also what separates them at a glance.
##
## Raising it means resizing LineLabel in the scene to match. A RichTextLabel clips to its own rect
## rather than growing (its anchored offsets are what fix that rect, so fit_content cannot save it),
## and the symptom of a box a few pixels short is the second line cut off along its baseline — which
## reads as a rendering fault rather than as a layout one. At 104 the two lines measure 188 px, and
## the box carries 20 px over that for the outline.
@export var time_font_size: int = 104

## A wrap driven quicker than the pace ghost's own time on it, and one driven slower. The same green and red
## CountdownHud's deltas use, so faster/slower reads the same on both screens.
@export var gain_color: Color = Color(0.29, 0.93, 0.42)
@export var loss_color: Color = Color(0.94, 0.24, 0.24)

## The colour of a delta too small to call. CountdownHud's tie colour, deliberately dim for its
## reason: a tie is the one comparison that is not news.
@export var tie_color: Color = Color(0.62, 0.62, 0.68)

## The clock's own colour, shared with PickupPopups: the wrap bonus banner and the "+10s" that flies
## off the gate as it is banked are the same award reported twice, and colour is what says so.
@export var clock_color: Color = Color(0.4, 0.75, 1.0)

## Below this many seconds a difference is called a tie rather than coloured. A tenth: the time
## above it is shown to the tenth, so anything finer is a delta the readout itself cannot show.
const TIE_EPSILON: float = 0.05

var _director: RunDirector

## Seconds since the wrap closed, driving the pop, the hold and the fade. Negative means nothing is
## up — the banner has never fired this Run, or has finished fading.
var _elapsed: float = -1.0

@onready var _line_label: RichTextLabel = $LineLabel


func _ready() -> void:
	_director = get_node_or_null(director_path) as RunDirector
	if _director != null:
		_director.wrap_completed.connect(_on_wrap_completed)
		# A wrap closed a fraction of a second before an Abort would otherwise leave the banner
		# hanging over the new Run's countdown.
		_director.countdown_started.connect(_dismiss)
		_director.run_completed.connect(_dismiss.unbind(2))
	else:
		push_warning("WrapHud: no RunDirector — no wrap readout.")
	_dismiss()


## Composed once, on the edge: every figure is frozen the instant the wrap closes, and the frames
## after it are pure animation.
func _on_wrap_completed(wrap_time: float, ghost_wrap_time: float, bonus_seconds: float) -> void:
	_elapsed = 0.0
	var head := PackedStringArray(["[font_size=%d]%s[/font_size]" % [time_font_size,
			_format_time(wrap_time)]])
	var delta_markup: String = _delta_markup(wrap_time, ghost_wrap_time)
	if delta_markup != "":
		head.append(delta_markup)
	var lines := PackedStringArray(["   ".join(head)])
	# The award goes under the time rather than beside it: it is the one figure here that is not a
	# measurement of the wrap, and a line of its own is what says so without a word.
	if bonus_seconds > 0.0:
		lines.append("[color=#%s]+%ds[/color]" % [clock_color.to_html(false), roundi(bonus_seconds)])
	_line_label.text = "[center]%s[/center]" % "\n".join(lines)
	_line_label.visible = true


func _process(delta: float) -> void:
	if _elapsed < 0.0:
		return

	_elapsed += delta
	if _elapsed >= pop_seconds + hold_seconds + fade_seconds:
		_dismiss()
		return

	var pop: float = clampf(_elapsed / pop_seconds, 0.0, 1.0)
	# Starts oversized and shrinks in, as CountdownHud's headline does: the banner lands on the
	# screen rather than appearing on it.
	var pop_scale: float = 1.0 + 0.3 * (1.0 - ease(pop, 0.25))
	var fade: float = 1.0 - clampf((_elapsed - pop_seconds - hold_seconds) / fade_seconds, 0.0, 1.0)
	var alpha: float = minf(pop, fade)

	# The line spans the banner's full width, so its centre is the banner's: the swell stays put
	# instead of walking the text sideways.
	_line_label.pivot_offset = _line_label.size * 0.5
	_line_label.scale = Vector2.ONE * pop_scale
	_line_label.modulate = Color(1.0, 1.0, 1.0, alpha)


func _dismiss() -> void:
	_elapsed = -1.0
	_line_label.visible = false


## What stands beside the time: how it compares with the pace ghost's own time on this same wrap.
## Empty when the ghost has no data for it — no ghost line yet, or the record Run itself never
## reached this wrap number — since a signed zero there would claim a comparison nothing was made.
func _delta_markup(wrap_time: float, ghost_wrap_time: float) -> String:
	if ghost_wrap_time < 0.0:
		return ""
	var delta: float = wrap_time - ghost_wrap_time
	var color: Color = tie_color
	# Down is good here and nowhere else on screen: this is the one figure in the game a smaller
	# number is a better drive. Hence the explicit inversion rather than CountdownHud's shared rule.
	if absf(delta) > TIE_EPSILON:
		color = gain_color if delta < 0.0 else loss_color
	return "[color=#%s]%+.1f[/color]" % [color.to_html(false), delta]


## m:ss.t once past a minute, floored to the tenth — RunHud's clock and CountdownHud's TIME row are
## formatted identically, so no two figures in the game disagree about their last digit.
static func _format_time(seconds: float) -> String:
	var tenths: int = floori(seconds * 10.0)
	var minutes: int = floori(tenths / 600.0)
	var remainder: float = (tenths - minutes * 600) / 10.0
	if minutes > 0:
		return "%d:%04.1f" % [minutes, remainder]
	return "%.1f" % remainder
