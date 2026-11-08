class_name UnitLayer
extends Node2D
## Pools UnitView instances keyed by unit id (§8). Milestone 4 exposes a
## full-state sync() for the static display; event-driven create/free
## (UnitCreated / UnitDestroyed via EventPlayer) arrives with the
## playable-loop milestone.

## Optional scene for unit views (unit_view.tscn, wired in the editor).
## When absent, bare UnitView nodes with placeholder drawing are used.
@export var unit_view_scene: PackedScene
## Sprite sheet handed to every view; null keeps the placeholder bodies.
@export var art_set: ArtSet

var _views: Dictionary[int, UnitView] = {}


## Reconciles views with `state`: creates missing, refreshes existing,
## frees departed. Loaded units (inside a carrier) have no view, and
## with a `perspective_team` under fog, neither do enemies that team
## cannot see (-1 = omniscient).
func sync(state: GameState, perspective_team: int = -1) -> void:
	var seen: Dictionary[int, bool] = {}
	var mask := PackedByteArray()
	if perspective_team >= 0:
		mask = Fog.mask_for(state, perspective_team)
	for uid: int in state.units:
		var unit: UnitState = state.units[uid]
		if unit.carrier_id != -1:
			continue
		if perspective_team >= 0 and not Fog.sees_unit(state, perspective_team, unit, mask):
			continue
		seen[uid] = true
		var view: UnitView
		if _views.has(uid):
			view = _views[uid]
		else:
			view = _make_view()
			add_child(view)
			_views[uid] = view
		view.present(unit, state.ruleset.unit_types[unit.type_id])
	for uid: int in _views.keys():
		if not seen.has(uid):
			var stale: UnitView = _views[uid]
			_views.erase(uid)
			remove_child(stale)
			stale.queue_free()


## The view for `unit_id`, or null if none exists.
func view_for(unit_id: int) -> UnitView:
	if _views.has(unit_id):
		return _views[unit_id]
	return null


func _make_view() -> UnitView:
	var view: UnitView
	if unit_view_scene != null:
		view = unit_view_scene.instantiate() as UnitView
	else:
		view = UnitView.new()
	view.art = art_set
	return view
