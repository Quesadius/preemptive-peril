extends Node
## Autoload: persistent player settings at user://settings.json. Other
## systems read via get_setting(); writes save immediately (the file is
## tiny). No class_name — autoloads are reached by node name.

const PATH := "user://settings.json"

const DEFAULTS: Dictionary[String, Variant] = {
	"animation_speed": 1.0,
	"skip_animations": false,
	"sfx_volume": 0.8,
	"music_volume": 0.6,
	"fog_default": false,
	"weather_default": false,
	"sound_on": true,
	"last_map": "crossroads",
	"difficulty": "normal",
	"player_funds": 0,
	"enemy_funds": 0,
}

var _values: Dictionary[String, Variant] = {}


func _ready() -> void:
	reload()


## Reads a setting (falling back to its default).
func get_setting(key: String) -> Variant:
	return _values.get(key, DEFAULTS.get(key))


## Writes and persists a setting.
func set_setting(key: String, value: Variant) -> void:
	_values[key] = value
	save_settings()


## Loads from disk, tolerating a missing or corrupt file. Only known
## keys whose value has the default's type are taken (consumers read
## them as typed values), and volumes are clamped to 0..1 — anything
## else in the file keeps its default.
func reload() -> void:
	_values = {}
	for key: String in DEFAULTS:
		_values[key] = DEFAULTS[key]
	if not FileAccess.file_exists(PATH):
		return
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		apply_loaded(parsed as Dictionary)


## Merges parsed settings over the current values, applying reload()'s
## key, type, and range rules. Split out so the rules are testable
## without touching the real settings file.
func apply_loaded(loaded: Dictionary) -> void:
	for key: Variant in loaded:
		if not key is String or not DEFAULTS.has(key):
			continue
		var value: Variant = loaded[key]
		# JSON has one number type: a whole float is how an int setting
		# comes back from disk.
		if DEFAULTS[key] is int and value is float and value == floorf(value):
			value = int(value)
		if typeof(value) != typeof(DEFAULTS[key]):
			continue
		if (key as String).ends_with("_volume"):
			value = clampf(value, 0.0, 1.0)
		_values[key] = value


## Persists to disk.
func save_settings() -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		push_warning("SettingsStore: cannot write %s" % PATH)
		return
	file.store_string(JSON.stringify(_values, "\t"))
