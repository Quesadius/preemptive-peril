class_name MapCatalog
extends RefCounted
## The authored maps shipped under data/maps, for map pickers and for
## resolving a save's map key back to its definition.

const MAP_DIR := "res://data/maps"


## Every shipped map, ordered by display name.
static func all() -> Array[MapDefinition]:
	var maps: Array[MapDefinition] = []
	# list_directory sees through the renames an exported build applies
	# to resource files, which DirAccess does not.
	for file: String in ResourceLoader.list_directory(MAP_DIR):
		if not file.ends_with(".tres"):
			continue
		var def := load(MAP_DIR.path_join(file)) as MapDefinition
		if def != null:
			maps.append(def)
	maps.sort_custom(
		func(a: MapDefinition, b: MapDefinition) -> bool: return a.display_name < b.display_name
	)
	return maps


## The shipped map with this key, or null.
static func find(key: StringName) -> MapDefinition:
	for def: MapDefinition in all():
		if def.key == key:
			return def
	return null
