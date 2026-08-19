# Track resource

Status: closed
Blocked by: 06

Replace the hardcoded circuit paths from issues 03 and 04 with a `Track` resource, one `.tres` per
circuit:

- `circuit_scene: PackedScene`
- `ghost_line_path: String`
- `display_name: String`
- `world_transform: Transform3D`

`world_transform` is applied by the world only. The race scene always instances at identity.

`TrackSession.pending_track` becomes a `Track`. The world's entry trigger carries the `Track` of the
circuit it guards. `LapDirector.ghost_line_path` is set from the track at load.

Write `tracks/circuit3.tres`. Circuit4's arrives in issue 08.

Settle the naming first: CONTEXT.md uses **circuit** throughout and never says "track". If the
glossary wins, this is `Circuit` / `CircuitSession` / `exit_circuit`, and the rename should happen
here rather than after more code depends on it.

Done when: no circuit path is hardcoded in `race.tscn` or `main.tscn`, and circuit3 still
round-trips.
