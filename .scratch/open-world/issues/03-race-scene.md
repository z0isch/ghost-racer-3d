# scenes/race.tscn

Status: closed
Blocked by: 01, 02

One race scene, not one per circuit. Move everything `main.tscn` has today — Kart, ChaseCamera plus
Moebius, WorldEnvironment, Sun, Ground2, DebugHud, LapHud, CountdownHud, PurseHud, CoinField,
BoostGhostField, HazardGhostField, PaceGhost, LapDirector, PickupPopups — into `scenes/race.tscn`.

The circuit is not authored into the scene. A script on the root instantiates it during
`_enter_tree`, as a child named `Circuit`, at identity, so that:

- every existing NodePath (`../Circuit/StartLine`, `../Circuit/Coins`,
  `../Circuit/RoadManager/RoadContainer`, `../Circuit/BoostGhosts`, `../Circuit/HazardGhosts`,
  `../Circuit/Checkpoints`) resolves before `LapDirector._ready` runs;
- recorded ghost lines stay valid. `GhostLine.positions` are in circuit coordinates, and any world
  offset must never reach here.

Note the current paths say `Circuit2` while the instanced scene is `circuit4.tscn`. Rename the child
to `Circuit` and fix the paths here.

For the slice, hardcode circuit3: `scenes/circuit3.tscn` plus `ghost_lines/circuit3.tres`. Issue 07
replaces the hardcoding with the Track resource.

Add the `PurseLink` node from issue 02.

Done when: running `scenes/race.tscn` directly plays exactly as `main.tscn` does today, on circuit3.
