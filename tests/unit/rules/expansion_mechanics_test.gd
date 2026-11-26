extends GdUnitTestSuite
## Unit tests for the gameplay expansion: rivers/bridges/sea/ports,
## Comms Towers, Missile Silos, the 5 new COs, MapGenerator, MissionCatalog,
## MatchRank, puzzle turn-limit victory, and BattleController undo/idle-unit.

const CLASSIC := "res://data/rulesets/classic.tres"


func _classic() -> Ruleset:
	return load(CLASSIC) as Ruleset


func _make_custom_state(
	w: int, h: int, fill_key: StringName, p0_co: StringName = &"vale", p1_co: StringName = &"rook"
) -> GameState:
	var rs := _classic()
	var def := MapDefinition.new()
	def.key = &"test_custom"
	def.display_name = "Test"
	def.width = w
	def.height = h
	def.terrain_palette = [fill_key]
	var cells := PackedInt32Array()
	cells.resize(w * h)
	cells.fill(0)
	def.terrain = cells
	var owners := PackedInt32Array()
	owners.resize(w * h)
	owners.fill(-1)
	def.property_owner = owners
	return Replay.state_from_map(
		def, rs, GameConfig.new(), 42, [{"team": 0, "co": p0_co}, {"team": 1, "co": p1_co}]
	)


func _terrain_id(rs: Ruleset, key: StringName) -> int:
	for i: int in range(rs.terrain_types.size()):
		if rs.terrain_types[i].key == key:
			return i
	return -1


func _unit_id(rs: Ruleset, key: StringName) -> int:
	for i: int in range(rs.unit_types.size()):
		if rs.unit_types[i].key == key:
			return i
	return -1


func test_river_blocks_tanks_while_bridge_allows_crossing() -> void:
	var gs := _make_custom_state(5, 3, &"plains")
	var river := _terrain_id(gs.ruleset, &"river")
	var bridge := _terrain_id(gs.ruleset, &"bridge")
	gs.map.terrain[gs.map.idx(Vector2i(2, 0))] = river
	gs.map.terrain[gs.map.idx(Vector2i(2, 1))] = bridge
	gs.map.terrain[gs.map.idx(Vector2i(2, 2))] = river
	var tank := Ids.create_unit(gs, _unit_id(gs.ruleset, &"tank"), 0, Vector2i(1, 0))
	var inf := Ids.create_unit(gs, _unit_id(gs.ruleset, &"infantry"), 0, Vector2i(1, 2))
	assert_int(Movement.enter_cost(gs, tank, Vector2i(2, 0))).is_equal(-1)
	assert_int(Movement.enter_cost(gs, tank, Vector2i(2, 1))).is_equal(1)
	assert_int(Movement.enter_cost(gs, inf, Vector2i(2, 2))).is_equal(2)


func test_port_builds_naval_units_and_repairs_ships() -> void:
	var gs := _make_custom_state(4, 3, &"sea")
	var port := _terrain_id(gs.ruleset, &"port")
	gs.map.terrain[gs.map.idx(Vector2i(1, 1))] = port
	gs.map.property_owner[gs.map.idx(Vector2i(1, 1))] = 0
	gs.players[0].funds = 30000
	var buildable := Economy.buildable_units(gs, Vector2i(1, 1))
	assert_bool(buildable.has(_unit_id(gs.ruleset, &"lander"))).is_true()
	assert_bool(buildable.has(_unit_id(gs.ruleset, &"cruiser"))).is_true()
	assert_bool(buildable.has(_unit_id(gs.ruleset, &"battleship"))).is_true()
	assert_bool(buildable.has(_unit_id(gs.ruleset, &"tank"))).is_false()


func test_comms_tower_grants_global_attack_bonus() -> void:
	var gs := _make_custom_state(4, 3, &"plains", &"vale", &"vale")
	var comms := _terrain_id(gs.ruleset, &"comms_tower")
	var tank := Ids.create_unit(gs, _unit_id(gs.ruleset, &"tank"), 0, Vector2i(0, 0))
	assert_int(Combat.attack_mod(gs, tank)).is_equal(100)
	gs.map.terrain[gs.map.idx(Vector2i(1, 0))] = comms
	gs.map.property_owner[gs.map.idx(Vector2i(1, 0))] = 0
	assert_int(Combat.attack_mod(gs, tank)).is_equal(110)
	gs.map.terrain[gs.map.idx(Vector2i(2, 0))] = comms
	gs.map.property_owner[gs.map.idx(Vector2i(2, 0))] = 0
	assert_int(Combat.attack_mod(gs, tank)).is_equal(120)


