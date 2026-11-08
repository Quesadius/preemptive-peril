extends GdUnitTestSuite
## Tests for the GameState aggregate on a hand-built 5x5 two-player fixture.


func _make_map(w: int, h: int) -> MapState:
	var m := MapState.new()
	m.width = w
	m.height = h
	var t := PackedInt32Array()
	t.resize(w * h)
	m.terrain = t
	var owners := PackedInt32Array()
	owners.resize(w * h)
	owners.fill(MapState.NO_OWNER)
	m.property_owner = owners
	return m


func _make_state() -> GameState:
	var gs := GameState.new()
	gs.ruleset = Ruleset.new()
	gs.config = GameConfig.new()
	gs.map = _make_map(5, 5)
	gs.rng = DeterministicRng.new(42)
	for team: int in range(2):
		var p := PlayerState.new()
		p.team = team
		gs.players.append(p)
	return gs


func _spawn(gs: GameState, team: int, coord: Vector2i) -> UnitState:
	var u := UnitState.new()
	u.id = gs.next_unit_id
	gs.next_unit_id += 1
	u.team = team
	u.coord = coord
	gs.units[u.id] = u
	gs.occupancy[coord] = u.id
	return u


func test_defaults_match_spec() -> void:
	var gs := _make_state()
	assert_int(gs.current_player).is_equal(0)
	assert_int(gs.day).is_equal(1)
	assert_int(gs.weather).is_equal(GameState.Weather.CLEAR)
	assert_int(gs.weather_days_left).is_equal(0)
	assert_int(gs.next_unit_id).is_equal(1)
	assert_int(gs.units.size()).is_equal(0)
	assert_int(gs.occupancy.size()).is_equal(0)


func test_unit_at_finds_occupant() -> void:
	var gs := _make_state()
	var u := _spawn(gs, 0, Vector2i(2, 2))
	assert_object(gs.unit_at(Vector2i(2, 2))).is_same(u)


func test_unit_at_empty_tile_is_null() -> void:
	var gs := _make_state()
	_spawn(gs, 0, Vector2i(2, 2))
	assert_object(gs.unit_at(Vector2i(1, 2))).is_null()


func test_units_of_filters_by_team_and_sorts_by_id() -> void:
	var gs := _make_state()
	# Insert team 0's units out of id order to prove the sort is real.
	var high := UnitState.new()
	high.id = 8
	high.team = 0
	high.coord = Vector2i(3, 3)
	gs.units[high.id] = high
	gs.occupancy[high.coord] = high.id
	var low := UnitState.new()
	low.id = 2
	low.team = 0
	low.coord = Vector2i(1, 1)
	gs.units[low.id] = low
	gs.occupancy[low.coord] = low.id
	_spawn(gs, 1, Vector2i(4, 4))
	var got_ids: Array[int] = []
	for u: UnitState in gs.units_of(0):
		got_ids.append(u.id)
	assert_array(got_ids).contains_exactly([2, 8])
	assert_array(gs.units_of(1)).has_size(1)
	assert_array(gs.units_of(9)).is_empty()


func test_units_of_includes_loaded_cargo() -> void:
	var gs := _make_state()
	var carrier := _spawn(gs, 0, Vector2i(0, 0))
	# A loaded unit exists in `units` but not in `occupancy`.
	var rider := UnitState.new()
	rider.id = gs.next_unit_id
	gs.next_unit_id += 1
	rider.team = 0
	rider.carrier_id = carrier.id
	carrier.cargo.append(rider.id)
	gs.units[rider.id] = rider
	assert_array(gs.units_of(0)).has_size(2)


func test_active_player_follows_current_player() -> void:
	var gs := _make_state()
	assert_object(gs.active_player()).is_same(gs.players[0])
	gs.current_player = 1
	assert_object(gs.active_player()).is_same(gs.players[1])


func test_clone_shares_immutable_data_copies_the_rest() -> void:
	var gs := _make_state()
	var c := gs.clone()
	assert_object(c.ruleset).is_same(gs.ruleset)
	assert_object(c.config).is_same(gs.config)
	assert_object(c.map).is_not_same(gs.map)
	assert_object(c.rng).is_not_same(gs.rng)


func test_clone_deep_copies_units_and_occupancy() -> void:
	var gs := _make_state()
	var u := _spawn(gs, 0, Vector2i(2, 2))
	var c := gs.clone()
	assert_object(c.units[u.id]).is_not_same(u)
	# Damage + move the original; the clone must keep the old picture.
	u.hp = 55
	gs.occupancy.erase(Vector2i(2, 2))
	u.coord = Vector2i(3, 2)
	gs.occupancy[u.coord] = u.id
	gs.day = 4
	gs.players[0].funds = 9000
	_spawn(gs, 1, Vector2i(0, 4))
	assert_int(c.units[u.id].hp).is_equal(100)
	assert_object(c.unit_at(Vector2i(2, 2))).is_not_null()
	assert_object(c.unit_at(Vector2i(3, 2))).is_null()
	assert_int(c.day).is_equal(1)
	assert_int(c.players[0].funds).is_equal(0)
	assert_int(c.units.size()).is_equal(1)
	assert_int(c.next_unit_id).is_equal(2)


func test_clone_rng_continues_identically() -> void:
	var gs := _make_state()
	gs.rng.roll_range(0, 100)  # advance a little first
	var c := gs.clone()
	var from_original: Array[int] = []
	var from_clone: Array[int] = []
	for _i: int in range(12):
		from_original.append(gs.rng.roll_range(0, 1000000))
	for _i: int in range(12):
		from_clone.append(c.rng.roll_range(0, 1000000))
	assert_array(from_original).is_equal(from_clone)
