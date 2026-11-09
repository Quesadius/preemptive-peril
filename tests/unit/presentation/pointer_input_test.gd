extends GdUnitTestSuite
## Mouse and touch through PointerInput, driven with synthetic events on
## BattleFixture's 5x5 map. Screen positions come from the viewport's own
## canvas transform, so each event lands on the intended tile whatever
## the camera is doing.


func _rig() -> Battle:
	var battle: Battle = auto_free(Battle.assemble())
	add_child(battle)
	battle.event_player.skip_animations = true
	return battle


func _screen(b: Battle, tile: Vector2i) -> Vector2:
	return b.get_viewport().get_canvas_transform() * MapRenderer.world_pos(tile)


func _hover(b: Battle, tile: Vector2i) -> void:
	var e := InputEventMouseMotion.new()
	e.position = _screen(b, tile)
	b.pointer_input._unhandled_input(e)


func _click(b: Battle, tile: Vector2i, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	for pressed: bool in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = button
		e.pressed = pressed
		e.position = _screen(b, tile)
		b.pointer_input._unhandled_input(e)


func _row_event(menu: Control, index: int, event: InputEvent) -> void:
	var row := menu.get_child(0).get_child(index) as Control
	row.gui_input.emit(event)


func _release(button: MouseButton = MOUSE_BUTTON_LEFT) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = false
	return e


func _click_row(b: Battle, label: String) -> void:
	var index := b.hud.action_menu.items().find(label)
	assert_int(index).append_failure_message("menu lacks %s" % label).is_not_equal(-1)
	_row_event(b.hud.action_menu, index, _release())


func _phase(b: Battle) -> BattleController.State:
	return b.controller.phase()


func test_hover_aims_and_click_confirms() -> void:
	var b := _rig()
	var gs := BattleFixture.make_state()
	var tank := BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(1, 2))
	b.load_state(gs)
	_hover(b, Vector2i(1, 2))
	assert_that(b.cursor.coord).is_equal(Vector2i(1, 2))
	assert_bool(b.cursor.pointer_driven).is_true()
	_click(b, Vector2i(1, 2))
	assert_that(_phase(b)).is_equal(BattleController.State.UNIT_SELECTED)
	_hover(b, Vector2i(2, 2))  # the route follows the pointer
	var route: Array[Vector2i] = [Vector2i(1, 2), Vector2i(2, 2)]
	assert_array(b.overlay.path_tiles).contains_exactly(route)
	_click(b, Vector2i(2, 2))
	assert_that(_phase(b)).is_equal(BattleController.State.ACTION_MENU)
	var wait_only: Array[String] = ["Wait"]
	assert_array(b.hud.action_menu.items()).contains_exactly(wait_only)
	_click_row(b, "Wait")
	assert_that(_phase(b)).is_equal(BattleController.State.IDLE)
	assert_that(tank.coord).is_equal(Vector2i(2, 2))
	# Read-only panels let the pointer reach the map beneath them.
	assert_int(b.hud.terrain_panel.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int(b.hud.terrain_panel.get_child(0).mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


func test_taps_without_hover_take_two() -> void:
	# Touch has no hover: the first tap aims, the second confirms.
	var b := _rig()
	var gs := BattleFixture.make_state()
	BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(1, 2))
	b.load_state(gs)
	assert_that(b.cursor.coord).is_equal(Vector2i(2, 2))  # centered by present()
	_click(b, Vector2i(1, 2))
	assert_that(b.cursor.coord).is_equal(Vector2i(1, 2))
	assert_that(_phase(b)).is_equal(BattleController.State.IDLE)
	_click(b, Vector2i(1, 2))
	assert_that(_phase(b)).is_equal(BattleController.State.UNIT_SELECTED)


func test_right_click_tap_away_and_click_outside_menu_back_out() -> void:
	var b := _rig()
	var gs := BattleFixture.make_state()
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))  # move 3
	b.load_state(gs)
	_hover(b, Vector2i(0, 0))
	_click(b, Vector2i(0, 0))
	assert_that(_phase(b)).is_equal(BattleController.State.UNIT_SELECTED)
	_click(b, Vector2i(3, 3), MOUSE_BUTTON_RIGHT)
	assert_that(_phase(b)).is_equal(BattleController.State.IDLE)
	# Tapping outside the blue range (8 tiles away) deselects at once.
	_click(b, Vector2i(0, 0))
	_click(b, Vector2i(4, 4))
	assert_that(_phase(b)).is_equal(BattleController.State.IDLE)
	# A click on the map while the menu is open backs out of the menu.
	_click(b, Vector2i(0, 0))
	_click(b, Vector2i(0, 0))  # stay put -> verb menu
	assert_that(_phase(b)).is_equal(BattleController.State.ACTION_MENU)
	_click(b, Vector2i(3, 3))
	assert_bool(b.hud.action_menu.visible).is_false()
	assert_that(_phase(b)).is_equal(BattleController.State.CHOOSING_DESTINATION)


