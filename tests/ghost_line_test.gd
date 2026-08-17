class_name GhostLineTest
extends TestCase

## The persistence round trip GhostLine exists for: LapDirector saves one to disk on every record
## lap and loads it back on _ready, so a track only needs to be recorded once, by whoever commits
## the file. This suite doesn't touch LapDirector — it pins the one thing that can silently break
## that promise, ResourceSaver/ResourceLoader losing or reshaping the packed arrays in transit.
##
## Written under user:// rather than res://: the test runner has no guarantee the working tree is
## writable, and user:// always is.

const PATH: String = "user://ghost_line_test.tres"


func suite_name() -> String:
	return "GhostLineTest"


func test_round_trip_preserves_positions_yaws_and_earn_rate() -> void:
	var saved := GhostLine.new()
	saved.positions = PackedVector3Array([Vector3(1.0, 0.0, 2.0), Vector3(3.5, 0.0, -4.5)])
	saved.yaws = PackedFloat32Array([0.0, PI / 2.0])
	saved.earn_rate = 12.5

	var error: Error = ResourceSaver.save(saved, PATH)
	check(error == OK, "GhostLine saves without error")

	var loaded: GhostLine = load(PATH) as GhostLine
	check(loaded != null, "GhostLine loads back as a GhostLine")
	if loaded == null:
		return

	check(loaded.positions == saved.positions, "positions survive the round trip")
	check(loaded.yaws == saved.yaws, "yaws survive the round trip")
	check_near(loaded.earn_rate, saved.earn_rate, 1e-6, "earn rate survives the round trip")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func test_defaults_are_an_empty_unrecorded_line() -> void:
	var line := GhostLine.new()
	check(line.positions.is_empty(), "a fresh GhostLine has no positions")
	check(line.yaws.is_empty(), "a fresh GhostLine has no yaws")
	check(line.earn_rate < 0.0, "a fresh GhostLine's earn rate is the unrecorded sentinel")
