class_name CountdownHud
extends CanvasLayer

## The countdown readout and the results screen — the two things that own the middle of the screen
## while nobody is driving. One CanvasLayer rather than two, because they are strictly exclusive:
## the countdown is the moment before a Run and the results are the moment after, and a single node
## that owns "what the middle of the screen says between Runs" cannot leave both up at once.
##
## Read-only and polled each _process, as DebugHud polls Kart — except [signal
## RunDirector.run_completed], a discrete edge a poll cannot see, which is where the results are
## composed. Composing once at the edge rather than every frame is not an optimisation: the numbers
## are frozen the instant the Run ends, and one of them (is_record) is only true on that frame.
##
## The results screen exists to make the next Run worth starting, so it is built around the deltas
## rather than the totals: a total says what happened, a delta says whether you are getting better,
## and only the second is an argument for pressing RESET. The headline says the same thing in one
## line — the record was taken, or exactly what it would have cost to take it.
##
## Every delta is against the ghost, never against the last Run driven. The ghost is the thing on
## the track: it is what the driver spent the Run looking at, it is what the record is kept on, and
## it does not move when a bad Run happens. Measuring against the last Run instead would make a
## column of green deltas out of two mediocre Runs in a row, which is a screen congratulating the
## driver for recovering from their own mistake rather than for getting anywhere.

@export var director_path: NodePath
## How long "GO!" hangs after the freeze releases.
@export var go_display_seconds: float = 0.6
## Shown during Results, telling the player how to start a new Run.
@export var results_prompt: String = "press RESET to run again"

## The record headline's colour. Gold rather than the money green: green on this screen means "up
## on the ghost", and a new record has to outrank four green deltas without reading as a fifth.
@export var record_color: Color = Color(1.0, 0.84, 0.25)

## A delta in the player's favour — the money green PickupPopups and PurseHud already use, so green
## means "you gained" on every screen in the game.
@export var gain_color: Color = Color(0.29, 0.93, 0.42)

## A delta against the player. RunHud's urgency red, for the same reason the green is shared.
@export var loss_color: Color = Color(0.94, 0.24, 0.24)

## An exact tie, and the colour of the row labels. Deliberately dim: a tie is the one delta that is
## not news, and a row label is never the thing being read.
@export var tie_color: Color = Color(0.62, 0.62, 0.68)

## How long the headline takes to settle at full size. The screen's opening beat: the rows start
## landing when it ends.
@export var headline_pop_seconds: float = 0.28

## The gap between two rows landing. Short enough that the whole block is up in well under a second,
## long enough that four rows read as four events rather than one.
@export var row_reveal_seconds: float = 0.16

## How long the screen holds on the wreck before the results appear: kart frozen where it stopped,
## nothing on screen, then the panel. A Timeout is expected — the clock was watched down to it, and
## the results are the beat everyone was already waiting for — but running out of Condition is a
## surprise, and cutting straight to a table of figures denies the driver the moment where they see
## what just killed them. 0.0 removes the hold entirely.
@export var wreck_hold_seconds: float = 1.2

## How long after the last row the prompt fades in. The screen finishes its sentence before it asks
## for the next Run.
@export var prompt_delay_seconds: float = 0.25

## The record headline's heartbeat: swells per second, and how far it swells as a fraction of its
## size. Only a record pulses — a screen where everything moves has nothing left to emphasise.
@export var record_pulse_hz: float = 1.6
@export var record_pulse_scale: float = 0.07

var _director: RunDirector

## Seconds since the Run ended, driving the staggered reveal and the record pulse. Started from the
## run_completed edge rather than from the phase changing, so a frame's slop between the two cannot
## leave a half-built screen up.
var _results_elapsed: float = 0.0
var _is_record: bool = false
var _headline_text: String = ""

## Whether the Run that just ended ran out of Condition, and how long this screen therefore waits
## before drawing anything. Latched at the run_completed edge alongside everything else on the
## screen, so the hold cannot change under a screen already holding.
var _wrecked: bool = false
var _reveal_hold: float = 0.0

