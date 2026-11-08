extends GdUnitTestSuite
## Drives the playable loop headless: selection, path tracing, the verb
## and build menus, target select with the damage forecast, cancels, end
## turn, AI turns, and game over. With skip_animations on, commits
## complete synchronously. Combat numbers ride on BattleFixture (luck 0)
## and are hand-computed.


func _rig() -> Battle:
	var battle: Battle = auto_free(Battle.assemble())
	add_child(battle)
	battle.event_player.skip_animations = true
	return battle


func _phase(b: Battle) -> BattleController.State:
	return b.controller.phase()


func _menu(b: Battle) -> ActionMenu:
	return b.hud.action_menu


func _choose(b: Battle, label: String) -> void:
	var items := _menu(b).items()
	var idx := items.find(label)
	assert_int(idx).append_failure_message("menu lacks %s in %s" % [label, str(items)]).is_between(
		0, 100
	)
	while _menu(b).selected_index() != idx:
		_menu(b).move_selection(1)
	_menu(b).choose_selected()


func test_select_move_wait_loop() -> void:
	var b := _rig()
	# Demo unit 1: team-0 infantry at (2,3), fresh.
	b.cursor.move_to(Vector2i(2, 3))
	b.controller.confirm()
	assert_that(_phase(b)).is_equal(BattleController.State.UNIT_SELECTED)
	assert_int(b.overlay.move_tiles.size()).is_equal(Movement.reachable(b.state, 1).size())
	b.cursor.move_to(Vector2i(2, 4))
	assert_that(_phase(b)).is_equal(BattleController.State.CHOOSING_DESTINATION)
	var expected_path: Array[Vector2i] = [Vector2i(2, 3), Vector2i(2, 4)]
	assert_array(b.overlay.path_tiles).contains_exactly(expected_path)
	b.controller.confirm()  # destination confirmed -> verb menu
	assert_that(_phase(b)).is_equal(BattleController.State.ACTION_MENU)
	var wait_only: Array[String] = ["Wait"]
	assert_array(_menu(b).items()).contains_exactly(wait_only)
	_choose(b, "Wait")
	assert_that(_phase(b)).is_equal(BattleController.State.IDLE)
	var moved := b.state.unit_at(Vector2i(2, 4))
	assert_object(moved).is_not_null()
	assert_int(moved.id).is_equal(1)
	assert_bool(moved.has_acted).is_true()
	assert_array(b.overlay.move_tiles).is_empty()
	assert_bool(_menu(b).visible).is_false()


func test_path_tracing_extends_and_truncates() -> void:
	var b := _rig()
	b.cursor.move_to(Vector2i(2, 3))
	b.controller.confirm()
	b.cursor.move_to(Vector2i(2, 4))
	b.cursor.move_to(Vector2i(3, 4))
	var traced: Array[Vector2i] = [Vector2i(2, 3), Vector2i(2, 4), Vector2i(3, 4)]
	assert_array(b.overlay.path_tiles).contains_exactly(traced)
	b.cursor.move_to(Vector2i(2, 4))  # stepping back truncates the arrow
	var truncated: Array[Vector2i] = [Vector2i(2, 3), Vector2i(2, 4)]
	assert_array(b.overlay.path_tiles).contains_exactly(truncated)


func test_cancel_is_pure_controller_state() -> void:
	var b := _rig()
	b.cursor.move_to(Vector2i(2, 3))
	b.controller.confirm()
	b.cursor.move_to(Vector2i(2, 4))
	b.controller.cancel()
	assert_that(_phase(b)).is_equal(BattleController.State.IDLE)
	assert_array(b.overlay.move_tiles).is_empty()
	assert_array(b.overlay.path_tiles).is_empty()
	var unit := b.state.unit_at(Vector2i(2, 3))
	assert_int(unit.id).is_equal(1)
	assert_bool(unit.has_acted).is_false()


