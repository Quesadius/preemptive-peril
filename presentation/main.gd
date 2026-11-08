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
	var battle := Battle.assemble(Battle.default_art())
	add_child(battle)
	# The shipped boot plays the authored map when it exists; the
	# code-built demo remains the fallback.
	var map_path := "res://data/maps/crossroads.tres"
	if ResourceLoader.exists(map_path):
		battle.load_map(load(map_path) as MapDefinition)
