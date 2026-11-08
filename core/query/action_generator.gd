class_name ActionGenerator
extends RefCounted
## Enumerates every legal action — the single source of "what can I do",
## shared by the UI's menus and the AI's search (§6). If an action is
## generated here it passes Rules.validate(), and if a canonical-path
## action passes validate() it is generated here; tests enforce both
## directions. Targets are evaluated against pre-move occupancy, exactly
## as validate() sees them.
##
## Orderings are deterministic: units by id, destinations row-major,
## ATTACK (one action per target, in Combat.attackable_tiles order)
## before WAIT, EndTurnAction last.


## Every legal action for the active player. EndTurnAction is always
## legal and always last.
static func generate(state: GameState) -> Array[Action]:
	var out: Array[Action] = []
	for unit: UnitState in state.units_of(state.active_player().team):
		out.append_array(for_unit(state, unit.id))
	out.append_array(builds(state))
	out.append_array(powers(state))
	out.append(EndTurnAction.new())
	return out


## Legal CO power activations for the active player (normal before
## super).
static func powers(state: GameState) -> Array[Action]:
	var out: Array[Action] = []
	var levels: Array[int] = [PlayerState.PowerState.CO_POWER, PlayerState.PowerState.SUPER]
	for level: int in levels:
		var action := PowerAction.new()
		action.power_level = level
		if Rules.validate(state, action) == null:
			out.append(action)
	return out


## Every legal BuildAction for the active player: owned production tiles
## in row-major order, buildable types in roster order.
static func builds(state: GameState) -> Array[Action]:
	var out: Array[Action] = []
	var team: int = state.active_player().team
	for i: int in range(state.map.property_owner.size()):
		if state.map.property_owner[i] != team:
			continue
		if state.ruleset.terrain_types[state.map.terrain[i]].builds == &"":
			continue  # cities and the like: nothing to probe
		var coord := Grid.from_idx(i, state.map.width)
		for type_id: int in Economy.buildable_units(state, coord):
			var action := BuildAction.new()
			action.unit_type_id = type_id
			action.coord = coord
			out.append(action)
	return out


## Legal actions for one unit, with canonical (cheapest) paths. Empty for
## units that cannot act: wrong team, exhausted, or loaded in a carrier.
## Requires `unit_id` to exist in `state.units`.
static func for_unit(state: GameState, unit_id: int) -> Array[Action]:
	var out: Array[Action] = []
	var unit: UnitState = state.units[unit_id]
	if not _can_act(state, unit):
		return out
	var mask := Fog.mask_for(state, unit.team)
	var paths := Movement.all_paths(state, unit_id)
	var dests: Array[Vector2i] = []
	dests.assign(paths.keys())
	dests.sort_custom(_row_major)
	for dest: Vector2i in dests:
		var occupant: UnitState = Fog.known_occupant(state, unit.team, dest, mask)
		var path: Array[Vector2i] = paths[dest]
		if occupant != null and occupant != unit:
			# Ally tile: LOAD into a carrier or JOIN a twin, nothing else.
			if Transport.validate_load(state, unit, occupant) == null:
				out.append(_verb_action(unit_id, path, UnitAction.Verb.LOAD))
			if Transport.validate_join(state, unit, occupant) == null:
				out.append(_verb_action(unit_id, path, UnitAction.Verb.JOIN))
			continue
		for target: Vector2i in _attack_targets(state, unit, dest, mask):
			var attack := _verb_action(unit_id, path, UnitAction.Verb.ATTACK)
			attack.target_coord = target
			out.append(attack)
		if Capture.validate(state, unit, dest) == null:
			out.append(_verb_action(unit_id, path, UnitAction.Verb.CAPTURE))
		if Supply.validate_supply(state, unit, dest) == null:
			out.append(_verb_action(unit_id, path, UnitAction.Verb.SUPPLY))
		for cargo_index: int in range(unit.cargo.size()):
			for drop: Vector2i in Grid.neighbors(dest):
				if Transport.validate_unload(state, unit, dest, cargo_index, drop, mask) == null:
					var unload := _verb_action(unit_id, path, UnitAction.Verb.UNLOAD)
					unload.cargo_index = cargo_index
					unload.target_coord = drop
					out.append(unload)
		out.append(_verb_action(unit_id, path, UnitAction.Verb.WAIT))
	return out


static func _verb_action(unit_id: int, path: Array[Vector2i], verb: int) -> UnitAction:
	var action := UnitAction.new()
	action.unit_id = unit_id
	action.path = path.duplicate()
	action.verb = verb
	return action


## Verbs available if `unit_id` stops on `dest`, in menu order (ATTACK
## then CAPTURE, SUPPLY, UNLOAD, then WAIT; ally-occupied destinations
## offer LOAD or JOIN instead). Empty when the unit cannot act or cannot
## reach `dest`.
static func verbs_at(state: GameState, unit_id: int, dest: Vector2i) -> Array[int]:
	var out: Array[int] = []
	var unit: UnitState = state.units[unit_id]
	if not _can_act(state, unit):
		return out
	if not Movement.reachable(state, unit_id).has(dest):
		return out
	var mask := Fog.mask_for(state, unit.team)
	var occupant: UnitState = Fog.known_occupant(state, unit.team, dest, mask)
	if occupant != null and occupant != unit:
		if Transport.validate_load(state, unit, occupant) == null:
			out.append(UnitAction.Verb.LOAD)
		if Transport.validate_join(state, unit, occupant) == null:
			out.append(UnitAction.Verb.JOIN)
		return out
	if not _attack_targets(state, unit, dest, mask).is_empty():
		out.append(UnitAction.Verb.ATTACK)
	if Capture.validate(state, unit, dest) == null:
		out.append(UnitAction.Verb.CAPTURE)
	if Supply.validate_supply(state, unit, dest) == null:
		out.append(UnitAction.Verb.SUPPLY)
	if _has_unload_option(state, unit, dest, mask):
		out.append(UnitAction.Verb.UNLOAD)
	out.append(UnitAction.Verb.WAIT)
	return out


static func _has_unload_option(
	state: GameState, unit: UnitState, dest: Vector2i, mask: PackedByteArray
) -> bool:
	for cargo_index: int in range(unit.cargo.size()):
		for drop: Vector2i in Grid.neighbors(dest):
			if Transport.validate_unload(state, unit, dest, cargo_index, drop, mask) == null:
				return true
	return false


static func _can_act(state: GameState, unit: UnitState) -> bool:
	if unit.team != state.active_player().team:
		return false
	return not unit.has_acted and unit.carrier_id == -1


## Enemy coords this unit could legally shoot after stopping on `dest`.
## Under fog only VISIBLE enemies are targets — you can't order fire on
## a unit you don't know about.
static func _attack_targets(
	state: GameState, unit: UnitState, dest: Vector2i, mask: PackedByteArray
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c: Vector2i in Combat.attackable_tiles(state, unit.id, dest):
		var target: UnitState = state.unit_at(c)
		if target == null or target.team == unit.team:
			continue
		if not Fog.sees_unit(state, unit.team, target, mask):
			continue
		if Combat.usable_weapon(state, unit, target) == null:
			continue
		out.append(c)
	return out


static func _row_major(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)
