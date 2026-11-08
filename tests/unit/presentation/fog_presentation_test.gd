extends GdUnitTestSuite
## Presentation under fog: the shroud layer masks unlit tiles and the
## unit layer only shows what the viewing team can see.


func _rig() -> Battle:
	var battle: Battle = auto_free(Battle.assemble())
	add_child(battle)
	battle.event_player.skip_animations = true
	return battle


func test_fog_layer_and_unit_filtering() -> void:
	var b := _rig()
	var gs := BattleFixture.make_state()
	gs.config.fog_enabled = true
	var mine := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	var far_foe := BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(4, 4))
	b.load_state(gs)
	# The shroud is active and matches Fog.compute for team 0.
	var mask := b.fog_layer.mask()
	assert_bool(mask.is_empty()).is_false()
	assert_int(mask[gs.map.idx(Vector2i(0, 1))]).is_equal(1)
	assert_int(mask[gs.map.idx(Vector2i(4, 4))]).is_equal(0)
	# Own unit rendered, unseen enemy not.
	assert_object(b.unit_layer.view_for(mine.id)).is_not_null()
	assert_object(b.unit_layer.view_for(far_foe.id)).is_null()


func test_fog_off_renders_everything_and_no_shroud() -> void:
	var b := _rig()
	var gs := BattleFixture.make_state()
	var mine := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	var far_foe := BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(4, 4))
	b.load_state(gs)
	assert_bool(b.fog_layer.mask().is_empty()).is_true()
	assert_object(b.unit_layer.view_for(mine.id)).is_not_null()
	assert_object(b.unit_layer.view_for(far_foe.id)).is_not_null()


func test_enemy_appears_when_walked_into_view() -> void:
	var b := _rig()
	var gs := BattleFixture.make_state()
	gs.config.fog_enabled = true
	var mine := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	var foe := BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(0, 4))  # dark
	b.load_state(gs)
	assert_object(b.unit_layer.view_for(foe.id)).is_null()
	# March two tiles south: the tank at distance 2 comes into view.
	b.cursor.move_to(Vector2i(0, 0))
	b.controller.confirm()
	b.cursor.move_to(Vector2i(0, 2))
	b.controller.confirm()
	b.hud.action_menu.choose_selected()  # only "Wait" is on offer
	assert_that(mine.coord).is_equal(Vector2i(0, 2))
	assert_object(b.unit_layer.view_for(foe.id)).is_not_null()


func test_hud_shows_only_what_fog_shows() -> void:
	# Econ map: neutral city at (2,0). The infantry at (0,2) sees
	# manhattan <= 2, so the city (distance 4) is dark and (2,2) is lit.
	var b := _rig()
	var gs := BattleFixture.make_econ_state()
	gs.config.fog_enabled = true
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 2))
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(2, 0))  # capturing, unseen
	gs.map.capture_progress[Vector2i(2, 0)] = 10
	BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(2, 2))  # plainly seen
	b.load_state(gs)
	b.cursor.move_to(Vector2i(2, 0))
	assert_bool(b.hud.unit_panel.visible).is_false()
	assert_bool(b.hud.terrain_panel.detail_text().contains("Capture")).is_false()
	b.cursor.move_to(Vector2i(2, 2))
	assert_bool(b.hud.unit_panel.visible).is_true()
	assert_bool(b.hud.unit_panel.title_text().begins_with("tank")).is_true()
	# Lift the fog and the same city reports its capture.
	gs.config.fog_enabled = false
	b.cursor.move_to(Vector2i(2, 0))
	assert_bool(b.hud.unit_panel.visible).is_true()
	assert_bool(b.hud.terrain_panel.detail_text().contains("Capture 10/20")).is_true()


func test_enemy_move_animation_stops_at_the_fog_edge() -> void:
	# Viewer at (2,2) lights the manhattan-2 diamond. An enemy path
	# (0,2) -> (1,2) -> (1,3) -> (1,4) -> (0,4) stays lit for two steps;
	# (1,4) is distance 3, so the tween must stop on (1,3).
	var b := _rig()
	var gs := BattleFixture.make_state()
	gs.config.fog_enabled = true
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(2, 2))
	b.load_state(gs)
	assert_int(b.event_player.perspective_team).is_equal(0)
	var path: Array[Vector2i] = [
		Vector2i(0, 2),
		Vector2i(1, 2),
		Vector2i(1, 3),
		Vector2i(1, 4),
		Vector2i(0, 4),
	]
	var e := Events.UnitMoved.new(99, path, -1)
	assert_int(b.event_player.visible_steps(e, 1)).is_equal(2)
	# Own moves are never cut short, except by an ambush.
	assert_int(b.event_player.visible_steps(e, 0)).is_equal(4)
	var ambushed := Events.UnitMoved.new(99, path, 1)
	assert_int(b.event_player.visible_steps(ambushed, 0)).is_equal(1)
	# Omniscient perspective (fog off): the whole path animates.
	b.event_player.perspective_team = -1
	assert_int(b.event_player.visible_steps(e, 1)).is_equal(4)
