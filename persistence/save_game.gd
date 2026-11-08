class_name SaveGame
extends RefCounted
## Save format (§11): initial-state recipe + ordered action log, tiny
## and human-readable. Unit types serialize by key, never index. The
## version field is guarded loudly on load.

const SAVE_VERSION := 1
## Integer-valued fields an action entry may carry.
const INT_FIELDS: Array[String] = ["level", "x", "y", "unit", "verb", "tx", "ty", "cargo"]
## Largest integer a JSON number (an IEEE double) holds exactly: 2^53.
const MAX_EXACT_JSON_INT := 9007199254740992.0

var version: int = SAVE_VERSION
var ruleset_key: StringName = &"classic"
var map_key: StringName = &""
var rng_seed: int = 0
var fog_enabled: bool = false
## {"team": int, "co": StringName, "is_ai": bool} per player.
var player_setup: Array[Dictionary] = []
var action_log: Array[Dictionary] = []


## Appends one action to the log.
func record(action: Action, ruleset: Ruleset) -> void:
	action_log.append(SaveGame.action_to_dict(action, ruleset))


## Serializes to pretty JSON.
func to_json() -> String:
	var setup_plain: Array = []
	for s: Dictionary in player_setup:
		setup_plain.append(
			{"team": s["team"], "co": String(s.get("co", &"")), "is_ai": s.get("is_ai", false)}
		)
	return (
		JSON
		. stringify(
			{
				"version": version,
				"ruleset": String(ruleset_key),
				"map": String(map_key),
				"seed": rng_seed,
				"fog": fog_enabled,
				"players": setup_plain,
				"actions": action_log,
			},
			"\t"
		)
	)


## Parses a save, rejecting loudly with null: version mismatches, and
## any field whose JSON type is wrong. Save files are outside input, so
## nothing is coerced on trust — a value of the wrong type would
## otherwise crash a typed assignment or slip in as garbage.
static func from_json(text: String) -> SaveGame:
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("save file is not a JSON object")
		return null
	var data: Dictionary = parsed
	var version: Variant = data.get("version")
	if not _is_int32(version) or int(version) != SAVE_VERSION:
		push_error("save version %s unsupported (want %d)" % [version, SAVE_VERSION])
		return null
	var ruleset: Variant = data.get("ruleset", "classic")
	var map: Variant = data.get("map", "")
	var seed_value: Variant = data.get("seed", 0)
	var fog: Variant = data.get("fog", false)
	var players: Variant = data.get("players", [])
	var actions: Variant = data.get("actions", [])
	if not (ruleset is String and map is String and fog is bool):
		push_error("save header has a field of the wrong type")
		return null
	if not (_is_whole(seed_value, MAX_EXACT_JSON_INT) and players is Array and actions is Array):
		push_error("save header has a field of the wrong type")
		return null
	var save := SaveGame.new()
	save.ruleset_key = StringName(ruleset)
	save.map_key = StringName(map)
	save.rng_seed = int(seed_value)
	save.fog_enabled = fog
	for s: Variant in players:
		if not s is Dictionary:
			push_error("save player entry is not an object")
			return null
		var row: Dictionary = s
		var team: Variant = row.get("team", 0)
		var co: Variant = row.get("co", "")
		var is_ai: Variant = row.get("is_ai", false)
		if not (_is_int32(team) and co is String and is_ai is bool):
			push_error("save player entry has a field of the wrong type")
			return null
		save.player_setup.append({"team": int(team), "co": StringName(co), "is_ai": is_ai})
	for a: Variant in actions:
		if not a is Dictionary:
			push_error("save action entry is not an object")
			return null
		save.action_log.append(a)
	return save


## Action -> plain dictionary. Unit TYPES go by key; unit ids are stable
## across replays because id allocation is deterministic.
static func action_to_dict(action: Action, ruleset: Ruleset) -> Dictionary:
	if action is EndTurnAction:
		return {"kind": "end"}
	if action is PowerAction:
		return {"kind": "power", "level": (action as PowerAction).power_level}
	if action is BuildAction:
		var b := action as BuildAction
		return {
			"kind": "build",
			"type": String(ruleset.unit_types[b.unit_type_id].key),
			"x": b.coord.x,
			"y": b.coord.y,
		}
	var ua := action as UnitAction
	var path_plain: Array = []
	for c: Vector2i in ua.path:
		path_plain.append([c.x, c.y])
	return {
		"kind": "unit",
		"unit": ua.unit_id,
		"verb": ua.verb,
		"path": path_plain,
		"tx": ua.target_coord.x,
		"ty": ua.target_coord.y,
		"cargo": ua.cargo_index,
	}


## Dictionary -> Action, or null on garbage: an unknown kind, a numeric
## field that isn't an exact integer, or a malformed path. Legality is
## still Rules.validate()'s job; this only guarantees a well-typed
## Action reaches it.
static func action_from_dict(data: Dictionary, ruleset: Ruleset) -> Action:
	for field: String in INT_FIELDS:
		if data.has(field) and not _is_int32(data[field]):
			push_error("save action field %s is not an integer: %s" % [field, data[field]])
			return null
	var kind: Variant = data.get("kind", "")
	var kind_name: String = kind if kind is String else ""
	match kind_name:
		"end":
			return EndTurnAction.new()
		"power":
			var pa := PowerAction.new()
			pa.power_level = int(data.get("level", PlayerState.PowerState.CO_POWER))
			return pa
		"build":
			var type_key: Variant = data.get("type", "")
			if not type_key is String:
				push_error("save build action has a non-string type")
				return null
			var b := BuildAction.new()
			b.unit_type_id = _type_index(ruleset, StringName(type_key))
			if b.unit_type_id < 0:
				return null
			b.coord = Vector2i(int(data.get("x", 0)), int(data.get("y", 0)))
			return b
		"unit":
			var ua := UnitAction.new()
			ua.unit_id = int(data.get("unit", -1))
			ua.verb = int(data.get("verb", UnitAction.Verb.WAIT))
			var steps: Variant = data.get("path", [])
			if not steps is Array:
				push_error("save unit action path is not an array")
				return null
			for step: Variant in steps:
				if not (step is Array and (step as Array).size() == 2):
					push_error("save unit action path step is not an [x, y] pair")
					return null
				var pair: Array = step
				if not (_is_int32(pair[0]) and _is_int32(pair[1])):
					push_error("save unit action path step is not an [x, y] pair")
					return null
				ua.path.append(Vector2i(int(pair[0]), int(pair[1])))
			ua.target_coord = Vector2i(int(data.get("tx", 0)), int(data.get("ty", 0)))
			ua.cargo_index = int(data.get("cargo", -1))
			return ua
	push_error("unknown action kind in save: %s" % kind)
	return null


static func _type_index(ruleset: Ruleset, key: StringName) -> int:
	for i: int in range(ruleset.unit_types.size()):
		if ruleset.unit_types[i].key == key:
			return i
	return -1


## True for a JSON number holding an exact 32-bit integer (JSON numbers
## parse as floats; Vector2i and enum fields are 32-bit).
static func _is_int32(v: Variant) -> bool:
	return _is_whole(v, 2147483647.0)


## True for a finite whole number no larger than `limit` in magnitude.
static func _is_whole(v: Variant, limit: float) -> bool:
	if not (v is int or v is float):
		return false
	var f: float = float(v)
	return is_finite(f) and f == floorf(f) and absf(f) <= limit
