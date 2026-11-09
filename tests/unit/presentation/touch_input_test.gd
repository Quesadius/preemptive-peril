extends GdUnitTestSuite
## Touch polish on BattleFixture's 5x5 map: the Back/Danger bar, touch
## never hovering, and pinch zoom. The test viewport is 1280x720, so its
## center is (640, 360); camera numbers below are worked out by hand from
## the 160x160 board.


func _rig() -> Battle:
	var battle: Battle = auto_free(Battle.assemble())
	add_child(battle)
	battle.event_player.skip_animations = true
	return battle


func _screen(b: Battle, tile: Vector2i) -> Vector2:
	return b.get_viewport().get_canvas_transform() * MapRenderer.world_pos(tile)


func _finger(b: Battle, index: int, at: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = at
	e.pressed = down
	b.pointer_input._unhandled_input(e)


func _slide(b: Battle, index: int, to: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = to
	b.pointer_input._unhandled_input(e)


## The mouse event Godot synthesizes from the first finger.
func _emulated_button(b: Battle, at: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.device = InputEvent.DEVICE_ID_EMULATION
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = at
	b.pointer_input._unhandled_input(e)


func test_touch_bar_backs_out_and_toggles_danger() -> void:
	var b := _rig()
	var gs := BattleFixture.make_state()
	BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(1, 2))
	BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(4, 4))
	b.load_state(gs)
	var hud := b.hud
	assert_bool(hud.touch_bar.visible).is_false()  # off unless asked for
	hud.set_touch_mode(true)
	assert_bool(hud.touch_bar.visible).is_true()
	var back := hud.touch_bar.get_child(0) as Button
	var danger := hud.touch_bar.get_child(1) as Button
	assert_int(back.focus_mode).is_equal(Control.FOCUS_NONE)  # Enter stays on the map
	# Back steps out of a selection, like Esc.
	b.cursor.move_to(Vector2i(1, 2))
	b.controller.confirm()
	assert_that(b.controller.phase()).is_equal(BattleController.State.UNIT_SELECTED)
	back.pressed.emit()
	assert_that(b.controller.phase()).is_equal(BattleController.State.IDLE)
	# Danger toggles the map and the button shows its state, whichever
	# way it was toggled.
	danger.pressed.emit()
	assert_bool(b.overlay.danger_tiles.is_empty()).is_false()
	assert_bool(danger.button_pressed).is_true()
	b.controller.toggle_danger()  # the D key
	assert_array(b.overlay.danger_tiles).is_empty()
	assert_bool(danger.button_pressed).is_false()
	# Menu rows grow to a fingertip in touch mode, and back again.
	var options: Array[String] = ["Wait"]
	hud.action_menu.open(options)
	var row := hud.action_menu.get_child(0).get_child(0) as Control
	assert_float(row.custom_minimum_size.y).is_equal(Hud.TOUCH_ROW_HEIGHT)
	hud.set_touch_mode(false)
	hud.action_menu.open(options)
	row = hud.action_menu.get_child(0).get_child(0) as Control
	assert_float(row.custom_minimum_size.y).is_equal(0.0)
	assert_bool(hud.touch_bar.visible).is_false()


func test_touch_never_hovers_so_a_shaky_tap_only_aims() -> void:
	var b := _rig()
	var gs := BattleFixture.make_state()
	BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(1, 2))
	b.load_state(gs)
	var at := _screen(b, Vector2i(1, 2))
	var glide := InputEventMouseMotion.new()  # emulated, no button: not a hover
	glide.device = InputEvent.DEVICE_ID_EMULATION
	glide.position = at
	b.pointer_input._unhandled_input(glide)
	assert_that(b.cursor.coord).is_equal(Vector2i(2, 2))  # unmoved
	# A tap that wobbles 5px (under the 16px touch threshold) still
	# counts as a tap — and as the first one, it only aims.
	_emulated_button(b, at, true)
	var wobble := InputEventMouseMotion.new()
	wobble.device = InputEvent.DEVICE_ID_EMULATION
	wobble.button_mask = MOUSE_BUTTON_MASK_LEFT
	wobble.position = at + Vector2(5, 0)
	b.pointer_input._unhandled_input(wobble)
	_emulated_button(b, at + Vector2(5, 0), false)
	assert_that(b.cursor.coord).is_equal(Vector2i(1, 2))
	assert_that(b.controller.phase()).is_equal(BattleController.State.IDLE)
	_emulated_button(b, at, true)
	_emulated_button(b, at, false)
	assert_that(b.controller.phase()).is_equal(BattleController.State.UNIT_SELECTED)


func test_pinch_zooms_around_the_fingers_and_is_never_a_tap() -> void:
	# Zoom 4: the view is 320x180, wider and taller than the board, so the
	# camera sits centered at (80, 80). Fingers 80px apart at y=450 (90px
	# below center) spread to 120px: zoom 4 x 1.5 = 6. The board point
	# under the old midpoint, y = 80 + 90/4 = 102.5, stays under the
	# fingers: camera y = 102.5 - 90/6 = 87.5 (inside 60..100 at zoom 6).
	var b := _rig()
	b.load_state(BattleFixture.make_state())
	var rig := b.camera_rig
	rig.set_zoom(4.0)
	var cam := rig.camera
	assert_float(cam.position.y).is_equal_approx(80.0, 0.01)
	var a := Vector2(600, 450)
	_emulated_button(b, a, true)  # the first finger also arrives as a mouse press
	_finger(b, 0, a, true)
	_finger(b, 1, Vector2(680, 450), true)
	_slide(b, 1, Vector2(720, 450))
	assert_float(rig.zoom_level).is_equal_approx(6.0, 0.001)
	assert_float(cam.position.y).is_equal_approx(87.5, 0.01)
	_finger(b, 1, Vector2(720, 450), false)  # settles: 6 is already a step
	assert_float(rig.zoom_level).is_equal_approx(6.0, 0.001)
	assert_float(cam.position.y).is_equal_approx(87.5, 0.01)
	_emulated_button(b, a, false)  # the first finger's mouse release: no tap
	_finger(b, 0, a, false)
	assert_that(b.controller.phase()).is_equal(BattleController.State.IDLE)
	assert_that(b.cursor.coord).is_equal(Vector2i(2, 2))


func test_pinch_settles_on_a_crisp_zoom_step() -> void:
	# 100px apart spreading to 132.5px: 4 x 1.325 = 5.3, which settles on
	# the nearest 0.5 step, 5.5, when a finger lifts. A screen change then
	# refits: never closer than the whole-board fit (min(1280, 720) / 160
	# = 4.5 here), but a smaller zoom the player chose is kept.
	var b := _rig()
	b.load_state(BattleFixture.make_state())
	var rig := b.camera_rig
	rig.set_zoom(4.0)
	_finger(b, 0, Vector2(590, 360), true)
	_finger(b, 1, Vector2(690, 360), true)
	_slide(b, 1, Vector2(722.5, 360))
	assert_float(rig.zoom_level).is_equal_approx(5.3, 0.001)
	_finger(b, 1, Vector2(722.5, 360), false)
	assert_float(rig.zoom_level).is_equal_approx(5.5, 0.001)
	_finger(b, 0, Vector2(590, 360), false)
	rig.refit()
	assert_float(rig.zoom_level).is_equal_approx(4.5, 0.001)  # the board fits again
	for _step: int in range(3):
		rig.zoom_out()  # 4.5 -> 3.0, chosen by the player
	rig.set_zoom(1.0)
	rig.refit()
	assert_float(rig.zoom_level).is_equal_approx(3.0, 0.001)
