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
## Builds keep a quota of capturers, then an answer to every enemy type
## in sight, before buying the priciest unit on offer — and never a unit
## that can neither fight nor capture (the AI doesn't run transports).
##
## Fuel: units that burn fuel every turn (aircraft) fly back to a
## property that services them before the tank runs dry.
##
## Tempo: evenly matched armies would otherwise stare at each other from
## just outside range forever. While its army is worth at least
## PRESS_RATIO of the enemy's it can see, the AI presses — healthy units
## all but ignore the threat map when advancing. And nobody loiters
## where they are in the way: on our own factories and airports (a
## blocked one builds nothing), or, for units that can't capture, on a
## property we have yet to take (our capturers need the tile).

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
## Army value (cost x HP) relative to the visible enemy's from which the
## AI presses, and how much of the threat shading a healthy unit still
## feels while it does.
const PRESS_RATIO := 0.8
const PRESS_THREAT_FACTOR := 0.1
## Moving off a tile the unit shouldn't block (see _in_the_way), and the
## same again as a penalty for ending a move on one.
const KEEP_CLEAR_SCORE := 200.0
const BUILD_BASE_SCORE := 120.0
## Building a capturer while the army is under the profile's quota.
const BUILD_CAPTURER_SCORE := 1000.0
## Building a unit that can hurt an enemy type nothing we own can.
const BUILD_COUNTER_SCORE := 800.0
## Base damage from which a unit counts as an answer to an enemy type.
const COUNTER_MIN_DAMAGE := 30
const POWER_SCORE := 2000.0
const SUPER_POWER_SCORE := 2500.0
## Resupply bonus per adjacent needy ally (low fuel or low ammo).
const SUPPLY_ALLY_SCORE := 350.0
## Base score for consolidating two damaged twin units via JOIN.
const JOIN_BASE_SCORE := 180.0
## Gentle territory-control shading from InfluenceMap (higher for wounded).
const INFLUENCE_HEALTHY_FACTOR := 0.02
const INFLUENCE_WOUNDED_FACTOR := 0.25
const NO_OBJECTIVE := Vector2i(-1, -1)

var profile: AIProfile

var _threat_cache: Dictionary[int, Dictionary] = {}
var _objective_cache: Dictionary[int, Vector2i] = {}
## Unit ids whose objective this decision is a refuel run.
var _refueling: Dictionary[int, bool] = {}
var _enemy_reach_cache: Dictionary[int, Dictionary] = {}
## Per-decision cached snapshots to avoid repeated fog/sort/army scans.
var _visible_units_ready: bool = false
var _visible_units: Array[UnitState] = []
var _my_units_ready: bool = false
var _my_units: Array[UnitState] = []
var _fog_mask_ready: bool = false
var _fog_mask: PackedByteArray = PackedByteArray()
var _influence_ready: bool = false
var _influence: Dictionary[Vector2i, int] = {}
var _short_capturers: int = -1
var _open_threats_ready: bool = false
var _open_threat_keys: Array[StringName] = []
## Per-decision HQ watch (see _watch_hqs): HQ tiles we own and the raiders
## near them.
var _hq_watch_ready: bool = false
var _my_hqs: Array[Vector2i] = []
var _raiders: Array[UnitState] = []
## Per-decision tempo read (see _is_pressing): -1 unknown, else 0 or 1.
var _pressing: int = -1


func _init(p_profile: AIProfile = null) -> void:
	profile = p_profile if p_profile != null else AIProfile.new()


