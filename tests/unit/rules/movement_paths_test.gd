extends GdUnitTestSuite
## Movement.all_paths() (one search, a route per destination) and
## validate_path()'s up-front length refusal, on the BattleFixture
## maps. Expected routes are traced by hand.


func test_all_paths_is_path_to_for_every_destination() -> void:
	# One search, same answers: keys are exactly the reachable set, and
	# each route is the one path_to() picks — including the hand-traced
	# eastern forest route to (2,1).
	var gs := BattleFixture.make_state()
	var u := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	var paths := Movement.all_paths(gs, u.id)
	var reach := Movement.reachable(gs, u.id)
	assert_int(paths.size()).is_equal(9)
	assert_int(paths.size()).is_equal(reach.size())
	for dest: Vector2i in reach:
		assert_bool(paths.has(dest)).append_failure_message("missing %s" % str(dest)).is_true()
		var route: Array[Vector2i] = []
		route.assign(paths[dest])
		assert_array(route).contains_exactly(Movement.path_to(gs, u.id, dest))
	var expected: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(1, 1),
		Vector2i(2, 1),
	]
	var east: Array[Vector2i] = []
	east.assign(paths[Vector2i(2, 1)])
	assert_array(east).contains_exactly(expected)
	var home: Array[Vector2i] = []
	home.assign(paths[Vector2i(0, 0)])
	assert_array(home).contains_exactly([Vector2i(0, 0)])


func test_all_paths_follows_fuel_pressure() -> void:
	# The wall map's two-budget tradeoff, in bulk: fuel 5 flips (4,0)
	# from the southern detour to the route over the wall.
	var gs := BattleFixture.make_wall_state()
	var u := BattleFixture.spawn(gs, BattleFixture.RANGER, 0, Vector2i(0, 0))
	u.fuel = 5
	var over_wall: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(2, 0),
		Vector2i(3, 0),
		Vector2i(4, 0),
	]
	var route: Array[Vector2i] = []
	route.assign(Movement.all_paths(gs, u.id)[Vector2i(4, 0)])
	assert_array(route).contains_exactly(over_wall)
	# Fuel 3: (4,0) drops out of the bulk result exactly as from reachable.
	u.fuel = 3
	assert_bool(Movement.all_paths(gs, u.id).has(Vector2i(4, 0))).is_false()


func test_validate_path_refuses_overlong_paths() -> void:
	# A 24-step snake over the whole board: far past move 3, refused
	# without walking it (save files can carry arbitrary paths).
	var gs := BattleFixture.make_state()
	var u := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	var snake: Array[Vector2i] = []
	for y: int in range(5):
		for i: int in range(5):
			snake.append(Vector2i(i if y % 2 == 0 else 4 - i, y))
	assert_int(snake.size()).is_equal(25)
	assert_bool(Movement.validate_path(gs, u.id, snake)).is_false()
