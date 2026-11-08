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


## Gives the player the state to re-sync views from after a batch.
func setup(state: GameState) -> void:
	_state = state


## Plays the ordered event log, then reconciles every view with the
## post-action state (the safety net that keeps display == state).
func play(events: Array[GameEvent]) -> void:
	for e: GameEvent in events:
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
	if _state != null and unit_layer != null:
		unit_layer.sync(_state, perspective_team)


func _animate_move(e: Events.UnitMoved) -> void:
	var view := unit_layer.view_for(e.unit_id)
	if view == null or skip_animations:
		return
	var last: int = visible_steps(e, view.team)
	if last < 1:
		return
	var tw := create_tween()
	for i: int in range(1, last + 1):
		tw.tween_property(view, "position", MapRenderer.world_pos(e.path[i]), seconds_per_tile)
	await tw.finished


## Index of the last path tile the move animation may reach: where an
## ambush stopped the unit, and for an enemy of `perspective_team`
## under fog, no further than the step before it first leaves that
## team's sight — tracing it into the dark would reveal where it went.
func visible_steps(e: Events.UnitMoved, mover_team: int) -> int:
	var last: int = e.interrupted_at if e.interrupted_at >= 0 else e.path.size() - 1
	if _state == null or perspective_team < 0 or mover_team == perspective_team:
		return last
	var mask := Fog.mask_for(_state, perspective_team)
	for i: int in range(1, last + 1):
		if not Fog.sees_at(_state, perspective_team, e.path[i], mask):
			return i - 1
	return last


func _flash(unit_id: int) -> void:
	var view := unit_layer.view_for(unit_id)
	if view == null or skip_animations:
		return
	var tw := create_tween()
	tw.tween_property(view, "modulate", Color(1.0, 0.35, 0.35), flash_seconds)
	tw.tween_property(view, "modulate", Color.WHITE, flash_seconds)
	await tw.finished


func _fade_out(unit_id: int) -> void:
	var view := unit_layer.view_for(unit_id)
	if view == null or skip_animations:
		return
	var tw := create_tween()
	tw.tween_property(view, "modulate:a", 0.0, flash_seconds * 2.0)
	await tw.finished
