extends GdUnitTestSuite
## Movement tests on the BattleFixture 5x5 map. Every expected set below
## was traced by hand against the fixture's terrain/cost tables.


func _assert_reachable(got: Dictionary[Vector2i, int], expected: Dictionary[Vector2i, int]) -> void:
	assert_int(got.size()).append_failure_message("set size, got %s" % str(got)).is_equal(
		expected.size()
	)
	for c: Vector2i in expected:
		assert_bool(got.has(c)).append_failure_message("missing %s" % str(c)).is_true()
		if got.has(c):
			assert_int(got[c]).append_failure_message("remaining at %s" % str(c)).is_equal(
				expected[c]
			)


func test_reachable_infantry_foot_clear() -> void:
	# Foot, move 3, from (0,0). Mountain (2,0) costs 2 via the forest at
	# (1,0); sea is impassable. 9 tiles.
	var gs := BattleFixture.make_state()
	var u := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	var expected: Dictionary[Vector2i, int] = {
		Vector2i(0, 0): 3,
		Vector2i(1, 0): 2,
		Vector2i(0, 1): 2,
		Vector2i(1, 1): 1,
		Vector2i(0, 2): 1,
		Vector2i(2, 0): 0,
		Vector2i(2, 1): 0,
		Vector2i(1, 2): 0,
		Vector2i(0, 3): 0,
	}
	_assert_reachable(Movement.reachable(gs, u.id), expected)


func test_reachable_infantry_foot_snow() -> void:
	# Snow doubles foot costs on plains/forest (2 each), so move 3 only
	# buys one step in any direction.
	var gs := BattleFixture.make_state()
	gs.weather = GameState.Weather.SNOW
	var u := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	var expected: Dictionary[Vector2i, int] = {
		Vector2i(0, 0): 3,
		Vector2i(1, 0): 1,
		Vector2i(0, 1): 1,
	}
	_assert_reachable(Movement.reachable(gs, u.id), expected)


func test_reachable_tank_treads_clear() -> void:
	# Treads, move 4, from (0,0). Forest costs 2, mountain and sea are
	# impassable, so the cheap column is x=0 southward. 11 tiles.
	var gs := BattleFixture.make_state()
	var u := BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(0, 0))
	var expected: Dictionary[Vector2i, int] = {
		Vector2i(0, 0): 4,
		Vector2i(0, 1): 3,
		Vector2i(1, 0): 2,
		Vector2i(0, 2): 2,
		Vector2i(1, 1): 1,
		Vector2i(0, 3): 1,
		Vector2i(1, 2): 1,
		Vector2i(2, 1): 0,
		Vector2i(2, 2): 0,
		Vector2i(1, 3): 0,
		Vector2i(0, 4): 0,
	}
	_assert_reachable(Movement.reachable(gs, u.id), expected)


func test_reachable_heli_air_clear() -> void:
	# Air, move 3, from the center: everything costs 1 (sea included), so
	# the set is the manhattan diamond clipped to the map — 21 tiles, only
	# the four corners (distance 4) missing.
	var gs := BattleFixture.make_state()
	var u := BattleFixture.spawn(gs, BattleFixture.HELI, 0, Vector2i(2, 2))
	var expected: Dictionary[Vector2i, int] = {
		Vector2i(2, 2): 3,
		# distance 1
		Vector2i(2, 1): 2,
		Vector2i(1, 2): 2,
		Vector2i(3, 2): 2,
		Vector2i(2, 3): 2,
		# distance 2
		Vector2i(2, 0): 1,
		Vector2i(1, 1): 1,
		Vector2i(3, 1): 1,
		Vector2i(0, 2): 1,
		Vector2i(4, 2): 1,
		Vector2i(1, 3): 1,
		Vector2i(3, 3): 1,
		Vector2i(2, 4): 1,
		# distance 3
		Vector2i(1, 0): 0,
		Vector2i(3, 0): 0,
		Vector2i(0, 1): 0,
		Vector2i(4, 1): 0,
		Vector2i(0, 3): 0,
		Vector2i(4, 3): 0,
		Vector2i(1, 4): 0,
		Vector2i(3, 4): 0,
	}
	_assert_reachable(Movement.reachable(gs, u.id), expected)


func test_reachable_enemy_blocks_entirely() -> void:
	# Enemy on (0,1) seals the west column: (0,1), (0,2), (0,3) all drop
	# out of the foot-clear baseline because no alternate route fits in 3.
	var gs := BattleFixture.make_state()
	var u := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(0, 1))
	var expected: Dictionary[Vector2i, int] = {
		Vector2i(0, 0): 3,
		Vector2i(1, 0): 2,
		Vector2i(1, 1): 1,
		Vector2i(2, 0): 0,
		Vector2i(2, 1): 0,
		Vector2i(1, 2): 0,
	}
	_assert_reachable(Movement.reachable(gs, u.id), expected)


