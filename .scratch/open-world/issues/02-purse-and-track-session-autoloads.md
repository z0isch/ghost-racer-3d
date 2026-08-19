# Purse and TrackSession autoloads

Status: closed

`project.godot` has no `[autoload]` section today. Add two.

**Purse** — move `scripts/purse.gd` to an autoload. Its `@export var coin_field_path: NodePath` goes
away: an autoload cannot hold a NodePath into a scene. Add a `PurseLink` node script that a scene
places to connect its `CoinField.coin_taken` to the autoload, so `CoinField` keeps knowing nothing
about who cares (CONTEXT.md, **Coin field**).

Rewrite the class comment. It currently reads "Not an autoload: an autoload earns its global by
surviving a scene change, and this game has one scene it never reloads." That premise is exactly
what this feature removes. The new comment should say the purse is an autoload because it must
outlive the scene swap, and keep the existing "not on LapDirector" reasoning intact.

**TrackSession** — new. Owns the pending track (what the race scene is about to load), the return
pose (where the world puts the kart back), and the entry cooldown. Deliberately separate from Purse
rather than one Session bag: CONTEXT.md's **Purse holder** entry exists to stop the purse becoming a
general state bag.

Done when: both autoloads are registered, the purse still tallies coins as it does today, and
`PurseHud` reads the autoload.
