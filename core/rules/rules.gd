class_name Rules
extends RefCounted
## The front door (§4): presentation and AI submit Actions here and
## consume the returned events. Nothing else mutates GameState.
##
## Verbs implemented so far: WAIT, ATTACK, CAPTURE, plus BuildAction and
## EndTurnAction. The rest validate to VERB_NOT_IMPLEMENTED until their
## milestone.


## null when legal; otherwise a reason code the UI can display.
static func validate(state: GameState, action: Action) -> ActionError:
	if action is UnitAction:
		return _validate_unit_action(state, action as UnitAction)
	if action is BuildAction:
		return Economy.validate_build(state, action as BuildAction)
	if action is PowerAction:
		return _validate_power(state, action as PowerAction)
	if action is EndTurnAction:
		return null
	return ActionError.new(ActionError.UNKNOWN_ACTION)


## Mutates `state` in place and returns the ordered event log.
## Precondition: validate() returned null. The only entry point allowed
## to advance state.rng.
static func apply(state: GameState, action: Action) -> Array[GameEvent]:
	var events: Array[GameEvent] = []
	if action is UnitAction:
		events = _apply_unit_action(state, action as UnitAction)
	elif action is BuildAction:
		events = Economy.apply_build(state, action as BuildAction)
	elif action is PowerAction:
		events = _apply_power(state, action as PowerAction)
	elif action is EndTurnAction:
		events = _apply_end_turn(state)
	events.append_array(Victory.check(state, events))
	return events


static func _validate_power(state: GameState, action: PowerAction) -> ActionError:
	var player := state.active_player()
	var co := Combat.co_of(state, player.team)
	if co == null:
		return ActionError.new(ActionError.NO_CO)
	if player.power_state != PlayerState.PowerState.NONE:
		return ActionError.new(ActionError.POWER_ALREADY_ACTIVE)
	var power := _power_for_level(co, action.power_level)
	if power == null:
		return ActionError.new(ActionError.NO_CO)
	if player.power_meter < power.meter_cost:
		return ActionError.new(ActionError.INSUFFICIENT_METER)
	return null


## Burns the meter, applies the one-shot heal, and marks the power
## active until the player's next turn begins.
static func _apply_power(state: GameState, action: PowerAction) -> Array[GameEvent]:
	var player := state.active_player()
	var co := Combat.co_of(state, player.team)
	var power := _power_for_level(co, action.power_level)
	player.power_meter -= power.meter_cost
	player.power_state = action.power_level
	player.power_turns_left = 1
	if power.heal_hp > 0:
		for u: UnitState in state.units_of(player.team):
			u.hp = mini(u.hp + power.heal_hp, 100)
	return [Events.PowerActivated.new(player.team, action.power_level, player.co_id)]


static func _power_for_level(co: COProfile, level: int) -> COPower:
	if co == null:
		return null
	match level:
		PlayerState.PowerState.CO_POWER:
			return co.power
		PlayerState.PowerState.SUPER:
			return co.super_power
	return null


static func _validate_unit_action(state: GameState, ua: UnitAction) -> ActionError:
	if not state.units.has(ua.unit_id):
		return ActionError.new(ActionError.UNKNOWN_UNIT)
	var unit: UnitState = state.units[ua.unit_id]
	if unit.team != state.active_player().team:
		return ActionError.new(ActionError.NOT_YOUR_TURN)
	if unit.has_acted:
		return ActionError.new(ActionError.UNIT_EXHAUSTED)
	# Passengers share the carrier's coord but not its occupancy entry; a
	# passenger "moving" would erase the carrier from occupancy and leave
	# itself in the cargo list. It leaves only via the carrier's UNLOAD.
	if unit.carrier_id != -1:
		return ActionError.new(ActionError.UNIT_IN_TRANSPORT)
	var implemented: Array[int] = [
		UnitAction.Verb.WAIT,
		UnitAction.Verb.ATTACK,
		UnitAction.Verb.CAPTURE,
		UnitAction.Verb.LOAD,
		UnitAction.Verb.UNLOAD,
		UnitAction.Verb.SUPPLY,
		UnitAction.Verb.JOIN,
	]
	if not implemented.has(ua.verb):
		return ActionError.new(ActionError.VERB_NOT_IMPLEMENTED)
	if not Movement.validate_path(state, ua.unit_id, ua.path):
		return ActionError.new(ActionError.ILLEGAL_PATH)
	var dest: Vector2i = ua.path[ua.path.size() - 1]
	var occupant: UnitState = Fog.known_occupant(state, unit.team, dest)
	# LOAD and JOIN end ON another unit; every other verb needs the tile
	# free (or the mover's own).
	if ua.verb == UnitAction.Verb.LOAD:
		return Transport.validate_load(state, unit, occupant)
	if ua.verb == UnitAction.Verb.JOIN:
		return Transport.validate_join(state, unit, occupant)
	if occupant != null and occupant != unit:
		return ActionError.new(ActionError.DESTINATION_OCCUPIED)
	match ua.verb:
		UnitAction.Verb.ATTACK:
			return _validate_attack(state, ua, unit, dest)
		UnitAction.Verb.CAPTURE:
			return Capture.validate(state, unit, dest)
		UnitAction.Verb.SUPPLY:
			return Supply.validate_supply(state, unit, dest)
		UnitAction.Verb.UNLOAD:
			return Transport.validate_unload(state, unit, dest, ua.cargo_index, ua.target_coord)
	return null


