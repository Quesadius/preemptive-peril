extends GdUnitTestSuite
## SimpleAI around headquarters and builds, on BattleFixture's maps with
## HQs painted on. Scores in the comments are worked out by hand from the
## fixture's damage tables (luck 0) and SimpleAI's constants.


func _paint(gs: GameState, coord: Vector2i, terrain: int, owner_team: int) -> void:
	gs.map.terrain[gs.map.idx(coord)] = terrain
	BattleFixture.claim(gs, coord, owner_team)


func _choose(gs: GameState, team: int) -> Action:
	return SimpleAI.new().choose_action(StateView.for_team(gs, team))


func _dest(action: Action) -> Vector2i:
	var ua := action as UnitAction
	return ua.path[ua.path.size() - 1]


func test_capturer_marches_on_the_enemy_hq_past_a_nearer_city() -> void:
	# Snow: plains and forest cost 2, roads 1, so the move-3 infantry at
	# (1,2) reaches only (1,1) (0,2) (2,2) (1,3) and, via (1,3), the road
	# at (1,4). The neutral city at (0,0) is 3 tiles off; blue's HQ at
	# (4,4) is 5, but counts 4 closer — so the march is on the HQ, and
	# (1,4) gains the most ground (2 tiles, 24 points).
	var gs := BattleFixture.make_state()
	gs.weather = GameState.Weather.SNOW
	_paint(gs, Vector2i(0, 0), BattleFixture.CITY, MapState.NO_OWNER)
	_paint(gs, Vector2i(4, 4), BattleFixture.HQ, 1)
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(1, 2))
	var action := _choose(gs, 0) as UnitAction
	assert_object(action).is_not_null()
	assert_int(action.verb).is_equal(UnitAction.Verb.WAIT)
	assert_that(_dest(action)).is_equal(Vector2i(1, 4))


func test_capture_step_on_an_enemy_hq_outbids_a_city_step() -> void:
	# Both adjacent; neither capture completes this turn. City step 500,
	# HQ step 900.
	var gs := BattleFixture.make_state()
	_paint(gs, Vector2i(2, 1), BattleFixture.CITY, MapState.NO_OWNER)
	_paint(gs, Vector2i(1, 2), BattleFixture.HQ, 1)
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(2, 2))
	var action := _choose(gs, 0) as UnitAction
	assert_int(action.verb).is_equal(UnitAction.Verb.CAPTURE)
	assert_that(_dest(action)).is_equal(Vector2i(1, 2))


func test_strikes_the_raider_on_its_hq_over_an_easy_kill() -> void:
	# Red's tank at (1,2) sits between a blue infantry standing on red's
	# HQ (4 stars) and a 1-HP blue tank.
	#   Kill the tank: 10/100 x 7000 + 30% bounty = 2800.
	#   MG the raider: 40 x 0.6 = 24 damage -> 240, plus 4000 x 5 x 24/100
	#   = 4800 for hitting a capturer on the HQ, minus the 3-damage counter
	#   (210) = 4830.
	var gs := BattleFixture.make_state()
	_paint(gs, Vector2i(0, 2), BattleFixture.HQ, 0)
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(0, 2))
	BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(1, 2))
	BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(2, 2)).hp = 10
	var action := _choose(gs, 0) as UnitAction
	assert_int(action.verb).is_equal(UnitAction.Verb.ATTACK)
	assert_that(action.target_coord).is_equal(Vector2i(0, 2))


func test_parks_on_the_hq_when_a_raider_closes_in() -> void:
	# Blue infantry at (3,4) is 3 tiles from red's HQ at (0,4): a raider,
	# and out of reach of red's infantry at (0,2) this turn. Standing on
	# the HQ (1500 - 20 for a 1000-cost doorstop) beats everything else —
	# an occupied HQ can't be captured.
	var gs := BattleFixture.make_state()
	_paint(gs, Vector2i(0, 4), BattleFixture.HQ, 0)
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 2))
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(3, 4))
	var action := _choose(gs, 0) as UnitAction
	assert_int(action.verb).is_equal(UnitAction.Verb.WAIT)
	assert_that(_dest(action)).is_equal(Vector2i(0, 4))
	# With the raider gone, the HQ is just another tile: red marches out.
	var calm := BattleFixture.make_state()
	_paint(calm, Vector2i(0, 4), BattleFixture.HQ, 0)
	BattleFixture.spawn(calm, BattleFixture.INFANTRY, 0, Vector2i(0, 2))
	BattleFixture.spawn(calm, BattleFixture.TANK, 1, Vector2i(4, 0))
	assert_that(_dest(_choose(calm, 0))).is_not_equal(Vector2i(0, 4))


func test_builds_a_capturer_first_when_it_has_none() -> void:
	# No units at all: infantry scores 120 + 10 + (1000 - 20) = 1110,
	# just ahead of the pricier ranger (1100) and far ahead of the heli.
	var gs := BattleFixture.make_econ_state()
	BattleFixture.claim(gs, Vector2i(1, 1), 0)
	gs.players[0].funds = 16000
	var action := _choose(gs, 0) as BuildAction
	assert_object(action).is_not_null()
	assert_int(action.unit_type_id).is_equal(BattleFixture.INFANTRY)


func test_builds_an_answer_to_an_enemy_nothing_it_owns_can_hurt() -> void:
	# Red fields only an infantry (rifle vs tank: 5). Against a visible
	# blue tank, a tank of its own (cannon 55) scores 120 + 70 + 800 = 990,
	# ahead of artillery (980) and the heli that would otherwise win (210).
	var gs := BattleFixture.make_econ_state()
	BattleFixture.claim(gs, Vector2i(1, 1), 0)
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0)).has_acted = true
	BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(4, 2))
	gs.players[0].funds = 16000
	var action := _choose(gs, 0) as BuildAction
	assert_object(action).is_not_null()
	assert_int(action.unit_type_id).is_equal(BattleFixture.TANK)


func test_low_on_fuel_a_flyer_turns_for_home() -> void:
	# The fixture heli (move 3) burns 5 fuel a turn here and red's city at
	# (0,0) services it, 4 tiles from the heli at (4,0). With 12 fuel
	# (<= 4 + 2 turns x 8) it heads home — (1,0) gains 3 tiles — instead
	# of toward the blue tank at (4,4); with a full tank it goes hunting.
	var gs := BattleFixture.make_state()
	gs.ruleset.unit_types[BattleFixture.HELI].fuel_per_turn = 5
	var air: MovementClass = gs.ruleset.unit_types[BattleFixture.HELI].movement_class
	gs.ruleset.terrain_types[BattleFixture.CITY].repairs_classes.append(air)
	_paint(gs, Vector2i(0, 0), BattleFixture.CITY, 0)
	var heli := BattleFixture.spawn(gs, BattleFixture.HELI, 0, Vector2i(4, 0))
	BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(4, 4))
	heli.fuel = 12
	assert_that(_dest(_choose(gs, 0))).is_equal(Vector2i(1, 0))
	heli.fuel = 99
	assert_that(_dest(_choose(gs, 0))).is_equal(Vector2i(4, 3))
