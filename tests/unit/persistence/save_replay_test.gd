extends GdUnitTestSuite
## Save/replay (§11): action serialization round-trips by key, version
## guards reject loudly, and a recorded match rebuilt from JSON lands on
## a field-identical state. Plus MapDefinition -> GameState resolution,
## editor operations, the settings autoload, and the authored map.


func _small_def() -> MapDefinition:
	var def := MapDefinition.new()
	def.key = &"proving_grounds"
	def.display_name = "Proving Grounds"
	def.width = 5
	def.height = 3
	def.terrain_palette = [&"plains", &"factory", &"city"]
	var terrain := PackedInt32Array()
	terrain.resize(15)
	def.terrain = terrain
	var owners := PackedInt32Array()
	owners.resize(15)
	owners.fill(-1)
	def.property_owner = owners
	MapEditor.paint(def, Vector2i(1, 1), 1)
	MapEditor.claim_tile(def, Vector2i(1, 1), 0)
	MapEditor.paint(def, Vector2i(2, 0), 2)
	MapEditor.place_unit(def, &"infantry", 0, Vector2i(0, 0))
	MapEditor.place_unit(def, &"tank", 1, Vector2i(4, 2))
	return def


func _fixture_ruleset() -> Ruleset:
	return BattleFixture.make_econ_state().ruleset


func _setup_players() -> Array[Dictionary]:
	return [{"team": 0}, {"team": 1, "is_ai": true}]


func test_state_from_map_resolves_keys() -> void:
	var ruleset := _fixture_ruleset()
	var gs := Replay.state_from_map(_small_def(), ruleset, GameConfig.new(), 9, _setup_players())
	assert_object(gs).is_not_null()
	assert_int(gs.map.terrain_at(Vector2i(1, 1))).is_equal(BattleFixture.FACTORY)
	assert_int(gs.map.terrain_at(Vector2i(2, 0))).is_equal(BattleFixture.CITY)
	assert_int(gs.map.terrain_at(Vector2i(0, 0))).is_equal(BattleFixture.PLAINS)
	assert_int(gs.map.property_owner[gs.map.idx(Vector2i(1, 1))]).is_equal(0)
	assert_int(gs.units.size()).is_equal(2)
	var inf := gs.unit_at(Vector2i(0, 0))
	assert_that(ruleset.unit_types[inf.type_id].key).is_equal(&"infantry")
	assert_bool(gs.players[1].is_ai).is_true()
	assert_int(gs.rng.initial_seed()).is_equal(9)


func test_state_from_map_rejects_unknown_keys() -> void:
	var def := _small_def()
	def.terrain_palette = [&"lava", &"factory", &"city"]
	var gs := Replay.state_from_map(def, _fixture_ruleset(), GameConfig.new(), 1, _setup_players())
	assert_object(gs).is_null()


func test_action_serialization_round_trips() -> void:
	var ruleset := _fixture_ruleset()
	var ua := UnitAction.new()
	ua.unit_id = 7
	ua.path = [Vector2i(1, 2), Vector2i(2, 2)]
	ua.verb = UnitAction.Verb.UNLOAD
	ua.target_coord = Vector2i(2, 1)
	ua.cargo_index = 0
	var build := BuildAction.new()
	build.unit_type_id = BattleFixture.TANK
	build.coord = Vector2i(1, 1)
	var power := PowerAction.new()
	power.power_level = PlayerState.PowerState.SUPER
	for original: Action in [ua, build, power, EndTurnAction.new()]:
		var wire: Variant = JSON.parse_string(
			JSON.stringify(SaveGame.action_to_dict(original, ruleset))
		)
		var back := SaveGame.action_from_dict(wire as Dictionary, ruleset)
		assert_that(SaveGame.action_to_dict(back, ruleset)).is_equal(
			SaveGame.action_to_dict(original, ruleset)
		)
	# Builds serialize the type KEY, not the index.
	var build_wire := SaveGame.action_to_dict(build, ruleset)
	assert_that(build_wire["type"]).is_equal("tank")


func test_save_version_guard_rejects_loudly() -> void:
	assert_object(SaveGame.from_json('{"version": 99}')).is_null()
	assert_object(SaveGame.from_json("not json at all")).is_null()