func test_drag_pans_the_camera_and_is_not_a_click() -> void:
	# Zoom 6 on the 160px-square board: the view is 120px tall, so the
	# camera can travel vertically between y = 60 and y = 100.
	var b := _rig()
	var gs := BattleFixture.make_state()
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(2, 2))
	b.load_state(gs)
	b.camera_rig.set_zoom(6.0)
	var cam := b.camera_rig.camera
	assert_float(cam.position.y).is_equal_approx(80.0, 0.01)  # centered on (2,2)
	var start := _screen(b, Vector2i(2, 2))
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = start
	b.pointer_input._unhandled_input(press)
	var drag := InputEventMouseMotion.new()
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	drag.position = start + Vector2(0, -20)  # past the 8px threshold
	drag.relative = Vector2(0, -60)  # 60 screen px up = 10 world px down
	b.pointer_input._unhandled_input(drag)
	assert_float(cam.position.y).is_equal_approx(90.0, 0.01)
	drag.relative = Vector2(0, -600)
	b.pointer_input._unhandled_input(drag)
	assert_float(cam.position.y).is_equal_approx(100.0, 0.01)  # clamped at the edge
	var release := _release()
	release.position = start
	b.pointer_input._unhandled_input(release)
	# The press began on the infantry, but a drag never selects.
	assert_that(_phase(b)).is_equal(BattleController.State.IDLE)


func test_camera_ignores_pointer_moves_but_follows_keys() -> void:
	var b := _rig()
	b.load_state(BattleFixture.make_state())
	var rig := b.camera_rig
	rig.set_zoom(6.0)
	rig.dead_zone = Vector2(8, 8)
	var cam := rig.camera
	_hover(b, Vector2i(2, 4))  # 64px below the camera center
	rig._process(0.016)
	assert_float(cam.position.y).is_equal_approx(80.0, 0.01)
	# The same move from the keyboard is followed: 64 - 8 dead zone = 56.
	b.cursor.move_to(Vector2i(2, 2))
	b.cursor.move_to(Vector2i(2, 4))
	rig._process(0.016)
	assert_float(cam.position.y).is_equal_approx(136.0, 0.01)


func test_menu_rows_follow_the_pointer() -> void:
	var menu: ActionMenu = auto_free(ActionMenu.new())
	add_child(menu)
	var picks: Array[int] = []
	var backs: Array[bool] = []
	menu.chosen.connect(func(i: int) -> void: picks.append(i))
	menu.cancelled.connect(func() -> void: backs.append(true))
	var options: Array[String] = ["Attack", "Wait"]
	menu.open(options)
	_row_event(menu, 1, InputEventMouseMotion.new())
	assert_int(menu.selected_index()).is_equal(1)  # hover highlights
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	_row_event(menu, 0, press)
	assert_array(picks).is_empty()  # choosing waits for the release
	_row_event(menu, 0, _release())
	assert_array(picks).contains_exactly([0])
	assert_bool(menu.visible).is_false()
	menu.open(options)
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	_row_event(menu, 1, right)
	assert_array(backs).has_size(1)
	# The build menu: an unaffordable row stays put; an affordable one builds.
	var builds: BuildMenu = auto_free(BuildMenu.new())
	add_child(builds)
	var built: Array[int] = []
	builds.chosen.connect(func(type_id: int) -> void: built.append(type_id))
	var rows: Array[Dictionary] = [
		{"type_id": BattleFixture.TANK, "label": "Tank", "affordable": false},
		{"type_id": BattleFixture.INFANTRY, "label": "Infantry", "affordable": true},
	]
	builds.open(rows)
	_row_event(builds, 0, _release())
	assert_bool(builds.visible).is_true()
	_row_event(builds, 1, _release())
	assert_array(built).contains_exactly([BattleFixture.INFANTRY])


func test_a_whole_fight_by_mouse_ends_and_restarts() -> void:
	var b := _rig()
	var gs := BattleFixture.make_state()
	BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(1, 2))
	var doomed := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(2, 2))
	doomed.hp = 20
	b.load_state(gs)
	_hover(b, Vector2i(1, 2))
	_click(b, Vector2i(1, 2))  # select
	_click(b, Vector2i(1, 2))  # stay put -> verb menu
	_click_row(b, "Attack")  # the cursor snaps onto the only target
	assert_that(b.cursor.coord).is_equal(Vector2i(2, 2))
	_click(b, Vector2i(2, 2))  # fire: the kill routs blue
	assert_that(_phase(b)).is_equal(BattleController.State.GAME_OVER)
	assert_bool(b.hud.result_panel.visible).is_true()
	var finished := b.state
	_click(b, Vector2i(0, 0))  # a click anywhere plays again
	assert_that(_phase(b)).is_equal(BattleController.State.IDLE)
	assert_object(b.state).is_not_same(finished)
	assert_bool(b.hud.result_panel.visible).is_false()


func test_clicking_off_the_targets_backs_out_of_aiming() -> void:
	# Touch has no right-click, so a tap on anything but a target backs
	# out to the verb menu; a tap on the target still fires.
	var b := _rig()
	var gs := BattleFixture.make_state()
	BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(1, 2))
	var foe := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(2, 2))
	b.load_state(gs)
	_hover(b, Vector2i(1, 2))
	_click(b, Vector2i(1, 2))
	_click(b, Vector2i(1, 2))
	_click_row(b, "Attack")
	assert_that(_phase(b)).is_equal(BattleController.State.TARGET_SELECT)
	_click(b, Vector2i(4, 4))
	assert_that(_phase(b)).is_equal(BattleController.State.ACTION_MENU)
	_click_row(b, "Attack")
	_click(b, Vector2i(2, 2))
	assert_int(foe.hp).is_less(100)  # the shot landed
