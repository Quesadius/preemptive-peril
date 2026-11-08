extends GdUnitTestSuite
## The remaining verbs (LOAD/UNLOAD/SUPPLY/JOIN) and the start-of-turn
## supply sequence: repair (after income), resupply, fuel drain, crash.
## Values hand-computed on BattleFixture (luck 0): repair heals 20 at
## cost*20/100; join refunds surplus display HP at cost/10 per point.


func _act(unit_id: int, path: Array[Vector2i], verb: int) -> UnitAction:
	var a := UnitAction.new()
	a.unit_id = unit_id
	a.path = path
	a.verb = verb
	return a


func test_load_validate_matrix() -> void:
	var gs := BattleFixture.make_econ_state()
	var apc := BattleFixture.spawn(gs, BattleFixture.APC, 0, Vector2i(2, 2))
	var tank := BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(1, 2))
	var inf := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(3, 2))
	var enemy_apc := BattleFixture.spawn(gs, BattleFixture.APC, 1, Vector2i(4, 2))
	# Treads don't fit in the fixture APC (foot only).
	var tank_in := _act(tank.id, [Vector2i(1, 2), Vector2i(2, 2)], UnitAction.Verb.LOAD)
	assert_that(Rules.validate(gs, tank_in).code).is_equal(ActionError.CANNOT_LOAD)
	# An enemy carrier is no carrier of yours: its tile blocks pathing
	# entirely, so the order dies as an illegal path.
	var wrong_side := _act(inf.id, [Vector2i(3, 2), Vector2i(4, 2)], UnitAction.Verb.LOAD)
	assert_that(Rules.validate(gs, wrong_side).code).is_equal(ActionError.ILLEGAL_PATH)
	assert_object(enemy_apc).is_not_null()
	# Legal boarding.
	var board := _act(inf.id, [Vector2i(3, 2), Vector2i(2, 2)], UnitAction.Verb.LOAD)
	assert_object(Rules.validate(gs, board)).is_null()
	# A full carrier refuses.
	apc.cargo.append(999)
	assert_that(Rules.validate(gs, board).code).is_equal(ActionError.CANNOT_LOAD)


func test_load_apply_boards_and_vacates() -> void:
	var gs := BattleFixture.make_econ_state()
	var apc := BattleFixture.spawn(gs, BattleFixture.APC, 0, Vector2i(2, 2))
	var inf := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 2))
	var board := _act(
		inf.id, [Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2)], UnitAction.Verb.LOAD
	)
	assert_object(Rules.validate(gs, board)).is_null()
	var events := Rules.apply(gs, board)
	assert_array(events).has_size(3)
	assert_object(events[0] as Events.UnitMoved).is_not_null()
	var loaded := events[1] as Events.UnitLoaded
	assert_object(loaded).is_not_null()
	assert_int(loaded.carrier_id).is_equal(apc.id)
	assert_int(inf.carrier_id).is_equal(apc.id)
	assert_array(apc.cargo).contains_exactly([inf.id])
	assert_that(inf.coord).is_equal(Vector2i(2, 2))
	assert_int(gs.occupancy[Vector2i(2, 2)]).is_equal(apc.id)  # carrier owns the tile
	assert_bool(gs.occupancy.has(Vector2i(0, 2))).is_false()
	assert_bool(inf.has_acted).is_true()
	assert_int(inf.fuel).is_equal(97)  # two tiles walked to board


