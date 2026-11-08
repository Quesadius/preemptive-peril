class_name Victory
extends RefCounted
## Win/loss conditions. Provisional rule set until HQ terrain and
## campaign objectives exist: a player is routed when they JUST LOST a
## unit or property and are left with no units and no production to
## rebuild from. Loss-triggered, so armyless factory starts and empty
## test fixtures are never eliminated out of nowhere. The game ends when
## one player remains. Rules.apply() runs check() after every action.


## Evaluates eliminations triggered by this action's `events` and, when
## exactly one player is left standing, ends the game. Idempotent:
## already-dead players and untouched teams produce nothing new.
static func check(state: GameState, events: Array[GameEvent]) -> Array[GameEvent]:
	var affected: Dictionary[int, bool] = {}
	for e: GameEvent in events:
		if e is Events.UnitDestroyed:
			affected[(e as Events.UnitDestroyed).team] = true
		elif e is Events.PropertyCaptured:
			affected[(e as Events.PropertyCaptured).old_team] = true
	if affected.is_empty():
		return []
	var out: Array[GameEvent] = []
	var newly_dead: bool = false
	for p: PlayerState in state.players:
		if not p.is_alive or not affected.has(p.team):
			continue
		if not state.units_of(p.team).is_empty():
			continue
		if _owns_production(state, p.team):
			continue
		p.is_alive = false
		newly_dead = true
		out.append(Events.PlayerEliminated.new(p.team, &"routed"))
	if newly_dead:
		var alive: Array[PlayerState] = []
		for p: PlayerState in state.players:
			if p.is_alive:
				alive.append(p)
		if alive.size() == 1:
			out.append(Events.GameEnded.new(alive[0].team, &"last_standing"))
	return out


static func _owns_production(state: GameState, team: int) -> bool:
	for i: int in range(state.map.property_owner.size()):
		if state.map.property_owner[i] != team:
			continue
		var terrain: TerrainType = state.ruleset.terrain_types[state.map.terrain[i]]
		if terrain.builds != &"":
			return true
	return false
