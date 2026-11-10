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
##
## Headquarters: capturers are pulled toward an enemy HQ, and an enemy
## capturer near an HQ we own is a "raider" — hitting it, or parking a
## unit on the HQ so it can't be entered, outbids ordinary business.
## Builds make sure the army has a capturer and an answer to every enemy
## type it can see before buying the priciest unit on offer.
##
## Fuel: units that burn fuel every turn (aircraft) fly back to a
## property that services them before the tank runs dry.

const END_TURN_SCORE := 1.0
const KILL_BOUNTY := 0.3
const CAPTURE_STEP_SCORE := 500.0
const CAPTURE_COMPLETE_SCORE := 1200.0
## Completing the capture of an enemy-held HQ — usually the game. Outbids
## everything else on the board.
const HQ_CAPTURE_SCORE := 1000000.0
## A capture step on an enemy-held HQ, short of completing it.
const HQ_CAPTURE_STEP_SCORE := 900.0
## How many tiles closer an enemy HQ counts than it is when a capturer
## picks where to march: it outbids somewhat nearer cities.
const HQ_PULL_TILES := 4
## Enemy capturers within this many tiles of an HQ we own are raiders.
const HQ_ALERT_RADIUS := 4
## Our units within this many tiles of the HQ turn to meet raiders.
const HQ_RESPONSE_RADIUS := 8
## Worth of removing all of a raider's HP, scaled by the share removed;
## multiplied when it already stands on the HQ (it is capturing).
const HQ_DEFENSE_SCORE := 4000.0
const HQ_DEFENSE_ON_HQ_FACTOR := 5.0
## Ending the turn on our own HQ while raiders are about — an occupied
## tile can't be captured. Cheaper units make the better doorstop.
const HQ_GARRISON_SCORE := 1500.0
const ADVANCE_PER_TILE := 12.0
## A fuel-burning unit turns for home once its fuel is down to the trip
## plus this many turns of flying; closing on home then counts
## LOW_FUEL_URGENCY times an ordinary advance, enough to outbid pokes.
const FUEL_RESERVE_TURNS := 2
const LOW_FUEL_URGENCY := 10.0
const BUILD_BASE_SCORE := 120.0
## Building a capturer when the army has none.
const BUILD_CAPTURER_SCORE := 1000.0
## Building a unit that can hurt an enemy type nothing we own can.
const BUILD_COUNTER_SCORE := 800.0
## Base damage from which a unit counts as an answer to an enemy type.
const COUNTER_MIN_DAMAGE := 30
const POWER_SCORE := 2000.0
const NO_OBJECTIVE := Vector2i(-1, -1)

var profile: AIProfile

var _threat_cache: Dictionary[int, Dictionary] = {}
var _objective_cache: Dictionary[int, Vector2i] = {}
## Unit ids whose objective this decision is a refuel run.
var _refueling: Dictionary[int, bool] = {}
var _enemy_reach_cache: Dictionary[int, Dictionary] = {}
## Per-decision HQ watch (see _watch_hqs): HQ tiles we own and the raiders
## near them.
var _hq_watch_ready: bool = false
var _my_hqs: Array[Vector2i] = []
var _raiders: Array[UnitState] = []


func _init(p_profile: AIProfile = null) -> void:
	profile = p_profile if p_profile != null else AIProfile.new()


## Greedy argmax over the legal actions; EndTurnAction once nothing
## scores above its baseline.
func choose_action(view: StateView) -> Action:
	_threat_cache = {}
	_objective_cache = {}
	_refueling = {}
	_enemy_reach_cache = {}
	_hq_watch_ready = false
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
	value += _raider_bonus(view, defender, dealt)
	# Counter approximation: the preview reasons from the attacker's
	# current tile; after a move the range-1 check may differ. Only
	# charge the counter when the shot lands from adjacency.
	var dest: Vector2i = ua.path[ua.path.size() - 1]
	if Grid.manhattan(dest, ua.target_coord) == 1 and preview.can_counter:
		var taken: int = mini(preview.counter_damage, attacker.hp)
		value -= taken / 100.0 * attacker_cost * profile.caution
	return value + _garrison_bonus(view, attacker, dest)


func _score_capture(view: StateView, ua: UnitAction) -> float:
	var capturer := view.unit(ua.unit_id)
	var dest: Vector2i = ua.path[ua.path.size() - 1]
	var progress: int = 0
	if view.map().capture_progress.has(dest):
		progress = view.map().capture_progress[dest]
	var after: int = progress + capturer.display_hp()
	var map := view.map()
	var terrain: TerrainType = view.ruleset().terrain_types[map.terrain_at(dest)]
	var enemy_hq: bool = terrain.is_hq and map.property_owner[map.idx(dest)] != MapState.NO_OWNER
	if after >= view.ruleset().capture_threshold:
		if enemy_hq:
			return HQ_CAPTURE_SCORE
		return CAPTURE_COMPLETE_SCORE * profile.capture_weight
	if enemy_hq:
		return HQ_CAPTURE_STEP_SCORE * profile.capture_weight
	return CAPTURE_STEP_SCORE * profile.capture_weight