## m/s of Tune awarded on the Run that just ended, or 0.0 for no award (CONTEXT.md's **Tune**).
## Pushed explicitly by race.gd's set_tune_award rather than read off the loadout, so the subtitle
## does not depend on which run_completed handler ran first — both fire inside the same
## synchronous emit, ahead of the _process frame that draws it.
var _tune_award: float = 0.0

# The results table, one entry per row, as three parallel columns. Parallel rather than one row
# object per row because that is how it is drawn: each column is a single RichTextLabel, which is
# what makes the columns line up without a table layout, and the reveal is "the first N of each".
var _row_names: PackedStringArray = PackedStringArray()
var _row_values: PackedStringArray = PackedStringArray()
var _row_deltas: PackedStringArray = PackedStringArray()

@onready var _label: Label = $CountdownLabel
@onready var _results: Control = $Results
@onready var _headline: Label = $Results/Headline
@onready var _tune_award_label: Label = $Results/TuneAward
@onready var _names: RichTextLabel = $Results/Rows/Names
@onready var _values: RichTextLabel = $Results/Rows/Values
@onready var _deltas: RichTextLabel = $Results/Rows/Deltas
@onready var _prompt: Label = $Results/Prompt


func _ready() -> void:
	_director = get_node_or_null(director_path) as RunDirector
	_prompt.text = results_prompt
	if _director != null:
		_director.run_completed.connect(_on_run_completed)


## Everything the results screen says is decided here, at the one instant all of it is true: the
## Run's totals are still unreset, and is_record still distinguishes "took the record" from "matched
## it" — which the record itself no longer can, having just been overwritten with this Run's rate.
## The ghost raced is read from [member RunDirector.raced_ghost] rather than from the record for the
## same reason: on a record Run the record is now this Run.
func _on_run_completed(run_time: float, is_record: bool) -> void:
	_results_elapsed = 0.0
	_is_record = is_record
	# Cleared here rather than left standing, so a later non-awarding Run cannot show the previous
	# Run's figure. race.gd's own call to set_tune_award, if this Run earns one, is guaranteed to
	# land after this clear rather than before it: both handlers fire inside the same synchronous
	# run_completed emit, in connection order, and race.gd connects from its own _ready — which,
	# since this node is race.gd's child, runs after this node's _ready already has.
	_tune_award = 0.0
	# Read off the director at the edge rather than carried on the signal: unlike is_record, this is
	# not a value the director overwrites on its way out — see RunDirector.run_ended_wrecked.
	_wrecked = _director.run_ended_wrecked
	_reveal_hold = wreck_hold_seconds if _wrecked else 0.0
	_headline_text = _format_headline(is_record, _wrecked)
	_build_rows(_director, run_time)


## Called by race.gd from its own run_completed handler, the same instant the award happens (or not
## at all, on a Run that earned nothing) — see race.gd's _on_run_completed.
func set_tune_award(amount: float) -> void:
	_tune_award = amount


func _process(delta: float) -> void:
	if _director == null:
		return

	match _director.phase:
		# Ceil, so a 3.0 s countdown reads 3 → 2 → 1 with a full second each rather than
		# flashing "3" for one frame.
		RunDirector.RunPhase.COUNTDOWN:
			_label.text = str(maxi(1, ceili(_director.phase_remaining)))
			_results.visible = false
		RunDirector.RunPhase.RACING:
			_label.text = "GO!" if _director.run_clock < go_display_seconds else ""
			_results.visible = false
		# Results is a real stop, not a held instant — so it gets a screen rather than a line: what
		# this Run did, what it did against the ghost it raced, and what beating that ghost would
		# have cost. The countdown digit stands down entirely; the headline is the big text now.
		RunDirector.RunPhase.RESULTS:
			_label.text = ""
			_results_elapsed += delta
			# The wreck hold. Nothing is drawn through it — not a dimmed panel, not a headline
			# waiting to grow — because the point of the beat is that the screen is empty and the
			# wreck is the only thing in it.
			_results.visible = _results_elapsed >= _reveal_hold
			if _results.visible:
				_draw_results()
		_:
			_label.text = ""
			_results.visible = false


