class_name Circuit
extends Resource

## The definition of one circuit you can race: what its geometry is, where its ghost line
## persists, what it is called, and where the world stands it.
##
## Read by both the world and the race scene, so the two cannot disagree about what a circuit is.
## [member world_transform] is applied by the world only — the race scene always instances
## [member circuit_scene] at identity, so ghost lines (recorded in the circuit's own coordinates)
## stay valid regardless of where the world stands the circuit.

@export var circuit_scene: PackedScene
## One ghost line per circuit. Empty is valid — a circuit with no recorded lap yet, exactly as
## [method LapDirector._load_ghost_line] already treats a missing file: an empty ghost line, no
## pace, boost or hazard ghosts, exactly as lap 1 always plays.
@export_file("*.tres") var ghost_line_path: String = ""
@export var display_name: String = ""
@export var world_transform: Transform3D = Transform3D.IDENTITY
