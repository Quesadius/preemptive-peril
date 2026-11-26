class_name Combat
extends RefCounted
## Damage, counterattack, and ammo rules (§6).
##
## Formula shape per §6 with CO/power modifiers pinned at 100 until the CO
## milestone:
##   damage = base * (attacker_dhp / 10) * ((100 - stars * defender_dhp) / 100)
## floored to internal HP, plus a luck roll of 0..ruleset.luck_max on
## resolve only. ⚠ Coefficients are provisional until pinned against a
## community damage calculator (§6 warning) — the shape lives in one
## function so swapping constants is a one-line change.
##
## Weapon choice: primary if it lists the defender's key and has ammo,
## else secondary under the same test, else the unit cannot attack.
## Counters: only after surviving, only at range 1, only by units that can
## fire at range 1, using post-damage HP. preview() never mutates state
## and never advances the RNG; resolve() advances it and is called only
## from Rules.apply().


class DamagePreview:
	var damage: int = 0  # internal HP points, luckless
	var damage_display: float = 0.0  # for the UI, e.g. 5.5
	var counter_damage: int = 0
	var can_counter: bool = false
	var has_ammo: bool = false  # false = no usable weapon at all
	var attacker_mod: int = 100
	var defender_mod: int = 100
	var defender_stars: int = 0
	var kills_defender: bool = false


## Luckless damage forecast for the UI and AI, counterattack included.
## Never advances the RNG. When `from` is provided (non-negative coord),
## counterattack adjacency and attacker terrain defense are evaluated as
## if `attacker` had already moved to `from`. When has_ammo is false the
## attacker has no usable weapon and the other fields are meaningless.
static func preview(
	state: GameState, attacker_id: int, defender_id: int, from: Vector2i = Vector2i(-1, -1)
) -> DamagePreview:
	var p := DamagePreview.new()
	var attacker: UnitState = state.units[attacker_id]
	var defender: UnitState = state.units[defender_id]
	var origin: Vector2i = from if state.map.in_bounds(from) else attacker.coord
	var attacker_type: UnitType = state.ruleset.unit_types[attacker.type_id]
	var defender_type: UnitType = state.ruleset.unit_types[defender.type_id]
	var weapon: WeaponProfile = usable_weapon(state, attacker, defender)
	if weapon == null:
		return p
	p.has_ammo = true
	var base: int = weapon.damage_table.base_damage[defender_type.key]
	p.attacker_mod = attack_mod(state, attacker)
	p.defender_mod = defense_mod(state, defender)
	p.defender_stars = _stars_for(state, defender)
	p.damage = _scaled(
		base,
		attacker.display_hp(),
		defender.display_hp(),
		p.defender_stars,
		p.attacker_mod,
		p.defender_mod
	)
	p.damage_display = p.damage / 10.0
	var hp_after: int = maxi(defender.hp - p.damage, 0)
	p.kills_defender = hp_after == 0
	if hp_after == 0 or not _fires_at_range_one(defender_type):
		return p
	if Grid.manhattan(origin, defender.coord) != 1:
		return p
	var counter_weapon: WeaponProfile = usable_weapon(state, defender, attacker)
	if counter_weapon == null:
		return p
	p.can_counter = true
	var counter_base: int = counter_weapon.damage_table.base_damage[attacker_type.key]
	var dhp_after: int = int(ceil(hp_after / 10.0))
	p.counter_damage = _scaled(
		counter_base,
		dhp_after,
		attacker.display_hp(),
		_stars_for(state, attacker, origin),
		attack_mod(state, defender),
		defense_mod(state, attacker, origin)
	)
	return p


