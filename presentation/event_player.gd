class_name EventPlayer
extends Node
## Translates the event log into animation, sequentially, with await
## (§8). This is the ONLY place animation pacing lives: a global speed
## and skip toggle here means every animation in the game respects them.
## Reads state for display data only; the events are the truth about
## what happened.

@export var unit_layer: UnitLayer
@export var seconds_per_tile: float = 0.08
@export var flash_seconds: float = 0.12
## When true, play() applies results instantly with no tweens — used by
## headless tests and, later, the player's skip setting.
@export var skip_animations: bool = false

## The team whose fog the board is drawn from (-1 = omniscient). Kept
## current by BattleController; play() honors it so neither a move
## animation nor the closing sync shows what that team can't see.
var perspective_team: int = -1

var _state: GameState
var _pre_mask: PackedByteArray = PackedByteArray()


## Gives the player the state to re-sync views from after a batch.
func setup(state: GameState) -> void:
	_state = state


## Plays the ordered event log, then optionally reconciles every view with
## the post-action state. `pre_mask` is the viewer's pre-action fog mask so
## moves onto a just-captured property stay visible during animation.
func play(
	events: Array[GameEvent], pre_mask: PackedByteArray = PackedByteArray(), sync_after: bool = true
) -> void:
	_pre_mask = pre_mask
	for e: GameEvent in events:
		var sound := sound_for(e)
		if sound != &"":
			Sfx.play(self, sound)
		if e is Events.UnitMoved:
			await _animate_move(e as Events.UnitMoved)
		elif e is Events.UnitAmbushed:
			await _flash((e as Events.UnitAmbushed).unit_id)
		elif e is Events.UnitAttacked:
			await _flash((e as Events.UnitAttacked).defender_id)
		elif e is Events.UnitCounterattacked:
			await _flash((e as Events.UnitCounterattacked).defender_id)
		elif e is Events.UnitDestroyed:
			await _fade_out((e as Events.UnitDestroyed).unit_id)
		# Remaining events (exhaustion, turn markers) apply in the sync.
	_pre_mask = PackedByteArray()
	if sync_after and _state != null and unit_layer != null:
		unit_layer.sync(_state, perspective_team)


## The sound effect for `e`, or &"" for none: silent events, and anything
## the viewing team couldn't see under fog — a hidden enemy moving,
## shooting, building or capturing must not be heard either. Ownership
## changes and turn starts are public knowledge and always sound.
func sound_for(e: GameEvent) -> StringName:
	var key: StringName = &""
	var heard: bool = true
	if e is Events.UnitMoved:
		var moved := e as Events.UnitMoved
		key = &"move"
		heard = _shown(moved.unit_id) or _move_enters_sight(moved)
	elif e is Events.UnitAmbushed:
		var trap := e as Events.UnitAmbushed
		key = &"ambush"
		heard = _shown(trap.unit_id) or _in_sight(trap.coord)
	elif e is Events.UnitAttacked:
		var hit := e as Events.UnitAttacked
		key = &"attack"
		heard = _shown(hit.attacker_id) or _shown(hit.defender_id)
	elif e is Events.UnitCounterattacked:
		var back := e as Events.UnitCounterattacked
		key = &"attack"
		heard = _shown(back.attacker_id) or _shown(back.defender_id)
	elif e is Events.UnitDestroyed:
		key = &"destroy"
		heard = _shown((e as Events.UnitDestroyed).unit_id)
	elif e is Events.CaptureProgressed:
		key = &"capture"
		heard = _shown((e as Events.CaptureProgressed).unit_id)
	elif e is Events.UnitCreated:
		key = &"build"
		heard = _in_sight((e as Events.UnitCreated).coord)
	elif e is Events.PropertyCaptured:
		key = &"captured"
	elif e is Events.PowerActivated:
		key = &"power"
	elif e is Events.TurnStarted:
		key = &"turn"
	return key if heard else &""


## True when the unit is on screen — it has a view, which under fog only
## units the viewing team can see do.
func _shown(unit_id: int) -> bool:
	return unit_layer != null and unit_layer.view_for(unit_id) != null


func _in_sight(coord: Vector2i) -> bool:
	if _state == null or perspective_team < 0:
		return true
	return Fog.sees_at(_state, perspective_team, coord, _active_mask())


