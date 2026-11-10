class_name MatchSetup
extends CanvasLayer
## The new-match screen: pick a map, switch fog of war, random weather
## and sound on or off, and start — or continue a saved match when one
## is offered. Built in code from stock Buttons, so arrow keys and Enter,
## the mouse, and touch all drive it through Godot's own focus handling.
## It only reports choices; main.gd owns what they do.

signal start_requested(map: MapDefinition, fog: bool, weather: bool)
signal continue_requested
signal sound_toggled(on: bool)

## Every row is a comfortable fingertip tall.
const ROW_HEIGHT := 44.0
## The column is as wide as the screen allows, within these bounds: wide
## enough for one row of maps on a desktop or a phone held sideways.
const MIN_WIDTH := 280.0
const MAX_WIDTH := 560.0
const SIDE_MARGIN := 16.0

var _maps: Array[MapDefinition] = []
var _map_group := ButtonGroup.new()
var _column: VBoxContainer
var _map_row: HFlowContainer
var _continue: Button
var _fog: Button
var _weather: Button
var _sound: Button
var _start: Button


func _init() -> void:
	layer = 20
	visible = false
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.09, 0.1, 0.14)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	# Scrolls when the column is taller than the screen (small phones).
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	backdrop.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 10)
	center.add_child(_column)
	var title := Label.new()
	title.text = "Preemptive Peril"
	title.add_theme_font_size_override("font_size", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_column.add_child(title)
	_continue = _button("")
	_continue.visible = false
	_continue.pressed.connect(func() -> void: continue_requested.emit())
	_column.add_child(_continue)
	_column.add_child(_heading("Map"))
	_map_row = HFlowContainer.new()
	_map_row.add_theme_constant_override("h_separation", 8)
	_map_row.add_theme_constant_override("v_separation", 8)
	_column.add_child(_map_row)
	_column.add_child(_heading("Options"))
	var options := HFlowContainer.new()
	options.add_theme_constant_override("h_separation", 8)
	options.add_theme_constant_override("v_separation", 8)
	_column.add_child(options)
	_fog = _toggle("Fog of war")
	_weather = _toggle("Random weather")
	_sound = _toggle("Sound")
	_sound.toggled.connect(func(on: bool) -> void: sound_toggled.emit(on))
	for toggle: Button in [_fog, _weather, _sound]:
		options.add_child(toggle)
	_start = _button("Start match")
	_start.pressed.connect(_on_start_pressed)
	_column.add_child(_start)


func _ready() -> void:
	get_viewport().size_changed.connect(_fit)
	_fit()


## Shows the screen with these maps and remembered choices. The map whose
## key is `selected_key` starts chosen (the first map if none matches).
func open(
	maps: Array[MapDefinition], selected_key: StringName, fog: bool, weather: bool, sound: bool
) -> void:
	_maps = maps.duplicate()
	for old: Node in _map_row.get_children():
		_map_row.remove_child(old)
		old.free()
	var chosen: int = 0
	for i: int in range(_maps.size()):
		if _maps[i].key == selected_key:
			chosen = i
	for i: int in range(_maps.size()):
		var def := _maps[i]
		var button := _button("%s  %d×%d" % [def.display_name, def.width, def.height])
		button.toggle_mode = true
		button.button_group = _map_group
		button.button_pressed = i == chosen
		_map_row.add_child(button)
	_set_toggle(_fog, fog)
	_set_toggle(_weather, weather)
	_set_toggle(_sound, sound)
	visible = true
	if is_inside_tree():
		_start.grab_focus.call_deferred()  # Enter starts with the remembered choices


## Hides the screen.
func close() -> void:
	visible = false


## Offers "continue" with this label; an empty label withdraws the offer.
func set_continue(label: String) -> void:
	_continue.text = label
	_continue.visible = not label.is_empty()


## The chosen map, or null when no maps were given.
func selected_map() -> MapDefinition:
	for i: int in range(_map_row.get_child_count()):
		if (_map_row.get_child(i) as Button).button_pressed:
			return _maps[i]
	return null


## The map buttons, in catalog order, for tests.
func map_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for child: Node in _map_row.get_children():
		out.append(child as Button)
	return out


## The fog, weather and sound toggles, in that order, for tests.
func option_buttons() -> Array[Button]:
	var out: Array[Button] = [_fog, _weather, _sound]
	return out


## The Start and Continue buttons, for tests.
func start_button() -> Button:
	return _start


func continue_button() -> Button:
	return _continue


## The column's current width, for tests.
func column_width() -> float:
	return _column.custom_minimum_size.x


func _on_start_pressed() -> void:
	var map := selected_map()
	if map != null:
		start_requested.emit(map, _fog.button_pressed, _weather.button_pressed)


## Sizes the column to the screen: phones in portrait get a narrow one
## whose rows wrap, wide screens one row of maps.
func _fit() -> void:
	var available := get_viewport().get_visible_rect().size.x - 2.0 * SIDE_MARGIN
	_column.custom_minimum_size.x = clampf(available, MIN_WIDTH, MAX_WIDTH)


static func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = ROW_HEIGHT
	return button


## An on/off button that says which it is ("Fog of war: Off"): a bare
## switch is easy to misread, and the words cost nothing.
static func _toggle(text: String) -> Button:
	var toggle := _button("")
	toggle.toggle_mode = true
	toggle.set_meta(&"label", text)
	toggle.toggled.connect(func(on: bool) -> void: _caption(toggle, on))
	_caption(toggle, false)
	return toggle


static func _caption(toggle: Button, on: bool) -> void:
	toggle.text = "%s: %s" % [toggle.get_meta(&"label"), "On" if on else "Off"]


## Sets a toggle without announcing it (the caption still follows).
static func _set_toggle(toggle: Button, on: bool) -> void:
	toggle.set_pressed_no_signal(on)
	_caption(toggle, on)


static func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.modulate = Color(1, 1, 1, 0.6)
	return label
