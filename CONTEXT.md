# Ghostracer

A kart game of two circuits reached from an open world: drive onto a circuit's own track and press a button to drive it, looping its ordered checkpoints for a fixed time budget — a **Run** — against a ghost of your highest-earning Run on it. The checkpoints are where the money is: each one pays more than the last, on a **checkpoint ladder** that runs unbroken through the whole Run, so a longer Run and a better-driven Run each necessarily earn more per second. What you chase is the best **earn rate** — dollars per second — and the one thing standing off the racing line is a **clock**, which buys you seconds rather than dollars, so every detour to one is a real choice rather than free time. There is no race and no opponents, but a Run does end: it is a fixed, timed attempt, not an indefinite loop, and it stops the moment the clock runs out or the player aborts it. What you buy with the money is a better circuit to earn on, and eventually **income ghosts**: copies of your own best Run that go on running it, and paying, while you are somewhere else.

## Language

### The run

**Run**:
One fixed-duration attempt at a circuit, timed from countdown-zero to the moment the clock reaches the circuit's configured duration (a **Timeout**), the kart runs out of **Condition** (a **Wreck**), or the player aborts it. Driven by looping the circuit's ordered checkpoints as many times as the time budget allows — the sequence wraps back to the first checkpoint every time the last one is taken, with no limit on how many times that happens inside a Run. The record-bearing unit, and the only one: a single pass through the checkpoints is named — a **wrap** — but nothing is scored or recorded per wrap, and the **checkpoint ladder** runs straight through every one of them. Its length is not quite fixed after all: a **clock** taken during a Run adds seconds to the budget, so a circuit's configured duration is the length of a Run nobody detoured on.
_Avoid_: Lap — this project used to organize play around laps, one ordered pass through the checkpoints that ended the moment the last one was taken; a Run replaces that shape entirely (see `docs/adr/0001-timed-circuit-runs.md`). Also avoid: race, circuit (the circuit is the track, not an attempt at it).

