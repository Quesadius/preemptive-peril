extends GdUnitTestSuite
## The new-match screen: it lists the shipped maps, shows the remembered
## choices, and reports what the player picks. Pressing is simulated by
## emitting the buttons' own signals, the path a click or Enter takes.


func _screen() -> MatchSetup:
	var screen: MatchSetup = auto_free(MatchSetup.new())
	add_child(screen)
	return screen


func _captions(buttons: Array[Button]) -> Array[String]:
	var out: Array[String] = []
	for b: Button in buttons:
		out.append(b.text)
	return out


func test_lists_maps_and_shows_remembered_choices() -> void:
	var screen := _screen()
	assert_bool(screen.visible).is_false()
	screen.open(MapCatalog.all(), &"gauntlet", true, false, true)
	assert_bool(screen.visible).is_true()
	var maps: Array[String] = ["Crossroads  12×10", "Gauntlet  8×12", "Highlands  18×12"]
	assert_array(_captions(screen.map_buttons())).contains_exactly(maps)
	assert_that(screen.selected_map().key).is_equal(&"gauntlet")
	var options: Array[String] = ["Fog of war: On", "Random weather: Off", "Sound: On"]
	assert_array(_captions(screen.option_buttons())).contains_exactly(options)
	# A remembered map that no longer exists falls back to the first.
	screen.open(MapCatalog.all(), &"atlantis", false, false, false)
	assert_that(screen.selected_map().key).is_equal(&"crossroads")
	screen.close()
	assert_bool(screen.visible).is_false()


func test_start_reports_the_map_and_options_chosen() -> void:
	var screen := _screen()
	screen.open(MapCatalog.all(), &"crossroads", false, false, true)
	var started: Array = []
	screen.start_requested.connect(
		func(map: MapDefinition, fog: bool, weather: bool) -> void:
			started.append([map.key, fog, weather])
	)
	screen.map_buttons()[2].button_pressed = true  # Highlands; the group unpicks Crossroads
	assert_bool(screen.map_buttons()[0].button_pressed).is_false()
	var weather := screen.option_buttons()[1]
	weather.button_pressed = true
	assert_that(weather.text).is_equal("Random weather: On")
	screen.start_button().pressed.emit()
	assert_array(started).contains_exactly([[&"highlands", false, true]])


func test_sound_toggle_reports_at_once() -> void:
	var screen := _screen()
	screen.open(MapCatalog.all(), &"crossroads", false, false, true)
	var heard: Array[bool] = []
	screen.sound_toggled.connect(func(on: bool) -> void: heard.append(on))
	var sound := screen.option_buttons()[2]
	sound.button_pressed = false
	assert_array(heard).contains_exactly([false])
	assert_that(sound.text).is_equal("Sound: Off")


func test_continue_is_offered_only_when_asked() -> void:
	var screen := _screen()
	screen.open(MapCatalog.all(), &"crossroads", false, false, true)
	assert_bool(screen.continue_button().visible).is_false()
	var resumed: Array[bool] = []
	screen.continue_requested.connect(func() -> void: resumed.append(true))
	screen.set_continue("Continue: Crossroads, day 5")
	assert_bool(screen.continue_button().visible).is_true()
	assert_that(screen.continue_button().text).is_equal("Continue: Crossroads, day 5")
	screen.continue_button().pressed.emit()
	assert_array(resumed).has_size(1)
	screen.set_continue("")
	assert_bool(screen.continue_button().visible).is_false()


func test_column_fits_the_screen() -> void:
	# The test viewport is 1280 wide: the column takes its 560 maximum.
	var screen := _screen()
	assert_that(get_viewport().get_visible_rect().size.x).is_equal(1280.0)
	assert_float(screen.column_width()).is_equal(MatchSetup.MAX_WIDTH)
