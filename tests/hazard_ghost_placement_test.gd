class_name HazardGhostPlacementTest
extends TestCase

## The arclength and lane rules the hazard field is built out of: HazardGhostField.place_along,
## which decides where hazards start along the centreline; lane_capacity and deal_offsets, which
## decide the lane each hazard drives across the road; and the pair of sample lookups the hazard
## ribbons are sliced with.
##
## Unlike BoostGhostPlacementTest the placement rule works purely in arclength — no line, no yaw —
## because a hazard's lane is a separate, independent draw (deal_offsets) from where it
## starts along that lane; the pose resolution and the backward-facing yaw live in _pose_at,
## exercised instead by the field's own runtime behaviour.
##
## The lookups are here because a hazard ribbon is a *slice* of a prebuilt vertex array
## (HazardGhostField._update_ribbons): the two ends of that slice are found by two different walks,
## one scanning up from zero and one back down from a known index, and a ribbon detaching from its
## own car is what it looks like when they disagree by one.

const START_MARGIN: float = 10.0
## Enough rolls that a bound broken in one draw out of a handful still shows up every run.
const ROLLS: int = 200
const LINE_LENGTH: float = 90.0


func suite_name() -> String:
	return "HazardGhostPlacementTest"


func _place(total_length: float, count: int,
		start_margin: float = START_MARGIN,
		jitter: float = 0.0,
		rng: RandomNumberGenerator = RandomNumberGenerator.new()) -> Array[float]:
	return HazardGhostField.place_along(total_length, count, start_margin, rng, jitter)


func test_count_zero_is_empty() -> void:
	check(_place(LINE_LENGTH, 0).is_empty(), "no hazards requested, none placed")


func test_zero_length_line_is_empty() -> void:
	check(_place(0.0, 3).is_empty(), "no line, no hazards")


func test_count_one_sits_dead_centre_of_the_usable_span() -> void:
	var distances: Array[float] = _place(LINE_LENGTH, 1)
	check(distances.size() == 1, "exactly one hazard placed")
	# Usable span is [10, 90], 80 m long; its centre is 50.
	check_near(distances[0], 50.0, 1e-4, "a single hazard centres the usable span")


func test_margin_past_the_line_length_is_empty() -> void:
	var distances: Array[float] = _place(5.0, 3) # shorter than the 10 m margin leaves usable
	check(distances.is_empty(), "a margin that consumes the whole line places nothing, not negative spacing")


func test_a_straight_line_of_known_length_places_exact_midpoint_distances() -> void:
	var distances: Array[float] = _place(LINE_LENGTH, 4)
	check(distances.size() == 4, "four hazards requested, four placed")
	# Usable span [10, 90], 80 m long, quarters of 20 m, midpoints at 10 + 10, 30, 50, 70.
	var expected: Array[float] = [20.0, 40.0, 60.0, 80.0]
	for i in expected.size():
		check_near(distances[i], expected[i], 1e-4,
			"hazard %d sits at its exact midpoint distance along the line" % i)


func test_full_jitter_never_leaves_a_hazard_s_own_slot() -> void:
	# Usable span [10, 90], four 20 m slots, so hazard i lives in [10 + 20i, 30 + 20i].
	var rng := RandomNumberGenerator.new()

	for roll in ROLLS:
		var distances: Array[float] = _place(LINE_LENGTH, 4, START_MARGIN, 1.0, rng)
		check(distances.size() == 4, "four hazards requested, four placed")
		for i in distances.size():
			var low: float = 10.0 + 20.0 * i
			check(distances[i] >= low - 1e-4 and distances[i] <= low + 20.0 + 1e-4,
				"hazard %d stays inside its own slot" % i)


func test_jitter_moves_the_field_between_rolls() -> void:
	# The ghost line only changes on a record lap, so without jitter two consecutive countdowns
	# rebuild the identical field.
	var rng := RandomNumberGenerator.new()

	var first: Array[float] = _place(LINE_LENGTH, 5, START_MARGIN, 0.8, rng)
	var second: Array[float] = _place(LINE_LENGTH, 5, START_MARGIN, 0.8, rng)

	var moved: bool = false
	for i in first.size():
		if absf(first[i] - second[i]) > 1e-4:
			moved = true
	check(moved, "a second roll of the same line is not the first one again")


func test_zero_jitter_reproduces_the_fixed_field() -> void:
	var rng := RandomNumberGenerator.new()
	var expected: Array[float] = [20.0, 40.0, 60.0, 80.0]
	for roll in ROLLS:
		var distances: Array[float] = _place(LINE_LENGTH, 4, START_MARGIN, 0.0, rng)
		for i in distances.size():
			check_near(distances[i], expected[i], 1e-4, "hazard %d is pinned to its midpoint" % i)


