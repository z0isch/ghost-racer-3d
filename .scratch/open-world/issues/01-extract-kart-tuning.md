# Extract the kart tuning to a shared resource

Status: closed

The kart tuning is an inline `SubResource("Resource_npteq")` in `main.tscn` (lines 38-51). Once
there is a kart in the open world and a kart in the race scene, an inline copy forks the handling
model in two and the world kart silently drifts from the race kart.

Save it as `tuning/default.tres` and have `main.tscn`'s Kart reference the file. Nothing else
changes yet — this is a prerequisite landed on its own so the diff stays legible.

Done when: `main.tscn` carries no inline tuning SubResource, and the kart drives identically.
