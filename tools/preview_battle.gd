extends SceneTree
## Editor-free run of the game:
##   godot --path . -s tools/preview_battle.gd            -> the real match (Crossroads)
##   godot --path . -s tools/preview_battle.gd ++ demo    -> the code-built demo state
## Mirrors main.gd's boot, so .tres map edits show up without building
## main.tscn. The editor-authored main scene remains the shipped path
## (see presentation/main.gd).


func _initialize() -> void:
	var battle := Battle.assemble()
	root.add_child(battle)  # _ready loads the demo as the fallback
	if OS.get_cmdline_user_args().has("demo"):
		return
	var map_path := "res://data/maps/crossroads.tres"
	if ResourceLoader.exists(map_path):
		battle.load_map(load(map_path) as MapDefinition)
