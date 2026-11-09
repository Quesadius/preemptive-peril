class_name BattleController
extends Node
## The input state machine (§8): cursor + confirm/cancel in, Actions out.
## Nothing is committed until the final confirm — every cancel before
## that is pure controller state, no core call, no undo machinery. All
## legality questions go to ActionGenerator/Rules/Economy; this node
## never decides what is legal on its own.
##
## Since the UI milestone the menus are real: confirming a destination
## opens the verb menu (ACTION_MENU), owned factories open the build
## menu (BUILD_MENU), and confirming an empty tile offers End Turn.
## TARGET_SELECT shows the damage forecast for the hovered target.
## ENEMY_TURN plays AI-owned turns through the same commit pipeline;
## GAME_OVER announces the result and freezes play — confirming there
## asks for a new match (restart_requested), which Battle answers.

signal action_rejected(code: StringName)
signal restart_requested

enum State {
	IDLE,
	UNIT_SELECTED,
	CHOOSING_DESTINATION,
	ACTION_MENU,
	TARGET_SELECT,
	BUILD_MENU,
	EXECUTING,
	ENEMY_TURN,
	GAME_OVER,
}

const VERB_LABELS: Dictionary[int, String] = {
	UnitAction.Verb.ATTACK: "Attack",
	UnitAction.Verb.CAPTURE: "Capture",
	UnitAction.Verb.SUPPLY: "Supply",
	UnitAction.Verb.UNLOAD: "Unload",
	UnitAction.Verb.LOAD: "Load",
	UnitAction.Verb.JOIN: "Join",
	UnitAction.Verb.WAIT: "Wait",
}

@export var cursor: Cursor
@export var overlay: OverlayLayer
@export var unit_layer: UnitLayer
@export var map_renderer: MapRenderer
@export var event_player: EventPlayer
@export var hud: Hud
@export var fog_layer: FogLayer

var _state: GameState
var _phase: State = State.IDLE
var _selected_unit_id: int = -1
var _reachable: Dictionary[Vector2i, int] = {}
## Cheapest route per reachable tile, searched once at selection so the
## path preview doesn't re-run pathfinding on every cursor step.
var _paths: Dictionary[Vector2i, Array] = {}
var _current_path: Array[Vector2i] = []
var _targets: Array[Vector2i] = []
var _target_actions: Dictionary[Vector2i, UnitAction] = {}
var _target_is_attack: bool = false
var _target_index: int = 0
var _dest_verbs: Array[int] = []
var _menu_system: bool = false
var _inspecting: bool = false
var _danger_on: bool = false
var _system_entries: Array[Action] = []
var _build_coord: Vector2i = Vector2i.ZERO
var _view_team: int = 0
var _ai := SimpleAI.new()


## Binds the controller to a match state. Safe to call again on reload.
## If the first player is AI-owned, its turn starts immediately.
func setup(state: GameState) -> void:
	_state = state
	_reset_selection()
	_phase = State.IDLE
	if not _state.active_player().is_ai:
		_view_team = _state.active_player().team
	if cursor != null and not cursor.moved.is_connected(_on_cursor_moved):
		cursor.moved.connect(_on_cursor_moved)
	if hud != null:
		if not hud.action_menu.chosen.is_connected(_on_menu_chosen):
			hud.action_menu.chosen.connect(_on_menu_chosen)
			hud.action_menu.cancelled.connect(_on_menu_cancelled)
			hud.build_menu.chosen.connect(_on_build_chosen)
			hud.build_menu.cancelled.connect(_on_build_cancelled)
			hud.back_pressed.connect(cancel)
			hud.danger_pressed.connect(toggle_danger)
		hud.hide_result()
		hud.refresh(_state)
		if cursor != null:
			hud.inspect(_state, cursor.coord, _view_team)
	_refresh_fog()
	_run_ai_turns()


