# Ghost-car boost pads

Type: prototype
Status: resolved — build it; see `## Answer` and `issues/`
Branch: `prototype/ghost-car-boost-pads` (throwaway, kept as the primary source; main carries none
of the prototype code, only the slip ceiling finding it turned up)

## The question

A boost pad shaped like a translucent ghost of the car, standing on the road facing the direction
of travel, that you drive *through* — Mario Kart 8's boost panel, but car-shaped.

Two things the playtest has to answer, and neither can be reasoned out on paper:

1. **Does a car-shaped pad read as "drive through me" rather than "avoid me"?** Every other
   car-shaped object in this game is either you or the pace ghost, and the pace ghost is
   explicitly a thing you do not touch. A pad that makes you flinch is a failed pad.
2. **What boost is worth what detour?** The circuit's whole incentive structure is the earn rate,
   so a boost is only interesting if it trades against the same thing a coin does: line. The three
   pads deliberately disagree with each other so the answer comes from comparison, not from one
   number feeling "fine".

## What is in the prototype

A boost is a **bump and a bleed**: taking a pad puts `bonus` m/s straight into forward speed, above
the tuned ceiling, and the kart then sheds that overspeed at `bleed` m/s² until it is back at its
normal top speed. There is no duration and no envelope — how long a boost is felt for is emergent,
`bonus / bleed`, so there is no second authored number that can disagree with the first, and no
timer that can drift out of sync with the speed on screen.

Additive m/s rather than a multiplier so a boost reads in the same unit as `max_speed` and the
speed line: "+7" against a 12 m/s ceiling needs no arithmetic. The trade is that retuning
`max_speed` no longer carries the boosts with it — the point being that a pad is worth a fixed
amount of speed rather than a fixed fraction of whatever the kart tops out at.

Three pads on circuit3, all bumping the same +7 m/s so that the **bleed** is the variable under
test, against a 12 m/s ceiling:

| Pad | Position | Boost |
| --- | --- | --- |
| `BoostPad00` | 14% of the lap | +7 m/s, bleeding 2.0 m/s² — a long glide, ~3.5 s |
| `BoostPad01` | 42% of the lap | +7 m/s, bleeding 6.0 m/s² — a sharp punch, ~1.2 s |
| `BoostPad02` | 74% of the lap, up on the crest | +7 m/s, bleeding 3.5 m/s² — middling, ~2.0 s |

Colour is lerped by `bonus / bleed` seconds rather than by the raw bonus: it is the one scalar that
folds both of a pad's numbers together, so a field where every pad bumps the same amount and only
the bleed differs still reads as three different pads.

While overspeed, the **throttle is inert** — it cannot hold the speed up, which is what makes the
bleed a decay you watch rather than a tug-of-war you can win. The **brake still bites**, and spends
the boost rather than banking it, so braking into a corner off a pad is a real choice.

### Why boost overspeed is tracked rather than inferred

`KartModel._boost_credit` records how much of the current overspeed a boost is still owed. Without
it, "speed above the ceiling bleeds off gradually" would also apply to **driving onto grass**, where
speed is currently clamped hard and instantly. A gradual grass penalty makes cutting corners viable
and quietly guts the reason the racing line is worth anything. Only credited overspeed bleeds;
uncredited overspeed is clamped exactly as before.

### Chaining

A pad tops the overspeed **up to** its own bonus rather than adding to it, so a pad is a ceiling on
how far above top speed it can put you and a chain of pads refreshes the boost instead of
compounding it. Stacking read fine for two pads and turned a pad run into a runaway: six +7 pads
became +42 of overspeed and twelve seconds of bleed.

It never reduces — a weak pad taken while carrying a strong boost leaves the strong one alone, so no
pad is ever a thing to swerve around.

A pad that grants nothing changes nothing, including the bleed rate. Without that, a weak pad with a
slow bleed taken during a strong fast-bleeding boost would hand the strong boost the slow rate and
stretch it: chaining by the back door, which is what the cap exists to stop.

The remaining way to extend a boost is to keep hitting pads, which holds the overspeed at one pad's
worth for as long as the pads keep coming and then bleeds once — bounded by pad spacing rather than
unbounded in the amount.

Pads respawn (default 3 s) rather than being consumed for the lap: a boost you can only take once
per lap tells you nothing about whether it is worth the line it costs. (This is what the prototype
did. It was a tuning affordance and does not survive to main — see `## Answer`.)

## Files