func _score_advance(view: StateView, ua: UnitAction) -> float:
	var unit := view.unit(ua.unit_id)
	var dest: Vector2i = ua.path[ua.path.size() - 1]
	var score: float = _garrison_bonus(view, unit, dest)
	if ua.path.size() < 2:
		return score
	var objective := _objective_for(view, unit)
	if objective != NO_OBJECTIVE:
		var gain: int = Grid.manhattan(unit.coord, objective) - Grid.manhattan(dest, objective)
		if gain > 0:
			var urgency_factor: float = LOW_FUEL_URGENCY if _refueling.has(unit.id) else 1.0
			score += gain * ADVANCE_PER_TILE * profile.advance_weight * urgency_factor
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


## Priciest affordable unit by default; a capturer first when the army
## has none (cheapest wins), then an answer to any visible enemy type
## nothing we own can hurt.
func _score_build(view: StateView, action: BuildAction) -> float:
	var candidate: UnitType = view.ruleset().unit_types[action.unit_type_id]
	var score: float = BUILD_BASE_SCORE + candidate.cost * 0.01 * profile.expensive_unit_bias
	if candidate.capture_capable and not _has_capturer(view):
		score += BUILD_CAPTURER_SCORE - candidate.cost * 0.02
	if _answers_an_open_threat(view, candidate):
		score += BUILD_COUNTER_SCORE
	return score


func _has_capturer(view: StateView) -> bool:
	for mine: UnitState in view.my_units():
		if view.ruleset().unit_types[mine.type_id].capture_capable:
			return true
	return false


## True when some visible enemy type is hurt by `candidate` and by
## nothing the army already fields.
func _answers_an_open_threat(view: StateView, candidate: UnitType) -> bool:
	var ruleset := view.ruleset()
	var checked: Dictionary[int, bool] = {}
	for enemy: UnitState in view.visible_units():
		if enemy.team == view.team or checked.has(enemy.type_id):
			continue
		checked[enemy.type_id] = true
		var enemy_key: StringName = ruleset.unit_types[enemy.type_id].key
		if _base_damage(candidate, enemy_key) < COUNTER_MIN_DAMAGE:
			continue
		var answered: bool = false
		for mine: UnitState in view.my_units():
			if _base_damage(ruleset.unit_types[mine.type_id], enemy_key) >= COUNTER_MIN_DAMAGE:
				answered = true
				break
		if not answered:
			return true
	return false


## The best base damage either of `attacker`'s weapons lists against
## `defender_key` (ammo aside); 0 when it can't hurt that type.
static func _base_damage(attacker: UnitType, defender_key: StringName) -> int:
	var best: int = 0
	for w: WeaponProfile in [attacker.primary_weapon, attacker.secondary_weapon]:
		if w != null and w.damage_table != null:
			best = maxi(best, w.damage_table.base_damage.get(defender_key, 0))
	return best


## Finds, once per decision, the HQ tiles we own and the raiders near
## them: visible enemy capturers within HQ_ALERT_RADIUS.
func _watch_hqs(view: StateView) -> void:
	if _hq_watch_ready:
		return
	_hq_watch_ready = true
	_my_hqs = []
	_raiders = []
	var map := view.map()
	var ruleset := view.ruleset()
	for i: int in range(map.property_owner.size()):
		if map.property_owner[i] == view.team and ruleset.terrain_types[map.terrain[i]].is_hq:
			_my_hqs.append(Grid.from_idx(i, map.width))
	if _my_hqs.is_empty():
		return
	for enemy: UnitState in view.visible_units():
		if enemy.team == view.team or enemy.carrier_id != -1:
			continue
		if not ruleset.unit_types[enemy.type_id].capture_capable:
			continue
		if _hq_distance(enemy.coord) <= HQ_ALERT_RADIUS:
			_raiders.append(enemy)


## Tiles from `coord` to the nearest HQ we own (huge when we own none).
func _hq_distance(coord: Vector2i) -> int:
	var best: int = 1 << 30
	for hq: Vector2i in _my_hqs:
		best = mini(best, Grid.manhattan(coord, hq))
	return best