## Executes the attack, mutating both units and removing the destroyed.
## Returns the ordered events: UnitAttacked, then UnitDestroyed or
## UnitCounterattacked (+ UnitDestroyed). Advances the RNG (luck) — call
## only from Rules.apply(), after validation.
static func resolve(state: GameState, attacker_id: int, defender_id: int) -> Array[GameEvent]:
	var events: Array[GameEvent] = []
	var attacker: UnitState = state.units[attacker_id]
	var defender: UnitState = state.units[defender_id]
	var attacker_type: UnitType = state.ruleset.unit_types[attacker.type_id]
	var defender_type: UnitType = state.ruleset.unit_types[defender.type_id]
	var weapon: WeaponProfile = usable_weapon(state, attacker, defender)
	var base: int = weapon.damage_table.base_damage[defender_type.key]
	var dmg: int = _scaled(
		base,
		attacker.display_hp(),
		defender.display_hp(),
		_stars_for(state, defender),
		attack_mod(state, attacker),
		defense_mod(state, defender)
	)
	dmg += state.rng.roll_range(0, luck_max_for(state, attacker))
	var ammo_used: int = 0
	if weapon.uses_ammo:
		attacker.ammo -= 1
		ammo_used = 1
	var dealt: int = mini(dmg, defender.hp)
	defender.hp = maxi(defender.hp - dmg, 0)
	events.append(Events.UnitAttacked.new(attacker_id, defender_id, dmg, ammo_used))
	_charge(state, defender.team, dealt, events)
	@warning_ignore("integer_division")
	_charge(state, attacker.team, dealt / 2, events)
	if defender.hp == 0:
		events.append(destroy(state, defender))
		return events
	if not _fires_at_range_one(defender_type):
		return events
	if Grid.manhattan(attacker.coord, defender.coord) != 1:
		return events
	var counter_weapon: WeaponProfile = usable_weapon(state, defender, attacker)
	if counter_weapon == null:
		return events
	var counter_base: int = counter_weapon.damage_table.base_damage[attacker_type.key]
	var counter_dmg: int = _scaled(
		counter_base,
		defender.display_hp(),
		attacker.display_hp(),
		_stars_for(state, attacker),
		attack_mod(state, defender),
		defense_mod(state, attacker)
	)
	counter_dmg += state.rng.roll_range(0, luck_max_for(state, defender))
	var counter_ammo: int = 0
	if counter_weapon.uses_ammo:
		defender.ammo -= 1
		counter_ammo = 1
	var counter_dealt: int = mini(counter_dmg, attacker.hp)
	attacker.hp = maxi(attacker.hp - counter_dmg, 0)
	events.append(
		Events.UnitCounterattacked.new(defender_id, attacker_id, counter_dmg, counter_ammo)
	)
	_charge(state, attacker.team, counter_dealt, events)
	@warning_ignore("integer_division")
	_charge(state, defender.team, counter_dealt / 2, events)
	if attacker.hp == 0:
		events.append(destroy(state, attacker))
	return events


## Adds meter charge for `team` (full for damage taken, half for damage
## dealt, per the call sites). No charge without a CO or while a power
## burns; the meter caps at the super's cost.
static func _charge(state: GameState, team: int, amount: int, events: Array[GameEvent]) -> void:
	if amount <= 0:
		return
	var co := co_of(state, team)
	var player := Economy.player_of(state, team)
	if co == null or player == null or player.power_state != PlayerState.PowerState.NONE:
		return
	var cap: int = 0
	if co.super_power != null:
		cap = co.super_power.meter_cost
	elif co.power != null:
		cap = co.power.meter_cost
	var new_total: int = mini(player.power_meter + amount, cap)
	var delta: int = new_total - player.power_meter
	if delta <= 0:
		return
	player.power_meter = new_total
	events.append(Events.PowerCharged.new(team, delta, new_total))


## Effective max attack range for `unit`, including CO indirect-range bonuses.
static func attack_range_max_for(state: GameState, unit: UnitState) -> int:
	var unit_type: UnitType = state.ruleset.unit_types[unit.type_id]
	var max_r: int = unit_type.attack_range_max
	if unit_type.attack_range_min >= 2:
		var co := co_of(state, unit.team)
		if co != null:
			max_r += co.passive_indirect_range_bonus
			var active := active_power(state, unit.team)
			if active != null:
				max_r += active.indirect_range_bonus
	return max_r


## Tiles this unit could shoot standing on `from`: the range annulus,
## bounds-filtered. Empty when the unit cannot move and fire and `from`
## is not its current tile. Occupancy is not consulted — target legality
## is validate()'s job.
static func attackable_tiles(state: GameState, unit_id: int, from: Vector2i) -> Array[Vector2i]:
	var unit: UnitState = state.units[unit_id]
	var unit_type: UnitType = state.ruleset.unit_types[unit.type_id]
	if from != unit.coord and not unit_type.can_move_and_fire:
		return []
	var out: Array[Vector2i] = []
	var max_r: int = attack_range_max_for(state, unit)
	var ring := Grid.coords_in_range(from, unit_type.attack_range_min, max_r)
	for c: Vector2i in ring:
		if state.map.in_bounds(c):
			out.append(c)
	return out


## The weapon `attacker` would use against `defender`: primary if it lists
## the defender's type key and has ammo (or needs none), else secondary by
## the same test, else null (cannot attack this target).
static func usable_weapon(
	state: GameState, attacker: UnitState, defender: UnitState
) -> WeaponProfile:
	var attacker_type: UnitType = state.ruleset.unit_types[attacker.type_id]
	var defender_key: StringName = state.ruleset.unit_types[defender.type_id].key
	if _usable(attacker_type.primary_weapon, attacker, defender_key):
		return attacker_type.primary_weapon
	if _usable(attacker_type.secondary_weapon, attacker, defender_key):
		return attacker_type.secondary_weapon
	return null


static func _usable(weapon: WeaponProfile, attacker: UnitState, defender_key: StringName) -> bool:
	if weapon == null or weapon.damage_table == null:
		return false
	if not weapon.damage_table.base_damage.has(defender_key):
		return false
	return not weapon.uses_ammo or attacker.ammo > 0


