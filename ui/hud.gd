class_name Hud
extends CanvasLayer
## Script-built HUD (§9): status bar, terrain and unit info panels that
## follow the cursor, the damage preview, verb and build menus, and the
## turn banner. Author a real Theme as ui/theme/main_theme.tres and
## assign it to `theme_override` in the editor; until then a minimal
## dark theme is built in code.

## Touch bar buttons: Back (one step back, like Esc) and the danger map
## (like D) — the keys a touchscreen doesn't have.
signal back_pressed
signal danger_pressed

## Menu row height in touch mode: a comfortable fingertip.
const TOUCH_ROW_HEIGHT := 40.0

@export var theme_override: Theme

var status_label: Label
var terrain_panel: TerrainInfoPanel
var unit_panel: UnitInfoPanel
var damage_panel: DamagePreviewPanel
var action_menu: ActionMenu
var build_menu: BuildMenu
var banner: Label
## The end-of-match message; stays up until the next match starts.
var result_panel: PanelContainer
## Back and danger-map buttons, shown only in touch mode.
var touch_bar: VBoxContainer

var _root: Control
var _result_label: Label
var _danger_button: Button


func _init() -> void:
	layer = 10
	_root = Control.new()
	_root.name = "UIRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = theme_override if theme_override != null else _built_theme()
	add_child(_root)
	status_label = Label.new()
	status_label.position = Vector2(8, 4)
	_root.add_child(status_label)
	terrain_panel = TerrainInfoPanel.new()
	_pin(
		terrain_panel,
		Control.PRESET_BOTTOM_LEFT,
		8,
		Control.GROW_DIRECTION_END,
		Control.GROW_DIRECTION_BEGIN
	)
	_root.add_child(terrain_panel)
	unit_panel = UnitInfoPanel.new()
	_pin(
		unit_panel,
		Control.PRESET_BOTTOM_RIGHT,
		8,
		Control.GROW_DIRECTION_BEGIN,
		Control.GROW_DIRECTION_BEGIN
	)
	_root.add_child(unit_panel)
	damage_panel = DamagePreviewPanel.new()
	_pin(
		damage_panel,
		Control.PRESET_CENTER_RIGHT,
		8,
		Control.GROW_DIRECTION_BEGIN,
		Control.GROW_DIRECTION_BOTH
	)
	_root.add_child(damage_panel)
	action_menu = ActionMenu.new()
	_pin(
		action_menu,
		Control.PRESET_CENTER,
		0,
		Control.GROW_DIRECTION_BOTH,
		Control.GROW_DIRECTION_BOTH
	)
	_root.add_child(action_menu)
	build_menu = BuildMenu.new()
	_pin(
		build_menu,
		Control.PRESET_CENTER,
		0,
		Control.GROW_DIRECTION_BOTH,
		Control.GROW_DIRECTION_BOTH
	)
	_root.add_child(build_menu)
	banner = Label.new()
	banner.add_theme_font_size_override("font_size", 28)
	_pin(
		banner,
		Control.PRESET_CENTER_TOP,
		24,
		Control.GROW_DIRECTION_BOTH,
		Control.GROW_DIRECTION_END
	)
	banner.visible = false
	_root.add_child(banner)
	result_panel = PanelContainer.new()
	_result_label = Label.new()
	_result_label.add_theme_font_size_override("font_size", 32)
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_panel.add_child(_result_label)
	result_panel.visible = false
	_pin(
		result_panel,
		Control.PRESET_CENTER,
		0,
		Control.GROW_DIRECTION_BOTH,
		Control.GROW_DIRECTION_BOTH
	)
	_root.add_child(result_panel)
	touch_bar = VBoxContainer.new()
	touch_bar.add_theme_constant_override("separation", 8)
	var back := _touch_button("Back")
	back.pressed.connect(func() -> void: back_pressed.emit())
	touch_bar.add_child(back)
	_danger_button = _touch_button("Danger")
	_danger_button.toggle_mode = true
	_danger_button.pressed.connect(func() -> void: danger_pressed.emit())
	touch_bar.add_child(_danger_button)
	# Stacked under the status line, top-left: one button wide fits the
	# side margin the centered board leaves on tablets and landscape
	# phones, and portrait boards sit well below it.
	touch_bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	touch_bar.position = Vector2(8, 36)
	touch_bar.visible = false
	_root.add_child(touch_bar)
	# Read-only panels let the pointer through to the map beneath them;
	# only the menus take clicks.
	for panel: Control in [terrain_panel, unit_panel, damage_panel, result_panel]:
		_ignore_pointer(panel)