func test_recorded_match_replays_to_identical_state() -> void:
	var def := _small_def()
	var live_ruleset := _fixture_ruleset()
	live_ruleset.starting_funds = 1500
	var save := SaveGame.new()
	save.map_key = def.key
	save.rng_seed = 21
	save.player_setup = _setup_players()
	var live := Replay.state_from_map(def, live_ruleset, GameConfig.new(), 21, save.player_setup)
	var script: Array[Action] = []
	var build := BuildAction.new()
	build.unit_type_id = BattleFixture.INFANTRY
	build.coord = Vector2i(1, 1)
	script.append(build)
	var walk := UnitAction.new()
	walk.unit_id = 1
	walk.path = [Vector2i(0, 0), Vector2i(1, 0)]
	script.append(walk)
	script.append(EndTurnAction.new())
	var roll := UnitAction.new()
	roll.unit_id = 2
	roll.path = [Vector2i(4, 2), Vector2i(3, 2)]
	script.append(roll)
	script.append(EndTurnAction.new())
	for action: Action in script:
		assert_object(Rules.validate(live, action)).is_null()
		Rules.apply(live, action)
		save.record(action, live_ruleset)
	var reloaded := SaveGame.from_json(save.to_json())
	assert_object(reloaded).is_not_null()
	var replay_ruleset := _fixture_ruleset()
	replay_ruleset.starting_funds = 1500
	var rebuilt := Replay.run(reloaded, replay_ruleset, def)
	assert_object(rebuilt).is_not_null()
	assert_int(rebuilt.units.size()).is_equal(live.units.size())
	for uid: int in live.units:
		var a: UnitState = live.units[uid]
		var b: UnitState = rebuilt.units[uid]
		assert_that(b.coord).is_equal(a.coord)
		assert_int(b.hp).is_equal(a.hp)
		assert_int(b.fuel).is_equal(a.fuel)
		assert_bool(b.has_acted).is_equal(a.has_acted)
	assert_int(rebuilt.day).is_equal(live.day)
	assert_int(rebuilt.current_player).is_equal(live.current_player)
	assert_int(rebuilt.players[0].funds).is_equal(live.players[0].funds)
	var next_live: int = live.rng.clone().roll_range(0, 1000000)
	var next_rebuilt: int = rebuilt.rng.clone().roll_range(0, 1000000)
	assert_int(next_rebuilt).is_equal(next_live)


func test_replay_rejects_wrong_map() -> void:
	var save := SaveGame.new()
	save.map_key = &"elsewhere"
	save.player_setup = _setup_players()
	assert_object(Replay.run(save, _fixture_ruleset(), _small_def())).is_null()


func test_editor_operations() -> void:
	var def := _small_def()
	MapEditor.paint(def, Vector2i(0, 2), 2)
	assert_int(def.terrain[2 * 5 + 0]).is_equal(2)
	MapEditor.paint(def, Vector2i(9, 9), 2)  # off-map: ignored
	MapEditor.paint(def, Vector2i(0, 0), 99)  # bad palette: ignored
	assert_int(def.terrain[0]).is_equal(0)
	# Replacing a starting unit keeps one entry per tile.
	MapEditor.place_unit(def, &"tank", 0, Vector2i(0, 0))
	assert_int(def.starting_units.size()).is_equal(2)
	MapEditor.remove_unit(def, Vector2i(0, 0))
	assert_int(def.starting_units.size()).is_equal(1)
	# Shrinking preserves overlap and culls out-of-bounds spawns.
	MapEditor.resize(def, 3, 3)
	assert_int(def.width).is_equal(3)
	assert_int(def.terrain.size()).is_equal(9)
	assert_int(def.terrain[1 * 3 + 1]).is_equal(1)  # the factory survived
	assert_int(def.starting_units.size()).is_equal(0)  # tank at (4,2) culled


func test_settings_store_round_trip() -> void:
	var store: Node = get_tree().root.get_node("SettingsStore")
	assert_object(store).is_not_null()
	var before: float = store.get_setting("sfx_volume")
	store.set_setting("sfx_volume", 0.25)
	store.reload()
	assert_float(store.get_setting("sfx_volume")).is_equal_approx(0.25, 0.001)
	store.set_setting("sfx_volume", before)


