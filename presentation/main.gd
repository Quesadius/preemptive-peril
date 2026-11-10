class_name Main
extends Node2D
## Root script of the game's main scene (main.tscn: one Node2D with this
## script). Boots into the match setup screen; each match gets a freshly
## assembled Battle, freed again when the player returns to the screen —
## so nothing of a finished match can linger or take input behind it.
## The match in progress is saved after every action; while a save that
## still replays exists, the setup screen offers to continue it.
##
## For a look at a battle without the menu:
##   godot --path . -s tools/preview_battle.gd

const AUTOSAVE_PATH := "user://autosave.json"
const RULESET_PATH := "res://data/rulesets/classic.tres"

var _setup: MatchSetup
var _battle: Battle
var _touch: bool = false
## The saved match the setup screen is offering, if any.
var _resumable: SaveGame


func _ready() -> void:
	_touch = DisplayServer.is_touchscreen_available()
	# Browsers and touch devices size the layout to the screen (phones get
	# readable text and fill portrait or landscape); native desktop windows
	# keep the fixed 1280x720 layout from project settings.
	if OS.has_feature("web") or _touch:
		ScreenFit.attach(get_window())
	_setup = MatchSetup.new()
	add_child(_setup)
	_setup.start_requested.connect(_start_match)
	_setup.continue_requested.connect(_continue_match)
	_setup.sound_toggled.connect(_on_sound_toggled)
	_show_setup()


## Ends any running match and shows the setup screen with the player's
## remembered choices.
func _show_setup() -> void:
	if _battle != null:
		_battle.queue_free()
		_battle = null
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
	var sound: bool = settings.get_setting("sound_on")
	var funds_choices := (load(RULESET_PATH) as Ruleset).starting_funds_options
	_setup.open(MapCatalog.all(), AIProfileCatalog.all(), funds_choices, remembered, sound)
	_setup.set_continue(_find_resumable())


func _start_match(options: MatchOptions) -> void:
	var settings := _settings()
	settings.set_setting("last_map", String(options.map.key))
	settings.set_setting("fog_default", options.fog)
	settings.set_setting("weather_default", options.weather)
	settings.set_setting("difficulty", String(options.difficulty))
	settings.set_setting("player_funds", options.player_funds)
	settings.set_setting("enemy_funds", options.enemy_funds)
	Sfx.play(self, &"select")
	_new_battle()
	_battle.start_match(options)
	_enter_battle()


func _continue_match() -> void:
	if _resumable == null:
		return
	_new_battle()
	if not _battle.resume(_resumable):
		_show_setup()  # no longer replayable: back to the menu, offer withdrawn
		return
	Sfx.play(self, &"select")
	_enter_battle()


## A fresh battle, not yet in the tree: its match is loaded first, so it
## never builds its fallback demo.
func _new_battle() -> void:
	_battle = Battle.assemble(Battle.default_art())
	_battle.hand_off_new_match = true
	_battle.autosave_path = AUTOSAVE_PATH
	_battle.new_match_requested.connect(_show_setup)


func _enter_battle() -> void:
	_setup.close()
	add_child(_battle)
	# Back and danger-map buttons, and finger-sized menu rows, wherever a
	# touchscreen exists (phones, tablets, touch laptops).
	_battle.hud.set_touch_mode(_touch)


## Looks for a saved match that still replays under today's rules and
## maps; returns the label to offer it with, or "" (deleting a save that
## can't be continued, so it isn't tried again).
func _find_resumable() -> String:
	_resumable = null
	var save := SaveGame.read_file(AUTOSAVE_PATH)
	if save == null:
		return ""
	var def := MapCatalog.find(save.map_key)
	var replayed: GameState = null
	if def != null:
		replayed = Replay.run(save, load(RULESET_PATH) as Ruleset, def)
	if replayed == null:
		SaveGame.delete_file(AUTOSAVE_PATH)
		return ""
	_resumable = save
	return "Continue: %s, day %d" % [def.display_name, replayed.day]


func _on_sound_toggled(on: bool) -> void:
	_settings().set_setting("sound_on", on)
	Sfx.play(self, &"select")  # heard only when it was just switched on


## The SettingsStore autoload, reached by path: autoload names aren't
## visible to a script that is parse-checked on its own.
func _settings() -> Node:
	return get_node("/root/SettingsStore")
