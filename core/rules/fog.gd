class_name Fog
extends RefCounted
## Visibility computation (§6). Vision is per-unit radius (plus the
## terrain's vision bonus under the unit) and owned properties light
## their own tile. Terrain with hides_units (forests) conceals enemies
## even on lit tiles unless one of the viewer's units stands adjacent.
##
## compute() is recomputed on demand. Queries that run per tile or per
## unit (movement search, action generation, visible-unit lists) take
## an optional precomputed mask from mask_for() so one query costs one
## compute, not one per lookup. When config.fog_enabled is false every
## query answers "visible".


## Bitmask for `team`: one byte per tile, 1 = lit. Row-major w*h.
static func compute(state: GameState, team: int) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(state.map.terrain.size())
	for uid: int in state.units:
		var unit: UnitState = state.units[uid]
		if unit.team != team or unit.carrier_id != -1:
			continue  # loaded units see nothing
		var unit_type: UnitType = state.ruleset.unit_types[unit.type_id]
		var under: TerrainType = state.ruleset.terrain_types[state.map.terrain_at(unit.coord)]
		var radius: int = unit_type.vision
		if not Combat.is_airborne(state, unit):
			radius += under.vision_bonus  # flyers aren't standing on the mountain
		for c: Vector2i in Grid.coords_in_range(unit.coord, 0, radius):
			if state.map.in_bounds(c):
				mask[state.map.idx(c)] = 1
	for i: int in range(state.map.property_owner.size()):
		if state.map.property_owner[i] == team:
			mask[i] = 1
	return mask


## True when `team` can see the tile at `coord`. Always true with fog
## disabled.
static func tile_visible(state: GameState, team: int, coord: Vector2i) -> bool:
	if not state.config.fog_enabled:
		return true
	return compute(state, team)[state.map.idx(coord)] == 1


## compute() for `team` when fog is on; an empty array when it is off
## (every query answers "visible" then, so no mask is needed). Compute
## once per query and pass it to sees_unit / sees_at / known_occupant.
static func mask_for(state: GameState, team: int) -> PackedByteArray:
	if not state.config.fog_enabled:
		return PackedByteArray()
	return compute(state, team)


## True when `team` knows about `unit`: own units always; enemies when
## their tile is lit — except ground units on hiding terrain, which need one of the
## viewer's units adjacent. `mask` is an optional mask_for() result for
## `team`, computed here when omitted.
static func sees_unit(
	state: GameState, team: int, unit: UnitState, mask: PackedByteArray = PackedByteArray()
) -> bool:
	if not state.config.fog_enabled or unit.team == team:
		return true
	if Combat.is_airborne(state, unit):
		return _lit(state, team, unit.coord, mask)  # nothing hides a flyer
	return sees_at(state, team, unit.coord, mask)


## True when `team` would see an enemy standing on `coord`: the tile is
## lit and, on hiding terrain, one of `team`'s units stands adjacent.
## Always true with fog disabled. `mask` as in sees_unit().
static func sees_at(
	state: GameState, team: int, coord: Vector2i, mask: PackedByteArray = PackedByteArray()
) -> bool:
	if not state.config.fog_enabled:
		return true
	if not state.map.in_bounds(coord):
		return false
	var terrain: TerrainType = state.ruleset.terrain_types[state.map.terrain_at(coord)]
	if terrain.hides_units:
		# Occupancy holds exactly the units not loaded in a carrier, so the
		# four neighbors are the only viewers that can reveal this tile.
		for n: Vector2i in Grid.neighbors(coord):
			var viewer := state.unit_at(n)
			if viewer != null and viewer.team == team:
				return true
		return false
	return _lit(state, team, coord, mask)


static func _lit(state: GameState, team: int, coord: Vector2i, mask: PackedByteArray) -> bool:
	if not state.map.in_bounds(coord):
		return false
	if mask.is_empty():
		mask = compute(state, team)
	return mask[state.map.idx(coord)] == 1


## The occupant of `coord` as far as `team` knows: invisible enemies
## read as an empty tile. This is what validation and generation consult
## so orders onto suspected-empty tiles stay legal — execution handles
## the ambush. `mask` as in sees_unit().
static func known_occupant(
	state: GameState, team: int, coord: Vector2i, mask: PackedByteArray = PackedByteArray()
) -> UnitState:
	var occupant := state.unit_at(coord)
	if occupant == null or sees_unit(state, team, occupant, mask):
		return occupant
	return null


## Fog-filtered projection — what this team is allowed to know (§6).
static func project(state: GameState, team: int) -> StateView:
	return StateView.for_team(state, team)
