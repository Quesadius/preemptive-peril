class_name Replay
extends RefCounted
## Deterministic reconstruction (§11): builds the initial GameState from
## a MapDefinition + player setup, and replays a SaveGame's action log
## through Rules.apply(). Because state is initial state + ordered
## actions, save, replay, and undo are the same feature.


## Builds a fresh match state. `player_setup` entries:
## {"team": int, "co": StringName (optional), "is_ai": bool (optional)}.
## Terrain, unit, and CO identity resolve by key; unknown keys, a
## malformed grid or spawn list, and an empty or duplicate-team player
## list are a loud error returning null — the state must be safe to
## index before a single rule runs on it.
static func state_from_map(
	def: MapDefinition,
	ruleset: Ruleset,
	config: GameConfig,
	rng_seed: int,
	player_setup: Array[Dictionary]
) -> GameState:
	var grid_problem := _grid_problem(def)
	if grid_problem != "":
		push_error("map %s is malformed: %s" % [def.key, grid_problem])
		return null
	var palette: PackedInt32Array = PackedInt32Array()
	palette.resize(def.terrain_palette.size())
	for i: int in range(def.terrain_palette.size()):
		var idx: int = _terrain_index(ruleset, def.terrain_palette[i])
		if idx < 0:
			push_error("map %s uses unknown terrain key %s" % [def.key, def.terrain_palette[i]])
			return null
		palette[i] = idx
	var gs := GameState.new()
	gs.ruleset = ruleset
	gs.config = config
	gs.rng = DeterministicRng.new(rng_seed)
	var map := MapState.new()
	map.width = def.width
	map.height = def.height
	var cells := PackedInt32Array()
	cells.resize(def.terrain.size())
	for i: int in range(def.terrain.size()):
		cells[i] = palette[def.terrain[i]]
	map.terrain = cells
	map.property_owner = def.property_owner.duplicate()
	gs.map = map
	if player_setup.is_empty():
		push_error("match setup has no players")
		return null
	for setup: Dictionary in player_setup:
		var team: Variant = setup.get("team")
		var is_ai: Variant = setup.get("is_ai", false)
		var co: Variant = setup.get("co", &"")
		if not (team is int and is_ai is bool and (co is StringName or co is String)):
			push_error("match setup entry %s has a field of the wrong type" % str(setup))
			return null
		if int(team) < 0 or Economy.player_of(gs, team) != null:
			push_error("match setup team %s is negative or repeated" % str(team))
			return null
		var p := PlayerState.new()
		p.team = team
		p.is_ai = is_ai
		p.funds = ruleset.starting_funds
		var co_key := StringName(co)
		if co_key != &"":
			for ci: int in range(ruleset.cos.size()):
				if ruleset.cos[ci].key == co_key:
					p.co_id = ci
			if p.co_id < 0:
				push_error("match setup uses unknown CO key %s" % co_key)
				return null
		gs.players.append(p)
	for spawn: Dictionary in def.starting_units:
		var type_key: Variant = spawn.get("type")
		var type_id: int = -1
		if type_key is StringName or type_key is String:
			type_id = _unit_type_index(ruleset, StringName(type_key))
		if type_id < 0:
			push_error("map %s spawns unknown unit key %s" % [def.key, type_key])
			return null
		var team: Variant = spawn.get("team")
		var x: Variant = spawn.get("x")
		var y: Variant = spawn.get("y")
		if not (team is int and x is int and y is int):
			push_error("map %s has a malformed spawn %s" % [def.key, str(spawn)])
			return null
		var at := Vector2i(x, y)
		if not map.in_bounds(at) or gs.occupancy.has(at):
			push_error("map %s spawns off-map or onto an occupied tile at %s" % [def.key, at])
			return null
		Ids.create_unit(gs, type_id, team, at)
	return gs


## Replays `save` against the given resources. Refuses loudly (null) on
## key mismatches, an illegal logged action, or an end state that doesn't
## match the save's digest — a save that half-loads, or loads into a
## different match than the one that was saved, is worse than one that
## refuses (§11).
static func run(save: SaveGame, ruleset: Ruleset, map_def: MapDefinition) -> GameState:
	if save == null:
		return null
	if map_def.key != save.map_key:
		push_error("save expects map %s, got %s" % [save.map_key, map_def.key])
		return null
	var config := GameConfig.new()
	config.fog_enabled = save.fog_enabled
	config.random_weather = save.weather_enabled
	var gs := state_from_map(map_def, ruleset, config, save.rng_seed, save.player_setup)
	if gs == null:
		return null
	for i: int in range(save.action_log.size()):
		var action := SaveGame.action_from_dict(save.action_log[i], ruleset)
		if action == null or Rules.validate(gs, action) != null:
			push_error("save action %d is illegal against the rebuilt state" % i)
			return null
		Rules.apply(gs, action)
	if save.digest != "" and digest(gs) != save.digest:
		push_error("save replays to a different state than it recorded")
		return null
	return gs


## A checksum of everything that makes two states the same match at the
## same moment: the clock, weather, players, properties, capture
## progress, every unit, and where the random sequence stands.
static func digest(state: GameState) -> String:
	var parts: Array[String] = [
		(
			"clock %d %d %d %d %d"
			% [
				state.day,
				state.current_player,
				state.weather,
				state.weather_days_left,
				state.next_unit_id
			]
		),
		"next roll %d" % state.rng.clone().roll_range(0, 1 << 30),
		"owners %s" % str(state.map.property_owner),
	]
	for p: PlayerState in state.players:
		parts.append(
			(
				"player %d %d %d %d %d %d %s"
				% [
					p.team,
					p.funds,
					p.co_id,
					p.power_meter,
					p.power_state,
					p.power_turns_left,
					p.is_alive
				]
			)
		)
	var capturing: Array[Vector2i] = []
	capturing.assign(state.map.capture_progress.keys())
	capturing.sort()
	for c: Vector2i in capturing:
		parts.append("capture %s %d" % [c, state.map.capture_progress[c]])
	var ids: Array[int] = []
	ids.assign(state.units.keys())
	ids.sort()
	for id: int in ids:
		var u: UnitState = state.units[id]
		parts.append(
			(
				"unit %d %s %d %s %d %d %d %s %s %d %s"
				% [
					u.id,
					state.ruleset.unit_types[u.type_id].key,
					u.team,
					u.coord,
					u.hp,
					u.fuel,
					u.ammo,
					u.has_moved,
					u.has_acted,
					u.carrier_id,
					str(u.cargo)
				]
			)
		)
	return "\n".join(parts).md5_text()


## Why the definition's grids can't be indexed safely, or "" if they can.
static func _grid_problem(def: MapDefinition) -> String:
	if def.width < 1 or def.height < 1:
		return "non-positive size %dx%d" % [def.width, def.height]
	var cells: int = def.width * def.height
	if def.terrain.size() != cells or def.property_owner.size() != cells:
		return "grids don't match the %dx%d size" % [def.width, def.height]
	for i: int in range(cells):
		if def.terrain[i] < 0 or def.terrain[i] >= def.terrain_palette.size():
			return "terrain cell %d is outside the palette" % i
	return ""


static func _terrain_index(ruleset: Ruleset, key: StringName) -> int:
	for i: int in range(ruleset.terrain_types.size()):
		if ruleset.terrain_types[i].key == key:
			return i
	return -1


static func _unit_type_index(ruleset: Ruleset, key: StringName) -> int:
	for i: int in range(ruleset.unit_types.size()):
		if ruleset.unit_types[i].key == key:
			return i
	return -1
