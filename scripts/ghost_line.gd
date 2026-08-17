class_name GhostLine
extends Resource

## The ghost line's on-disk form: the same (positions, yaws) pair LapDirector holds in memory, plus
## the earn rate it was recorded at, so a session that loads a saved line can still be beaten by a
## better one rather than overwriting a fast line with a slow one.

@export var positions: PackedVector3Array = PackedVector3Array()
@export var yaws: PackedFloat32Array = PackedFloat32Array()
@export var earn_rate: float = -1.0