func test_crossroads_is_playable() -> void:
	var def := load("res://data/maps/crossroads.tres") as MapDefinition
	assert_object(def).is_not_null()
	assert_int(def.width).is_equal(12)
	assert_int(def.height).is_equal(10)
	var ruleset := load("res://data/rulesets/classic.tres") as Ruleset
	var setup: Array[Dictionary] = [
		{"team": 0, "co": &"vale"},
		{"team": 1, "co": &"rook", "is_ai": true},
	]
	var gs := Replay.state_from_map(def, ruleset, GameConfig.new(), 5, setup)
	assert_object(gs).is_not_null()
	assert_int(gs.units.size()).is_equal(6)
	assert_int(gs.occupancy.size()).is_equal(6)
	assert_int(gs.players[0].co_id).is_equal(0)  # vale
	assert_int(gs.players[1].co_id).is_equal(1)  # rook
	assert_int(gs.map.property_owner[gs.map.idx(Vector2i(1, 2))]).is_equal(0)
	# Each side's home city is its HQ: red at (1,1), blue at (10,1).
	for hq: Vector2i in [Vector2i(1, 1), Vector2i(10, 1)]:
		assert_bool(ruleset.terrain_types[gs.map.terrain_at(hq)].is_hq).is_true()
	assert_int(gs.map.property_owner[gs.map.idx(Vector2i(1, 1))]).is_equal(0)
	assert_int(gs.map.property_owner[gs.map.idx(Vector2i(10, 1))]).is_equal(1)
	assert_bool(ActionGenerator.generate(gs).size() > 1).is_true()


func test_from_json_rejects_mistyped_fields() -> void:
	var bad: Array[String] = [
		"[]",
		'{"version": "1"}',
		'{"version": 1.5}',
		'{"version": 1, "fog": "yes"}',
		'{"version": 1, "seed": 0.5}',
		'{"version": 1, "map": 7}',
		'{"version": 1, "players": {}}',
		'{"version": 1, "players": [3]}',
		'{"version": 1, "players": [{"team": "0"}]}',
		'{"version": 1, "players": [{"team": 0, "is_ai": "no"}]}',
		'{"version": 1, "actions": [5]}',
	]
	for text: String in bad:
		assert_object(SaveGame.from_json(text)).append_failure_message(text).is_null()
	var ok_text := (
		'{"version": 1, "seed": 42, "players": [{"team": 1, "co": "rook"}],'
		+ ' "actions": [{"kind": "end"}]}'
	)
	var ok := SaveGame.from_json(ok_text)
	assert_object(ok).is_not_null()
	assert_int(ok.rng_seed).is_equal(42)
	assert_int(ok.player_setup.size()).is_equal(1)
	assert_int(ok.player_setup[0]["team"]).is_equal(1)
	assert_that(ok.player_setup[0]["co"]).is_equal(&"rook")
	assert_int(ok.action_log.size()).is_equal(1)


func test_action_from_dict_rejects_malformed_fields() -> void:
	var ruleset := _fixture_ruleset()
	var bad: Array[String] = [
		'{"kind": 3}',
		'{"kind": "unit", "unit": 1.5, "path": [[0, 0]]}',
		'{"kind": "unit", "unit": 1, "path": "north"}',
		'{"kind": "unit", "unit": 1, "path": [[0]]}',
		'{"kind": "unit", "unit": 1, "path": [["a", 0]]}',
		'{"kind": "unit", "unit": 1, "path": [[0, 0]], "tx": 1e12}',
		'{"kind": "build", "type": 1, "x": 1, "y": 1}',
		'{"kind": "build", "type": "tank", "x": [1], "y": 1}',
		'{"kind": "power", "level": null}',
	]
	for text: String in bad:
		var data: Dictionary = JSON.parse_string(text)
		(
			assert_object(SaveGame.action_from_dict(data, ruleset))
			. append_failure_message(text)
			. is_null()
		)
	var good: Dictionary = JSON.parse_string(
		'{"kind": "unit", "unit": 1, "verb": 0, "path": [[0, 0], [1, 0]], "tx": 0, "ty": 0}'
	)
	var ua := SaveGame.action_from_dict(good, ruleset) as UnitAction
	assert_object(ua).is_not_null()
	assert_array(ua.path).contains_exactly([Vector2i(0, 0), Vector2i(1, 0)])
	assert_int(ua.cargo_index).is_equal(-1)


func test_state_from_map_rejects_malformed_maps() -> void:
	var ruleset := _fixture_ruleset()
	var defs: Array[MapDefinition] = []
	var short := _small_def()  # 14 cells for a 5x3 grid
	var cells := short.terrain
	cells.resize(14)
	short.terrain = cells
	defs.append(short)
	var off_palette := _small_def()  # palette has 3 entries
	cells = off_palette.terrain
	cells[7] = 9
	off_palette.terrain = cells
	defs.append(off_palette)
	var flat := _small_def()
	flat.width = 0
	defs.append(flat)
	var off_map := _small_def()
	MapEditor.place_unit(off_map, &"infantry", 0, Vector2i(9, 9))
	defs.append(off_map)
	var stacked := _small_def()  # a second unit onto the infantry at (0,0)
	stacked.starting_units.append({"type": &"tank", "team": 1, "x": 0, "y": 0})
	defs.append(stacked)
	var no_x := _small_def()
	no_x.starting_units.append({"type": &"infantry", "team": 0, "y": 1})
	defs.append(no_x)
	var numeric_type := _small_def()
	numeric_type.starting_units.append({"type": 5, "team": 0, "x": 3, "y": 0})
	defs.append(numeric_type)
	for i: int in range(defs.size()):
		var gs := Replay.state_from_map(defs[i], ruleset, GameConfig.new(), 1, _setup_players())
		assert_object(gs).append_failure_message("case %d" % i).is_null()


