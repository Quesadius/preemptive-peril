extends GdUnitTestSuite
## Rules.validate() reason codes and Rules.apply() state transitions.


func _wait(unit_id: int, path: Array[Vector2i]) -> UnitAction:
	var a := UnitAction.new()
	a.unit_id = unit_id
	a.path = path
	a.verb = UnitAction.Verb.WAIT
	return a


func _attack(unit_id: int, path: Array[Vector2i], target: Vector2i) -> UnitAction:
	var a := UnitAction.new()
	a.unit_id = unit_id
	a.path = path
	a.verb = UnitAction.Verb.ATTACK
	a.target_coord = target
	return a


func _code(gs: GameState, action: Action) -> StringName:
	var err := Rules.validate(gs, action)
	return err.code if err != null else &""


func test_validate_basic_errors() -> void:
	var gs := BattleFixture.make_state()
	var inf := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	var ally := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 1))
	var enemy := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(4, 4))
	var here: Array[Vector2i] = [Vector2i(0, 0)]
	assert_that(_code(gs, Action.new())).is_equal(ActionError.UNKNOWN_ACTION)
	assert_that(_code(gs, _wait(999, here))).is_equal(ActionError.UNKNOWN_UNIT)
	assert_that(_code(gs, _wait(enemy.id, [Vector2i(4, 4)]))).is_equal(ActionError.NOT_YOUR_TURN)
	var future_verb := _wait(inf.id, here)
	future_verb.verb = UnitAction.Verb.LAUNCH  # silos arrive in a later milestone
	assert_that(_code(gs, future_verb)).is_equal(ActionError.VERB_NOT_IMPLEMENTED)
	assert_that(_code(gs, _wait(inf.id, [Vector2i(1, 0)]))).is_equal(ActionError.ILLEGAL_PATH)
	var onto_ally: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1)]
	assert_that(_code(gs, _wait(inf.id, onto_ally))).is_equal(ActionError.DESTINATION_OCCUPIED)
	inf.has_acted = true
	assert_that(_code(gs, _wait(inf.id, here))).is_equal(ActionError.UNIT_EXHAUSTED)
	assert_bool(ally.has_acted).is_false()  # untouched by all the probing


func test_validate_attack_errors() -> void:
	var gs := BattleFixture.make_state()
	var tank := BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(1, 2))
	var arty := BattleFixture.spawn(gs, BattleFixture.ARTILLERY, 0, Vector2i(0, 2))
	var heli := BattleFixture.spawn(gs, BattleFixture.HELI, 0, Vector2i(2, 3))
	BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(2, 2))
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(0, 1))
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(4, 0))
	var tank_here: Array[Vector2i] = [Vector2i(1, 2)]
	var arty_here: Array[Vector2i] = [Vector2i(0, 2)]
	# Indirects cannot move and fire.
	var arty_move: Array[Vector2i] = [Vector2i(0, 2), Vector2i(0, 3)]
	var moving_shot := _attack(arty.id, arty_move, Vector2i(2, 2))
	assert_that(_code(gs, moving_shot)).is_equal(ActionError.CANNOT_MOVE_AND_FIRE)
	# Empty tile and friendly tile are not targets.
	assert_that(_code(gs, _attack(tank.id, tank_here, Vector2i(1, 3)))).is_equal(
		ActionError.NO_TARGET
	)
	assert_that(_code(gs, _attack(tank.id, tank_here, Vector2i(0, 2)))).is_equal(
		ActionError.NO_TARGET
	)
	# Range: artillery can't fire point-blank; a tank can't snipe.
	assert_that(_code(gs, _attack(arty.id, arty_here, Vector2i(0, 1)))).is_equal(
		ActionError.TARGET_OUT_OF_RANGE
	)
	assert_that(_code(gs, _attack(tank.id, tank_here, Vector2i(4, 0)))).is_equal(
		ActionError.TARGET_OUT_OF_RANGE
	)
	# No usable weapon: unarmed heli; dry cannon with no mg fallback vs tank.
	var heli_here: Array[Vector2i] = [Vector2i(2, 3)]
	assert_that(_code(gs, _attack(heli.id, heli_here, Vector2i(2, 2)))).is_equal(
		ActionError.CANNOT_ATTACK_TARGET
	)
	tank.ammo = 0
	assert_that(_code(gs, _attack(tank.id, tank_here, Vector2i(2, 2)))).is_equal(
		ActionError.CANNOT_ATTACK_TARGET
	)
	tank.ammo = 3
	# And the legal cases come back null.
	assert_object(Rules.validate(gs, _attack(tank.id, tank_here, Vector2i(2, 2)))).is_null()
	assert_object(Rules.validate(gs, _attack(arty.id, arty_here, Vector2i(2, 2)))).is_null()


func test_apply_wait_moves_and_exhausts() -> void:
	var gs := BattleFixture.make_state()
	var inf := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)]
	var action := _wait(inf.id, path)
	assert_object(Rules.validate(gs, action)).is_null()
	var events := Rules.apply(gs, action)
	assert_array(events).has_size(2)
	var moved := events[0] as Events.UnitMoved
	assert_object(moved).is_not_null()
	assert_int(moved.unit_id).is_equal(inf.id)
	assert_array(moved.path).contains_exactly(path)
	assert_int(moved.interrupted_at).is_equal(-1)
	assert_object(events[1] as Events.UnitExhausted).is_not_null()
	assert_that(inf.coord).is_equal(Vector2i(0, 2))
	assert_object(gs.unit_at(Vector2i(0, 0))).is_null()
	assert_object(gs.unit_at(Vector2i(0, 2))).is_same(inf)
	assert_int(inf.fuel).is_equal(97)  # per-tile: two tiles entered
	assert_bool(inf.has_moved).is_true()
	assert_bool(inf.has_acted).is_true()


