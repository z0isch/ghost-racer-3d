# Track entry and exit, with the fade

Status: closed
Blocked by: 04, 05

The ticket the whole slice exists to reach: the swap, felt end to end.

## Entry

A trigger node in the world tests the kart's swept segment against the circuit's `StartLine` marker
using the same prism rule as the lap director's checkpoint sweep (scripts/lap_director.gd:339): a
plane crossing bounded laterally (4 m each side) and vertically, so it cannot be tunnelled at any
speed and cannot fire while driving past beside the line. Either direction counts.

On crossing: record the kart's pose into `TrackSession`, fade to black over roughly 0.3 s, then
`change_scene_to_file("res://scenes/race.tscn")`. The race scene opens with the ordinary 3-second
first countdown.

## Exit

New `exit_track` input action (Esc plus a gamepad menu button) in `project.godot`, live in any lap
phase. It discards the in-progress lap the way an abort does — the record earn rate and the ghost
line are already persisted to `.tres` by then — fades, and loads `main.tscn`.

Deliberately a separate action from `reset`. Abort and exit are different intents with different
costs; a hold-to-exit overload that misfires throws away a good lap.

## Return

The world reads the return pose from `TrackSession` and places the kart there. That pose is on the
entry line, so that circuit's trigger starts disarmed and re-arms only once the kart has been fully
outside the prism for a moment. Without this the first metre driven bounces you straight back into
the race scene.

Done when: world to circuit3 to `exit_track` to world round-trips cleanly, the purse survives both
directions, and you are not immediately re-entered on return.
