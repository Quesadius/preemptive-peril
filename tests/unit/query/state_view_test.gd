extends GdUnitTestSuite
## StateView: the AI's only window into the game. Until fog lands the
## projection is total, but the boundary and its contracts are pinned
## here.


func test_view_exposes_team_scoped_reads() -> void:
	var gs := BattleFixture.make_econ_state()
	BattleFixture.claim(gs, Vector2i(1, 1), 0)
	gs.players[0].funds = 1234
	var mine := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	var theirs := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(4, 2))
	var view := StateView.for_team(gs, 0)
	assert_int(view.team).is_equal(0)
	assert_int(view.my_funds()).is_equal(1234)
	assert_object(view.unit(mine.id)).is_same(mine)
	assert_object(view.unit_at(Vector2i(4, 2))).is_same(theirs)
	assert_array(view.my_units()).has_size(1)
	assert_array(view.visible_units()).has_size(2)  # total until fog
	assert_object(view.map()).is_same(gs.map)
	assert_object(view.ruleset()).is_same(gs.ruleset)


func test_legal_actions_only_on_your_turn() -> void:
	var gs := BattleFixture.make_econ_state()
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(4, 2))
	var active := StateView.for_team(gs, 0)
	var waiting := StateView.for_team(gs, 1)
	assert_int(active.legal_actions().size()).is_equal(ActionGenerator.generate(gs).size())
	assert_array(waiting.legal_actions()).is_empty()


func test_validate_and_apply_pass_through() -> void:
	var gs := BattleFixture.make_econ_state()
	var inf := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	var view := StateView.for_team(gs, 0)
	var walk := UnitAction.new()
	walk.unit_id = inf.id
	walk.path = [Vector2i(0, 0), Vector2i(0, 1)]
	assert_object(view.validate(walk)).is_null()
	var bogus := UnitAction.new()
	bogus.unit_id = 999
	bogus.path = [Vector2i(0, 0)]
	assert_that(view.validate(bogus).code).is_equal(ActionError.UNKNOWN_UNIT)
	var events := view.apply(walk)
	assert_bool(events.is_empty()).is_false()
	assert_that(inf.coord).is_equal(Vector2i(0, 1))


func test_preview_matches_combat() -> void:
	var gs := BattleFixture.make_state()
	var tank := BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(1, 2))
	var inf := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(2, 2))
	var view := StateView.for_team(gs, 0)
	var via_view := view.preview_attack(tank.id, inf.id)
	var direct := Combat.preview(gs, tank.id, inf.id)
	assert_int(via_view.damage).is_equal(direct.damage)
	assert_int(via_view.counter_damage).is_equal(direct.counter_damage)
