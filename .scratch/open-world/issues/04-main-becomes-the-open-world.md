# main.tscn becomes the open world

Status: closed
Blocked by: 01, 03

Strip `main.tscn` down to the world.

Keep: WorldEnvironment, Sun, Ground2, Kart (referencing the shared tuning from issue 01),
ChaseCamera plus Moebius, PurseHud.

Remove: LapDirector, CoinField, BoostGhostField, HazardGhostField, PaceGhost, PickupPopups, LapHud,
CountdownHud.

`DebugHud` stays, trimmed to speed and surface. Leave `boost_ghost_field_path` and
`hazard_ghost_field_path` empty and drop the two labels: dead labels showing plausible numbers
("Boost ghosts: 5") are worse than no labels.

Instance `scenes/circuit3.tscn` for now; circuit4 arrives in issue 08.

`reset` in the world returns the kart to a world spawn pose. It does not abort anything, because
there is no lap.

`run/main_scene` stays `res://main.tscn`.

Done when: you can drive the open world, see the circuit's road, gates and coins, and nothing
lap-shaped is running or on screen.
