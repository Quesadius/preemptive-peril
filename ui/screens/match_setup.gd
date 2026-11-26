class_name MatchSetup
extends CanvasLayer
## The new-match screen: logo, mode tabs (Skirmish / Missions / Puzzles /
## Random), map or mission picker with saved S/A/B/C rank badges, CO
## selection (Your CO / Opponent CO), options (Fog, Weather, Sound, Music,
## 2P Hotseat), balance controls, and Start / Continue.

signal start_requested(options: MatchOptions)
signal continue_requested
signal sound_toggled(on: bool)
signal music_toggled(on: bool)

enum Mode { SKIRMISH, MISSIONS, PUZZLES, RANDOM }

## Every row is a comfortable fingertip tall.
const ROW_HEIGHT := 40.0
const MIN_WIDTH := 280.0
const MAX_WIDTH := 560.0
const SIDE_MARGIN := 16.0
const LOGO_PATH := "res://assets/logo/preemptive_peril.jpg"
const GAME_NAME := "Preemptive Peril"
const BACKDROP := Color("0e151d")
const LOGO_HEIGHT_SHARE := 0.36
const BESIDE_BELOW_HEIGHT := 520.0
const LOGO_WIDTH_SHARE := 0.4
const BESIDE_GAP := 16.0
const STACKED_GAP := 10.0

var _mode: Mode = Mode.SKIRMISH
var _mode_group := ButtonGroup.new()
var _mode_buttons: Array[Button] = []

var _maps: Array[MapDefinition] = []
var _missions: Array[MissionCatalog.MissionDef] = []
var _puzzles: Array[MissionCatalog.MissionDef] = []
var _cos: Array[COProfile] = []
var _progress: Dictionary = {}

var _map_group := ButtonGroup.new()
var _mission_group := ButtonGroup.new()
var _puzzle_group := ButtonGroup.new()

var _layout: BoxContainer
var _logo: TextureRect
var _column: VBoxContainer
var _map_heading: Label
var _map_row: HFlowContainer
var _mission_row: HFlowContainer
var _puzzle_row: HFlowContainer
var _random_row: HFlowContainer
var _mission_note: Label

var _co_heading: Label
var _co_row: HFlowContainer
var _player_co_btn: Button
var _enemy_co_btn: Button
var _co_note: Label
var _player_co_index: int = 0
var _enemy_co_index: int = 1

var _random_preset_btn: Button
var _random_seed_btn: Button
var _random_preset_index: int = 0
var _random_seed: int = 101

var _continue: Button
var _fog: Button
var _weather: Button
var _sound: Button
var _music: Button
var _hotseat: Button
var _start: Button

var _levels: Array[AIProfile] = []
var _level_index: int = 0
var _difficulty: Button
var _level_note: Label
var _funds_choices := PackedInt32Array()
var _player_funds_index: int = 0
var _enemy_funds_index: int = 0
var _player_funds: Button
var _enemy_funds: Button
var _balance_heading: Label
var _balance_row: HFlowContainer
var _options_heading: Label
var _options_row: HFlowContainer