func test_unload_validate_matrix() -> void:
	var gs := BattleFixture.make_state()  # main map: sea at (3,2)
	var apc := BattleFixture.spawn(gs, BattleFixture.APC, 0, Vector2i(2, 2))
	var rider := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(2, 3))
	var here: Array[Vector2i] = [Vector2i(2, 2)]
	var empty := _act(apc.id, here, UnitAction.Verb.UNLOAD)
	empty.cargo_index = 0
	empty.target_coord = Vector2i(2, 1)
	assert_that(Rules.validate(gs, empty).code).is_equal(ActionError.NO_CARGO)
	# Board the rider for the rest.
	Rules.apply(gs, _act(rider.id, [Vector2i(2, 3), Vector2i(2, 2)], UnitAction.Verb.LOAD))
	Rules.apply(gs, EndTurnAction.new())
	Rules.apply(gs, EndTurnAction.new())  # back to team 0, un-exhausted
	var far := _act(apc.id, here, UnitAction.Verb.UNLOAD)
	far.cargo_index = 0
	far.target_coord = Vector2i(4, 2)
	assert_that(Rules.validate(gs, far).code).is_equal(ActionError.BAD_UNLOAD_TARGET)
	var sea := _act(apc.id, here, UnitAction.Verb.UNLOAD)
	sea.cargo_index = 0
	sea.target_coord = Vector2i(3, 2)  # foot can't stand on sea
	assert_that(Rules.validate(gs, sea).code).is_equal(ActionError.BAD_UNLOAD_TARGET)
	var fine := _act(apc.id, here, UnitAction.Verb.UNLOAD)
	fine.cargo_index = 0
	fine.target_coord = Vector2i(2, 1)
	assert_object(Rules.validate(gs, fine)).is_null()


func test_unload_apply_move_then_drop() -> void:
	var gs := BattleFixture.make_econ_state()
	var apc := BattleFixture.spawn(gs, BattleFixture.APC, 0, Vector2i(2, 2))
	var rider := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(1, 2))
	Rules.apply(gs, _act(rider.id, [Vector2i(1, 2), Vector2i(2, 2)], UnitAction.Verb.LOAD))
	Rules.apply(gs, EndTurnAction.new())
	Rules.apply(gs, EndTurnAction.new())
	var drop := _act(apc.id, [Vector2i(2, 2), Vector2i(3, 2)], UnitAction.Verb.UNLOAD)
	drop.cargo_index = 0
	drop.target_coord = Vector2i(3, 1)
	assert_object(Rules.validate(gs, drop)).is_null()
	var events := Rules.apply(gs, drop)
	assert_array(events).has_size(3)
	var out := events[1] as Events.UnitUnloaded
	assert_object(out).is_not_null()
	assert_int(out.unit_id).is_equal(rider.id)
	assert_that(out.coord).is_equal(Vector2i(3, 1))
	assert_that(rider.coord).is_equal(Vector2i(3, 1))
	assert_int(rider.carrier_id).is_equal(-1)
	assert_bool(rider.has_acted).is_true()  # disembarking spends the unit
	assert_array(apc.cargo).is_empty()
	assert_int(gs.occupancy[Vector2i(3, 1)]).is_equal(rider.id)
	assert_int(gs.occupancy[Vector2i(3, 2)]).is_equal(apc.id)


func test_unload_onto_vacated_origin_is_legal() -> void:
	var gs := BattleFixture.make_econ_state()
	var apc := BattleFixture.spawn(gs, BattleFixture.APC, 0, Vector2i(1, 0))
	var rider := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	Rules.apply(gs, _act(rider.id, [Vector2i(0, 0), Vector2i(1, 0)], UnitAction.Verb.LOAD))
	Rules.apply(gs, EndTurnAction.new())
	Rules.apply(gs, EndTurnAction.new())
	var drop := _act(apc.id, [Vector2i(1, 0), Vector2i(2, 0)], UnitAction.Verb.UNLOAD)
	drop.cargo_index = 0
	drop.target_coord = Vector2i(1, 0)  # the tile the APC is vacating
	assert_object(Rules.validate(gs, drop)).is_null()
	Rules.apply(gs, drop)
	assert_that(rider.coord).is_equal(Vector2i(1, 0))


