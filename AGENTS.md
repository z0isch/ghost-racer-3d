## Agent skills

### Issue tracker

Issues and specs live as markdown files under `.scratch/<feature-slug>/`. See `docs/agents/issue-tracker.md`.

### Domain docs

Single-context: `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.

### Code comments

Inline comments (`#`) should be used sparringly and only if the implemention is surprising in some way.
Inline comments should be terse and use precise technical language.

Documentation comments (`##` on a class, signal, property, or method) may carry more detail. They
describe what a thing is, what it owns, and the constraints a caller has to respect — including the
reasoning behind a non-obvious boundary. Keep them precise; prose that restates the code is still noise.

Comments should *never* be about the history of a change (we can look in the git history for that)