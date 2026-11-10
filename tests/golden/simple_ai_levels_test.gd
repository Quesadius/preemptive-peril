extends GdUnitTestSuite
## The shipped difficulty levels: what each one is, and that Easy really
## plays without the habits it is described as lacking. Each Easy case
## reruns a scenario from the HQ and tempo suites, where the default
## (Normal) profile is pinned to the opposite choice.


func _paint(gs: GameState, coord: Vector2i, terrain: int, owner_team: int) -> void:
	gs.map.terrain[gs.map.idx(coord)] = terrain
	BattleFixture.claim(gs, coord, owner_team)


func _choose(gs: GameState, level: StringName) -> Action:
	var ai := SimpleAI.new(AIProfileCatalog.find(level))
	return ai.choose_action(StateView.for_team(gs, 0))


func _dest(action: Action) -> Vector2i:
	var ua := action as UnitAction
	return ua.path[ua.path.size() - 1]


func test_three_levels_easiest_first() -> void:
	var levels := AIProfileCatalog.all()
	var keys: Array[StringName] = []
	for level: AIProfile in levels:
		keys.append(level.key)
	assert_array(keys).contains_exactly([&"easy", &"normal", &"hard"])
	var easy := levels[0]
	assert_that(easy.display_name).is_equal("Easy")
	assert_int(easy.income_percent).is_equal(67)
	assert_bool(easy.defends_hq or easy.counter_builds or easy.presses).is_false()
	assert_int(easy.min_capturers).is_equal(1)
	# Normal is the profile's own defaults, so code that asks for no
	# particular level plays Normal.
	var normal := levels[1]
	var defaults := AIProfile.new()
	assert_int(normal.income_percent).is_equal(100)
	assert_bool(normal.defends_hq and normal.counter_builds and normal.presses).is_true()
	assert_int(normal.min_capturers).is_equal(defaults.min_capturers)
	assert_that(defaults.key).is_equal(&"normal")
	# Hard plays exactly like Normal and collects half again as much.
	var hard := levels[2]
	assert_int(hard.income_percent).is_equal(150)
	assert_bool(hard.defends_hq and hard.counter_builds and hard.presses).is_true()
	for level: AIProfile in levels:
		assert_bool(level.description.is_empty()).is_false()
	# A level this build doesn't have falls back to Normal.
	assert_that(AIProfileCatalog.find(&"nightmare").key).is_equal(&"normal")


func test_easy_leaves_the_raider_on_its_hq_alone() -> void:
	# Normal MGs the infantry capturing its HQ (4830); Easy sees only a
	# 30-point poke there and takes the 2800 kill on the 1-HP tank.
	var gs := BattleFixture.make_state()
	_paint(gs, Vector2i(0, 2), BattleFixture.HQ, 0)
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(0, 2))
	BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(1, 2))
	BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(2, 2)).hp = 10
	assert_that((_choose(gs, &"normal") as UnitAction).target_coord).is_equal(Vector2i(0, 2))
	assert_that((_choose(gs, &"easy") as UnitAction).target_coord).is_equal(Vector2i(2, 2))


func test_easy_does_not_build_counters_or_a_second_capturer() -> void:
	# The heli only artillery can hit (shells 60, added here): Normal
	# buys the artillery, Easy the priciest fighter on offer, the tank.
	var gs := BattleFixture.make_econ_state()
	var shells := gs.ruleset.unit_types[BattleFixture.ARTILLERY].primary_weapon
	shells.damage_table.base_damage[&"heli"] = 60
	BattleFixture.claim(gs, Vector2i(1, 1), 0)
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0)).has_acted = true
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 1)).has_acted = true
	BattleFixture.spawn(gs, BattleFixture.HELI, 1, Vector2i(4, 2))
	gs.players[0].funds = 16000
	assert_int((_choose(gs, &"normal") as BuildAction).unit_type_id).is_equal(
		BattleFixture.ARTILLERY
	)
	assert_int((_choose(gs, &"easy") as BuildAction).unit_type_id).is_equal(BattleFixture.TANK)
	# With a single capturer, Normal wants its second; Easy is content.
	var lone := BattleFixture.make_econ_state()
	BattleFixture.claim(lone, Vector2i(1, 1), 0)
	BattleFixture.spawn(lone, BattleFixture.INFANTRY, 0, Vector2i(0, 0)).has_acted = true
	lone.players[0].funds = 16000
	assert_int((_choose(lone, &"normal") as BuildAction).unit_type_id).is_equal(
		BattleFixture.INFANTRY
	)
	assert_int((_choose(lone, &"easy") as BuildAction).unit_type_id).is_equal(BattleFixture.TANK)


func test_easy_waits_out_of_range_where_normal_presses() -> void:
	# Tank against tank at even strength: Normal steps into range at
	# (2,2); Easy stops at (1,1), the nearest tile blue's cannon can't
	# reach.
	var gs := BattleFixture.make_state()
	BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(0, 0))
	BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(4, 4))
	assert_that(_dest(_choose(gs, &"normal"))).is_equal(Vector2i(2, 2))
	assert_that(_dest(_choose(gs, &"easy"))).is_equal(Vector2i(1, 1))
