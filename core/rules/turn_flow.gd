class_name TurnFlow
extends RefCounted
## Start-of-turn and end-of-turn sequences (§6).
##
## The begin_turn order is a contract — income before repair (repairs cost
## funds), repair before fuel drain, fuel drain before crash checks, then
## capture reset, power meter, weather, un-exhaust. Each item slots into
## its marked position when its milestone lands; milestone 2 implements
## player rotation and un-exhaust only.


## Start-of-turn sequence for `team`. Emits TurnStarted and resets the
## team's units to fresh (un-exhausted). Later milestones insert income,
## repair, fuel drain, crash checks, capture reset, power meter and
## weather here, in that order.
static func begin_turn(state: GameState, team: int) -> Array[GameEvent]:
	var events: Array[GameEvent] = [Events.TurnStarted.new(team, state.day)]
	var income: int = Economy.income_for(state, team)
	if income > 0:
		var player := Economy.player_of(state, team)
		player.funds += income
		events.append(Events.FundsChanged.new(team, income, player.funds, &"income"))
	# §6 order: income above funds the repairs below; drain precedes the
	# crash checks inside begin_turn_fuel.
	events.append_array(Supply.begin_turn_repairs(state, team))
	events.append_array(Supply.begin_turn_fuel(state, team))
	# (capture reset happens at move time in Rules.apply, not here)
	var player := Economy.player_of(state, team)
	if player != null and player.power_state != PlayerState.PowerState.NONE:
		player.power_turns_left -= 1
		if player.power_turns_left <= 0:
			player.power_state = PlayerState.PowerState.NONE
			events.append(Events.PowerExpired.new(team))
	if Weather.is_day_start(state, team):
		events.append_array(Weather.begin_day_roll(state))
	for u: UnitState in state.units_of(team):
		u.has_moved = false
		u.has_acted = false
	return events


## End-of-turn sequence: emits TurnEnded and advances current_player to
## the next living player, incrementing the day each time the rotation
## passes player index 0. Requires at least one living player.
static func end_turn(state: GameState) -> Array[GameEvent]:
	var events: Array[GameEvent] = [Events.TurnEnded.new(state.active_player().team)]
	var count: int = state.players.size()
	var next: int = state.current_player
	for _i: int in range(count):
		next = (next + 1) % count
		if next == 0:
			state.day += 1
		if state.players[next].is_alive:
			break
	state.current_player = next
	return events
