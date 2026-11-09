class_name ScreenFit
extends RefCounted
## Sizes the game's logical canvas to the device, the way a web page
## sizes to CSS pixels: the window's size divided by the screen's scale
## factor (devicePixelRatio on the web, 2 on Retina Macs), so UI text
## stays a readable physical size on a phone. The shorter side is kept
## between MIN_SHORT and MAX_SHORT logical pixels: large windows scale the
## 720-tall layout up as before, and tiny ones never drop below 360. The
## canvas then expands to the window's own shape — portrait, landscape,
## ultrawide — instead of letterboxing a fixed 16:9.

const MIN_SHORT := 360
const MAX_SHORT := 720


## The logical canvas size for a window of `window_px` device pixels on a
## screen with scale factor `screen_scale`.
static func logical_size(window_px: Vector2i, screen_scale: float) -> Vector2i:
	if window_px.x <= 0 or window_px.y <= 0:
		return Vector2i(1280, 720)
	var css := Vector2(window_px) / maxf(screen_scale, 1.0)
	var short_side := minf(css.x, css.y)
	var target := clampf(short_side, MIN_SHORT, MAX_SHORT)
	return Vector2i((css * (target / short_side)).round())


## Applies logical_size() to `window` now and whenever it is resized.
static func attach(window: Window) -> void:
	_apply(window)
	window.size_changed.connect(_apply.bind(window))


static func _apply(window: Window) -> void:
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	var logical := logical_size(window.size, DisplayServer.screen_get_scale())
	if window.content_scale_size != logical:  # setting it re-emits size_changed
		window.content_scale_size = logical