func _init() -> void:
	layer = 20
	visible = false
	var backdrop := ColorRect.new()
	backdrop.color = BACKDROP
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
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
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_logo.visible = _logo.texture != null
	_layout.add_child(_logo)
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 8)
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

	# Mode switcher row: Skirmish / Missions / Puzzles / Random
	var mode_row := _flow_row()
	var mode_specs: Array[Array] = [
		[Mode.SKIRMISH, "Skirmish"],
		[Mode.MISSIONS, "Missions"],
		[Mode.PUZZLES, "Puzzles"],
		[Mode.RANDOM, "Random Map"],
	]
	for spec: Array in mode_specs:
		var m_val: Mode = spec[0]
		var btn := _button(spec[1])
		btn.toggle_mode = true
		btn.button_group = _mode_group
		btn.button_pressed = m_val == Mode.SKIRMISH
		btn.pressed.connect(_set_mode.bind(m_val))
		mode_row.add_child(btn)
		_mode_buttons.append(btn)

	_map_heading = _heading("Map")
	_column.add_child(_map_heading)
	_map_row = _flow_row()
	_mission_row = _flow_row()
	_mission_row.visible = false
	_puzzle_row = _flow_row()
	_puzzle_row.visible = false
	_random_row = _flow_row()
	_random_row.visible = false
	_random_preset_btn = _button("")
	_random_preset_btn.pressed.connect(_step_random_preset)
	_random_seed_btn = _button("")
	_random_seed_btn.pressed.connect(_step_random_seed)
	_random_row.add_child(_random_preset_btn)
	_random_row.add_child(_random_seed_btn)

	_mission_note = Label.new()
	_mission_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mission_note.modulate = Color(0.85, 0.92, 1.0, 0.85)
	_mission_note.visible = false
	_column.add_child(_mission_note)

	_co_heading = _heading("Commanders")
	_column.add_child(_co_heading)
	_co_row = _flow_row()
	_player_co_btn = _button("")
	_player_co_btn.pressed.connect(_step_player_co)
	_enemy_co_btn = _button("")
	_enemy_co_btn.pressed.connect(_step_enemy_co)
	_co_row.add_child(_player_co_btn)
	_co_row.add_child(_enemy_co_btn)
	_co_note = Label.new()
	_co_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_co_note.modulate = Color(1, 1, 1, 0.65)
	_column.add_child(_co_note)
	_co_heading.visible = false
	_co_row.visible = false
	_co_note.visible = false

	_options_heading = _heading("Options")
	_column.add_child(_options_heading)
	_options_row = _flow_row()
	_fog = _toggle("Fog of war")
	_weather = _toggle("Random weather")
	_sound = _toggle("Sound")
	_sound.toggled.connect(func(on: bool) -> void: sound_toggled.emit(on))
	_music = _toggle("Music")
	_music.toggled.connect(func(on: bool) -> void: music_toggled.emit(on))
	_hotseat = _toggle("2P Hotseat")
	_hotseat.toggled.connect(func(_on: bool) -> void: _refresh_choices())
	for toggle: Button in [_fog, _weather, _sound, _music, _hotseat]:
		_options_row.add_child(toggle)

	_balance_heading = _heading("Balance")
	_column.add_child(_balance_heading)
	_balance_row = _flow_row()
	_difficulty = _button("")
	_difficulty.pressed.connect(_step_difficulty)
	_player_funds = _button("")
	_player_funds.pressed.connect(_step_player_funds)
	_enemy_funds = _button("")
	_enemy_funds.pressed.connect(_step_enemy_funds)
	for choice: Button in [_difficulty, _player_funds, _enemy_funds]:
		_balance_row.add_child(choice)
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