func test_reachable_ally_is_passable_and_listed() -> void:
	# An ally on (0,1) changes nothing: passable, and its tile stays in
	# the set (whether stopping there is legal is a verb question).
	var gs := BattleFixture.make_state()
	var u := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 1))
	var expected: Dictionary[Vector2i, int] = {
		Vector2i(0, 0): 3,
		Vector2i(1, 0): 2,
		Vector2i(0, 1): 2,
		Vector2i(1, 1): 1,
		Vector2i(0, 2): 1,
		Vector2i(2, 0): 0,
		Vector2i(2, 1): 0,
		Vector2i(1, 2): 0,
		Vector2i(0, 3): 0,
	}
	_assert_reachable(Movement.reachable(gs, u.id), expected)


func test_reachable_fuel_caps_movement() -> void:
	# Heli with 2 fuel: per-tile fuel allows two steps, so the distance-3
	# ring drops off, leaving 13 tiles. Remaining reports movement POINTS
	# left (3 - cost), even where fuel is what actually stops the unit.
	var gs := BattleFixture.make_state()
	var u := BattleFixture.spawn(gs, BattleFixture.HELI, 0, Vector2i(2, 2))
	u.fuel = 2
	var expected: Dictionary[Vector2i, int] = {
		Vector2i(2, 2): 3,
		# distance 1
		Vector2i(2, 1): 2,
		Vector2i(1, 2): 2,
		Vector2i(3, 2): 2,
		Vector2i(2, 3): 2,
		# distance 2
		Vector2i(2, 0): 1,
		Vector2i(1, 1): 1,
		Vector2i(3, 1): 1,
		Vector2i(0, 2): 1,
		Vector2i(4, 2): 1,
		Vector2i(1, 3): 1,
		Vector2i(3, 3): 1,
		Vector2i(2, 4): 1,
	}
	_assert_reachable(Movement.reachable(gs, u.id), expected)


func test_reachable_fuel_one_still_climbs_mountains() -> void:
	# Per-tile fuel: one fuel buys one step onto ANY enterable tile, even
	# the cost-2 mountain — points pay the terrain, fuel pays the step.
	var gs := BattleFixture.make_state()
	var u := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(1, 0))
	u.fuel = 1
	var expected: Dictionary[Vector2i, int] = {
		Vector2i(1, 0): 3,
		Vector2i(0, 0): 2,
		Vector2i(2, 0): 1,
		Vector2i(1, 1): 2,
	}
	_assert_reachable(Movement.reachable(gs, u.id), expected)


func test_enter_cost_by_terrain_class_and_weather() -> void:
	var gs := BattleFixture.make_state()
	var inf := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 2))
	var tank := BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(2, 3))
	var heli := BattleFixture.spawn(gs, BattleFixture.HELI, 0, Vector2i(2, 4))
	# Clear weather.
	assert_int(Movement.enter_cost(gs, inf, Vector2i(3, 0))).is_equal(1)  # plains
	assert_int(Movement.enter_cost(gs, inf, Vector2i(1, 0))).is_equal(1)  # forest
	assert_int(Movement.enter_cost(gs, inf, Vector2i(2, 0))).is_equal(2)  # mountain
	assert_int(Movement.enter_cost(gs, inf, Vector2i(3, 2))).is_equal(-1)  # sea
	assert_int(Movement.enter_cost(gs, inf, Vector2i(0, 4))).is_equal(1)  # road
	assert_int(Movement.enter_cost(gs, inf, Vector2i(5, 0))).is_equal(-1)  # off-map
	assert_int(Movement.enter_cost(gs, tank, Vector2i(1, 0))).is_equal(2)  # forest
	assert_int(Movement.enter_cost(gs, tank, Vector2i(2, 0))).is_equal(-1)  # mountain
	assert_int(Movement.enter_cost(gs, heli, Vector2i(3, 2))).is_equal(1)  # sea
	# Rain slows treads on plains but not foot.
	gs.weather = GameState.Weather.RAIN
	assert_int(Movement.enter_cost(gs, tank, Vector2i(3, 0))).is_equal(2)
	assert_int(Movement.enter_cost(gs, inf, Vector2i(3, 0))).is_equal(1)
	# Snow slows foot on plains; roads stay cost 1.
	gs.weather = GameState.Weather.SNOW
	assert_int(Movement.enter_cost(gs, inf, Vector2i(3, 0))).is_equal(2)
	assert_int(Movement.enter_cost(gs, inf, Vector2i(0, 4))).is_equal(1)


