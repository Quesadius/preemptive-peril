extends GdUnitTestSuite
## Integrity checks for the authored classic ruleset (milestone 3), plus a
## smoke battle proving the real rules run on the real data. Damage
## expectations are hand-computed from the authored tables.

const CLASSIC := "res://data/rulesets/classic.tres"

const UNIT_KEYS: Array[StringName] = [
	&"infantry",
	&"mech",
	&"tank",
	&"artillery",
	&"recon",
	&"md_tank",
	&"rockets",
	&"anti_air",
	&"apc",
]
const TERRAIN_KEYS: Array[StringName] = [
	&"plains", &"road", &"forest", &"mountain", &"city", &"factory"
]
const CLASS_KEYS: Array[StringName] = [&"foot", &"boots", &"treads", &"tires"]


func _classic() -> Ruleset:
	var rs := load(CLASSIC) as Ruleset
	assert_object(rs).is_not_null()
	return rs


func test_loads_with_expected_content() -> void:
	var rs := _classic()
	assert_int(rs.unit_types.size()).is_equal(9)
	assert_int(rs.terrain_types.size()).is_equal(6)
	assert_int(rs.movement_classes.size()).is_equal(4)
	for i: int in range(UNIT_KEYS.size()):
		assert_that(rs.unit_types[i].key).is_equal(UNIT_KEYS[i])
	for i: int in range(TERRAIN_KEYS.size()):
		assert_that(rs.terrain_types[i].key).is_equal(TERRAIN_KEYS[i])
	for i: int in range(CLASS_KEYS.size()):
		assert_that(rs.movement_classes[i].key).is_equal(CLASS_KEYS[i])
	assert_int(rs.luck_max).is_equal(9)
	assert_int(rs.funds_per_property).is_equal(1000)
	assert_int(rs.capture_threshold).is_equal(20)


func test_every_terrain_covers_every_class_and_weather() -> void:
	var rs := _classic()
	for t: TerrainType in rs.terrain_types:
		for ck: StringName in CLASS_KEYS:
			(
				assert_bool(t.move_costs.has(ck))
				. append_failure_message("%s missing costs for %s" % [t.key, ck])
				. is_true()
			)
			var costs: PackedInt32Array = t.move_costs[ck]
			assert_int(costs.size()).is_equal(GameState.Weather.size())
			for c: int in costs:
				(
					assert_bool(c == -1 or c >= 1)
					. append_failure_message("%s/%s has cost %d" % [t.key, ck, c])
					. is_true()
				)


func test_unit_internal_consistency() -> void:
	var rs := _classic()
	for u: UnitType in rs.unit_types:
		assert_object(u.movement_class).is_not_null()
		assert_bool(CLASS_KEYS.has(u.movement_class.key)).is_true()
		assert_bool(u.cost > 0 and u.movement > 0 and u.max_fuel > 0).is_true()
		var needs_ammo: bool = false
		for w: WeaponProfile in [u.primary_weapon, u.secondary_weapon]:
			if w == null:
				continue
			assert_object(w.damage_table).is_not_null()
			needs_ammo = needs_ammo or w.uses_ammo
			for defender: StringName in w.damage_table.base_damage:
				(
					assert_bool(UNIT_KEYS.has(defender))
					. append_failure_message("%s targets unknown unit %s" % [w.key, defender])
					. is_true()
				)
				# Heavy weapons legitimately exceed 100 vs soft targets.
				assert_int(w.damage_table.base_damage[defender]).is_between(1, 130)
		# Ammo capacity exists exactly for units with an ammo-using weapon.
		assert_bool(u.max_ammo > 0).is_equal(needs_ammo)
	# Role flags.
	assert_bool(rs.unit_types[0].capture_capable).is_true()  # infantry
	assert_bool(rs.unit_types[1].capture_capable).is_true()  # mech
	assert_bool(rs.unit_types[2].capture_capable).is_false()  # tank
	var artillery: UnitType = rs.unit_types[3]
	assert_int(artillery.attack_range_min).is_equal(2)
	assert_int(artillery.attack_range_max).is_equal(3)
	assert_bool(artillery.can_move_and_fire).is_false()


