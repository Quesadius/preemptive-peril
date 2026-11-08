class_name MapEditor
extends Node2D
## In-game map editor (§2). The editing OPERATIONS are static and
## headless-testable; this node is the scene shell that will wire them
## to a cursor and palette UI when tools/map_editor/map_editor.tscn is
## built in the editor:
##   MapEditor (Node2D, this script)
##   ├─ MapRenderer (as in battle.tscn)
##   ├─ Cursor
##   └─ Hud-style palette (editor-only, to taste)
## Until then, edits can be scripted: build ops on a MapDefinition and
## save_definition() writes the .tres.

@export var definition: MapDefinition


## Paints `palette_index` at `coord`. No-op off-map or with a bad index.
static func paint(def: MapDefinition, coord: Vector2i, palette_index: int) -> void:
	if palette_index < 0 or palette_index >= def.terrain_palette.size():
		return
	if coord.x < 0 or coord.y < 0 or coord.x >= def.width or coord.y >= def.height:
		return
	def.terrain[coord.y * def.width + coord.x] = palette_index


## Sets the property owner at `coord` (-1 = unowned).
static func claim_tile(def: MapDefinition, coord: Vector2i, team: int) -> void:
	if coord.x < 0 or coord.y < 0 or coord.x >= def.width or coord.y >= def.height:
		return
	def.property_owner[coord.y * def.width + coord.x] = team


## Resizes, preserving overlapping content; new tiles get palette 0.
static func resize(def: MapDefinition, new_width: int, new_height: int) -> void:
	var terrain := PackedInt32Array()
	terrain.resize(new_width * new_height)
	var owners := PackedInt32Array()
	owners.resize(new_width * new_height)
	owners.fill(-1)
	for y: int in range(mini(def.height, new_height)):
		for x: int in range(mini(def.width, new_width)):
			terrain[y * new_width + x] = def.terrain[y * def.width + x]
			owners[y * new_width + x] = def.property_owner[y * def.width + x]
	def.width = new_width
	def.height = new_height
	def.terrain = terrain
	def.property_owner = owners
	for i: int in range(def.starting_units.size() - 1, -1, -1):
		var spawn: Dictionary = def.starting_units[i]
		if int(spawn["x"]) >= new_width or int(spawn["y"]) >= new_height:
			def.starting_units.remove_at(i)


## Places (or replaces) a starting unit at `coord`.
static func place_unit(
	def: MapDefinition, type_key: StringName, team: int, coord: Vector2i
) -> void:
	remove_unit(def, coord)
	def.starting_units.append({"type": type_key, "team": team, "x": coord.x, "y": coord.y})


## Removes any starting unit at `coord`.
static func remove_unit(def: MapDefinition, coord: Vector2i) -> void:
	for i: int in range(def.starting_units.size() - 1, -1, -1):
		var spawn: Dictionary = def.starting_units[i]
		if int(spawn["x"]) == coord.x and int(spawn["y"]) == coord.y:
			def.starting_units.remove_at(i)


## Writes the definition to disk (res:// in dev, user:// in exports).
static func save_definition(def: MapDefinition, path: String) -> int:
	return ResourceSaver.save(def, path)
