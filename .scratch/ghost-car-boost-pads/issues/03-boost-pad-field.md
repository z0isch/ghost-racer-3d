# The boost pad field

Type: task
Status: open
Blocked by: 02

The owner of the pads: where they are, which are currently taken, and the swept test that takes
them. Modelled on `CoinField` deliberately — same shape, same boundary, same reasons — and it should
read as its sibling.

**Not** a port of `scripts/prototype/boost_pad_field.gd`. That file is built around per-pad metadata
and a colour ramp, both of which the playtest rejected, and it is smaller once they are gone.

## Shape

`BoostPadField extends Node`, a sibling of `CoinField` in `main.tscn`.

```gdscript
signal pad_taken(position: Vector3)

@export var kart_path: NodePath
@export var director_path: NodePath
@export var pads_path: NodePath
@export var bump: float = 10.0        # m/s, every pad on the circuit
@export var bleed: float = 5.0        # m/s^2
@export var pickup_radius: float = 2.0
```

The boost is **on the field, not on the pads**. Every pad is worth the same; that is the finding, and
per-pad metadata is the thing being deleted. Pads are `Marker3D`s carrying a position and a Ghost
model child and nothing else.

The signal carries position only. There is no per-pad value to report, and nothing downstream needs
to know what a boost was worth.

## Behaviour

- Sweep the segment the kart travelled this frame, deferred, for `CoinField`'s reason: the director
  runs at the head of the physics frame and the kart moves after it. Re-check the phase inside the
  deferred call — the director's own sweep is queued first and can end the lap.
- Reuse `CoinField.segment_takes_coin` rather than re-deriving it. If sharing a coin-named static
  method between two callers reads badly, lift it to a small shared helper — but only then, and not
  by copying it.
- **A pad is taken once and stays taken for the rest of the lap**, exactly as a coin is. Restore
  every pad on `countdown_started`, so two laps are offered the same track. There is no respawn
  timer and no per-pad clock of any kind — a taken flag and the countdown restore are the whole
  lifecycle, and it is `CoinField`'s lifecycle line for line.
  (The prototype respawned pads after 3 s. That was a tuning affordance — it let a pad be driven at
  repeatedly without waiting a lap — and not a design position. It does not survive.)
- One translucent material, built in code and applied by walking the instanced FBX, as `PaceGhost`
  does and for the same reason: the model's internal node structure belongs to the importer.

## Explicitly not building

- **Per-pad `boost_bonus` / `boost_bleed` metadata.** Rejected: tuning converged on identical pads.
- **Colour by strength**, and the `strong_seconds` / `weak_color` / `strong_color` knobs with it.
  With uniform pads there is nothing for colour to say. One colour.
- **`strength_scale`.** A tuning-session knob. `bump` is the knob now.
- **The prototype HUD.** Scaffolding; nothing on main needs it.

The alpha pulse is a judgement call — it helped a pad read as a ghost rather than a parked car.
Keep it if it still earns its two lines, drop it if it does not.

## circuit3

**Copy the `BoostPads` subtree straight across from `prototype/ghost-car-boost-pads`**, minus the
`boost_bonus` / `boost_bleed` metadata lines. Five `Marker3D`s, each with a `Ghost` child instancing
`res://cars/FBX/SportsCar.fbx`, plus that ext_resource. The placements were arrived at by driving and
are the finding; there is nothing to regenerate.

No placement tool. Boost pads are hand-authored, and unlike checkpoints and coins they have no
even-spacing rule that a tool could express — where a pad goes is a judgement about the corner it
precedes. If that ever stops being true, `place_features.gd` is where it would go.

Two things to know about the interaction with `place_features.gd`, since it rewrites this scene:

- It leaves the subtree alone. `_is_generated_node` claims only the `Checkpoints` and `Coins` roots
  and their descendants, so `BoostPads` passes through as an ordinary preserved node block, and
  `_drop_orphaned_subs` touches sub-resources only, never the `SportsCar` ext_resource.
- It will move the subtree *above* `Checkpoints` and `Coins` in the file, because preserved nodes are
  emitted before the generated ones. Cosmetic, and not corruption.

## Done when

- Driving through a pad boosts it once; the pad is gone for the rest of the lap
- Every pad is back at the next countdown
- No per-pad metadata anywhere
- `check` and the suite are clean
