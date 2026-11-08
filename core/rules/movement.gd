class_name Movement
extends RefCounted
## Movement rules: reachability, terrain entry cost, path finding and path
## validation. This is the only movement-legality logic in the project —
## the UI and the AI both consume it (via ActionGenerator).
##
## Two budgets constrain a move: movement points pay the terrain cost of
## each tile entered, and fuel is spent per tile — one fuel per step,
## regardless of terrain. A route is legal only if it fits both, and the
## best route can differ per budget (a cheap winding road vs an expensive
## short cut), so the search runs Dijkstra over (coord, steps) states
## rather than coords alone.
##
## Blocking rules (§6): enemy units block movement entirely; allied units
## are passable, and ally-occupied tiles do appear in reachable() because
## whether the destination is a legal *stop* is a verb question (WAIT vs
## LOAD vs JOIN) that belongs to ActionGenerator / Rules.validate().
## Exhaustion (has_acted) is likewise ActionGenerator's concern, not
## encoded here. Fog ambush — stopping mid-path on an invisible blocker —
## arrives with the fog milestone and lives in Rules.apply(), not here.


## Bounded Dijkstra from the unit's tile. Returns coord -> remaining
## movement points (movement minus the cheapest cost among routes that
## also fit the fuel's step limit). The unit's own tile is included with
## full movement. Deterministic: ties break by discovery order, which
## follows Grid.CARDINAL_DIRS. Requires `unit_id` to exist in
## `state.units`.
static func reachable(state: GameState, unit_id: int) -> Dictionary[Vector2i, int]:
	var unit: UnitState = state.units[unit_id]
	var points: int = state.ruleset.unit_types[unit.type_id].movement
	var cost := _dijkstra(state, unit)
	var out: Dictionary[Vector2i, int] = {}
	for s: Vector3i in cost:
		var c := Vector2i(s.x, s.y)
		var remaining: int = points - cost[s]
		if not out.has(c) or remaining > out[c]:
			out[c] = remaining
	return out


## Cost for this unit's movement class to enter `coord` under the current
## weather. -1 if impassable: off-map, no entry for the class on that
## terrain, no cost listed for the current weather, or non-positive data.
## Terrain cost only — occupancy blocking is reachable()'s concern.
static func enter_cost(state: GameState, unit: UnitState, coord: Vector2i) -> int:
	if not state.map.in_bounds(coord):
		return -1
	var unit_type: UnitType = state.ruleset.unit_types[unit.type_id]
	var terrain: TerrainType = state.ruleset.terrain_types[state.map.terrain_at(coord)]
	var class_key: StringName = unit_type.movement_class.key
	if not terrain.move_costs.has(class_key):
		return -1
	var costs: PackedInt32Array = terrain.move_costs[class_key]
	if state.weather < 0 or state.weather >= costs.size():
		return -1
	var cost: int = costs[state.weather]
	return cost if cost >= 1 else -1


## Best path from the unit's tile to `dest`, both ends included, for the
## cursor path preview: cheapest in movement points among routes that fit
## the fuel limit, fewest steps among those. Empty when `dest` is not
## reachable. Deterministic (see reachable()).
static func path_to(state: GameState, unit_id: int, dest: Vector2i) -> Array[Vector2i]:
	var unit: UnitState = state.units[unit_id]
	var pred: Dictionary[Vector3i, Vector3i] = {}
	var best := _best_states(_dijkstra(state, unit, pred))
	if not best.has(dest):
		return []
	return _trace(best[dest], pred)


## Every coord reachable() lists, mapped to the exact route path_to()
## returns for it, from a single search — the bulk form for callers that
## need a path per destination (ActionGenerator, the cursor preview).
## Each value is an Array[Vector2i], both ends included. Requires
## `unit_id` to exist in `state.units`.
static func all_paths(state: GameState, unit_id: int) -> Dictionary[Vector2i, Array]:
	var unit: UnitState = state.units[unit_id]
	var pred: Dictionary[Vector3i, Vector3i] = {}
	var best := _best_states(_dijkstra(state, unit, pred))
	var out: Dictionary[Vector2i, Array] = {}
	for c: Vector2i in best:
		out[c] = _trace(best[c], pred)
	return out


