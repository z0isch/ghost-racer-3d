class_name RewindHud
extends CanvasLayer

## The Rewind screen: the scrub depth, large, over the road, and a small standing prompt line for
## hold/release/decline. Its own CanvasLayer rather than a third state folded into CountdownHud:
## CountdownHud documents itself as owning "what the middle of the screen says between Runs" and is
## strictly exclusive between countdown and results — a Rewind is spatially the same slot, but the
## world underneath it is frozen rather than absent, which is a different enough beat (the kart, the
## traffic and the ghosts are all still standing there, mid-scrub) to earn its own class rather than
## stretch CountdownHud's stated invariant to cover a case it wasn't written for.
##
## Read-only and polled each _process, like RunHud: there is no discrete edge to catch here beyond
## the phase itself, and the depth changes every frame the scrub is held.
##
## Also up through RunPhase.RESUMING, the short held beat between accepting a Rewind and Racing
## actually starting back up (RunDirector.rewind_resume_pause_seconds) — the world is still frozen
## for that beat, so the screen stays too, showing "GO!" in the depth label's place.

@export var director_path: NodePath
## Left up permanently, per CONTEXT.md's **Rewind**: nothing about it needs to fade.
@export var prompt_text: String = "hold Y to rewind"

var _director: RunDirector

@onready var _depth_label: Label = $DepthLabel
@onready var _prompt_label: Label = $PromptLabel


func _ready() -> void:
	_director = get_node_or_null(director_path) as RunDirector
	_prompt_label.text = prompt_text
	visible = false


func _process(_delta: float) -> void:
	if _director == null:
		return

	var phase: RunDirector.RunPhase = _director.phase
	# RESUMING stays on screen too: the world is still frozen for that beat, and dropping the HUD
	# the instant the scrub is released would leave a frozen frame with nothing on it to explain why.
	var active: bool = phase == RunDirector.RunPhase.REWIND or phase == RunDirector.RunPhase.RESUMING
	visible = active
	if not active:
		return

	if phase == RunDirector.RunPhase.RESUMING:
		_depth_label.text = "GO!"
	else:
		_depth_label.text = "-%.1fs" % _director.rewind_depth_seconds
