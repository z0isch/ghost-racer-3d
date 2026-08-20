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
## One ghost line per circuit. Empty is valid — a circuit with no recorded lap yet, exactly as
## [method LapDirector._load_ghost_line] already treats a missing file: an empty ghost line, no
## pace, boost or hazard ghosts, exactly as lap 1 always plays.
@export_file("*.tres") var ghost_line_path: String = ""
## One loadout per circuit, exactly parallel to [member ghost_line_path]. Empty is valid and means
## the same thing it does there: nothing bought yet, so [autoload LoadoutHolder] hands back a fresh
## zeroed CircuitLoadout.
@export_file("*.tres") var loadout_path: String = ""
@export var display_name: String = ""