## True if `path` is a legal client-supplied move: starts on the unit's
## tile, contiguous cardinal steps, no revisited tile, every step
## enterable, no enemy anywhere on it, total terrain cost within movement
## points, and step count within fuel. A path need not be cheapest — any
## affordable route is legal. Says nothing about whether the destination
## is a legal place to stop; that depends on the verb.
static func validate_path(state: GameState, unit_id: int, path: Array[Vector2i]) -> bool:
	var unit: UnitState = state.units[unit_id]
	if path.is_empty() or path[0] != unit.coord:
		return false
	var points: int = state.ruleset.unit_types[unit.type_id].movement
	# Every step costs at least 1 point and 1 fuel, so an over-long path
	# fails here without walking it (paths arrive from save files too).
	if path.size() - 1 > mini(points, unit.fuel):
		return false
	var seen: Dictionary[Vector2i, bool] = {path[0]: true}
	var total: int = 0
	for i: int in range(1, path.size()):
		var c: Vector2i = path[i]
		if Grid.manhattan(path[i - 1], c) != 1:
			return false
		if seen.has(c):
			return false
		seen[c] = true
		var step: int = enter_cost(state, unit, c)
		if step < 0:
			return false
		if _blocked(state, unit, c):
			return false
		total += step
		if total > points:
			return false
	return true


## Shared bounded Dijkstra over (x, y, steps) states, packed as Vector3i
## with z = steps taken. Returns state -> cheapest movement-point cost;
## fills `pred` with each state's predecessor state. Steps are capped at
## min(fuel, movement) — every step costs at least 1 point, so longer
## routes can never be affordable. Plain array frontier with
## first-found-min extraction — fine at AW map sizes (§6).
static func _dijkstra(
	state: GameState, unit: UnitState, pred: Dictionary[Vector3i, Vector3i] = {}
) -> Dictionary[Vector3i, int]:
	var points: int = state.ruleset.unit_types[unit.type_id].movement
	var max_steps: int = mini(unit.fuel, points)
	var mask := Fog.mask_for(state, unit.team)  # the state is fixed for the whole search
	var start := Vector3i(unit.coord.x, unit.coord.y, 0)
	var cost: Dictionary[Vector3i, int] = {start: 0}
	var frontier: Array[Vector3i] = [start]
	while not frontier.is_empty():
		var best_i: int = 0
		for i: int in range(1, frontier.size()):
			if cost[frontier[i]] < cost[frontier[best_i]]:
				best_i = i
		var cur: Vector3i = frontier[best_i]
		frontier.remove_at(best_i)
		if cur.z == max_steps:
			continue
		var cur_cost: int = cost[cur]
		for n: Vector2i in Grid.neighbors(Vector2i(cur.x, cur.y)):
			var step: int = enter_cost(state, unit, n)
			if step < 0:
				continue
			if _blocked(state, unit, n, mask):
				continue
			var nc: int = cur_cost + step
			if nc > points:
				continue
			var ns := Vector3i(n.x, n.y, cur.z + 1)
			if cost.has(ns) and cost[ns] <= nc:
				continue
			cost[ns] = nc
			pred[ns] = cur
			if not frontier.has(ns):
				frontier.append(ns)
	return cost


## Per coord, the search state path_to() routes through: cheapest cost,
## then fewest steps. (coord, steps) states are unique, so the pick does
## not depend on dictionary order.
static func _best_states(cost: Dictionary[Vector3i, int]) -> Dictionary[Vector2i, Vector3i]:
	var best: Dictionary[Vector2i, Vector3i] = {}
	for s: Vector3i in cost:
		var c := Vector2i(s.x, s.y)
		if not best.has(c):
			best[c] = s
			continue
		var held: Vector3i = best[c]
		if cost[s] < cost[held] or (cost[s] == cost[held] and s.z < held.z):
			best[c] = s
	return best


## Walks predecessor links from `end` back to the start state.
static func _trace(end: Vector3i, pred: Dictionary[Vector3i, Vector3i]) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var cur := end
	while true:
		path.append(Vector2i(cur.x, cur.y))
		if cur.z == 0:
			break
		cur = pred[cur]
	path.reverse()
	return path


## Enemy units block planning only when the mover's team can SEE them —
## invisible blockers are fog's ambush mechanic, resolved in
## Rules.apply(), not here (§6). `mask` is an optional Fog.mask_for().
static func _blocked(
	state: GameState, mover: UnitState, coord: Vector2i, mask: PackedByteArray = PackedByteArray()
) -> bool:
	var occupant := state.unit_at(coord)
	if occupant == null or occupant.team == mover.team:
		return false
	return Fog.sees_unit(state, mover.team, occupant, mask)