**Run phase**:
Which part of a Run is currently live — Countdown, Racing, Rewind or Results (`RunDirector.RunPhase.COUNTDOWN` / `.RACING` / `.REWIND` / `.RESULTS`). Exactly one is active at any moment. Unlike the old lap cycle, this does not return to Countdown on its own: Results is a real stop, and a new Run begins only when the player explicitly starts one.
Rewind is the one phase a Run can leave in either direction — back into Racing if the **Rewind** is taken, on to Results if it is declined — and the only one in which the Run clock is stopped while the Run is still live.
_Avoid_: Run state (too easily confused with the run's recorded data), mode, lap phase.

**Countdown**:
The phase before a Run, with the kart held motionless on the start line. Every Run is preceded by one — whether it follows a scene load, an abort, or the player explicitly starting a new Run from Results.

**Racing**:
The phase during which a Run is being driven and the clock is running. Ends only by Timeout, by Wreck or by Abort — never by completing the checkpoint sequence, which just wraps and keeps going. Condition reaching zero *suspends* it into **Rewind** rather than ending it; it becomes a Wreck only where the rewind is declined, and a taken rewind returns here.
_Avoid_: Running (reserved for the clock), driving, active.

**Results**:
The phase after a Run ends by Timeout or by Wreck, holding the Run's figures on screen until the player explicitly starts a new Run. A real, indefinite stop — not a held instant before an automatic return, the way the old Finished phase was.
What it shows is four totals — the Run's length, its earnings, its checkpoints taken and its earn rate — each beside the same figure from the Run before it, under a headline that is either the record or the exact dollars the Run fell short by. Deltas rather than totals alone, because the screen's job is to make the next Run worth starting and only a delta says whether the driver is getting better; the shortfall in dollars for the same reason, since a gap that can be closed by one more checkpoint on the ladder is an argument for another Run and "you lost" is not. Length is one of the four because a Run's length is not a constant — clocks buy seconds — so without it a larger earnings figure is ambiguous between a better line and a longer Run.
The comparison is against the **ghost line** the Run was driven against, never against the last Run driven — the ghost is the thing that was on the track, it is what the record is kept on, and it does not move when a bad Run happens. Measured against the last Run instead, two mediocre Runs in a row would show a column of green: a screen congratulating the driver for recovering from their own mistake rather than for getting anywhere. It survives a scene load and a session, exactly as the ghost line does; a circuit no Run has ever been completed on has no ghost, and there the screen shows totals with no delta column at all rather than comparing against a zero.
A Run that takes the record is compared against the ghost it *beat*, not against itself: the ghost is replaced the instant the Run is promoted, and a screen of zeroes is the opposite of what beating your best should look like.
An **Abort** never becomes a comparison, and never disturbs one: it has no result and cannot promote a ghost line.
A Run that took one or more **Rewind**s is reported here exactly as one that took none: four figures, the same deltas, the same headline, and no mention anywhere that it rewound. The seconds a rewind cost are already in the Run's length and absent from its earnings, so the earn rate has said the whole of it; a count beside the four would be a fifth figure that ranks nothing and that the ghost has no matching value for.
_Avoid_: Finished (the old, instant-then-loop phase this replaces), Game Over, scoreboard (nothing here ranks Runs against anything but the last one and the record).

**Timeout**:
The Run clock reaching the circuit's configured duration. Ends the Run immediately, wherever the kart happens to be between checkpoints, and keeps everything earned up to that instant: the run earnings stand, the earn rate is computed from them, and the Run may set a new record. One of the two ways a Run ends with a result; the other is a **Wreck**.
_Avoid_: Time up, expiry, finish.

**Abort**:
Ending a Run before Timeout, triggered by the player's `reset` action. Unlike a Timeout, an abort discards the Run outright: no result is shown, the run earnings are thrown away, no record earn rate can be set, and the pace ghost recorded so far is discarded. The money already taken stays in the purse.
_Avoid_: Restart, cancel, retry, timeout (a Timeout keeps its result; an abort has none).

**Condition**:
What a Run has left to absorb **hazard hit**s with: a small whole number of segments, starting full at every **Countdown** and losing one to each hazard driven into. Per-Run and nothing else — it is reset alongside the Run clock and the **checkpoint ladder**, because a Run is a clean priced attempt and Condition carried in from the Run before would let the previous attempt decide whether this one is drivable. Nothing restores it mid-Run: not a hopped hazard, not a checkpoint, not a **wrap**. Owned by the **run director**, not by the kart — the kart is a thing that drives, and what happens at zero is that a *Run* is suspended and possibly ended, which only the director may do.
A **Rewind** does not restore it either, and is a different thing: a rewind rolls Condition *back* along with every other thing a Run owns, to whatever it stood at a few seconds ago, rather than handing any back. Return from a rewind taken at zero and Condition is one — what it was before the hit that emptied it.
Because a rewind is unlimited and costs only Run-clock seconds, Condition is no longer a hard budget whose exhaustion ends a Run. It is a soft one, converted into seconds off the **earn rate** at a rate the driver picks in the moment. The Run clock is the hard budget now, and the only one: every Run still ends by **Timeout**, **Wreck** or **Abort**.
Deliberately small and integral rather than a pool of a hundred points. Hazards are consumed on contact and thicken as a Run goes on, so the interesting range is a handful of hits; a large pool would only ever be drawn as a few chunky jumps pretending to be a smooth drain.
_Avoid_: HP, health, hit points, lives, damage (the *loss* of a segment, not the resource), durability.

**Wreck**:
A Run's Condition reaching zero **with the rewind declined**. Ends the Run immediately, exactly as a **Timeout** does and with exactly the same standing: everything earned up to that instant is kept, the earn rate is computed from it, and the Run may set a new record. Not an **Abort** — the driver did not throw the Run away, they ran out of one of its two budgets, and the **checkpoint ladder** has already priced the mistake by ending the earning early.
Condition reaching zero no longer reaches here on its own: it opens a **Rewind** first, and a Wreck is what is left when the driver turns that down. The beat the wreck used to hold — **Results** waiting, kart frozen where it stopped and nothing drawn, because a Timeout is watched down to and a Wreck is a surprise — is now the rewind's own opening, and Results follows it only where the offer was refused. A Run that wrecks *and* takes the record is headlined as the record — the wreck was just seen, and the record is the thing that cannot be seen from it.
_Avoid_: Death, crash (a barrier impact is a crash and costs nothing), game over, DNF, fail.

**Rewind**:
Taking a Run back a few seconds after its Condition reaches zero, and driving on. The instant the last segment goes, the Run enters the Rewind **run phase**: everything stops — the Run clock, the traffic, the kart — and the driver scrubs the world backward in real time, as far as a tuned cap (eight seconds today) or the Run's own start, whichever comes first. Accepting resumes Racing from the instant scrubbed to; declining takes the **Wreck**. There is no limit on how many a Run may take, and no budget to spend: the cap bounds one rewind's depth and nothing bounds their number.
What comes back is everything a Run owns — the kart's pose, its motion, its drift and its banked boosts; **Condition**; the **checkpoint ladder**'s rung; run earnings; the pending checkpoint; wraps closed; slipstream ghosts caught; the taken flag of every clock, boost ghost, hazard ghost and slipstream ghost; and the hazard and slipstream cars' own positions along their lanes, including un-spawning the traffic that thickened onto the circuit after the instant being returned to. A rewind that lands on a state the Run was never in is the one way this fails, so what it restores is captured whole, once a frame, after everything else in that frame has resolved. What does not come back is the **purse**, which outlives a Rewind for the same reason it outlives a Run and an **Abort**.
And what does not come back is the **Run clock**, which is the entire price and the only one. The seconds scrubbed away are seconds the Run has already spent and has to spend again, the **pace ghost** does not wait through them — its pose is a function of the Run clock, so the gap it opens is the gap the rewind really cost — and the **earn rate** wears all of it. Priced that way it needs no currency of its own: a bought count would be a second budget for something the Run's existing budget already prices, and a Run clock that rewound with the world would make the rewind free and the earn rate a lie.
A rewind may cross a **wrap** boundary, which is the one place it is not a perfect reversal: the clock and boost fields re-roll their placement on a wrap, and a re-crossed wrap rolls afresh rather than dealing the same placement twice. Pickups therefore move on a stretch of circuit already driven this wrap. Accepted deliberately — the alternative is capturing every field's RNG state to make the deal reproducible, and a rewind blocked at a wrap boundary is a worse answer than a rewind that re-deals.
It is deliberately invisible once the Run ends. **Results** says nothing about it, the **ghost line** records nothing about it — the recording is truncated to the instant rewound to, so a promoted line never holds the drive into a wreck — and a Run that rewound may take the record like any other. There is no second class of Run here, and that is the point: a rewound Run is a Run with a worse earn rate than the one that did not need to rewind.
_Avoid_: Retry, continue, respawn, extra life, undo, checkpoint restore, save state.

### The open world

**Open world**:
The scene holding both circuits as real geometry, standing apart on open ground, that the kart drives freely between. Nothing run-shaped runs here: no run director, no checkpoints, no clock field, no pace, boost or hazard ghosts. The one thing that does move out here is the **income ghosts**, which run their circuits' recordings continuously and are only ever seen from the world. Gates stand dimmed, since with no pending checkpoint a lit gate would claim to be the pending one and there is no such thing out here. A circuit's bought clocks stand translucent and uncollectible — a window onto what has been paid for rather than time lying on the ground — and its unbought clocks are not shown at all, exactly as they are not shown on the circuit itself. A circuit with a bare loadout therefore stands empty out here, and that a circuit pays anything at all before it is invested in is the checkpoints' doing. `reset` here returns the kart to a world spawn; there is no Run to abort.
_Avoid_: Hub, lobby, menu (there is no menu — the world is driven, not navigated).

**Race scene**:
The one scene that drives a Run, exactly as the game always has, pointed at whichever circuit sent the kart here. Not one scene per circuit: a single scene instances the entered circuit's geometry as a child, at identity, so every circuit is driven, checkpointed and ghosted by the same run director, camera and HUD rather than by N forked copies of them.
_Avoid_: Level, stage, arena.

**Circuit entry**:
Pressing the enter action while standing on a circuit's own track in the open world, which fades out, records the kart's pose to return to, and loads the race scene pointed at that circuit. Eligibility — whether the kart is on *this* circuit's track right now — is inferred from what the kart's ground ray is resting on, not from any authored trigger volume: that node belongs to the circuit's own scene subtree if and only if the kart is driving its road. A HUD prompt is shown at the bottom of the screen exactly while eligible.
_Avoid_: Portal, teleport, loading zone, gate (the start/finish gate no longer has anything to do with triggering entry — see **Start/finish gate**).

### The track

**Circuit**:
The definition of one thing you can drive: its geometry, where its ghost line persists, where its loadout persists, what it is called, and where the open world stands it. A single resource type, one instance per circuit, read by both the open world and the race scene so the two cannot disagree about what a circuit is. Its world placement is a property the open world alone applies — the race scene always instances a circuit's geometry at identity, so a ghost line recorded in the circuit's own coordinates stays valid regardless of where the world stands it. It also carries the circuit's configured **Run** duration, and the per-circuit dials that only make sense against that duration — the intervals at which hazard and slipstream traffic thicken, the **wrap bonus**, the wrap limit, and the slipstream target the **resource bars** fill toward.
_Avoid_: Track, level, map.

**Circuit loadout**:
What the player has bought for one circuit: how many clocks are live on it, how many boost ghosts, how many hazard ghosts, how many income ghosts. Four raw counts rather than levels — a level is a second representation of a count, and a second representation is a thing that can disagree with the first — and every one of them starts at 0, so a circuit is bare until it is invested in. A bare circuit still pays, because its checkpoints do; what a bare circuit has none of is decisions.
Deliberately not part of the **Circuit**. A circuit's definition is authored content, identical on every machine and versioned with the game; a loadout is one player's purchases, and belongs beside their ghost lines rather than in the repo. It persists exactly as a ghost line does — one per circuit, found by a path the circuit itself carries — so a new circuit is still one authored resource, with no central registry to also remember to edit.
Bought into and never refunded, and buying clears nothing: the circuit's record earn rate and its ghost line both stand across a purchase. See **Record earn rate** for what that costs and why it is paid.
Three of the four counts are spent inside a Run and are meaningless outside one; the income ghost count is the exception, and is the only part of a loadout that does anything while the circuit is not being driven. It is also the only one that raises **income** directly — the clock count reaches income the long way round, by making a longer Run possible and a higher record with it.
_Avoid_: Circuit state ("state" is a word this glossary keeps out — see **Run phase**), upgrades (names the transaction, not the thing), config, settings, progression.

**Checkpoint**:
One position in the circuit's ordered checkpoint sequence. Checkpoints must be taken in order; taking one out of sequence does nothing, and taking the last one wraps the sequence back to the first rather than ending anything. Taking one **pays**, on the **checkpoint ladder**: the checkpoints are where all of a Run's money comes from, now that the coins are retired.
Mandatory, and that is a design fact rather than an implementation detail — a checkpoint cannot be skipped, so nothing about it can ever be a decision. Everything that is a decision has to be optional, which is what the **clock** is for.
_Avoid_: Waypoint, node, split (there are no sector times), lap (the sequence no longer belongs to a lap — see **Run**).

**Wrap**:
One complete pass of the checkpoint sequence inside a Run — from the taking of the first checkpoint to the taking of the last, at which point the sequence wraps back and another begins. A Run holds as many as its time budget allows, plus a partial one cut short by the Timeout.
**Not a unit of scoring.** Nothing is scored per wrap, there is no wrap record, nothing about a wrap is written to disk or compared across Runs, and the **checkpoint ladder** runs straight through one without resetting. A wrap is *timed*, though, and the figure is shown the instant it closes — see **Wrap readout**. That is feedback inside a Run and nothing more: a fast wrap is worth exactly what the checkpoints it took paid, and the only thing a Run is ranked on is still its **earn rate**. A circuit may pay a **wrap bonus** — a fixed number of seconds banked into the Run budget every wrap, exactly as a **clock** banks seconds — but that is a time award, not a score: it does not touch the ladder or the earn rate's numerator, only the denominator's ceiling, and a circuit authored at 0 pays nothing, exactly as before this existed. It is a unit of *recording* and of *restoration*: the **ghost line** stores every checkpoint crossing, and the first *checkpoint count* of them mark the first wrap — which is how the hazard field finds one wrap's worth of line to place itself along. Where a Run's budget ran out before a single wrap closed there are not enough of them to mark one, and the hazard field takes the whole partial recording instead: traffic on the piece of line that exists beats no traffic at all, and a circuit long enough to outlast its own Run would otherwise never show a hazard. The **boost ghost** field restores and re-rolls on the same signal, but from the road's own centreline rather than this line. The **hazard ghost** field pointedly does not listen to it: hazards are per-Run, not per-wrap.
_Avoid_: Lap — a lap was the unit of play this project retired (`docs/adr/0001-timed-circuit-runs.md`), and a wrap is deliberately not a revival of it: a lap ended something, a wrap ends nothing.

**Gate**:
The visible geometry over the track marking where a checkpoint is. Deliberately a separate word from checkpoint: the gate is what the player sees, the checkpoint is the rule, and the two need not be the same size or shape.
_Avoid_: Arch, marker, banner.

**Checkpoint prism**:
The bounded region that defines where a checkpoint counts — as wide as the gate itself (±4.5 m: the road's ±4 m plus the gate's overhang), from 1 m below the road surface to 5 m above, carried in the frame of the checkpoint's own marker. It has no thickness: it is crossed, not entered. The prism rolls with the road: a marker's frame is taken from the road's own definition — the same interpolation the road surface is built from — so its up *is* the road's up where it stands, the prism lies flat on banked and cresting road exactly as it does on a straight, and a gate may be placed anywhere on the circuit.
_Avoid_: Trigger, volume, collider — there is no `Area3D` and no physics body involved, and it is not a **hitbox** either: a checkpoint is a rule about a plane, not a shape a car has.

**Taken**:
What a checkpoint becomes when the kart's path crosses its prism while that checkpoint is the pending one. Direction does not matter, and taking is permanent until the sequence wraps back to the first checkpoint, at which point every checkpoint is untaken again and the pending checkpoint is once more the first. Taking one also advances the **checkpoint ladder**, which — unlike the pending checkpoint — does *not* reset on a wrap.
_Avoid_: Hit, triggered, passed (a checkpoint can be passed without being taken — that is the whole point of the ordering rule).
A **clock** is taken too, and so is a **boost ghost**, by the same swept path. The shared verb is deliberate and is a true statement about the design, not a coincidence: all three are things the kart's path collects rather than touches, and all three are tested against the segment travelled rather than a sampled position. A checkpoint comes back on the next wrap; a clock, a boost ghost and a **hazard ghost** do not come back until the next Run.

**Hitbox**:
The shape a car is, for every purpose other than being looked at: a capsule lying flat in the horizontal plane, as long as the car and as wide, with height ignored entirely. One shape covers everything — the kart against the barriers, the kart against a **clock**, a **boost ghost**, a **hazard ghost** or a **slipstream ghost**, and each of those cars against the kart — because they are all the same model under a scale, and a hitbox is that model's own measured footprint under that same scale. Nothing is tuned to be a shape the car is not; a field that wants to be forgiving or harsh scales its cars' hitboxes as a whole and says so.
Deliberately not a sphere, which is what all of this was before. A car is more than twice as long as it is wide, so a circle around one is simultaneously too generous across the road and too mean along it — and the wrong one in both directions changes with which way the car happens to be pointing.
The kart's hitbox **swings with the drift cant**, about the same front-axle pivot the chassis is drawn rotating about. What you can see is what you can be hit on: with the tail hung out, the box is out with it. Bank is excluded — a rolled hitbox is a hitbox that changes width mid-corner.
Tested **swept**, never sampled: the region a hitbox covers between one physics frame and the next is what a pickup or a hazard is measured against, so nothing is driven through at speed. Height is each field's own separate check (a metres-of-vertical-gap tolerance), for the same reason the **checkpoint prism** rolls with the road: a pickup up a banked sweeper belongs to the road it is on.
_Avoid_: Sphere, radius, collider, bounding box.

**Pending checkpoint**:
The single checkpoint that is currently live. Every other checkpoint is inert: crossing one does nothing at all. Advances by one each time it is taken, wrapping from the last checkpoint back to the first rather than stopping, and never moves backwards otherwise.
_Avoid_: Current checkpoint (ambiguous with the last one taken), next gate.

**Start line**:
The pose on the circuit the kart is returned to at the beginning of every Run. It is a property of the circuit, not of the kart. It sits a short way *past* the start/finish gate in the direction of travel, so a Run opens already clear of the gate that will later wrap it, and the last stretch of each pass is the drive from that gate up to the line. Which side of the line the gate sits on is a free choice rather than a constraint: the start/finish is the last checkpoint in the sequence and inert until all the others have been taken, so a gate ahead of the line is crossed harmlessly on the way out. This is the arrangement the circuit is authored with, not a rule the run system enforces.
Entry no longer has anything to do with this marker's position — see **Circuit entry** — but the marker still stands for the circuit as a whole in the open world: it is what an entry trigger is wired to in order to find the circuit's scene root.
_Avoid_: Spawn, start position, grid (there is no grid).

**Start/finish gate**:
The gate for the last checkpoint in the sequence — the one whose taking wraps the sequence back to the first checkpoint rather than ending anything. Only a Timeout or an Abort ends a Run. Visually distinct from the intermediate gates. It stands just short of the start line, which is what the kart is closest to at the moment a Run begins.

### Driving

The kart is held at both ends: the left stick says where the **front** is pointed, the right
stick says where the **rear** is going, and rotation is what happens when the two disagree. The
four angles below are distinct and must not be collapsed into one another, in code or in
conversation.

**Steer angle**:
The direction the front axle travels, relative to the kart's heading. Set by the left stick, eased
by front grip. Positive = left.
_Avoid_: Turn rate (that's a body property, and the kart deliberately does not have one), wheel angle.

**Rear slip angle**:
The direction the rear axle travels, relative to heading. Commanded by the right stick as a
fraction of the slip ceiling, eased by rear grip. The honest "how far the rear is out" signal, and
what every drift and cosmetic predicate reads.
_Avoid_: Drift angle, slip angle unqualified.

**Body slip angle**:
The direction the body *origin* actually travels, relative to heading — a wheelbase-weighted blend
of the two axle angles. A derived output, never an input. Not the same number as the rear slip
angle, and the two diverge most exactly when the driving is most interesting: a rear held out
against opposite steer spins the kart with very little body-level divergence.
_Avoid_: Slip angle unqualified, drift angle.

**Yaw rate**:
How fast the heading rotates. Solved from the disagreement between the two axle angles, and never
assigned anywhere.

**Front grip / rear grip**:
Degrees-per-second easing rates, not forces. "Grip" means exactly one thing in this game: how fast
an end obeys its stick. High grip answers instantly; low grip lags, and that lag is the car's
weight. There is no tyre model and no friction coefficient anywhere.
_Avoid_: Traction, friction, tyre load.

**Slip ceiling**:
The speed-dependent cap on the rear slip angle — a long way round at low speed, barely any swing
flat out. The entire safety model: the kart cannot spin out, so there is no loss-of-control state,
no recovery state and no spin case anywhere downstream. Overcooking a corner is paid for in speed
and line.
_Avoid_: Max drift angle, spin threshold.

**Disagreement**:
The difference between the steer angle and the rear slip angle. The quantity that produces
rotation, and the thing the player is actually manipulating.

### Money

**Checkpoint ladder**:
The payout schedule the checkpoints pay on: the *n*th checkpoint taken in a Run pays *n* times the circuit's base checkpoint value, counted from the Run's first checkpoint and running straight through every **wrap** without resetting. A Run of 45 checkpoints therefore earns 1035 base values, and its last checkpoint alone pays 45. Reset only at Countdown, alongside run earnings.
It exists because a fixed Run duration had made the earn rate decorative: before clocks, a Timeout always landed with the clock at the circuit's configured duration, so under a flat payout the denominator was a constant and the record ranked Runs identically to raw earnings — and worse, a flat payout makes the earn rate a linear function of average speed, and the game lap time with a dollar sign. The ladder makes both things a Run can vary matter. With *N* checkpoints taken over *T* seconds the rate is `base·N(N+1)/(2T)`, strictly increasing in *N* at a fixed *T* and strictly increasing in *T* at a fixed checkpoint interval: **a longer Run and a better-driven Run each necessarily earn more per second.**
Linear and not geometric on purpose. Under geometric growth the rate goes exponential in Run length — doubling a Run's duration raises its rate to a power rather than multiplying it — which makes Runs of different lengths incomparable and turns the record into a count of how many clocks were grabbed, with driving as a rounding error.
The base value is one number for the whole circuit, and deliberately **not** carried per-checkpoint the way a coin's value once was. A checkpoint cannot be skipped, so its value can never be a decision; a hairpin's checkpoint paying double would be a payout schedule dressed up as a mechanic. Value that varies is reserved for things that are optional, which today means the **clock**.
_Avoid_: Multiplier, combo, streak (nothing breaks it and nothing has to be maintained), bonus, chain.

**Clock**:
A single pickup standing above the road, taken by driving through it, worth a fixed number of **seconds** added to the Run's time budget. Carried per-clock, so a hard-to-reach one can be made to pay more without redesigning anything. A clock has no effect on the kart whatsoever — no speed, no grip — and no effect on the purse: it pays in time and never in money.
The mirror of the retired **coin**, and worth stating that way. A coin sat off the racing line and added to the numerator of the earn rate; a clock sits off the racing line and adds to the denominator. It is the only thing left in the game that is not on the racing line, and therefore the only decision a Run contains: is this detour worth the seconds it buys? That it is *optional* is the whole of why it can be a decision where a checkpoint cannot.
_Avoid_: Timer, time bonus, extend, pickup, item, collectible.

**Clock field**:
Every *live* clock on the circuit, considered as one thing. A purely spatial concern — where the clocks are and which are currently taken — and the whole of it is restored at the start of every countdown and at every **wrap** alike, the same moments the **boost ghost** and **hazard ghost** fields restore on: a clock taken on one lap is offered again on the next, so a long Run is not one live lap followed by an empty circuit.
Which clocks are live is the **circuit loadout**'s to say: the circuit authors a full field, the loadout buys the first *k* of it, and the rest are not merely hidden but absent from the swept test entirely — an unbought clock cannot be taken by driving through where it would have stood. Authored order is therefore a purchase order, and hand-reordering a circuit's clocks is how it decides which of them are worth buying first.
The subset is fixed for as long as the loadout is, and pointedly *not* re-rolled at every countdown the way the boost ghosts are. Two Runs drawn different clocks would not be two Runs of the same circuit.
_Avoid_: Clock manager, timer field, spawner, pickups.

**Purse**:
The money the player is holding. It rises when a checkpoint is taken — never when a clock is taken, which pays in seconds — it rises on its own while the income ghosts run, and it falls when something is bought for a circuit. It survives Run completion, it survives an abort, it survives the swap between the open world and a race scene, and it now survives the process itself: it is the one total in the game belonging to the player rather than to a Run or to a circuit.
Persisted, and the first thing in the game that has to be. Everything else worth keeping — a ghost line, a loadout — is only ever written at a moment the player caused, so losing the last few seconds of it loses nothing they would notice. The purse rises on its own, which means a purse that did not persist would quietly delete money earned while the player was doing nothing — precisely the money the income ghosts exist to produce.
Money, not a score. The pace ghost is promoted on the earn rate and never on this, and nothing is won by hoarding it — what it is *for* is the circuit loadouts it buys. It was a monotone lifetime total for exactly as long as nothing consumed it; the shop is that consumer.
_Avoid_: Bank, wallet, score, cash, balance, money (unqualified).

**Run earnings**:
The money taken during the current Run alone, reset at every countdown. The numerator of the earn rate. Distinct from the purse in every way except its unit, which is exactly why the two need different words.
_Avoid_: Coins (retired — see **Clock**), lap earnings, run score.

**Earn rate**:
Run earnings divided by the Run clock, in dollars per second. The game's single measure of merit: there is no other record, no best run and no second scoreboard. It is a cumulative average over the Run, not a windowed or instantaneous figure, so the number displayed while driving is the same quantity the completed Run will be judged on.
Under the **checkpoint ladder** it rises with Run length as well as with driving, and that is deliberate rather than a leak: it is the property the ladder exists to produce, and it is what makes a **clock** worth its detour. It is bounded only because a circuit's clocks are finite and are not restored on a wrap.
_Avoid_: Pace (that word is spoken for by the pace ghost), score, rate unqualified, $/sec (fine on screen, not as a term).

**Record earn rate**:
The highest earn rate any completed Run has achieved this session, and the bar a Run must strictly beat to promote its recording to the pace ghost. The record and the ghost are one concept with two faces — by construction the ghost always *is* the Run that set the record, so there is never a moment where the number on screen and the car beside you disagree. An aborted Run can never set one — nor does a Run need to complete anything to set one: only a Timeout can, at whatever earn rate the Run had reached the instant the clock ran out.
It is also, exactly, what each of the circuit's income ghosts pays per second. The two numbers are equal by construction rather than by coincidence — see **Income**.
A purchase does not clear it. Buying clocks raises the rate a Run can reach, so the record falls to a Run driven no better than the one that set it — and that is the point rather than a leak: the number going up is what the money bought. The cost is that the record stops measuring driving alone and comes to measure driving and investment together. Within a loadout it is exact; across a purchase it is a history rather than a ranking.
_Avoid_: Best lap, high score, personal best.

### Timing and the ghost

**Run clock**:
The time elapsed in the current Run, started at countdown-zero and running until the Run's budget is spent (a Timeout) or the player aborts. That budget is the circuit's configured duration plus the seconds of every **clock** taken so far, so it is not known at countdown and can rise mid-Run — the readout jumping *up* is a taken clock and nothing else. The thing you feel while driving — but not a record in its own right. On screen it is shown counted down rather than up, as the time left to earn in: what a driver acts on is how much Run is left, not how much has gone. For the last few seconds the readout leaves the top of the screen entirely and each remaining whole second is flashed, red and large, in the middle of the road — hundredths have nothing to say once what is left is a small integer, and a number that arrives reads as an alarm where one that never leaves reads as a display. A Run *is* now partly good for having lasted long — the **checkpoint ladder** sees to that, and it is what makes a **clock** worth its detour — but only the clocks it earned can make it last, so length is something a Run wins rather than something it is given.
It only ever moves forward. A **Rewind** takes the world back and leaves this where it stands, which is what makes a rewind cost anything at all: the seconds are gone, and the stretch of circuit they bought has to be bought again.
_Avoid_: Lap clock.

**Ghost line**:
The recorded position-and-heading line of the record Run, owned by the run director, together with the sample index of each checkpoint crossing inside it (the **checkpoint ladder**'s own record of where it paid, and the subsequence a wrap boundary falls at). The pace ghost and the hazard ghosts stand on it — the pace ghost moving along it at your own pace, the hazard ghosts driving along it backward — and the income ghosts replay the whole of it as a Run. The **boost ghosts** are the exception: they stand on the road's own centreline rather than this line — see **Boost ghost**. Promoted only on a strictly higher earn rate, and thrown away on abort. Not session-scoped: a promoted line is written to disk and reloaded next launch. Per *installation* rather than per session — it is a recording of this player's driving, not repo content, and a circuit never driven on this machine simply has no line, which plays exactly as before any Run has completed.
It is no longer one lap long, and every consumer has to be read in that light. A Run's recording runs for the whole time budget and ends mid-corner wherever the Timeout fell, so it is neither loop-closed nor of a predictable length: the checkpoint crossings are what let the hazard field find one wrap's worth of it to work with — falling back to the whole recording when they never marked a whole wrap — and the unclosed end is what an income ghost pops across. A saved line from before the crossings existed has none, and is treated as a circuit that has never been driven — it clears itself the first time someone sets a record.
_Avoid_: Racing line (that is the abstract ideal, not a recording), replay, path.

**Pace ghost**:
A translucent, non-colliding replay of the ghost line, replaying position and heading only. It starts moving when the player does and exists only in memory for the current session. It takes nothing and never will — not a checkpoint, not a clock, not a boost ghost: it is a line to follow, not a rival with a purse of its own. Nothing it drives through is consumed, and nothing it drives through is mimed either; a ghost that appeared to bank a checkpoint you had not reached would be a lie you would act on.
Because promotion demands a strictly higher earn rate, the ghost goes **stale on purpose**: set a strong Run and it may stand for fifty more. That is the intended feel. The ghost is a standard to be beaten, not a mirror of what you just did, and it stops moving the moment it becomes hard to beat.
It is not the only translucent car on the circuit — the **boost ghosts** are too, standing on the same ghost line — and the two are told apart in play by **both colour and motion**, neither primary: the pace ghost is blue and always *moving away from you at your own pace*, and a boost ghost is amber and *stationary*. This reverses an earlier position: when boost ghosts were scattered off the line, colour did no work and motion alone was the tell. Placing them *on* the ghost line is exactly the case that breaks stationary-vs-moving as a glance-level signal, which is why colour became load-bearing too.
_Avoid_: Ghost car, replay, rival, opponent.

### Roles

**Run director**:
The single owner of all mutable Run state — the run phase, checkpoint progress, the **checkpoint ladder**'s current rung, the Run clock, **Condition**, the slipstream ghosts caught this Run, Run earnings, the record earn rate, and the ghost line itself, both the in-progress recording and the promoted line. Everything else in the game either reports to it or reads from it. (The pace ghost reads the ghost line for pure playback and the clocks live on the clock field, which the director drives through run events; authority over a lifecycle is not a requirement that every consumer's data be fields on the director.)
It is also the only thing that knows where a **wrap** fell, and therefore the only thing that can write the wrap indices into a promoted ghost line.
Run earnings sit here rather than anywhere else because they are the numerator of the earn rate and the Run clock is the denominator — splitting a fraction across two owners is how the two come to disagree. Both ends of that fraction are now fed by pickups: the checkpoints raise the numerator and the clocks raise the denominator, and one owner holding both is what keeps them consistent. The purse sits elsewhere for the opposite reason: it is not run state at all.
_Avoid_: Lap director (retired name), lap manager, race manager, game manager.

**Clock field**:
The owner of the clocks themselves — their placement, their taken flags, and the swept test that decides a clock has been taken. It reports each pickup and knows nothing about who cares: not the Run clock it extends, not the earn rate that extension lands in. That ignorance is what keeps it small, and it is the retired coin field's shape exactly, moved from the numerator onto the denominator.
_Avoid_: Clock manager, timer field, pickup system, spawner.

**Purse holder**:
The owner of the purse, and deliberately not the run director: the purse outlives every Run and every abort, so housing it with run state would put a session-scoped total behind a per-run reset. Now that a Run can also be abandoned by leaving the circuit entirely — a race scene torn down and swapped for the open world — the purse outliving *that* too is the same requirement stated harder, and it is exactly what makes the purse holder an autoload: a scene-owned node dies with the scene, and an autoload is the one thing in Godot that survives the swap. It listens for pickups and adds them up, it takes money back out when something is bought, it takes what the income ghosts earn, and it writes itself to disk — and that is the whole of it.
It persists somewhere the player owns rather than beside the game's own files, which is a deliberate break from where ghost lines and loadouts are written today: those are only ever written by hand or from the editor and can afford to be, where a purse fed by a passive earner has to survive a real build or the earner is a lie. The inconsistency is the older two's to fix, not this one's to match.
What it deliberately does *not* own is the circuit loadouts that money is spent on. The obvious move when the second player-owned thing appeared was to let this role grow into a general holder of everything the player accumulates; the answer was a sibling autoload instead. The purse is one unkeyed integer, where the loadouts are a keyed collection — merging them buys nothing, and now that both persist the argument is unchanged rather than weakened: two things that save do not thereby become one thing.
_Avoid_: Economy, inventory, game state, save data.

**Loadout holder**:
The owner of every circuit's loadout, and the only thing that reads or writes them to disk. An autoload for the same reason the purse is one — the state outlives both the scene swap and the process — and separate from the purse for the reason given just above. Separate from CircuitSession too, which is scoped to a single entry-and-exit round trip and cleared by it, where a loadout is meant to outlive everything.
Nothing inside a race scene talks to it. The race scene reads the loadout once, in the same breath as the circuit's ghost line, and pushes the three race-side counts into the clock field and the two ghost fields — so those fields go on taking their counts from whoever owns them, rather than each one growing its own dependency on an autoload. The fourth count is read by the **income runner** instead, which sits inside no scene and so has no such breath to read it in.
_Avoid_: Shop, inventory, save manager, upgrade manager.

**Income runner**:
The owner of every circuit's income ghosts: where each one has got to along its recording, which rung of the **checkpoint ladder** it is on, and what it has earned. An autoload for the reason the purse is one, and then harder — income has to go on accruing while the player is inside a race scene where none of it is visible, so the thing that computes it cannot live in any scene at all.
It simulates every circuit whether or not anything is drawing it, and the open world renders a view of that — never the reverse. Earning and drawing are one simulation seen from two distances, so there is no second path that could pay a different rate when nobody is looking, and hiding a ghost stays purely a display decision: one too far away to draw goes on earning exactly as it did.
It walks a recorded line one sample at a time rather than jumping to where the clock says it should be, so a ghost is always where the driving put it. Income is therefore the same number on every machine, and cannot be raised by making the game run badly. It no longer sweeps anything: a recording's checkpoint crossings are fully determined by that recording, so they are found once at reseat and a ghost pays rung *n* on reaching crossing *n*.
Learns which circuits exist from the open world, which stands every one of them and has always been the place a circuit is added — so there is still no registry to remember to edit. Re-seats its ghosts, back to their even offsets with their ladders back at the first rung, whenever the line beneath them changes: a record set inside a race scene is paid at the new rate immediately rather than at the end of the session, which is the loop working.
_Avoid_: Income field (the *fields* are spatial owners inside a race scene, and this is not one of them), income manager, ledger, economy, idle manager.

**Income ghost view**:
The cars themselves, one set per circuit, standing inside that circuit's own geometry in the open world so a line recorded in the circuit's coordinates applies directly with no arithmetic. A pure view: it owns no money and no progress — not where a ghost has got to, not which rung of the ladder it is on — and asks the income runner where its ghosts are each frame. It is also what turns an income ghost's pickup into a **pickup popup**, converting the circuit's coordinates into the world's by the fact of standing in them.
Draws nothing past a distance, and this is the one thing here that scales: fifty ghosts is a trivial amount to simulate and fifty cars to draw, so the limit belongs on the drawing and nowhere else. Popups stop sooner than cars do — a car's silhouette reads much further out than a small green number.
_Avoid_: Income ghost field (see **Income runner**), income display, ghost spawner.

**Purse readout**:
The purse on screen: top-centre, green, in its own layer rather than a row in the racing block top-right, because the purse is the reward and not a racing stat. It flashes brighter for a moment on every pickup, and that flash is what ties taking a checkpoint to the number going up — the single most important piece of feedback in the money system. Income deliberately does not flash it. Six income ghosts running would strobe the readout permanently, and a flash that fires whether or not you did anything says nothing; the whole of what makes income passive is that it arrives while you are not looking. Written with thousands separated (`$1,234`), so a four-figure purse still reads at a glance out of the corner of the eye. It has no reset of any kind, matching the purse it reads.
_Avoid_: Score display, counter, money HUD.

**Wrap readout**:
What a **wrap** just cost, thrown into the middle of the screen the instant it closes: the wrap's time, the difference against the **pace ghost**'s own time on that same wrap, and the seconds the **wrap bonus** just banked. It holds for about a second and fades — it is read at racing speed, over the road, and lands the same way the **Results** headline does, so the two read as one gesture.
Timed closure to closure — the taking of the last checkpoint to the next taking of the last checkpoint — rather than from each wrap's first checkpoint, so the whole Run is accounted for and every figure covers the same stretch of circuit. The **start line** sits just past the start/finish gate, which is what makes the Run's opening stretch the same stretch as every later wrap's and the first figure comparable with the rest.
Measured against the ghost's same-numbered wrap rather than this Run's own previous wrap, deliberately: the ghost is the one fixed bar every other figure in the game is measured against, and a wrap-to-wrap comparison inside a single Run would reward a slow opening wrap with a cheap "faster" on the next rather than saying anything about the drive. Read out of the ghost line's own checkpoint crossings, not anything driven this Run.
It is the one number in the game where **down is good**, which is why it does not share the delta rule the Results screen's four rows do: there, up is more time, more money, more checkpoints, more rate. A wrap with no ghost data to compare against — no ghost line yet, or the record Run itself never reached that wrap number — shows no comparison at all, the same way a first wrap used to show none.
It sits above centre rather than dead centre, hard up under the **purse readout**, and it is two lines: the time with its comparison beside it, and the banked seconds underneath — the one figure of the three that is not a measurement of the wrap, which is what a line of its own says about it. At the size the time is drawn the block is taller than the gap between the purse readout and the **run clock**'s final-seconds digit, so it hangs clear of the purse — on screen every frame of every Run — and reaches down past centre into the digit's space, which is only occupied in the last five seconds of one. The collision left is rare, brief, and between two things that are never both being read. It carries no label naming it, either: it appears only at the instant a wrap closes, with the start/finish gate going past, and the signed delta and the banked seconds say what kind of number the big one is.
Purely cosmetic, exactly as the **pickup popup** is: nothing reads it back, and a readout that failed to appear would cost the feedback and nothing else.
_Avoid_: Lap time, split, sector — a wrap is not a lap (see **Wrap**), and there are no sectors.

**Pickup popup**:
The floating green label that stands where money was just taken — **`$12`**, or whatever rung of the **checkpoint ladder** paid it — a billboarded label a metre ahead of the pickup along whoever took it, rising and fading over 0.8 s. It is spawned at the pickup rather than at the taker, so a handful of them trace where the money was rather than where anyone happened to be. It is now the only place the ladder is legible while driving: the number climbing over the course of a Run is what tells the player they are driving for the tail.
Taken by the kart in a Run, and by an income ghost in the open world — one popup, two sources. Which way *ahead* points arrives *with* the report of the pickup rather than being looked up from the kart, because out in the world there is no kart involved at all; that is what lets one popup serve both without knowing which of them it is serving. Purely cosmetic and required to stay that way — nothing reads a popup back, and a popup that failed to appear would cost the player the feedback and nothing else. Green because the purse is green: the popup and the total it feeds are tied together by colour and by nothing else — which is exactly why a **clock**'s popup reads `+10s` and is *not* green. Green is money, and a clock is not money. Its colour is a light blue (`Color(0.4, 0.75, 1.0)`), matching the clock pickup's own mesh material — apart from the run clock's plain white and the final-seconds urgency red, both already spoken for elsewhere on screen.
_Avoid_: Toast, floater, damage number, notification, particle.

**Resource bars**:
The two vertical bars down the left edge of the screen, drawn only while **Racing**: the outer one a green fill counting the **slipstream ghost**s caught this Run against a target the circuit authors, the inner one a red bar of one discrete segment per point of **Condition** left. They carry no text and no numbers at all. Two shapes at the edge of vision are read without looking away from the road; a figure would have to be looked at to be read, which is the one thing a bar exists to avoid. What each one means is learned by watching it move while something happens to it, which is why the colours are the world's own — green is the traffic you just drove through, red is the oncoming ghost that just hit you — even though green already means money in text elsewhere on screen. A bar at the edge and a number in the middle are never mistaken for one another.
Condition sits **inboard** of slipstream, nearer the road: it is the bar with a consequence, so it gets the position peripheral vision is already pointed at, and the slipstream bar is the one that can afford to be glanced at. A lost segment flashes pale on its way out — the flash is what says *which* resource that hit just cost, since the speed already scrubbed out from under the driver has said everything else.
The slipstream bar is **pure information and pays nothing**: it fills toward the circuit's target, caps there, and reaching the top is not an event. Its target is per-circuit rather than a shared constant, because slipstream traffic thickens as a Run goes on and a longer Run therefore serves far more of it — one shared number would top the bar out in the opening third of a long Run and leave it dead scenery for the rest. The count behind it is uncapped and clamped only where it is drawn: a Run that caught twice the target genuinely caught them.
_Avoid_: Health bar, HP bar, meter, gauge, progress bar, XP bar.

### Boost

**Boost ghost**:
A translucent, stationary ghost of the car standing a short step off the road's own centreline facing the direction of travel, **taken** by driving through it — the same verb as a clock and the same swept test, and taken once is taken for the rest of the **Run**, exactly as a clock is. Placed automatically along the centreline — not authored into the circuit, and deliberately not the **ghost line** either: a racing line hugs the apex through a corner rather than sitting in the middle of the road, and a circuit with no recorded Run yet still has a road, so a boost ghost stands from the first countdown a driven line has never earned. Every ghost on a circuit is worth exactly the same, so the count is a known quantity you route around; what varies is where they sit, not what each is worth. The count is a single number for the whole circuit, and the **circuit loadout** is what says what it is. It starts at 0: boost ghosts are bought, not given.
A boost ghost pays in a **boost charge** rather than in money or in seconds, and that is the whole of the difference between it and a **clock**: both are taken by the path rather than touched, both are consumed, both are restored whole.
The field is restored — and **re-rolled** — at every countdown and never at a wrap, matching the **clock field**'s own lifecycle: a **wrap** is not the countdown, and a Run that keeps wrapping keeps the same, thinning field rather than an inexhaustible one. Each ghost is drawn inside its own slot of the centreline and jittered inside it at that one re-roll, which is what keeps a ghost a decision from Run to Run rather than a fixture, and what keeps the field from settling into the same shape for the fifty Runs a stale centreline can stand — the centreline itself never moves, since it is the road's, not the driver's.
_Avoid_: Boost pad, boost panel, ramp, speed strip, respawning (a boost ghost comes back at the next countdown, never within a Run).

**Boost charge**:
What taking a boost ghost banks, rather than boosting the kart on contact. Charges accrue — taking a second ghost while one is already banked makes two — and each is spent independently on a press of the boost button, applying one ordinary boost (a bump and a bleed) at the moment the driver chooses rather than the moment the ghost happened to stand. This is what turns a boost ghost from something you merely pass through into something you save for the straight, or the corner exit, or bank up before spending. Cleared at every countdown, matching the ghost field's own lifecycle.
_Avoid_: Boost meter (there is no continuous meter, only a count), turbo, stored boost.

**Bump**:
The m/s a spent charge puts straight into forward speed, above the tuned ceiling. One-shot: there is no envelope and no duration.
_Avoid_: Boost amount, impulse, thrust, power.

**Bleed**:
The m/s² the kart sheds overspeed at until it is back at its ceiling. Together with the bump this is the whole of a boost — how long one lasts is `bump / bleed` and is never authored directly, so no second number can disagree with the first and no timer can drift out of sync with the speed.
_Avoid_: Decay, falloff, boost duration (the thing this exists to not be).

**Overspeed**:
How far above its ceiling the kart currently is, in m/s. Not a stored "boost amount": it is read off the speed itself, so it cannot disagree with what the player sees. Zero is the normal condition.
_Avoid_: Boost remaining, boost meter, turbo.

Boost ghosts pay no money. They shorten the time between checkpoints and nothing else — which, under the **checkpoint ladder**, is exactly how they pay: more rungs reached in the same Run. That is the whole of their relationship to the economy.

### Hazard

**Hazard ghost**:
A translucent, red-tinted ghost of the car driving the ghost line **backward** — oncoming traffic on your own best line — **hit** on contact, the same swept test a clock or a boost ghost is taken by, and hit once is hit for the rest of the **Run**. Placed automatically along one wrap's worth of the ghost line — or along the whole recording, where no wrap ever closed inside it — one per equal slot of that stretch, exactly as boost ghosts are — the difference is that a hazard ghost stands *on* the line rather than a step to one side, since there is nowhere else for oncoming traffic to be, and it drives rather than stands still. Every hazard on a circuit costs the same, so the count is a known quantity. It comes from the **circuit loadout** exactly as the boost ghost count does, and starts at 0 for the same reason. A circuit may also tune an interval, in seconds of Racing time, at which one more hazard is spawned on top of that count — traffic that thickens as a Run goes on rather than staying fixed at the loadout's count — defaulting to disabled (0), unlike the base count itself not player-tunable.
**A wrap does nothing to the field at all**, and that is where it parts company with the **boost ghost**, which is both restored and re-rolled there. Neither half would be right here. Restoring it would respawn traffic the driver has already cleared, so a wrap you drove clean is handed back to you full — cleared is cleared for the rest of the Run, exactly as a clock or a boost ghost is. Re-placing it would cost more still: oncoming cars popping out of existence and a fresh field appearing in front of a driver already at speed — which a countdown can do unseen from a standing start and a wrap crossed at pace cannot — and the field's kart-clearance band re-cut around wherever the driver is every wrap, leaving a hole in the traffic there for the length of the Run. The hazards left standing simply keep driving across the boundary, which is what a wrap is: not an event, just the point the same stretch of line comes round again.
_Avoid_: Traffic, obstacle car, enemy, oncoming car.

**Hazard ribbon**:
The short, fading stretch of the **ghost line** each hazard ghost trails ahead of itself — the piece of line it is about to cover, running down the line toward you, since it drives the wrap backward. Drawn only while its hazard is near enough to matter, and gone the instant that hazard is **hit**. It is the warning, not decoration: what it says is *where the oncoming traffic is and which way it is coming*.
Deliberately not the whole wrap painted red. A Run drives the same wrap over and over, so a wrap-long ribbon is permanent scenery that says nothing about where any hazard actually is; a per-hazard one scales with the count you bought and disappears with the danger.
_Avoid_: Racing line, path preview, trail, warning line.

**Hazard hit**:
What driving through a hazard ghost costs: forward speed scrubbed by a tunable fraction, the same shape as a barrier impact but delivered by the hazard field's own swept test rather than a physics collision, **and one segment of Condition**. One-shot, with no duration — the same reasoning as bump/bleed's absence of an envelope, in miniature.
The two costs are not redundant. The speed scrub is the cue: it is felt through the controls, in the corner it happened in, and cannot be missed. The Condition segment is the consequence: it accumulates across a Run and eventually ends one. Hopping a hazard pays neither — clearing it cleanly is the whole reward for the trick.
_Avoid_: Damage, penalty, slow effect (unqualified).

Hazard ghosts pay no money. Like boost ghosts they are read from the ghost line rather than authored into the circuit, and they reach the economy only through the time they cost; unlike boost ghosts they never sit still, so the line you set is also the line you are then driven at.

### Slipstream

**Slipstream ghost**:
A translucent, green-tinted ghost of the car driving the road's own centreline **forward** — friendly traffic going the driver's own way — **caught** on contact, the same swept test a clock, boost ghost or hazard ghost is taken by, and caught once is caught for the rest of the **Run**. Placed automatically along the road's own centreline much as a hazard ghost is — the same per-lane wander, the same interval-driven thickening — but dealt into a window of road *ahead of the kart* rather than stratified over the whole lap, since friendly traffic is only worth anything where the driver will actually reach it, and driving forward rather than backward, and costing nothing to touch: there is no dodge, only the catch. Every slipstream ghost on a circuit is worth the same, so the count is a known quantity. It comes from the **circuit loadout** exactly as the boost and hazard ghost counts do, and starts at 0 for the same reason.
**A wrap does nothing to the field at all**, matching the **hazard ghost**'s own reason exactly: cleared is cleared for the rest of the Run, and the traffic left standing keeps driving straight through the wrap boundary.
_Avoid_: Draft ghost, convoy, ally car, friendly hazard.

**Slipstream catch**:
What driving through a slipstream ghost pays: a small permanent top-speed raise, applied straight to the kart, plus seconds added straight to the Run — its own tunable amount, independent of the top-speed raise. No boost charge — that reward is the **boost ghost**'s alone. One-shot, with no duration, the same shape as a **hazard hit**'s speed scrub in miniature, just paid rather than taken.
_Avoid_: Slipstream bonus, draft bonus, tailwind.

Slipstream ghosts pay no money. Like boost and hazard ghosts they are placed off the road's own centreline rather than authored into the circuit, and they reach the economy only through the top-speed raise and the seconds they pay.

### Income

**Income ghost**:
A translucent green replay of a circuit's ghost line that runs the record Run over and over, earning exactly what that Run earned. Alone among the ghosts it is not something you meet while driving: it exists precisely when you are *not* driving the circuit, and is hidden the moment you enter one. Its count comes from the **circuit loadout** exactly as the boost and hazard counts do, and starts at 0 for the same reason.
It runs **Runs, not wraps**. Where the other ghosts stand on the ghost line or drive it at you, an income ghost replays the whole recording end to end at the pace it was recorded at, paying the **checkpoint ladder** from its first rung to its last exactly as the record Run did, then Timeouts and begins again from the first rung. A ladder indexed on the ordinal within a Run has nothing to multiply for a thing that runs forever, and this is the only reading that resolves it: restarting the ladder at every wrap would pay the worst rungs for ever, and letting it grow across the pop would diverge.
N of them are spread evenly **through the Run** — the ith a fraction i/N through the recording — and pointedly not evenly around the track. Over a W-wrap recording that lands the ith near track fraction `(i·W/N) mod 1`, so when the ghost count and the record's wrap count share a factor the ghosts clump into a knot instead of ringing the circuit. Accepted deliberately: even spacing through the Run is what staggers their Timeouts, so the field never pops back to the line all at once, and the knot is a resonance between two numbers rather than a property of a circuit — it re-rolls whenever either changes. Buying one re-spaces all the others, which visibly jumps them; the jump lands on a purchase, which is already a moment of change.
It wraps by popping from wherever the recording's Timeout left it — mid-corner, anywhere on the circuit — back to the start line. Under laps this was a few metres and nearly invisible; under Runs it is an arbitrary jump, and it is honest rather than a seam to hide: a Run ends wherever the clock ran out and is followed by a Countdown at the line, which is exactly what the pop is. Not blended — the ghost line's whole claim is that it is a recording, and blending would invent motion nobody drove.
A circuit with no ghost line has nowhere to run one, so a bought income ghost earns nothing and is not drawn, exactly as there are no boost ghosts before any Run has completed.
Green, and green for a reason: the purse and the pickup popups are already green, and an income ghost is the only car in the game that *is* the money. It shares the pace ghost's silhouette and direction of travel, which would be a collision if the two were ever on screen together — and they never are, since one exists only in a Run and the other only outside one.
_Avoid_: Run ghost (ambiguous with the run director's own in-progress recording), idler, worker, farmer, AFK ghost.

**Income**:
What an income ghost earns, in dollars: **exactly the record earn rate, per ghost**. It replays the record recording as a Run and pays the **checkpoint ladder** at the crossings that recording actually made, so the money it produces is the money that Run produced, over the time that Run took. N ghosts pay N times it, and income is exactly linear in the count — ghosts do not compete and cannot take anything from each other or from you. Balancing that belongs in what a ghost costs, never in a rule that quietly makes the third ghost worth less than the first.
This replaces the old rule that income was **re-derived from the line against the coins live today** rather than replayed from what the record Run earned. That rule existed because a line's worth depended on money lying off it, which only a sweep against the coins actually standing there could price honestly. With the coins retired there is nothing spatial left to re-derive: the ladder is a function of the ordinal and of the recording, both fully determined the moment a line is promoted. The honesty now lives in the ghost paying the same rungs at the same places along the same path — the crossings are read off the recording once, not mimed on a timer.
The consequence is that **nothing you buy raises income except income ghosts**, where buying a coin used to raise it the instant it was bought. Clocks reach it only the long way round: buy clocks, drive a longer Run, set a higher record, and every income ghost is paid at the new rate from that moment. That loop is slower and it requires driving, which is the point rather than the cost.
**Income is not an earn rate.** They are now numerically equal, which makes the distinction matter more rather than less: the earn rate measures how well you drove and is the only thing that can set a record, where income is what that record pays while you are elsewhere, multiplied by a count you bought. Nothing an income ghost does can promote a ghost line or set a record.
_Avoid_: Passive income (fine in conversation, too long as a term), wage, yield, revenue, earnings (spoken for by **Run earnings**), idle money.

Income arrives silently. It never flashes the purse readout, because a flash that fires whether or not the player did anything stops meaning "you took a checkpoint" — see **Purse readout**. In the open world it is visible instead as the ghosts themselves and the popups they leave behind; inside a Run it has no visible sign at all beyond a total that climbs faster than the checkpoints alone explain.