static func _validate_attack(
	state: GameState, ua: UnitAction, unit: UnitState, dest: Vector2i
) -> ActionError:
	var unit_type: UnitType = state.ruleset.unit_types[unit.type_id]
	if ua.path.size() > 1 and not unit_type.can_move_and_fire:
		return ActionError.new(ActionError.CANNOT_MOVE_AND_FIRE)
	# Fog-honest, matching ActionGenerator: a hidden unit is no target —
	# otherwise validate() would answer "is anyone on that tile?".
	var target: UnitState = Fog.known_occupant(state, unit.team, ua.target_coord)
	if target == null or target.team == unit.team:
		return ActionError.new(ActionError.NO_TARGET)
	var dist: int = Grid.manhattan(dest, ua.target_coord)
	if dist < unit_type.attack_range_min or dist > unit_type.attack_range_max:
		return ActionError.new(ActionError.TARGET_OUT_OF_RANGE)
	if Combat.usable_weapon(state, unit, target) == null:
		return ActionError.new(ActionError.CANNOT_ATTACK_TARGET)
	return null


static func _apply_unit_action(state: GameState, ua: UnitAction) -> Array[GameEvent]:
	var unit: UnitState = state.units[ua.unit_id]
	var events: Array[GameEvent] = []
	var ambusher: UnitState = null
	var verb: int = ua.verb
	if ua.path.size() > 1:
		# Fog ambush (§6): walk the intended path; an unseen enemy stops
		# the move on the last free tile before it and cancels the order.
		var stop_index: int = ua.path.size() - 1
		if state.config.fog_enabled:
			for i: int in range(1, ua.path.size()):
				var occupant := state.unit_at(ua.path[i])
				if occupant != null and occupant.team != unit.team:
					ambusher = occupant
					stop_index = i - 1
					while stop_index > 0 and state.unit_at(ua.path[stop_index]) != null:
						stop_index -= 1
					break
		if ambusher != null:
			verb = UnitAction.Verb.WAIT  # the trap cancels whatever was ordered
		if stop_index > 0:
			var dest: Vector2i = ua.path[stop_index]
			state.map.capture_progress.erase(unit.coord)  # leaving abandons a capture
			state.occupancy.erase(unit.coord)
			unit.coord = dest
			# LOAD and JOIN land on the carrier/target's tile: the verb
			# finishes the occupancy bookkeeping, not the move.
			var lands_on_unit: bool = verb == UnitAction.Verb.LOAD or verb == UnitAction.Verb.JOIN
			if not lands_on_unit:
				state.occupancy[dest] = ua.unit_id
			unit.fuel -= stop_index  # per-tile fuel: one per tile entered
			unit.has_moved = true
			var interrupted_at: int = stop_index if ambusher != null else -1
			events.append(Events.UnitMoved.new(ua.unit_id, ua.path.duplicate(), interrupted_at))
		if ambusher != null:
			events.append(Events.UnitAmbushed.new(ua.unit_id, ambusher.id, ambusher.coord))
	match verb:
		UnitAction.Verb.ATTACK:
			var target: UnitState = state.unit_at(ua.target_coord)
			events.append_array(Combat.resolve(state, ua.unit_id, target.id))
		UnitAction.Verb.CAPTURE:
			events.append_array(Capture.apply(state, unit))
		UnitAction.Verb.SUPPLY:
			events.append_array(Supply.apply_supply(state, unit))
		UnitAction.Verb.LOAD:
			var carrier := state.unit_at(unit.coord)
			events.append_array(Transport.apply_load(state, unit, carrier))
		UnitAction.Verb.JOIN:
			var join_target := state.unit_at(unit.coord)
			events.append_array(Transport.apply_join(state, unit, join_target))
		UnitAction.Verb.UNLOAD:
			events.append_array(
				Transport.apply_unload(state, unit, ua.cargo_index, ua.target_coord)
			)
	if state.units.has(ua.unit_id):  # the attacker may have died to the counter
		unit.has_acted = true
		events.append(Events.UnitExhausted.new(ua.unit_id))
	return events


static func _apply_end_turn(state: GameState) -> Array[GameEvent]:
	var events := TurnFlow.end_turn(state)
	events.append_array(TurnFlow.begin_turn(state, state.active_player().team))
	return events