func test_unload_trap_under_fog() -> void:
	var gs := BattleFixture.make_econ_state()
	gs.config.fog_enabled = true
	var apc := BattleFixture.spawn(gs, BattleFixture.APC, 0, Vector2i(0, 1))
	var rider := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	Rules.apply(gs, _act(rider.id, [Vector2i(0, 0), Vector2i(0, 1)], UnitAction.Verb.LOAD))
	Rules.apply(gs, EndTurnAction.new())
	var lurker := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(3, 1))
	Rules.apply(gs, EndTurnAction.new())
	# From (0,1) the enemy at (3,1) is beyond vision 2: the drop looks
	# clear at order time.
	var drop := _act(
		apc.id, [Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)], UnitAction.Verb.UNLOAD
	)
	drop.cargo_index = 0
	drop.target_coord = Vector2i(3, 1)
	assert_object(Rules.validate(gs, drop)).is_null()
	var events := Rules.apply(gs, drop)
	assert_array(events).has_size(3)
	var trap := events[1] as Events.UnitAmbushed
	assert_object(trap).is_not_null()
	assert_int(trap.by_unit_id).is_equal(lurker.id)
	assert_int(rider.carrier_id).is_equal(apc.id)  # still aboard
	assert_array(apc.cargo).contains_exactly([rider.id])
	assert_bool(apc.has_acted).is_true()


func test_join_validate_matrix() -> void:
	var gs := BattleFixture.make_econ_state()
	var mover := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	var tank := BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(1, 0))
	var twin := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 1))
	var enemy_twin := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(1, 1))
	var onto_tank := _act(mover.id, [Vector2i(0, 0), Vector2i(1, 0)], UnitAction.Verb.JOIN)
	assert_that(Rules.validate(gs, onto_tank).code).is_equal(ActionError.CANNOT_JOIN)
	var onto_enemy := _act(
		mover.id, [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)], UnitAction.Verb.JOIN
	)
	assert_object(enemy_twin).is_not_null()
	assert_bool(Rules.validate(gs, onto_enemy) != null).is_true()
	var onto_full := _act(mover.id, [Vector2i(0, 0), Vector2i(0, 1)], UnitAction.Verb.JOIN)
	assert_that(Rules.validate(gs, onto_full).code).is_equal(ActionError.JOIN_TARGET_FULL)
	twin.hp = 60
	assert_object(Rules.validate(gs, onto_full)).is_null()


func test_join_apply_pools_and_refunds() -> void:
	var gs := BattleFixture.make_econ_state()
	var mover := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	mover.hp = 60
	var twin := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 1))
	twin.hp = 60
	var merge := _act(mover.id, [Vector2i(0, 0), Vector2i(0, 1)], UnitAction.Verb.JOIN)
	assert_object(Rules.validate(gs, merge)).is_null()
	var events := Rules.apply(gs, merge)
	# UnitMoved + UnitJoined; the mover no longer exists to exhaust.
	assert_array(events).has_size(2)
	var joined := events[1] as Events.UnitJoined
	assert_object(joined).is_not_null()
	assert_int(joined.survivor_id).is_equal(twin.id)
	assert_int(joined.absorbed_id).is_equal(mover.id)
	assert_int(joined.new_hp).is_equal(100)
	assert_int(joined.funds_refund).is_equal(200)  # surplus 2 * 1000/10
	assert_int(twin.hp).is_equal(100)
	assert_bool(twin.has_acted).is_true()
	assert_bool(gs.units.has(mover.id)).is_false()
	assert_int(gs.players[0].funds).is_equal(200)
	assert_int(gs.occupancy[Vector2i(0, 1)]).is_equal(twin.id)
	assert_bool(gs.occupancy.has(Vector2i(0, 0))).is_false()


