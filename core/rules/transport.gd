class_name Transport
extends RefCounted
## Load, unload, and join (§6). LAUNCH waits for silo terrain. A carrier
## holds unit ids in `cargo`; passengers keep existing in `units` with
## carrier_id set, share the carrier's coord, and leave `occupancy`.
## JOIN merges the mover into a damaged same-type ally: HP pools (capped
## at 100), the visual surplus refunds as funds (UnitJoined carries the
## refund — no separate FundsChanged), and the survivor is spent.


## null when `mover` may load into `carrier` (the known occupant of the
## move's destination).
static func validate_load(state: GameState, mover: UnitState, carrier: UnitState) -> ActionError:
	if carrier == null or carrier == mover or carrier.team != mover.team:
		return ActionError.new(ActionError.CANNOT_LOAD)
	var carrier_type: UnitType = state.ruleset.unit_types[carrier.type_id]
	if carrier.cargo.size() >= carrier_type.transport_capacity:
		return ActionError.new(ActionError.CANNOT_LOAD)
	var mover_type: UnitType = state.ruleset.unit_types[mover.type_id]
	if not _transportable(carrier_type, mover_type.movement_class):
		return ActionError.new(ActionError.CANNOT_LOAD)
	return null


## Boards the carrier. The mover's occupancy entry is already gone (the
## move step skips placement for LOAD). Precondition: validated.
static func apply_load(_state: GameState, mover: UnitState, carrier: UnitState) -> Array[GameEvent]:
	mover.carrier_id = carrier.id
	mover.coord = carrier.coord
	carrier.cargo.append(mover.id)
	return [Events.UnitLoaded.new(mover.id, carrier.id)]


## null when `carrier`, stopping on `dest`, may drop cargo_index onto
## `target`: a real passenger, an adjacent tile the passenger's class can
## enter, free as far as the carrier's team knows (its own origin tile
## counts as free — it vacates it by moving). `mask` is an optional
## Fog.mask_for() for the carrier's team.
static func validate_unload(
	state: GameState,
	carrier: UnitState,
	dest: Vector2i,
	cargo_index: int,
	target: Vector2i,
	mask: PackedByteArray = PackedByteArray()
) -> ActionError:
	if cargo_index < 0 or cargo_index >= carrier.cargo.size():
		return ActionError.new(ActionError.NO_CARGO)
	if Grid.manhattan(dest, target) != 1:
		return ActionError.new(ActionError.BAD_UNLOAD_TARGET)
	var occupant := Fog.known_occupant(state, carrier.team, target, mask)
	if occupant != null and occupant != carrier:
		return ActionError.new(ActionError.BAD_UNLOAD_TARGET)
	var passenger: UnitState = state.units[carrier.cargo[cargo_index]]
	if Movement.enter_cost(state, passenger, target) < 1:
		return ActionError.new(ActionError.BAD_UNLOAD_TARGET)
	return null


## Drops the passenger, spent for this turn. Under fog a hidden unit on
## the target tile traps the unload: nothing disembarks and the carrier
## is ambushed instead. Precondition: validated.
static func apply_unload(
	state: GameState, carrier: UnitState, cargo_index: int, target: Vector2i
) -> Array[GameEvent]:
	var blocker := state.unit_at(target)
	if blocker != null and blocker.id != carrier.id:
		return [Events.UnitAmbushed.new(carrier.id, blocker.id, target)]
	var passenger: UnitState = state.units[carrier.cargo[cargo_index]]
	carrier.cargo.remove_at(cargo_index)
	passenger.carrier_id = -1
	passenger.coord = target
	passenger.has_acted = true
	state.occupancy[target] = passenger.id
	return [Events.UnitUnloaded.new(passenger.id, carrier.id, target)]


## null when `mover` may join `target` (the known occupant of the move's
## destination): same team, same type, and the target has visible damage.
static func validate_join(_state: GameState, mover: UnitState, target: UnitState) -> ActionError:
	if target == null or target == mover or target.team != mover.team:
		return ActionError.new(ActionError.CANNOT_JOIN)
	if target.type_id != mover.type_id:
		return ActionError.new(ActionError.CANNOT_JOIN)
	if not target.cargo.is_empty() or not mover.cargo.is_empty():
		return ActionError.new(ActionError.CANNOT_JOIN)  # carriers with cargo can't merge
	if target.display_hp() >= 10:
		return ActionError.new(ActionError.JOIN_TARGET_FULL)
	return null


## Merges the mover into the target. HP, fuel, and ammo pool (capped);
## surplus displayed HP refunds cost/10 per point; the survivor is spent
## and the mover ceases to exist (no UnitDestroyed — nothing died).
## Precondition: validated.
static func apply_join(state: GameState, mover: UnitState, target: UnitState) -> Array[GameEvent]:
	var unit_type: UnitType = state.ruleset.unit_types[target.type_id]
	var surplus: int = maxi(0, mover.display_hp() + target.display_hp() - 10)
	@warning_ignore("integer_division")
	var refund: int = surplus * unit_type.cost / 10
	target.hp = mini(mover.hp + target.hp, 100)
	target.fuel = mini(mover.fuel + target.fuel, unit_type.max_fuel)
	target.ammo = mini(mover.ammo + target.ammo, unit_type.max_ammo)
	target.has_acted = true
	state.units.erase(mover.id)
	var player := Economy.player_of(state, target.team)
	if player != null and refund > 0:
		player.funds += refund
	return [Events.UnitJoined.new(target.id, mover.id, target.hp, refund)]


static func _transportable(carrier_type: UnitType, mc: MovementClass) -> bool:
	if mc == null:
		return false
	for tc: MovementClass in carrier_type.transportable_classes:
		if tc.key == mc.key:
			return true
	return false
