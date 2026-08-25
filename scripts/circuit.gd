class_name Circuit
extends Resource

## The definition of one circuit you can race: what its geometry is, where its ghost line
## persists, where its loadout persists, and what it is called.
##
## Read by both the world and the race scene, so the two cannot disagree about what a circuit is.
## Where the world stands a circuit is authored directly into main.tscn as that instance's own
## transform, not carried here — race.tscn always instances [member circuit_scene] at identity
## regardless, so ghost lines (recorded in the circuit's own coordinates) stay valid either way.

@export var circuit_scene: PackedScene
## One ghost line per circuit. Empty is valid — a circuit with no recorded Run yet, exactly as
## [method RunDirector._load_ghost_line] already treats a missing file: an empty ghost line, no
## pace, boost or hazard ghosts, exactly as a circuit's first Run always plays.
@export_file("*.tres") var ghost_line_path: String = ""
## One loadout per circuit, exactly parallel to [member ghost_line_path]. Empty is valid and means
## the same thing it does there: nothing bought yet, so [autoload LoadoutHolder] hands back a fresh
## zeroed CircuitLoadout.
@export_file("*.tres") var loadout_path: String = ""
@export var display_name: String = ""
## How long a Run on this circuit lasts, in seconds. Configured per circuit rather than a global
## constant, since the two existing circuits may want different budgets.
@export var run_duration_seconds: float = 23.0
## What the first checkpoint of a Run pays; the nth pays n times it (CONTEXT.md's **Checkpoint
## ladder**). One number for the whole circuit and deliberately not per-checkpoint: a checkpoint
## cannot be skipped, so its value can never be a decision. Value that varies is the clock's.
@export var base_checkpoint_value: int = 1
## Seconds between each extra hazard ghost added on top of the standing field —
## HazardGhostField.spawn_interval_seconds's own doc. 0.0 (or below) means a circuit's hazard
## traffic never thickens mid-Run, exactly as before checkpoint-driven spawning existed.
@export var hazard_spawn_interval_seconds: float = 8
## Seconds between each extra slipstream ghost added on top of the standing field —
## SlipstreamGhostField.spawn_interval_seconds's own doc. 0.0 (or below) means a circuit's
## slipstream traffic never thickens mid-Run, matching hazard_spawn_interval_seconds's own reason.
@export var slipstream_spawn_interval_seconds: float = 8
## Seconds added to the Run budget every time the checkpoint sequence wraps back to the first
## checkpoint — completing a full circuit pays a time bonus exactly as a clock pickup does. Per
## circuit rather than a global constant, since a short circuit's wrap is a much smaller fraction of
## a Run than a long one's. 0.0 means a wrap banks nothing, exactly as before this existed.
@export var wrap_bonus_seconds: float = 15.0
## How many wraps a Run may complete before it ends, independent of the clock. 0 means unlimited —
## a Run only ever ends by Timeout or Abort, exactly as before this existed. A short, tightly-looped
## circuit can want a race decided by laps rather than by outlasting a budget that a wrap bonus keeps
## refilling.
@export var max_wraps: int = 0

## How many slipstream ghosts caught in one Run fill the slipstream bar
## ([member RunDirector.slipstream_target]). Per circuit rather than a global constant for the same
## reason run_duration_seconds is: slipstream traffic thickens every
## [member slipstream_spawn_interval_seconds] of Racing, so a longer budget serves far more ghosts,
## and one shared number would top the bar out in the opening third of a long Run and leave it dead
## for the rest. A playtest dial — set it near what a well-driven Run on this circuit actually
## catches. 0 (or below) means this circuit has no target and the bar never fills.
@export var slipstream_bar_target: int = 6
