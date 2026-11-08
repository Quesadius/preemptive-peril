class_name Cursor
extends Node2D
## Grid-snapped cursor (§8). Arrow keys move it one tile at a time,
## clamped to the map; `moved` drives the info panels once those exist.
## Mouse/touch input and controller integration arrive with the
## playable-loop milestone.

signal moved(coord: Vector2i)

var coord: Vector2i = Vector2i.ZERO

var _map_size: Vector2i = Vector2i.ONE


## Sets the clamp bounds and re-snaps the cursor inside them.
func set_map(width: int, height: int) -> void:
	_map_size = Vector2i(width, height)
	move_to(coord)


## Moves to `c`, clamped to the map. Emits `moved` only on a real change.
func move_to(c: Vector2i) -> void:
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
	var box := Rect2(-half + 2, -half + 2, half * 2 - 4, half * 2 - 4)
	draw_rect(box, Color.WHITE, false, 2.0)
