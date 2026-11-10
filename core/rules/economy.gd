class_name Economy
extends RefCounted
## Income and build legality (§6). Per-property income comes from
## TerrainType.income when authored, falling back to
## Ruleset.funds_per_property for property terrains without a figure.


## Total start-of-turn income for `team`: what its owned properties pay,
## scaled by the player's income_percent (rounded down).
static func income_for(state: GameState, team: int) -> int:
	var total: int = 0
	for i: int in range(state.map.property_owner.size()):
		if state.map.property_owner[i] != team:
			continue
		var terrain: TerrainType = state.ruleset.terrain_types[state.map.terrain[i]]
		total += terrain.income if terrain.income > 0 else state.ruleset.funds_per_property
	var player := player_of(state, team)
	if player != null and player.income_percent != 100:
		@warning_ignore("integer_division")
		total = total * player.income_percent / 100
	return total


## The PlayerState for `team`, or null if no such player exists.
static func player_of(state: GameState, team: int) -> PlayerState:
	for p: PlayerState in state.players:
		if p.team == team:
			return p
	return null


## null when the active player may build `action.unit_type_id` at
## `action.coord`: an owned, unoccupied production property whose build
## key the unit type lists, with funds and headcount to spare.
static func validate_build(state: GameState, action: BuildAction) -> ActionError:
	if action.unit_type_id < 0 or action.unit_type_id >= state.ruleset.unit_types.size():
		return ActionError.new(ActionError.UNKNOWN_UNIT_TYPE)
	if not state.map.in_bounds(action.coord):
		return ActionError.new(ActionError.NOT_YOUR_PROPERTY)
	var team: int = state.active_player().team
	if state.map.property_owner[state.map.idx(action.coord)] != team:
		return ActionError.new(ActionError.NOT_YOUR_PROPERTY)
	var terrain: TerrainType = state.ruleset.terrain_types[state.map.terrain_at(action.coord)]
	var unit_type: UnitType = state.ruleset.unit_types[action.unit_type_id]
	if terrain.builds == &"" or not unit_type.built_at.has(terrain.builds):
		return ActionError.new(ActionError.CANNOT_BUILD_TYPE)
	if state.unit_at(action.coord) != null:
		return ActionError.new(ActionError.DESTINATION_OCCUPIED)
	if state.active_player().funds < unit_type.cost:
		return ActionError.new(ActionError.INSUFFICIENT_FUNDS)
	if _headcount(state, team) >= state.ruleset.max_units_per_player:
		return ActionError.new(ActionError.UNIT_LIMIT_REACHED)
	return null


## Units `team` fields, loaded cargo included — units_of().size()
## without building and sorting the array.
static func _headcount(state: GameState, team: int) -> int:
	var count: int = 0
	for uid: int in state.units:
		if state.units[uid].team == team:
			count += 1
	return count


## Pays for and creates the unit, exhausted for this turn (it can act
## next turn). Precondition: validate_build() returned null.
static func apply_build(state: GameState, action: BuildAction) -> Array[GameEvent]:
	var team: int = state.active_player().team
	var unit_type: UnitType = state.ruleset.unit_types[action.unit_type_id]
	var player := state.active_player()
	player.funds -= unit_type.cost
	var unit := Ids.create_unit(state, action.unit_type_id, team, action.coord)
	unit.has_acted = true
	return [
		Events.UnitCreated.new(unit.id, action.unit_type_id, team, action.coord),
		Events.FundsChanged.new(team, -unit_type.cost, player.funds, &"build"),
	]


## Type ids the active player could build at `coord` right now, in
## roster order — the build menu's item list, straight from the one
## source of legality.
static func buildable_units(state: GameState, coord: Vector2i) -> Array[int]:
	var out: Array[int] = []
	for type_id: int in range(state.ruleset.unit_types.size()):
		var probe := BuildAction.new()
		probe.unit_type_id = type_id
		probe.coord = coord
		if validate_build(state, probe) == null:
			out.append(type_id)
	return out