## Fog and unit visibility are always drawn from the human player's
## perspective (the last human to hold the turn, in hotseat terms).
func _refresh_fog() -> void:
	var perspective: int = _view_team if _state.config.fog_enabled else -1
	if fog_layer != null:
		fog_layer.update_fog(_state, _view_team)
	if event_player != null:
		event_player.perspective_team = perspective
	unit_layer.sync(_state, perspective)
	_refresh_danger()


## Toggles the persistent all-enemies danger overlay (the D key).
func toggle_danger() -> void:
	_danger_on = not _danger_on
	_refresh_danger()
	if hud != null:
		hud.set_danger_shown(_danger_on)


func _refresh_danger() -> void:
	if overlay == null or _state == null:
		return
	var tiles: Array[Vector2i] = []
	if _danger_on:
		tiles = Threat.team_danger_zone(_state, _view_team)
	overlay.show_danger(tiles)


## Current phase, for the HUD and for tests.
func phase() -> State:
	return _phase


## True when the selected unit can move to `tile` (false with nothing
## selected) — PointerInput deselects on a tap outside the range.
func can_reach(tile: Vector2i) -> bool:
	return _reachable.has(tile)


## True when `tile` is one of the targets (or drop tiles) on offer in
## TARGET_SELECT — PointerInput backs out on a tap anywhere else.
func is_target(tile: Vector2i) -> bool:
	return _target_actions.has(tile)


## Confirm (ui_accept). What it means depends on the phase. Menu phases
## are driven by the menus themselves.
func confirm() -> void:
	if _state == null:
		return
	match _phase:
		State.IDLE:
			_confirm_idle()
		State.UNIT_SELECTED, State.CHOOSING_DESTINATION:
			_confirm_destination()
		State.TARGET_SELECT:
			_confirm_target()
		State.GAME_OVER:
			restart_requested.emit()
		_:
			pass


## Cancel (ui_cancel): steps one phase back, touching nothing in core.
func cancel() -> void:
	match _phase:
		State.IDLE:
			_clear_inspection()
		State.UNIT_SELECTED, State.CHOOSING_DESTINATION:
			_reset_selection()
			_phase = State.IDLE
		State.ACTION_MENU:
			if hud != null:
				hud.action_menu.cancel_out()
		State.BUILD_MENU:
			if hud != null:
				hud.build_menu.cancel_out()
		State.TARGET_SELECT:
			_targets = []
			overlay.show_targets([])
			cursor.move_to(_current_path[_current_path.size() - 1])  # back to the unit
			if hud != null:
				hud.show_damage_preview(null)
				_phase = State.ACTION_MENU
				hud.action_menu.open(_verb_labels())
			else:
				_phase = State.CHOOSING_DESTINATION
		_:
			pass


func _unhandled_input(event: InputEvent) -> void:
	# While targeting, the arrows cycle targets instead of roaming the
	# cursor (this node sees input before the Cursor in tree order).
	if _phase == State.TARGET_SELECT:
		if event.is_action_pressed("ui_right", true) or event.is_action_pressed("ui_down", true):
			cycle_target(1)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("ui_left", true) or event.is_action_pressed("ui_up", true):
			cycle_target(-1)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("ui_accept"):
		confirm()
	elif event.is_action_pressed("ui_cancel"):
		cancel()
	elif event is InputEventKey and (event as InputEventKey).pressed:
		var key := event as InputEventKey
		if key.keycode == KEY_D and not key.echo:
			toggle_danger()
			get_viewport().set_input_as_handled()


