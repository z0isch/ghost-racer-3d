extends SceneTree

## Headless test entry point.
##
##   godot --headless --path . --script res://tests/run_tests.gd
##
## or, with the Godot path already worked out for you, tools/track/test.ps1 / test.sh.
##
## A SceneTree rather than a plain Object script because --script runs whatever MainLoop the
## script declares, and this way the engine is fully up (resources, class cache) before the first
## assertion runs. Nothing here touches the scene tree itself: the suites are all RefCounted.

func _initialize() -> void:
	var suites: Array[TestCase] = [
		KartModelTest.new(),
		KartInputTest.new(),
		ClockPickupTest.new(),
		BoostGhostPlacementTest.new(),
		HazardGhostPlacementTest.new(),
		GhostLineTest.new(),
		IncomeGhostSweepTest.new(),
		CheckpointLadderTest.new(),
	]

	var failures: PackedStringArray = PackedStringArray()
	var assertions: int = 0
	for suite: TestCase in suites:
		var suite_failures: PackedStringArray = suite.run()
		assertions += suite.assertion_count()
		for line: String in suite_failures:
			failures.append(line)
		var mark: String = "FAIL" if suite_failures.size() > 0 else "ok"
		print("  %-4s %s (%d assertions)" % [mark, suite.suite_name(), suite.assertion_count()])

	print("")
	if failures.size() > 0:
		for line: String in failures:
			printerr("  " + line)
		printerr("tests: %d assertion(s) failed of %d" % [failures.size(), assertions])
		quit(1)
		return

	print("tests: %d assertions passed" % assertions)
	quit(0)