# The staggered reveal, run off _results_elapsed rather than off a Tween: Results can be left at any
# moment by a RESET, and a Tween would have to be caught and killed on an edge the phase poll above
# already handles. Every property is written every frame, so there is no half-finished animation to
# strand — re-entering Results simply redraws from t=0.
func _draw_results() -> void:
	# Every beat below is measured from the moment the panel appears, not from the moment the Run
	# ended: the wreck hold delays the screen, it does not eat the front of its reveal.
	var elapsed: float = _results_elapsed - _reveal_hold
	var pop: float = clampf(elapsed / headline_pop_seconds, 0.0, 1.0)
	# Starts 35% oversized and shrinks in: the headline lands on the screen rather than appearing on
	# it. ease(t, 0.25) is fast-then-slow, so most of the travel is over in the first few frames.
	var pop_scale: float = 1.0 + 0.35 * (1.0 - ease(pop, 0.25))
	var pulse: float = 0.0
	if _is_record and pop >= 1.0:
		# Rides 0..1 rather than -1..1, so the swell only ever adds: a record headline never reads
		# smaller than a plain one.
		pulse = 0.5 + 0.5 * sin((elapsed - headline_pop_seconds) * TAU * record_pulse_hz)

	_headline.text = _headline_text
	_headline.add_theme_color_override("font_color", _headline_color())
	_headline.modulate = Color(1.0, 1.0, 1.0, pop)
	# The label spans the block's full width, so its centre is the block's: the swell stays put
	# instead of walking the text sideways.
	_headline.pivot_offset = _headline.size * 0.5
	_headline.scale = Vector2.ONE * (pop_scale + record_pulse_scale * pulse)

	# The Tune award: gold like the headline, since it is the headline's consequence, but
	# deliberately not pulsing and not taking pop_scale — the headline's own doc argues it must be
	# the single big statement that outranks four green deltas, so this reads as standing beside it
	# rather than competing with it. Only its alpha rides the same reveal clock.
	_tune_award_label.visible = _tune_award > 0.0
	if _tune_award_label.visible:
		_tune_award_label.text = "TUNE +%.1f TOP SPEED" % _tune_award
		_tune_award_label.modulate = Color(1.0, 1.0, 1.0, pop)

	# +1 so the first row lands the instant the headline settles rather than one interval later.
	var revealed: int = clampi(
			floori((elapsed - headline_pop_seconds) / row_reveal_seconds) + 1,
			0, _row_names.size())
	_names.text = _join_rows(_row_names, revealed)
	# Right-aligned as a column rather than per row, so the figures line up on their last digit and
	# the delta column starts at one x for every row.
	_values.text = "[right]%s[/right]" % _join_rows(_row_values, revealed)
	_deltas.text = _join_rows(_row_deltas, revealed)

	var prompt_at: float = headline_pop_seconds + _row_names.size() * row_reveal_seconds + prompt_delay_seconds
	# Breathes rather than blinks: the prompt is the only thing still moving once the screen has
	# settled, which is what points at it without pulling the eye off the numbers on the way in.
	var breath: float = 0.72 + 0.28 * sin(elapsed * TAU * 0.7)
	_prompt.modulate = Color(1.0, 1.0, 1.0, breath if elapsed >= prompt_at else 0.0)


