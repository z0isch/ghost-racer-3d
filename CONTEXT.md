# Ghostracer

A single-circuit kart game: you drive repeated laps of one track, collecting coins, against a ghost of your highest-earning lap. What you chase is not the fastest lap but the best **earn rate** — dollars per second — so every coin sitting off the racing line is a real choice rather than free money. There is no race, no opponents and no end — the lap cycle repeats indefinitely.

## Language

### The lap

**Lap**:
One ordered pass through every checkpoint, timed from countdown-zero to the moment the final checkpoint is taken.
_Avoid_: Run, circuit (the circuit is the track, not a pass around it), race.

**Lap phase**:
Which part of the lap cycle is currently live — Countdown, Racing or Finished (`LapDirector.LapPhase.COUNTDOWN` / `.RACING` / `.FINISHED`). Exactly one is active at any moment, and the cycle always returns to Countdown.
_Avoid_: Lap state (too easily confused with the lap's recorded data), mode.

**Countdown**:
The phase before a lap, with the kart held motionless on the start line. Every lap is preceded by one, whether it follows a scene load, a completed lap or an abort.

**Racing**:
The phase during which the lap is being driven and the clock is running.
_Avoid_: Running (reserved for the clock), driving, active.

**Finished**:
The phase after the final checkpoint is taken, during which the completed lap time is held on screen before the kart returns to the start line. A real phase with duration, not an instant.

**Abort**:
Ending a lap without completing it, triggered by the player's `reset` action. The lap time and the lap's earnings are discarded, no record earn rate can be set, and the pace ghost recorded so far is thrown away. The money already taken stays in the purse.
_Avoid_: Restart, cancel, retry.

### The track

**Checkpoint**:
One position in the lap's ordered sequence. Checkpoints must be taken in order for the lap to complete; taking one out of sequence does nothing.
_Avoid_: Waypoint, node, split (there are no sector times).

**Gate**:
The visible geometry over the track marking where a checkpoint is. Deliberately a separate word from checkpoint: the gate is what the player sees, the checkpoint is the rule, and the two need not be the same size or shape.
_Avoid_: Arch, marker, banner.

**Checkpoint prism**:
The bounded region that defines where a checkpoint counts — the road's full width and no more (±4 m), from 1 m below the road surface to 5 m above, carried in the frame of the checkpoint's own marker. It has no thickness: it is crossed, not entered. The prism rolls with the road: a marker's frame is taken from the road's own definition — the same interpolation the road surface is built from — so its up *is* the road's up where it stands, the prism lies flat on banked and cresting road exactly as it does on a straight, and a gate may be placed anywhere on the circuit.
_Avoid_: Trigger, volume, collider, hitbox — there is no `Area3D` and no physics body involved.

**Taken**:
What a checkpoint becomes when the kart's path crosses its prism while that checkpoint is the pending one. Direction does not matter, and taking is permanent for the rest of the lap.
_Avoid_: Hit, triggered, passed (a checkpoint can be passed without being taken — that is the whole point of the ordering rule).
A **coin** is taken too, by the same swept path. The shared verb is deliberate and is a true statement about the design, not a coincidence: both are things the kart's path collects rather than touches, both are tested against the segment travelled rather than a sampled position, and both reset with the lap.

**Pending checkpoint**:
The single checkpoint that is currently live. Every other checkpoint is inert: crossing one does nothing at all. Advances by one each time it is taken, and never moves backwards within a lap.
_Avoid_: Current checkpoint (ambiguous with the last one taken), next gate.

**Start line**:
The pose on the track the kart is returned to at the beginning of every lap. It is a property of the track, not of the kart. It sits a short way *past* the start/finish gate in the direction of travel, so a lap opens already clear of the gate that will end it, and the last stretch of a lap is the run from that gate up to the line. Which side of the line the gate sits on is a free choice rather than a constraint: the start/finish is the last checkpoint in the sequence and inert until all the others have been taken, so a gate ahead of the line is crossed harmlessly on the way out. This is the arrangement the circuit is authored with, not a rule the lap system enforces.
_Avoid_: Spawn, start position, grid (there is no grid).

**Start/finish gate**:
The gate for the last checkpoint in the sequence — the one whose taking ends the lap. Visually distinct from the intermediate gates. It stands just short of the start line, which is the last thing the kart reaches before the countdown returns it there.

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

**Coin**:
A single pickup standing above the road, taken by driving through it. Worth a fixed amount — its **value**, one dollar for every coin today, though value is carried per-coin so a hard-to-reach one can be made to pay more without redesigning anything. Coins have no effect on the kart whatsoever: no speed, no grip. The entire incentive to detour lives in the earn rate.
_Avoid_: Pickup, item, token, ring, collectible.

**Coin field**:
Every coin on the circuit, considered as one thing. A purely spatial concern — where the coins are and which are currently taken — and the whole of it is restored at the start of every countdown, so each lap is offered an identical maximum. This is what makes two laps' earn rates comparable at all.
_Avoid_: Coin manager, spawner, pickups.

**Purse**:
The lifetime running total of money taken this session. It only ever goes up: it survives lap completion, it survives an abort, and nothing in the game subtracts from it. It is a reward, not a score — it is deliberately *not* what the pace ghost is promoted on, and nothing is ever won or lost by having more of it.
_Avoid_: Bank, wallet, score, cash, balance, money (unqualified).

**Lap earnings**:
The money taken during the current lap alone, reset at every countdown. The numerator of the earn rate. Distinct from the purse in every way except its unit, which is exactly why the two need different words.
_Avoid_: Coins (unqualified), lap coins, lap score.

**Earn rate**:
Lap earnings divided by the lap clock, in dollars per second. The game's single measure of merit: there is no other record, no best lap and no second scoreboard. It is a cumulative average over the lap, not a windowed or instantaneous figure, so the number displayed while driving is the same quantity the completed lap will be judged on.
_Avoid_: Pace (that word is spoken for by the pace ghost), score, rate unqualified, $/sec (fine on screen, not as a term).

**Record earn rate**:
The highest earn rate any completed lap has achieved this session, and the bar a lap must strictly beat to promote its recording to the pace ghost. The record and the ghost are one concept with two faces — by construction the ghost always *is* the lap that set the record, so there is never a moment where the number on screen and the car beside you disagree. An aborted lap can never set one.
_Avoid_: Best lap, high score, personal best.

### Timing and the ghost

**Lap clock**:
The time elapsed in the current lap, started at countdown-zero and stopped when the final checkpoint is taken. The thing you feel while driving, and on screen — but not a record in its own right. A lap is not good because it was quick; it is good because it earned well for its length.

**Ghost line**:
The recorded position-and-heading line of the record lap, owned by the lap director. The pace ghost, the boost ghosts and the hazard ghosts all stand on it — the pace ghost moving along it at your own pace, the boost ghosts parked a step to one side of it, the hazard ghosts driving along it backward. Session-scoped: promoted only on a strictly higher earn rate, thrown away on abort.
_Avoid_: Racing line (that is the abstract ideal, not a recording), replay, path.

**Pace ghost**:
A translucent, non-colliding replay of the ghost line, replaying position and heading only. It starts moving when the player does and exists only in memory for the current session. It cannot take coins and never will: it is a line to follow, not a rival with a purse of its own — a ghost that consumed coins would be taking them from you, and one that mimed a pickup on a coin still standing there would be a lie you would act on.
Because promotion demands a strictly higher earn rate, the ghost goes **stale on purpose**: set a strong lap and it may stand for fifty more. That is the intended feel. The ghost is a standard to be beaten, not a mirror of what you just did, and it stops moving the moment it becomes hard to beat.
It is not the only translucent car on the circuit — the **boost ghosts** are too, standing on the same ghost line — and the two are told apart in play by **both colour and motion**, neither primary: the pace ghost is blue and always *moving away from you at your own pace*, and a boost ghost is amber and *stationary*. This reverses an earlier position: when boost ghosts were scattered off the line, colour did no work and motion alone was the tell. Placing them *on* the ghost line is exactly the case that breaks stationary-vs-moving as a glance-level signal, which is why colour became load-bearing too.
_Avoid_: Ghost car, replay, rival, opponent.

### Roles

**Lap director**:
The single owner of all mutable lap state — the lap phase, checkpoint progress, the lap clock, lap earnings, the record earn rate, and the ghost line itself, both the in-progress recording and the promoted line. Everything else in the game either reports to it or reads from it. (The pace ghost reads the ghost line for pure playback and the coins live on the coin field, which the director drives through lap events; authority over a lifecycle is not a requirement that every consumer's data be fields on the director.)
Lap earnings sit here rather than on the coin field because they are the numerator of the earn rate and the lap clock is the denominator — splitting a fraction across two owners is how the two come to disagree. The purse sits elsewhere for the opposite reason: it is not lap state at all.
_Avoid_: Lap manager, race manager, game manager.

**Coin field**:
The owner of the coins themselves — their placement, their taken flags, and the swept test that decides a coin has been taken. It reports each pickup and knows nothing about who cares: not the purse it feeds, not the lap earnings it increments, not the rate either of them ends up in. That ignorance is what keeps it small.
_Avoid_: Coin manager, pickup system, spawner.

**Purse holder**:
The owner of the purse, and deliberately not the lap director: the purse outlives every lap and every abort, so housing it with lap state would put a session-scoped total behind a per-lap reset. It listens for pickups and adds them up, and that is the whole of it. (The name is provisional — as the game grows this role is the obvious place for anything else the player accumulates across laps, and it should be renamed when that happens rather than accreting.)
_Avoid_: Economy, inventory, game state, save data.

**Purse readout**:
The purse on screen: top-centre, green, in its own layer rather than a row in the racing block top-right, because the purse is the reward and not a racing stat. It flashes brighter for a moment on every pickup, and that flash is what ties driving through a coin to the number going up — the single most important piece of feedback in the money system. Written with thousands separated (`$1,234`), so a four-figure purse still reads at a glance out of the corner of the eye. It has no reset of any kind, matching the purse it reads.
_Avoid_: Score display, counter, money HUD.

**Pickup popup**:
The floating green **`$1`** you drive through when you take a coin: a billboarded label standing a metre ahead of the coin along your travel, rising and fading over 0.8 s. It is spawned at the coin rather than at the kart, so a handful of them trace where the money was rather than where you happened to be. Purely cosmetic and required to stay that way — nothing reads a popup back, and a popup that failed to appear would cost the player the feedback and nothing else. Green because the purse is green: the popup and the total it feeds are tied together by colour and by nothing else.
_Avoid_: Toast, floater, damage number, notification, particle.

### Boost

**Boost ghost**:
A translucent, stationary ghost of the car standing a short step off the ghost line facing the direction of travel, **taken** by driving through it — the same verb as a coin and the same swept test, and taken once is taken for the rest of the lap. Placed automatically along the ghost line — not authored into the circuit. Because the line is the record lap's own, improving your line moves the boost with you: the boost is only there if you repeat what earned it. Every ghost on a circuit is worth exactly the same, so the count is a known quantity you route around; what varies is where they sit, not what each is worth. The count is a single number for the whole circuit, expected to be driven by a later system.
A boost ghost is a coin that pays in a **boost charge** instead of money. That is the whole of the difference and it is worth stating positively: both are taken by the path rather than touched, both are consumed for the lap, both are restored whole at every countdown. Anything true of the coin field's lifecycle is true here.
Where the coins differ: the boost ghosts are **re-rolled** at every countdown rather than restored to where they stood, so two laps of a circuit are not the same track. Each ghost is drawn inside its own slot of the lap and pushed to one side of the line or the other, which is what keeps a ghost a decision — drive the line exactly and it will not be handed to you — and what keeps the field from settling into the same shape for the fifty laps a stale ghost line can stand.
No boost ghosts on lap 1, for the same reason there is no pace ghost: there is no line yet.
_Avoid_: Boost pad, boost panel, ramp, speed strip, respawning (boost ghosts do not come back within a lap).

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

Boost ghosts have no effect on money and no effect on the coin field. They change the denominator of the earn rate and nothing else. That is the whole of their relationship to the economy.

### Hazard

**Hazard ghost**:
A translucent, red-tinted ghost of the car driving the ghost line **backward** — oncoming traffic on your own best line — **hit** on contact, the same swept test a coin or a boost ghost is taken by, and hit once is hit for the rest of the lap. Placed automatically along the ghost line at countdown, one per equal slot of it, exactly as boost ghosts are — the difference is that a hazard ghost stands *on* the line rather than a step to one side, since there is nowhere else for oncoming traffic to be, and it drives rather than stands still. Every hazard on a circuit costs the same, so the count is a known quantity, tunable live by a dev input exactly as the boost ghost count is.
_Avoid_: Traffic, obstacle car, enemy, oncoming car.

**Hazard hit**:
What driving through a hazard ghost costs: forward speed scrubbed by a tunable fraction, the same shape as a barrier impact but delivered by the hazard field's own swept test rather than a physics collision. One-shot, with no duration — the same reasoning as bump/bleed's absence of an envelope, in miniature.
_Avoid_: Damage, penalty, slow effect (unqualified).

Hazard ghosts have no effect on money and no effect on the coin field. Like boost ghosts, they are read from the ghost line, not authored into the circuit; unlike boost ghosts, they never sit still, so the line you set is also the line you are then driven at.
