extends GdUnitTestSuite
## HUD layout: panels pinned to screen edges grow inward as their text
## fills in, and the menus center on the screen rather than hanging off
## its center point.


func test_panels_stay_on_screen_and_menus_center() -> void:
	var battle: Battle = auto_free(Battle.assemble())
	add_child(battle)
	var gs := BattleFixture.make_state()
	BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(0, 0))
	battle.load_state(gs)
	battle.cursor.move_to(Vector2i(0, 0))  # fills both info panels
	var options: Array[String] = ["Attack", "Capture", "Supply", "Wait"]
	battle.hud.action_menu.open(options)
	await get_tree().process_frame
	await get_tree().process_frame
	var screen := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var hud := battle.hud
	assert_bool(hud.unit_panel.visible).is_true()
	for panel: Control in [hud.terrain_panel, hud.unit_panel, hud.action_menu]:
		var rect := panel.get_global_rect()
		(
			assert_bool(screen.encloses(rect))
			. append_failure_message(
				"%s at %s leaves the %s screen" % [panel.get_class(), rect, screen.size]
			)
			. is_true()
		)
		assert_bool(rect.size.x > 0.0 and rect.size.y > 0.0).is_true()
	var menu_center := hud.action_menu.get_global_rect().get_center()
	assert_float(menu_center.distance_to(screen.get_center())).is_less(1.5)
	# The unit panel hugs the bottom-right corner, 8px in.
	var unit_rect := hud.unit_panel.get_global_rect()
	assert_float(unit_rect.end.x).is_equal_approx(screen.end.x - 8.0, 1.0)
	assert_float(unit_rect.end.y).is_equal_approx(screen.end.y - 8.0, 1.0)
