class_name EventPlayer
extends Node
## Translates the event log into animation, sequentially, with await
## (§8). This is the ONLY place animation pacing lives: a global speed
## and skip toggle here means every animation in the game respects them.
## Reads state for display data only; the events are the truth about
## what happened.

@export var unit_layer: UnitLayer
@export var camera_rig: CameraRig
@export var seconds_per_tile: float = 0.08
@export var flash_seconds: float = 0.12
## When true, play() applies results instantly with no tweens — used by
## headless tests and the player's skip setting.
@export var skip_animations: bool = false

## The team whose fog the board is drawn from (-1 = omniscient). Kept
## current by BattleController; play() honors it so neither a move
## animation nor the closing sync shows what that team can't see.
var perspective_team: int = -1

var _state: GameState
var _pre_mask: PackedByteArray = PackedByteArray()


class _BlastBurst:
	extends Node2D
	var radius: float = 4.0
	var max_radius: float = 20.0
	var progress: float = 0.0
	var ring_color: Color = Color(1.0, 0.55, 0.15, 0.95)

	func _draw() -> void:
		var r: float = lerpf(radius, max_radius, progress)
		var alpha: float = clampf(1.0 - progress, 0.0, 1.0)
		var fill := Color(1.0, 0.85, 0.35, alpha * 0.65)
		var ring := Color(ring_color.r, ring_color.g, ring_color.b, alpha)
		draw_circle(Vector2.ZERO, r * 0.65, fill)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 24, ring, maxf(1.5, 4.0 * alpha))
		# Radial sparks
		for i: int in range(8):
			var ang: float = float(i) * TAU / 8.0 + 0.25
			var p0 := Vector2(cos(ang), sin(ang)) * (r * 0.55)
			var p1 := Vector2(cos(ang), sin(ang)) * (r * 1.15)
			draw_line(p0, p1, Color(1.0, 0.92, 0.5, alpha), 1.6)


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
			var trap := e as Events.UnitAmbushed
			_spawn_popup(MapRenderer.world_pos(trap.coord), "AMBUSH!", Color(1.0, 0.75, 0.2))
			await _flash(trap.unit_id)
		elif e is Events.UnitAttacked:
			var atk := e as Events.UnitAttacked
			await _animate_attack(atk.attacker_id, atk.defender_id, atk.damage)
		elif e is Events.UnitCounterattacked:
			var ctr := e as Events.UnitCounterattacked
			await _animate_attack(ctr.attacker_id, ctr.defender_id, ctr.damage)
		elif e is Events.UnitDestroyed:
			var dead := e as Events.UnitDestroyed
			if _shown(dead.unit_id):
				_spawn_burst(MapRenderer.world_pos(dead.coord), 26.0, Color(1.0, 0.3, 0.1, 1.0))
				_shake_camera(5.0)
			await _fade_out(dead.unit_id)
		elif e is Events.SiloLaunched:
			await _animate_silo(e as Events.SiloLaunched)
		elif e is Events.UnitRepaired:
			var rep := e as Events.UnitRepaired
			var rv := unit_layer.view_for(rep.unit_id) if unit_layer != null else null
			if rv != null and rep.hp_restored > 0:
				var dhp: int = maxi(1, int(round(rep.hp_restored / 10.0)))
				_spawn_popup(rv.position, "+%d" % dhp, Color(0.35, 1.0, 0.45))
	_pre_mask = PackedByteArray()
	if sync_after and _state != null and unit_layer != null:
		unit_layer.sync(_state, perspective_team)


## The sound effect for `e`, or &"" for none: silent events, and anything
## the viewing team couldn't see under fog — a hidden enemy moving,
## shooting, building or capturing must not be heard either. Ownership
## changes, silo launches, and turn starts are public knowledge and always sound.
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
	elif e is Events.SiloLaunched:
		key = &"silo"
	elif e is Events.PowerActivated:
		key = &"power"
	elif e is Events.TurnStarted:
		key = &"turn"
	return key if heard else &""


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