func test_path_to_is_cheapest_and_deterministic() -> void:
	# Two cost-3 routes to (2,1) exist; the fixed N/E/S/W expansion order
	# must always pick the eastern one through the forests.
	var gs := BattleFixture.make_state()
	var u := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	var expected: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(1, 1),
		Vector2i(2, 1),
	]
	assert_array(Movement.path_to(gs, u.id, Vector2i(2, 1))).contains_exactly(expected)


func test_path_to_own_tile_is_single_element() -> void:
	var gs := BattleFixture.make_state()
	var u := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	assert_array(Movement.path_to(gs, u.id, Vector2i(0, 0))).contains_exactly([Vector2i(0, 0)])


func test_path_to_unreachable_is_empty() -> void:
	var gs := BattleFixture.make_state()
	var u := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	assert_array(Movement.path_to(gs, u.id, Vector2i(3, 2))).is_empty()  # sea
	assert_array(Movement.path_to(gs, u.id, Vector2i(4, 4))).is_empty()  # too far


func test_validate_path_accepts_legal_routes() -> void:
	var gs := BattleFixture.make_state()
	var u := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	var cheapest: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(1, 1),
		Vector2i(2, 1),
	]
	assert_bool(Movement.validate_path(gs, u.id, cheapest)).is_true()
	# A scenic-but-affordable route is just as legal as the cheapest one.
	var scenic: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(0, 1),
		Vector2i(1, 1),
		Vector2i(2, 1),
	]
	assert_bool(Movement.validate_path(gs, u.id, scenic)).is_true()
	# Standing still is a valid (empty) move.
	assert_bool(Movement.validate_path(gs, u.id, [Vector2i(0, 0)])).is_true()


func test_validate_path_rejects_malformed_input() -> void:
	var gs := BattleFixture.make_state()
	var u := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	assert_bool(Movement.validate_path(gs, u.id, [])).is_false()
	# Doesn't start on the unit's tile.
	assert_bool(Movement.validate_path(gs, u.id, [Vector2i(1, 0), Vector2i(1, 1)])).is_false()
	# Gap and diagonal steps.
	assert_bool(Movement.validate_path(gs, u.id, [Vector2i(0, 0), Vector2i(2, 0)])).is_false()
	assert_bool(Movement.validate_path(gs, u.id, [Vector2i(0, 0), Vector2i(1, 1)])).is_false()
	# Revisiting a tile.
	var loop: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 0)]
	assert_bool(Movement.validate_path(gs, u.id, loop)).is_false()
	# Over budget: four plains steps cost 4 > move 3.
	var long_walk: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(0, 1),
		Vector2i(0, 2),
		Vector2i(0, 3),
		Vector2i(0, 4),
	]
	assert_bool(Movement.validate_path(gs, u.id, long_walk)).is_false()


func test_validate_path_rejects_blockers_and_impassable() -> void:
	var gs := BattleFixture.make_state()
	var u := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(1, 0))
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 1))
	# Enemy mid-path and enemy at the destination both fail.
	var through: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1)]
	assert_bool(Movement.validate_path(gs, u.id, through)).is_false()
	assert_bool(Movement.validate_path(gs, u.id, [Vector2i(0, 0), Vector2i(1, 0)])).is_false()
	# Ally at the destination passes here — stop legality is a verb question.
	assert_bool(Movement.validate_path(gs, u.id, [Vector2i(0, 0), Vector2i(0, 1)])).is_true()
	# Impassable terrain: infantry stepping into sea.
	var sailor := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(2, 2))
	var into_sea: Array[Vector2i] = [Vector2i(2, 2), Vector2i(3, 2)]
	assert_bool(Movement.validate_path(gs, sailor.id, into_sea)).is_false()


func test_validate_path_honors_fuel_budget() -> void:
	var gs := BattleFixture.make_state()
	var u := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	u.fuel = 1
	# Two steps need two fuel, whatever they cost in points.
	var two_steps: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1)]
	assert_bool(Movement.validate_path(gs, u.id, two_steps)).is_false()
	assert_bool(Movement.validate_path(gs, u.id, [Vector2i(0, 0), Vector2i(1, 0)])).is_true()
	# One fuel is enough for one expensive step: the cost-2 mountain.
	var climber := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(1, 0))
	climber.fuel = 1
	var onto_mountain: Array[Vector2i] = [Vector2i(1, 0), Vector2i(2, 0)]
	assert_bool(Movement.validate_path(gs, climber.id, onto_mountain)).is_true()


