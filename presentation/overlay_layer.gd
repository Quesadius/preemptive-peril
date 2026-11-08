class_name OverlayLayer
extends Node2D
## Move range (blue), attack targets (red), and the traced path arrow,
## all via _draw() (§8). Redrawn only when the controller changes
## selection state — the arrays are display state, written by
## BattleController and read by _draw().

const MOVE_COLOR := Color(0.25, 0.5, 1.0, 0.3)
const TARGET_COLOR := Color(1.0, 0.2, 0.15, 0.4)
const PATH_COLOR := Color(1.0, 0.95, 0.3, 0.9)
const DANGER_COLOR := Color(1.0, 0.32, 0.05, 0.22)

## Draws the traced path with the sheet's arrow pieces when set; a
## yellow polyline if not.
@export var art_set: ArtSet

var move_tiles: Array[Vector2i] = []
var target_tiles: Array[Vector2i] = []
var path_tiles: Array[Vector2i] = []
var danger_tiles: Array[Vector2i] = []


## Shows the blue movement range.
func show_move_range(tiles: Array[Vector2i]) -> void:
	move_tiles = tiles
	queue_redraw()


## Shows red attack-target tiles (TARGET_SELECT phase).
func show_targets(tiles: Array[Vector2i]) -> void:
	target_tiles = tiles
	queue_redraw()


## Updates the traced path arrow.
func set_path(path: Array[Vector2i]) -> void:
	path_tiles = path.duplicate()
	queue_redraw()


## The persistent full-board threat tint (the danger-map toggle).
## Unlike the transient channels, clear() leaves it alone — only the
## toggle rewrites it.
func show_danger(tiles: Array[Vector2i]) -> void:
	danger_tiles = tiles
	queue_redraw()


## Clears the transient overlays (danger persists; see show_danger).
func clear() -> void:
	move_tiles = []
	target_tiles = []
	path_tiles = []
	queue_redraw()


func _draw() -> void:
	for c: Vector2i in danger_tiles:
		draw_rect(_tile_rect(c), DANGER_COLOR)
	for c: Vector2i in move_tiles:
		draw_rect(_tile_rect(c), MOVE_COLOR)
	for c: Vector2i in target_tiles:
		draw_rect(_tile_rect(c), TARGET_COLOR)
	if path_tiles.size() >= 2 and art_set != null and art_set.sheet != null:
		for i: int in range(path_tiles.size()):
			var piece := art_set.arrow_piece(path_tiles, i)
			if piece != ArtSet.NONE:
				draw_texture_rect_region(
					art_set.sheet, _tile_rect(path_tiles[i]), art_set.region(piece)
				)
	elif path_tiles.size() >= 2:
		var points := PackedVector2Array()
		for c: Vector2i in path_tiles:
			points.append(MapRenderer.world_pos(c))
		draw_polyline(points, PATH_COLOR, 4.0)
		draw_circle(points[points.size() - 1], 6.0, PATH_COLOR)


func _tile_rect(c: Vector2i) -> Rect2:
	var size := float(MapRenderer.TILE_SIZE)
	return Rect2(Vector2(c) * size, Vector2(size, size))
