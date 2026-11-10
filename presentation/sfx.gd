class_name Sfx
extends RefCounted
## One-line sound effects for presentation nodes: Sfx.play(self, &"move").
## Finds the AudioDirector autoload by path (autoload names aren't
## visible to scripts parse-checked on their own) and does nothing when
## it isn't there — a node outside the tree, or a bare test scene.


## Asks the AudioDirector to play `key`.
static func play(from: Node, key: StringName) -> void:
	if from == null or not from.is_inside_tree():
		return
	var director := from.get_node_or_null("/root/AudioDirector")
	if director != null:
		director.play_sfx(key)
