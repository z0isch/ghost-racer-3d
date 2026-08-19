# Add circuit4 to the world

Status: closed
Blocked by: 07

Write `tracks/circuit4.tres` and instance `scenes/circuit4.tscn` in the world alongside circuit3.

Both circuits are authored around the origin and currently overlap exactly. Give them
`world_transform` offsets placing them roughly 150 m apart: a short drive, both comfortably inside
the existing 1000x1000 ground, so the world reads as "two circuits and the space between them"
rather than as a long empty commute. No ground resize.

Ghost lines go per circuit. `ghost_lines/circuit3.tres` stays as circuit3's, and circuit4 starts
with no ghost line — `LapDirector._load_ghost_line` already treats a missing file as an empty line,
so the first lap there simply has no pace, boost or hazard ghosts, exactly as lap 1 always does.

Note the current wiring in `main.tscn` runs circuit4's geometry against circuit3's recorded line
(main.tscn:216 against main.tscn:333). That mismatch dies here.

Done when: both circuits stand in the world, each enters its own race scene, and each keeps its own
record earn rate and ghost line across a session.