## Shows the setup screen with maps, difficulty levels, funds choices,
## optional commanders, campaign missions, tactical puzzles, and progress.
func open(
	maps: Array[MapDefinition],
	levels: Array[AIProfile],
	funds_choices: PackedInt32Array,
	remembered: MatchOptions,
	sound: bool,
	cos: Array[COProfile] = [],
	missions: Array[MissionCatalog.MissionDef] = [],
	puzzles: Array[MissionCatalog.MissionDef] = [],
	progress: Dictionary = {},
	music: bool = true
) -> void:
	_maps = maps.duplicate()
	_cos = cos.duplicate()
	_missions = missions.duplicate()
	_puzzles = puzzles.duplicate()
	_progress = progress.duplicate()

	_rebuild_flow(_map_row)
	var chosen: int = maxi(0, _maps.find(remembered.map))
	for i: int in range(_maps.size()):
		var def := _maps[i]
		var badge := ProgressStore.badge_for(def.key, _progress)
		var button := _button("%s  %d×%d%s" % [def.display_name, def.width, def.height, badge])
		button.toggle_mode = true
		button.button_group = _map_group
		button.button_pressed = i == chosen
		_map_row.add_child(button)

	_rebuild_flow(_mission_row)
	for i: int in range(_missions.size()):
		var m := _missions[i]
		var badge := ProgressStore.badge_for(m.key, _progress)
		var button := _button("%s%s" % [m.display_name, badge])
		button.toggle_mode = true
		button.button_group = _mission_group
		button.button_pressed = i == 0
		button.pressed.connect(_refresh_mission_note)
		_mission_row.add_child(button)

	_rebuild_flow(_puzzle_row)
	for i: int in range(_puzzles.size()):
		var p := _puzzles[i]
		var badge := ProgressStore.badge_for(p.key, _progress)
		var button := _button("%s%s" % [p.display_name, badge])
		button.toggle_mode = true
		button.button_group = _puzzle_group
		button.button_pressed = i == 0
		button.pressed.connect(_refresh_mission_note)
		_puzzle_row.add_child(button)

	# Hide Missions/Puzzles tabs if none were passed (keeps minimal test setups clean).
	_mode_buttons[1].visible = not _missions.is_empty()
	_mode_buttons[2].visible = not _puzzles.is_empty()

	_player_co_index = 0
	_enemy_co_index = mini(1, maxi(0, _cos.size() - 1))
	for i: int in range(_cos.size()):
		if _cos[i].key == remembered.player_co:
			_player_co_index = i
		if _cos[i].key == remembered.enemy_co:
			_enemy_co_index = i

	_set_toggle(_fog, remembered.fog)
	_set_toggle(_weather, remembered.weather)
	_set_toggle(_sound, sound)
	_set_toggle(_music, music)
	_set_toggle(_hotseat, remembered.hotseat)

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
	_set_mode(Mode.SKIRMISH)
	visible = true
	if is_inside_tree():
		_start.grab_focus.call_deferred()


func close() -> void:
	visible = false


func set_continue(label: String) -> void:
	_continue.text = label
	_continue.visible = not label.is_empty()


func selected_map() -> MapDefinition:
	if _mode == Mode.MISSIONS:
		var m := _selected_mission()
		return m.map if m != null else null
	if _mode == Mode.PUZZLES:
		var p := _selected_puzzle()
		return p.map if p != null else null
	if _mode == Mode.RANDOM:
		var preset: StringName = MapGenerator.PRESETS[_random_preset_index]
		return MapGenerator.generate(preset, _random_seed)
	for i: int in range(_map_row.get_child_count()):
		if (_map_row.get_child(i) as Button).button_pressed:
			return _maps[i]
	return null


func map_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for child: Node in _map_row.get_children():
		out.append(child as Button)
	return out


func mode_buttons() -> Array[Button]:
	return _mode_buttons.duplicate()


## The fog, weather and sound toggles, in that order, for tests.
func option_buttons() -> Array[Button]:
	var out: Array[Button] = [_fog, _weather, _sound]
	return out


## The music and 2P hotseat toggles.
func extra_option_buttons() -> Array[Button]:
	var out: Array[Button] = [_music, _hotseat]
	return out


## The difficulty, your-funds and enemy-funds buttons, in that order,
## for tests.
func choice_buttons() -> Array[Button]:
	var out: Array[Button] = [_difficulty, _player_funds, _enemy_funds]
	return out


## The Your CO and Opponent CO buttons.
func co_buttons() -> Array[Button]:
	var out: Array[Button] = [_player_co_btn, _enemy_co_btn]
	return out


func level_note() -> String:
	return _level_note.text


func chosen_options() -> MatchOptions:
	var options := MatchOptions.new()
	if _mode == Mode.MISSIONS:
		var m := _selected_mission()
		if m != null:
			return _options_from_mission(m)
	elif _mode == Mode.PUZZLES:
		var p := _selected_puzzle()
		if p != null:
			return _options_from_mission(p)
	options.map = selected_map()
	options.fog = _fog.button_pressed
	options.weather = _weather.button_pressed
	options.hotseat = _hotseat.button_pressed
	if not _levels.is_empty():
		options.difficulty = _levels[_level_index].key
	options.player_funds = _funds_choices[_player_funds_index]
	options.enemy_funds = _funds_choices[_enemy_funds_index]
	if not _cos.is_empty():
		options.player_co = _cos[_player_co_index].key
		options.enemy_co = _cos[_enemy_co_index].key
	if options.map != null:
		options.record_key = options.map.key
	return options


