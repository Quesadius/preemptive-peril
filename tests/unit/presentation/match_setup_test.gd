extends GdUnitTestSuite
## The new-match screen: it lists the shipped maps, shows the remembered
## choices, and reports what the player picks. Pressing is simulated by
## emitting the buttons' own signals, the path a click or Enter takes.

const FUNDS: Array[int] = [0, 5000, 10000]


func _screen() -> MatchSetup:
	var screen: MatchSetup = auto_free(MatchSetup.new())
	add_child(screen)
	return screen


## Opens `screen` with the shipped maps and levels and these choices.
func _open(screen: MatchSetup, remembered: MatchOptions, sound: bool = true) -> void:
	screen.open(
		MapCatalog.all(), AIProfileCatalog.all(), PackedInt32Array(FUNDS), remembered, sound
	)


func _remembered(map_key: StringName) -> MatchOptions:
	var options := MatchOptions.new()
	options.map = MapCatalog.find(map_key)
	return options


func _captions(buttons: Array[Button]) -> Array[String]:
	var out: Array[String] = []
	for b: Button in buttons:
		out.append(b.text)
	return out


func test_lists_maps_and_shows_remembered_choices() -> void:
	var screen := _screen()
	assert_bool(screen.visible).is_false()
	var remembered := _remembered(&"gauntlet")
	remembered.fog = true
	remembered.difficulty = &"hard"
	remembered.enemy_funds = 5000
	_open(screen, remembered)
	assert_bool(screen.visible).is_true()
	var maps: Array[String] = ["Crossroads  12×10", "Gauntlet  8×12", "Highlands  18×12"]
	assert_array(_captions(screen.map_buttons())).contains_exactly(maps)
	assert_that(screen.selected_map().key).is_equal(&"gauntlet")
	var options: Array[String] = ["Fog of war: On", "Random weather: Off", "Sound: On"]
	assert_array(_captions(screen.option_buttons())).contains_exactly(options)
	var choices: Array[String] = ["Difficulty: Hard", "Your funds: 0", "Enemy funds: 5,000"]
	assert_array(_captions(screen.choice_buttons())).contains_exactly(choices)
	assert_that(screen.level_note()).is_equal("The computer earns 50% more from its properties.")
	screen.close()
	assert_bool(screen.visible).is_false()


func test_choices_no_longer_on_offer_fall_back() -> void:
	# An unknown map, level and funds amount (say, from an older build's
	# settings): the first map, Normal, and no head start.
	var screen := _screen()
	var stale := MatchOptions.new()
	stale.map = null
	stale.difficulty = &"nightmare"
	stale.player_funds = 7777
	_open(screen, stale, false)
	assert_that(screen.selected_map().key).is_equal(&"crossroads")
	var choices: Array[String] = ["Difficulty: Normal", "Your funds: 0", "Enemy funds: 0"]
	assert_array(_captions(screen.choice_buttons())).contains_exactly(choices)
	assert_that(screen.level_note()).is_equal("An even fight.")
	assert_that(screen.option_buttons()[2].text).is_equal("Sound: Off")


func test_start_reports_everything_chosen() -> void:
	var screen := _screen()
	_open(screen, _remembered(&"crossroads"))
	var started: Array[MatchOptions] = []
	screen.start_requested.connect(func(options: MatchOptions) -> void: started.append(options))
	screen.map_buttons()[2].button_pressed = true  # Highlands; the group unpicks Crossroads
	assert_bool(screen.map_buttons()[0].button_pressed).is_false()
	var weather := screen.option_buttons()[1]
	weather.button_pressed = true
	assert_that(weather.text).is_equal("Random weather: On")
	# Each press steps to the next choice and wraps: Normal -> Hard -> Easy.
	var difficulty := screen.choice_buttons()[0]
	difficulty.pressed.emit()
	assert_that(difficulty.text).is_equal("Difficulty: Hard")
	difficulty.pressed.emit()
	assert_that(difficulty.text).is_equal("Difficulty: Easy")
	assert_bool(screen.level_note().begins_with("The computer earns a third less")).is_true()
	# The two sides' funds step independently: yours twice, the enemy's once.
	var yours := screen.choice_buttons()[1]
	var theirs := screen.choice_buttons()[2]
	yours.pressed.emit()
	yours.pressed.emit()
	theirs.pressed.emit()
	assert_that(yours.text).is_equal("Your funds: 10,000")
	assert_that(theirs.text).is_equal("Enemy funds: 5,000")
	screen.start_button().pressed.emit()
	assert_int(started.size()).is_equal(1)
	var options := started[0]
	assert_that(options.map.key).is_equal(&"highlands")
	assert_bool(options.fog).is_false()
	assert_bool(options.weather).is_true()
	assert_that(options.difficulty).is_equal(&"easy")
	assert_int(options.player_funds).is_equal(10000)
	assert_int(options.enemy_funds).is_equal(5000)
	# A third press wraps your funds back to nothing.
	yours.pressed.emit()
	assert_that(yours.text).is_equal("Your funds: 0")


func test_sound_toggle_reports_at_once() -> void:
	var screen := _screen()
	_open(screen, _remembered(&"crossroads"))
	var heard: Array[bool] = []
	screen.sound_toggled.connect(func(on: bool) -> void: heard.append(on))
	var sound := screen.option_buttons()[2]
	sound.button_pressed = false
	assert_array(heard).contains_exactly([false])
	assert_that(sound.text).is_equal("Sound: Off")


func test_continue_is_offered_only_when_asked() -> void:
	var screen := _screen()
	_open(screen, _remembered(&"crossroads"))
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