func test_supply_verb_refills_adjacent_allies() -> void:
	var gs := BattleFixture.make_econ_state()
	var apc := BattleFixture.spawn(gs, BattleFixture.APC, 0, Vector2i(2, 2))
	var thirsty := BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(1, 2))
	thirsty.fuel = 3
	thirsty.ammo = 0
	var full := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(3, 2))
	var enemy := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(2, 1))
	enemy.fuel = 1
	var tank_cannot := _act(thirsty.id, [Vector2i(1, 2)], UnitAction.Verb.SUPPLY)
	assert_that(Rules.validate(gs, tank_cannot).code).is_equal(ActionError.CANNOT_SUPPLY)
	var pump := _act(apc.id, [Vector2i(2, 2)], UnitAction.Verb.SUPPLY)
	assert_object(Rules.validate(gs, pump)).is_null()
	var events := Rules.apply(gs, pump)
	# One resupply (the thirsty tank) + exhaustion; full ally and the
	# enemy are untouched.
	assert_array(events).has_size(2)
	var refill := events[0] as Events.UnitResupplied
	assert_object(refill).is_not_null()
	assert_int(refill.unit_id).is_equal(thirsty.id)
	assert_int(thirsty.fuel).is_equal(70)
	assert_int(thirsty.ammo).is_equal(3)
	assert_int(full.fuel).is_equal(99)
	assert_int(enemy.fuel).is_equal(1)


func test_turn_flow_repairs_after_income_then_resupplies() -> void:
	var gs := BattleFixture.make_econ_state()
	BattleFixture.claim(gs, Vector2i(2, 0), 1)  # city, income 1000
	var tank := BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(2, 0))
	tank.hp = 55
	tank.fuel = 3
	gs.players[1].funds = 500  # repair costs 1400: only affordable AFTER income
	var events := Rules.apply(gs, EndTurnAction.new())
	var income_at: int = -1
	var repair_at: int = -1
	var resupply_at: int = -1
	for i: int in range(events.size()):
		if events[i] is Events.FundsChanged:
			income_at = i
		elif events[i] is Events.UnitRepaired:
			repair_at = i
		elif events[i] is Events.UnitResupplied:
			resupply_at = i
	assert_bool(income_at >= 0 and repair_at >= 0 and resupply_at >= 0).is_true()
	assert_bool(income_at < repair_at).is_true()  # §6: income before repair
	assert_int(tank.hp).is_equal(75)
	assert_int(tank.fuel).is_equal(70)
	assert_int(gs.players[1].funds).is_equal(100)  # 500 + 1000 - 1400


func test_repair_skipped_when_broke_but_resupply_is_free() -> void:
	var gs := BattleFixture.make_econ_state()
	BattleFixture.claim(gs, Vector2i(2, 0), 1)
	var tank := BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(2, 0))
	tank.hp = 55
	tank.fuel = 3
	gs.players[1].funds = 0  # income 1000 < 1400 repair cost
	var events := Rules.apply(gs, EndTurnAction.new())
	for e: GameEvent in events:
		assert_bool(e is Events.UnitRepaired).is_false()
	assert_int(tank.hp).is_equal(55)
	assert_int(tank.fuel).is_equal(70)  # resupply doesn't care about funds
	assert_int(gs.players[1].funds).is_equal(1000)


func test_fuel_drain_and_crash_at_turn_start() -> void:
	var gs := BattleFixture.make_state()
	gs.ruleset.unit_types[BattleFixture.HELI].fuel_per_turn = 2
	gs.ruleset.unit_types[BattleFixture.HELI].crashes_without_fuel = true
	var cruising := BattleFixture.spawn(gs, BattleFixture.HELI, 1, Vector2i(0, 0))
	cruising.fuel = 5
	var fumes := BattleFixture.spawn(gs, BattleFixture.HELI, 1, Vector2i(4, 4))
	fumes.fuel = 1
	var events := Rules.apply(gs, EndTurnAction.new())
	var drained: int = 0
	var crashed := false
	for e: GameEvent in events:
		if e is Events.UnitFuelDrained:
			drained += 1
		elif e is Events.UnitDestroyed:
			crashed = crashed or (e as Events.UnitDestroyed).unit_id == fumes.id
	assert_int(drained).is_equal(2)
	assert_bool(crashed).is_true()
	assert_int(cruising.fuel).is_equal(3)
	assert_bool(gs.units.has(fumes.id)).is_false()
