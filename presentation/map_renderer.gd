class_name MapRenderer
extends Node2D
## Renders MapState into TileMapLayers (§8). Pure view — reads state,
## never mutates it; the terrain grid stays authoritative in MapState.
##
## Two modes, chosen by `art_set`:
## - Placeholder (no ArtSet): flat colors built in code — terrain_layer
##   holds one 32px tile per terrain in ruleset order, property_layer a
##   translucent team tint over owned properties.
## - Art: terrain_layer holds ground (grass) and detail_layer what stands
##   on it — road shapes, trees, hills, and buildings in their owner's
##   color, which replace the tint. Sheet tiles are smaller than
##   TILE_SIZE, so both layers are scaled up to match. Terrain the set
##   doesn't map falls back to its flat color.

const TILE_SIZE := 32
const SOURCE_ID := 0  # flat-color placeholder tiles
const ART_SOURCE := 1  # the ArtSet's sheet
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
## Art mode only: roads, trees, hills, and buildings over the ground.
@export var detail_layer: TileMapLayer
@export var art_set: ArtSet


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
	if _art_ready():
		_render_art(state)
		return
	if terrain_layer.tile_set == null:
		var placeholder := TileSet.new()
		placeholder.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
		placeholder.add_source(_placeholder_source(state.ruleset, TILE_SIZE), SOURCE_ID)
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


## Road-neighbor mask for `c` (ArtSet bits). A road that would dead-end
## facing the board's edge runs off it instead; junctions and roads that
## merely run along an edge don't sprout stubs off the board.
func road_mask(state: GameState, c: Vector2i) -> int:
	var mask: int = 0
	var off_board: Array[int] = []
	for n: Vector2i in Grid.neighbors(c):
		var bit := ArtSet.dir_bit(n - c)
		if not state.map.in_bounds(n):
			off_board.append(bit)
		elif _is_road(state, n):
			mask |= bit
	for bit: int in off_board:
		if mask == ArtSet.opposite(bit):
			mask |= bit
	return mask


func _is_road(state: GameState, c: Vector2i) -> bool:
	if not state.map.in_bounds(c):
		return false
	var terrain: TerrainType = state.ruleset.terrain_types[state.map.terrain_at(c)]
	return terrain.key == art_set.road_terrain


func _art_ready() -> bool:
	return art_set != null and art_set.sheet != null and detail_layer != null


func _render_art(state: GameState) -> void:
	if terrain_layer.tile_set == null:
		var art_tiles := _build_art_tileset(state.ruleset)
		terrain_layer.tile_set = art_tiles
		detail_layer.tile_set = art_tiles
		property_layer.tile_set = art_tiles
	var s := art_set.draw_scale()
	terrain_layer.scale = Vector2(s, s)
	detail_layer.scale = Vector2(s, s)
	terrain_layer.clear()
	detail_layer.clear()
	property_layer.clear()  # buildings carry their owner's color instead
	for i: int in range(state.map.terrain.size()):
		var c := Grid.from_idx(i, state.map.width)
		var terrain_id: int = state.map.terrain[i]
		var terrain: TerrainType = state.ruleset.terrain_types[terrain_id]
		if not art_set.draws_on_ground(terrain.key):
			terrain_layer.set_cell(c, SOURCE_ID, Vector2i(terrain_id, 0))
			continue
		terrain_layer.set_cell(c, ART_SOURCE, art_set.ground_tile(c))
		var mask: int = road_mask(state, c) if terrain.key == art_set.road_terrain else 0
		var detail := art_set.detail_tile(terrain.key, state.map.property_owner[i], mask)
		if detail != ArtSet.NONE:
			detail_layer.set_cell(c, ART_SOURCE, detail)


## The art TileSet: the sheet, plus flat-color fallbacks at the sheet's
## tile size for terrain the ArtSet doesn't map.
func _build_art_tileset(ruleset: Ruleset) -> TileSet:
	var px: int = art_set.tile_px
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(px, px)
	tile_set.add_source(_placeholder_source(ruleset, px), SOURCE_ID)
	var sheet := TileSetAtlasSource.new()
	sheet.texture = art_set.sheet
	sheet.texture_region_size = Vector2i(px, px)
	@warning_ignore("integer_division")
	var cols: int = art_set.sheet.get_width() / px
	@warning_ignore("integer_division")
	var rows: int = art_set.sheet.get_height() / px
	for y: int in range(rows):
		for x: int in range(cols):
			sheet.create_tile(Vector2i(x, y))
	tile_set.add_source(sheet, ART_SOURCE)
	return tile_set


## Flat colors at `px`: one tile per terrain in ruleset order, then one
## translucent tint per team.
func _placeholder_source(ruleset: Ruleset, px: int) -> TileSetAtlasSource:
	var terrain_count: int = ruleset.terrain_types.size()
	var total: int = terrain_count + MAX_TEAMS
	var img := Image.create_empty(total * px, px, false, Image.FORMAT_RGBA8)
	for i: int in range(terrain_count):
		var key: StringName = ruleset.terrain_types[i].key
		var color: Color = TERRAIN_COLORS.get(key, Color(1.0, 0.0, 1.0))
		_paint_tile(img, i, color, px)
	for team: int in range(MAX_TEAMS):
		var tint := team_color(team)
		tint.a = 0.4
		img.fill_rect(Rect2i((terrain_count + team) * px, 0, px, px), tint)
	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(img)
	source.texture_region_size = Vector2i(px, px)
	for i: int in range(total):
		source.create_tile(Vector2i(i, 0))
	return source


func _paint_tile(img: Image, index: int, color: Color, px: int) -> void:
	var x: int = index * px
	img.fill_rect(Rect2i(x, 0, px, px), color)
	# A darker edge so the grid reads without real art.
	var edge := color.darkened(0.25)
	@warning_ignore("integer_division")
	var line: int = maxi(1, px / 16)
	img.fill_rect(Rect2i(x, px - line, px, line), edge)
	img.fill_rect(Rect2i(x + px - line, 0, line, px), edge)
