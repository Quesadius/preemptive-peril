class_name Main
extends Node2D
## Root script of the game's main scene (main.tscn: one Node2D with this
## script). Boots into the match setup screen; each match gets a freshly
## assembled Battle, freed again when the player returns to the screen —
## so nothing of a finished match can linger or take input behind it.
## The match in progress is saved after every action; while a save that
## still replays exists, the setup screen offers to continue it.

const AUTOSAVE_PATH := "user://autosave.json"
const RULESET_PATH := "res://data/rulesets/classic.tres"

var _setup: MatchSetup
var _battle: Battle
var _touch: bool = false
var _resumable: SaveGame
var _resumable_state: GameState
var _resumable_def: MapDefinition


func _ready() -> void:
	_touch = DisplayServer.is_touchscreen_available()
	if OS.has_feature("web") or _touch:
		ScreenFit.attach(get_window())
	_setup = MatchSetup.new()
	add_child(_setup)
	_setup.start_requested.connect(_start_match)
	_setup.continue_requested.connect(_continue_match)
	_setup.sound_toggled.connect(_on_sound_toggled)
	_setup.music_toggled.connect(_on_music_toggled)
	_show_setup()


## Ends any running match and shows the setup screen with the player's
## remembered choices.
func _show_setup() -> void:
	if _battle != null:
		_battle.queue_free()
		_battle = null
	var audio := get_node_or_null("/root/AudioDirector")
	if audio != null and audio.has_method("stop_music"):
		audio.stop_music()
	var settings := _settings()
	var last_map: String = settings.get_setting("last_map")
	var difficulty: String = settings.get_setting("difficulty")
	var remembered := MatchOptions.new()
	remembered.map = MapCatalog.find(StringName(last_map))
	remembered.fog = settings.get_setting("fog_default")
	remembered.weather = settings.get_setting("weather_default")
	remembered.difficulty = StringName(difficulty)
	remembered.player_funds = settings.get_setting("player_funds")
	remembered.enemy_funds = settings.get_setting("enemy_funds")
	remembered.player_co = StringName(str(settings.get_setting("player_co")))
	remembered.enemy_co = StringName(str(settings.get_setting("enemy_co")))
	remembered.hotseat = bool(settings.get_setting("hotseat"))
	var sound: bool = settings.get_setting("sound_on")
	var music: bool = settings.get_setting("music_on")
	var rs := load(RULESET_PATH) as Ruleset
	_setup.open(
		MapCatalog.all(),
		AIProfileCatalog.all(),
		rs.starting_funds_options,
		remembered,
		sound,
		rs.cos,
		MissionCatalog.missions(),
		MissionCatalog.puzzles(),
		ProgressStore.load_all(),
		music
	)
	_setup.set_continue(_find_resumable())


func _start_match(options: MatchOptions) -> void:
	var settings := _settings()
	if MapCatalog.find(options.map.key) != null:
		(
			settings
			. set_settings(
				{
					"last_map": String(options.map.key),
					"fog_default": options.fog,
					"weather_default": options.weather,
					"difficulty": String(options.difficulty),
					"player_funds": options.player_funds,
					"enemy_funds": options.enemy_funds,
					"player_co": String(options.player_co),
					"enemy_co": String(options.enemy_co),
					"hotseat": options.hotseat,
				}
			)
		)
	Sfx.play(self, &"select")
	_new_battle()
	# Only autosave maps that can be resolved back by key on reload.
	if MapCatalog.find(options.map.key) == null and MissionCatalog.find(options.map.key) == null:
		_battle.autosave_path = ""
	_battle.start_match(options)
	_enter_battle()


func _continue_match() -> void:
	if _resumable == null:
		return
	_new_battle()
	var pre_state := _resumable_state
	var pre_def := _resumable_def
	_resumable_state = null
	_resumable_def = null
	if not _battle.resume(_resumable, pre_state, pre_def):
		_show_setup()
		return
	Sfx.play(self, &"select")
	_enter_battle()


func _new_battle() -> void:
	_battle = Battle.assemble(Battle.default_art())
	_battle.hand_off_new_match = true
	_battle.autosave_path = AUTOSAVE_PATH
	_battle.new_match_requested.connect(_show_setup)


func _enter_battle() -> void:
	_setup.close()
	add_child(_battle)
	_battle.hud.set_touch_mode(_touch)


func _find_resumable() -> String:
	_resumable = null
	_resumable_state = null
	_resumable_def = null
	var save := SaveGame.read_file(AUTOSAVE_PATH)
	if save == null:
		return ""
	var def := MapCatalog.find(save.map_key)
	if def == null:
		var mission := MissionCatalog.find(save.map_key)
		if mission != null:
			def = mission.map
	var replayed: GameState = null
	if def != null:
		replayed = Replay.run(save, load(RULESET_PATH) as Ruleset, def)
	if replayed == null:
		SaveGame.delete_file(AUTOSAVE_PATH)
		return ""
	_resumable = save
	_resumable_state = replayed
	_resumable_def = def
	return "Continue: %s, day %d" % [def.display_name, replayed.day]


func _on_sound_toggled(on: bool) -> void:
	_settings().set_setting("sound_on", on)
	var audio := get_node_or_null("/root/AudioDirector")
	if audio != null and audio.has_method("refresh_music"):
		audio.refresh_music()
	Sfx.play(self, &"select")


func _on_music_toggled(on: bool) -> void:
	_settings().set_setting("music_on", on)
	var audio := get_node_or_null("/root/AudioDirector")
	if audio != null and audio.has_method("refresh_music"):
		audio.refresh_music()
	Sfx.play(self, &"select")


func _settings() -> Node:
	return get_node("/root/SettingsStore")