func test_attack_flow_with_menu_and_forecast() -> void:
	var b := _rig()
	var gs := BattleFixture.make_state()
	var tank := BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(1, 2))
	var inf := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(2, 2))
	b.load_state(gs)
	b.cursor.move_to(Vector2i(1, 2))
	b.controller.confirm()  # select
	b.controller.confirm()  # destination = own tile -> verb menu
	assert_that(_phase(b)).is_equal(BattleController.State.ACTION_MENU)
	var expected_menu: Array[String] = ["Attack", "Wait"]
	assert_array(_menu(b).items()).contains_exactly(expected_menu)
	_choose(b, "Attack")
	assert_that(_phase(b)).is_equal(BattleController.State.TARGET_SELECT)
	var targets: Array[Vector2i] = [Vector2i(2, 2)]
	assert_array(b.overlay.target_tiles).contains_exactly(targets)
	# The cursor snaps to the target and the forecast shows immediately:
	# mg 36 -> 3.6, counter 3 -> 0.3.
	assert_that(b.cursor.coord).is_equal(Vector2i(2, 2))
	assert_bool(b.hud.damage_panel.visible).is_true()
	assert_that(b.hud.damage_panel.text()).is_equal("DMG 3.6  counter 0.3")
	b.controller.confirm()
	assert_that(_phase(b)).is_equal(BattleController.State.IDLE)
	assert_int(inf.hp).is_equal(64)
	assert_int(tank.hp).is_equal(97)
	assert_bool(tank.has_acted).is_true()
	assert_bool(b.hud.damage_panel.visible).is_false()


func test_cancel_from_target_select_reopens_menu() -> void:
	var b := _rig()
	var gs := BattleFixture.make_state()
	var tank := BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(1, 2))
	var inf := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(2, 2))
	b.load_state(gs)
	b.cursor.move_to(Vector2i(1, 2))
	b.controller.confirm()
	b.controller.confirm()
	_choose(b, "Attack")
	assert_that(_phase(b)).is_equal(BattleController.State.TARGET_SELECT)
	b.controller.cancel()
	assert_that(_phase(b)).is_equal(BattleController.State.ACTION_MENU)
	assert_bool(_menu(b).visible).is_true()
	assert_that(b.cursor.coord).is_equal(Vector2i(1, 2))  # back on the unit
	_choose(b, "Wait")
	assert_that(_phase(b)).is_equal(BattleController.State.IDLE)
	assert_int(inf.hp).is_equal(100)  # nobody got hurt
	assert_bool(tank.has_acted).is_true()


func test_capture_commits_via_menu() -> void:
	var b := _rig()
	var gs := BattleFixture.make_econ_state()
	var inf := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(2, 1))
	b.load_state(gs)
	b.cursor.move_to(Vector2i(2, 1))
	b.controller.confirm()  # select
	b.cursor.move_to(Vector2i(2, 0))  # the neutral city
	b.controller.confirm()
	assert_that(_phase(b)).is_equal(BattleController.State.ACTION_MENU)
	var expected_menu: Array[String] = ["Capture", "Wait"]
	assert_array(_menu(b).items()).contains_exactly(expected_menu)
	_choose(b, "Capture")
	assert_that(_phase(b)).is_equal(BattleController.State.IDLE)
	assert_that(inf.coord).is_equal(Vector2i(2, 0))
	assert_int(b.state.map.capture_progress[Vector2i(2, 0)]).is_equal(10)


func test_build_menu_flow() -> void:
	var b := _rig()
	var gs := BattleFixture.make_econ_state()
	BattleFixture.claim(gs, Vector2i(1, 1), 0)
	gs.players[0].funds = 1500
	b.load_state(gs)
	b.cursor.move_to(Vector2i(1, 1))
	b.controller.confirm()
	assert_that(_phase(b)).is_equal(BattleController.State.BUILD_MENU)
	var rows := b.hud.build_menu.rows()
	assert_int(rows.size()).is_equal(6)  # the whole fixture roster lists
	assert_bool(rows[0]["affordable"]).is_true()  # infantry, 1000
	assert_bool(rows[1]["affordable"]).is_false()  # tank, 7000
	# Choosing an unaffordable row does nothing.
	b.hud.build_menu.move_selection(1)
	b.hud.build_menu.choose_selected()
	assert_that(_phase(b)).is_equal(BattleController.State.BUILD_MENU)
	assert_object(b.state.unit_at(Vector2i(1, 1))).is_null()
	# Back up to infantry and build it.
	b.hud.build_menu.move_selection(-1)
	b.hud.build_menu.choose_selected()
	assert_that(_phase(b)).is_equal(BattleController.State.IDLE)
	var built := b.state.unit_at(Vector2i(1, 1))
	assert_object(built).is_not_null()
	assert_int(built.type_id).is_equal(BattleFixture.INFANTRY)
	assert_int(b.state.players[0].funds).is_equal(500)


