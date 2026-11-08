extends GdUnitTestSuite
## Turn rotation, day counting, and per-team un-exhaust.


func test_end_turn_rotates_and_starts_next() -> void:
	var gs := BattleFixture.make_state()
	var events := Rules.apply(gs, EndTurnAction.new())
	assert_array(events).has_size(2)
	var ended := events[0] as Events.TurnEnded
	assert_object(ended).is_not_null()
	assert_int(ended.team).is_equal(0)
	var started := events[1] as Events.TurnStarted
	assert_object(started).is_not_null()
	assert_int(started.team).is_equal(1)
	assert_int(started.day).is_equal(1)
	assert_int(gs.current_player).is_equal(1)
	assert_int(gs.day).is_equal(1)


func test_day_increments_when_rotation_wraps() -> void:
	var gs := BattleFixture.make_state()
	Rules.apply(gs, EndTurnAction.new())
	var events := Rules.apply(gs, EndTurnAction.new())
	var started := events[1] as Events.TurnStarted
	assert_int(started.team).is_equal(0)
	assert_int(started.day).is_equal(2)
	assert_int(gs.current_player).is_equal(0)
	assert_int(gs.day).is_equal(2)


func test_begin_turn_unexhausts_only_that_team() -> void:
	var gs := BattleFixture.make_state()
	var ours := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	var theirs := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(4, 4))
	ours.has_moved = true
	ours.has_acted = true
	theirs.has_moved = true
	theirs.has_acted = true
	Rules.apply(gs, EndTurnAction.new())  # 0 -> 1: team 1 wakes up
	assert_bool(theirs.has_acted).is_false()
	assert_bool(theirs.has_moved).is_false()
	assert_bool(ours.has_acted).is_true()
	Rules.apply(gs, EndTurnAction.new())  # 1 -> 0: team 0 wakes up
	assert_bool(ours.has_acted).is_false()


func test_dead_players_are_skipped() -> void:
	var gs := BattleFixture.make_state()
	var third := PlayerState.new()
	third.team = 2
	gs.players.append(third)
	gs.players[1].is_alive = false
	var events := Rules.apply(gs, EndTurnAction.new())
	var started := events[1] as Events.TurnStarted
	assert_int(started.team).is_equal(2)
	assert_int(gs.current_player).is_equal(2)
	assert_int(gs.day).is_equal(1)  # rotation has not crossed player 0 yet
	Rules.apply(gs, EndTurnAction.new())
	assert_int(gs.current_player).is_equal(0)
	assert_int(gs.day).is_equal(2)


func test_validate_end_turn_always_legal() -> void:
	var gs := BattleFixture.make_state()
	assert_object(Rules.validate(gs, EndTurnAction.new())).is_null()
