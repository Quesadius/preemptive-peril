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
## follows Grid.CARDINAL_DIRS. `viewer_team` (-1 = unit's own team) lets
## enemy range inspection evaluate fog strictly from the viewer's eyes.
## Requires `unit_id` to exist in `state.units`.
static func reachable(
	state: GameState,
	unit_id: int,
	viewer_team: int = -1,
	viewer_mask: PackedByteArray = PackedByteArray()
) -> Dictionary[Vector2i, int]:
	var unit: UnitState = state.units[unit_id]
	var points: int = state.ruleset.unit_types[unit.type_id].movement
	var effective_viewer: int = unit.team if viewer_team < 0 else viewer_team
	var mask: PackedByteArray = (
		viewer_mask if not viewer_mask.is_empty() else Fog.mask_for(state, effective_viewer)
	)
	var out: Dictionary[Vector2i, int] = {}
	if unit.fuel >= points:
		var pred_2d: Dictionary[Vector2i, Vector2i] = {}
		var cost_2d := _dijkstra_2d(state, unit, points, effective_viewer, mask, pred_2d)
		for c: Vector2i in cost_2d:
			out[c] = points - cost_2d[c]
		return out
	var pred_3d: Dictionary[Vector3i, Vector3i] = {}
	var cost := _dijkstra_3d(state, unit, points, effective_viewer, mask, pred_3d)
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
static func path_to(
	state: GameState,
	unit_id: int,
	dest: Vector2i,
	viewer_team: int = -1,
	viewer_mask: PackedByteArray = PackedByteArray()
) -> Array[Vector2i]:
	var unit: UnitState = state.units[unit_id]
	var points: int = state.ruleset.unit_types[unit.type_id].movement
	var effective_viewer: int = unit.team if viewer_team < 0 else viewer_team
	var mask: PackedByteArray = (
		viewer_mask if not viewer_mask.is_empty() else Fog.mask_for(state, effective_viewer)
	)
	if unit.fuel >= points:
		var pred_2d: Dictionary[Vector2i, Vector2i] = {}
		var cost_2d := _dijkstra_2d(state, unit, points, effective_viewer, mask, pred_2d)
		if not cost_2d.has(dest):
			return []
		return _trace_2d(unit.coord, dest, pred_2d)
	var pred: Dictionary[Vector3i, Vector3i] = {}
	var best := _best_states(_dijkstra_3d(state, unit, points, effective_viewer, mask, pred))
	if not best.has(dest):
		return []
	return _trace(best[dest], pred)


## Every coord reachable() lists, mapped to the exact route path_to()
## returns for it, from a single search — the bulk form for callers that
## need a path per destination (ActionGenerator, the cursor preview).
## Each value is an Array[Vector2i], both ends included. Requires
## `unit_id` to exist in `state.units`.
static func all_paths(
	state: GameState,
	unit_id: int,
	viewer_team: int = -1,
	viewer_mask: PackedByteArray = PackedByteArray()
) -> Dictionary[Vector2i, Array]:
	var unit: UnitState = state.units[unit_id]
	var points: int = state.ruleset.unit_types[unit.type_id].movement
	var effective_viewer: int = unit.team if viewer_team < 0 else viewer_team
	var mask: PackedByteArray = (
		viewer_mask if not viewer_mask.is_empty() else Fog.mask_for(state, effective_viewer)
	)
	var out: Dictionary[Vector2i, Array] = {}
	if unit.fuel >= points:
		var pred_2d: Dictionary[Vector2i, Vector2i] = {}
		var cost_2d := _dijkstra_2d(state, unit, points, effective_viewer, mask, pred_2d)
		for c: Vector2i in cost_2d:
			out[c] = _trace_2d(unit.coord, c, pred_2d)
		return out
	var pred: Dictionary[Vector3i, Vector3i] = {}
	var best := _best_states(_dijkstra_3d(state, unit, points, effective_viewer, mask, pred))
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
	var mask := Fog.mask_for(state, unit.team)
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
		if _blocked(state, unit, c, unit.team, mask):
			return false
		total += step
		if total > points:
			return false
	return true


