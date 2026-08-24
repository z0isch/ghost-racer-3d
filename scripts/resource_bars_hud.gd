class_name ResourceBarsHud
extends Control

## The two bars down the left edge: what this Run has caught, and what it has left.
##
##   slipstream — outer, green, a continuous fill toward the circuit's own
##                [member RunDirector.slipstream_bar_target]. Pure information: it says how the Run
##                is going for traffic, and reaching the top pays nothing.
##   Condition  — inner, red, one discrete segment per hazard hit the Run can still take. At zero
##                the Run ends (CONTEXT.md's **Condition**).
##
## No text and no numbers anywhere on either bar. Two shapes at the edge of vision, read without
## looking away from the road — a figure would have to be looked at to be read, which is the one
## thing a bar exists to avoid. What each one means is learned by watching it move while something
## happens, which is why the colours are the world's own: green is the traffic you just drove
## through, red is the oncoming ghost that just hit you.
##
## Condition sits inboard of slipstream deliberately. It is the bar with a consequence, so it gets
## the position nearer the road, where peripheral vision is already pointed while driving; the
## slipstream bar is the one you can afford to actually glance at.
##
## A Control with its own [method _draw] rather than a CanvasLayer of ColorRects, which is what the
## rest of the HUD is: the Condition bar's segment count is [member RunDirector.starting_condition]
## and not a scene-authored constant, so the nodes would have to be built at runtime anyway. It
## therefore lives *under* a CanvasLayer in the scene rather than being one, unlike its neighbours.
##
## Polled each _process like [RunHud], with one discrete edge — [signal RunDirector.condition_lost],
## a hit a per-frame poll would see only as a segment that had already gone.

@export var director_path: NodePath

## Distance from the left edge of the screen to the outer bar.
@export var margin_left: float = 26.0

## How tall the bars are, as a fraction of screen height. Centred vertically: the vertical middle of
## the left edge is the closest point of the HUD to where the eyes already are.
@export var height_fraction: float = 0.34

@export var bar_width: float = 13.0
## Between the two bars. Wide enough that they never read as one two-tone bar.
@export var bar_gap: float = 9.0

## Between two Condition segments. Small: the gaps divide one bar, they are not three bars.
@export var segment_gap: float = 3.0

## The slipstream ghost's own colour (SlipstreamGhostField.ghost_color), opaque here — the world
## draws it translucent because it is a thing you see the road through.
@export var slipstream_color: Color = Color(0.15, 0.85, 0.35)

## The hazard ghost's own colour (HazardGhostField.ghost_color), opaque for slipstream_color's
## reason.
@export var condition_color: Color = Color(0.95, 0.1, 0.1)

## The unfilled part of either bar: the same dark, so an empty slipstream bar and a spent Condition
## segment read as the same kind of nothing.
@export var track_color: Color = Color(0.08, 0.08, 0.1, 0.55)

## What a segment flashes to on the way out. Whiter than the red so it registers at the edge of
## vision, where a red on a red does not.
@export var flash_color: Color = Color(1.0, 0.85, 0.85)

## How long the flash on a lost segment lasts. Short — it marks an instant, and the speed already
## bled out from under the driver is the other half of the same message.
@export var flash_duration: float = 0.35

var _director: RunDirector

## Seconds left of the lost-segment flash, and which segment is flashing — the index the segment had
## while it was still lit, which is exactly the remaining count the signal carried.
var _flash: float = 0.0
var _flash_index: int = -1


func _ready() -> void:
	_director = get_node_or_null(director_path) as RunDirector
	if _director == null:
		push_warning("ResourceBarsHud: no RunDirector — the bars will not be drawn.")
		return
	_director.condition_lost.connect(_on_condition_lost)
	# Nothing here is ever clicked, and a full-rect Control over the screen would otherwise eat every
	# press aimed at anything behind it.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## [param remaining] is the count left *after* the hit, which is also the index of the segment that
## just went: segments are drawn from the bottom, so with 3 lit the topmost is index 2, and losing it
## leaves 2.
func _on_condition_lost(remaining: int) -> void:
	_flash = flash_duration
	_flash_index = remaining


func _process(delta: float) -> void:
	if _director == null:
		return

	# Racing only, matching the rest of the HUD: during Countdown the bars say nothing that has
	# happened yet, and during Results the middle of the screen belongs to CountdownHud.
	visible = _director.phase == RunDirector.RunPhase.RACING
	if not visible:
		# Dropped rather than left to expire, so a flash cannot survive an Abort and land on the
		# first frame of the next Run.
		_flash = 0.0
		return

	_flash = maxf(0.0, _flash - delta)
	# Every frame: the fills move continuously and the flash fades, so there is no edge worth
	# detecting to redraw on.
	queue_redraw()


func _draw() -> void:
	if _director == null:
		return

	var height: float = size.y * height_fraction
	var top: float = (size.y - height) * 0.5

	# Outer first, then inner — see the class doc on why Condition is the inboard one.
	_draw_fill_bar(Rect2(margin_left, top, bar_width, height), _slipstream_fraction())
	var condition_x: float = margin_left + bar_width + bar_gap
	_draw_segment_bar(Rect2(condition_x, top, bar_width, height))


## The slipstream bar. Clamped here rather than at the source ([member RunDirector.slipstream_taken]
## counts uncapped), and a target of 0 draws an empty bar rather than dividing by it.
func _slipstream_fraction() -> float:
	if _director.slipstream_bar_target <= 0:
		return 0.0
	return clampf(float(_director.slipstream_taken) / float(_director.slipstream_bar_target), 0.0, 1.0)


# Grown from the bottom: a bar that fills upward is filling, and one that fills downward is draining.
func _draw_fill_bar(rect: Rect2, fraction: float) -> void:
	draw_rect(rect, track_color)
	if fraction <= 0.0:
		return
	var filled: float = rect.size.y * fraction
	draw_rect(Rect2(rect.position.x, rect.position.y + rect.size.y - filled, rect.size.x, filled),
			slipstream_color)


# The Condition bar: one segment per point of starting Condition, drawn bottom-up so that losing one
# takes the top off — the bar drains the way the slipstream bar fills, and the two motions are
# opposite because the two facts are.
func _draw_segment_bar(rect: Rect2) -> void:
	var count: int = maxi(1, _director.starting_condition)
	# The gaps come out of the bar's height, not out of the segments' claim on it, so a bar of three
	# and a bar of five occupy the same space.
	var segment_height: float = (rect.size.y - segment_gap * (count - 1)) / float(count)
	var remaining: int = _director.condition

	for index: int in range(count):
		# index 0 at the bottom.
		var y: float = rect.position.y + rect.size.y - (index + 1) * segment_height - index * segment_gap
		var segment := Rect2(rect.position.x, y, rect.size.x, segment_height)
		draw_rect(segment, condition_color if index < remaining else track_color)

		if index != _flash_index or _flash <= 0.0:
			continue
		# Over the spent segment rather than in place of it: the flash is the moment the segment was
		# taken, sitting on the hole it left. Squared, so it reads at full strength and then goes,
		# for RunHud._apply_urgency's identical reason.
		var alpha: float = pow(_flash / flash_duration, 2.0)
		draw_rect(segment, Color(flash_color, alpha))
