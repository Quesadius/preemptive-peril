class_name MatchSetup
extends CanvasLayer
## The new-match screen: the game's logo, then pick a map, switch fog of
## war, random weather and sound on or off, choose the opponent's
## difficulty and each side's starting funds, and start — or continue a
## saved match when one is offered. Built in code from stock Buttons, so
## arrow keys and Enter, the mouse, and touch all drive it through
## Godot's own focus handling. It only reports choices; main.gd owns
## what they do.

signal start_requested(options: MatchOptions)
signal continue_requested
signal sound_toggled(on: bool)

## Every row is a comfortable fingertip tall.
const ROW_HEIGHT := 44.0
## The column is as wide as the screen allows, within these bounds: wide
## enough for one row of maps on a desktop or a phone held sideways.
const MIN_WIDTH := 280.0
const MAX_WIDTH := 560.0
const SIDE_MARGIN := 16.0
## The logo that heads the screen. Without it (the file missing) the
## game's name is written out instead.
const LOGO_PATH := "res://assets/logo/preemptive_peril.jpg"
const GAME_NAME := "Preemptive Peril"
## The screen's background: the colour of the logo's own margin, so the
## logo sits on the screen instead of in a box.
const BACKDROP := Color("0e151d")
## On top of the column, the logo is as wide as the column unless that
## would make it taller than this share of the screen.
const LOGO_HEIGHT_SHARE := 0.36
## A screen shorter than this has no height to spare for a logo on top
## (a phone held sideways): there it sits beside the column, taking this
## share of the width, as long as the column keeps its minimum.
const BESIDE_BELOW_HEIGHT := 520.0
const LOGO_WIDTH_SHARE := 0.4
const BESIDE_GAP := 16.0
const STACKED_GAP := 10.0

var _maps: Array[MapDefinition] = []
var _map_group := ButtonGroup.new()
## Holds the logo and the column: one above the other, or side by side.
var _layout: BoxContainer
var _logo: TextureRect
var _column: VBoxContainer
var _map_row: HFlowContainer
var _continue: Button
var _fog: Button
var _weather: Button
var _sound: Button
var _start: Button
## The difficulty levels on offer and the one chosen; pressing the
## button steps to the next.
var _levels: Array[AIProfile] = []
var _level_index: int = 0
var _difficulty: Button
## What the chosen level means, in the level's own words.
var _level_note: Label
## Starting-funds choices and each side's pick, stepped the same way.
var _funds_choices := PackedInt32Array()
var _player_funds_index: int = 0
var _enemy_funds_index: int = 0
var _player_funds: Button
var _enemy_funds: Button


func _init() -> void:
	layer = 20
	visible = false
	var backdrop := ColorRect.new()
	backdrop.color = BACKDROP
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
	_layout = BoxContainer.new()
	_layout.vertical = true
	center.add_child(_layout)
	_logo = TextureRect.new()
	if ResourceLoader.exists(LOGO_PATH):
		_logo.texture = load(LOGO_PATH) as Texture2D
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE  # _fit() sizes it
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Shown smaller than it was painted: smooth it rather than drop pixels.
	_logo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_logo.visible = _logo.texture != null
	_layout.add_child(_logo)
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 10)
	_layout.add_child(_column)
	if _logo.texture == null:
		var title := Label.new()
		title.text = GAME_NAME
		title.add_theme_font_size_override("font_size", 30)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_column.add_child(title)
	_continue = _button("")
	_continue.visible = false
	_continue.pressed.connect(func() -> void: continue_requested.emit())
	_column.add_child(_continue)
	_column.add_child(_heading("Map"))
	_map_row = _flow_row()
	_column.add_child(_heading("Options"))
	var options := _flow_row()
	_fog = _toggle("Fog of war")
	_weather = _toggle("Random weather")
	_sound = _toggle("Sound")
	_sound.toggled.connect(func(on: bool) -> void: sound_toggled.emit(on))
	for toggle: Button in [_fog, _weather, _sound]:
		options.add_child(toggle)
	# The balance of the match gets a row of its own, with the chosen
	# level's description right under it.
	_column.add_child(_heading("Balance"))
	var balance := _flow_row()
	_difficulty = _button("")
	_difficulty.pressed.connect(_step_difficulty)
	_player_funds = _button("")
	_player_funds.pressed.connect(_step_player_funds)
	_enemy_funds = _button("")
	_enemy_funds.pressed.connect(_step_enemy_funds)
	for choice: Button in [_difficulty, _player_funds, _enemy_funds]:
		balance.add_child(choice)
	_level_note = Label.new()
	_level_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_level_note.modulate = Color(1, 1, 1, 0.6)
	_column.add_child(_level_note)
	_start = _button("Start match")
	_start.pressed.connect(_on_start_pressed)
	_column.add_child(_start)


func _ready() -> void:
	get_viewport().size_changed.connect(_fit)
	_fit()


