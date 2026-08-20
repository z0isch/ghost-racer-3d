class_name CircuitEntryHud
extends CanvasLayer

## The bottom-of-screen prompt telling the player they can enter a race right now. Shown exactly
## while some [CircuitEntryTrigger] reports itself [member CircuitEntryTrigger.eligible] — the
## kart standing on that circuit's own track — and hidden the rest of the time.
##
## Polls every trigger in [const CircuitEntryTrigger.GROUP_NAME] each frame rather than holding a
## reference to any one of them: the open world can hold any number of circuits, and this HUD does
## not need to know how many or where.
##
## The prompt names whichever input actually fires "enter_circuit", read from the InputMap rather
## than hardcoded, so rebinding the action changes what the player is told to press. It shows the
## bound joypad button when a joypad is connected — matching what the player's hand is actually on
## — and the bound key otherwise; a player who plugs a controller in mid-session sees the prompt
## follow on the very next frame, since this is read fresh every time, not cached at _ready.

const ACTION: StringName = &"enter_circuit"

## Godot ships no button-name lookup (there is no single glyph set — layouts disagree even on
## what "A" means), so the common face/shoulder/d-pad buttons are named by hand. An index missing
## here still shows as "Button N" rather than failing to show a prompt at all.
const JOY_BUTTON_NAMES: Dictionary[int, String] = {
	JOY_BUTTON_A: "A",
	JOY_BUTTON_B: "B",
	JOY_BUTTON_X: "X",
	JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Back",
	JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_SHOULDER: "LB",
	JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D-Pad Up",
	JOY_BUTTON_DPAD_DOWN: "D-Pad Down",
	JOY_BUTTON_DPAD_LEFT: "D-Pad Left",
	JOY_BUTTON_DPAD_RIGHT: "D-Pad Right",
}

@onready var _label: Label = $PromptLabel


func _process(_delta: float) -> void:
	_label.text = "Press %s to enter a race" % _action_glyph() if _any_eligible() else ""


func _any_eligible() -> bool:
	for trigger: Node in get_tree().get_nodes_in_group(CircuitEntryTrigger.GROUP_NAME):
		if (trigger as CircuitEntryTrigger).eligible:
			return true
	return false


## The label for whichever [const ACTION] event best matches the player's current input: a
## joypad button if a joypad is connected and the action is bound to one, else a key. Falls back
## to the other kind of binding if the preferred kind is not present, and to the raw action name
## if neither is.
func _action_glyph() -> String:
	var key_event: InputEventKey = null
	var joy_event: InputEventJoypadButton = null
	for event: InputEvent in InputMap.action_get_events(ACTION):
		if key_event == null and event is InputEventKey:
			key_event = event as InputEventKey
		elif joy_event == null and event is InputEventJoypadButton:
			joy_event = event as InputEventJoypadButton

	var prefer_joypad: bool = Input.get_connected_joypads().size() > 0
	if prefer_joypad and joy_event != null:
		return _joy_button_glyph(joy_event.button_index)
	if key_event != null:
		return OS.get_keycode_string(key_event.physical_keycode as Key)
	if joy_event != null:
		return _joy_button_glyph(joy_event.button_index)
	return String(ACTION)


func _joy_button_glyph(button_index: int) -> String:
	return JOY_BUTTON_NAMES.get(button_index, "Button %d" % button_index)
