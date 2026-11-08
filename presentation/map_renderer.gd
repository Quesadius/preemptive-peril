class_name MapRenderer
extends Node2D
## Renders MapState into two TileMapLayers (§8): base terrain and a
## property-ownership tint overlay. Pure view — reads state, never
## mutates it; the terrain grid stays authoritative in MapState.
##
## With no TileSet assigned in the editor, a flat-color placeholder set
## is built in code so the project renders before any art exists. Assign
## a real TileSet to `terrain_layer`/`property_layer` later and the
## placeholder path never runs. Atlas layout (placeholder): one 32px tile
## per terrain in ruleset order, then one translucent tile per team.

const TILE_SIZE := 32
const SOURCE_ID := 0
const MAX_TEAMS := 4

const TEAM_COLORS: Array[Color] = [
	Color(0.87, 0.3, 0.2),
	Color(0.2, 0.45, 0.85),
	Color(0.25, 0.7, 0.3),
	Color(0.85, 0.75, 0.2),
]

## Placeholder colors keyed by TerrainType.key; unknown keys get magenta.
const TERRAIN_COLORS: Dictionary[StringName, Color] = {
	&"plains": Color(0.49, 0.72, 0.38),
	&"road": Color(0.73, 0.69, 0.6),
	&"forest": Color(0.23, 0.47, 0.26),
	&"mountain": Color(0.55, 0.42, 0.3),
	&"city": Color(0.78, 0.78, 0.8),
	&"factory": Color(0.5, 0.5, 0.56),
	&"hq": Color(0.93, 0.8, 0.35),
	&"sea": Color(0.25, 0.45, 0.75),
}

@export var terrain_layer: TileMapLayer
@export var property_layer: TileMapLayer


## Center of `coord` in world pixels — the one grid-to-world mapping,
## shared by every presentation node.
static func world_pos(coord: Vector2i) -> Vector2:
	return Vector2(coord) * TILE_SIZE + Vector2(TILE_SIZE, TILE_SIZE) / 2.0


## Tile coord containing the world-space point `pos`.
static func coord_at(pos: Vector2) -> Vector2i:
	return Vector2i((pos / TILE_SIZE).floor())


## The placeholder color for `team` (wraps past MAX_TEAMS).
static func team_color(team: int) -> Color:
	return TEAM_COLORS[team % TEAM_COLORS.size()]


## Full redraw of both layers from `state`. Cheap at AW map sizes; per-
## event retinting arrives with the capture milestone.
func render(state: GameState) -> void:
	if terrain_layer == null or property_layer == null:
		push_warning("MapRenderer: tile layers not wired; nothing to render")
		return
	if terrain_layer.tile_set == null:
		var placeholder := _build_placeholder_tileset(state.ruleset)
		terrain_layer.tile_set = placeholder
		property_layer.tile_set = placeholder
	terrain_layer.clear()
	property_layer.clear()
	var terrain_count: int = state.ruleset.terrain_types.size()
	for i: int in range(state.map.terrain.size()):
		var c := Grid.from_idx(i, state.map.width)
		terrain_layer.set_cell(c, SOURCE_ID, Vector2i(state.map.terrain[i], 0))
		var owner_team: int = state.map.property_owner[i]
		if owner_team != MapState.NO_OWNER:
			property_layer.set_cell(c, SOURCE_ID, Vector2i(terrain_count + owner_team, 0))


func _build_placeholder_tileset(ruleset: Ruleset) -> TileSet:
	var terrain_count: int = ruleset.terrain_types.size()
	var total: int = terrain_count + MAX_TEAMS
	var img := Image.create_empty(total * TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	for i: int in range(terrain_count):
		var key: StringName = ruleset.terrain_types[i].key
		var color: Color = TERRAIN_COLORS.get(key, Color(1.0, 0.0, 1.0))
		_paint_tile(img, i, color)
	for team: int in range(MAX_TEAMS):
		var tint := team_color(team)
		tint.a = 0.4
		img.fill_rect(Rect2i((terrain_count + team) * TILE_SIZE, 0, TILE_SIZE, TILE_SIZE), tint)
	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(img)
	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	for i: int in range(total):
		source.create_tile(Vector2i(i, 0))
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	tile_set.add_source(source, SOURCE_ID)
	return tile_set


func _paint_tile(img: Image, index: int, color: Color) -> void:
	var x: int = index * TILE_SIZE
	img.fill_rect(Rect2i(x, 0, TILE_SIZE, TILE_SIZE), color)
	# A darker edge so the grid reads without real art.
	var edge := color.darkened(0.25)
	img.fill_rect(Rect2i(x, TILE_SIZE - 2, TILE_SIZE, 2), edge)
	img.fill_rect(Rect2i(x + TILE_SIZE - 2, 0, 2, TILE_SIZE), edge)