func test_terrain_properties_and_stats() -> void:
	var rs := _classic()
	var mountain: TerrainType = rs.terrain_types[3]
	var city: TerrainType = rs.terrain_types[4]
	var factory: TerrainType = rs.terrain_types[5]
	for weather: int in range(GameState.Weather.size()):
		assert_int(mountain.move_costs[&"treads"][weather]).is_equal(-1)
	assert_int(mountain.move_costs[&"boots"][GameState.Weather.CLEAR]).is_equal(1)
	assert_int(mountain.vision_bonus).is_equal(3)
	assert_bool(rs.terrain_types[2].hides_units).is_true()  # forest
	for property: TerrainType in [city, factory]:
		assert_bool(property.is_property).is_true()
		assert_bool(property.capturable).is_true()
		assert_int(property.income).is_equal(1000)
		assert_int(property.repairs_classes.size()).is_equal(4)
	assert_that(factory.builds).is_equal(&"factory")
	assert_that(city.builds).is_equal(&"")


func test_new_roster_roles_and_costs() -> void:
	var rs := _classic()
	var recon: UnitType = rs.unit_types[4]
	assert_int(recon.vision).is_equal(5)
	assert_that(recon.movement_class.key).is_equal(&"tires")
	var rockets: UnitType = rs.unit_types[6]
	assert_int(rockets.attack_range_min).is_equal(3)
	assert_int(rockets.attack_range_max).is_equal(5)
	assert_bool(rockets.can_move_and_fire).is_false()
	assert_that(rockets.movement_class.key).is_equal(&"tires")
	# Tires pay 2 on plains but 1 on roads in the clear.
	assert_int(rs.terrain_types[0].move_costs[&"tires"][GameState.Weather.CLEAR]).is_equal(2)
	assert_int(rs.terrain_types[1].move_costs[&"tires"][GameState.Weather.CLEAR]).is_equal(1)
	assert_int(rs.terrain_types[3].move_costs[&"tires"][GameState.Weather.CLEAR]).is_equal(-1)
	# Nothing in the roster is invulnerable: every unit key appears as a
	# defender in someone's damage table.
	var hittable: Dictionary[StringName, bool] = {}
	for u: UnitType in rs.unit_types:
		for w: WeaponProfile in [u.primary_weapon, u.secondary_weapon]:
			if w == null:
				continue
			for defender: StringName in w.damage_table.base_damage:
				hittable[defender] = true
	for key: StringName in UNIT_KEYS:
		(
			assert_bool(hittable.has(key))
			. append_failure_message("nothing can damage %s" % key)
			. is_true()
		)


func test_new_roster_damage_smoke() -> void:
	# Hand-computed spot checks with luck off, defenders on plains:
	# recon MG 70 * 0.9 = 63; md cannon 85 * 0.9 = 76; vulcan 105 * 0.9 = 94.
	var rs := (load(CLASSIC) as Ruleset).duplicate() as Ruleset
	rs.luck_max = 0
	var gs := GameState.new()
	gs.ruleset = rs
	gs.config = GameConfig.new()
	gs.map = _open_plains(5, 5)
	gs.rng = DeterministicRng.new(4)
	for team: int in range(2):
		var p := PlayerState.new()
		p.team = team
		gs.players.append(p)
	var recon := _spawn(gs, 4, 0, Vector2i(1, 2))
	var inf := _spawn(gs, 0, 1, Vector2i(2, 2))
	assert_int(Combat.preview(gs, recon.id, inf.id).damage).is_equal(63)
	var md := _spawn(gs, 5, 0, Vector2i(1, 1))
	var tank := _spawn(gs, 2, 1, Vector2i(2, 1))
	assert_int(Combat.preview(gs, md.id, tank.id).damage).is_equal(76)
	var aa := _spawn(gs, 7, 0, Vector2i(3, 3))
	var mech := _spawn(gs, 1, 1, Vector2i(3, 2))
	assert_int(Combat.preview(gs, aa.id, mech.id).damage).is_equal(94)
	# Rockets: minimum range 3 keeps adjacent tiles out of reach.
	var rockets := _spawn(gs, 6, 0, Vector2i(0, 4))
	var ring := Combat.attackable_tiles(gs, rockets.id, Vector2i(0, 4))
	assert_bool(ring.has(Vector2i(0, 3))).is_false()
	assert_bool(ring.has(Vector2i(3, 4))).is_true()


