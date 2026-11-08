extends GdUnitTestSuite
## Combat tests on BattleFixture. All damage values hand-computed from
## damage = floor(base * a_dhp/10 * (100 - stars * d_dhp)/100), luck 0.


func test_preview_tank_duel_on_plains() -> void:
	# 55 * 1.0 * (100 - 1*10)/100 = 49.5 -> 49; counter at 51 hp (dhp 6):
	# 55 * 0.6 * 0.9 = 29.7 -> 29.
	var gs := BattleFixture.make_state()
	var a := BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(1, 2))
	var d := BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(2, 2))
	var p := Combat.preview(gs, a.id, d.id)
	assert_bool(p.has_ammo).is_true()
	assert_int(p.damage).is_equal(49)
	assert_float(p.damage_display).is_equal_approx(4.9, 0.001)
	assert_bool(p.can_counter).is_true()
	assert_int(p.counter_damage).is_equal(29)


func test_preview_terrain_cover() -> void:
	# Defender on forest (2 stars): 55 * (100 - 20)/100 = 44.
	var gs := BattleFixture.make_state()
	var a := BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(1, 2))
	var d := BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(1, 1))
	var p := Combat.preview(gs, a.id, d.id)
	assert_int(p.damage).is_equal(44)
	# Counter from 56 hp (dhp 6) against attacker on plains: 29.
	assert_int(p.counter_damage).is_equal(29)


func test_preview_scales_with_attacker_hp() -> void:
	# Attacker at 55 hp (dhp 6): 55 * 0.6 * 0.9 = 29.7 -> 29.
	var gs := BattleFixture.make_state()
	var a := BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(1, 2))
	a.hp = 55
	var d := BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(2, 2))
	assert_int(Combat.preview(gs, a.id, d.id).damage).is_equal(29)


func test_preview_no_usable_weapon() -> void:
	var gs := BattleFixture.make_state()
	var heli := BattleFixture.spawn(gs, BattleFixture.HELI, 0, Vector2i(2, 3))
	var tank := BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(2, 2))
	# The heli is unarmed…
	var p := Combat.preview(gs, heli.id, tank.id)
	assert_bool(p.has_ammo).is_false()
	assert_int(p.damage).is_equal(0)
	assert_bool(p.can_counter).is_false()
	# …and nothing in the fixture can target a heli.
	var inf := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(1, 3))
	assert_bool(Combat.preview(gs, inf.id, heli.id).has_ammo).is_false()


func test_preview_indirect_cannot_be_countered() -> void:
	# Artillery at range 2: 70 * 0.9 = 63, and no counter at range > 1.
	var gs := BattleFixture.make_state()
	var arty := BattleFixture.spawn(gs, BattleFixture.ARTILLERY, 0, Vector2i(0, 2))
	var tank := BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(2, 2))
	var p := Combat.preview(gs, arty.id, tank.id)
	assert_int(p.damage).is_equal(63)
	assert_bool(p.can_counter).is_false()


func test_preview_does_not_advance_rng() -> void:
	var gs := BattleFixture.make_state()
	var a := BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(1, 2))
	var d := BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(2, 2))
	var before: int = gs.rng.clone().roll_range(0, 1000000)
	Combat.preview(gs, a.id, d.id)
	var after: int = gs.rng.clone().roll_range(0, 1000000)
	assert_int(after).is_equal(before)


func test_resolve_exchange_luckless() -> void:
	var gs := BattleFixture.make_state()
	var a := BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(1, 2))
	var d := BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(2, 2))
	var events := Combat.resolve(gs, a.id, d.id)
	assert_array(events).has_size(2)
	var atk := events[0] as Events.UnitAttacked
	assert_object(atk).is_not_null()
	assert_int(atk.attacker_id).is_equal(a.id)
	assert_int(atk.defender_id).is_equal(d.id)
	assert_int(atk.damage).is_equal(49)
	assert_int(atk.ammo_used).is_equal(1)
	var counter := events[1] as Events.UnitCounterattacked
	assert_object(counter).is_not_null()
	assert_int(counter.attacker_id).is_equal(d.id)
	assert_int(counter.defender_id).is_equal(a.id)
	assert_int(counter.damage).is_equal(29)
	assert_int(d.hp).is_equal(51)
	assert_int(a.hp).is_equal(71)
	assert_int(a.ammo).is_equal(2)  # cannon fired
	assert_int(d.ammo).is_equal(2)  # counter also used the cannon


