class_name DebugHud
extends CanvasLayer

## Minimal debug HUD: plain unstyled Labels, a read-only view onto Kart's public physics and drift
## state, and the boost ghost field's count, each frame.

@export var target_path: NodePath
@export var boost_ghost_field_path: NodePath
@export var hazard_ghost_field_path: NodePath

var _target: Kart
var _boost_ghost_field: BoostGhostField
var _hazard_ghost_field: HazardGhostField

@onready var _speed_label: Label = $SpeedLabel
@onready var _road_label: Label = $RoadLabel
@onready var _ghost_count_label: Label = $GhostCountLabel
@onready var _boost_charges_label: Label = $BoostChargesLabel
@onready var _hazard_count_label: Label = $HazardCountLabel


func _ready() -> void:
	_target = get_node(target_path) as Kart
	_boost_ghost_field = get_node_or_null(boost_ghost_field_path) as BoostGhostField
	_hazard_ghost_field = get_node_or_null(hazard_ghost_field_path) as HazardGhostField


func _process(_delta: float) -> void:
	if _target != null:
		_speed_label.text = "Speed: %.1f" % _target.speed
		_boost_charges_label.text = "Boost charges: %d" % _target.boost_charges
		match _target.current_surface:
			Kart.SurfaceType.ROAD:
				_road_label.text = "On-road"
			Kart.SurfaceType.KERB:
				_road_label.text = "Kerb"
			Kart.SurfaceType.GRASS:
				_road_label.text = "Off-road"
			_:
				_road_label.text = "?"

	if _boost_ghost_field != null:
		_ghost_count_label.text = "Boost ghosts: %d" % _boost_ghost_field.ghost_count

	if _hazard_ghost_field != null:
		_hazard_count_label.text = "Hazard ghosts: %d" % _hazard_ghost_field.ghost_count
