# Ghostracer

A kart game of two circuits reached from an open world: drive onto a circuit's own track and press a button to drive it, looping its ordered checkpoints for a fixed time budget — a **Run** — collecting coins, against a ghost of your highest-earning Run on it. What you chase is not the fastest lap around but the best **earn rate** — dollars per second — so every coin sitting off the racing line is a real choice rather than free money. There is no race and no opponents, but a Run does end: it is a fixed, timed attempt, not an indefinite loop, and it stops the moment the clock runs out or the player aborts it. What you buy with the money is a better circuit to earn on, and eventually **income ghosts**: copies of your own best Run that go on running it, and paying, while you are somewhere else.

## Language

### The run

**Run**:
One fixed-duration attempt at a circuit, timed from countdown-zero to the moment the clock reaches the circuit's configured duration (a **Timeout**) or the player aborts it. Driven by looping the circuit's ordered checkpoints as many times as the time budget allows — the sequence wraps back to the first checkpoint every time the last one is taken, with no limit on how many times that happens inside a Run. The record-bearing unit: no single pass through the checkpoints is tracked or named on its own.
_Avoid_: Lap — this project used to organize play around laps, one ordered pass through the checkpoints that ended the moment the last one was taken; a Run replaces that shape entirely (see `docs/adr/0001-timed-circuit-runs.md`). Also avoid: race, circuit (the circuit is the track, not an attempt at it).

