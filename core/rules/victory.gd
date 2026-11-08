class_name Victory
extends RefCounted
## Win/loss conditions, checked after every action by Rules.apply().
## Two ways to lose, both loss-triggered (only teams that JUST lost a
## unit or property are examined), so armyless factory starts and empty
## test fixtures are never eliminated out of nowhere:
##   - "hq_captured": the player's last HQ tile (TerrainType.is_hq) was
##     captured. Players who never held an HQ can't lose this way.
##   - "routed": no units left and no production to rebuild from.
## The game ends when one player remains.


## Evaluates eliminations triggered by this action's `events` and, when
## exactly one player is left standing, ends the game. Idempotent:
## already-dead players and untouched teams produce nothing new.
static func check(state: GameState, events: Array[GameEvent]) -> Array[GameEvent]:
	var affected: Dictionary[int, bool] = {}
	var lost_hq: Dictionary[int, bool] = {}
	for e: GameEvent in events:
		if e is Events.UnitDestroyed:
			affected[(e as Events.UnitDestroyed).team] = true
		elif e is Events.PropertyCaptured:
			var captured := e as Events.PropertyCaptured
			affected[captured.old_team] = true
			if _is_hq(state, state.map.idx(captured.coord)):
				lost_hq[captured.old_team] = true
	if affected.is_empty():
		return []
	var out: Array[GameEvent] = []
	var newly_dead: bool = false
	for p: PlayerState in state.players:
		if not p.is_alive or not affected.has(p.team):
			continue
		var reason := _loss_reason(state, p.team, lost_hq.has(p.team))
		if reason == &"":
			continue
		p.is_alive = false
		newly_dead = true
		out.append(Events.PlayerEliminated.new(p.team, reason))
	if newly_dead:
		var alive: Array[PlayerState] = []
		for p: PlayerState in state.players:
			if p.is_alive:
				alive.append(p)
		if alive.size() == 1:
			out.append(Events.GameEnded.new(alive[0].team, &"last_standing"))
	return out


## Why `team` is out after this action, or &"" if it survives.
static func _loss_reason(state: GameState, team: int, lost_an_hq: bool) -> StringName:
	if lost_an_hq and not _owns_hq(state, team):
		return &"hq_captured"
	if state.units_of(team).is_empty() and not _owns_production(state, team):
		return &"routed"
	return &""


static func _is_hq(state: GameState, i: int) -> bool:
	return state.ruleset.terrain_types[state.map.terrain[i]].is_hq


static func _owns_hq(state: GameState, team: int) -> bool:
	for i: int in range(state.map.property_owner.size()):
		if state.map.property_owner[i] == team and _is_hq(state, i):
			return true
	return false


static func _owns_production(state: GameState, team: int) -> bool:
	for i: int in range(state.map.property_owner.size()):
		if state.map.property_owner[i] != team:
			continue
		var terrain: TerrainType = state.ruleset.terrain_types[state.map.terrain[i]]
		if terrain.builds != &"":
			return true
	return false
