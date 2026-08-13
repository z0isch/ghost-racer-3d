# Language: boost pads in CONTEXT.md

Type: task
Status: open

Add the boost pad vocabulary to `CONTEXT.md` before any of it is written in code. This project fixes
its terms deliberately and every other system in it has an entry; four new words are about to enter
the codebase and one existing entry becomes wrong.

Land this first. Every other issue names these terms.

## New entries, under a **Boost** heading after **Money**

**Boost pad**:
A translucent, stationary ghost of the car standing on the road facing the direction of travel,
**taken** by driving through it — the same verb as a coin and the same swept test, and taken once is
taken for the rest of the lap. Every pad on a circuit is worth exactly the same, so a pad is a known
quantity you route around; what varies is where the pads are, not what each is worth.

A pad is a coin that pays in speed instead of money. That is the whole of the difference and it is
worth stating positively: both are taken by the path rather than touched, both are consumed for the
lap, both are restored whole at every countdown so two laps are offered the same track. Anything
true of the coin field's lifecycle is true here.
_Avoid_: Boost panel, ramp, speed strip, respawning (pads do not come back within a lap).

**Bump**:
The m/s a pad puts straight into forward speed the instant it is taken, above the tuned ceiling.
One-shot: there is no envelope and no duration.
_Avoid_: Boost amount, impulse, thrust, power.

**Bleed**:
The m/s² the kart sheds overspeed at until it is back at its ceiling. Together with the bump this is
the whole of a boost — how long one lasts is `bump / bleed` and is never authored directly, so no
second number can disagree with the first and no timer can drift out of sync with the speed.
_Avoid_: Decay, falloff, boost duration (the thing this exists to not be).

**Overspeed**:
How far above its ceiling the kart currently is, in m/s. Not a stored "boost amount": it is read off
the speed itself, so it cannot disagree with what the player sees. Zero is the normal condition.
_Avoid_: Boost remaining, boost meter, turbo.

## Amend the existing **Pace ghost** entry

The entry says the ghost is a thing you follow and never touch. That was the only translucent car in
the game; it no longer is. Add a sentence distinguishing them, and record *why* the collision turned
out not to matter, since it is the kind of thing that gets "fixed" later by someone who reads the
old entry: the pace ghost moves away from you at your own pace and a boost pad is stationary, and
that difference is what tells them apart in play. Colour is not doing the work and should not be
relied on to.

## Also worth stating

Boost pads have no effect on money and no effect on the coin field. They change the denominator of
the earn rate and nothing else. That is the whole of their relationship to the economy, and saying
so stops the question being reopened.

## Done when

- `CONTEXT.md` carries the four entries and the pace ghost amendment
- No term in it contradicts `docs/adr/`