func _confirm_idle() -> void:
	_clear_inspection()
	# Fog-honest lookup: a hidden enemy's tile must behave exactly like
	# an empty one, or the cursor becomes a minesweeper.
	var unit: UnitState = Fog.known_occupant(_state, _view_team, cursor.coord)
	if unit == null:
		var tile_owner: int = _state.map.property_owner[_state.map.idx(cursor.coord)]
		var terrain: TerrainType = _state.ruleset.terrain_types[_state.map.terrain_at(cursor.coord)]
		var mine: bool = tile_owner == _state.active_player().team
		if mine and terrain.builds != &"" and hud != null:
			_build_coord = cursor.coord
			_phase = State.BUILD_MENU
			hud.build_menu.open(_build_rows(_build_coord))
			return
		# Anywhere else: the system menu — CO powers when charged, then
		# End Turn.
		if hud != null:
			_menu_system = true
			_system_entries = []
			var labels: Array[String] = []
			for power_action: Action in ActionGenerator.powers(_state):
				var pa := power_action as PowerAction
				var co := Combat.co_of(_state, _state.active_player().team)
				var power := (
					co.super_power if pa.power_level == PlayerState.PowerState.SUPER else co.power
				)
				_system_entries.append(pa)
				labels.append("Power: %s" % power.display_name)
			_system_entries.append(EndTurnAction.new())
			labels.append("End Turn")
			_phase = State.ACTION_MENU
			hud.action_menu.open(labels)
			return
		_commit(EndTurnAction.new())  # headless fallback without a HUD
		return
	if unit.team != _state.active_player().team:
		_inspect_enemy(unit)
		return
	if unit.has_acted:
		return
	_selected_unit_id = unit.id
	_reachable = Movement.reachable(_state, unit.id)
	_paths = Movement.all_paths(_state, unit.id)
	_current_path = [unit.coord]
	overlay.show_move_range(_dict_keys(_reachable))
	overlay.set_path(_current_path)
	_phase = State.UNIT_SELECTED


## Enemy range inspection: blue = where it can move, red = every tile
## it could attack next turn (Threat.danger_zone). Pure display — the
## phase stays IDLE and clears on cursor movement or cancel.
func _inspect_enemy(unit: UnitState) -> void:
	_inspecting = true
	overlay.show_move_range(_dict_keys(Movement.reachable(_state, unit.id)))
	overlay.show_targets(Threat.danger_zone(_state, unit.id))


func _clear_inspection() -> void:
	if not _inspecting:
		return
	_inspecting = false
	overlay.clear()


func _confirm_destination() -> void:
	var dest := cursor.coord
	if not _reachable.has(dest):
		return
	# verbs_at is fog-honest: a hidden enemy's tile offers the ordinary
	# verbs (execution springs the ambush) rather than a refusal that would
	# reveal it, and an ally's tile offers only LOAD / JOIN, when legal.
	var verbs := ActionGenerator.verbs_at(_state, _selected_unit_id, dest)
	if verbs.is_empty():
		return  # ally tile with nothing to board or join
	_dest_verbs = verbs
	_menu_system = false
	_phase = State.ACTION_MENU
	if hud != null:
		hud.action_menu.open(_verb_labels())
		return
	# Headless fallback without a HUD: the last verb (WAIT on open ground).
	_commit(_unit_action(_dest_verbs[_dest_verbs.size() - 1], Vector2i.ZERO))


func _confirm_target() -> void:
	var at := cursor.coord
	if _target_actions.has(at):
		_commit(_target_actions[at])
	# Anything else: keep choosing (cancel returns to the menu).


func _on_menu_chosen(index: int) -> void:
	if _phase != State.ACTION_MENU:
		return
	if _menu_system:
		_menu_system = false
		var entry: Action = _system_entries[index]
		_system_entries = []
		_commit(entry)
		return
	var verb: int = _dest_verbs[index]
	if verb == UnitAction.Verb.ATTACK or verb == UnitAction.Verb.UNLOAD:
		# Both pick a tile next: attack targets or unload drop tiles.
		_enter_target_select(verb)
		return
	_commit(_unit_action(verb, Vector2i.ZERO))