## The one place the damage shape lives (see class doc). CO passives and
## active powers feed attack_mod/defense_mod; 100/100 is the no-CO case
## and reproduces the §6 base shape exactly.
static func _scaled(
	base: int,
	attacker_dhp: int,
	defender_dhp: int,
	stars: int,
	attack_mod: int = 100,
	defense_mod: int = 100
) -> int:
	var offense: float = base * (attacker_dhp / 10.0) * (attack_mod / 100.0)
	var mitigation: float = (200.0 - defense_mod - stars * defender_dhp) / 100.0
	return int(floor(offense * mitigation))


## Attack modifier for `unit`'s owner: 100 plus CO passives, role bonuses,
## active power bonus, and owned Comms Towers.
static func attack_mod(state: GameState, unit: UnitState) -> int:
	var mod: int = 100
	var unit_type: UnitType = state.ruleset.unit_types[unit.type_id]
	var co := co_of(state, unit.team)
	if co != null:
		mod += co.passive_attack_bonus
		if unit_type.attack_range_min >= 2:
			mod += co.passive_indirect_attack_bonus
		else:
			mod += co.passive_direct_attack_bonus
		if is_airborne(state, unit):
			mod += co.passive_air_attack_bonus
		var active := active_power(state, unit.team)
		if active != null:
			mod += active.attack_bonus
	mod += comms_tower_bonus(state, unit.team)
	return maxi(mod, 10)


## Total attack percentage bonus from Comms Towers (or any terrain with
## attack_bonus_percent) owned by `team`.
static func comms_tower_bonus(state: GameState, team: int) -> int:
	var bonus: int = 0
	for i: int in range(state.map.property_owner.size()):
		if state.map.property_owner[i] == team:
			bonus += state.ruleset.terrain_types[state.map.terrain[i]].attack_bonus_percent
	return bonus


## Defense modifier for `unit`'s owner, including per-star terrain cover bonuses.
static func defense_mod(state: GameState, unit: UnitState, at: Vector2i = Vector2i(-1, -1)) -> int:
	var mod: int = 100
	var co := co_of(state, unit.team)
	if co != null:
		mod += co.passive_defense_bonus
		var per_star: int = co.passive_terrain_defense_bonus
		var active := active_power(state, unit.team)
		if active != null:
			mod += active.defense_bonus
			per_star += active.terrain_defense_bonus
		if per_star != 0:
			mod += per_star * _stars_for(state, unit, at)
	return maxi(mod, 10)


## The luck ceiling for `unit`'s owner: ruleset base plus CO bonuses.
static func luck_max_for(state: GameState, unit: UnitState) -> int:
	var ceiling: int = state.ruleset.luck_max
	var co := co_of(state, unit.team)
	if co != null:
		ceiling += co.passive_luck_bonus
		var active := active_power(state, unit.team)
		if active != null:
			ceiling += active.luck_bonus
	return ceiling


## The CO commanding `team`, or null.
static func co_of(state: GameState, team: int) -> COProfile:
	var player := Economy.player_of(state, team)
	if player == null or player.co_id < 0 or player.co_id >= state.ruleset.cos.size():
		return null
	return state.ruleset.cos[player.co_id]


## The power currently burning for `team`, or null.
static func active_power(state: GameState, team: int) -> COPower:
	var player := Economy.player_of(state, team)
	var co := co_of(state, team)
	if player == null or co == null:
		return null
	match player.power_state:
		PlayerState.PowerState.CO_POWER:
			return co.power
		PlayerState.PowerState.SUPER:
			return co.super_power
	return null


## Defense stars protecting `unit` at `at` (defaults to `unit.coord`): the
## terrain's, or none for airborne units.
static func _stars_for(state: GameState, unit: UnitState, at: Vector2i = Vector2i(-1, -1)) -> int:
	if is_airborne(state, unit):
		return 0
	var coord: Vector2i = at if state.map.in_bounds(at) else unit.coord
	return state.ruleset.terrain_types[state.map.terrain_at(coord)].defense_stars


## True when `unit`'s movement class flies (MovementClass.airborne).
static func is_airborne(state: GameState, unit: UnitState) -> bool:
	var mc: MovementClass = state.ruleset.unit_types[unit.type_id].movement_class
	return mc != null and mc.airborne


## Direct-combat check: can this unit fire at range 1 (and therefore
## counterattack)? Indirects (min range 2+) never counter.
static func _fires_at_range_one(unit_type: UnitType) -> bool:
	return unit_type.attack_range_min <= 1 and unit_type.attack_range_max >= 1


## Removes `unit` from play (combat kills, crashes) and returns the
## UnitDestroyed event. The single removal path: occupancy, capture
## progress, and any carried cargo go with it.
static func destroy(state: GameState, unit: UnitState) -> GameEvent:
	for cargo_id: int in unit.cargo:
		state.units.erase(cargo_id)  # passengers go down with the carrier
	state.units.erase(unit.id)
	state.occupancy.erase(unit.coord)
	state.map.capture_progress.erase(unit.coord)  # a dead capturer forfeits progress
	return Events.UnitDestroyed.new(unit.id, unit.coord, unit.team)
