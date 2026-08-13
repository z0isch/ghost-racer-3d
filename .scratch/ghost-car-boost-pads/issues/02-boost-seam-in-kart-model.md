# The boost seam in KartModel and Kart

Type: task
Status: open
Blocked by: 01

Give the feel model a way to be handed speed from outside it. This is the only change the whole
feature needs in the physics, and it is small: forward speed is clamped to the tuned ceiling every
step, so nothing outside `kart_model.gd` can push the kart past it today.

Transfers nearly verbatim from `prototype/ghost-car-boost-pads` — take the diff and drop the
`PROTOTYPE` markers. It is written and driven; this issue is about landing it, not designing it.

## KartModel

```gdscript
func apply_boost(bump: float, bleed: float) -> void
var overspeed: float      # m/s above the ceiling, read off the speed itself
var boost_remaining: float # overspeed / bleed, derived — there is no timer
```

State is two floats: `_boost_bleed`, and `_boost_credit` for how much of the current overspeed a
boost is still owed.

Four rules, each of which the prototype found the hard way and none of which is optional:

1. **Bump once, then bleed.** `apply_boost` adds to `_forward_speed` directly. The bleed carries it
   back down; there is no duration anywhere.
2. **The throttle is inert above the ceiling and the brake still bites.** Handle the overspeed case
   *before* the normal integration and return, so the bleed is a literal m/s² rather than the rate
   net of whatever acceleration just ran. Re-clamp the credit to the overspeed actually present each
   frame, so braking spends the boost instead of banking it.
3. **A pad tops the overspeed up to its bump, never adds to it, and never reduces it.** Stacking is
   fine for two pads and a runaway for six. A pad that grants nothing must return early *before*
   touching `_boost_bleed` — otherwise a weak slow-bleeding pad picked up during a strong
   fast-bleeding boost hands it the slow rate and chaining returns through the bleed.
4. **Only credited overspeed bleeds.** Speed above the ceiling with no credit — driving onto grass —
   stays clamped hard and instantly. This is `_boost_credit`'s entire reason to exist: a gradual
   grass penalty makes cutting corners viable and guts the reason the racing line is worth anything.

`reset()` clears both fields.

## Kart

A passthrough `apply_boost`, and `overspeed` / `boost_remaining` getters. It sits beside
`apply_impact` as the other thing the world does to the kart: the pad field decides a pad was taken,
the model owns what a boost does.

## Tests

`tests/kart_model_test.gd`. The prototype verified all of this with throwaway scripts; on main it
wants real coverage, because rules 3 and 4 are both invisible until someone breaks them:

- a bump lands instantly and is gone after `bump / bleed` seconds
- the throttle cannot hold overspeed up; the brake spends it faster
- three chained pads leave the same overspeed as one
- a pad taken part-way through a boost tops up rather than adding
- a weak pad during a strong boost changes neither the overspeed nor the bleed rate
- the first grass frame with no boost still clamps instantly

## Done when

- The suite passes and `check` is clean
- Nothing in `scripts/` says `PROTOTYPE`