func test_path_to_agrees_with_reachable_and_validate() -> void:
	# Glue property: every reachable coord gets a valid path that starts
	# at the unit, ends at the coord, and spends exactly budget-remaining.
	var gs := BattleFixture.make_state()
	var u := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	var reach := Movement.reachable(gs, u.id)
	for dest: Vector2i in reach:
		var path := Movement.path_to(gs, u.id, dest)
		assert_bool(path.is_empty()).append_failure_message("no path to %s" % str(dest)).is_false()
		assert_that(path[0]).is_equal(Vector2i(0, 0))
		assert_that(path[path.size() - 1]).is_equal(dest)
		assert_bool(Movement.validate_path(gs, u.id, path)).is_true()


func test_reachable_two_budget_tradeoff_on_wall_map() -> void:
	# Ranger (move 7) at (0,0) on the wall map. To (4,0): through the wall
	# costs 7 in 4 steps; around the south row costs 6 in 6 steps. With
	# ample fuel the cheap detour wins — remaining 1.
	var gs := BattleFixture.make_wall_state()
	var u := BattleFixture.spawn(gs, BattleFixture.RANGER, 0, Vector2i(0, 0))
	var ample: Dictionary[Vector2i, int] = {
		Vector2i(0, 0): 7,
		Vector2i(1, 0): 5,
		Vector2i(2, 0): 3,
		Vector2i(3, 0): 1,
		Vector2i(4, 0): 1,
		Vector2i(0, 1): 6,
		Vector2i(1, 1): 5,
		Vector2i(2, 1): 4,
		Vector2i(3, 1): 3,
		Vector2i(4, 1): 2,
	}
	_assert_reachable(Movement.reachable(gs, u.id), ample)
	# Fuel 5: the 6-step detour no longer fits, but the 4-step wall route
	# still does — (4,0) stays reachable at cost 7, remaining 0. A search
	# over coords alone would miss this route.
	u.fuel = 5
	var tight: Dictionary[Vector2i, int] = {
		Vector2i(0, 0): 7,
		Vector2i(1, 0): 5,
		Vector2i(2, 0): 3,
		Vector2i(3, 0): 1,
		Vector2i(4, 0): 0,
		Vector2i(0, 1): 6,
		Vector2i(1, 1): 5,
		Vector2i(2, 1): 4,
		Vector2i(3, 1): 3,
		Vector2i(4, 1): 2,
	}
	_assert_reachable(Movement.reachable(gs, u.id), tight)
	# Fuel 3: every route to (4,0), (3,1) or (4,1) needs 4+ steps.
	u.fuel = 3
	var exhausted: Dictionary[Vector2i, int] = {
		Vector2i(0, 0): 7,
		Vector2i(1, 0): 5,
		Vector2i(2, 0): 3,
		Vector2i(3, 0): 1,
		Vector2i(0, 1): 6,
		Vector2i(1, 1): 5,
		Vector2i(2, 1): 4,
	}
	_assert_reachable(Movement.reachable(gs, u.id), exhausted)


func test_path_to_switches_route_under_fuel_pressure() -> void:
	var gs := BattleFixture.make_wall_state()
	var u := BattleFixture.spawn(gs, BattleFixture.RANGER, 0, Vector2i(0, 0))
	# Ample fuel: the cost-6 southern detour is the unique cheapest route.
	var detour: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(0, 1),
		Vector2i(1, 1),
		Vector2i(2, 1),
		Vector2i(3, 1),
		Vector2i(4, 1),
		Vector2i(4, 0),
	]
	assert_array(Movement.path_to(gs, u.id, Vector2i(4, 0))).contains_exactly(detour)
	assert_bool(Movement.validate_path(gs, u.id, detour)).is_true()
	# Fuel 5: the detour is illegal (6 steps) and the wall route wins.
	u.fuel = 5
	var over_wall: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(2, 0),
		Vector2i(3, 0),
		Vector2i(4, 0),
	]
	assert_array(Movement.path_to(gs, u.id, Vector2i(4, 0))).contains_exactly(over_wall)
	assert_bool(Movement.validate_path(gs, u.id, over_wall)).is_true()
	assert_bool(Movement.validate_path(gs, u.id, detour)).is_false()
	# Fuel 3: no route at all.
	u.fuel = 3
	assert_array(Movement.path_to(gs, u.id, Vector2i(4, 0))).is_empty()
