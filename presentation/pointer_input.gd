class_name PointerInput
extends Node
## Mouse and touch for the battle view. Touch arrives as emulated mouse
## events (Godot's default), so one path serves both. Everything lands
## on the cursor, the camera, or BattleController's public confirm() and
## cancel() — the same calls the keyboard makes.
##
##   hover               cursor follows the pointer (route and forecast too)
##   click / tap         on the cursor's tile: confirm; elsewhere: aim the
##                       cursor there first (touch has no hover, so it
##                       takes two taps); outside a selected unit's range,
##                       or off the targets while aiming: back out; away
##                       from an open menu: back out of it; after the
##                       match: play again
##   right-click         cancel, one step back
##   drag (left button)  pan the camera — never also a click
##   pinch (two fingers) zoom around the fingers and pan with them; it
##                       settles on a crisp zoom step on release, and
##                       nothing it touched counts as a tap
## Touch never hovers: Godot's touch-emulated mouse motion only drags,
## so a slightly shaky first tap still just aims.
## Menu rows handle their own hover and clicks (ActionMenu, BuildMenu).

## Screen pixels a press may travel before it becomes a pan (fingers
## wobble more than mice).
const DRAG_THRESHOLD := 8.0
const TOUCH_DRAG_THRESHOLD := 16.0
const NO_HOVER_PHASES: Array[int] = [
	BattleController.State.ACTION_MENU,
	BattleController.State.BUILD_MENU,
	BattleController.State.EXECUTING,
	BattleController.State.ENEMY_TURN,
]

@export var cursor: Cursor
@export var controller: BattleController
@export var camera_rig: CameraRig

var _pressed: bool = false
var _press_at: Vector2 = Vector2.ZERO
var _panning: bool = false
## Fingers currently down, by touch index, at their latest positions.
var _touches: Dictionary[int, Vector2] = {}
## True from a second finger landing until every finger lifts.
var _pinching: bool = false
var _pinch_start_distance: float = 0.0
var _pinch_start_zoom: float = 1.0
var _pinch_mid: Vector2 = Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if cursor == null or controller == null:
		return
	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
		return
	if event is InputEventScreenDrag:
		_on_finger_drag(event as InputEventScreenDrag)
		return
	if _pinching:
		return  # the emulated mouse of a pinching finger means nothing
	if event is InputEventMouseMotion:
		_on_motion(event as InputEventMouseMotion)
	elif event is InputEventMouseButton:
		_on_button(event as InputEventMouseButton)


## The map tile under a viewport-space point.
func tile_at(screen_pos: Vector2) -> Vector2i:
	var world := cursor.get_viewport().get_canvas_transform().affine_inverse() * screen_pos
	return MapRenderer.coord_at(world)


## What a click or tap on `tile` means in the current phase.
func tap(tile: Vector2i) -> void:
	var phase := controller.phase()
	if phase == BattleController.State.EXECUTING or phase == BattleController.State.ENEMY_TURN:
		return  # the board is animating
	if phase == BattleController.State.GAME_OVER:
		controller.confirm()  # anywhere: play again
		return
	if _backs_out(phase, tile):
		controller.cancel()
		return
	if not cursor.contains(tile):
		return
	if tile != cursor.coord:
		cursor.move_to(tile, true)  # first tap aims
		return
	controller.confirm()


## Taps that mean "back out one step": away from an open menu, outside a
## selected unit's range, or off the targets while aiming.
func _backs_out(phase: BattleController.State, tile: Vector2i) -> bool:
	match phase:
		BattleController.State.ACTION_MENU, BattleController.State.BUILD_MENU:
			return true
		BattleController.State.UNIT_SELECTED, BattleController.State.CHOOSING_DESTINATION:
			return not controller.can_reach(tile)
		BattleController.State.TARGET_SELECT:
			return not controller.is_target(tile)
	return false


func _on_motion(event: InputEventMouseMotion) -> void:
	var from_touch: bool = event.device == InputEvent.DEVICE_ID_EMULATION
	if _pressed and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		var threshold := TOUCH_DRAG_THRESHOLD if from_touch else DRAG_THRESHOLD
		if not _panning and event.position.distance_to(_press_at) > threshold:
			_panning = true
		if _panning:
			if camera_rig != null:
				camera_rig.pan_by(event.relative)
			get_viewport().set_input_as_handled()
			return
	if from_touch or _pressed or not _hover_allowed():
		return
	var tile := tile_at(event.position)
	if cursor.contains(tile) and tile != cursor.coord:
		cursor.move_to(tile, true)


func _on_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				_pressed = true
				_press_at = event.position
				_panning = false
			else:
				var was_click: bool = _pressed and not _panning
				_pressed = false
				_panning = false
				if was_click:
					tap(tile_at(event.position))
		MOUSE_BUTTON_RIGHT:
			if event.pressed:
				controller.cancel()
		_:
			return  # the wheel belongs to CameraRig
	get_viewport().set_input_as_handled()


## Hovering moves the cursor only where the cursor means something:
## not behind an open menu, and not while the board is animating.
func _hover_allowed() -> bool:
	return not NO_HOVER_PHASES.has(controller.phase())


func _on_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touches[event.index] = event.position
	else:
		_touches.erase(event.index)
	if _touches.size() >= 2 and (not _pinching or _pinch_start_distance <= 0.0):
		_begin_pinch()  # a fresh pinch, or a finger back down mid-gesture
	elif _touches.size() < 2 and _pinching:
		if camera_rig != null:
			camera_rig.settle_zoom(_pinch_mid)
		_pinch_start_distance = 0.0  # stays _pinching until the last finger lifts
	if _touches.is_empty():
		_pinching = false


func _on_finger_drag(event: InputEventScreenDrag) -> void:
	if not _touches.has(event.index):
		return
	_touches[event.index] = event.position
	if not _pinching or _touches.size() < 2 or _pinch_start_distance <= 0.0:
		return
	var spread := _finger_spread()
	var mid := _finger_mid()
	if camera_rig != null:
		var level := _pinch_start_zoom * spread / _pinch_start_distance
		camera_rig.pinch(level, _pinch_mid, mid)
	_pinch_mid = mid
	get_viewport().set_input_as_handled()


func _begin_pinch() -> void:
	_pinching = true
	_pressed = false  # the first finger's press is no longer a tap or a drag
	_panning = false
	_pinch_start_distance = maxf(_finger_spread(), 1.0)
	_pinch_start_zoom = camera_rig.zoom_level if camera_rig != null else 1.0
	_pinch_mid = _finger_mid()


## Distance between the first two fingers down (lowest touch indices).
func _finger_spread() -> float:
	var pair := _first_two()
	return pair[0].distance_to(pair[1])


func _finger_mid() -> Vector2:
	var pair := _first_two()
	return (pair[0] + pair[1]) / 2.0


func _first_two() -> Array[Vector2]:
	var indices: Array[int] = []
	indices.assign(_touches.keys())
	indices.sort()
	var out: Array[Vector2] = [_touches[indices[0]], _touches[indices[1]]]
	return out