# TIME, CASH, CP, RATE — the Run's four totals, each against the same figure from the ghost it raced.
#
# TIME is in the set because a Run's length is not a constant: clocks buy seconds, so "+8.0" is a
# line the player drove for, and without it a bigger CASH figure is ambiguous between a better line
# and a longer Run. RATE resolves that ambiguity outright, and is what the record is
# actually kept on, so it goes last: it reads as the conclusion of the three above it.
func _build_rows(director: RunDirector, run_time: float) -> void:
	# Null on a circuit with no ghost yet, which is the whole "totals, no delta column" case: one
	# object rather than three sentinels, so no row can disagree with another about whether there was
	# anything to compare against.
	var ghost: RunDirector.RunTotals = director.raced_ghost

	# int / float is float division in GDScript, so the rate needs no widening — but the guard does:
	# a Run cannot end at zero seconds, and the expression should not be the thing that assumes it.
	var rate: float = 0.0 if run_time <= 0.0 else director.run_earnings / run_time

	_row_names = PackedStringArray()
	_row_values = PackedStringArray()
	_row_deltas = PackedStringArray()

	var time_delta: float = 0.0 if ghost == null else run_time - ghost.time
	var cash_delta: int = 0 if ghost == null else director.run_earnings - ghost.earnings
	var checkpoint_delta: int = 0 if ghost == null else director.run_checkpoints_taken - ghost.checkpoints
	# Against the ghost's own recorded rate rather than earnings/time recomputed: that is the number
	# promotion was judged on, and it is the one RunHud has been showing as RECORD all Run.
	var rate_delta: float = 0.0 if ghost == null else rate - ghost.rate

	_add_row("TIME", _format_time(run_time),
			_delta_markup(time_delta, "%+.1f" % time_delta, ghost != null))
	_add_row("CASH", "$%d" % director.run_earnings,
			_delta_markup(cash_delta, "%+d" % cash_delta, ghost != null))
	_add_row("CHECKPOINTS", str(director.run_checkpoints_taken),
			_delta_markup(checkpoint_delta, "%+d" % checkpoint_delta, ghost != null))
	_add_row("RATE", "$%.2f/s" % rate,
			_delta_markup(rate_delta, "%+.2f" % rate_delta, ghost != null))


func _add_row(row_name: String, value: String, delta: String) -> void:
	_row_names.append("[color=#%s]%s[/color]" % [tie_color.to_html(false), row_name])
	_row_values.append(value)
	_row_deltas.append(delta)


## The delta cell: coloured by direction and always signed, so a tie reads as a comparison that was
## made and came out level rather than as a cell that failed to fill in. Empty on a session's first
## Run, where there is nothing to compare against.
##
## Up is good in every row: more time means clocks were taken, and the other three are money,
## checkpoints and rate. Nothing here wants the opposite convention, which is why one colour rule
## serves all four.
func _delta_markup(delta: float, text: String, has_ghost: bool) -> String:
	if not has_ghost:
		return ""
	var color: Color = tie_color
	# Not != 0.0: the two float rows come off a subtraction of near-equal numbers, and a Run that
	# genuinely tied would otherwise be coloured off the last bit of a float and read "-0.00" in red.
	if absf(delta) > 0.005:
		color = gain_color if delta > 0.0 else loss_color
	return "[color=#%s]%s[/color]" % [color.to_html(false), text]


# The headline's colour, which follows whichever line it ended up being: gold for the record, the
# loss red for a wreck, white for a plain Run with nothing to say.
func _headline_color() -> Color:
	if _is_record:
		return record_color
	return loss_color if _wrecked else Color.WHITE


## "NEW RECORD" on a record Run, "WRECKED" on a Run that ran out of Condition, otherwise blank — the
## deltas table below already says what the Run did against the ghost, and a Run that did neither has
## no other headline to make.
##
## The record outranks the wreck when a Run manages both. The wreck is not news by the time this
## screen appears: the driver watched it happen and then sat through a second of it. The record is
## the thing they cannot see from the wreck, and it is the thing that argues for another Run.
static func _format_headline(is_record: bool, wrecked: bool) -> String:
	if is_record:
		return "NEW RECORD"
	return "WRECKED" if wrecked else ""


## The Run's whole length, as m:ss.t once past a minute. Floored to the tenth, as RunHud's clock is,
## so the two never disagree about the last figure the clock showed.
static func _format_time(seconds: float) -> String:
	var tenths: int = floori(seconds * 10.0)
	var minutes: int = floori(tenths / 600.0)
	var remainder: float = (tenths - minutes * 600) / 10.0
	if minutes > 0:
		return "%d:%04.1f" % [minutes, remainder]
	return "%.1f" % remainder


## The first [param count] rows of a column, as one label's text. Rows rather than characters, so a
## row lands whole: a value revealed a digit at a time would be read, briefly, as a smaller number.
static func _join_rows(rows: PackedStringArray, count: int) -> String:
	return "\n".join(rows.slice(0, count))
