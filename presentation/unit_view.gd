class_name UnitView
extends Node2D
## One unit on screen (§8): sprite, team palette, HP pip, exhaustion
## tint. Until real art is wired via `sprite`, the placeholder body
## identifies itself two ways: a two-letter glyph from the type's
## display name, and a silhouette by movement class — circles walk,
## rectangles drive, diamonds fly. Reads display data only — never raw
## hp (display_hp() is the law, per CLAUDE.md).

enum BodyShape { RECT, CIRCLE, DIAMOND }

const BODY_HALF := 11
const GLYPH_COLOR := Color(0.0, 0.0, 0.0, 0.78)

@export var sprite: AnimatedSprite2D

var unit_id: int = -1
var team: int = 0
var display_hp: int = 10
var exhausted: bool = false
var type_label: String = ""
var body_shape: BodyShape = BodyShape.RECT


## Refreshes this view from a unit's current display data.
func present(unit: UnitState, unit_type: UnitType) -> void:
	unit_id = unit.id
	team = unit.team
	display_hp = unit.display_hp()
	exhausted = unit.has_acted
	type_label = _glyph_for(unit_type)
	body_shape = _shape_for(unit_type)
	position = MapRenderer.world_pos(unit.coord)
	modulate = Color(0.6, 0.6, 0.6) if exhausted else Color.WHITE
	if sprite != null and unit_type.sprite_frames != null:
		sprite.sprite_frames = unit_type.sprite_frames
	queue_redraw()


func _draw() -> void:
	if sprite != null and sprite.sprite_frames != null:
		return  # real art draws itself
	var fill := MapRenderer.team_color(team)
	var outline := Color(0.0, 0.0, 0.0, 0.6)
	match body_shape:
		BodyShape.CIRCLE:
			draw_circle(Vector2.ZERO, BODY_HALF, fill)
			draw_arc(Vector2.ZERO, BODY_HALF, 0.0, TAU, 24, outline, 2.0)
		BodyShape.DIAMOND:
			var points := PackedVector2Array(
				[
					Vector2(0, -BODY_HALF - 2),
					Vector2(BODY_HALF + 2, 0),
					Vector2(0, BODY_HALF + 2),
					Vector2(-BODY_HALF - 2, 0),
				]
			)
			draw_colored_polygon(points, fill)
			var closed := points.duplicate()
			closed.append(points[0])
			draw_polyline(closed, outline, 2.0)
		_:
			var body := Rect2(-BODY_HALF, -BODY_HALF, BODY_HALF * 2, BODY_HALF * 2)
			draw_rect(body, fill)
			draw_rect(body, outline, false, 2.0)
	var font := ThemeDB.fallback_font
	draw_string(
		font,
		Vector2(-BODY_HALF, 1.0),
		type_label,
		HORIZONTAL_ALIGNMENT_CENTER,
		BODY_HALF * 2.0,
		10,
		GLYPH_COLOR
	)
	if display_hp < 10:
		draw_string(
			font,
			Vector2(2.0, BODY_HALF + 3.0),
			str(display_hp),
			HORIZONTAL_ALIGNMENT_RIGHT,
			-1,
			12,
			Color.WHITE
		)


static func _glyph_for(unit_type: UnitType) -> String:
	var source := unit_type.display_name
	if source.is_empty():
		source = String(unit_type.key)
	return source.substr(0, 2).to_upper()


static func _shape_for(unit_type: UnitType) -> BodyShape:
	if unit_type.movement_class == null:
		return BodyShape.RECT
	match unit_type.movement_class.key:
		&"foot", &"boots":
			return BodyShape.CIRCLE
		&"air":
			return BodyShape.DIAMOND
	return BodyShape.RECT