## Fast 2D bucket-queue Dijkstra for the common case where fuel >= movement
## (every step costs at least 1 point, so fuel cannot bind). Minimizes
## (cost, steps) with O(1) bucket pops and exact CARDINAL_DIRS tie-breaking.
static func _dijkstra_2d(
	state: GameState,
	unit: UnitState,
	points: int,
	viewer_team: int,
	mask: PackedByteArray,
	pred: Dictionary[Vector2i, Vector2i]
) -> Dictionary[Vector2i, int]:
	var best_cost: Dictionary[Vector2i, int] = {unit.coord: 0}
	var best_steps: Dictionary[Vector2i, int] = {unit.coord: 0}
	var buckets: Array[Array] = []
	buckets.resize(points + 1)
	for i: int in range(points + 1):
		buckets[i] = []
	buckets[0].append(unit.coord)
	for cur_cost: int in range(points + 1):
		var bucket: Array = buckets[cur_cost]
		var bi: int = 0
		while bi < bucket.size():
			var cur: Vector2i = bucket[bi]
			bi += 1
			if best_cost[cur] != cur_cost:
				continue
			var cur_steps: int = best_steps[cur]
			for d: Vector2i in Grid.CARDINAL_DIRS:
				var n: Vector2i = cur + d
				var step: int = enter_cost(state, unit, n)
				if step < 0:
					continue
				if _blocked(state, unit, n, viewer_team, mask):
					continue
				var nc: int = cur_cost + step
				if nc > points:
					continue
				var ns: int = cur_steps + 1
				if best_cost.has(n):
					var prev_cost: int = best_cost[n]
					if nc > prev_cost or (nc == prev_cost and ns >= best_steps[n]):
						continue
				var needs_push: bool = not best_cost.has(n) or best_cost[n] != nc
				best_cost[n] = nc
				best_steps[n] = ns
				pred[n] = cur
				if needs_push:
					buckets[nc].append(n)
	return best_cost


## Fuel-constrained bounded Dijkstra over (x, y, steps) states packed as
## Vector3i with z = steps taken. Bucket queue pops in non-decreasing cost
## order so Pareto-dominated states (higher-or-equal cost AND steps) are
## pruned on pop.
static func _dijkstra_3d(
	state: GameState,
	unit: UnitState,
	points: int,
	viewer_team: int,
	mask: PackedByteArray,
	pred: Dictionary[Vector3i, Vector3i]
) -> Dictionary[Vector3i, int]:
	var max_steps: int = mini(unit.fuel, points)
	var start := Vector3i(unit.coord.x, unit.coord.y, 0)
	var cost: Dictionary[Vector3i, int] = {start: 0}
	var min_steps_expanded: Dictionary[Vector2i, int] = {}
	var buckets: Array[Array] = []
	buckets.resize(points + 1)
	for i: int in range(points + 1):
		buckets[i] = []
	buckets[0].append(start)
	for cur_cost: int in range(points + 1):
		var bucket: Array = buckets[cur_cost]
		var bi: int = 0
		while bi < bucket.size():
			var cur: Vector3i = bucket[bi]
			bi += 1
			if cost[cur] != cur_cost:
				continue
			var cur_coord := Vector2i(cur.x, cur.y)
			if min_steps_expanded.has(cur_coord) and cur.z >= min_steps_expanded[cur_coord]:
				continue
			min_steps_expanded[cur_coord] = cur.z
			if cur.z == max_steps:
				continue
			for d: Vector2i in Grid.CARDINAL_DIRS:
				var n: Vector2i = cur_coord + d
				var step: int = enter_cost(state, unit, n)
				if step < 0:
					continue
				if _blocked(state, unit, n, viewer_team, mask):
					continue
				var nc: int = cur_cost + step
				if nc > points:
					continue
				var ns := Vector3i(n.x, n.y, cur.z + 1)
				if cost.has(ns) and cost[ns] <= nc:
					continue
				cost[ns] = nc
				pred[ns] = cur
				buckets[nc].append(ns)
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


## Walks 2D predecessor links from `end` back to `start`.
static func _trace_2d(
	start: Vector2i, end: Vector2i, pred: Dictionary[Vector2i, Vector2i]
) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var cur := end
	while true:
		path.append(cur)
		if cur == start:
			break
		cur = pred[cur]
	path.reverse()
	return path


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


## Enemy units block planning only when `viewer_team` can SEE them —
## invisible blockers are fog's ambush mechanic, resolved in
## Rules.apply(), not here (§6). `mask` is an optional Fog.mask_for().
static func _blocked(
	state: GameState,
	mover: UnitState,
	coord: Vector2i,
	viewer_team: int = -1,
	mask: PackedByteArray = PackedByteArray()
) -> bool:
	var occupant := state.unit_at(coord)
	if occupant == null or occupant.team == mover.team:
		return false
	var team: int = mover.team if viewer_team < 0 else viewer_team
	return Fog.sees_unit(state, team, occupant, mask)
