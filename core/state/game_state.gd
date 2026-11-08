class_name GameState
extends RefCounted
## The root aggregate: everything needed to reconstruct the game exactly.
##
## Mutated only by Rules.apply(); presentation and AI read, never write.
## `occupancy` is a derived index — rebuilt on load, maintained on every
## move — turning "who is on this tile" from O(n) into O(1).

## Global weather condition. Declared here (not in a rules module) because
## the `weather` field needs it from milestone 1; weather *rules* come later.
enum Weather { CLEAR, RAIN, SNOW }

var ruleset: Ruleset  # data, not owned
var config: GameConfig
var map: MapState
var units: Dictionary[int, UnitState] = {}  # id -> unit
var occupancy: Dictionary[Vector2i, int] = {}  # coord -> unit id (derived, kept in sync)
var players: Array[PlayerState] = []
var current_player: int = 0
var day: int = 1
var weather: int = Weather.CLEAR
var weather_days_left: int = 0
var rng: DeterministicRng
var next_unit_id: int = 1


## Deep copy for AI search. Mutable state (map, units, occupancy, players,
## rng) is copied; `ruleset` and `config` are immutable data and shared.
func clone() -> GameState:
	var copy := GameState.new()
	copy.ruleset = ruleset
	copy.config = config
	copy.map = map.clone()
	for uid: int in units:
		copy.units[uid] = units[uid].clone()
	for c: Vector2i in occupancy:
		copy.occupancy[c] = occupancy[c]
	for p: PlayerState in players:
		copy.players.append(p.clone())
	copy.current_player = current_player
	copy.day = day
	copy.weather = weather
	copy.weather_days_left = weather_days_left
	copy.rng = rng.clone()
	copy.next_unit_id = next_unit_id
	return copy


## The unit occupying `coord`, or null if the tile is empty.
func unit_at(coord: Vector2i) -> UnitState:
	if not occupancy.has(coord):
		return null
	return units[occupancy[coord]]


## Every unit belonging to `team`, loaded cargo included, sorted by id so
## the result is reproducible regardless of dictionary insertion history.
func units_of(team: int) -> Array[UnitState]:
	var out: Array[UnitState] = []
	for uid: int in units:
		var u: UnitState = units[uid]
		if u.team == team:
			out.append(u)
	out.sort_custom(func(a: UnitState, b: UnitState) -> bool: return a.id < b.id)
	return out


## The player whose turn it is.
func active_player() -> PlayerState:
	return players[current_player]
