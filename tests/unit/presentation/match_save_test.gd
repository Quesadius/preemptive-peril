extends GdUnitTestSuite
## Autosave through a real battle: the match is written after every
## action, a fresh battle resumes it exactly and keeps recording, the
## save goes away when the match is decided, and states loaded directly
## are never recorded.

const SCRATCH := "user://test_match_autosave.json"


func after_test() -> void:
	SaveGame.delete_file(SCRATCH)


func _rig() -> Battle:
	var battle: Battle = auto_free(Battle.assemble())
	add_child(battle)
	battle.event_player.skip_animations = true
	battle.autosave_path = SCRATCH
	return battle


func _end_turn(b: Battle) -> void:
	b.cursor.move_to(Vector2i(0, 0))  # empty plains on Gauntlet: the system menu
	b.controller.confirm()
	b.hud.action_menu.choose_selected()  # End Turn; the AI then plays its turn


func test_match_is_saved_after_every_action_and_resumes_exactly() -> void:
	var b := _rig()
	b.load_map(MapCatalog.find(&"gauntlet"), true, false)
	var opening := SaveGame.read_file(SCRATCH)
	assert_object(opening).is_not_null()  # saved the moment the match starts
	assert_array(opening.action_log).is_empty()
	assert_bool(opening.fog_enabled).is_true()
	_end_turn(b)
	assert_int(b.state.day).is_equal(2)
	assert_int(b.state.current_player).is_equal(0)
	var saved := SaveGame.read_file(SCRATCH)
	# Red's End Turn, whatever blue's AI did, and blue's End Turn.
	assert_bool(saved.action_log.size() >= 2).is_true()
	assert_that(saved.action_log[0]).is_equal({"kind": "end"})
	assert_that(saved.digest).is_equal(Replay.digest(b.state))
	# A brand-new battle picks the match up where it stood.
	var again: Battle = auto_free(Battle.assemble())
	add_child(again)
	again.event_player.skip_animations = true
	again.autosave_path = SCRATCH
	assert_bool(again.resume(saved)).is_true()
	assert_that(Replay.digest(again.state)).is_equal(Replay.digest(b.state))
	assert_bool(again.state.config.fog_enabled).is_true()
	assert_int(again.state.map.width).is_equal(8)
	# ...and goes on recording into the same save.
	var before: int = saved.action_log.size()
	_end_turn(again)
	assert_int(again.state.day).is_equal(3)
	var later := SaveGame.read_file(SCRATCH)
	assert_bool(later.action_log.size() >= before + 2).is_true()
	assert_object(Replay.run(later, again.ruleset, MapCatalog.find(&"gauntlet"))).is_not_null()


func test_a_decided_match_removes_its_save() -> void:
	# Stand a red infantry on blue's HQ at (2,0), one step from taking it.
	var b := _rig()
	b.load_map(MapCatalog.find(&"gauntlet"))
	assert_object(SaveGame.read_file(SCRATCH)).is_not_null()
	var gs := b.state
	var raider := gs.unit_at(Vector2i(5, 10))  # a red infantry
	gs.occupancy.erase(raider.coord)
	raider.coord = Vector2i(2, 0)
	gs.occupancy[raider.coord] = raider.id
	gs.map.capture_progress[Vector2i(2, 0)] = 10
	b.cursor.move_to(Vector2i(2, 0))
	b.controller.confirm()
	b.controller.confirm()  # stay put -> verb menu
	var menu := b.hud.action_menu
	while menu.items()[menu.selected_index()] != "Capture":
		menu.move_selection(1)
	menu.choose_selected()
	assert_that(b.controller.phase()).is_equal(BattleController.State.GAME_OVER)
	assert_object(SaveGame.read_file(SCRATCH)).is_null()


func test_states_loaded_directly_are_not_recorded() -> void:
	var b := _rig()
	var gs := BattleFixture.make_state()
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(4, 4))
	b.load_state(gs)
	b.cursor.move_to(Vector2i(0, 0))
	b.controller.confirm()
	b.cursor.move_to(Vector2i(0, 1))
	b.controller.confirm()
	b.hud.action_menu.choose_selected()  # Wait
	assert_that(gs.unit_at(Vector2i(0, 1))).is_not_null()
	assert_object(SaveGame.read_file(SCRATCH)).is_null()


func test_resume_refuses_what_it_cannot_replay() -> void:
	var b := _rig()
	b.load_map(MapCatalog.find(&"crossroads"))
	var state := b.state
	var unknown_map := SaveGame.new()
	unknown_map.map_key = &"atlantis"
	unknown_map.player_setup = [{"team": 0}, {"team": 1}]
	assert_bool(b.resume(unknown_map)).is_false()
	var bad_log := SaveGame.new()
	bad_log.map_key = &"gauntlet"
	bad_log.player_setup = [{"team": 0}, {"team": 1}]
	bad_log.action_log.append({"kind": "unit", "unit": 99, "verb": 0, "path": [[0, 0]]})
	assert_bool(b.resume(bad_log)).is_false()
	assert_object(b.state).is_same(state)  # the running match is untouched


func test_resume_brings_back_the_difficulty_and_funds() -> void:
	var b := _rig()
	var options := MatchOptions.new()
	options.map = MapCatalog.find(&"gauntlet")
	options.difficulty = &"hard"
	options.player_funds = 10000
	b.start_match(options)
	_end_turn(b)
	var saved := SaveGame.read_file(SCRATCH)
	assert_that(saved.player_setup[1]["ai"]).is_equal(&"hard")
	assert_int(saved.player_setup[0]["funds"]).is_equal(10000)
	var again: Battle = auto_free(Battle.assemble())
	add_child(again)
	again.event_player.skip_animations = true
	assert_that(again.controller.ai_profile().key).is_equal(&"normal")
	assert_bool(again.resume(saved)).is_true()
	assert_that(again.controller.ai_profile().key).is_equal(&"hard")
	assert_int(again.state.players[1].income_percent).is_equal(150)
	assert_that(Replay.digest(again.state)).is_equal(Replay.digest(b.state))