## Samples every metre, so cumulative[i] == i and the expected index of a distance is its floor.
func _metre_cumulative(samples: int) -> PackedFloat32Array:
	var cumulative := PackedFloat32Array()
	for i in samples:
		cumulative.append(float(i))
	return cumulative


func test_forward_lookup_lands_on_the_sample_the_distance_falls_on() -> void:
	var cumulative: PackedFloat32Array = _metre_cumulative(50)
	for metre in 47:
		var distance: float = float(metre) + 0.5
		check(HazardGhostField._sample_index_at(cumulative, distance) == metre,
			"%.1f m along a metre-per-sample line is sample %d" % [distance, metre])


func test_forward_lookup_caps_so_the_next_sample_always_exists() -> void:
	var cumulative: PackedFloat32Array = _metre_cumulative(50)
	# Past the end of the line, and exactly on its last sample: both must leave index + 1 addressable,
	# because every caller reads cumulative[index + 1].
	check(HazardGhostField._sample_index_at(cumulative, 1000.0) == 48, "past the end caps at size - 2")
	check(HazardGhostField._sample_index_at(cumulative, 49.0) == 48, "the last sample caps too")


func test_backward_lookup_agrees_with_the_forward_one() -> void:
	# The ribbon's two ends are found by different walks; they have to reach the same sample for the
	# same distance or a ribbon lands offset from the hazard trailing it.
	var cumulative: PackedFloat32Array = _metre_cumulative(200)
	for metre in range(0, 190):
		var distance: float = float(metre) + 0.5
		var high: int = HazardGhostField._sample_index_at(cumulative, 195.0)
		var back: int = HazardGhostField._sample_index_back_from(cumulative, high, distance)
		check(back == metre, "walking back to %.1f m reaches sample %d" % [distance, metre])


func test_backward_lookup_clamps_at_the_line_start() -> void:
	var cumulative: PackedFloat32Array = _metre_cumulative(50)
	var high: int = HazardGhostField._sample_index_at(cumulative, 20.0)
	# A hazard less than a lead length from the start of the wrap asks for a negative distance; the
	# slice has to stop at the seam rather than run off the front of the array.
	check(HazardGhostField._sample_index_back_from(cumulative, high, -40.0) == 0,
		"a lead reaching past the line start stops at sample 0")


func test_backward_lookup_never_passes_the_index_it_started_from() -> void:
	var cumulative: PackedFloat32Array = _metre_cumulative(50)
	# A zero-length lead: the slice collapses onto the hazard's own sample and _update_ribbons drops
	# it, rather than the walk running forward and inverting the slice.
	check(HazardGhostField._sample_index_back_from(cumulative, 30, 1000.0) == 30,
		"a distance already behind the starting index moves nothing")


## A loop length whose gradient budget sits strictly between "the slow harmonic alone, at its
## widest range (n=4), still fits" and "the slow harmonic plus even the loosest fast harmonic
## (n_slow=2, n_fast=9) fits" — so the cap-binding test reliably shrinks only the fast harmonic,
## regardless of which harmonics the rng draws.
const CAP_BINDING_LOOP_LENGTH: float = 1100.0
const HALF_BAND: float = 3.25
const MAX_GRADIENT: float = 0.06
const LOOP_LENGTH: float = 700.0


func test_wander_offset_is_seamless_across_the_loop() -> void:
	var rng := RandomNumberGenerator.new()
	for roll in ROLLS:
		var wander: HazardGhostField.Wander = HazardGhostField.draw_wander(
			HALF_BAND, LOOP_LENGTH, MAX_GRADIENT, rng.randf_range(0.0, TAU), rng)
		check_near(
			HazardGhostField.wander_offset_at(wander, 0.0, LOOP_LENGTH),
			HazardGhostField.wander_offset_at(wander, LOOP_LENGTH, LOOP_LENGTH),
			1e-3,
			"the wander's value at the seam matches its value at the loop's end")


func test_wander_offset_stays_within_the_half_band() -> void:
	var rng := RandomNumberGenerator.new()
	var wander: HazardGhostField.Wander = HazardGhostField.draw_wander(
		HALF_BAND, LOOP_LENGTH, MAX_GRADIENT, rng.randf_range(0.0, TAU), rng)
	var samples: int = 2000
	for i in samples:
		var s: float = LOOP_LENGTH * float(i) / float(samples)
		check(absf(HazardGhostField.wander_offset_at(wander, s, LOOP_LENGTH)) <= HALF_BAND + 1e-4,
			"the wander never asks for more than its own half_band at s=%.1f" % s)


