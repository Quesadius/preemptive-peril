class_name Ids
extends RefCounted
## Unit id allocation and registration (§2). The one place a new unit
## enters `units` and `occupancy`, so the id counter and both indexes
## can never drift apart.


## Creates a unit of `type_id` for `team` at `coord` with stats at type
## maxima, registers it, and advances next_unit_id. The coord must be
## empty — callers (build rules, map loading) check legality first.
static func create_unit(state: GameState, type_id: int, team: int, coord: Vector2i) -> UnitState:
	var unit_type: UnitType = state.ruleset.unit_types[type_id]
	var u := UnitState.new()
	u.id = state.next_unit_id
	state.next_unit_id += 1
	u.type_id = type_id
	u.team = team
	u.coord = coord
	u.fuel = unit_type.max_fuel
	u.ammo = unit_type.max_ammo
	state.units[u.id] = u
	state.occupancy[coord] = u.id
	return u
