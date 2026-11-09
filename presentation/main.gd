class_name Main
extends Node2D
## Root script for the game's main scene. The one manual step for a
## runnable export: in the editor, create a scene containing a single
## Node2D with this script attached, save it as res://main.tscn, and set
## it as the main scene (Project Settings > Application > Run). Godot's
## runner refuses to start without a main scene, and scenes are authored
## in the editor, never by hand (CLAUDE.md).
##
## Until then, development runs use:
##   godot --path . -s tools/preview_battle.gd


func _ready() -> void:
	var touch := DisplayServer.is_touchscreen_available()
	# Browsers and touch devices size the layout to the screen (phones get
	# readable text and fill portrait or landscape); native desktop windows
	# keep the fixed 1280x720 layout from project settings.
	if OS.has_feature("web") or touch:
		ScreenFit.attach(get_window())
	var battle := Battle.assemble(Battle.default_art())
	add_child(battle)
	# Back and danger-map buttons, and finger-sized menu rows, wherever a
	# touchscreen exists (phones, tablets, touch laptops).
	battle.hud.set_touch_mode(touch)
	# The shipped boot plays the authored map when it exists; the
	# code-built demo remains the fallback.
	var map_path := "res://data/maps/crossroads.tres"
	if ResourceLoader.exists(map_path):
		battle.load_map(load(map_path) as MapDefinition)
