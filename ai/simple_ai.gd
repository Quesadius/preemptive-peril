class_name SimpleAI
extends AIPlayer
## Stage-1 greedy AI (§10): score every legal action with a hand-weighted
## heuristic, take the best, repeat until EndTurnAction wins. One ply of
## lookahead, no search — the goal is a recognizable game, months early.
##
## Scoring is denominated in funds: damage is worth the defender's cost
## times the fraction of HP removed; counters charge the same the other
## way. Captures outbid pokes, kills earn a bounty, idle units drift
## toward objectives. Deterministic: pure arithmetic, strict-greater
## comparisons, generation order breaks ties.

const END_TURN_SCORE := 1.0
const KILL_BOUNTY := 0.3
const CAPTURE_STEP_SCORE := 500.0
const CAPTURE_COMPLETE_SCORE := 1200.0
const ADVANCE_PER_TILE := 12.0
const BUILD_BASE_SCORE := 120.0
const POWER_SCORE := 2000.0

var profile: AIProfile

var _threat_cache: Dictionary[int, Dictionary] = {}
var _objective_cache: Dictionary[int, Vector2i] = {}
var _enemy_reach_cache: Dictionary[int, Dictionary] = {}


func _init(p_profile: AIProfile = null) -> void:
	profile = p_profile if p_profile != null else AIProfile.new()


## Greedy argmax over the legal actions; EndTurnAction once nothing
## scores above its baseline.
func choose_action(view: StateView) -> Action:
	_threat_cache = {}
	_objective_cache = {}
	_enemy_reach_cache = {}
	var best: Action = EndTurnAction.new()
	var best_score: float = END_TURN_SCORE
	for action: Action in view.legal_actions():
		var score := _score(view, action)
		if score > best_score:
			best_score = score
			best = action
	return best


func _score(view: StateView, action: Action) -> float:
	if action is PowerAction:
		# Powers are pure upside once charged; supers outrank normals via
		# generation order and the same score.
		return POWER_SCORE
	if action is BuildAction:
		return _score_build(view, action as BuildAction)
	if action is UnitAction:
		var ua := action as UnitAction
		match ua.verb:
			UnitAction.Verb.ATTACK:
				return _score_attack(view, ua)
			UnitAction.Verb.CAPTURE:
				return _score_capture(view, ua)
			UnitAction.Verb.WAIT:
				return _score_advance(view, ua)
	return 0.0


func _score_attack(view: StateView, ua: UnitAction) -> float:
	var attacker := view.unit(ua.unit_id)
	var defender := view.unit_at(ua.target_coord)
	var preview := view.preview_attack(attacker.id, defender.id)
	var attacker_cost: int = view.ruleset().unit_types[attacker.type_id].cost
	var defender_cost: int = view.ruleset().unit_types[defender.type_id].cost
	var dealt: int = mini(preview.damage, defender.hp)
	var value: float = dealt / 100.0 * defender_cost * profile.aggression
	if preview.damage >= defender.hp:
		value += defender_cost * KILL_BOUNTY
	# Counter approximation: the preview reasons from the attacker's
	# current tile; after a move the range-1 check may differ. Only
	# charge the counter when the shot lands from adjacency.
	var dest: Vector2i = ua.path[ua.path.size() - 1]
	if Grid.manhattan(dest, ua.target_coord) == 1 and preview.can_counter:
		var taken: int = mini(preview.counter_damage, attacker.hp)
		value -= taken / 100.0 * attacker_cost * profile.caution
	return value


func _score_capture(view: StateView, ua: UnitAction) -> float:
	var capturer := view.unit(ua.unit_id)
	var dest: Vector2i = ua.path[ua.path.size() - 1]
	var progress: int = 0
	if view.map().capture_progress.has(dest):
		progress = view.map().capture_progress[dest]
	var after: int = progress + capturer.display_hp()
	if after >= view.ruleset().capture_threshold:
		return CAPTURE_COMPLETE_SCORE * profile.capture_weight
	return CAPTURE_STEP_SCORE * profile.capture_weight


func _score_advance(view: StateView, ua: UnitAction) -> float:
	if ua.path.size() < 2:
		return 0.0
	var unit := view.unit(ua.unit_id)
	var dest: Vector2i = ua.path[ua.path.size() - 1]
	var score: float = 0.0
	var objective := _objective_for(view, unit)
	if objective != Vector2i(-1, -1):
		var gain: int = Grid.manhattan(unit.coord, objective) - Grid.manhattan(dest, objective)
		if gain > 0:
			score += gain * ADVANCE_PER_TILE * profile.advance_weight
	# Stage 2: the threat map turns waiting into positioning. Healthy
	# units shade away from danger; the wounded actively retreat.
	var threat := _threat_for(view, unit.type_id)
	var here: int = threat.get(unit.coord, 0)
	var there: int = threat.get(dest, 0)
	var my_cost: int = view.ruleset().unit_types[unit.type_id].cost
	var urgency: float = 1.5 if unit.display_hp() <= 4 else 0.5
	score += (here - there) / 100.0 * my_cost * 0.01 * urgency * profile.caution * 10.0
	return score


## Threat maps are expensive; one per unit type per decision.
func _threat_for(view: StateView, type_id: int) -> Dictionary[Vector2i, int]:
	if not _threat_cache.has(type_id):
		_threat_cache[type_id] = ThreatMap.compute(view, view.team, type_id, _enemy_reach_cache)
	return _threat_cache[type_id]


func _score_build(view: StateView, action: BuildAction) -> float:
	var cost: int = view.ruleset().unit_types[action.unit_type_id].cost
	return BUILD_BASE_SCORE + cost * 0.01 * profile.expensive_unit_bias


## The unit's march objective, scanned once per decision: it depends on
## the unit's current tile, not on the destination being scored.
func _objective_for(view: StateView, unit: UnitState) -> Vector2i:
	if not _objective_cache.has(unit.id):
		_objective_cache[unit.id] = _find_objective(view, unit)
	return _objective_cache[unit.id]


## Capture-capable units march on the nearest property they don't own;
## everyone else marches on the nearest enemy. (-1,-1) = no objective.
func _find_objective(view: StateView, unit: UnitState) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_dist: int = 1 << 30
	if view.ruleset().unit_types[unit.type_id].capture_capable:
		var map := view.map()
		for i: int in range(map.property_owner.size()):
			var terrain: TerrainType = view.ruleset().terrain_types[map.terrain[i]]
			if not terrain.capturable or map.property_owner[i] == unit.team:
				continue
			var coord := Grid.from_idx(i, map.width)
			var d: int = Grid.manhattan(unit.coord, coord)
			if d < best_dist:
				best_dist = d
				best = coord
	if best != Vector2i(-1, -1):
		return best
	for enemy: UnitState in view.visible_units():
		if enemy.team == unit.team:
			continue
		var d: int = Grid.manhattan(unit.coord, enemy.coord)
		if d < best_dist:
			best_dist = d
			best = enemy.coord
	return best
