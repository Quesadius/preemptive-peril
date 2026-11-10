extends GdUnitTestSuite
## Match options and the hand-off to the setup screen: fog and weather
## reach the match config, a restart keeps them, and with a listener
## attached "play again" and "Quit to menu" ask for a new match instead
## of restarting in place. Plus the weather readout that makes the
## weather option visible in play.


func _rig() -> Battle:
	var battle: Battle = auto_free(Battle.assemble())
	add_child(battle)
	battle.event_player.skip_animations = true
	return battle


func test_fog_and_weather_reach_the_match_and_survive_a_restart() -> void:
	var b := _rig()
	b.load_map(MapCatalog.find(&"gauntlet"), true, true)
	assert_bool(b.state.config.fog_enabled).is_true()
	assert_bool(b.state.config.random_weather).is_true()
	assert_int(b.state.map.width).is_equal(8)
	assert_bool(b.fog_layer.mask().is_empty()).is_false()  # the shroud is drawn
	var first := b.state
	b.play_again()
	assert_object(b.state).is_not_same(first)
	assert_bool(b.state.config.fog_enabled).is_true()
	assert_bool(b.state.config.random_weather).is_true()
	# Defaults stay off.
	b.load_map(MapCatalog.find(&"gauntlet"))
	assert_bool(b.state.config.fog_enabled).is_false()
	assert_bool(b.state.config.random_weather).is_false()


func test_quit_to_menu_is_offered_only_with_a_listener() -> void:
	var b := _rig()
	b.load_map(MapCatalog.find(&"crossroads"))
	b.cursor.move_to(Vector2i(0, 0))  # empty plains: the system menu
	b.controller.confirm()
	var end_only: Array[String] = ["End Turn"]
	assert_array(b.hud.action_menu.items()).contains_exactly(end_only)
	b.controller.cancel()
	# With the hand-off on, the menu gains the entry, and choosing it asks
	# for a new match without touching the one in progress.
	var asked: Array[bool] = []
	b.new_match_requested.connect(func() -> void: asked.append(true))
	b.hand_off_new_match = true
	b.controller.confirm()
	var with_quit: Array[String] = ["End Turn", "Quit to menu"]
	assert_array(b.hud.action_menu.items()).contains_exactly(with_quit)
	var state := b.state
	b.hud.action_menu.move_selection(1)
	b.hud.action_menu.choose_selected()
	assert_array(asked).has_size(1)
	assert_object(b.state).is_same(state)
	assert_int(b.state.current_player).is_equal(0)  # the turn did not end
	assert_that(b.controller.phase()).is_equal(BattleController.State.IDLE)


func test_play_again_hands_off_when_asked_to() -> void:
	var b := _rig()
	b.load_map(MapCatalog.find(&"crossroads"))
	var asked: Array[bool] = []
	b.new_match_requested.connect(func() -> void: asked.append(true))
	b.hand_off_new_match = true
	var state := b.state
	b.play_again()
	assert_array(asked).has_size(1)
	assert_object(b.state).is_same(state)  # nothing restarted here


func test_weather_shows_in_the_status_line_and_banner() -> void:
	var b := _rig()
	var gs := BattleFixture.make_state()
	b.load_state(gs)
	assert_bool(b.hud.status_label.text.contains("Rain")).is_false()
	gs.weather = GameState.Weather.RAIN
	b.hud.refresh(gs)
	assert_bool(b.hud.status_label.text.ends_with("Rain")).is_true()
	var turned: Array[GameEvent] = [Events.WeatherChanged.new(GameState.Weather.SNOW, 2)]
	b.hud.on_events(turned)
	assert_bool(b.hud.banner.visible).is_true()
	assert_that(b.hud.banner.text).is_equal("Snow — slower going")
	var cleared: Array[GameEvent] = [Events.WeatherChanged.new(GameState.Weather.CLEAR, 0)]
	b.hud.on_events(cleared)
	assert_that(b.hud.banner.text).is_equal("The skies clear")
	assert_that(Hud.weather_name(GameState.Weather.CLEAR)).is_equal("Clear")
