class_name PurseLink
extends Node

## Connects a scene's RunDirector to the Purse autoload.
##
## The director cannot reach an autoload without its own ignorance costing something, so a scene
## that wants its checkpoints to pay places one of these.
##
## Nothing connects the clock field to the purse. That absence is the point — a clock pays in
## seconds and never in money — and this is the one node that could have made that mistake.

@export var director_path: NodePath


func _ready() -> void:
	var director: RunDirector = get_node_or_null(director_path) as RunDirector
	if director == null:
		push_warning("PurseLink: no RunDirector — nothing can be earned.")
		return

	# unbind(2) drops checkpoint_paid's position and direction arguments, which the purse has no
	# use for. Godot does not drop surplus arguments by itself: connected bare, every pickup would
	# fail at emit time.
	director.checkpoint_paid.connect(_on_checkpoint_paid.unbind(2))


func _on_checkpoint_paid(value: int) -> void:
	Purse.add(value)