func test_end_turn_via_system_menu() -> void:
	var b := _rig()
	b.load_state(BattleFixture.make_econ_state())
	b.cursor.move_to(Vector2i(0, 0))
	b.controller.confirm()
	assert_that(_phase(b)).is_equal(BattleController.State.ACTION_MENU)
	var end_only: Array[String] = ["End Turn"]
	assert_array(_menu(b).items()).contains_exactly(end_only)
	b.controller.cancel()  # backing out changes nothing
	assert_that(_phase(b)).is_equal(BattleController.State.IDLE)
	assert_int(b.state.current_player).is_equal(0)
	b.controller.confirm()
	_choose(b, "End Turn")
	assert_int(b.state.current_player).is_equal(1)
	assert_bool(b.hud.banner.visible).is_true()
	assert_that(b.hud.banner.text).is_equal("Day 1 — Team 1")


func test_enemy_and_exhausted_units_refuse_selection() -> void:
	var b := _rig()
	# Demo unit 2 (team 0) is exhausted; unit 5 (team 1) is the enemy's.
	b.cursor.move_to(Vector2i(1, 3))
	b.controller.confirm()
	assert_that(_phase(b)).is_equal(BattleController.State.IDLE)
	b.cursor.move_to(Vector2i(7, 3))
	b.controller.confirm()
	assert_that(_phase(b)).is_equal(BattleController.State.IDLE)
	assert_int(b.state.current_player).is_equal(0)


func test_confirm_outside_range_is_ignored() -> void:
	var b := _rig()
	b.cursor.move_to(Vector2i(2, 3))
	b.controller.confirm()
	b.cursor.move_to(Vector2i(9, 7))  # far outside infantry range
	b.controller.confirm()
	assert_that(_phase(b)).is_equal(BattleController.State.CHOOSING_DESTINATION)
	assert_bool(b.state.unit_at(Vector2i(2, 3)).has_acted).is_false()


func test_hud_status_and_panels_follow_cursor() -> void:
	var b := _rig()
	assert_bool(b.hud.status_label.text.contains("Day 1")).is_true()
	assert_bool(b.hud.status_label.text.contains("Funds")).is_true()
	b.cursor.move_to(Vector2i(2, 3))  # demo infantry on a road
	assert_bool(b.hud.unit_panel.visible).is_true()
	assert_bool(b.hud.unit_panel.title_text().contains("Md Tank")).is_true()
	assert_bool(b.hud.terrain_panel.name_text().contains("Road")).is_true()
	b.cursor.move_to(Vector2i(0, 0))  # empty plains
	assert_bool(b.hud.unit_panel.visible).is_false()
	assert_that(b.hud.terrain_panel.name_text()).is_equal("Plains")
	b.cursor.move_to(Vector2i(7, 3))  # the demo's damaged infantry
	assert_bool(b.hud.unit_panel.stats_text().contains("HP 6")).is_true()


func test_ai_plays_its_whole_turn_after_human_ends() -> void:
	var b := _rig()
	var gs := BattleFixture.make_econ_state()
	gs.players[1].is_ai = true
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 2))
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(4, 0))
	b.load_state(gs)
	b.cursor.move_to(Vector2i(0, 0))
	b.controller.confirm()
	_choose(b, "End Turn")  # human ends; AI turn runs synchronously
	assert_int(b.state.current_player).is_equal(0)
	assert_int(b.state.day).is_equal(2)
	assert_that(_phase(b)).is_equal(BattleController.State.IDLE)


