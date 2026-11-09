class_name Cursor
extends Node2D
## Grid-snapped cursor (§8). Arrow keys move it one tile at a time,
## clamped to the map; `moved` drives the info panels and path preview.
## PointerInput moves it for mouse and touch.

signal moved(coord: Vector2i)

## Draws the sheet's corner-bracket cursor when set; a white box if not.
@export var art_set: ArtSet

var coord: Vector2i = Vector2i.ZERO
## True when the last move came from the pointer (hover or tap). The
## camera doesn't chase those: hovering near the screen edge would
## otherwise scroll the map out from under the pointer.
var pointer_driven: bool = false

var _map_size: Vector2i = Vector2i.ONE


## Sets the clamp bounds and re-snaps the cursor inside them.
func set_map(width: int, height: int) -> void:
	_map_size = Vector2i(width, height)
	move_to(coord)


## True when `c` is on the map the cursor is bound to.
func contains(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < _map_size.x and c.y < _map_size.y


## Moves to `c`, clamped to the map. Emits `moved` only on a real change.
## `by_pointer` marks hover/tap moves (see pointer_driven).
func move_to(c: Vector2i, by_pointer: bool = false) -> void:
	pointer_driven = by_pointer
	var clamped := c.clamp(Vector2i.ZERO, _map_size - Vector2i.ONE)
	var changed := clamped != coord
	coord = clamped
	position = MapRenderer.world_pos(coord)
	if changed:
		moved.emit(coord)
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left", true):
		move_to(coord + Vector2i.LEFT)
	elif event.is_action_pressed("ui_right", true):
		move_to(coord + Vector2i.RIGHT)
	elif event.is_action_pressed("ui_up", true):
		move_to(coord + Vector2i.UP)
	elif event.is_action_pressed("ui_down", true):
		move_to(coord + Vector2i.DOWN)


func _draw() -> void:
	var half := MapRenderer.TILE_SIZE / 2.0
	if art_set != null and art_set.sheet != null and art_set.cursor_tile != ArtSet.NONE:
		var tile_rect := Rect2(-half, -half, half * 2.0, half * 2.0)
		draw_texture_rect_region(art_set.sheet, tile_rect, art_set.region(art_set.cursor_tile))
		return
	var box := Rect2(-half + 2, -half + 2, half * 2 - 4, half * 2 - 4)
	draw_rect(box, Color.WHITE, false, 2.0)