## Greedy argmax over the legal actions; EndTurnAction once nothing
## scores above its baseline.
func choose_action(view: StateView) -> Action:
	_threat_cache = {}
	_objective_cache = {}
	_refueling = {}
	_enemy_reach_cache = {}
	_visible_units_ready = false
	_visible_units = []
	_my_units_ready = false
	_my_units = []
	_fog_mask_ready = false
	_fog_mask = PackedByteArray()
	_influence_ready = false
	_influence = {}
	_short_capturers = -1
	_open_threats_ready = false
	_open_threat_keys = []
	_hq_watch_ready = false
	_pressing = -1
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
		# Supers strictly outbid normal powers when both are available.
		var pa := action as PowerAction
		if pa.power_level == PlayerState.PowerState.SUPER:
			return SUPER_POWER_SCORE
		return POWER_SCORE
	if action is BuildAction:
		return _score_build(view, action as BuildAction)
	if action is UnitAction:
		return _score_unit_action(view, action as UnitAction)
	return 0.0


func _score_unit_action(view: StateView, ua: UnitAction) -> float:
	match ua.verb:
		UnitAction.Verb.ATTACK:
			return _score_attack(view, ua)
		UnitAction.Verb.CAPTURE:
			return _score_capture(view, ua)
		UnitAction.Verb.SUPPLY:
			return _score_supply(view, ua)
		UnitAction.Verb.JOIN:
			return _score_join(view, ua)
		UnitAction.Verb.WAIT:
			return _score_advance(view, ua)
	return 0.0


func _score_attack(view: StateView, ua: UnitAction) -> float:
	var attacker := view.unit(ua.unit_id)
	var defender := view.unit_at(ua.target_coord)
	var dest: Vector2i = ua.path[ua.path.size() - 1]
	var preview := view.preview_attack(attacker.id, defender.id, dest)
	var attacker_cost: int = view.ruleset().unit_types[attacker.type_id].cost
	var defender_cost: int = view.ruleset().unit_types[defender.type_id].cost
	var dealt: int = mini(preview.damage, defender.hp)
	var value: float = dealt / 100.0 * defender_cost * profile.aggression
	if preview.damage >= defender.hp:
		value += defender_cost * KILL_BOUNTY
	value += _raider_bonus(view, defender, dealt)
	if preview.can_counter:
		var taken: int = mini(preview.counter_damage, attacker.hp)
		value -= taken / 100.0 * attacker_cost * profile.caution
	if dest != attacker.coord and _in_the_way(view, attacker, attacker.coord):
		value += KEEP_CLEAR_SCORE
	if _in_the_way(view, attacker, dest):
		value -= KEEP_CLEAR_SCORE  # fire from somewhere that blocks nothing, if it's as good
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


func _score_supply(view: StateView, ua: UnitAction) -> float:
	var supplier := view.unit(ua.unit_id)
	var dest: Vector2i = ua.path[ua.path.size() - 1]
	var score: float = 0.0
	var ruleset := view.ruleset()
	for n: Vector2i in Grid.neighbors(dest):
		var ally := view.unit_at(n)
		if ally == null or ally.team != supplier.team or ally.id == supplier.id:
			continue
		var t: UnitType = ruleset.unit_types[ally.type_id]
		var low_fuel: bool = ally.fuel * 2 <= t.max_fuel
		var low_ammo: bool = t.max_ammo > 0 and ally.ammo * 2 <= t.max_ammo
		if low_fuel or low_ammo:
			score += SUPPLY_ALLY_SCORE
	if score <= 0.0:
		return 0.0
	if _in_the_way(view, supplier, dest):
		score -= KEEP_CLEAR_SCORE
	return score + _garrison_bonus(view, supplier, dest)


func _score_join(view: StateView, ua: UnitAction) -> float:
	var mover := view.unit(ua.unit_id)
	var dest: Vector2i = ua.path[ua.path.size() - 1]
	var target := view.unit_at(dest)
	if target == null or mover.display_hp() > 5 or target.display_hp() > 7:
		return 0.0
	var unit_type: UnitType = view.ruleset().unit_types[mover.type_id]
	var surplus: int = maxi(0, mover.display_hp() + target.display_hp() - 10)
	@warning_ignore("integer_division")
	var refund: int = surplus * unit_type.cost / 10
	return JOIN_BASE_SCORE + refund * 0.05