func visible_steps(e: Events.UnitMoved, mover_team: int) -> int:
	var last: int = e.interrupted_at if e.interrupted_at >= 0 else e.path.size() - 1
	if _state == null or perspective_team < 0 or mover_team == perspective_team:
		return last
	var mask := _active_mask()
	for i: int in range(1, last + 1):
		if not Fog.sees_at(_state, perspective_team, e.path[i], mask):
			return i - 1
	return last


func _animate_attack(attacker_id: int, defender_id: int, damage: int) -> void:
	if _should_skip() or unit_layer == null:
		return
	var av := unit_layer.view_for(attacker_id)
	var dv := unit_layer.view_for(defender_id)
	var secs: float = flash_seconds / _speed_scale()
	if av != null and dv != null:
		var dir: Vector2 = (dv.position - av.position).normalized()
		var start_pos: Vector2 = av.position
		var tw_lunge := create_tween()
		tw_lunge.tween_property(av, "position", start_pos + dir * 7.0, secs * 0.45)
		tw_lunge.tween_property(av, "position", start_pos, secs * 0.55)
		await tw_lunge.finished
	if dv != null:
		_spawn_burst(dv.position, 16.0, Color(1.0, 0.55, 0.15, 0.95))
		var disp_dmg: int = maxi(0, int(round(damage / 10.0)))
		if damage > 0:
			var txt := "-%d" % maxi(1, disp_dmg)
			_spawn_popup(dv.position, txt, Color(1.0, 0.35, 0.25))
			_shake_camera(3.0 if damage >= 40 else 1.8)
		await _flash(defender_id)


func _animate_silo(e: Events.SiloLaunched) -> void:
	if _should_skip() or unit_layer == null:
		return
	var center := MapRenderer.world_pos(e.target_coord)
	_spawn_burst(center, 58.0, Color(1.0, 0.42, 0.08, 1.0))
	_shake_camera(7.5)
	for i: int in range(e.affected_unit_ids.size()):
		var uid: int = e.affected_unit_ids[i]
		var dmg: int = e.damages[i]
		var v := unit_layer.view_for(uid)
		if v != null and dmg > 0:
			var disp: int = maxi(1, int(round(dmg / 10.0)))
			_spawn_popup(v.position, "-%d" % disp, Color(1.0, 0.55, 0.15))
	var secs: float = (flash_seconds * 2.5) / _speed_scale()
	var tw := create_tween()
	tw.tween_interval(secs)
	await tw.finished


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


func _spawn_burst(at: Vector2, max_r: float, color: Color) -> void:
	if _should_skip() or unit_layer == null or not is_inside_tree():
		return
	var burst := _BlastBurst.new()
	burst.position = at
	burst.max_radius = max_r
	burst.ring_color = color
	burst.z_index = 40
	unit_layer.add_child(burst)
	var secs: float = 0.24 / _speed_scale()
	var tw := burst.create_tween()
	tw.tween_method(
		func(p: float) -> void:
			burst.progress = p
			burst.queue_redraw(),
		0.0,
		1.0,
		secs
	)
	tw.tween_callback(burst.queue_free)


func _spawn_popup(at: Vector2, text: String, color: Color) -> void:
	if _should_skip() or unit_layer == null or not is_inside_tree():
		return
	var label := Label.new()
	label.text = text
	label.position = at + Vector2(-14.0, -22.0)
	label.z_index = 50
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.08, 0.95))
	label.add_theme_constant_override("outline_size", 3)
	unit_layer.add_child(label)
	var secs: float = 0.55 / _speed_scale()
	var tw := label.create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "position:y", label.position.y - 18.0, secs)
	tw.tween_property(label, "modulate:a", 0.0, secs)
	tw.set_parallel(false)
	tw.tween_callback(label.queue_free)


func _shake_camera(strength: float) -> void:
	if _should_skip() or camera_rig == null or camera_rig.camera == null or not is_inside_tree():
		return
	var cam := camera_rig.camera
	var tw := cam.create_tween()
	var step: float = 0.035 / _speed_scale()
	tw.tween_property(cam, "offset", Vector2(strength, -strength * 0.6), step)
	tw.tween_property(cam, "offset", Vector2(-strength * 0.8, strength * 0.7), step)
	tw.tween_property(cam, "offset", Vector2(strength * 0.4, strength * 0.3), step)
	tw.tween_property(cam, "offset", Vector2.ZERO, step)