## Shows the screen with these maps, difficulty levels and funds choices,
## set to the `remembered` options (anything no longer on offer falls
## back to the first choice — Normal, for the difficulty).
func open(
	maps: Array[MapDefinition],
	levels: Array[AIProfile],
	funds_choices: PackedInt32Array,
	remembered: MatchOptions,
	sound: bool
) -> void:
	_maps = maps.duplicate()
	for old: Node in _map_row.get_children():
		_map_row.remove_child(old)
		old.free()
	var chosen: int = maxi(0, _maps.find(remembered.map))
	for i: int in range(_maps.size()):
		var def := _maps[i]
		var button := _button("%s  %d×%d" % [def.display_name, def.width, def.height])
		button.toggle_mode = true
		button.button_group = _map_group
		button.button_pressed = i == chosen
		_map_row.add_child(button)
	_set_toggle(_fog, remembered.fog)
	_set_toggle(_weather, remembered.weather)
	_set_toggle(_sound, sound)
	_levels = levels.duplicate()
	_level_index = 0
	for i: int in range(_levels.size()):
		if _levels[i].key == &"normal":
			_level_index = i
	for i: int in range(_levels.size()):
		if _levels[i].key == remembered.difficulty:
			_level_index = i
	_funds_choices = funds_choices.duplicate()
	if _funds_choices.is_empty():
		_funds_choices.append(0)
	_player_funds_index = maxi(0, _funds_choices.find(remembered.player_funds))
	_enemy_funds_index = maxi(0, _funds_choices.find(remembered.enemy_funds))
	_refresh_choices()
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


## The difficulty, your-funds and enemy-funds buttons, in that order,
## for tests.
func choice_buttons() -> Array[Button]:
	var out: Array[Button] = [_difficulty, _player_funds, _enemy_funds]
	return out


## The line describing the chosen difficulty, for tests.
func level_note() -> String:
	return _level_note.text


## The options as currently chosen.
func chosen_options() -> MatchOptions:
	var options := MatchOptions.new()
	options.map = selected_map()
	options.fog = _fog.button_pressed
	options.weather = _weather.button_pressed
	if not _levels.is_empty():
		options.difficulty = _levels[_level_index].key
	options.player_funds = _funds_choices[_player_funds_index]
	options.enemy_funds = _funds_choices[_enemy_funds_index]
	return options


## The Start and Continue buttons, for tests.
func start_button() -> Button:
	return _start


func continue_button() -> Button:
	return _continue


## The column's current width, for tests.
func column_width() -> float:
	return _column.custom_minimum_size.x


## The logo's art (null when the file is missing) and the size it is
## shown at, for tests.
func logo_texture() -> Texture2D:
	return _logo.texture


func logo_size() -> Vector2:
	return _logo.custom_minimum_size


## Whether the logo sits beside the column rather than on top of it.
func logo_is_beside() -> bool:
	return not _layout.vertical


func _on_start_pressed() -> void:
	if selected_map() != null:
		start_requested.emit(chosen_options())


func _step_difficulty() -> void:
	if not _levels.is_empty():
		_level_index = (_level_index + 1) % _levels.size()
	_refresh_choices()


func _step_player_funds() -> void:
	_player_funds_index = (_player_funds_index + 1) % _funds_choices.size()
	_refresh_choices()


func _step_enemy_funds() -> void:
	_enemy_funds_index = (_enemy_funds_index + 1) % _funds_choices.size()
	_refresh_choices()


## Rewrites the stepping buttons' captions and the difficulty note.
func _refresh_choices() -> void:
	var level_name := "Normal"
	var note := ""
	if not _levels.is_empty():
		level_name = _levels[_level_index].display_name
		note = _levels[_level_index].description
	_difficulty.text = "Difficulty: %s" % level_name
	_level_note.text = note
	_player_funds.text = "Your funds: %s" % _thousands(_funds_choices[_player_funds_index])
	_enemy_funds.text = "Enemy funds: %s" % _thousands(_funds_choices[_enemy_funds_index])


## 5000 -> "5,000".
static func _thousands(amount: int) -> String:
	var digits := str(amount)
	var out := ""
	for i: int in range(digits.length()):
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return out


## Sizes the column and the logo to the screen: phones in portrait get a
## narrow column whose rows wrap, wide screens one row of maps. The logo
## goes on top, or beside the column when the screen is too short.
func _fit() -> void:
	var screen := get_viewport().get_visible_rect().size
	var available := screen.x - 2.0 * SIDE_MARGIN
	var column_width := clampf(available, MIN_WIDTH, MAX_WIDTH)
	if _logo.texture != null:
		var art := _logo.texture.get_size()
		var shared := available - BESIDE_GAP
		var beside := (
			screen.y < BESIDE_BELOW_HEIGHT and shared * (1.0 - LOGO_WIDTH_SHARE) >= MIN_WIDTH
		)
		# The most room the logo may take here; it keeps its shape inside it.
		var room := Vector2(column_width, screen.y * LOGO_HEIGHT_SHARE)
		if beside:
			room = Vector2(shared * LOGO_WIDTH_SHARE, screen.y - 2.0 * SIDE_MARGIN)
		var logo_size := (art * minf(room.x / art.x, room.y / art.y)).round()
		if beside:
			column_width = clampf(shared - logo_size.x, MIN_WIDTH, MAX_WIDTH)
		_layout.vertical = not beside
		_layout.add_theme_constant_override("separation", BESIDE_GAP if beside else STACKED_GAP)
		_logo.custom_minimum_size = logo_size
	_column.custom_minimum_size.x = column_width
	_level_note.custom_minimum_size.x = column_width  # wraps to the column


## Adds a row to the column whose buttons wrap when they run out of width.
func _flow_row() -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	_column.add_child(row)
	return row


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
