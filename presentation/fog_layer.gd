class_name FogLayer
extends Node2D
## Darkens tiles outside the viewing team's vision (§8). Pure view of
## Fog.compute(); recomputed on update_fog(), drawn with _draw(). With
## fog disabled the layer draws nothing.

const SHROUD := Color(0.02, 0.03, 0.08, 0.5)

var _mask: PackedByteArray = PackedByteArray()
var _size: Vector2i = Vector2i.ZERO


## Recomputes the mask for `team` and redraws.
func update_fog(state: GameState, team: int) -> void:
	if not state.config.fog_enabled:
		_mask = PackedByteArray()
		_size = Vector2i.ZERO
		queue_redraw()
		return
	_mask = Fog.compute(state, team)
	_size = Vector2i(state.map.width, state.map.height)
	queue_redraw()


## The current mask (empty when fog is off), for tests.
func mask() -> PackedByteArray:
	return _mask


func _draw() -> void:
	if _mask.is_empty():
		return
	var tile := float(MapRenderer.TILE_SIZE)
	for i: int in range(_mask.size()):
		if _mask[i] == 1:
			continue
		var c := Grid.from_idx(i, _size.x)
		draw_rect(Rect2(Vector2(c) * tile, Vector2(tile, tile)), SHROUD)
