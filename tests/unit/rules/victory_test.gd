extends GdUnitTestSuite
## Victory rules: rout when a player has no units and no production,
## game end when one player stands, rotation skipping the fallen.


func test_rout_ends_the_game() -> void:
	var gs := BattleFixture.make_state()
	var tank := BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(1, 2))
	var inf := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(2, 2))
	inf.hp = 30
	var attack := UnitAction.new()
	attack.unit_id = tank.id
	attack.path = [Vector2i(1, 2)]
	attack.verb = UnitAction.Verb.ATTACK
	attack.target_coord = Vector2i(2, 2)
	var events := Rules.apply(gs, attack)
	assert_array(events).has_size(5)
	assert_object(events[1] as Events.UnitDestroyed).is_not_null()
	var eliminated := events[3] as Events.PlayerEliminated
	assert_object(eliminated).is_not_null()
	assert_int(eliminated.team).is_equal(1)
	assert_that(eliminated.reason).is_equal(&"routed")
	var ended := events[4] as Events.GameEnded
	assert_object(ended).is_not_null()
	assert_int(ended.winning_team).is_equal(0)
	assert_bool(gs.players[1].is_alive).is_false()
	assert_bool(gs.players[0].is_alive).is_true()


func test_production_defers_rout_until_captured() -> void:
	# Team 1 loses its last unit but still owns a factory: alive. Then
	# team 0 captures that factory: the PropertyCaptured loss triggers
	# the rout.
	var gs := BattleFixture.make_econ_state()
	BattleFixture.claim(gs, Vector2i(3, 1), 1)
	var tank := BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(4, 1))
	var capturer := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(3, 1))
	var last := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(4, 2))
	last.hp = 20
	var kill := UnitAction.new()
	kill.unit_id = tank.id
	kill.path = [Vector2i(4, 1)]
	kill.verb = UnitAction.Verb.ATTACK
	kill.target_coord = Vector2i(4, 2)
	var kill_events := Rules.apply(gs, kill)
	for e: GameEvent in kill_events:
		assert_bool(e is Events.PlayerEliminated).is_false()
	assert_bool(gs.players[1].is_alive).is_true()  # the factory sustains them
	# Now take the factory out from under them.
	gs.map.capture_progress[Vector2i(3, 1)] = 19
	var grab := UnitAction.new()
	grab.unit_id = capturer.id
	grab.path = [Vector2i(3, 1)]
	grab.verb = UnitAction.Verb.CAPTURE
	var fatal := Rules.apply(gs, grab)
	var saw_elimination := false
	var saw_end := false
	for e: GameEvent in fatal:
		saw_elimination = saw_elimination or e is Events.PlayerEliminated
		saw_end = saw_end or e is Events.GameEnded
	assert_bool(saw_elimination).is_true()
	assert_bool(saw_end).is_true()
	assert_bool(gs.players[1].is_alive).is_false()


func test_rotation_skips_the_eliminated() -> void:
	var gs := BattleFixture.make_state()
	var third := PlayerState.new()
	third.team = 2
	gs.players.append(third)
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 2, Vector2i(4, 4))
	gs.players[1].is_alive = false  # already fell earlier
	Rules.apply(gs, EndTurnAction.new())
	assert_int(gs.current_player).is_equal(2)
	Rules.apply(gs, EndTurnAction.new())
	assert_int(gs.current_player).is_equal(0)
	assert_int(gs.day).is_equal(2)


## Paints an HQ for `team` on the econ map and parks a team-0 infantry
## on it, one step from finishing the capture (10 progress + 10 HP).
func _hq_siege(gs: GameState, coord: Vector2i, team: int) -> UnitState:
	gs.map.terrain[gs.map.idx(coord)] = BattleFixture.HQ
	BattleFixture.claim(gs, coord, team)
	var capturer := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, coord)
	gs.map.capture_progress[coord] = 10
	return capturer