func test_classic_battle_smoke() -> void:
	# Real rules on real data, luck disabled for exact numbers.
	var rs := (load(CLASSIC) as Ruleset).duplicate() as Ruleset
	rs.luck_max = 0
	var gs := GameState.new()
	gs.ruleset = rs
	gs.config = GameConfig.new()
	gs.map = _open_plains(5, 5)
	gs.rng = DeterministicRng.new(3)
	for team: int in range(2):
		var p := PlayerState.new()
		p.team = team
		gs.players.append(p)
	var tank := _spawn(gs, 2, 0, Vector2i(1, 2))
	var inf := _spawn(gs, 0, 1, Vector2i(2, 2))
	var mech := _spawn(gs, 1, 1, Vector2i(4, 4))
	# Infantry on open plains, move 3: the 21-tile manhattan diamond,
	# minus the enemy tank's tile AND (0,2) behind it — every 3-cost
	# route there runs through the tank, and the detours cost 4. 19 tiles.
	assert_int(Movement.reachable(gs, inf.id).size()).is_equal(19)
	# Tank vs infantry: cannon can't target foot, so the MG fires:
	# 75 * 1.0 * (100 - 1*10)/100 = 67.5 -> 67. Counter from 33 hp
	# (dhp 4): 5 * 0.4 * 0.9 = 1.8 -> 1.
	var p := Combat.preview(gs, tank.id, inf.id)
	assert_int(p.damage).is_equal(67)
	assert_int(p.counter_damage).is_equal(1)
	var attack := UnitAction.new()
	attack.unit_id = tank.id
	attack.path = [Vector2i(1, 2)]
	attack.verb = UnitAction.Verb.ATTACK
	attack.target_coord = Vector2i(2, 2)
	assert_object(Rules.validate(gs, attack)).is_null()
	var events := Rules.apply(gs, attack)
	assert_array(events).has_size(3)  # attack, counter, exhaust
	assert_int(inf.hp).is_equal(33)
	assert_int(tank.hp).is_equal(99)
	assert_int(tank.ammo).is_equal(9)  # the MG costs nothing
	# Mech weapon selection: bazooka for armor (55 * 0.9 vs the 99-hp
	# tank = 49), MG for foot (65 * (100 - 4)/100 vs the 33-hp infantry
	# = 62.4 -> 62).
	assert_int(Combat.preview(gs, mech.id, tank.id).damage).is_equal(49)
	assert_int(Combat.preview(gs, mech.id, inf.id).damage).is_equal(62)


func _open_plains(w: int, h: int) -> MapState:
	var m := MapState.new()
	m.width = w
	m.height = h
	var t := PackedInt32Array()
	t.resize(w * h)  # terrain id 0 = plains
	m.terrain = t
	var owners := PackedInt32Array()
	owners.resize(w * h)
	owners.fill(MapState.NO_OWNER)
	m.property_owner = owners
	return m


func _spawn(gs: GameState, type_id: int, team: int, coord: Vector2i) -> UnitState:
	var unit_type: UnitType = gs.ruleset.unit_types[type_id]
	var u := UnitState.new()
	u.id = gs.next_unit_id
	gs.next_unit_id += 1
	u.type_id = type_id
	u.team = team
	u.coord = coord
	u.fuel = unit_type.max_fuel
	u.ammo = unit_type.max_ammo
	gs.units[u.id] = u
	gs.occupancy[coord] = u.id
	return u
