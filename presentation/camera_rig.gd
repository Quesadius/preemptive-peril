class_name CameraRig
extends Node2D
## Follows the cursor with a dead zone and clamps the view to the map
## (§8). The rig must sit at the world origin; the child Camera2D's
## position is then in world pixels.
##
## Zoom: on map load the camera fits the whole board on screen (zooming
## out from `zoom_level` only as far as needed, in zoom_step snaps).
## +/- and the mouse wheel adjust it live between zoom_min and zoom_max;
## whenever the view is larger than the map, the map stays centered
## instead of pinning to a corner.
##
## Dragging with the pointer pans (pan_by); the camera then stays put
## until the cursor next moves, and never chases cursor moves the
## pointer made (Cursor.pointer_driven).

@export var camera: Camera2D
@export var cursor: Cursor
@export var dead_zone: Vector2 = Vector2(96, 64)
## Preferred magnification; map loads zoom OUT from here only if the
## board wouldn't fit.
@export var zoom_level: float = 3.0
@export var zoom_min: float = 1.0
@export var zoom_max: float = 6.0
@export var zoom_step: float = 0.5

var _map_px: Vector2 = Vector2.ZERO
## Set by a pointer pan, cleared by the cursor's next move: the camera
## stays where it was dragged instead of snapping back to the cursor.
var _follow_paused: bool = false


func _ready() -> void:
	if cursor != null:
		cursor.moved.connect(func(_c: Vector2i) -> void: _follow_paused = false)


## Registers the map's pixel extent, then fits and centers the view.
func set_map(width: int, height: int) -> void:
	if camera == null:
		push_warning("CameraRig: camera not wired")
		return
	_map_px = Vector2(width, height) * MapRenderer.TILE_SIZE
	set_zoom(minf(zoom_level, _fit_zoom()))


## Applies a zoom level, clamped to [zoom_min, zoom_max], and re-derives
## the camera limits (centering axes the map doesn't fill).
func set_zoom(level: float) -> void:
	zoom_level = clampf(level, zoom_min, zoom_max)
	if camera == null:
		return
	camera.zoom = Vector2(zoom_level, zoom_level)
	_apply_limits()


## One step closer.
func zoom_in() -> void:
	set_zoom(zoom_level + zoom_step)


## One step farther out.
func zoom_out() -> void:
	set_zoom(zoom_level - zoom_step)


## Jumps the camera to a tile (start of match, turn banner, etc.).
func center_on(coord: Vector2i) -> void:
	if camera == null:
		return
	camera.position = MapRenderer.world_pos(coord)


## Drags the view by a screen-space delta (a pointer pan), kept inside
## the map's limits. The camera stops following the cursor until the
## cursor next moves.
func pan_by(screen_delta: Vector2) -> void:
	if camera == null:
		return
	camera.position -= screen_delta / zoom_level
	_clamp_to_limits()
	_follow_paused = true


func _process(_delta: float) -> void:
	if camera == null or cursor == null:
		return
	if _follow_paused or cursor.pointer_driven:
		return
	var pos := camera.position
	var to_cursor := cursor.position - pos
	if absf(to_cursor.x) > dead_zone.x:
		pos.x += to_cursor.x - signf(to_cursor.x) * dead_zone.x
	if absf(to_cursor.y) > dead_zone.y:
		pos.y += to_cursor.y - signf(to_cursor.y) * dead_zone.y
	camera.position = pos


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed:
		match (event as InputEventKey).keycode:
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
				zoom_in()
				get_viewport().set_input_as_handled()
			KEY_MINUS, KEY_KP_SUBTRACT:
				zoom_out()
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_WHEEL_UP:
				zoom_in()
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_DOWN:
				zoom_out()
				get_viewport().set_input_as_handled()


## Camera limits per axis: the map's extent when it overflows the view,
## or the view rect centered on the map when it doesn't (Camera2D can't
## center on its own once limits are smaller than the view).
func _apply_limits() -> void:
	if _map_px == Vector2.ZERO:
		return
	var view := _base_view_size() / zoom_level
	if view.x >= _map_px.x:
		camera.limit_left = int((_map_px.x - view.x) / 2.0)
		camera.limit_right = camera.limit_left + int(view.x)
	else:
		camera.limit_left = 0
		camera.limit_right = int(_map_px.x)
	if view.y >= _map_px.y:
		camera.limit_top = int((_map_px.y - view.y) / 2.0)
		camera.limit_bottom = camera.limit_top + int(view.y)
	else:
		camera.limit_top = 0
		camera.limit_bottom = int(_map_px.y)


## Keeps the camera center where the view stays inside the limits.
func _clamp_to_limits() -> void:
	var half := _base_view_size() / zoom_level / 2.0
	var lo := Vector2(camera.limit_left, camera.limit_top) + half
	var hi := Vector2(camera.limit_right, camera.limit_bottom) - half
	camera.position = camera.position.clamp(lo, hi.max(lo))


## The largest zoom_step-snapped zoom that shows the whole map.
func _fit_zoom() -> float:
	if _map_px == Vector2.ZERO:
		return zoom_level
	var base := _base_view_size()
	var raw := minf(base.x / _map_px.x, base.y / _map_px.y)
	var snapped_fit := floorf(raw / zoom_step) * zoom_step
	return clampf(snapped_fit, zoom_min, zoom_max)


## Viewport size in screen pixels; falls back to the project's window
## settings when the rig isn't in the tree yet (pre-_ready boots).
func _base_view_size() -> Vector2:
	if is_inside_tree():
		return get_viewport().get_visible_rect().size
	return Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 1152),
		ProjectSettings.get_setting("display/window/size/viewport_height", 648)
	)