## TARGET_SELECT serves any verb that needs a tile choice; the concrete
## per-tile actions come from the generator, the single legality source.
func _enter_target_select(verb: int) -> void:
	var dest: Vector2i = _current_path[_current_path.size() - 1]
	_target_actions = {}
	_target_is_attack = verb == UnitAction.Verb.ATTACK
	for a: Action in ActionGenerator.for_unit(_state, _selected_unit_id):
		var ua := a as UnitAction
		if ua.verb != verb or ua.path[ua.path.size() - 1] != dest:
			continue
		ua.path = _current_path.duplicate()  # honor the traced arrow
		_target_actions[ua.target_coord] = ua
	_targets = []
	_targets.assign(_target_actions.keys())
	_targets.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	overlay.show_targets(_targets)
	_phase = State.TARGET_SELECT
	_target_index = 0
	if not _targets.is_empty():
		cursor.move_to(_targets[0])  # snap; the moved signal shows the forecast


## Steps the target-select cursor through the sorted targets (arrow
## keys; +1 next, -1 previous). Public so tests mirror the input path.
func cycle_target(delta: int) -> void:
	if _phase != State.TARGET_SELECT or _targets.is_empty():
		return
	_target_index = wrapi(_target_index + delta, 0, _targets.size())
	cursor.move_to(_targets[_target_index])


func _on_menu_cancelled() -> void:
	if _phase != State.ACTION_MENU:
		return
	if _menu_system:
		_menu_system = false
		_phase = State.IDLE
		return
	_phase = State.CHOOSING_DESTINATION


func _on_build_chosen(type_id: int) -> void:
	if _phase != State.BUILD_MENU:
		return
	var build := BuildAction.new()
	build.unit_type_id = type_id
	build.coord = _build_coord
	_commit(build)


func _on_build_cancelled() -> void:
	if _phase == State.BUILD_MENU:
		_phase = State.IDLE


func _on_cursor_moved(c: Vector2i) -> void:
	if _state != null and hud != null:
		hud.inspect(_state, c, _view_team)
	if _phase == State.IDLE:
		_clear_inspection()
	if _phase == State.TARGET_SELECT:
		if hud != null:
			var preview: Combat.DamagePreview = null
			if _target_is_attack and _targets.has(c):
				preview = Combat.preview(_state, _selected_unit_id, _state.unit_at(c).id)
			hud.show_damage_preview(preview)
		return
	if _phase != State.UNIT_SELECTED and _phase != State.CHOOSING_DESTINATION:
		return
	_phase = State.CHOOSING_DESTINATION
	if _reachable.has(c):
		_update_path(c)
		overlay.set_path(_current_path)


## Extends the traced arrow like AW: step onto an adjacent tile extends,
## revisiting a path tile truncates back to it, anything unaffordable
## falls back to the cheapest route.
func _update_path(c: Vector2i) -> void:
	var last: Vector2i = _current_path[_current_path.size() - 1]
	if c == last:
		return
	var revisit: int = _current_path.find(c)
	if revisit >= 0:
		_current_path = _current_path.slice(0, revisit + 1)
		return
	if Grid.manhattan(last, c) == 1:
		var extended := _current_path.duplicate()
		extended.append(c)
		if Movement.validate_path(_state, _selected_unit_id, extended):
			_current_path = extended
			return
	var cheapest: Array[Vector2i] = []
	cheapest.assign(_paths.get(c, []))
	_current_path = cheapest


func _unit_action(verb: int, target: Vector2i) -> UnitAction:
	var action := UnitAction.new()
	action.unit_id = _selected_unit_id
	action.path = _current_path.duplicate()
	action.verb = verb
	action.target_coord = target
	return action


