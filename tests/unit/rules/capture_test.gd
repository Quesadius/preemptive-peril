extends GdUnitTestSuite
## Capture rules on the economy fixture map: neutral city at (2,0),
## factories at (1,1) and (3,1). Threshold is 20; a step adds the
## capturer's displayed HP.


func _capture(unit_id: int, path: Array[Vector2i]) -> UnitAction:
	var a := UnitAction.new()
	a.unit_id = unit_id
	a.path = path
	a.verb = UnitAction.Verb.CAPTURE
	return a


func test_validate_capture_rules() -> void:
	var gs := BattleFixture.make_econ_state()
	var tank := BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(2, 0))
	var err := Rules.validate(gs, _capture(tank.id, [Vector2i(2, 0)]))
	assert_that(err.code).is_equal(ActionError.CANNOT_CAPTURE)
	var inf := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	err = Rules.validate(gs, _capture(inf.id, [Vector2i(0, 0)]))
	assert_that(err.code).is_equal(ActionError.NOT_CAPTURABLE)
	# Own property: claim the factory and stand the infantry on it.
	BattleFixture.claim(gs, Vector2i(1, 1), 0)
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)]
	err = Rules.validate(gs, _capture(inf.id, path))
	assert_that(err.code).is_equal(ActionError.ALREADY_OWNED)
	# A neutral factory next door is fair game.
	BattleFixture.claim(gs, Vector2i(1, 1), MapState.NO_OWNER)
	assert_object(Rules.validate(gs, _capture(inf.id, path))).is_null()


func test_capture_progresses_persists_and_completes() -> void:
	var gs := BattleFixture.make_econ_state()
	var inf := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(2, 0))
	var events := Rules.apply(gs, _capture(inf.id, [Vector2i(2, 0)]))
	assert_array(events).has_size(2)  # CaptureProgressed + UnitExhausted
	var progressed := events[0] as Events.CaptureProgressed
	assert_object(progressed).is_not_null()
	assert_int(progressed.points).is_equal(10)
	assert_int(progressed.total).is_equal(10)
	assert_int(gs.map.capture_progress[Vector2i(2, 0)]).is_equal(10)
	assert_bool(gs.map.is_property(Vector2i(2, 0))).is_false()  # still neutral
	# Progress survives the enemy turn while the capturer stays put.
	Rules.apply(gs, EndTurnAction.new())
	Rules.apply(gs, EndTurnAction.new())
	assert_int(gs.map.capture_progress[Vector2i(2, 0)]).is_equal(10)
	# Second step: 10 + 10 reaches the threshold.
	var done := Rules.apply(gs, _capture(inf.id, [Vector2i(2, 0)]))
	var captured := done[0] as Events.PropertyCaptured
	assert_object(captured).is_not_null()
	assert_int(captured.new_team).is_equal(0)
	assert_int(captured.old_team).is_equal(MapState.NO_OWNER)
	assert_int(gs.map.property_owner[gs.map.idx(Vector2i(2, 0))]).is_equal(0)
	assert_bool(gs.map.capture_progress.has(Vector2i(2, 0))).is_false()


func test_damaged_capturer_progresses_by_display_hp() -> void:
	var gs := BattleFixture.make_econ_state()
	var inf := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(2, 0))
	inf.hp = 45  # displayed 5
	var events := Rules.apply(gs, _capture(inf.id, [Vector2i(2, 0)]))
	assert_int((events[0] as Events.CaptureProgressed).total).is_equal(5)


func test_capturing_enemy_property_records_old_owner() -> void:
	var gs := BattleFixture.make_econ_state()
	BattleFixture.claim(gs, Vector2i(2, 0), 1)
	var inf := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(2, 0))
	gs.map.capture_progress[Vector2i(2, 0)] = 15  # mid-capture
	var events := Rules.apply(gs, _capture(inf.id, [Vector2i(2, 0)]))
	var captured := events[0] as Events.PropertyCaptured
	assert_int(captured.old_team).is_equal(1)
	assert_int(gs.map.property_owner[gs.map.idx(Vector2i(2, 0))]).is_equal(0)


func test_moving_away_abandons_progress() -> void:
	var gs := BattleFixture.make_econ_state()
	var inf := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(2, 0))
	Rules.apply(gs, _capture(inf.id, [Vector2i(2, 0)]))
	Rules.apply(gs, EndTurnAction.new())
	Rules.apply(gs, EndTurnAction.new())
	var walk := UnitAction.new()
	walk.unit_id = inf.id
	walk.path = [Vector2i(2, 0), Vector2i(2, 1)]
	Rules.apply(gs, walk)
	assert_bool(gs.map.capture_progress.has(Vector2i(2, 0))).is_false()


func test_capturer_death_abandons_progress() -> void:
	var gs := BattleFixture.make_econ_state()
	var inf := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(2, 0))
	inf.hp = 30
	gs.map.capture_progress[Vector2i(2, 0)] = 10
	var tank := BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(2, 1))
	Rules.apply(gs, EndTurnAction.new())  # team 1's turn
	var attack := UnitAction.new()
	attack.unit_id = tank.id
	attack.path = [Vector2i(2, 1)]
	attack.verb = UnitAction.Verb.ATTACK
	attack.target_coord = Vector2i(2, 0)
	assert_object(Rules.validate(gs, attack)).is_null()
	Rules.apply(gs, attack)
	assert_bool(gs.units.has(inf.id)).is_false()
	assert_bool(gs.map.capture_progress.has(Vector2i(2, 0))).is_false()


func test_move_and_capture_is_one_action() -> void:
	var gs := BattleFixture.make_econ_state()
	var inf := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(2, 2))
	var path: Array[Vector2i] = [Vector2i(2, 2), Vector2i(2, 1), Vector2i(2, 0)]
	var action := _capture(inf.id, path)
	assert_object(Rules.validate(gs, action)).is_null()
	var events := Rules.apply(gs, action)
	assert_array(events).has_size(3)
	assert_object(events[0] as Events.UnitMoved).is_not_null()
	assert_object(events[1] as Events.CaptureProgressed).is_not_null()
	assert_object(events[2] as Events.UnitExhausted).is_not_null()
	assert_that(inf.coord).is_equal(Vector2i(2, 0))
	assert_int(gs.map.capture_progress[Vector2i(2, 0)]).is_equal(10)