func test_silo_launch_damages_diamond_non_lethally_and_spends_silo() -> void:
	var gs := _make_custom_state(6, 5, &"plains")
	var silo := _terrain_id(gs.ruleset, &"silo")
	gs.map.terrain[gs.map.idx(Vector2i(1, 2))] = silo
	var inf := Ids.create_unit(gs, _unit_id(gs.ruleset, &"infantry"), 0, Vector2i(0, 2))
	var tank := Ids.create_unit(gs, _unit_id(gs.ruleset, &"tank"), 0, Vector2i(0, 0))
	var foe_full := Ids.create_unit(gs, _unit_id(gs.ruleset, &"tank"), 1, Vector2i(4, 2))
	var foe_low := Ids.create_unit(gs, _unit_id(gs.ruleset, &"infantry"), 1, Vector2i(4, 3))
	foe_low.hp = 20
	var foe_far := Ids.create_unit(gs, _unit_id(gs.ruleset, &"tank"), 1, Vector2i(5, 4))

	# Non-capturers cannot launch a silo.
	assert_object(Silo.validate(gs, tank, Vector2i(1, 2), Vector2i(4, 2))).is_not_null()

	# Infantry moves onto the silo and launches at (4, 2).
	var ua := UnitAction.new()
	ua.unit_id = inf.id
	ua.path = [Vector2i(0, 2), Vector2i(1, 2)]
	ua.verb = UnitAction.Verb.LAUNCH
	ua.target_coord = Vector2i(4, 2)
	assert_object(Rules.validate(gs, ua)).is_null()
	var events := Rules.apply(gs, ua)
	assert_int(foe_full.hp).is_equal(70)
	assert_int(foe_low.hp).is_equal(1)  # non-lethal floor
	assert_int(foe_far.hp).is_equal(100)  # Manhattan distance 3 > 2: untouched
	assert_that(gs.ruleset.terrain_types[gs.map.terrain_at(Vector2i(1, 2))].key).is_equal(
		&"silo_spent"
	)
	var saw_silo: bool = false
	for e: GameEvent in events:
		if e is Events.SiloLaunched:
			saw_silo = true
	assert_bool(saw_silo).is_true()
	# Second launch on spent silo is rejected.
	inf.has_acted = false
	ua.path = [Vector2i(1, 2)]
	assert_object(Rules.validate(gs, ua)).is_not_null()


func test_new_commanders_apply_distinct_mechanics() -> void:
	# Blitz: +15% direct ATK, -10% indirect ATK, Super refreshes acted units +2 move.
	var g_blitz := _make_custom_state(6, 3, &"plains", &"blitz", &"vale")
	var b_tank := Ids.create_unit(g_blitz, _unit_id(g_blitz.ruleset, &"tank"), 0, Vector2i(0, 1))
	var b_art := Ids.create_unit(
		g_blitz, _unit_id(g_blitz.ruleset, &"artillery"), 0, Vector2i(0, 2)
	)
	assert_int(Combat.attack_mod(g_blitz, b_tank)).is_equal(115)
	assert_int(Combat.attack_mod(g_blitz, b_art)).is_equal(90)
	b_tank.has_acted = true
	g_blitz.players[0].power_meter = 600
	var sp := PowerAction.new()
	sp.power_level = PlayerState.PowerState.SUPER
	Rules.apply(g_blitz, sp)
	assert_bool(b_tank.has_acted).is_false()
	assert_int(Movement.points_for(g_blitz, b_tank)).is_equal(8)  # 6 + 2

	# Nova: +25% indirect ATK, Power extends indirect max range by +1.
	var g_nova := _make_custom_state(7, 3, &"plains", &"nova", &"vale")
	var n_art := Ids.create_unit(g_nova, _unit_id(g_nova.ruleset, &"artillery"), 0, Vector2i(0, 1))
	assert_int(Combat.attack_mod(g_nova, n_art)).is_equal(125)
	assert_int(Combat.attack_range_max_for(g_nova, n_art)).is_equal(3)
	g_nova.players[0].power_meter = 300
	var np := PowerAction.new()
	np.power_level = PlayerState.PowerState.CO_POWER
	Rules.apply(g_nova, np)
	assert_int(Combat.attack_range_max_for(g_nova, n_art)).is_equal(4)

	# Aero: +20% air ATK and half air fuel burn.
	var g_aero := _make_custom_state(4, 3, &"plains", &"aero", &"vale")
	var copter := Ids.create_unit(g_aero, _unit_id(g_aero.ruleset, &"copter"), 0, Vector2i(1, 1))
	assert_int(Combat.attack_mod(g_aero, copter)).is_equal(120)
	var before_fuel: int = copter.fuel
	Supply.begin_turn_fuel(g_aero, 0)
	assert_int(before_fuel - copter.fuel).is_equal(1)  # 2 halved to 1

	# Midas: 15% unit discount + War Chest bonus funds.
	var g_midas := _make_custom_state(4, 3, &"plains", &"midas", &"vale")
	var tank_type: UnitType = g_midas.ruleset.unit_types[_unit_id(g_midas.ruleset, &"tank")]
	assert_int(Economy.unit_cost(g_midas, 0, tank_type)).is_equal(5950)
	g_midas.map.terrain[0] = _terrain_id(g_midas.ruleset, &"city")
	g_midas.map.property_owner[0] = 0
	g_midas.players[0].power_meter = 300
	var mp := PowerAction.new()
	mp.power_level = PlayerState.PowerState.CO_POWER
	Rules.apply(g_midas, mp)
	assert_int(g_midas.players[0].funds).is_equal(500)  # 50% of 1000 income

	# Shade: +1 vision, ignores weather slowdown, +5% DEF per terrain star.
	var g_shade := _make_custom_state(6, 3, &"plains", &"shade", &"vale")
	g_shade.config.fog_enabled = true
	g_shade.weather = GameState.Weather.SNOW
	var s_tank := Ids.create_unit(g_shade, _unit_id(g_shade.ruleset, &"tank"), 0, Vector2i(0, 1))
	assert_int(Movement.enter_cost(g_shade, s_tank, Vector2i(1, 1))).is_equal(1)  # clear cost!
	assert_bool(Fog.tile_visible(g_shade, 0, Vector2i(4, 1))).is_true()  # vision 3 + 1 = 4
	assert_int(Combat.defense_mod(g_shade, s_tank)).is_equal(105)  # 1 star * 5%