func test_wander_gradient_stays_at_or_under_the_cap() -> void:
	var rng := RandomNumberGenerator.new()
	var wander: HazardGhostField.Wander = HazardGhostField.draw_wander(
		HALF_BAND, LOOP_LENGTH, MAX_GRADIENT, rng.randf_range(0.0, TAU), rng)
	# Sampled at 0.1 m, well under the fast harmonic's wavelength: a coarser stride can miss a
	# violation between samples and go quietly green.
	var step: float = 0.1
	var previous: float = HazardGhostField.wander_offset_at(wander, 0.0, LOOP_LENGTH)
	var s: float = step
	while s <= LOOP_LENGTH:
		var current: float = HazardGhostField.wander_offset_at(wander, s, LOOP_LENGTH)
		var gradient: float = absf(current - previous) / step
		check(gradient <= MAX_GRADIENT + 1e-3,
			"lateral movement per metre stays at or under max_lane_gradient at s=%.1f" % s)
		previous = current
		s += step


func test_wander_is_inert_at_zero_half_band() -> void:
	var rng := RandomNumberGenerator.new()
	var wander: HazardGhostField.Wander = HazardGhostField.draw_wander(
		0.0, LOOP_LENGTH, MAX_GRADIENT, rng.randf_range(0.0, TAU), rng)
	for roll in ROLLS:
		var s: float = rng.randf_range(0.0, LOOP_LENGTH)
		check(HazardGhostField.wander_offset_at(wander, s, LOOP_LENGTH) == 0.0,
			"a zero half_band reproduces the pre-change constant lane exactly")


func test_wander_cap_binds_the_fast_harmonic_only() -> void:
	var rng := RandomNumberGenerator.new()
	var wander: HazardGhostField.Wander = HazardGhostField.draw_wander(
		HALF_BAND, CAP_BINDING_LOOP_LENGTH, MAX_GRADIENT, rng.randf_range(0.0, TAU), rng)
	var expected_slow: float = HALF_BAND * 0.75
	check_near(wander.slow_amplitude, expected_slow, 1e-4,
		"the slow harmonic keeps its full share of the half_band when the cap binds")
	check(wander.fast_amplitude < HALF_BAND * 0.25 - 1e-4,
		"only the fast harmonic's amplitude shrinks to fit the gradient budget")


func test_wander_is_deterministic_per_seed() -> void:
	var first_rng := RandomNumberGenerator.new()
	first_rng.seed = 1
	var second_rng := RandomNumberGenerator.new()
	second_rng.seed = 1
	var third_rng := RandomNumberGenerator.new()
	third_rng.seed = 2

	var first: HazardGhostField.Wander = HazardGhostField.draw_wander(
		HALF_BAND, LOOP_LENGTH, MAX_GRADIENT, 1.0, first_rng)
	var second: HazardGhostField.Wander = HazardGhostField.draw_wander(
		HALF_BAND, LOOP_LENGTH, MAX_GRADIENT, 1.0, second_rng)
	var third: HazardGhostField.Wander = HazardGhostField.draw_wander(
		HALF_BAND, LOOP_LENGTH, MAX_GRADIENT, 1.0, third_rng)

	check(first.slow_harmonic == second.slow_harmonic
			and first.fast_harmonic == second.fast_harmonic
			and is_equal_approx(first.fast_phase, second.fast_phase),
		"the same rng seed draws the same wander")
	check(first.slow_harmonic != third.slow_harmonic
			or first.fast_harmonic != third.fast_harmonic
			or not is_equal_approx(first.fast_phase, third.fast_phase),
		"different rng seeds draw different wanders")


func test_wander_degenerate_inputs_give_zero_and_deal_phases_are_well_formed() -> void:
	var rng := RandomNumberGenerator.new()
	var zero_band: HazardGhostField.Wander = HazardGhostField.draw_wander(
		0.0, LOOP_LENGTH, MAX_GRADIENT, 0.0, rng)
	check(zero_band.slow_amplitude == 0.0 and zero_band.fast_amplitude == 0.0,
		"half_band <= 0.0 gives an all-zero wander")

	var zero_loop: HazardGhostField.Wander = HazardGhostField.draw_wander(
		HALF_BAND, 0.0, MAX_GRADIENT, 0.0, rng)
	check(zero_loop.slow_amplitude == 0.0 and zero_loop.fast_amplitude == 0.0,
		"loop_length <= 0.0 gives an all-zero wander")

	check(HazardGhostField.deal_phases(0, rng).is_empty(), "count <= 0 gives an empty array")

	var count: int = 5
	var band_width: float = TAU / count
	for roll in ROLLS:
		var phases: Array[float] = HazardGhostField.deal_phases(count, rng)
		var bands_seen: Dictionary = {}
		for phase in phases:
			check(phase >= 0.0 and phase < TAU, "every dealt phase is in [0, TAU)")
			var band: int = floori(phase / band_width)
			check(not bands_seen.has(band), "no two of count phases fall in the same band")
			bands_seen[band] = true
