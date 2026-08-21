class_name CheckpointLadderTest
extends TestCase

## RunDirector.ladder_value: the checkpoint ladder's arithmetic as a static seam, pinned exactly as
## CONTEXT.md's **Checkpoint ladder** and docs/adr/0002 state it — the ADR's central claim and the
## only thing in the change that is a formula rather than a wiring.
##
## N checkpoints taken over T seconds earns base·N(N+1)/2 in total, so the rate is
## base·N(N+1)/(2T) — strictly increasing in N at a fixed T, and strictly increasing in T at a fixed
## checkpoint interval (more checkpoints taken in the extra time).


func suite_name() -> String:
	return "CheckpointLadderTest"


func _total_earnings(checkpoint_count: int, base: int) -> int:
	var total: int = 0
	for rung in range(1, checkpoint_count + 1):
		total += RunDirector.ladder_value(rung, base)
	return total


func test_the_nth_checkpoint_pays_n_times_the_base_value() -> void:
	check(RunDirector.ladder_value(1, 5) == 5, "the first checkpoint pays exactly the base value")
	check(RunDirector.ladder_value(4, 5) == 20, "the fourth checkpoint pays four times the base value")


func test_a_run_of_45_checkpoints_earns_1035_base_values() -> void:
	# The ADR's own worked example, pinned literally: sum_{n=1}^{45} n == 1035.
	check(_total_earnings(45, 1) == 1035, "45 checkpoints at base 1 earn 1035")


func test_total_earnings_matches_the_closed_form() -> void:
	var ns: Array[int] = [1, 2, 3, 10, 45, 100]
	for n: int in ns:
		var base: int = 3
		# n * (n + 1) is always even, so the division is always exact.
		@warning_ignore("integer_division")
		var expected: int = base * n * (n + 1) / 2
		check(_total_earnings(n, base) == expected,
			"N(N+1)/2 · base matches the summed ladder for N=%d" % n)


func test_the_rate_strictly_increases_with_more_checkpoints_at_a_fixed_duration() -> void:
	var base: int = 1
	var duration: float = 60.0
	var previous_rate: float = -1.0
	var ns: Array[int] = [1, 5, 10, 20, 45]
	for n: int in ns:
		var rate: float = float(_total_earnings(n, base)) / duration
		check_greater(rate, previous_rate,
			"the rate at N=%d checkpoints strictly beats the rate at fewer, for the same duration" % n)
		previous_rate = rate


func test_the_rate_strictly_increases_with_a_longer_run_at_a_fixed_checkpoint_interval() -> void:
	# A fixed checkpoint interval means N grows in proportion to T: doubling the duration doubles
	# how many checkpoints a Run of the same driving quality can take.
	var base: int = 1
	var checkpoints_per_second: float = 0.5
	var previous_rate: float = -1.0
	var durations: Array[float] = [30.0, 60.0, 120.0, 240.0]
	for duration: float in durations:
		var n: int = int(duration * checkpoints_per_second)
		var rate: float = float(_total_earnings(n, base)) / duration
		check_greater(rate, previous_rate,
			"the rate at duration %.0fs strictly beats a shorter Run driven at the same checkpoint interval" % duration)
		previous_rate = rate