func _score_advance(view: StateView, ua: UnitAction) -> float:
	var unit := view.unit(ua.unit_id)
	var dest: Vector2i = ua.path[ua.path.size() - 1]
	var score: float = _garrison_bonus(view, unit, dest)
	if ua.path.size() < 2:
		return score
	if _in_the_way(view, unit, unit.coord):
		score += KEEP_CLEAR_SCORE
	if _in_the_way(view, unit, dest):
		score -= KEEP_CLEAR_SCORE
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
	var wounded: bool = unit.display_hp() <= 4
	var urgency: float = 1.5 if wounded else 0.5
	if not wounded and _is_pressing(view):
		urgency *= PRESS_THREAT_FACTOR
	score += (here - there) / 100.0 * my_cost * 0.01 * urgency * profile.caution * 10.0
	# Territory shading from InfluenceMap: wounded units pull toward
	# friendly-controlled ground; exclude this unit's own pre-move shadow
	# so moving off a tile isn't penalized for leaving itself behind.
	if wounded:
		var influence := _influence_for(view)
		var inf_delta: int = (
			_other_influence(view, influence, unit, dest)
			- _other_influence(view, influence, unit, unit.coord)
		)
		score += clampf(inf_delta * INFLUENCE_WOUNDED_FACTOR, -40.0, 40.0)
	return score


## Influence at `coord` with `self_unit`'s own contribution subtracted so a
## unit measures allied/enemy support rather than its own pre-move shadow.
static func _other_influence(
	view: StateView, influence: Dictionary[Vector2i, int], self_unit: UnitState, coord: Vector2i
) -> int:
	var val: int = influence.get(coord, 0)
	var d: int = Grid.manhattan(self_unit.coord, coord)
	if d <= InfluenceMap.SPREAD:
		@warning_ignore("integer_division")
		var weight: int = view.ruleset().unit_types[self_unit.type_id].cost / 100
		var falloff: int = InfluenceMap.SPREAD + 1 - d
		@warning_ignore("integer_division")
		val -= weight * falloff / (InfluenceMap.SPREAD + 1)
	return val


## Cached visible units for this decision.
func _get_visible_units(view: StateView) -> Array[UnitState]:
	if not _visible_units_ready:
		_visible_units_ready = true
		_visible_units = view.visible_units()
	return _visible_units


## Cached friendly units for this decision.
func _get_my_units(view: StateView) -> Array[UnitState]:
	if not _my_units_ready:
		_my_units_ready = true
		_my_units = view.my_units()
	return _my_units


## Cached fog mask for this decision.
func _get_fog_mask(view: StateView) -> PackedByteArray:
	if not _fog_mask_ready:
		_fog_mask_ready = true
		_fog_mask = view.fog_mask()
	return _fog_mask


## Territory control map, computed once per decision.
func _influence_for(view: StateView) -> Dictionary[Vector2i, int]:
	if not _influence_ready:
		_influence_ready = true
		_influence = InfluenceMap.compute(view, view.team, _get_visible_units(view))
	return _influence


## True when `unit` idling on `coord` would block something: our own
## production (nothing can be built on an occupied tile), or — for a unit
## that can't capture — a property we don't own, which our capturers
## must be able to step onto.
func _in_the_way(view: StateView, unit: UnitState, coord: Vector2i) -> bool:
	var map := view.map()
	var terrain: TerrainType = view.ruleset().terrain_types[map.terrain_at(coord)]
	if map.property_owner[map.idx(coord)] == view.team:
		return terrain.builds != &""
	return terrain.capturable and not view.ruleset().unit_types[unit.type_id].capture_capable