func test_map_generator_is_deterministic_and_fair() -> void:
	var rs := _classic()
	for preset: StringName in MapGenerator.PRESETS:
		var a := MapGenerator.generate(preset, 77)
		var b := MapGenerator.generate(preset, 77)
		assert_that(a.terrain).is_equal(b.terrain)
		assert_that(a.property_owner).is_equal(b.property_owner)
		var gs := Replay.state_from_map(
			a, rs, GameConfig.new(), 1, [{"team": 0, "co": &"vale"}, {"team": 1, "co": &"rook"}]
		)
		assert_object(gs).append_failure_message(String(preset)).is_not_null()
		assert_bool(ActionGenerator.generate(gs).size() > 1).is_true()


func test_all_missions_and_puzzles_load_and_enforce_turn_limit() -> void:
	var rs := _classic()
	for m: MissionCatalog.MissionDef in MissionCatalog.missions():
		var gs := (
			Replay
			. state_from_map(
				m.map,
				rs,
				GameConfig.new(),
				1,
				[
					{"team": 0, "co": m.player_co, "funds": m.player_funds},
					{"team": 1, "co": m.enemy_co, "is_ai": true, "funds": m.enemy_funds},
				]
			)
		)
		assert_object(gs).append_failure_message(String(m.key)).is_not_null()
		assert_bool(ActionGenerator.generate(gs).size() > 1).is_true()
	for p: MissionCatalog.MissionDef in MissionCatalog.puzzles():
		var cfg := GameConfig.new()
		cfg.turn_limit = p.turn_limit
		var gs := (
			Replay
			. state_from_map(
				p.map,
				rs,
				cfg,
				1,
				[
					{"team": 0, "co": p.player_co, "meter": p.initial_player_meter},
					{"team": 1, "co": p.enemy_co, "is_ai": true},
				]
			)
		)
		assert_object(gs).append_failure_message(String(p.key)).is_not_null()
		# Passing turns past turn_limit ends the puzzle in defeat for team 0.
		Rules.apply(gs, EndTurnAction.new())
		Rules.apply(gs, EndTurnAction.new())
		assert_bool(Rules.is_game_over(gs)).is_true()
		assert_bool(gs.players[0].is_alive).is_false()


func test_match_rank_and_battle_controller_undo_and_next_idle() -> void:
	var s_rank := MatchRank.evaluate(6, 8, 3, 2, 0, 5)
	assert_that(s_rank.grade).is_equal("S")
	var c_rank := MatchRank.evaluate(25, 8, 0, 2, 5, 1)
	assert_that(c_rank.grade).is_equal("C")

	var b: Battle = auto_free(Battle.assemble())
	add_child(b)
	b.event_player.skip_animations = true
	b.load_map(MapCatalog.find(&"crossroads"))
	var start_coord := Vector2i(2, 3)  # red infantry
	b.cursor.move_to(start_coord)
	b.controller.confirm()
	b.cursor.move_to(Vector2i(3, 3))
	b.controller.confirm()
	b.hud.action_menu.choose_selected()  # Wait
	assert_bool(b.controller.can_undo()).is_true()
	assert_object(b.state.unit_at(Vector2i(3, 3))).is_not_null()
	b.controller.undo_last_move()
	assert_bool(b.controller.can_undo()).is_false()
	assert_object(b.state.unit_at(start_coord)).is_not_null()
	assert_object(b.state.unit_at(Vector2i(3, 3))).is_null()
	b.cursor.move_to(Vector2i(0, 0))
	b.controller.focus_next_idle_unit()
	assert_object(b.state.unit_at(b.cursor.coord)).is_not_null()
