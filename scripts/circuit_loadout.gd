class_name CircuitLoadout
extends Resource

## What one player has bought for one circuit: how many coins are live on it, how many boost
## ghosts, how many hazard ghosts. Three raw counts rather than levels, all starting at 0 and
## rising only by being bought (CONTEXT.md's **Circuit loadout**).
##
## No upper clamp here — the cap on coins is the circuit's authored coin total, which this
## resource has no way to know. That clamp happens where the coin field resolves its live count
## ([method CoinField._resolve_coins]).

@export var coin_count: int = 0:
	set(value):
		coin_count = maxi(value, 0)

@export var boost_ghost_count: int = 0:
	set(value):
		boost_ghost_count = maxi(value, 0)

@export var hazard_ghost_count: int = 0:
	set(value):
		hazard_ghost_count = maxi(value, 0)
