class_name GhostLine
extends Resource

## The ghost line's on-disk form: the same (positions, yaws) pair RunDirector holds in memory, plus
## the earn rate it was recorded at, so a session that loads a saved line can still be beaten by a
## better one rather than overwriting a fast line with a slow one.

@export var positions: PackedVector3Array = PackedVector3Array()
@export var yaws: PackedFloat32Array = PackedFloat32Array()
@export var earn_rate: float = -1.0

## What the recorded Run earned and how long it lasted — the two figures the results screen sets a
## new Run beside, alongside the checkpoint count [member checkpoint_samples] already carries and
## the rate above. Persisted rather than recomputed because a Run's length is not a constant (clocks
## and jumped hazards extend it) and the ladder's base value is per-circuit authored content: both
## can differ from what any later session would derive.
##
## The negative defaults are what a line saved before these existed loads as, and RunDirector
## reconstructs the pair rather than dropping the line.
@export var run_earnings: int = -1
@export var run_time: float = -1.0

## The sample index in [member positions] at which each checkpoint of the recorded Run was taken,
## in order — the whole Run's worth, running straight through every wrap. Written by RunDirector,
## which is the only thing that knows the moment.
##
## One consumer: IncomeRunner pays the checkpoint ladder at these indices rather than sweeping
## anything (CONTEXT.md's **Income**).
@export var checkpoint_samples: PackedInt32Array = PackedInt32Array()

## How many checkpoints the circuit had when this line was recorded, so a wrap boundary is
## checkpoint_samples[k * checkpoints_per_wrap - 1] without a second array that could disagree
## with the first.
@export var checkpoints_per_wrap: int = 0
