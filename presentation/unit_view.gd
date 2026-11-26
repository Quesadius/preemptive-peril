class_name UnitView
extends Node2D
## One unit on screen (§8): sprite, team palette, HP pip, exhaustion
## tint. With an ArtSet (`art`, set by UnitLayer) that maps the type, the
## unit draws its team-colored sheet sprite, mirrored for left-facing
## teams, with the sheet's HP badge and an optional short tag for types
## that borrow another's sprite. Otherwise the placeholder body
## identifies itself two ways: a two-letter glyph from the type's
## display name, and a silhouette by movement class — circles walk,
## rectangles drive, diamonds fly. Reads display data only — never raw
## hp (display_hp() is the law, per CLAUDE.md).

enum BodyShape { RECT, CIRCLE, DIAMOND }

const BODY_HALF := 11
const GLYPH_COLOR := Color(0.0, 0.0, 0.0, 0.78)

@export var sprite: AnimatedSprite2D

var art: ArtSet
var unit_id: int = -1
var team: int = 0
var display_hp: int = 10
var exhausted: bool = false
var type_label: String = ""
var body_shape: BodyShape = BodyShape.RECT
## The sheet tile drawn for this unit (ArtSet.NONE = placeholder body).
var art_tile: Vector2i = ArtSet.NONE
## Short label over borrowed sprites ("" when the sprite is its own).
var tag: String = ""
## On-map status badges synced from GameState by UnitLayer.
var is_capturing: bool = false
var cargo_count: int = 0
var low_fuel: bool = false
var low_ammo: bool = false
var power_active: bool = false

var _art_sprite: Sprite2D
var _art_texture: AtlasTexture


## Refreshes this view from a unit's current display data.
func present(
	unit: UnitState, unit_type: UnitType, p_capturing: bool = false, p_power_active: bool = false
) -> void:
	unit_id = unit.id
	team = unit.team
	display_hp = unit.display_hp()
	exhausted = unit.has_acted
	is_capturing = p_capturing
	cargo_count = unit.cargo.size()
	low_fuel = unit_type.max_fuel > 0 and unit.fuel * 4 <= unit_type.max_fuel
	low_ammo = unit_type.max_ammo > 0 and unit.ammo * 4 <= unit_type.max_ammo
	power_active = p_power_active
	type_label = _glyph_for(unit_type)
	body_shape = _shape_for(unit_type)
	position = MapRenderer.world_pos(unit.coord)
	modulate = Color(0.6, 0.6, 0.6) if exhausted else Color.WHITE
	if sprite != null and unit_type.sprite_frames != null:
		sprite.sprite_frames = unit_type.sprite_frames
	art_tile = ArtSet.NONE
	tag = ""
	if art != null and art.sheet != null:
		art_tile = art.unit_tile(unit_type.key, unit.team)
	if art_tile != ArtSet.NONE:
		tag = art.unit_tags.get(unit_type.key, "")
		_show_art_sprite()
	elif _art_sprite != null:
		_art_sprite.visible = false
	queue_redraw()


## True when the sheet sprite is showing and mirrored, for tests.
func art_flipped() -> bool:
	return _art_sprite != null and _art_sprite.visible and _art_sprite.flip_h


func _show_art_sprite() -> void:
	if _art_sprite == null:
		_art_texture = AtlasTexture.new()
		_art_sprite = Sprite2D.new()
		# Draw beneath this node so the HP badge and tag from _draw()
		# land on top of the sprite.
		_art_sprite.show_behind_parent = true
		add_child(_art_sprite)
	_art_texture.atlas = art.sheet
	_art_texture.region = art.region(art_tile)
	_art_sprite.texture = _art_texture
	var s := art.draw_scale()
	var filter := (
		CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		if art.tile_px > MapRenderer.TILE_SIZE
		else CanvasItem.TEXTURE_FILTER_NEAREST
	)
	texture_filter = filter
	_art_sprite.texture_filter = filter
	_art_sprite.scale = Vector2(s, s)
	_art_sprite.flip_h = art.left_facing_teams.has(team)
	_art_sprite.visible = true


func _draw() -> void:
	if art_tile != ArtSet.NONE:
		_draw_art_badges()
		return
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


## The sheet's HP badge (drawn over the whole tile; the badge sits in its
## bottom-right corner), plus capture flag, cargo, low-fuel/ammo, and active
## CO power aura badges.
func _draw_art_badges() -> void:
	var half := MapRenderer.TILE_SIZE / 2.0
	if power_active and not exhausted:
		var aura := MapRenderer.team_color(team).lightened(0.35)
		aura.a = 0.65
		draw_rect(
			Rect2(-half + 1.0, -half + 1.0, half * 2.0 - 2.0, half * 2.0 - 2.0), aura, false, 1.5
		)
	if display_hp < 10:
		var digit := art.digit_tile(display_hp)
		if digit != ArtSet.NONE:
			var tile_rect := Rect2(-half, -half, half * 2.0, half * 2.0)
			draw_texture_rect_region(art.sheet, tile_rect, art.region(digit))
	if is_capturing:
		var flag := art.flag_tile(team)
		if flag != ArtSet.NONE:
			var flag_rect := Rect2(-half + 1.0, -half + 1.0, 12.0, 12.0)
			draw_texture_rect_region(art.sheet, flag_rect, art.region(flag))
	if cargo_count > 0:
		var badge_rect := Rect2(half - 11.0, -half + 1.0, 10.0, 10.0)
		draw_rect(badge_rect, Color(0.12, 0.45, 0.85, 0.92))
		draw_rect(badge_rect, Color(1.0, 1.0, 1.0, 0.85), false, 1.0)
		var font := ThemeDB.fallback_font
		var txt := "L" if cargo_count == 1 else str(cargo_count)
		draw_string(
			font,
			Vector2(half - 9.0, -half + 9.0),
			txt,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			8,
			Color.WHITE
		)
	if low_fuel and art.fuel_icon_tile != ArtSet.NONE:
		var fuel_rect := Rect2(-half + 1.0, half - 12.0, 11.0, 11.0)
		draw_texture_rect_region(art.sheet, fuel_rect, art.region(art.fuel_icon_tile))
	elif low_ammo:
		draw_circle(Vector2(-half + 5.0, half - 5.0), 3.5, Color(1.0, 0.72, 0.12, 0.95))
		draw_arc(
			Vector2(-half + 5.0, half - 5.0), 3.5, 0.0, TAU, 12, Color(0.0, 0.0, 0.0, 0.85), 1.0
		)
	if not tag.is_empty():
		var font := ThemeDB.fallback_font
		var at := Vector2(-half + 1.0, -half + 8.0)
		var shadow := Color(0.0, 0.0, 0.0, 0.9)
		draw_string_outline(font, at, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, 3, shadow)
		draw_string(font, at, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)


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