func start_button() -> Button:
	return _start


func continue_button() -> Button:
	return _continue


func column_width() -> float:
	return _column.custom_minimum_size.x


func logo_texture() -> Texture2D:
	return _logo.texture


func logo_size() -> Vector2:
	return _logo.custom_minimum_size


func logo_is_beside() -> bool:
	return not _layout.vertical


func _set_mode(new_mode: Mode) -> void:
	_mode = new_mode
	for i: int in range(_mode_buttons.size()):
		_mode_buttons[i].set_pressed_no_signal(i == int(new_mode))
	_map_row.visible = new_mode == Mode.SKIRMISH
	_mission_row.visible = new_mode == Mode.MISSIONS
	_puzzle_row.visible = new_mode == Mode.PUZZLES
	_random_row.visible = new_mode == Mode.RANDOM
	var is_custom: bool = new_mode == Mode.SKIRMISH or new_mode == Mode.RANDOM
	var show_cos: bool = is_custom and not _cos.is_empty()
	_co_heading.visible = show_cos
	_co_row.visible = show_cos
	_co_note.visible = show_cos
	_options_heading.visible = is_custom
	_options_row.visible = is_custom
	_balance_heading.visible = is_custom
	_balance_row.visible = is_custom
	_level_note.visible = is_custom
	match new_mode:
		Mode.SKIRMISH:
			_map_heading.text = "Map"
			_start.text = "Start match"
		Mode.MISSIONS:
			_map_heading.text = "Campaign Missions"
			_start.text = "Start mission"
		Mode.PUZZLES:
			_map_heading.text = "Tactical Puzzles"
			_start.text = "Start puzzle"
		Mode.RANDOM:
			_map_heading.text = "Random Skirmish"
			_start.text = "Generate & start"
	_refresh_mission_note()
	_refresh_choices()


func _selected_mission() -> MissionCatalog.MissionDef:
	for i: int in range(_mission_row.get_child_count()):
		if (_mission_row.get_child(i) as Button).button_pressed:
			return _missions[i]
	return null


func _selected_puzzle() -> MissionCatalog.MissionDef:
	for i: int in range(_puzzle_row.get_child_count()):
		if (_puzzle_row.get_child(i) as Button).button_pressed:
			return _puzzles[i]
	return null


func _options_from_mission(m: MissionCatalog.MissionDef) -> MatchOptions:
	var opt := MatchOptions.new()
	opt.map = m.map
	opt.fog = m.fog
	opt.weather = m.weather
	opt.difficulty = m.difficulty
	opt.player_funds = m.player_funds
	opt.enemy_funds = m.enemy_funds
	opt.player_co = m.player_co
	opt.enemy_co = m.enemy_co
	opt.turn_limit = m.turn_limit
	opt.par_days = m.par_days
	opt.initial_player_meter = m.initial_player_meter
	opt.briefing = m.briefing
	opt.record_key = m.key
	return opt


func _refresh_mission_note() -> void:
	if _mode == Mode.MISSIONS:
		var m := _selected_mission()
		_mission_note.text = m.briefing if m != null else ""
		_mission_note.visible = not _mission_note.text.is_empty()
	elif _mode == Mode.PUZZLES:
		var p := _selected_puzzle()
		_mission_note.text = p.briefing if p != null else ""
		_mission_note.visible = not _mission_note.text.is_empty()
	else:
		_mission_note.visible = false


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


func _step_player_co() -> void:
	if not _cos.is_empty():
		_player_co_index = (_player_co_index + 1) % _cos.size()
	_refresh_choices()


func _step_enemy_co() -> void:
	if not _cos.is_empty():
		_enemy_co_index = (_enemy_co_index + 1) % _cos.size()
	_refresh_choices()


