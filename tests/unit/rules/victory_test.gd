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
