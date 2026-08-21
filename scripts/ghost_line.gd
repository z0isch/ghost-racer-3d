class_name GhostLine
extends Resource

## The ghost line's on-disk form: the same (positions, yaws) pair RunDirector holds in memory, plus
## the earn rate it was recorded at, so a session that loads a saved line can still be beaten by a
## better one rather than overwriting a fast line with a slow one.

@export var positions: PackedVector3Array = PackedVector3Array()
@export var yaws: PackedFloat32Array = PackedFloat32Array()
@export var earn_rate: float = -1.0

## The sample index in [member positions] at which each checkpoint of the recorded Run was taken,
## in order — the whole Run's worth, running straight through every wrap. Written by RunDirector,
## which is the only thing that knows the moment.
##
## Two consumers, for two different reasons: HazardGhostField slices one wrap's worth of line out
## of it to place a field along, and IncomeRunner pays the checkpoint ladder at these indices
## rather than sweeping anything (CONTEXT.md's **Income**).
@export var checkpoint_samples: PackedInt32Array = PackedInt32Array()

## How many checkpoints the circuit had when this line was recorded, so a wrap boundary is
## checkpoint_samples[k * checkpoints_per_wrap - 1] without a second array that could disagree
## with the first.
@export var checkpoints_per_wrap: int = 0
