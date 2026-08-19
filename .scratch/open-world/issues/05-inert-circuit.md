# InertCircuit: dim the gates in the world

Status: closed
Blocked by: 04

Gate dimming today is `LapDirector._update_gate_visibility` (scripts/lap_director.gd:325), which
duplicates each gate material to `inactive_gate_alpha` and swaps it per mesh. No lap director runs
in the world, so every intermediate gate would render at full brightness, reading as "every gate is
the pending one".

Add a small `InertCircuit` script the world puts on each circuit instance: dim every gate mesh under
`Checkpoints`, using the same duplicate-and-alpha approach so the shared materials are not mutated.

It hides nothing else. Coins stay visible and standing. They are uncollectible already with no
`CoinField` present, and they are how the player sees that a circuit pays.

Done when: every gate in the open world is dimmed, and entering the race scene still shows gate 1
lit as it does today.
