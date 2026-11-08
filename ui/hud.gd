class_name Hud
extends CanvasLayer
## Script-built HUD (§9): status bar, terrain and unit info panels that
## follow the cursor, the damage preview, verb and build menus, and the
## turn banner. Author a real Theme as ui/theme/main_theme.tres and
## assign it to `theme_override` in the editor; until then a minimal
## dark theme is built in code.

@export var theme_override: Theme

var status_label: Label
var terrain_panel: TerrainInfoPanel
var unit_panel: UnitInfoPanel
var damage_panel: DamagePreviewPanel
var action_menu: ActionMenu
var build_menu: BuildMenu
var banner: Label

var _root: Control


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
	terrain_panel.set_anchors_and_offsets_preset(
		Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 8
	)
	_root.add_child(terrain_panel)
	unit_panel = UnitInfoPanel.new()
	unit_panel.set_anchors_and_offsets_preset(
		Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 8
	)
	_root.add_child(unit_panel)
	damage_panel = DamagePreviewPanel.new()
	damage_panel.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_RIGHT, Control.PRESET_MODE_MINSIZE, 8
	)
	_root.add_child(damage_panel)
	action_menu = ActionMenu.new()
	action_menu.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE, 0
	)
	_root.add_child(action_menu)
	build_menu = BuildMenu.new()
	build_menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE, 0)
	_root.add_child(build_menu)
	banner = Label.new()
	banner.add_theme_font_size_override("font_size", 28)
	banner.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 24
	)
	banner.visible = false
	_root.add_child(banner)


## Refreshes the status bar from the state (CO meter included).
func refresh(state: GameState) -> void:
	var player := state.active_player()
	var ai_tag := " (AI)" if player.is_ai else ""
	var co_tag := ""
	var co := Combat.co_of(state, player.team)
	if co != null:
		var burning := " *" if player.power_state != PlayerState.PowerState.NONE else ""
		co_tag = "   %s  Meter %d%s" % [co.display_name, player.power_meter, burning]
	status_label.text = (
		"Day %d   Team %d%s   Funds %d%s" % [state.day, player.team, ai_tag, player.funds, co_tag]
	)


## Points the info panels at `coord` (§9: they follow the cursor),
## showing only what `viewing_team` knows under fog: a hidden enemy
## reads as an empty tile. -1 = omniscient (fog off, tests).
func inspect(state: GameState, coord: Vector2i, viewing_team: int = -1) -> void:
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
