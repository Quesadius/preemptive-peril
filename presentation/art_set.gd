class_name ArtSet
extends Resource
## A sprite-sheet art pack for the battle view: which tile of `sheet`
## draws each terrain, property building (per owner), road shape, and
## unit (per team), plus the HP badges, cursor, and path arrow. Keyed by
## TerrainType / UnitType keys, so the ruleset stays free of art. Every
## presentation node treats a missing ArtSet — or a key it doesn't map —
## as "draw the flat-color placeholder", so art can arrive piecemeal.
##
## Sheet tiles are `tile_px` square with no spacing, addressed by
## (column, row). They are drawn scaled to MapRenderer.TILE_SIZE world
## pixels (16px art -> exactly 2x), so world math never changes.

## Neighbor-mask bits shared by roads and the path arrow.
const N := 1
const E := 2
const S := 4
const W := 8
const NONE := Vector2i(-1, -1)

@export var sheet: Texture2D
@export var tile_px: int = 16

## Terrain keys drawn as bare ground (the ground tile and nothing over it).
@export var ground_terrains: Array[StringName] = []
## Ground variants under every mapped tile; repeats weight the choice,
## which is a fixed hash of the coord (stable across redraws and runs).
@export var ground_tiles: Array[Vector2i] = []
## Non-property terrain drawn over the ground: key -> tile.
@export var terrain_tiles: Dictionary[StringName, Vector2i] = {}

## The road terrain key and its 16 shapes, indexed by the mask of road
## neighbors (N=1, E=2, S=4, W=8; MapRenderer.road_mask() decides when an
## off-board side counts).
@export var road_terrain: StringName = &"road"
@export var road_tiles: Array[Vector2i] = []

## Property buildings: key -> sheet column. The row is the owner's color:
## neutral_building_row when unowned, else team_building_rows[team].
@export var building_columns: Dictionary[StringName, int] = {}
@export var neutral_building_row: int = 0
@export var team_building_rows: Array[int] = []

## Units: key -> sheet column; the row is team_unit_rows[team].
@export var unit_columns: Dictionary[StringName, int] = {}
@export var team_unit_rows: Array[int] = []
## Short labels drawn on units that borrow another type's sprite.
@export var unit_tags: Dictionary[StringName, String] = {}
## Sprites face right; these teams' units are mirrored to face left.
@export var left_facing_teams: Array[int] = []

## HP badge tiles for displayed HP 0..9 (the badge sits in the tile's
## bottom-right corner, so it is drawn over the unit's whole tile).
@export var digit_tiles: Array[Vector2i] = []
@export var cursor_tile: Vector2i = NONE
## Path arrow: shaft and corner pieces keyed by connection mask (5 = N+S,
## 10 = E+W, 6 = E+S, 12 = S+W, 3 = N+E, 9 = N+W), heads indexed by the
## direction they point (N, E, S, W).
@export var arrow_bodies: Dictionary[int, Vector2i] = {}
@export var arrow_heads: Array[Vector2i] = []


## World-space scale for sheet tiles.
func draw_scale() -> float:
	return float(MapRenderer.TILE_SIZE) / tile_px


## Pixel rect of `tile` on the sheet.
func region(tile: Vector2i) -> Rect2:
	return Rect2(Vector2(tile * tile_px), Vector2(tile_px, tile_px))


## True when this set draws terrain `key` on a ground tile (bare ground,
## road, mapped terrain, or a mapped building). Anything else falls back
## to its flat placeholder color.
func draws_on_ground(key: StringName) -> bool:
	return (
		ground_terrains.has(key)
		or key == road_terrain
		or terrain_tiles.has(key)
		or building_columns.has(key)
	)


## The ground variant for `coord`.
func ground_tile(coord: Vector2i) -> Vector2i:
	if ground_tiles.is_empty():
		return NONE
	var h: int = coord.x * 374761393 + coord.y * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return ground_tiles[posmod(h, ground_tiles.size())]


## What sits on top of the ground for terrain `key`: the road shape for
## `road_mask`, the building in its owner's color, the terrain's own
## tile, or NONE for bare ground.
func detail_tile(key: StringName, owner_team: int, road_mask: int) -> Vector2i:
	if key == road_terrain and road_tiles.size() == 16:
		return road_tiles[road_mask & 15]
	if building_columns.has(key):
		var row := neutral_building_row
		if owner_team >= 0 and owner_team < team_building_rows.size():
			row = team_building_rows[owner_team]
		return Vector2i(building_columns[key], row)
	return terrain_tiles.get(key, NONE)


## The sprite tile for unit type `key` on `team`, or NONE if unmapped.
func unit_tile(key: StringName, team: int) -> Vector2i:
	if not unit_columns.has(key) or team < 0 or team >= team_unit_rows.size():
		return NONE
	return Vector2i(unit_columns[key], team_unit_rows[team])


## The badge tile for displayed HP `hp`, or NONE.
func digit_tile(hp: int) -> Vector2i:
	if hp < 0 or hp >= digit_tiles.size():
		return NONE
	return digit_tiles[hp]


## The arrow piece for `path[i]`: a straight shaft through the unit's own
## tile, shafts and corners along the way, and a head on the last tile
## pointing the way the unit travels. NONE for paths under two tiles.
func arrow_piece(path: Array[Vector2i], i: int) -> Vector2i:
	if path.size() < 2 or i < 0 or i >= path.size():
		return NONE
	if i == path.size() - 1:
		var heading := _dir_index(path[i] - path[i - 1])
		if heading < 0 or heading >= arrow_heads.size():
			return NONE
		return arrow_heads[heading]
	var out_bit := dir_bit(path[i + 1] - path[i])
	var mask := out_bit | opposite(out_bit)
	if i > 0:
		mask = out_bit | dir_bit(path[i - 1] - path[i])
	return arrow_bodies.get(mask, NONE)


## Mask bit for a unit step (N, E, S or W); 0 for anything else.
static func dir_bit(step: Vector2i) -> int:
	match step:
		Vector2i(0, -1):
			return N
		Vector2i(1, 0):
			return E
		Vector2i(0, 1):
			return S
		Vector2i(-1, 0):
			return W
	return 0


static func _dir_index(step: Vector2i) -> int:
	match dir_bit(step):
		N:
			return 0
		E:
			return 1
		S:
			return 2
		W:
			return 3
	return -1


## The bit for the opposite side (N <-> S, E <-> W); 0 for anything else.
static func opposite(bit: int) -> int:
	match bit:
		N:
			return S
		S:
			return N
		E:
			return W
		W:
			return E
	return 0
