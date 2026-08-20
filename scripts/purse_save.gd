class_name PurseSave
extends Resource

## The purse's on-disk form: the running total and nothing else.
##
## Matches the GhostLine/CircuitLoadout serialization idiom, but lives under user:// rather than
## res:// ([autoload Purse]'s own reason): a purse fed by a passive earner has to survive a real
## exported build, where res:// is read-only once packed.

@export var total: int = 0
