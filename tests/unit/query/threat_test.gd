extends GdUnitTestSuite
## Threat.danger_zone: the enemy-range inspection primitive. Values
## hand-checked on BattleFixture.


func test_immobile_fire_zone_is_exactly_the_ring() -> void:
	# Artillery can't move and fire, so its zone is its 2..3 ring from
	# where it stands — identical to Combat.attackable_tiles.
	var gs := BattleFixture.make_state()
	var arty := BattleFixture.spawn(gs, BattleFixture.ARTILLERY, 1, Vector2i(0, 2))
	var zone := Threat.danger_zone(gs, arty.id)
	assert_array(zone).contains_exactly(Combat.attackable_tiles(gs, arty.id, Vector2i(0, 2)))
	assert_array(zone).has_size(10)


func test_unarmed_units_threaten_nothing() -> void:
	var gs := BattleFixture.make_state()
	var heli := BattleFixture.spawn(gs, BattleFixture.HELI, 1, Vector2i(2, 2))
	var apc := BattleFixture.spawn(gs, BattleFixture.APC, 1, Vector2i(0, 0))
	assert_array(Threat.danger_zone(gs, heli.id)).is_empty()
	assert_array(Threat.danger_zone(gs, apc.id)).is_empty()


func test_dry_ammo_silences_ammo_weapons_only() -> void:
	var gs := BattleFixture.make_state()
	# Artillery has no ammo-free fallback: dry means harmless.
	var arty := BattleFixture.spawn(gs, BattleFixture.ARTILLERY, 1, Vector2i(0, 2))
	arty.ammo = 0
	assert_array(Threat.danger_zone(gs, arty.id)).is_empty()
	# A dry tank still has its mg: the zone survives.
	var tank := BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(2, 2))
	tank.ammo = 0
	assert_bool(Threat.danger_zone(gs, tank.id).is_empty()).is_false()


func test_mobile_zone_covers_ring_of_every_stoppable_dest() -> void:
	var gs := BattleFixture.make_state()
	var tank := BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(2, 2))
	var zone := Threat.danger_zone(gs, tank.id)
	# Adjacent to where it stands.
	assert_bool(zone.has(Vector2i(2, 1))).is_true()
	# (0,0) is hit from the destination (0,1): route (1,2)-(0,2)-(0,1)
	# costs 3 of its 4 movement.
	assert_bool(zone.has(Vector2i(0, 0))).is_true()
	# Deterministic row-major ordering.
	for i: int in range(1, zone.size()):
		var earlier := zone[i - 1]
		var later := zone[i]
		var ordered := earlier.y < later.y or (earlier.y == later.y and earlier.x < later.x)
		assert_bool(ordered).is_true()


func test_team_danger_zone_unions_enemies_only() -> void:
	var gs := BattleFixture.make_state()
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))  # armed, but ours
	var tank := BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(2, 2))
	var arty := BattleFixture.spawn(gs, BattleFixture.ARTILLERY, 1, Vector2i(0, 2))
	var manual: Dictionary[Vector2i, bool] = {}
	for c: Vector2i in Threat.danger_zone(gs, tank.id):
		manual[c] = true
	for c: Vector2i in Threat.danger_zone(gs, arty.id):
		manual[c] = true
	var combined := Threat.team_danger_zone(gs, 0)
	assert_int(combined.size()).is_equal(manual.size())
	for c: Vector2i in combined:
		assert_bool(manual.has(c)).is_true()


func test_team_danger_zone_respects_fog() -> void:
	var gs := BattleFixture.make_state()
	gs.config.fog_enabled = true
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))  # vision 2
	var arty := BattleFixture.spawn(gs, BattleFixture.ARTILLERY, 1, Vector2i(0, 3))  # dark
	assert_array(Threat.team_danger_zone(gs, 0)).is_empty()
	var tank := BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(0, 2))  # lit
	var combined := Threat.team_danger_zone(gs, 0)
	assert_array(combined).contains_exactly(Threat.danger_zone(gs, tank.id))
	assert_object(arty).is_not_null()  # present, hidden, and excluded
