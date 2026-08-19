# Open world

Status: closed

`main.tscn` stops being the one circuit you drive and becomes an **open world** holding both
circuits. Driving across a circuit's start line loads a **race scene** — a self-contained scene that
is everything `main.tscn` does today, pointed at that one circuit. Leaving a race scene returns you
to the world where you entered it.

This falsifies `CONTEXT.md`'s opening sentence ("A single-circuit kart game"). The lap, the coin
field, the ghost line, the boost and hazard fields and the earn rate are all unchanged — they simply
now live in the race scene rather than in the only scene.

## What the open world is

The existing 1000x1000 ground, with both `scenes/circuit3.tscn` and `scenes/circuit4.tscn`
instanced roughly 150 m apart. The circuits' real geometry, not portals or markers: you drive up to
the actual start/finish gate you are about to race through.

Nothing lap-shaped runs out there. No lap director, no lap clock, no checkpoints, no pace ghost, no
boost or hazard ghosts. Gates render dimmed, since with no pending checkpoint a lit gate would be a
lie. Coins stand where they are authored and are uncollectible — they are the visible advertisement
that a circuit pays. The purse readout stays, because the purse is session-scoped and is not a
racing stat; the HUD is otherwise trimmed to speed and surface.

`reset` in the world means "return the kart to a sane world spawn". It does not mean abort — there
is no lap to abort.

## What a race scene is

One scene, `scenes/race.tscn`, not one per circuit. It carries everything `main.tscn` carries today
and instantiates the chosen circuit as a child named `Circuit` at **identity** during `_enter_tree`,
before `LapDirector._ready` resolves its exported NodePaths. Instancing at identity is what keeps
the existing recorded ghost lines valid: `GhostLine.positions` are recorded in the circuit's own
coordinates, and the world's positional offsets must never reach the race scene.

Copying `main.tscn` once per circuit was rejected: it forks the kart tuning, the camera, the HUD and
the field wiring N ways, and every tuning tweak then has to land N times. Godot inherited scenes
were rejected too — an inherited scene cannot cleanly swap which `PackedScene` an inherited child
instances.

## What a track is

A `Track` resource, one `.tres` per circuit, is the single definition of "a circuit you can race":

- `circuit_scene: PackedScene`
- `ghost_line_path: String` — one ghost line per circuit; `circuit4` starts with none
- `display_name: String`
- `world_transform: Transform3D` — applied **only** by the world

Both the world and the race scene read the same resource, so the two cannot disagree about what a
circuit is.

> Open naming question: `CONTEXT.md` uses **circuit** for this thing and lists "track" nowhere.
> The spec keeps `Track` because that is the word used while designing it, but `Circuit` would match
> the glossary. Worth settling before the resource type is written.

## Entry and exit

**Entry** reuses the lap director's swept prism test against the circuit's `StartLine` marker: a
segment crossing, bounded laterally and vertically, so it cannot be tunnelled at any speed and
cannot fire while you are off the road beside the line. Either direction counts. Crossing records
the kart's current pose into `TrackSession`, fades out over ~0.3 s, and loads `scenes/race.tscn`,
which opens with the ordinary 3-second countdown.

**Exit** is a new `exit_track` input action, live in any lap phase. It discards the in-progress lap
exactly as an abort does — the record earn rate and the ghost line have already been persisted to
`.tres` by then — fades, and returns to the world at the recorded pose. That pose is on the entry
line, so the circuit's trigger stays disarmed until the kart has been clear of the prism for a beat.

## Autoloads

The project has none today; this adds the first two, deliberately kept separate:

- **`Purse`** — money only. It moves here because a scene swap would otherwise destroy the session
  total, which directly contradicts what the purse is. `purse.gd`'s class comment currently argues
  the opposite ("Not an autoload: ... this game has one scene it never reloads") and must be
  rewritten. `CoinField` stays ignorant of who consumes its pickups: a small `PurseLink` node in
  `race.tscn` connects `coin_taken` to the autoload.
- **`TrackSession`** — the pending track, the return pose, and the entry cooldown. Not folded into
  `Purse`, for the same reason `CONTEXT.md`'s **Purse holder** entry gives for keeping the purse off
  the lap director: a single-purpose owner does not become a general state bag.

## Out of scope

- Tests. The entry trigger has real edge cases and would be worth a suite, but this is a prototype.
- An ADR. Reconsider when the scene-swap decision stops being provisional.
- Any change to lap, coin, boost, hazard or ghost-line behaviour.

## Build order

A vertical slice: get circuit3 round-tripping world -> race -> world with a hardcoded path first,
because the thing most likely to be wrong is how the swap *feels* — the fade length, the return
pose, the countdown on arrival. Generalising to the `Track` resource and adding circuit4 afterwards
is mechanical. Issues `01`-`06` are the slice; `07`-`10` generalise and tidy.