func _capture(gs: GameState, unit: UnitState) -> Array[GameEvent]:
	var grab := UnitAction.new()
	grab.unit_id = unit.id
	grab.path = [unit.coord]
	grab.verb = UnitAction.Verb.CAPTURE
	assert_object(Rules.validate(gs, grab)).is_null()
	return Rules.apply(gs, grab)


func _eliminations(events: Array[GameEvent]) -> Array[Events.PlayerEliminated]:
	var out: Array[Events.PlayerEliminated] = []
	for e: GameEvent in events:
		if e is Events.PlayerEliminated:
			out.append(e as Events.PlayerEliminated)
	return out


func _game_end(events: Array[GameEvent]) -> Events.GameEnded:
	for e: GameEvent in events:
		if e is Events.GameEnded:
			return e as Events.GameEnded
	return null


func test_capturing_the_hq_ends_the_game() -> void:
	# Blue keeps a factory and a tank, so this can't be a rout: the HQ
	# alone decides it.
	var gs := BattleFixture.make_econ_state()
	BattleFixture.claim(gs, Vector2i(3, 1), 1)
	BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(4, 2))
	var capturer := _hq_siege(gs, Vector2i(2, 0), 1)
	var events := _capture(gs, capturer)
	var out := _eliminations(events)
	assert_int(out.size()).is_equal(1)
	assert_int(out[0].team).is_equal(1)
	assert_that(out[0].reason).is_equal(&"hq_captured")
	var ended := _game_end(events)
	assert_object(ended).is_not_null()
	assert_int(ended.winning_team).is_equal(0)
	assert_bool(gs.players[1].is_alive).is_false()
	assert_int(gs.map.property_owner[gs.map.idx(Vector2i(2, 0))]).is_equal(0)


func test_cities_and_neutral_hqs_are_not_decisive() -> void:
	# The same capture on an ordinary city costs blue nothing but the city…
	var gs := BattleFixture.make_econ_state()
	BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(4, 2))
	BattleFixture.claim(gs, Vector2i(2, 0), 1)  # the econ map's city
	var capturer := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(2, 0))
	gs.map.capture_progress[Vector2i(2, 0)] = 10
	assert_array(_eliminations(_capture(gs, capturer))).is_empty()
	assert_bool(gs.players[1].is_alive).is_true()
	# …and taking an unowned HQ eliminates nobody.
	var neutral := BattleFixture.make_econ_state()
	BattleFixture.spawn(neutral, BattleFixture.TANK, 1, Vector2i(4, 2))
	var taker := _hq_siege(neutral, Vector2i(2, 0), MapState.NO_OWNER)
	assert_array(_eliminations(_capture(neutral, taker))).is_empty()
	assert_bool(neutral.players[1].is_alive).is_true()


func test_a_second_hq_keeps_its_owner_in_the_game() -> void:
	var gs := BattleFixture.make_econ_state()
	BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(4, 2))
	var first := _hq_siege(gs, Vector2i(2, 0), 1)
	var second := _hq_siege(gs, Vector2i(0, 0), 1)
	assert_array(_eliminations(_capture(gs, first))).is_empty()  # (0,0) still stands
	assert_bool(gs.players[1].is_alive).is_true()
	var events := _capture(gs, second)
	assert_that(_eliminations(events)[0].reason).is_equal(&"hq_captured")
	assert_object(_game_end(events)).is_not_null()


func test_hq_loss_among_three_players_leaves_the_game_running() -> void:
	var gs := BattleFixture.make_econ_state()
	var third := PlayerState.new()
	third.team = 2
	gs.players.append(third)
	BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(4, 2))
	BattleFixture.spawn(gs, BattleFixture.TANK, 2, Vector2i(4, 0))
	var capturer := _hq_siege(gs, Vector2i(2, 0), 1)
	var events := _capture(gs, capturer)
	var out := _eliminations(events)
	assert_int(out.size()).is_equal(1)
	assert_int(out[0].team).is_equal(1)
	assert_object(_game_end(events)).is_null()  # red and team 2 fight on
	assert_bool(gs.players[2].is_alive).is_true()