## Extra worth of `dealt` damage when the defender is a raider.
func _raider_bonus(view: StateView, defender: UnitState, dealt: int) -> float:
	_watch_hqs(view)
	if not _raiders.has(defender):
		return 0.0
	var factor: float = HQ_DEFENSE_ON_HQ_FACTOR if _my_hqs.has(defender.coord) else 1.0
	return HQ_DEFENSE_SCORE * factor * dealt / defender.hp


## Worth of `unit` ending its turn on `dest` as an HQ doorstop.
func _garrison_bonus(view: StateView, unit: UnitState, dest: Vector2i) -> float:
	_watch_hqs(view)
	if _raiders.is_empty() or not _my_hqs.has(dest):
		return 0.0
	return HQ_GARRISON_SCORE - view.ruleset().unit_types[unit.type_id].cost * 0.02


## The unit's march objective, scanned once per decision: it depends on
## the unit's current tile, not on the destination being scored.
func _objective_for(view: StateView, unit: UnitState) -> Vector2i:
	if not _objective_cache.has(unit.id):
		_objective_cache[unit.id] = _find_objective(view, unit)
	return _objective_cache[unit.id]


## Where `unit` marches when it has nothing better to do: home when it is
## low on fuel; at the nearest raider when one threatens an HQ it is
## close to; otherwise capturers
## head for the nearest property they don't own (an enemy HQ counting
## HQ_PULL_TILES closer) and everyone else for the nearest enemy.
## NO_OBJECTIVE when there is nothing to march on.
func _find_objective(view: StateView, unit: UnitState) -> Vector2i:
	var home := _refuel_point(view, unit)
	if home != NO_OBJECTIVE:
		_refueling[unit.id] = true
		return home
	_watch_hqs(view)
	if not _raiders.is_empty() and _hq_distance(unit.coord) <= HQ_RESPONSE_RADIUS:
		return _nearest_unit(unit.coord, _raiders)
	var best := NO_OBJECTIVE
	var best_dist: int = 1 << 30
	if view.ruleset().unit_types[unit.type_id].capture_capable:
		var map := view.map()
		for i: int in range(map.property_owner.size()):
			var terrain: TerrainType = view.ruleset().terrain_types[map.terrain[i]]
			var owner_team: int = map.property_owner[i]
			if not terrain.capturable or owner_team == unit.team:
				continue
			var coord := Grid.from_idx(i, map.width)
			var d: int = Grid.manhattan(unit.coord, coord)
			if terrain.is_hq and owner_team != MapState.NO_OWNER:
				d -= HQ_PULL_TILES
			if d < best_dist:
				best_dist = d
				best = coord
	if best != NO_OBJECTIVE:
		return best
	var enemies: Array[UnitState] = []
	for enemy: UnitState in view.visible_units():
		if enemy.team != unit.team:
			enemies.append(enemy)
	return _nearest_unit(unit.coord, enemies)


## The nearest property we own that services `unit`'s movement class,
## when `unit` burns fuel every turn and holds no more than the trip
## there plus FUEL_RESERVE_TURNS turns of flying. NO_OBJECTIVE otherwise.
func _refuel_point(view: StateView, unit: UnitState) -> Vector2i:
	var unit_type: UnitType = view.ruleset().unit_types[unit.type_id]
	if unit_type.fuel_per_turn <= 0 or unit_type.movement_class == null:
		return NO_OBJECTIVE
	var map := view.map()
	var best := NO_OBJECTIVE
	var best_dist: int = 1 << 30
	for i: int in range(map.property_owner.size()):
		if map.property_owner[i] != unit.team:
			continue
		var terrain: TerrainType = view.ruleset().terrain_types[map.terrain[i]]
		if not _services(terrain, unit_type.movement_class.key):
			continue
		var d: int = Grid.manhattan(unit.coord, Grid.from_idx(i, map.width))
		if d < best_dist:
			best_dist = d
			best = Grid.from_idx(i, map.width)
	if best == NO_OBJECTIVE:
		return NO_OBJECTIVE
	var reserve: int = FUEL_RESERVE_TURNS * (unit_type.fuel_per_turn + unit_type.movement)
	return best if unit.fuel <= best_dist + reserve else NO_OBJECTIVE


static func _services(terrain: TerrainType, class_key: StringName) -> bool:
	for mc: MovementClass in terrain.repairs_classes:
		if mc.key == class_key:
			return true
	return false


## The coord of the unit in `units` nearest `from` (first wins ties);
## NO_OBJECTIVE for an empty list.
static func _nearest_unit(from: Vector2i, units: Array[UnitState]) -> Vector2i:
	var best := NO_OBJECTIVE
	var best_dist: int = 1 << 30
	for u: UnitState in units:
		var d: int = Grid.manhattan(from, u.coord)
		if d < best_dist:
			best_dist = d
			best = u.coord
	return best
