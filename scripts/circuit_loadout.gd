class_name CircuitLoadout
extends Resource

## What one player has bought — and, since [member tune], earned — for one circuit: how many
## clocks are live on it, how many boost ghosts, how many hazard ghosts, how many slipstream
## ghosts, how many income ghosts, and how much top speed it has earned. Five raw counts rather
## than levels, all starting at 0 and rising only by being bought, plus one quantity that is not
## a count at all (CONTEXT.md's **Circuit loadout**, CONTEXT.md's **Tune**).
##
## No upper clamp here — the cap on clocks is the circuit's authored clock total, which this
## resource has no way to know. That clamp happens where the clock field resolves its live count
## ([method ClockField._resolve_clocks]). income_ghost_count has no meaningful cap at all. tune's
## clamp is likewise not here: its ceiling is derived from KartTuning, which this resource has no
## way to know either, so it is clamped at the award site instead (race.gd's _on_run_completed).

@export var clock_count: int = 0:
	set(value):
		clock_count = maxi(value, 0)

@export var boost_ghost_count: int = 0:
	set(value):
		boost_ghost_count = maxi(value, 0)

@export var hazard_ghost_count: int = 0:
	set(value):
		hazard_ghost_count = maxi(value, 0)

@export var slipstream_ghost_count: int = 0:
	set(value):
		slipstream_ghost_count = maxi(value, 0)

## Consumed only by [autoload IncomeRunner], which sits inside no scene — unlike the other three,
## never pushed into a race scene's fields (CONTEXT.md's **Loadout holder**).
@export var income_ghost_count: int = 0:
	set(value):
		income_ghost_count = maxi(value, 0)

## m/s of permanent top-speed gain this circuit has earned (CONTEXT.md's **Tune**). Unlike the
## five counts above, driven for rather than paid for — awarded, not bought — and floored rather
## than clamped above, since this resource has no way to know its own ceiling. See race.gd's
## _on_run_completed for where that ceiling is applied.
@export var tune: float = 0:
	set(value):
		tune = maxf(value, 0.0)
