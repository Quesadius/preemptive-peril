class_name Weather
extends RefCounted
## Weather rules (§6): the day-start roll and expiry. Movement costs are
## already weather-indexed in TerrainType.move_costs, so all this module
## does is turn the dial deterministically through state.rng (inside
## Rules.apply, like every other roll).


## Runs at the first living player's dawn when random weather is on:
## active weather counts down and clears; clear skies may roll into rain
## or snow for 1-3 days (ruleset.weather_chance percent).
static func begin_day_roll(state: GameState) -> Array[GameEvent]:
	if not state.config.random_weather:
		return []
	var events: Array[GameEvent] = []
	if state.weather != GameState.Weather.CLEAR:
		state.weather_days_left -= 1
		if state.weather_days_left <= 0:
			state.weather = GameState.Weather.CLEAR
			state.weather_days_left = 0
			events.append(Events.WeatherChanged.new(GameState.Weather.CLEAR, 0))
		return events
	if state.rng.roll_range(0, 99) < state.ruleset.weather_chance:
		var kinds: Array[int] = [GameState.Weather.RAIN, GameState.Weather.SNOW]
		var kind: int = kinds[state.rng.roll_range(0, kinds.size() - 1)]
		var days: int = state.rng.roll_range(1, 3)
		state.weather = kind
		state.weather_days_left = days
		events.append(Events.WeatherChanged.new(kind, days))
	return events


## True when `team`'s turn opens a new day: they are the first living
## player in rotation order.
static func is_day_start(state: GameState, team: int) -> bool:
	for p: PlayerState in state.players:
		if p.is_alive:
			return p.team == team
	return false
