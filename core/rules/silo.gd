class_name Silo
extends RefCounted
## Missile silo launch rules: an infantry or mech standing on an unspent
## silo may fire a one-time tactical warhead at any tile on the board,
## dealing non-lethal splash damage in a Manhattan-2 diamond (30 HP,
## leaving targets at >= 1 HP) and permanently marking the silo spent.

const SILO_DAMAGE := 30
const SILO_RADIUS := 2


## True when `unit` standing on `dest` is allowed to launch a missile silo
## (regardless of where it aims).
static func can_launch_at(state: GameState, unit: UnitState, dest: Vector2i) -> bool:
	if not state.map.in_bounds(dest):
		return false
	var unit_type: UnitType = state.ruleset.unit_types[unit.type_id]
	if not unit_type.capture_capable:
		return false
	var terrain: TerrainType = state.ruleset.terrain_types[state.map.terrain_at(dest)]
	return terrain.is_silo


## null when `unit` at `dest` may launch the silo at `target_coord`.
static func validate(
	state: GameState, unit: UnitState, dest: Vector2i, target_coord: Vector2i
) -> ActionError:
	var unit_type: UnitType = state.ruleset.unit_types[unit.type_id]
	if not unit_type.capture_capable:
		return ActionError.new(ActionError.CANNOT_LAUNCH)
	if not state.map.in_bounds(dest):
		return ActionError.new(ActionError.NOT_A_SILO)
	var terrain: TerrainType = state.ruleset.terrain_types[state.map.terrain_at(dest)]
	if not terrain.is_silo:
		return ActionError.new(ActionError.NOT_A_SILO)
	if not state.map.in_bounds(target_coord):
		return ActionError.new(ActionError.TARGET_OUT_OF_RANGE)
	return null


## Fires the silo: converts the silo tile to `silo_spent`, deals non-lethal
## splash damage across the blast diamond, and returns the SiloLaunched event.
static func apply(state: GameState, unit: UnitState, target_coord: Vector2i) -> Array[GameEvent]:
	var spent_id: int = _spent_terrain_id(state.ruleset)
	if spent_id >= 0:
		state.map.terrain[state.map.idx(unit.coord)] = spent_id
	var blast := blast_tiles(state, target_coord)
	var hit_ids: Array[int] = []
	for c: Vector2i in blast:
		var victim: UnitState = state.unit_at(c)
		if victim != null:
			hit_ids.append(victim.id)
	hit_ids.sort()
	var damages: Array[int] = []
	for uid: int in hit_ids:
		var victim: UnitState = state.units[uid]
		var next_hp: int = maxi(victim.hp - SILO_DAMAGE, 1)
		var dealt: int = victim.hp - next_hp
		victim.hp = next_hp
		damages.append(dealt)
	return [Events.SiloLaunched.new(unit.id, unit.coord, target_coord, hit_ids, damages)]


## Every in-bounds tile inside the silo's splash diamond centered on `center`.
static func blast_tiles(state: GameState, center: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c: Vector2i in Grid.coords_in_range(center, 0, SILO_RADIUS):
		if state.map.in_bounds(c):
			out.append(c)
	return out


static func _spent_terrain_id(ruleset: Ruleset) -> int:
	for i: int in range(ruleset.terrain_types.size()):
		if ruleset.terrain_types[i].key == &"silo_spent":
			return i
	return -1