func _step_random_preset() -> void:
	_random_preset_index = (_random_preset_index + 1) % MapGenerator.PRESETS.size()
	_refresh_choices()


func _step_random_seed() -> void:
	_random_seed = (_random_seed * 37 + 17) % 997 + 1
	_refresh_choices()


func _refresh_choices() -> void:
	var level_name := "Normal"
	var note := ""
	if not _levels.is_empty():
		level_name = _levels[_level_index].display_name
		note = _levels[_level_index].description
	_difficulty.text = "Difficulty: %s" % level_name
	_difficulty.disabled = _hotseat.button_pressed
	_level_note.text = (
		"2-Player Pass-and-Play: Red vs Blue on one screen." if _hotseat.button_pressed else note
	)
	_player_funds.text = "Your funds: %s" % _thousands(_funds_choices[_player_funds_index])
	_enemy_funds.text = "Enemy funds: %s" % _thousands(_funds_choices[_enemy_funds_index])
	if not _cos.is_empty():
		var p_co := _cos[_player_co_index]
		var e_co := _cos[_enemy_co_index]
		_player_co_btn.text = "Your CO: %s" % p_co.display_name
		_enemy_co_btn.text = "Opponent CO: %s" % e_co.display_name
		_co_note.text = "%s — %s" % [p_co.display_name, p_co.description]
	var preset: StringName = MapGenerator.PRESETS[_random_preset_index]
	_random_preset_btn.text = "Terrain: %s" % MapGenerator.PRESET_NAMES.get(preset, String(preset))
	_random_seed_btn.text = "Seed: #%d (Next)" % _random_seed


static func _thousands(amount: int) -> String:
	var digits := str(amount)
	var out := ""
	for i: int in range(digits.length()):
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return out


func _fit() -> void:
	var screen := get_viewport().get_visible_rect().size
	var available := screen.x - 2.0 * SIDE_MARGIN
	var col_w := clampf(available, MIN_WIDTH, MAX_WIDTH)
	if _logo.texture != null:
		var art := _logo.texture.get_size()
		var shared := available - BESIDE_GAP
		var beside := (
			screen.y < BESIDE_BELOW_HEIGHT and shared * (1.0 - LOGO_WIDTH_SHARE) >= MIN_WIDTH
		)
		var room := Vector2(col_w, screen.y * LOGO_HEIGHT_SHARE)
		if beside:
			room = Vector2(shared * LOGO_WIDTH_SHARE, screen.y - 2.0 * SIDE_MARGIN)
		var logo_sz := (art * minf(room.x / art.x, room.y / art.y)).round()
		if beside:
			col_w = clampf(shared - logo_sz.x, MIN_WIDTH, MAX_WIDTH)
		_layout.vertical = not beside
		_layout.add_theme_constant_override("separation", BESIDE_GAP if beside else STACKED_GAP)
		_logo.custom_minimum_size = logo_sz
	_column.custom_minimum_size.x = col_w
	_level_note.custom_minimum_size.x = col_w
	_co_note.custom_minimum_size.x = col_w
	_mission_note.custom_minimum_size.x = col_w


func _flow_row() -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	_column.add_child(row)
	return row


static func _rebuild_flow(row: HFlowContainer) -> void:
	for old: Node in row.get_children():
		row.remove_child(old)
		old.free()


static func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = ROW_HEIGHT
	return button


static func _toggle(text: String) -> Button:
	var toggle := _button("")
	toggle.toggle_mode = true
	toggle.set_meta(&"label", text)
	toggle.toggled.connect(func(on: bool) -> void: _caption(toggle, on))
	_caption(toggle, false)
	return toggle


static func _caption(toggle: Button, on: bool) -> void:
	toggle.text = "%s: %s" % [toggle.get_meta(&"label"), "On" if on else "Off"]


static func _set_toggle(toggle: Button, on: bool) -> void:
	toggle.set_pressed_no_signal(on)
	_caption(toggle, on)


static func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.modulate = Color(1, 1, 1, 0.6)
	return label
