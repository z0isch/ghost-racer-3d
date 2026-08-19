# Update CONTEXT.md

Status: closed
Blocked by: 08

`CONTEXT.md` is what `docs/agents/domain.md` points every agent at before it explores. Leaving it
describing the old game is worse than having no doc at all.

Rewrite:

- The opening line, "A single-circuit kart game" — now two circuits reached from an open world.
- **Start line** — currently "the pose on the track the kart is returned to at the beginning of
  every lap". It is now also the circuit's entrance from the world, crossed in either direction.
  Both roles are the same marker, and that is worth saying explicitly rather than leaving a reader
  to discover the second one in code.
- **Purse holder** — currently justifies not being an autoload. It is one now, and the stated
  reasoning ("the purse outlives every lap and every abort") is exactly what forces it, so the entry
  gets stronger rather than weaker.

Add the new terms: **open world**, **race scene**, **track entry**, and whichever of
**track** / **circuit** issue 07 settled on for the resource.

Done when: no sentence in `CONTEXT.md` is false, and the new vocabulary is defined with the same
_Avoid_ discipline as the existing entries.