func test_resolve_kill_removes_unit_and_skips_counter() -> void:
	# mg vs infantry at 30 hp (dhp 3): 40 * (100 - 3)/100 = 38.8 -> 38.
	var gs := BattleFixture.make_state()
	var a := BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(1, 2))
	var d := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(2, 2))
	d.hp = 30
	var events := Combat.resolve(gs, a.id, d.id)
	assert_array(events).has_size(2)
	var atk := events[0] as Events.UnitAttacked
	assert_int(atk.damage).is_equal(38)
	assert_int(atk.ammo_used).is_equal(0)  # mg needs no ammo
	var death := events[1] as Events.UnitDestroyed
	assert_object(death).is_not_null()
	assert_int(death.unit_id).is_equal(d.id)
	assert_that(death.coord).is_equal(Vector2i(2, 2))
	assert_bool(gs.units.has(d.id)).is_false()
	assert_object(gs.unit_at(Vector2i(2, 2))).is_null()
	assert_int(a.hp).is_equal(100)
	assert_int(a.ammo).is_equal(3)


func test_resolve_indirect_attack_draws_no_counter() -> void:
	var gs := BattleFixture.make_state()
	var arty := BattleFixture.spawn(gs, BattleFixture.ARTILLERY, 0, Vector2i(0, 2))
	var tank := BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(2, 2))
	var events := Combat.resolve(gs, arty.id, tank.id)
	assert_array(events).has_size(1)
	assert_int(tank.hp).is_equal(37)  # 100 - 63
	assert_int(arty.hp).is_equal(100)
	assert_int(arty.ammo).is_equal(1)


func test_resolve_luck_adds_damage_deterministically() -> void:
	var first := BattleFixture.make_state()
	var second := BattleFixture.make_state()
	var damages: Array[int] = []
	for gs: GameState in [first, second]:
		gs.ruleset.luck_max = 9
		var a := BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(1, 2))
		var d := BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(2, 2))
		var events := Combat.resolve(gs, a.id, d.id)
		damages.append((events[0] as Events.UnitAttacked).damage)
	assert_int(damages[0]).is_between(49, 58)
	assert_int(damages[0]).is_equal(damages[1])  # same seed, same luck


func test_secondary_fallback_when_out_of_ammo() -> void:
	var gs := BattleFixture.make_state()
	var a := BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(1, 2))
	a.ammo = 0
	var inf := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(1, 1))
	var tank := BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(2, 2))
	# vs infantry the mg still works (no ammo cost): on forest (2 stars):
	# 40 * (100 - 20)/100 = 32.
	var p := Combat.preview(gs, a.id, inf.id)
	assert_bool(p.has_ammo).is_true()
	assert_int(p.damage).is_equal(32)
	# vs a tank the dry cannon has no fallback — mg can't scratch it.
	assert_bool(Combat.preview(gs, a.id, tank.id).has_ammo).is_false()


func test_attackable_tiles() -> void:
	var gs := BattleFixture.make_state()
	var arty := BattleFixture.spawn(gs, BattleFixture.ARTILLERY, 0, Vector2i(0, 2))
	# Ring 2..3 around (0,2), clipped to the 5x5 map: 10 tiles.
	var from_home := Combat.attackable_tiles(gs, arty.id, Vector2i(0, 2))
	assert_array(from_home).has_size(10)
	assert_array(from_home).contains([Vector2i(2, 2), Vector2i(0, 0), Vector2i(3, 2)])
	assert_bool(from_home.has(Vector2i(1, 2))).is_false()  # range 1 excluded
	# Indirects cannot move and fire: any other origin yields nothing.
	assert_array(Combat.attackable_tiles(gs, arty.id, Vector2i(0, 3))).is_empty()
	# A tank shoots the four neighbors of wherever it stands.
	var tank := BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(2, 2))
	var ring := Combat.attackable_tiles(gs, tank.id, Vector2i(3, 1))
	var expected: Array[Vector2i] = [
		Vector2i(3, 0),
		Vector2i(2, 1),
		Vector2i(4, 1),
		Vector2i(3, 2),
	]
	assert_array(ring).contains_exactly(expected)