func test_apply_wait_in_place() -> void:
	var gs := BattleFixture.make_state()
	var inf := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	var events := Rules.apply(gs, _wait(inf.id, [Vector2i(0, 0)]))
	assert_array(events).has_size(1)
	assert_object(events[0] as Events.UnitExhausted).is_not_null()
	assert_int(inf.fuel).is_equal(99)
	assert_bool(inf.has_moved).is_false()
	assert_bool(inf.has_acted).is_true()


func test_apply_attack_move_and_fire() -> void:
	var gs := BattleFixture.make_state()
	var tank := BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(1, 3))
	var enemy := BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(2, 2))
	var path: Array[Vector2i] = [Vector2i(1, 3), Vector2i(1, 2)]
	var action := _attack(tank.id, path, Vector2i(2, 2))
	assert_object(Rules.validate(gs, action)).is_null()
	var events := Rules.apply(gs, action)
	assert_array(events).has_size(4)
	assert_object(events[0] as Events.UnitMoved).is_not_null()
	assert_int((events[1] as Events.UnitAttacked).damage).is_equal(49)
	assert_int((events[2] as Events.UnitCounterattacked).damage).is_equal(29)
	assert_object(events[3] as Events.UnitExhausted).is_not_null()
	assert_that(tank.coord).is_equal(Vector2i(1, 2))
	assert_int(tank.fuel).is_equal(69)
	assert_int(tank.hp).is_equal(71)
	assert_int(tank.ammo).is_equal(2)
	assert_int(enemy.hp).is_equal(51)
	assert_bool(tank.has_acted).is_true()


func test_apply_attack_attacker_destroyed_by_counter() -> void:
	# Weak infantry pokes a tank: rifle 5 * 0.2 * 0.9 = 0.9 -> 0 damage;
	# the mg counter does 40 * (100 - 2)/100 = 39.2 -> 39 and kills it.
	var gs := BattleFixture.make_state()
	var inf := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(1, 2))
	inf.hp = 20
	var tank := BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(2, 2))
	var action := _attack(inf.id, [Vector2i(1, 2)], Vector2i(2, 2))
	assert_object(Rules.validate(gs, action)).is_null()
	var events := Rules.apply(gs, action)
	# No UnitExhausted for the dead; losing the last unit routs team 0
	# and ends the game, so victory events trail the combat ones.
	assert_array(events).has_size(5)
	assert_int((events[0] as Events.UnitAttacked).damage).is_equal(0)
	assert_int((events[1] as Events.UnitCounterattacked).damage).is_equal(39)
	var death := events[2] as Events.UnitDestroyed
	assert_int(death.unit_id).is_equal(inf.id)
	assert_int((events[3] as Events.PlayerEliminated).team).is_equal(0)
	assert_int((events[4] as Events.GameEnded).winning_team).is_equal(1)
	assert_bool(gs.units.has(inf.id)).is_false()
	assert_object(gs.unit_at(Vector2i(1, 2))).is_null()
	assert_int(tank.hp).is_equal(100)
	assert_int(tank.ammo).is_equal(3)  # mg counter costs nothing


func test_loaded_unit_cannot_act_on_its_own() -> void:
	# A passenger shares the carrier's coord but not its occupancy entry.
	# If validate() let it "move", apply() would erase the CARRIER from
	# occupancy and leave the passenger listed in cargo — so it can only
	# leave through the carrier's UNLOAD.
	var gs := BattleFixture.make_state()
	var apc := BattleFixture.spawn(gs, BattleFixture.APC, 0, Vector2i(2, 2))
	var rider := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(1, 2))
	var board := _wait(rider.id, [Vector2i(1, 2), Vector2i(2, 2)])
	board.verb = UnitAction.Verb.LOAD
	assert_that(_code(gs, board)).is_equal(&"")
	Rules.apply(gs, board)
	Rules.apply(gs, EndTurnAction.new())
	Rules.apply(gs, EndTurnAction.new())  # team 0 again: the rider is fresh
	assert_bool(rider.has_acted).is_false()
	assert_int(rider.carrier_id).is_equal(apc.id)
	var walk_off := _wait(rider.id, [Vector2i(2, 2), Vector2i(2, 1)])
	assert_that(_code(gs, walk_off)).is_equal(ActionError.UNIT_IN_TRANSPORT)
	assert_that(_code(gs, _wait(rider.id, [Vector2i(2, 2)]))).is_equal(
		ActionError.UNIT_IN_TRANSPORT
	)
	assert_array(ActionGenerator.for_unit(gs, rider.id)).is_empty()
	assert_object(gs.unit_at(Vector2i(2, 2))).is_same(apc)


func test_attack_on_unseen_unit_is_no_target() -> void:
	# Artillery on the road at (0,4), vision 2; infantry at (0,1) is in
	# range (distance 3) but dark. validate() must not confirm that
	# anyone is there — it agrees with the generator, which never offers
	# the shot.
	var gs := BattleFixture.make_state()
	gs.config.fog_enabled = true
	var arty := BattleFixture.spawn(gs, BattleFixture.ARTILLERY, 0, Vector2i(0, 4))
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(0, 1))
	var shot := _attack(arty.id, [Vector2i(0, 4)], Vector2i(0, 1))
	assert_that(_code(gs, shot)).is_equal(ActionError.NO_TARGET)
	for a: Action in ActionGenerator.for_unit(gs, arty.id):
		assert_int((a as UnitAction).verb).is_not_equal(UnitAction.Verb.ATTACK)
	gs.config.fog_enabled = false  # in plain sight, the same shot is legal
	assert_that(_code(gs, shot)).is_equal(&"")