func test_game_over_announces_and_restarts() -> void:
	var b := _rig()
	var gs := BattleFixture.make_state()
	BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(1, 2))
	var doomed := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(2, 2))
	doomed.hp = 20
	b.load_state(gs)
	b.cursor.move_to(Vector2i(1, 2))
	b.controller.confirm()
	b.controller.confirm()
	_choose(b, "Attack")
	b.cursor.move_to(Vector2i(2, 2))
	b.controller.confirm()  # kill -> rout -> game over
	assert_that(_phase(b)).is_equal(BattleController.State.GAME_OVER)
	assert_bool(b.state.units.has(doomed.id)).is_false()
	assert_bool(b.hud.result_panel.visible).is_true()
	assert_str(b.hud.result_text()).is_equal(
		"Victory!\nThe enemy army is routed.\nPress Enter to play again."
	)
	# Play is frozen: the cursor roams but selects nothing.
	b.cursor.move_to(Vector2i(1, 2))
	assert_that(_phase(b)).is_equal(BattleController.State.GAME_OVER)
	# Confirm starts a new match — the demo, since this state wasn't
	# built from an authored map.
	var finished := b.state
	b.controller.confirm()
	assert_that(_phase(b)).is_equal(BattleController.State.IDLE)
	assert_object(b.state).is_not_same(finished)
	assert_int(b.state.map.width).is_equal(10)  # the demo board
	assert_bool(b.hud.result_panel.visible).is_false()


func test_hq_capture_wins_through_the_ui() -> void:
	# Blue keeps a factory and a tank; only the HQ falls.
	var b := _rig()
	var gs := BattleFixture.make_econ_state()
	gs.map.terrain[gs.map.idx(Vector2i(2, 0))] = BattleFixture.HQ
	BattleFixture.claim(gs, Vector2i(2, 0), 1)
	BattleFixture.claim(gs, Vector2i(3, 1), 1)
	BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(4, 2))
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(2, 0))
	gs.map.capture_progress[Vector2i(2, 0)] = 10
	b.load_state(gs)
	b.cursor.move_to(Vector2i(2, 0))
	b.controller.confirm()
	b.controller.confirm()  # stay put -> verb menu
	_choose(b, "Capture")
	assert_that(_phase(b)).is_equal(BattleController.State.GAME_OVER)
	assert_str(b.hud.result_text()).is_equal(
		"Victory!\nEnemy HQ captured.\nPress Enter to play again."
	)
	# The losing side's wording, for when the AI takes yours.
	assert_str(BattleController.result_text(false, &"hq_captured")).is_equal(
		"Defeat\nYour HQ has fallen.\nPress Enter to play again."
	)


func test_unload_flow_via_menu_and_target_select() -> void:
	var b := _rig()
	var gs := BattleFixture.make_econ_state()
	var apc := BattleFixture.spawn(gs, BattleFixture.APC, 0, Vector2i(2, 2))
	var rider := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(1, 2))
	var board := UnitAction.new()
	board.unit_id = rider.id
	board.path = [Vector2i(1, 2), Vector2i(2, 2)]
	board.verb = UnitAction.Verb.LOAD
	Rules.apply(gs, board)
	Rules.apply(gs, EndTurnAction.new())
	Rules.apply(gs, EndTurnAction.new())  # back to team 0, fresh
	b.load_state(gs)
	b.cursor.move_to(Vector2i(2, 2))
	b.controller.confirm()  # select the APC
	b.controller.confirm()  # destination = own tile -> verb menu
	assert_that(_phase(b)).is_equal(BattleController.State.ACTION_MENU)
	assert_bool(_menu(b).items().has("Unload")).is_true()
	_choose(b, "Unload")
	assert_that(_phase(b)).is_equal(BattleController.State.TARGET_SELECT)
	assert_bool(b.overlay.target_tiles.has(Vector2i(2, 1))).is_true()
	b.cursor.move_to(Vector2i(2, 1))
	assert_bool(b.hud.damage_panel.visible).is_false()  # drops show no forecast
	b.controller.confirm()
	assert_that(_phase(b)).is_equal(BattleController.State.IDLE)
	assert_that(rider.coord).is_equal(Vector2i(2, 1))
	assert_int(rider.carrier_id).is_equal(-1)
	assert_array(apc.cargo).is_empty()
	assert_object(b.unit_layer.view_for(rider.id)).is_not_null()