## Refreshes the status bar from the state (CO meter included).
func refresh(state: GameState) -> void:
	var player := state.active_player()
	var ai_tag := " (AI)" if player.is_ai else ""
	var co_tag := ""
	var co := Combat.co_of(state, player.team)
	if co != null:
		var burning := " *" if player.power_state != PlayerState.PowerState.NONE else ""
		co_tag = "   %s  Meter %d%s" % [co.display_name, player.power_meter, burning]
	var sky := ""
	if state.weather != GameState.Weather.CLEAR:
		sky = "   %s" % weather_name(state.weather)
	status_label.text = (
		"Day %d   Team %d%s   Funds %d%s%s"
		% [state.day, player.team, ai_tag, player.funds, co_tag, sky]
	)


## "Rain", "Snow" or "Clear" for a GameState.Weather value.
static func weather_name(weather: int) -> String:
	match weather:
		GameState.Weather.RAIN:
			return "Rain"
		GameState.Weather.SNOW:
			return "Snow"
	return "Clear"


## Points the info panels at `coord` (§9: they follow the cursor),
## showing only what `viewing_team` knows under fog: a hidden enemy
## reads as an empty tile. -1 = omniscient (fog off, tests).
func inspect(state: GameState, coord: Vector2i, viewing_team: int = -1) -> void:
	# While a new match loads, the cursor moves onto the new map before
	# the controller drops the old state; skip coords the state lacks.
	if not state.map.in_bounds(coord):
		return
	terrain_panel.show_tile(state, coord, viewing_team)
	var unit: UnitState = state.unit_at(coord)
	if viewing_team >= 0:
		unit = Fog.known_occupant(state, viewing_team, coord)
	unit_panel.show_unit(state, unit)


## Shows or hides the damage forecast.
func show_damage_preview(preview: Combat.DamagePreview) -> void:
	damage_panel.show_preview(preview)


## Reacts to played events: the turn banner.
func on_events(events: Array[GameEvent]) -> void:
	for e: GameEvent in events:
		if e is Events.TurnStarted:
			var started := e as Events.TurnStarted
			_flash_banner("Day %d — Team %d" % [started.day, started.team])
		elif e is Events.WeatherChanged:
			# Arrives after the day's TurnStarted, so the weather is what stays up.
			var turn := e as Events.WeatherChanged
			if turn.new_weather == GameState.Weather.CLEAR:
				_flash_banner("The skies clear")
			else:
				_flash_banner("%s — slower going" % weather_name(turn.new_weather))


## Touchscreen affordances on or off: the Back/Danger bar and taller,
## finger-sized menu rows.
func set_touch_mode(on: bool) -> void:
	touch_bar.visible = on
	var row_height := TOUCH_ROW_HEIGHT if on else 0.0
	action_menu.row_min_height = row_height
	build_menu.row_min_height = row_height


## Mirrors the danger map's on/off state on its button.
func set_danger_shown(on: bool) -> void:
	_danger_button.set_pressed_no_signal(on)


## Shows the end-of-match message, centered, until hide_result().
func show_result(text: String) -> void:
	_result_label.text = text
	result_panel.visible = true
	result_panel.reset_size()  # re-center on the new text's size
	result_panel.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE, 0
	)


## Clears the end-of-match message (a new match is starting).
func hide_result() -> void:
	result_panel.visible = false


## The end-of-match message, for tests.
func result_text() -> String:
	return _result_label.text


## Anchors `control` to a screen spot and sets which way it grows as its
## content fills in. Panels are pinned while still empty, and Godot's
## default growth (right and down) would push bottom- or right-anchored
## panels off screen and hang centered ones off the center point.
static func _pin(
	control: Control,
	preset: Control.LayoutPreset,
	margin: int,
	grow_h: Control.GrowDirection,
	grow_v: Control.GrowDirection
) -> void:
	control.grow_horizontal = grow_h
	control.grow_vertical = grow_v
	control.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, margin)


static func _touch_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(96, 44)
	button.add_theme_font_size_override("font_size", 18)
	# Never take keyboard focus, or Enter would press the button instead
	# of confirming on the map.
	button.focus_mode = Control.FOCUS_NONE
	return button


## Sets `control` and every Control inside it to ignore the pointer
## (containers default to catching it).
static func _ignore_pointer(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in control.get_children():
		if child is Control:
			_ignore_pointer(child as Control)


## Hides every transient element (menus, forecast).
func close_menus() -> void:
	action_menu.close()
	build_menu.close()
	damage_panel.show_preview(null)


func _flash_banner(text: String) -> void:
	banner.text = text
	banner.visible = true
	banner.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(0.9)
	tw.tween_property(banner, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func() -> void: banner.visible = false)


func _built_theme() -> Theme:
	var theme := Theme.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.88)
	style.set_content_margin_all(8.0)
	theme.set_stylebox("panel", "PanelContainer", style)
	theme.set_color("font_color", "Label", Color(0.92, 0.94, 0.97))
	return theme