## True while our army is worth at least PRESS_RATIO of the enemy's we
## can see (cost x HP share, cargo included). Read once per decision.
func _is_pressing(view: StateView) -> bool:
	if not profile.presses:
		return false
	if _pressing < 0:
		var ours: float = 0.0
		var theirs: float = 0.0
		for u: UnitState in _get_visible_units(view):
			var worth: float = view.ruleset().unit_types[u.type_id].cost * u.hp / 100.0
			if u.team == view.team:
				ours += worth
			else:
				theirs += worth
		_pressing = 1 if ours >= theirs * PRESS_RATIO else 0
	return _pressing == 1


## Threat maps are expensive; one per unit type per decision.
func _threat_for(view: StateView, type_id: int) -> Dictionary[Vector2i, int]:
	if not _threat_cache.has(type_id):
		_threat_cache[type_id] = ThreatMap.compute(
			view,
			view.team,
			type_id,
			_enemy_reach_cache,
			_get_visible_units(view),
			_get_fog_mask(view)
		)
	return _threat_cache[type_id]


## Priciest affordable unit by default; a capturer first while the army
## is short of them (cheapest wins), then an answer to any visible enemy
## type nothing we own can hurt. Units that can neither fight nor capture
## score nothing.
func _score_build(view: StateView, action: BuildAction) -> float:
	var candidate: UnitType = view.ruleset().unit_types[action.unit_type_id]
	var armed: bool = candidate.primary_weapon != null or candidate.secondary_weapon != null
	if not armed and not candidate.capture_capable:
		return 0.0
	var score: float = BUILD_BASE_SCORE + candidate.cost * 0.01 * profile.expensive_unit_bias
	if candidate.capture_capable and _short_of_capturers(view):
		score += BUILD_CAPTURER_SCORE - candidate.cost * 0.02
	if _answers_an_open_threat(view, candidate):
		score += BUILD_COUNTER_SCORE
	return score


## True while the army holds fewer capturers than its quota (cached per decision).
func _short_of_capturers(view: StateView) -> bool:
	if _short_capturers < 0:
		var army := _get_my_units(view)
		var capturers: int = 0
		for mine: UnitState in army:
			if view.ruleset().unit_types[mine.type_id].capture_capable:
				capturers += 1
		var quota: int = profile.min_capturers
		if profile.capturer_share > 0:
			@warning_ignore("integer_division")
			quota = maxi(quota, army.size() / profile.capturer_share)
		_short_capturers = 1 if capturers < quota else 0
	return _short_capturers == 1


## True when some visible enemy type is hurt by `candidate` and by
## nothing the army already fields. Open threats are computed once per decision.
func _answers_an_open_threat(view: StateView, candidate: UnitType) -> bool:
	if not profile.counter_builds:
		return false
	if not _open_threats_ready:
		_open_threats_ready = true
		_open_threat_keys = []
		var ruleset := view.ruleset()
		var my_army := _get_my_units(view)
		var checked: Dictionary[int, bool] = {}
		for enemy: UnitState in _get_visible_units(view):
			if enemy.team == view.team or checked.has(enemy.type_id):
				continue
			checked[enemy.type_id] = true
			var enemy_key: StringName = ruleset.unit_types[enemy.type_id].key
			var answered: bool = false
			for mine: UnitState in my_army:
				if _base_damage(ruleset.unit_types[mine.type_id], enemy_key) >= COUNTER_MIN_DAMAGE:
					answered = true
					break
			if not answered:
				_open_threat_keys.append(enemy_key)
	for enemy_key: StringName in _open_threat_keys:
		if _base_damage(candidate, enemy_key) >= COUNTER_MIN_DAMAGE:
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
	if not profile.defends_hq:
		return  # no HQs watched, so no raiders: every HQ habit stays off
	var map := view.map()
	var ruleset := view.ruleset()
	for i: int in range(map.property_owner.size()):
		if map.property_owner[i] == view.team and ruleset.terrain_types[map.terrain[i]].is_hq:
			_my_hqs.append(Grid.from_idx(i, map.width))
	if _my_hqs.is_empty():
		return
	for enemy: UnitState in _get_visible_units(view):
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
	for enemy: UnitState in _get_visible_units(view):
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
