class_name MapState
extends RefCounted
## Terrain and property-ownership grid.
##
## Both grids are row-major PackedInt32Arrays sized width * height —
## copy-on-write value semantics keep clone() cheap for AI search.

## Value in `property_owner` for tiles no team owns: non-property terrain,
## and capturable properties that are still neutral. Whether a neutral tile
## *can* be captured is a ruleset question (TerrainType.capturable), not
## map state.
const NO_OWNER: int = -1

var width: int
var height: int
var terrain: PackedInt32Array  # w*h, index into ruleset.terrain_types
var property_owner: PackedInt32Array  # w*h, team id or NO_OWNER
var capture_progress: Dictionary[Vector2i, int] = {}  # sparse — only in-progress tiles


## Row-major flat index of `c`. Requires in_bounds(c).
func idx(c: Vector2i) -> int:
	return c.y * width + c.x


## True if `c` is on the map.
func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height


## Terrain id at `c`. Requires in_bounds(c).
func terrain_at(c: Vector2i) -> int:
	return terrain[idx(c)]


## True if some team currently owns the property on `c`.
## Requires in_bounds(c). Neutral (uncaptured) properties report false.
func is_property(c: Vector2i) -> bool:
	return property_owner[idx(c)] != NO_OWNER


## Deep copy. Packed arrays are duplicated; the sparse capture dictionary
## is copied key by key.
func clone() -> MapState:
	var copy := MapState.new()
	copy.width = width
	copy.height = height
	copy.terrain = terrain.duplicate()
	copy.property_owner = property_owner.duplicate()
	for c: Vector2i in capture_progress:
		copy.capture_progress[c] = capture_progress[c]
	return copy