func test_enemy_inspection_shows_ranges_and_clears() -> void:
	var b := _rig()
	var gs := BattleFixture.make_state()
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	var foe := BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(2, 2))
	b.load_state(gs)
	b.cursor.move_to(Vector2i(2, 2))
	b.controller.confirm()  # inspect, don't select
	assert_that(_phase(b)).is_equal(BattleController.State.IDLE)
	assert_int(b.overlay.move_tiles.size()).is_equal(Movement.reachable(b.state, foe.id).size())
	assert_array(b.overlay.target_tiles).contains_exactly(Threat.danger_zone(b.state, foe.id))
	assert_bool(foe.has_acted).is_false()  # pure display, no core call
	# Any cursor movement dismisses the reading.
	b.cursor.move_to(Vector2i(1, 2))
	assert_array(b.overlay.move_tiles).is_empty()
	assert_array(b.overlay.target_tiles).is_empty()
	# And normal selection still works right after.
	b.cursor.move_to(Vector2i(0, 0))
	b.controller.confirm()
	assert_that(_phase(b)).is_equal(BattleController.State.UNIT_SELECTED)


func test_hidden_enemy_tile_behaves_like_empty_ground() -> void:
	var b := _rig()
	var gs := BattleFixture.make_state()
	gs.config.fog_enabled = true
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(0, 3))  # beyond vision 2
	b.load_state(gs)
	b.cursor.move_to(Vector2i(0, 3))
	b.controller.confirm()
	# No inspection, no silent refusal: the system menu opens exactly as
	# it would on any empty tile.
	assert_that(_phase(b)).is_equal(BattleController.State.ACTION_MENU)
	var end_only: Array[String] = ["End Turn"]
	assert_array(_menu(b).items()).contains_exactly(end_only)
	assert_array(b.overlay.target_tiles).is_empty()


func test_danger_map_toggle_persists_and_refreshes() -> void:
	var b := _rig()
	var gs := BattleFixture.make_state()
	BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(2, 1))
	var doomed := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(0, 1))
	doomed.hp = 20
	BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(4, 4))
	b.load_state(gs)
	b.controller.toggle_danger()
	var before := b.overlay.danger_tiles.duplicate()
	assert_array(before).contains_exactly(Threat.team_danger_zone(b.state, 0))
	assert_bool(before.is_empty()).is_false()
	# The map survives selection (clear() spares the danger channel)…
	b.cursor.move_to(Vector2i(2, 1))
	b.controller.confirm()
	assert_bool(b.overlay.danger_tiles.is_empty()).is_false()
	# …and refreshes after the kill removes one threat source.
	b.cursor.move_to(Vector2i(1, 1))
	b.controller.confirm()
	_choose(b, "Attack")
	b.cursor.move_to(Vector2i(0, 1))
	b.controller.confirm()
	assert_bool(b.state.units.has(doomed.id)).is_false()
	var after := b.overlay.danger_tiles
	assert_array(after).contains_exactly(Threat.team_danger_zone(b.state, 0))
	assert_bool(after.size() < before.size()).is_true()
	b.controller.toggle_danger()
	assert_array(b.overlay.danger_tiles).is_empty()


func test_target_select_cycles_with_arrows() -> void:
	var b := _rig()
	var gs := BattleFixture.make_state()
	BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(1, 2))
	var north := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(1, 1))
	var east := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(2, 2))
	b.load_state(gs)
	b.cursor.move_to(Vector2i(1, 2))
	b.controller.confirm()
	b.controller.confirm()
	_choose(b, "Attack")
	# Snap to the row-major first target, forecast up.
	assert_that(b.cursor.coord).is_equal(Vector2i(1, 1))
	assert_bool(b.hud.damage_panel.visible).is_true()
	# Cycle forward, wrap, and back.
	b.controller.cycle_target(1)
	assert_that(b.cursor.coord).is_equal(Vector2i(2, 2))
	b.controller.cycle_target(1)
	assert_that(b.cursor.coord).is_equal(Vector2i(1, 1))
	b.controller.cycle_target(-1)
	assert_that(b.cursor.coord).is_equal(Vector2i(2, 2))
	b.controller.confirm()  # commit on the cycled selection
	assert_that(_phase(b)).is_equal(BattleController.State.IDLE)
	assert_int(east.hp).is_equal(64)  # mg 36 on plains
	assert_int(north.hp).is_equal(100)  # spared
