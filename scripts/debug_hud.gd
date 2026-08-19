class_name DebugHud
extends CanvasLayer

## Minimal debug HUD: plain unstyled Labels, a read-only view onto Kart's speed and surface, each
## frame.
##
## Trimmed to speed and surface, since this runs in the open world too, where there is no boost or
## hazard field to read from.

@export var target_path: NodePath

var _target: Kart

@onready var _speed_label: Label = $SpeedLabel
@onready var _road_label: Label = $RoadLabel


func _ready() -> void:
	_target = get_node(target_path) as Kart


func _process(_delta: float) -> void:
	if _target == null:
		return

	_speed_label.text = "Speed: %.1f" % _target.speed
	match _target.current_surface:
		Kart.SurfaceType.ROAD:
			_road_label.text = "On-road"
		Kart.SurfaceType.KERB:
			_road_label.text = "Kerb"
		Kart.SurfaceType.GRASS:
			_road_label.text = "Off-road"
		_:
			_road_label.text = "?"
