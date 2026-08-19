extends Node

## The state a scene swap between the open world and a race scene must not lose: which circuit is
## about to be raced, and where the kart should reappear in the world when it exits.
##
## An autoload for the same reason as [autoload Purse]: this state must survive the scene change
## that would otherwise destroy it. Kept separate from Purse rather than folded into one Session
## bag, for the reason CONTEXT.md's **Purse holder** entry gives against the purse becoming a
## general state bag — a single-purpose owner does not become one either.

## The circuit a CircuitEntryTrigger just sent the kart to race. Read by [script race.gd] to pick
## which circuit_scene to instance and which ghost_line_path to give the LapDirector.
var pending_circuit: Circuit = null

## Where the world places the kart on return from a race scene, and whether that placement is
## still pending. World._ready consumes and clears the flag, so a plain load of main.tscn outside
## the entry/exit flow is not mistaken for a return and does not move the kart off its authored
## spawn.
var return_pose: Transform3D = Transform3D.IDENTITY
var has_return_pose: bool = false
