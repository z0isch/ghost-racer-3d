class_name CountdownHud
extends CanvasLayer

## The countdown readout. Its own CanvasLayer rather than a Label in DebugHud, which is an unstyled
## corner readout of physics state; this is the one thing a player reads under time pressure, so it
## wants the middle of the screen and a large face.
##
## Read-only and polled each _process, as DebugHud polls Kart.

@export var director_path: NodePath
## How long "GO!" hangs after the freeze releases.
@export var go_display_seconds: float = 0.6
## Shown during Results, telling the player how to start a new Run.
@export var results_prompt: String = "press RESET to run again"

var _director: RunDirector

@onready var _label: Label = $CountdownLabel


func _ready() -> void:
	_director = get_node_or_null(director_path) as RunDirector


func _process(_delta: float) -> void:
	if _director == null:
		return

	match _director.phase:
		# Ceil, so a 3.0 s countdown reads 3 → 2 → 1 with a full second each rather than
		# flashing "3" for one frame.
		RunDirector.RunPhase.COUNTDOWN:
			_label.text = str(maxi(1, ceili(_director.phase_remaining)))
		RunDirector.RunPhase.RACING:
			_label.text = "GO!" if _director.run_clock < go_display_seconds else ""
		# Results is a real stop, not a held instant — tell the player how to continue.
		RunDirector.RunPhase.RESULTS:
			_label.text = results_prompt
		_:
			_label.text = ""