- `scripts/prototype/boost_pad_field.gd` — the pad field. Modelled on `CoinField`: markers under the
  circuit, the same swept-segment take test (`CoinField.segment_takes_coin`, reused), purely
  spatial, emits and knows nothing about who listens.
- `scripts/prototype/boost_pad_hud.gd` — bottom-left readout: live speed against the raised ceiling,
  a decaying boost bar, and what the last pad was worth.
- `tools/track/prototype_boost_pads.gd` — prints the `BoostPads` .tscn block for a set of positions.
  The loop walk and road sampling are lifted from `place_features.gd` rather than shared: this file
  is meant to be deleted, and a helper extracted for a prototype outlives the prototype.
- `scenes/circuit3.tscn` — the `BoostPads` subtree.
- `main.tscn` — the field and HUD nodes.
- `scripts/chase_camera.gd` — the boost FOV punch, marked `PROTOTYPE`.

## The FOV punch

The camera already widened with speed, but its `speed_fraction` saturates at `max_speed`, so the
entire overspeed range looked identical to cruising and a boost read as a number on the HUD rather
than as speed. `boost_fov_gain` adds degrees on top of `max_speed_fov`, driven by the **overspeed
rather than the speed**, so the widen tracks the bleed: it opens on the bump and closes as the boost
is spent, the same curve the driver feels through the wheels.

Attack is asymmetric — `boost_fov_attack` (30) on the way up while boosting, the soft `fov_smoothing`
(12) on the way down — so the widen snaps and the settle does not. A 12-rate ease spreads the punch
over half a second, by which time the bleed has already taken some of it back. It is gated on there
being a boost at all rather than on the target merely rising, so ordinary acceleration keeps its
existing feel.

Measured against a real `KartModel` with a +7 / 3.5 bleed pad:

| t | speed | overspeed | fov |
| --- | --- | --- | --- |
| cruising | 12.00 | — | 90.0 |
| 0.12 s | 18.59 | +6.59 | 101.1 |
| 0.50 s | 17.19 | +5.19 | 99.3 |
| 1.00 s | 15.50 | +3.50 | 96.5 |
| 2.00 s | 12.00 | +0.00 | 90.4 |

## The one production seam

`KartModel.apply_boost(bonus, bleed)` and `Kart.apply_boost(...)`, both marked `PROTOTYPE`.
Unavoidable: forward speed is clamped to the tuned maximum every step, so nothing outside
`kart_model.gd` can push the kart past it. Delete with the prototype, or keep if boost pads survive.

## Knobs to drag while driving

On the `PrototypeBoostPadField` node: `strength_scale` (scales every pad's boost at once, for
sweeping the whole idea up or down without editing the scene), `pickup_radius`, `respawn_seconds`,
the two colours and the pulse.

## Open questions the playtest should settle

- Does the pad want to sit **on** the racing line or off it? `BoostPad00` is on, the other two are
  off; the earn-rate design says off, but a boost you cannot miss may simply be a better rhythm.
- Which **bleed** reads best at a constant +7 bump: the 2.0 glide, the 6.0 punch, or the 3.5 middle?
  This is the live question — the three pads differ in nothing else.
- Once a bleed is settled, does the **bump** want to vary per pad again, or is one bump size with
  varying bleed the whole design?
- Additive means a boost is worth proportionally *more* at low speed, since it is the same m/s on
  top of a slower base. Does that reward taking a pad on a corner exit, and is that the right
  incentive, or does it want to be gated on already being fast?
- Is +12 degrees of FOV the right punch, and does it want company — a camera pullback, a lens dip
  *below* base as the boost expires for contrast, screen-edge streaks? FOV alone is the cheapest
  test of whether the speed feeling was ever a camera problem.
- Should a **hard bleed** be paired with a bigger bump, so a punch pad and a glide pad gain the same
  total distance and differ only in shape? Right now the glide pads gain considerably more.
- Does the ghost car want to be visibly *different* from the pace ghost — a different silhouette
  rather than a different colour — given CONTEXT.md's rule that the pace ghost is a thing you never
  touch?
- Does a boost belong in this game's economy at all, or does it flatten the coin detour choice by
  making lap time cheap?

## Answer

**Both questions answered yes. Build it on main.** Implementation issues are in `issues/`.

### 1. Does a car-shaped pad read as "drive through me"?

