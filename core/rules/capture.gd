class_name Capture
extends RefCounted
## Capture rules: progress, completion, reset. A capture step adds the
## capturing unit's displayed HP to the tile's progress; at
## ruleset.capture_threshold the property changes hands. Progress dies
## with the attempt — moving off the tile (Rules.apply's move step) or
## losing the unit (Combat's destroy) erases it.


## null when `unit` may capture the property at `coord` (which the rules
## have already established the unit will be standing on).
static func validate(state: GameState, unit: UnitState, coord: Vector2i) -> ActionError:
	var unit_type: UnitType = state.ruleset.unit_types[unit.type_id]
	if not unit_type.capture_capable:
		return ActionError.new(ActionError.CANNOT_CAPTURE)
	var terrain: TerrainType = state.ruleset.terrain_types[state.map.terrain_at(coord)]
	if not terrain.capturable:
		return ActionError.new(ActionError.NOT_CAPTURABLE)
	if state.map.property_owner[state.map.idx(coord)] == unit.team:
		return ActionError.new(ActionError.ALREADY_OWNED)
	return null


## One capture step by `unit` on its own tile. Precondition: validated.
static func apply(state: GameState, unit: UnitState) -> Array[GameEvent]:
	var coord := unit.coord
	var previous: int = 0
	if state.map.capture_progress.has(coord):
		previous = state.map.capture_progress[coord]
	var points: int = unit.display_hp()
	var total: int = previous + points
	if total >= state.ruleset.capture_threshold:
		var idx: int = state.map.idx(coord)
		var old_team: int = state.map.property_owner[idx]
		state.map.capture_progress.erase(coord)
		state.map.property_owner[idx] = unit.team
		return [Events.PropertyCaptured.new(coord, unit.team, old_team)]
	state.map.capture_progress[coord] = total
	return [Events.CaptureProgressed.new(coord, unit.id, points, total)]
