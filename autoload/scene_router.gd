extends Node
## Autoload: the one place scene changes happen, so screens never hold
## paths to each other. Screens land with the menus milestone; the demo
## flow boots straight into battle.


## Changes scene by path, complaining loudly on a bad path instead of
## half-navigating.
func go_to(scene_path: String) -> void:
	if not ResourceLoader.exists(scene_path):
		push_error("SceneRouter: no scene at %s" % scene_path)
		return
	get_tree().change_scene_to_file(scene_path)
