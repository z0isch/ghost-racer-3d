class_name RewindHud
extends CanvasLayer

## The Rewind screen: the scrub depth, large, over the road, and a small standing prompt line for
## hold/accept/decline. Its own CanvasLayer rather than a third state folded into CountdownHud:
## CountdownHud documents itself as owning "what the middle of the screen says between Runs" and is
## strictly exclusive between countdown and results — a Rewind is spatially the same slot, but the
## world underneath it is frozen rather than absent, which is a different enough beat (the kart, the
## traffic and the ghosts are all still standing there, mid-scrub) to earn its own class rather than
## stretch CountdownHud's stated invariant to cover a case it wasn't written for.
##
## Read-only and polled each _process, like RunHud: there is no discrete edge to catch here beyond
## the phase itself, and the depth changes every frame the scrub is held.

@export var director_path: NodePath
## Left up permanently, per CONTEXT.md's **Rewind**: nothing about it needs to fade.
@export var prompt_text: String = "hold to rewind — accept to resume, decline to wreck"

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

	var active: bool = _director.phase == RunDirector.RunPhase.REWIND
	visible = active
	if not active:
		return

	_depth_label.text = "-%.1fs" % _director.rewind_depth_seconds
