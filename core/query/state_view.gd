class_name StateView
extends RefCounted
## Read-only projection of GameState for one team (§6). The AI consumes
## this and never GameState itself — cheating requires a deliberate
## bypass rather than being the default. Until the fog milestone the
## projection is total; fog filtering will land here, invisible to
## callers.
##
## Contract: everything returned is for READING. Mutation goes through
## actions submitted to Rules (or apply() here), nowhere else.

var team: int

var _state: GameState


## Builds the view `team` is entitled to.
static func for_team(state: GameState, p_team: int) -> StateView:
	var view := StateView.new()
	view._state = state
	view.team = p_team
	return view


## Every legal action right now — empty when it isn't this team's turn.
## Honest under fog: the generator itself consults Fog for occupants and
## targets, so nothing here aims at units this team cannot see.
func legal_actions() -> Array[Action]:
	if _state.active_player().team != team:
		return []
	return ActionGenerator.generate(_state)


## Rules.validate passthrough.
func validate(action: Action) -> ActionError:
	return Rules.validate(_state, action)


## Rules.apply passthrough — the sanctioned way an AI driver executes
## the action it chose.
func apply(action: Action) -> Array[GameEvent]:
	return Rules.apply(_state, action)


## This team's funds.
func my_funds() -> int:
	var player := Economy.player_of(_state, team)
	return player.funds if player != null else 0


## The unit with this id, or null.
func unit(unit_id: int) -> UnitState:
	if _state.units.has(unit_id):
		return _state.units[unit_id]
	return null


## The unit on `coord` as far as this team knows — invisible enemies
## read as an empty tile.
func unit_at(coord: Vector2i) -> UnitState:
	return Fog.known_occupant(_state, team, coord)


## Units this team may know about — fog hides the rest. Sorted by id.
func visible_units() -> Array[UnitState]:
	var out: Array[UnitState] = []
	var mask := Fog.mask_for(_state, team)
	for uid: int in _state.units:
		var u: UnitState = _state.units[uid]
		if Fog.sees_unit(_state, team, u, mask):
			out.append(u)
	out.sort_custom(func(a: UnitState, b: UnitState) -> bool: return a.id < b.id)
	return out


## This team's units, sorted by id.
func my_units() -> Array[UnitState]:
	return _state.units_of(team)


## The terrain/ownership grid (read-only by contract).
func map() -> MapState:
	return _state.map


## The balance data.
func ruleset() -> Ruleset:
	return _state.ruleset


## Luckless damage forecast.
func preview_attack(attacker_id: int, defender_id: int) -> Combat.DamagePreview:
	return Combat.preview(_state, attacker_id, defender_id)


## Movement.reachable passthrough, for AI positioning maps.
func reachable_of(unit_id: int) -> Dictionary[Vector2i, int]:
	return Movement.reachable(_state, unit_id)