Yes, and the overlap with the pace ghost is a non-issue in practice — driven, the two never got
confused. The worry was that a translucent car is already established as a thing you never touch;
it turns out the pace ghost is *moving away from you at your own pace* and a pad is *stationary*,
and that difference does all the work the colour was supposed to do. No shape change needed.

### 2. What boost is worth what detour?

**+10 m/s, bleeding at 5.0 m/s²** — about two seconds above the ceiling, against a 12 m/s kart.
Reached by tuning while driving, not by argument.

### What the playtest rejected

- **Variable per-pad boosts.** The original request, and wrong. Tuning converged on five pads all
  carrying the identical boost. Uniform pads make the circuit legible: a pad is a known quantity you
  route around, and the interesting variable turned out to be *where the pads are*, not what each
  one is worth. This kills per-pad `boost_bonus`/`boost_bleed` metadata, the `strength_scale` knob,
  and the pad count being a spread rather than a placement.
- **Colour by strength.** Follows directly: with uniform pads there is nothing for colour to say.
  One colour for all pads.
- **Respawning pads.** The prototype brought a pad back 3 s after it was taken, on the reasoning that
  a boost you can take once a lap tells you nothing about whether it is worth the line it costs.
  True while tuning, and it was the right call for a prototype — but it was a tuning affordance
  mistaken for a design position. On main a pad is **taken once and stays taken for the rest of the
  lap**, exactly as a coin is, and is restored at the countdown with everything else. A pad becomes
  a coin that pays in speed instead of money, which is a smaller thing to explain and a smaller
  thing to build: a taken flag and the countdown restore, no per-pad clock.
- **The prototype HUD.** Scaffolding for reading numbers while tuning. Nothing on main needs it.
- **A placement tool.** See below.

### What the playtest settled, in order of how surprising it was

1. **Bump and bleed beats a raised ceiling.** The first two attempts held the speed *ceiling* up for
   an authored duration. Both felt like being on rails. Injecting speed once and letting drag take
   it back is the version that feels like a boost, and it deletes duration as an authored number.
2. **The throttle must be inert above the ceiling, and the brake must still bite.** Together these
   make the bleed something you watch and can spend, rather than a tug-of-war you can win.
3. **A pad caps the overspeed at its own bonus rather than adding to it.** Stacking was fine for two
   pads and a runaway for six. A pad that grants nothing must also not change the bleed rate,
   or chaining comes back through the bleed.
4. **The camera was half the "speed feeling" problem.** `ChaseCamera`'s speed fraction saturates at
   `max_speed`, so the entire overspeed range rendered identically to cruising. A FOV punch driven
   by the overspeed — snapping open, easing closed — is most of what makes a boost read.
5. **The boost exposed a pre-existing hole in the feel model**, which is the finding with the
   longest reach: the slip ceiling's speed taper leaves the kart numb exactly where it is fastest,
   and boosting pins it there. Braking now raises the high-speed end of the taper. This stands on
   its own merits and is **already on main** as `1f4582b`, ahead of any decision about pads.

### Where the prototype code stands

Main-quality already, transferring nearly verbatim (drop the `PROTOTYPE` markers):

- the `KartModel` boost seam — `_boost_credit`, `_boost_bleed`, `apply_boost`, two readouts, one
  branch in `_integrate_forward_speed`
- the `ChaseCamera` FOV punch — three exports and about fifteen lines

Carried over as data, not as code:

- The `BoostPads` subtree in `scenes/circuit3.tscn` — five markers whose placements were arrived at
  by driving, which makes them the finding rather than an input to one. Copy them across and drop
  the per-pad metadata.
- `tools/track/prototype_boost_pads.gd` is **dropped, not rebuilt**. It was 296 lines, most of them
  `place_features.gd`'s loop walk and road sampling copied — the right call for a prototype, since a
  helper extracted for a prototype outlives the prototype. But the reason to fold it into
  `place_features` was to keep generating pads, and there is nothing left to generate: five
  hand-placed markers exist and boost pads have no even-spacing rule for a tool to express. Where a
  pad goes is a judgement about the corner it precedes. Writing the tool would be building the
  general case for a set of five things that are already correct.

Needs rebuilding rather than tidying:

- `boost_pad_field.gd` is shaped around per-pad metadata, colour and a respawn timer, all three now
  rejected. The field owns one boost; pads become pure position markers with a taken flag.
- `CONTEXT.md` has no entry for any of this. Four new terms and one clarification are owed before
  the code lands, since this project fixes its vocabulary on purpose.
