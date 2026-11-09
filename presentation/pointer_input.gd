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
## Menu rows handle their own hover and clicks (ActionMenu, BuildMenu).

## Screen pixels a press may travel before it becomes a pan.
const DRAG_THRESHOLD := 8.0
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


func _unhandled_input(event: InputEvent) -> void:
	if cursor == null or controller == null:
		return
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
	if _pressed and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		if not _panning and event.position.distance_to(_press_at) > DRAG_THRESHOLD:
			_panning = true
		if _panning:
			if camera_rig != null:
				camera_rig.pan_by(event.relative)
			get_viewport().set_input_as_handled()
			return
	if not _hover_allowed():
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
