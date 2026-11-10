extends SceneTree
## Builds assets/tiny_battle/tilemap_extended.png from Kenney's pristine
## tilemap_packed.png: the same 18x11 sheet plus two columns of unit
## sprites the pack lacks, drawn from its own pixels in all five colors
## (rows 5-9: grey, green, blue, red, orange).
##   column 18  Medium Tank — the tank (column 8) with a second cannon
##   column 19  Rockets — the covered truck (column 6) with its canvas
##              replaced by a launcher box of six rocket tubes
## Run after editing:  godot --headless --path . -s tools/art/extend_tiny_battle.gd

const SOURCE := "res://assets/tiny_battle/tilemap_packed.png"
const TARGET := "res://assets/tiny_battle/tilemap_extended.png"
const TILE := 16
const FIRST_UNIT_ROW := 5
const LAST_UNIT_ROW := 9
const TANK_COLUMN := 8
const TRUCK_COLUMN := 6
const MD_TANK_COLUMN := 18
const ROCKETS_COLUMN := 19

## The pack's outline and metal colors, identical for every team.
const OUTLINE := Color("3f2631")
const STEEL := Color("8b9bb4")
const STEEL_LIGHT := Color("c0cbdc")
const STEEL_DARK := Color("52607c")
const WHITE := Color("eef8fe")

## Medium Tank: rows 1-7 of the tank's right side, redrawn as two stacked
## cannons. One string per row, covering columns 10-15; '.' keeps the
## tank's own pixel. o outline, s steel, l light steel, d dark steel.
const TWIN_CANNON: Array[String] = [
	".oooo.",
	"oooooo",
	"slllOO",
	"dsssoo",
	"oooooo",
	"slllOO",
	"dsssoo",
]
const TWIN_CANNON_TOP := 1
const TWIN_CANNON_LEFT := 10

## Rockets: the truck's canvas (columns 2-7, rows 3-10) becomes a launcher
## box: two rows of three tubes, each a white nose over its dark bore, on
## a light rail. w white, T the team's dark shade (the chassis).
const LAUNCHER: Array[String] = [
	"ssssss",
	"swswsw",
	"sdsdsd",
	"ssssss",
	"swswsw",
	"sdsdsd",
	"llllll",
	"TTTTTT",
]
const LAUNCHER_TOP := 3
const LAUNCHER_LEFT := 2
## A pixel of the covered truck holding the team's dark shade.
const TEAM_DARK_AT := Vector2i(2, 11)


func _initialize() -> void:
	var source := Image.load_from_file(ProjectSettings.globalize_path(SOURCE))
	source.convert(Image.FORMAT_RGBA8)
	var sheet := Image.create_empty(
		source.get_width() + 2 * TILE, source.get_height(), false, Image.FORMAT_RGBA8
	)
	sheet.blit_rect(source, Rect2i(Vector2i.ZERO, source.get_size()), Vector2i.ZERO)
	for row: int in range(FIRST_UNIT_ROW, LAST_UNIT_ROW + 1):
		_copy_tile(source, sheet, TANK_COLUMN, MD_TANK_COLUMN, row)
		_stamp(sheet, MD_TANK_COLUMN, row, TWIN_CANNON, TWIN_CANNON_LEFT, TWIN_CANNON_TOP, OUTLINE)
		_copy_tile(source, sheet, TRUCK_COLUMN, ROCKETS_COLUMN, row)
		var team_dark := source.get_pixel(
			TRUCK_COLUMN * TILE + TEAM_DARK_AT.x, row * TILE + TEAM_DARK_AT.y
		)
		_stamp(sheet, ROCKETS_COLUMN, row, LAUNCHER, LAUNCHER_LEFT, LAUNCHER_TOP, team_dark)
	var err := sheet.save_png(ProjectSettings.globalize_path(TARGET))
	print("wrote %s (%dx%d): %s" % [TARGET, sheet.get_width(), sheet.get_height(), error_string(err)])
	quit()


func _copy_tile(source: Image, sheet: Image, from_column: int, to_column: int, row: int) -> void:
	var region := Rect2i(from_column * TILE, row * TILE, TILE, TILE)
	sheet.blit_rect(source, region, Vector2i(to_column * TILE, row * TILE))


func _stamp(
	sheet: Image, column: int, row: int, art: Array[String], left: int, top: int, team_dark: Color
) -> void:
	for y: int in range(art.size()):
		for x: int in range(art[y].length()):
			var color := _ink(art[y][x], team_dark)
			if color.a > 0.0:
				sheet.set_pixel(column * TILE + left + x, row * TILE + top + y, color)


## The color a stamp character paints; transparent means "leave as is".
func _ink(symbol: String, team_dark: Color) -> Color:
	match symbol:
		"o", "O":
			return OUTLINE
		"s":
			return STEEL
		"l":
			return STEEL_LIGHT
		"d":
			return STEEL_DARK
		"w":
			return WHITE
		"T":
			return team_dark
	return Color(0, 0, 0, 0)