**Run phase**:
Which part of a Run is currently live — Countdown, Racing or Results (`RunDirector.RunPhase.COUNTDOWN` / `.RACING` / `.RESULTS`). Exactly one is active at any moment. Unlike the old lap cycle, this does not return to Countdown on its own: Results is a real stop, and a new Run begins only when the player explicitly starts one.
_Avoid_: Run state (too easily confused with the run's recorded data), mode, lap phase.

**Countdown**:
The phase before a Run, with the kart held motionless on the start line. Every Run is preceded by one — whether it follows a scene load, an abort, or the player explicitly starting a new Run from Results.

**Racing**:
The phase during which a Run is being driven and the clock is running. Ends only by Timeout or by Abort — never by completing the checkpoint sequence, which just wraps and keeps going.
_Avoid_: Running (reserved for the clock), driving, active.

**Results**:
The phase after a Run ends by Timeout, holding the Run's earnings on screen until the player explicitly starts a new Run. A real, indefinite stop — not a held instant before an automatic return, the way the old Finished phase was.
_Avoid_: Finished (the old, instant-then-loop phase this replaces), Game Over.

**Timeout**:
The Run clock reaching the circuit's configured duration. Ends the Run immediately, wherever the kart happens to be between checkpoints, and keeps everything earned up to that instant: the run earnings stand, the earn rate is computed from them, and the Run may set a new record. The only way a Run ends with a result.
_Avoid_: Time up, expiry, finish.

**Abort**:
Ending a Run before Timeout, triggered by the player's `reset` action. Unlike a Timeout, an abort discards the Run outright: no result is shown, the run earnings are thrown away, no record earn rate can be set, and the pace ghost recorded so far is discarded. The money already taken stays in the purse.
_Avoid_: Restart, cancel, retry, timeout (a Timeout keeps its result; an abort has none).

### The open world

**Open world**:
The scene holding both circuits as real geometry, standing apart on open ground, that the kart drives freely between. Nothing run-shaped runs here: no run director, no checkpoints, no coin field, no pace, boost or hazard ghosts. The one thing that does move out here is the **income ghosts**, which run their circuits' lines continuously and are only ever seen from the world. Gates stand dimmed, since with no pending checkpoint a lit gate would claim to be the pending one and there is no such thing out here. A circuit's bought coins stand translucent and uncollectible — a window onto what has been paid for rather than money on the ground — and its unbought coins are not shown at all, exactly as they are not shown on the circuit itself. A circuit with a bare loadout therefore stands empty out here, and that a circuit pays anything at all before it is invested in is the checkpoints' doing rather than the coins'. `reset` here returns the kart to a world spawn; there is no Run to abort.
_Avoid_: Hub, lobby, menu (there is no menu — the world is driven, not navigated).

**Race scene**:
The one scene that drives a Run, exactly as the game always has, pointed at whichever circuit sent the kart here. Not one scene per circuit: a single scene instances the entered circuit's geometry as a child, at identity, so every circuit is driven, checkpointed and ghosted by the same run director, camera and HUD rather than by N forked copies of them.
_Avoid_: Level, stage, arena.

**Circuit entry**:
Pressing the enter action while standing on a circuit's own track in the open world, which fades out, records the kart's pose to return to, and loads the race scene pointed at that circuit. Eligibility — whether the kart is on *this* circuit's track right now — is inferred from what the kart's ground ray is resting on, not from any authored trigger volume: that node belongs to the circuit's own scene subtree if and only if the kart is driving its road. A HUD prompt is shown at the bottom of the screen exactly while eligible.
_Avoid_: Portal, teleport, loading zone, gate (the start/finish gate no longer has anything to do with triggering entry — see **Start/finish gate**).

### The track

**Circuit**:
The definition of one thing you can drive: its geometry, where its ghost line persists, where its loadout persists, what it is called, and where the open world stands it. A single resource type, one instance per circuit, read by both the open world and the race scene so the two cannot disagree about what a circuit is. Its world placement is a property the open world alone applies — the race scene always instances a circuit's geometry at identity, so a ghost line recorded in the circuit's own coordinates stays valid regardless of where the world stands it. It also carries the circuit's configured **Run** duration.
_Avoid_: Track, level, map.

**Circuit loadout**:
What the player has bought for one circuit: how many coins are live on it, how many boost ghosts, how many hazard ghosts, how many income ghosts. Four raw counts rather than levels — a level is a second representation of a count, and a second representation is a thing that can disagree with the first — and every one of them starts at 0, so a circuit is bare until it is invested in.
Deliberately not part of the **Circuit**. A circuit's definition is authored content, identical on every machine and versioned with the game; a loadout is one player's purchases, and belongs beside their ghost lines rather than in the repo. It persists exactly as a ghost line does — one per circuit, found by a path the circuit itself carries — so a new circuit is still one authored resource, with no central registry to also remember to edit.
Bought into and never refunded, and buying clears nothing: the circuit's record earn rate and its ghost line both stand across a purchase. See **Record earn rate** for what that costs and why it is paid.
Three of the four counts are spent inside a Run and are meaningless outside one; the income ghost count is the exception, and is the only part of a loadout that does anything while the circuit is not being driven.
_Avoid_: Circuit state ("state" is a word this glossary keeps out — see **Run phase**), upgrades (names the transaction, not the thing), config, settings, progression.

**Checkpoint**:
One position in the circuit's ordered checkpoint sequence. Checkpoints must be taken in order; taking one out of sequence does nothing, and taking the last one wraps the sequence back to the first rather than ending anything.
_Avoid_: Waypoint, node, split (there are no sector times), lap (the sequence no longer belongs to a lap — see **Run**).

**Gate**:
The visible geometry over the track marking where a checkpoint is. Deliberately a separate word from checkpoint: the gate is what the player sees, the checkpoint is the rule, and the two need not be the same size or shape.
_Avoid_: Arch, marker, banner.

**Checkpoint prism**:
The bounded region that defines where a checkpoint counts — the road's full width and no more (±4 m), from 1 m below the road surface to 5 m above, carried in the frame of the checkpoint's own marker. It has no thickness: it is crossed, not entered. The prism rolls with the road: a marker's frame is taken from the road's own definition — the same interpolation the road surface is built from — so its up *is* the road's up where it stands, the prism lies flat on banked and cresting road exactly as it does on a straight, and a gate may be placed anywhere on the circuit.
_Avoid_: Trigger, volume, collider, hitbox — there is no `Area3D` and no physics body involved.

**Taken**:
What a checkpoint becomes when the kart's path crosses its prism while that checkpoint is the pending one. Direction does not matter, and taking is permanent until the sequence wraps back to the first checkpoint, at which point every checkpoint is untaken again and the pending checkpoint is once more the first.
_Avoid_: Hit, triggered, passed (a checkpoint can be passed without being taken — that is the whole point of the ordering rule).
A **coin** is taken too, by the same swept path. The shared verb is deliberate and is a true statement about the design, not a coincidence: both are things the kart's path collects rather than touches, both are tested against the segment travelled rather than a sampled position. Unlike checkpoints, though, a taken coin does *not* come back on a wrap — see **Coin field** for why only the first wrap of a Run earns anything.

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

**Coin**:
A single pickup standing above the road, taken by driving through it. Worth a fixed amount — its **value**, one dollar for every coin today, though value is carried per-coin so a hard-to-reach one can be made to pay more without redesigning anything. Coins have no effect on the kart whatsoever: no speed, no grip. The entire incentive to detour lives in the earn rate.
_Avoid_: Pickup, item, token, ring, collectible.

**Coin field**:
Every *live* coin on the circuit, considered as one thing. A purely spatial concern — where the coins are and which are currently taken — and the whole of it is restored at the start of every countdown, so each Run is offered an identical maximum. It is *not* restored on a wrap: once a coin is taken, it stays taken for the rest of the Run, so only a Run's first pass through the checkpoints has anything left to collect — later wraps in the same Run drive an already-emptied circuit. This was a deliberate choice: the time budget is meant to create pressure on its own, not to be a container for repeated earning.
Which coins are live is the **circuit loadout**'s to say: the circuit authors a full field, the loadout buys the first *k* of it, and the rest are not merely hidden but absent from the swept test entirely — an unbought coin cannot be taken by driving through where it would have stood. Authored order is therefore a purchase order, and hand-reordering a circuit's coins is how it decides which of them are worth buying first.
The subset is fixed for as long as the loadout is, and pointedly *not* re-rolled at every countdown the way the boost ghosts are. Re-rolling is safe for a field that moves only the denominator of the earn rate; the coins are its numerator, and two Runs drawn different coins would not be two Runs of the same circuit.
_Avoid_: Coin manager, spawner, pickups.

**Purse**:
The money the player is holding. It rises when a coin is taken — and, once checkpoints pay, when a checkpoint is taken — it rises on its own while the income ghosts run, and it falls when something is bought for a circuit. It survives Run completion, it survives an abort, it survives the swap between the open world and a race scene, and it now survives the process itself: it is the one total in the game belonging to the player rather than to a Run or to a circuit.
Persisted, and the first thing in the game that has to be. Everything else worth keeping — a ghost line, a loadout — is only ever written at a moment the player caused, so losing the last few seconds of it loses nothing they would notice. The purse rises on its own, which means a purse that did not persist would quietly delete money earned while the player was doing nothing — precisely the money the income ghosts exist to produce.
Money, not a score. The pace ghost is promoted on the earn rate and never on this, and nothing is won by hoarding it — what it is *for* is the circuit loadouts it buys. It was a monotone lifetime total for exactly as long as nothing consumed it; the shop is that consumer.
_Avoid_: Bank, wallet, score, cash, balance, money (unqualified).

**Run earnings**:
The money taken during the current Run alone, reset at every countdown. The numerator of the earn rate. Distinct from the purse in every way except its unit, which is exactly why the two need different words.
_Avoid_: Coins (unqualified), lap earnings, run score.

**Earn rate**:
Run earnings divided by the Run clock, in dollars per second. The game's single measure of merit: there is no other record, no best run and no second scoreboard. It is a cumulative average over the Run, not a windowed or instantaneous figure, so the number displayed while driving is the same quantity the completed Run will be judged on.
_Avoid_: Pace (that word is spoken for by the pace ghost), score, rate unqualified, $/sec (fine on screen, not as a term).

**Record earn rate**:
The highest earn rate any completed Run has achieved this session, and the bar a Run must strictly beat to promote its recording to the pace ghost. The record and the ghost are one concept with two faces — by construction the ghost always *is* the Run that set the record, so there is never a moment where the number on screen and the car beside you disagree. An aborted Run can never set one — nor does a Run need to complete anything to set one: only a Timeout can, at whatever earn rate the Run had reached the instant the clock ran out.
A purchase does not clear it. Buying coins raises the rate a Run can reach, so the record falls to a Run driven no better than the one that set it — and that is the point rather than a leak: the number going up is what the money bought. The cost is that the record stops measuring driving alone and comes to measure driving and investment together. Within a loadout it is exact; across a purchase it is a history rather than a ranking.
_Avoid_: Best lap, high score, personal best.

### Timing and the ghost

**Run clock**:
The time elapsed in the current Run, started at countdown-zero and running until the circuit's configured duration is reached (a Timeout) or the player aborts. The thing you feel while driving — but not a record in its own right. On screen it is shown counted down rather than up, as the time left to earn in: what a driver acts on is how much Run is left, not how much has gone. For the last few seconds the readout leaves the top of the screen entirely and each remaining whole second is flashed, red and large, in the middle of the road — hundredths have nothing to say once what is left is a small integer, and a number that arrives reads as an alarm where one that never leaves reads as a display. A Run is not good because it lasted long; it is good because it earned well for the time it had.
_Avoid_: Lap clock.

**Ghost line**:
The recorded position-and-heading line of the record Run, owned by the run director. The pace ghost, the boost ghosts and the hazard ghosts all stand on it — the pace ghost moving along it at your own pace, the boost ghosts parked a step to one side of it, the hazard ghosts driving along it backward. Promoted only on a strictly higher earn rate, and thrown away on abort. Not session-scoped: a promoted line is written to disk and reloaded next launch. Per *installation* rather than per session — it is a recording of this player's driving, not repo content, and a circuit never driven on this machine simply has no line, which plays exactly as before any Run has completed.
_Avoid_: Racing line (that is the abstract ideal, not a recording), replay, path.

**Pace ghost**:
A translucent, non-colliding replay of the ghost line, replaying position and heading only. It starts moving when the player does and exists only in memory for the current session. It cannot take coins and never will: it is a line to follow, not a rival with a purse of its own — a ghost that consumed coins would be taking them from you, and one that mimed a pickup on a coin still standing there would be a lie you would act on.
Because promotion demands a strictly higher earn rate, the ghost goes **stale on purpose**: set a strong Run and it may stand for fifty more. That is the intended feel. The ghost is a standard to be beaten, not a mirror of what you just did, and it stops moving the moment it becomes hard to beat.
It is not the only translucent car on the circuit — the **boost ghosts** are too, standing on the same ghost line — and the two are told apart in play by **both colour and motion**, neither primary: the pace ghost is blue and always *moving away from you at your own pace*, and a boost ghost is amber and *stationary*. This reverses an earlier position: when boost ghosts were scattered off the line, colour did no work and motion alone was the tell. Placing them *on* the ghost line is exactly the case that breaks stationary-vs-moving as a glance-level signal, which is why colour became load-bearing too.
_Avoid_: Ghost car, replay, rival, opponent.

### Roles

**Run director**:
The single owner of all mutable Run state — the run phase, checkpoint progress, the Run clock, Run earnings, the record earn rate, and the ghost line itself, both the in-progress recording and the promoted line. Everything else in the game either reports to it or reads from it. (The pace ghost reads the ghost line for pure playback and the coins live on the coin field, which the director drives through run events; authority over a lifecycle is not a requirement that every consumer's data be fields on the director.)
Run earnings sit here rather than on the coin field because they are the numerator of the earn rate and the Run clock is the denominator — splitting a fraction across two owners is how the two come to disagree. The purse sits elsewhere for the opposite reason: it is not run state at all.
_Avoid_: Lap director (retired name), lap manager, race manager, game manager.

**Coin field**:
The owner of the coins themselves — their placement, their taken flags, and the swept test that decides a coin has been taken. It reports each pickup and knows nothing about who cares: not the purse it feeds, not the run earnings it increments, not the rate either of them ends up in. That ignorance is what keeps it small.
_Avoid_: Coin manager, pickup system, spawner.

**Purse holder**:
The owner of the purse, and deliberately not the run director: the purse outlives every Run and every abort, so housing it with run state would put a session-scoped total behind a per-run reset. Now that a Run can also be abandoned by leaving the circuit entirely — a race scene torn down and swapped for the open world — the purse outliving *that* too is the same requirement stated harder, and it is exactly what makes the purse holder an autoload: a scene-owned node dies with the scene, and an autoload is the one thing in Godot that survives the swap. It listens for pickups and adds them up, it takes money back out when something is bought, it takes what the income ghosts earn, and it writes itself to disk — and that is the whole of it.
It persists somewhere the player owns rather than beside the game's own files, which is a deliberate break from where ghost lines and loadouts are written today: those are only ever written by hand or from the editor and can afford to be, where a purse fed by a passive earner has to survive a real build or the earner is a lie. The inconsistency is the older two's to fix, not this one's to match.
What it deliberately does *not* own is the circuit loadouts that money is spent on. The obvious move when the second player-owned thing appeared was to let this role grow into a general holder of everything the player accumulates; the answer was a sibling autoload instead. The purse is one unkeyed integer, where the loadouts are a keyed collection — merging them buys nothing, and now that both persist the argument is unchanged rather than weakened: two things that save do not thereby become one thing.
_Avoid_: Economy, inventory, game state, save data.

**Loadout holder**:
The owner of every circuit's loadout, and the only thing that reads or writes them to disk. An autoload for the same reason the purse is one — the state outlives both the scene swap and the process — and separate from the purse for the reason given just above. Separate from CircuitSession too, which is scoped to a single entry-and-exit round trip and cleared by it, where a loadout is meant to outlive everything.
Nothing inside a race scene talks to it. The race scene reads the loadout once, in the same breath as the circuit's ghost line, and pushes the three race-side counts into the coin field and the two ghost fields — so those fields go on taking their counts from whoever owns them, rather than each one growing its own dependency on an autoload. The fourth count is read by the **income runner** instead, which sits inside no scene and so has no such breath to read it in.
_Avoid_: Shop, inventory, save manager, upgrade manager.

**Income runner**:
The owner of every circuit's income ghosts: where each one has got to along its line, which coins it has taken, and what it has earned. An autoload for the reason the purse is one, and then harder — income has to go on accruing while the player is inside a race scene where none of it is visible, so the thing that computes it cannot live in any scene at all.
It simulates every circuit whether or not anything is drawing it, and the open world renders a view of that — never the reverse. Earning and drawing are one simulation seen from two distances, so there is no second path that could pay a different rate when nobody is looking, and hiding a ghost stays purely a display decision: one too far away to draw goes on earning exactly as it did.
It walks a recorded line one sample at a time rather than jumping to where the clock says it should be, so the path swept for coins is exactly the path that was driven. Income is therefore the same number on every machine, and cannot be raised by making the game run badly.
Learns which circuits exist from the open world, which stands every one of them and has always been the place a circuit is added — so there is still no registry to remember to edit. Re-seats its ghosts, back to their even offsets with their coins forgotten, whenever the line beneath them changes: a record set inside a race scene is paid at the new rate immediately rather than at the end of the session, which is the loop working.
_Avoid_: Income field (the three *fields* are spatial owners inside a race scene, and this is not a fourth of them), income manager, ledger, economy, idle manager.

**Income ghost view**:
The cars themselves, one set per circuit, standing inside that circuit's own geometry in the open world so a line recorded in the circuit's coordinates applies directly with no arithmetic. A pure view: it owns no money, no progress and no coins, and asks the income runner where its ghosts are each frame. It is also what turns an income ghost's pickup into a **pickup popup**, converting the circuit's coordinates into the world's by the fact of standing in them.
Draws nothing past a distance, and this is the one thing here that scales: fifty ghosts is a trivial amount to simulate and fifty cars to draw, so the limit belongs on the drawing and nowhere else. Popups stop sooner than cars do — a car's silhouette reads much further out than a small green number.
_Avoid_: Income ghost field (see **Income runner**), income display, ghost spawner.

**Purse readout**:
The purse on screen: top-centre, green, in its own layer rather than a row in the racing block top-right, because the purse is the reward and not a racing stat. It flashes brighter for a moment on every pickup, and that flash is what ties driving through a coin to the number going up — the single most important piece of feedback in the money system. Income deliberately does not flash it. Six income ghosts running would strobe the readout permanently, and a flash that fires whether or not you did anything says nothing; the whole of what makes income passive is that it arrives while you are not looking. Written with thousands separated (`$1,234`), so a four-figure purse still reads at a glance out of the corner of the eye. It has no reset of any kind, matching the purse it reads.
_Avoid_: Score display, counter, money HUD.

**Pickup popup**:
The floating green **`$1`** that stands where money was just taken: a billboarded label a metre ahead of the coin along whoever took it, rising and fading over 0.8 s. It is spawned at the coin rather than at the taker, so a handful of them trace where the money was rather than where anyone happened to be.
Taken by the kart in a Run, and by an income ghost in the open world — one popup, two sources. Which way *ahead* points arrives *with* the report of the pickup rather than being looked up from the kart, because out in the world there is no kart involved at all; that is what lets one popup serve both without knowing which of them it is serving. Purely cosmetic and required to stay that way — nothing reads a popup back, and a popup that failed to appear would cost the player the feedback and nothing else. Green because the purse is green: the popup and the total it feeds are tied together by colour and by nothing else.
_Avoid_: Toast, floater, damage number, notification, particle.

### Boost

**Boost ghost**:
A translucent, stationary ghost of the car standing a short step off the ghost line facing the direction of travel, **taken** by driving through it — the same verb as a coin and the same swept test, and taken once is taken for the rest of the Run (it does not come back on a wrap, exactly as a coin does not — see **Coin field**). Placed automatically along the ghost line — not authored into the circuit. Because the line is the record Run's own, improving your line moves the boost with you: the boost is only there if you repeat what earned it. Every ghost on a circuit is worth exactly the same, so the count is a known quantity you route around; what varies is where they sit, not what each is worth. The count is a single number for the whole circuit, and the **circuit loadout** is what says what it is. It starts at 0: boost ghosts are bought, not given.
A boost ghost is a coin that pays in a **boost charge** instead of money. That is the whole of the difference and it is worth stating positively: both are taken by the path rather than touched, both are consumed for the Run, both are restored whole at every countdown. Anything true of the coin field's lifecycle is true here.
Where the coins differ: the boost ghosts are **re-rolled** at every countdown rather than restored to where they stood, so two Runs of a circuit are not the same track. Each ghost is drawn inside its own slot of the ghost line and pushed to one side of it or the other, which is what keeps a ghost a decision — drive the line exactly and it will not be handed to you — and what keeps the field from settling into the same shape for the fifty Runs a stale ghost line can stand.
No boost ghosts before any Run has completed, for the same reason there is no pace ghost: there is no line yet.
_Avoid_: Boost pad, boost panel, ramp, speed strip, respawning (boost ghosts do not come back within a Run).

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
A translucent, red-tinted ghost of the car driving the ghost line **backward** — oncoming traffic on your own best line — **hit** on contact, the same swept test a coin or a boost ghost is taken by, and hit once is hit for the rest of the Run (it does not come back on a wrap — see **Coin field**). Placed automatically along the ghost line at countdown, one per equal slot of it, exactly as boost ghosts are — the difference is that a hazard ghost stands *on* the line rather than a step to one side, since there is nowhere else for oncoming traffic to be, and it drives rather than stands still. Every hazard on a circuit costs the same, so the count is a known quantity. It comes from the **circuit loadout** exactly as the boost ghost count does, and starts at 0 for the same reason.
_Avoid_: Traffic, obstacle car, enemy, oncoming car.

**Hazard hit**:
What driving through a hazard ghost costs: forward speed scrubbed by a tunable fraction, the same shape as a barrier impact but delivered by the hazard field's own swept test rather than a physics collision. One-shot, with no duration — the same reasoning as bump/bleed's absence of an envelope, in miniature.
_Avoid_: Damage, penalty, slow effect (unqualified).

Hazard ghosts have no effect on money and no effect on the coin field. Like boost ghosts, they are read from the ghost line, not authored into the circuit; unlike boost ghosts, they never sit still, so the line you set is also the line you are then driven at.

### Income

**Income ghost**:
A translucent green replay of a circuit's ghost line that runs it forever, earning what that line would earn if you drove it today. Alone among the ghosts it is not something you meet while driving: it exists precisely when you are *not* driving the circuit, and is hidden the moment you enter one. Its count comes from the **circuit loadout** exactly as the boost and hazard counts do, and starts at 0 for the same reason.
Where the other ghosts stand on the ghost line or drive it at you, an income ghost simply *runs* it, at the pace it was recorded at, starting again the instant it finishes. N of them are spread evenly around the line — the ith a fraction i/N of the way through it — so they never bunch up, and buying one re-spaces all the others, which visibly jumps them. The jump is accepted: it lands on a purchase, which is already a moment of change.
It wraps by popping back from the end of the recording to the start line each time it finishes, the same few metres a Countdown itself covers. Not blended — the ghost line's whole claim is that it is a recording, and blending would invent motion nobody drove.
A circuit with no ghost line has nowhere to run one, so a bought income ghost earns nothing and is not drawn, exactly as there are no boost ghosts before any Run has completed.
Green, and green for a reason: the purse and the pickup popups are already green, and an income ghost is the only car in the game that *is* the money. It shares the pace ghost's silhouette and direction of travel, which would be a collision if the two were ever on screen together — and they never are, since one exists only in a Run and the other only outside one.
_Avoid_: Run ghost (ambiguous with the run director's own in-progress recording), idler, worker, farmer, AFK ghost.

**Income**:
What an income ghost earns, in dollars. Not replayed from what the record Run earned, but **re-derived from that line against the coins live today**: the recorded path is swept against the circuit's currently bought coin field, and each coin it crosses pays that coin's own value at the moment it is crossed. Buying a coin the line runs through therefore raises income the instant it is bought, with no need to drive the circuit again — and the money shown stands where the coins actually are rather than being mimed on a timer, which is the same honesty the pace ghost is held to.
Each ghost carries its own idea of which coins it has taken, cleared when its own recording finishes and starts over. Ghosts do not compete for coins, and cannot take one from each other or from you: N ghosts pay N times, and income is exactly linear in the count. Balancing that belongs in what a ghost costs, never in a rule that quietly makes the third ghost worth less than the first.
**Income is not an earn rate.** Both are dollars per second, and the two must never be compared or added: the earn rate measures how well you drove and is the only thing that can set a record, where income measures what you have bought. Nothing an income ghost does can promote a ghost line, set a record, or touch the coin field of a Run you are driving.
_Avoid_: Passive income (fine in conversation, too long as a term), wage, yield, revenue, earnings (spoken for by **Run earnings**), idle money.

Income arrives silently. It never flashes the purse readout, because a flash that fires whether or not the player did anything stops meaning "you took a coin" — see **Purse readout**. In the open world it is visible instead as the ghosts themselves and the popups they leave behind; inside a Run it has no visible sign at all beyond a total that climbs faster than the coins alone explain.
