class_name Main
extends Node2D
## Root script of the game's main scene (main.tscn: one Node2D with this
## script). Boots into the match setup screen; each match gets a freshly
## assembled Battle, freed again when the player returns to the screen —
## so nothing of a finished match can linger or take input behind it.
##
## For a look at a battle without the menu:
##   godot --path . -s tools/preview_battle.gd

var _setup: MatchSetup
var _battle: Battle
var _touch: bool = false


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
	var fog: bool = settings.get_setting("fog_default")
	var weather: bool = settings.get_setting("weather_default")
	var sound: bool = settings.get_setting("sound_on")
	_setup.open(MapCatalog.all(), StringName(last_map), fog, weather, sound)


func _start_match(map: MapDefinition, fog: bool, weather: bool) -> void:
	var settings := _settings()
	settings.set_setting("last_map", String(map.key))
	settings.set_setting("fog_default", fog)
	settings.set_setting("weather_default", weather)
	_setup.close()
	_battle = Battle.assemble(Battle.default_art())
	_battle.hand_off_new_match = true
	_battle.new_match_requested.connect(_show_setup)
	# Loaded before entering the tree, so the battle never builds its demo.
	_battle.load_map(map, fog, weather)
	add_child(_battle)
	# Back and danger-map buttons, and finger-sized menu rows, wherever a
	# touchscreen exists (phones, tablets, touch laptops).
	_battle.hud.set_touch_mode(_touch)


func _on_sound_toggled(on: bool) -> void:
	_settings().set_setting("sound_on", on)


## The SettingsStore autoload, reached by path: autoload names aren't
## visible to a script that is parse-checked on its own.
func _settings() -> Node:
	return get_node("/root/SettingsStore")