## The §8 commit: validate, apply, animate, refresh, back to IDLE (or
## GAME_OVER), then hand control to the AI while it holds the turn.
func _commit(action: Action) -> void:
	var err := Rules.validate(_state, action)
	if err != null:
		action_rejected.emit(err.code)
		push_warning("BattleController: rejected action (%s)" % err.code)
		return
	_phase = State.EXECUTING
	var events := Rules.apply(_state, action)
	await event_player.play(events)
	_reset_selection()
	if map_renderer != null:
		map_renderer.render(_state)
	if not _state.active_player().is_ai:
		_view_team = _state.active_player().team
	_refresh_fog()
	if hud != null:
		hud.refresh(_state)
		hud.on_events(events)
	_settle(events)
	await _run_ai_turns()


## Plays AI-owned turns to completion, one greedy action at a time,
## through the same validate/apply/animate pipeline the human uses.
func _run_ai_turns() -> void:
	while _phase == State.IDLE and _state.active_player().is_ai:
		_phase = State.ENEMY_TURN
		var view := StateView.for_team(_state, _state.active_player().team)
		var action := _ai.choose_action(view)
		if Rules.validate(_state, action) != null:
			push_warning("BattleController: AI chose an illegal action; ending its turn")
			action = EndTurnAction.new()
		var events := Rules.apply(_state, action)
		await event_player.play(events)
		if map_renderer != null:
			map_renderer.render(_state)
		if not _state.active_player().is_ai:
			_view_team = _state.active_player().team
		_refresh_fog()
		if hud != null:
			hud.refresh(_state)
			hud.on_events(events)
		_settle(events)


## Lands the phase after a committed action: IDLE, or GAME_OVER with the
## result on screen when the action ended the match.
func _settle(events: Array[GameEvent]) -> void:
	var ended: Events.GameEnded = null
	var reason: StringName = &""
	for e: GameEvent in events:
		if e is Events.GameEnded:
			ended = e as Events.GameEnded
		elif e is Events.PlayerEliminated:
			reason = (e as Events.PlayerEliminated).reason
	if ended == null:
		_phase = State.IDLE
		return
	_phase = State.GAME_OVER
	if hud != null:
		hud.show_result(result_text(ended.winning_team == _view_team, reason))


## The game-over message from the viewing player's side. `reason` is the
## final elimination's (Victory's "hq_captured" or "routed").
static func result_text(won: bool, reason: StringName) -> String:
	var how := ""
	match reason:
		&"hq_captured":
			how = "Enemy HQ captured." if won else "Your HQ has fallen."
		&"routed":
			how = "The enemy army is routed." if won else "Your army is routed."
	var headline := "Victory!" if won else "Defeat"
	return "%s\n%s\nPress Enter or click to play again." % [headline, how]


## Build-menu rows for the facility at `coord`: every type it can
## produce, affordability judged by Economy.validate_build — the single
## source of build legality.
func _build_rows(coord: Vector2i) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var terrain: TerrainType = _state.ruleset.terrain_types[_state.map.terrain_at(coord)]
	for type_id: int in range(_state.ruleset.unit_types.size()):
		var unit_type: UnitType = _state.ruleset.unit_types[type_id]
		if not unit_type.built_at.has(terrain.builds):
			continue
		var probe := BuildAction.new()
		probe.unit_type_id = type_id
		probe.coord = coord
		(
			rows
			. append(
				{
					"type_id": type_id,
					"label": "%s  %dG" % [unit_type.display_name, unit_type.cost],
					"affordable": Rules.validate(_state, probe) == null,
				}
			)
		)
	return rows


func _verb_labels() -> Array[String]:
	var out: Array[String] = []
	for verb: int in _dest_verbs:
		out.append(VERB_LABELS.get(verb, "?"))
	return out


func _reset_selection() -> void:
	_inspecting = false
	_selected_unit_id = -1
	_reachable = {}
	_paths = {}
	_current_path = []
	_targets = []
	_target_actions = {}
	_target_is_attack = false
	_target_index = 0
	_dest_verbs = []
	_menu_system = false
	if overlay != null:
		overlay.clear()
	if hud != null:
		hud.close_menus()


func _dict_keys(d: Dictionary[Vector2i, int]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.assign(d.keys())
	return out
