class_name Supply
extends RefCounted
## Resupply, repair, and fuel drain (§6): the SUPPLY verb for
## supply-capable units, plus the start-of-turn sequences TurnFlow runs
## in contract order — repair (costs funds, so after income), then fuel
## drain, then crash checks.
##
## Repair heals up to ruleset.repair_hp_per_turn internal HP at
## cost * healed / 100 funds, skipped when unaffordable; properties also
## refill fuel and ammo for classes they repair. UnitRepaired carries the
## cost — no separate FundsChanged is emitted for repairs.


## null when `unit`, stopping on `coord`, may supply: it must be
## supply-capable with at least one adjacent ally.
static func validate_supply(state: GameState, unit: UnitState, coord: Vector2i) -> ActionError:
	var unit_type: UnitType = state.ruleset.unit_types[unit.type_id]
	if not unit_type.supply_capable:
		return ActionError.new(ActionError.CANNOT_SUPPLY)
	if allies_adjacent(state, unit, coord).is_empty():
		return ActionError.new(ActionError.NOTHING_TO_SUPPLY)
	return null


## Adjacent allied units (excluding the supplier itself) around `coord`,
## in Grid.CARDINAL_DIRS order.
static func allies_adjacent(state: GameState, unit: UnitState, coord: Vector2i) -> Array[UnitState]:
	var out: Array[UnitState] = []
	for n: Vector2i in Grid.neighbors(coord):
		var ally := state.unit_at(n)
		if ally != null and ally.team == unit.team and ally.id != unit.id:
			out.append(ally)
	return out


## Tops up every adjacent ally's fuel and ammo. Precondition: validated.
static func apply_supply(state: GameState, unit: UnitState) -> Array[GameEvent]:
	var events: Array[GameEvent] = []
	for ally: UnitState in allies_adjacent(state, unit, unit.coord):
		var ally_type: UnitType = state.ruleset.unit_types[ally.type_id]
		if ally.fuel == ally_type.max_fuel and ally.ammo == ally_type.max_ammo:
			continue
		ally.fuel = ally_type.max_fuel
		ally.ammo = ally_type.max_ammo
		events.append(Events.UnitResupplied.new(ally.id, ally.fuel, ally.ammo))
	return events


## Start-of-turn repair and resupply on owned properties that service the
## unit's movement class. Income has already landed; repairs stop when
## funds run dry, resupply is free.
static func begin_turn_repairs(state: GameState, team: int) -> Array[GameEvent]:
	var events: Array[GameEvent] = []
	var player := Economy.player_of(state, team)
	for u: UnitState in state.units_of(team):
		if u.carrier_id != -1:
			continue
		if state.map.property_owner[state.map.idx(u.coord)] != team:
			continue
		var terrain: TerrainType = state.ruleset.terrain_types[state.map.terrain_at(u.coord)]
		var unit_type: UnitType = state.ruleset.unit_types[u.type_id]
		if not _repairs_class(terrain, unit_type.movement_class):
			continue
		var heal: int = mini(state.ruleset.repair_hp_per_turn, 100 - u.hp)
		if heal > 0:
			@warning_ignore("integer_division")
			var cost: int = unit_type.cost * heal / 100
			if player.funds >= cost:
				player.funds -= cost
				u.hp += heal
				events.append(Events.UnitRepaired.new(u.id, heal, cost))
		if u.fuel != unit_type.max_fuel or u.ammo != unit_type.max_ammo:
			u.fuel = unit_type.max_fuel
			u.ammo = unit_type.max_ammo
			events.append(Events.UnitResupplied.new(u.id, u.fuel, u.ammo))
	return events


## Start-of-turn daily fuel drain, then crash checks for units that
## cannot fly (or sail) on empty.
static func begin_turn_fuel(state: GameState, team: int) -> Array[GameEvent]:
	var events: Array[GameEvent] = []
	for u: UnitState in state.units_of(team):
		if u.carrier_id != -1:
			continue
		var unit_type: UnitType = state.ruleset.unit_types[u.type_id]
		if unit_type.fuel_per_turn > 0 and u.fuel > 0:
			var amount: int = mini(unit_type.fuel_per_turn, u.fuel)
			u.fuel -= amount
			events.append(Events.UnitFuelDrained.new(u.id, amount, u.fuel))
	for u: UnitState in state.units_of(team):
		if u.carrier_id != -1:
			continue
		var unit_type: UnitType = state.ruleset.unit_types[u.type_id]
		if unit_type.crashes_without_fuel and u.fuel == 0:
			events.append(Combat.destroy(state, u))
	return events


static func _repairs_class(terrain: TerrainType, mc: MovementClass) -> bool:
	if mc == null:
		return false
	for rc: MovementClass in terrain.repairs_classes:
		if rc.key == mc.key:
			return true
	return false