func test_state_from_map_rejects_bad_player_setups() -> void:
	var ruleset := _fixture_ruleset()  # no COs defined
	var cases: Array[Array] = [
		[],
		[{"team": 0}, {"team": 0}],
		[{"team": -1}],
		[{"team": 0, "co": &"nobody"}],
		[{"team": 0.0}],
		[{"team": 0, "is_ai": "yes"}],
	]
	for i: int in range(cases.size()):
		var setup: Array[Dictionary] = []
		setup.assign(cases[i])
		var gs := Replay.state_from_map(_small_def(), ruleset, GameConfig.new(), 1, setup)
		assert_object(gs).append_failure_message("case %d" % i).is_null()


func _logged(unit_id: int, verb: int, path: Array[Vector2i]) -> UnitAction:
	var ua := UnitAction.new()
	ua.unit_id = unit_id
	ua.verb = verb
	ua.path = path
	return ua


func test_crafted_save_cannot_walk_a_passenger_out() -> void:
	# The exploit a save file could carry before validate() refused
	# loaded units: board the APC, wait a turn, then march the passenger
	# off by itself — which erased the APC from occupancy. Ids follow
	# spawn order: infantry 1 at (0,0), tank 2, APC 3 at (1,0).
	var def := _small_def()
	MapEditor.place_unit(def, &"apc", 0, Vector2i(1, 0))
	var ruleset := _fixture_ruleset()
	var save := SaveGame.new()
	save.map_key = def.key
	save.rng_seed = 3
	save.player_setup = _setup_players()
	save.record(_logged(1, UnitAction.Verb.LOAD, [Vector2i(0, 0), Vector2i(1, 0)]), ruleset)
	save.record(EndTurnAction.new(), ruleset)
	save.record(EndTurnAction.new(), ruleset)
	var honest := Replay.run(SaveGame.from_json(save.to_json()), ruleset, def)
	assert_object(honest).is_not_null()
	assert_int(honest.units[1].carrier_id).is_equal(3)
	assert_int(honest.occupancy[Vector2i(1, 0)]).is_equal(3)
	save.record(_logged(1, UnitAction.Verb.WAIT, [Vector2i(1, 0), Vector2i(2, 0)]), ruleset)
	assert_object(Replay.run(SaveGame.from_json(save.to_json()), ruleset, def)).is_null()


func test_settings_store_filters_types_and_clamps() -> void:
	var store: Node = get_tree().root.get_node("SettingsStore")
	var sfx_before: float = store.get_setting("sfx_volume")
	var skip_before: bool = store.get_setting("skip_animations")
	(
		store
		. apply_loaded(
			{
				"sfx_volume": "loud",  # wrong type: ignored
				"music_volume": 7.0,  # clamped to 1
				"skip_animations": 1.0,  # wrong type: ignored
				"bogus": true,  # unknown key: dropped
				"fog_default": true,
			}
		)
	)
	assert_float(store.get_setting("sfx_volume")).is_equal_approx(sfx_before, 0.0001)
	assert_float(store.get_setting("music_volume")).is_equal_approx(1.0, 0.0001)
	assert_bool(store.get_setting("skip_animations")).is_equal(skip_before)
	assert_object(store.get_setting("bogus")).is_null()
	assert_bool(store.get_setting("fog_default")).is_true()
	# Whole numbers come back from JSON as floats; an int setting takes
	# them as ints and ignores anything fractional.
	store.apply_loaded({"player_funds": 5000.0, "enemy_funds": 2500.5, "difficulty": "hard"})
	assert_that(store.get_setting("player_funds")).is_equal(5000)
	assert_int(typeof(store.get_setting("player_funds"))).is_equal(TYPE_INT)
	assert_that(store.get_setting("enemy_funds")).is_equal(0)
	assert_that(store.get_setting("difficulty")).is_equal("hard")
	store.reload()  # back to what's on disk
