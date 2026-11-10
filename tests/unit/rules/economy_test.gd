extends GdUnitTestSuite
## Income and build rules on the economy fixture map. Fixture costs:
## infantry 1000, ranger 2000, artillery 6000, tank 7000, heli 9000;
## city and factory income is 1000 each.


func _build(type_id: int, coord: Vector2i) -> BuildAction:
	var a := BuildAction.new()
	a.unit_type_id = type_id
	a.coord = coord
	return a


func test_income_arrives_at_turn_start() -> void:
	var gs := BattleFixture.make_econ_state()
	BattleFixture.claim(gs, Vector2i(2, 0), 1)  # city
	BattleFixture.claim(gs, Vector2i(1, 1), 1)  # factory
	assert_int(Economy.income_for(gs, 1)).is_equal(2000)
	assert_int(Economy.income_for(gs, 0)).is_equal(0)
	var events := Rules.apply(gs, EndTurnAction.new())
	assert_array(events).has_size(3)  # TurnEnded, TurnStarted, FundsChanged
	var funds := events[2] as Events.FundsChanged
	assert_object(funds).is_not_null()
	assert_int(funds.team).is_equal(1)
	assert_int(funds.delta).is_equal(2000)
	assert_int(funds.new_total).is_equal(2000)
	assert_that(funds.reason).is_equal(&"income")
	assert_int(gs.players[1].funds).is_equal(2000)


func test_build_validation_matrix() -> void:
	var gs := BattleFixture.make_econ_state()
	BattleFixture.claim(gs, Vector2i(1, 1), 0)
	BattleFixture.claim(gs, Vector2i(3, 1), 1)
	BattleFixture.claim(gs, Vector2i(2, 0), 0)
	gs.players[0].funds = 1000
	var codes: Dictionary[StringName, StringName] = {}
	codes[&"unknown"] = Rules.validate(gs, _build(99, Vector2i(1, 1))).code
	codes[&"unowned"] = Rules.validate(gs, _build(0, Vector2i(0, 0))).code
	codes[&"enemy"] = Rules.validate(gs, _build(0, Vector2i(3, 1))).code
	codes[&"city"] = Rules.validate(gs, _build(0, Vector2i(2, 0))).code
	assert_that(codes[&"unknown"]).is_equal(ActionError.UNKNOWN_UNIT_TYPE)
	assert_that(codes[&"unowned"]).is_equal(ActionError.NOT_YOUR_PROPERTY)
	assert_that(codes[&"enemy"]).is_equal(ActionError.NOT_YOUR_PROPERTY)
	assert_that(codes[&"city"]).is_equal(ActionError.CANNOT_BUILD_TYPE)
	# Occupied pad.
	var blocker := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(1, 1))
	var occupied := Rules.validate(gs, _build(0, Vector2i(1, 1))).code
	assert_that(occupied).is_equal(ActionError.DESTINATION_OCCUPIED)
	gs.units.erase(blocker.id)
	gs.occupancy.erase(Vector2i(1, 1))
	# Too expensive.
	var poor := Rules.validate(gs, _build(BattleFixture.TANK, Vector2i(1, 1))).code
	assert_that(poor).is_equal(ActionError.INSUFFICIENT_FUNDS)
	# Headcount cap.
	gs.ruleset.max_units_per_player = 1
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(4, 2))
	var capped := Rules.validate(gs, _build(0, Vector2i(1, 1))).code
	assert_that(capped).is_equal(ActionError.UNIT_LIMIT_REACHED)
	gs.ruleset.max_units_per_player = 50
	# And the happy path.
	assert_object(Rules.validate(gs, _build(0, Vector2i(1, 1)))).is_null()


func test_build_apply_pays_and_creates_exhausted() -> void:
	var gs := BattleFixture.make_econ_state()
	BattleFixture.claim(gs, Vector2i(1, 1), 0)
	gs.players[0].funds = 8000
	var events := Rules.apply(gs, _build(BattleFixture.TANK, Vector2i(1, 1)))
	assert_array(events).has_size(2)
	var created := events[0] as Events.UnitCreated
	assert_object(created).is_not_null()
	assert_int(created.type_id).is_equal(BattleFixture.TANK)
	assert_that(created.coord).is_equal(Vector2i(1, 1))
	var funds := events[1] as Events.FundsChanged
	assert_int(funds.delta).is_equal(-7000)
	assert_int(funds.new_total).is_equal(1000)
	assert_that(funds.reason).is_equal(&"build")
	var unit := gs.unit_at(Vector2i(1, 1))
	assert_object(unit).is_not_null()
	assert_bool(unit.has_acted).is_true()
	assert_int(unit.fuel).is_equal(70)
	assert_int(unit.ammo).is_equal(3)
	assert_int(gs.players[0].funds).is_equal(1000)


func test_buildable_units_lists_affordable_roster() -> void:
	var gs := BattleFixture.make_econ_state()
	BattleFixture.claim(gs, Vector2i(1, 1), 0)
	gs.players[0].funds = 2500
	var options := Economy.buildable_units(gs, Vector2i(1, 1))
	var expected: Array[int] = [BattleFixture.INFANTRY, BattleFixture.RANGER]
	assert_array(options).contains_exactly(expected)
	assert_array(Economy.buildable_units(gs, Vector2i(3, 1))).is_empty()  # unowned


func test_generator_emits_builds_and_they_validate() -> void:
	var gs := BattleFixture.make_econ_state()
	BattleFixture.claim(gs, Vector2i(1, 1), 0)
	gs.players[0].funds = 2500
	var build_actions := ActionGenerator.builds(gs)
	assert_array(build_actions).has_size(2)
	for a: Action in build_actions:
		assert_object(Rules.validate(gs, a)).is_null()
	var all := ActionGenerator.generate(gs)
	assert_object(all[all.size() - 1] as EndTurnAction).is_not_null()
	assert_int(all.size()).is_equal(3)  # two builds + end turn, no units


func test_income_percent_scales_what_properties_pay() -> void:
	# Blue owns the city and a factory: 2000 a turn at the plain 100%.
	#   150% (the Hard handicap): 3000.
	#   67% (Easy): 2000 x 67 / 100 = 1340.
	# A lone 1000 property at 67% pays 670; red, at 100%, is untouched.
	var gs := BattleFixture.make_econ_state()
	BattleFixture.claim(gs, Vector2i(2, 0), 1)
	BattleFixture.claim(gs, Vector2i(1, 1), 1)
	BattleFixture.claim(gs, Vector2i(3, 1), 0)
	assert_int(gs.players[1].income_percent).is_equal(100)
	gs.players[1].income_percent = 150
	assert_int(Economy.income_for(gs, 1)).is_equal(3000)
	assert_int(Economy.income_for(gs, 0)).is_equal(1000)
	gs.players[1].income_percent = 67
	assert_int(Economy.income_for(gs, 1)).is_equal(1340)
	BattleFixture.claim(gs, Vector2i(1, 1), MapState.NO_OWNER)
	assert_int(Economy.income_for(gs, 1)).is_equal(670)
	# The scaled amount is what lands at turn start, and a clone keeps
	# the handicap.
	var events := Rules.apply(gs, EndTurnAction.new())
	var paid := events[2] as Events.FundsChanged
	assert_int(paid.delta).is_equal(670)
	assert_int(gs.players[1].funds).is_equal(670)
	assert_int(gs.clone().players[1].income_percent).is_equal(67)
