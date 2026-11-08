extends GdUnitTestSuite
## Tests for DeterministicRng. Replay determinism rests on these holding.


func _draws(rng: DeterministicRng, n: int) -> Array[int]:
	var out: Array[int] = []
	for _i: int in range(n):
		out.append(rng.roll_range(0, 1000000))
	return out


func test_same_seed_same_sequence() -> void:
	var a := DeterministicRng.new(42)
	var b := DeterministicRng.new(42)
	assert_array(_draws(a, 32)).is_equal(_draws(b, 32))


func test_different_seeds_diverge() -> void:
	var a := DeterministicRng.new(1)
	var b := DeterministicRng.new(2)
	assert_array(_draws(a, 16)).is_not_equal(_draws(b, 16))


func test_initial_seed_is_recorded() -> void:
	assert_int(DeterministicRng.new(12345).initial_seed()).is_equal(12345)
	assert_int(DeterministicRng.new().initial_seed()).is_equal(0)


func test_roll_range_respects_bounds() -> void:
	var rng := DeterministicRng.new(7)
	var seen: Dictionary[int, bool] = {}
	for _i: int in range(200):
		var v: int = rng.roll_range(3, 7)
		assert_int(v).is_between(3, 7)
		seen[v] = true
	# 200 draws over 5 values must show variety (deterministic per seed 7).
	assert_int(seen.size()).is_between(3, 5)


func test_clone_continues_identically_and_independently() -> void:
	var a := DeterministicRng.new(99)
	_draws(a, 7)  # advance mid-stream before cloning
	var b := a.clone()
	# Drawing from both yields the same values only if the state was copied,
	# not shared — a shared generator would interleave and diverge.
	assert_array(_draws(a, 16)).is_equal(_draws(b, 16))
	assert_int(b.initial_seed()).is_equal(99)
