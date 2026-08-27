class_name DebugHud
extends CanvasLayer

## Minimal debug HUD: plain unstyled Labels, a read-only view onto Kart's speed and surface, each
## frame.
##
## Trimmed to speed and surface, since this runs in the open world too, where there is no boost or
## hazard field to read from. hazard_field_path/slipstream_field_path are the one exception: left
## unset (as the world's own HUD instance leaves them), [member _spawn_interval_label] is simply
## never shown, rather than this class growing a hard dependency on either field.

@export var target_path: NodePath
## The race's own HazardGhostField, read-only, for its spawn_interval_seconds — race.gd's dev keys
## edit that property, not the Circuit resource's, so this must read the field too, not the circuit.
@export var hazard_field_path: NodePath
@export var slipstream_field_path: NodePath

var _target: Kart
var _hazard_field: HazardGhostField
var _slipstream_field: SlipstreamGhostField

@onready var _speed_label: Label = $SpeedLabel
@onready var _road_label: Label = $RoadLabel
@onready var _spawn_interval_label: Label = get_node_or_null("SpawnIntervalLabel") as Label
## Optional, for _spawn_interval_label's own reason: this HUD runs in the open world too, where
## there is no circuit and so no Tune (CONTEXT.md's **Tune**). Authored into race.tscn's HUD only.
@onready var _tune_label: Label = get_node_or_null("TuneLabel") as Label


func _ready() -> void:
	_target = get_node(target_path) as Kart
	_hazard_field = get_node_or_null(hazard_field_path) as HazardGhostField
	_slipstream_field = get_node_or_null(slipstream_field_path) as SlipstreamGhostField


func _process(_delta: float) -> void:
	if _target == null:
		return

	_speed_label.text = "Speed: %.1f" % _target.speed
	match _target.current_surface:
		Kart.SurfaceType.ROAD:
			_road_label.text = "On-road"
		Kart.SurfaceType.MUD:
			_road_label.text = "Mud"
		Kart.SurfaceType.GRASS:
			_road_label.text = "Off-road"
		_:
			_road_label.text = "?"

	if _tune_label != null:
		_tune_label.text = "Tune: +%.1f" % _target.tune

	if _spawn_interval_label == null:
		return
	if _hazard_field == null and _slipstream_field == null:
		_spawn_interval_label.visible = false
		return

	_spawn_interval_label.visible = true
	var hazard_seconds: float = _hazard_field.spawn_interval_seconds if _hazard_field != null else 0.0
	var slipstream_seconds: float = (
		_slipstream_field.spawn_interval_seconds if _slipstream_field != null else 0.0)
	_spawn_interval_label.text = "Spawn interval: hazard %.1fs / slipstream %.1fs" % [
		hazard_seconds, slipstream_seconds]
