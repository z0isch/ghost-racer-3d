# The boost FOV punch

Type: task
Status: open
Blocked by: 02

Make a boost read as speed rather than as a number.

`ChaseCamera._update_fov` clamps its speed fraction to 1.0 at `max_speed`, so **the entire overspeed
range renders identically to cruising** — at 22 m/s the camera is doing exactly what it does at 12.
The dynamic FOV already in the file goes blind precisely when the speed is most worth selling. This
was about half of why the early boost attempts felt flat.

Transfers nearly verbatim from `prototype/ghost-car-boost-pads`: three exports and about fifteen
lines, minus the `PROTOTYPE` markers.

## Shape

```gdscript
@export var boost_fov_gain: float = 12.0      # degrees on top of max_speed_fov
@export var boost_fov_reference: float = 10.0 # the overspeed earning the full gain
@export var boost_fov_attack: float = 30.0    # smoothing on the way up only
```

Two properties that are the whole point:

1. **Driven by the overspeed, not the speed**, so the widen tracks the bleed — it opens on the bump
   and closes as the boost is spent, the same curve the driver feels through the wheels.
2. **Asymmetric smoothing.** The stiff attack on the way up, the existing soft `fov_smoothing` on
   the way down, so the widen snaps and the settle does not. At the soft rate the punch spreads over
   half a second, by which point the bleed has clawed some of it back and it reads as a vague swell
   rather than a hit. Gate the stiff rate on there actually being overspeed rather than on the
   target merely rising, so ordinary acceleration keeps the feel it has.

Set `boost_fov_reference` to the settled bump (10.0), not the prototype's 7.0.

## Done when

- A pad visibly punches the camera and the widen decays with the boost
- Driving with no boost is unchanged
