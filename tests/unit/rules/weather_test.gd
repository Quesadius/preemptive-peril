extends GdUnitTestSuite
## Weather rules: the day-start roll, countdown, and determinism. Costs
## per weather are already covered by the movement tests; these pin the
## dial itself.


func _stormy(chance: int) -> GameState:
	var gs := BattleFixture.make_state()
	gs.config.random_weather = true
	gs.ruleset.weather_chance = chance
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(4, 4))
	return gs


func test_no_roll_without_random_weather() -> void:
	var gs := BattleFixture.make_state()
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	for _i: int in range(10):
		var events := Rules.apply(gs, EndTurnAction.new())
		for e: GameEvent in events:
			assert_bool(e is Events.WeatherChanged).is_false()
	assert_int(gs.weather).is_equal(GameState.Weather.CLEAR)


func test_active_weather_counts_down_and_clears() -> void:
	var gs := _stormy(0)  # chance 0: no new fronts, pure countdown
	gs.weather = GameState.Weather.RAIN
	gs.weather_days_left = 2
	Rules.apply(gs, EndTurnAction.new())  # team 1's turn, same day
	assert_int(gs.weather).is_equal(GameState.Weather.RAIN)
	Rules.apply(gs, EndTurnAction.new())  # new day: countdown to 1
	assert_int(gs.weather).is_equal(GameState.Weather.RAIN)
	assert_int(gs.weather_days_left).is_equal(1)
	Rules.apply(gs, EndTurnAction.new())
	var events := Rules.apply(gs, EndTurnAction.new())  # next day: clears
	var cleared := false
	for e: GameEvent in events:
		if e is Events.WeatherChanged:
			cleared = true
			assert_int((e as Events.WeatherChanged).new_weather).is_equal(GameState.Weather.CLEAR)
	assert_bool(cleared).is_true()
	assert_int(gs.weather).is_equal(GameState.Weather.CLEAR)


func test_certain_weather_rolls_at_day_start_deterministically() -> void:
	var first := _stormy(100)
	var second := _stormy(100)
	var changed_first: Events.WeatherChanged = null
	for gs: GameState in [first, second]:
		var events := Rules.apply(gs, EndTurnAction.new())
		events.append_array(Rules.apply(gs, EndTurnAction.new()))  # crosses into day 2
		for e: GameEvent in events:
			if e is Events.WeatherChanged:
				var change := e as Events.WeatherChanged
				(
					assert_bool(
						change.new_weather in [GameState.Weather.RAIN, GameState.Weather.SNOW]
					)
					. is_true()
				)
				assert_int(change.days).is_between(1, 3)
				if changed_first == null:
					changed_first = change
				else:
					# Same seed, same roll: fully deterministic.
					assert_int(change.new_weather).is_equal(changed_first.new_weather)
					assert_int(change.days).is_equal(changed_first.days)
	assert_object(changed_first).is_not_null()
	assert_int(first.weather).is_equal(second.weather)
	assert_int(first.weather_days_left).is_equal(second.weather_days_left)


func test_day_start_detection_skips_the_dead() -> void:
	var gs := BattleFixture.make_state()
	var third := PlayerState.new()
	third.team = 2
	gs.players.append(third)
	gs.players[0].is_alive = false
	assert_bool(Weather.is_day_start(gs, 0)).is_false()
	assert_bool(Weather.is_day_start(gs, 1)).is_true()
	assert_bool(Weather.is_day_start(gs, 2)).is_false()