func _active_mask() -> PackedByteArray:
	if not _pre_mask.is_empty():
		return _pre_mask
	if _state == null or perspective_team < 0:
		return PackedByteArray()
	return Fog.mask_for(_state, perspective_team)


func _should_skip() -> bool:
	if skip_animations:
		return true
	if is_inside_tree():
		var store := get_node_or_null("/root/SettingsStore")
		if store != null and bool(store.get_setting("skip_animations")):
			return true
	return false


func _speed_scale() -> float:
	if is_inside_tree():
		var store := get_node_or_null("/root/SettingsStore")
		if store != null:
			var speed: Variant = store.get_setting("animation_speed")
			if speed is float and float(speed) > 0.0:
				return clampf(float(speed), 0.25, 4.0)
	return 1.0


func _move_enters_sight(e: Events.UnitMoved) -> bool:
	if _state == null or perspective_team < 0:
		return false
	var last: int = e.interrupted_at if e.interrupted_at >= 0 else e.path.size() - 1
	var mask := _active_mask()
	for i: int in range(1, last + 1):
		if Fog.sees_at(_state, perspective_team, e.path[i], mask):
			return true
	return false


func _animate_move(e: Events.UnitMoved) -> void:
	if _should_skip() or unit_layer == null:
		return
	var view := unit_layer.view_for(e.unit_id)
	var step_secs: float = seconds_per_tile / _speed_scale()
	if view == null:
		# Enemy moved from fog into sight: spawn its view at the first
		# visible tile and animate the visible suffix.
		if _state == null or not _state.units.has(e.unit_id):
			return
		var last_idx: int = e.interrupted_at if e.interrupted_at >= 0 else e.path.size() - 1
		var mask := _active_mask()
		var first_vis: int = -1
		for i: int in range(1, last_idx + 1):
			if Fog.sees_at(_state, perspective_team, e.path[i], mask):
				first_vis = i
				break
		if first_vis < 0:
			return
		var unit: UnitState = _state.units[e.unit_id]
		view = unit_layer.ensure_view(unit, _state.ruleset.unit_types[unit.type_id])
		view.position = MapRenderer.world_pos(e.path[first_vis])
		var end_vis: int = first_vis
		for i: int in range(first_vis + 1, last_idx + 1):
			if not Fog.sees_at(_state, perspective_team, e.path[i], mask):
				break
			end_vis = i
		if end_vis <= first_vis:
			return
		var tw_in := create_tween()
		for i: int in range(first_vis + 1, end_vis + 1):
			tw_in.tween_property(view, "position", MapRenderer.world_pos(e.path[i]), step_secs)
		await tw_in.finished
		return
	var last: int = visible_steps(e, view.team)
	if last < 1:
		return
	var tw := create_tween()
	for i: int in range(1, last + 1):
		tw.tween_property(view, "position", MapRenderer.world_pos(e.path[i]), step_secs)
	await tw.finished


## Index of the last path tile the move animation may reach: where an
## ambush stopped the unit, and for an enemy of `perspective_team`
## under fog, no further than the step before it first leaves that
## team's sight — tracing it into the dark would reveal where it went.
func visible_steps(e: Events.UnitMoved, mover_team: int) -> int:
	var last: int = e.interrupted_at if e.interrupted_at >= 0 else e.path.size() - 1
	if _state == null or perspective_team < 0 or mover_team == perspective_team:
		return last
	var mask := _active_mask()
	for i: int in range(1, last + 1):
		if not Fog.sees_at(_state, perspective_team, e.path[i], mask):
			return i - 1
	return last


func _flash(unit_id: int) -> void:
	if _should_skip() or unit_layer == null:
		return
	var view := unit_layer.view_for(unit_id)
	if view == null:
		return
	var original: Color = view.modulate
	var secs: float = flash_seconds / _speed_scale()
	var tw := create_tween()
	tw.tween_property(view, "modulate", Color(1.0, 0.35, 0.35), secs)
	tw.tween_property(view, "modulate", original, secs)
	await tw.finished


func _fade_out(unit_id: int) -> void:
	if _should_skip() or unit_layer == null:
		return
	var view := unit_layer.view_for(unit_id)
	if view == null:
		return
	var secs: float = (flash_seconds * 2.0) / _speed_scale()
	var tw := create_tween()
	tw.tween_property(view, "modulate:a", 0.0, secs)
	await tw.finished
