extends GdUnitTestSuite
## The shipped Tiny Battle ArtSet and ArtSet's lookups. Expected tiles are
## (column, row) on Kenney's 18x11 packed sheet, read off the sheet by
## hand: buildings in rows 0-4 and units in rows 5-9 run grey, green,
## blue, red, orange; roads fill columns 0-3 of rows 6-9; HP digits are
## row 10. Columns 18-19 are the two sprites tools/art adds: Medium Tank
## and Rockets.


func _art() -> ArtSet:
	var art := Battle.default_art()
	assert_object(art).is_not_null()
	return art


func test_covers_the_classic_roster_and_terrain() -> void:
	var art := _art()
	assert_that(art.sheet.get_size()).is_equal(Vector2(320, 176))  # 20x11 tiles of 16px
	assert_float(art.draw_scale()).is_equal_approx(2.0, 0.0001)
	var rs := load("res://data/rulesets/classic.tres") as Ruleset
	for unit_type: UnitType in rs.unit_types:
		for team: int in [0, 1]:
			var tile := art.unit_tile(unit_type.key, team)
			assert_that(tile).append_failure_message(String(unit_type.key)).is_not_equal(
				ArtSet.NONE
			)
	for terrain: TerrainType in rs.terrain_types:
		(
			assert_bool(art.draws_on_ground(terrain.key))
			. append_failure_message(String(terrain.key))
			. is_true()
		)


func test_units_take_their_team_row() -> void:
	var art := _art()
	assert_that(art.unit_tile(&"tank", 0)).is_equal(Vector2i(8, 8))  # red
	assert_that(art.unit_tile(&"tank", 1)).is_equal(Vector2i(8, 7))  # blue
	assert_that(art.unit_tile(&"infantry", 0)).is_equal(Vector2i(16, 8))
	assert_that(art.unit_tile(&"copter", 0)).is_equal(Vector2i(11, 8))
	assert_that(art.unit_tile(&"bomber", 1)).is_equal(Vector2i(10, 7))
	# Medium tanks and rockets have sprites of their own in the added
	# columns, so nothing in the shipped set needs a tag.
	assert_that(art.unit_tile(&"md_tank", 0)).is_equal(Vector2i(18, 8))
	assert_that(art.unit_tile(&"rockets", 1)).is_equal(Vector2i(19, 7))
	assert_bool(art.unit_tags.is_empty()).is_true()
	assert_that(art.unit_tile(&"battleship", 0)).is_equal(ArtSet.NONE)  # unmapped
	assert_that(art.unit_tile(&"tank", 9)).is_equal(ArtSet.NONE)  # no such team row
	assert_array(art.left_facing_teams).contains_exactly([1])


func test_added_sprites_are_drawn_from_the_packs_own_pixels() -> void:
	# The twin cannon: the Medium Tank keeps the tank's turret (base red
	# at (5,5)) and gains an upper barrel where the tank has only outline.
	var img := _art().sheet.get_image()
	img.convert(Image.FORMAT_RGBA8)
	var outline := Color("3f2631")
	var steel_light := Color("c0cbdc")
	assert_that(img.get_pixel(8 * 16 + 11, 8 * 16 + 3)).is_equal(outline)  # tank
	assert_that(img.get_pixel(18 * 16 + 11, 8 * 16 + 3)).is_equal(steel_light)  # md tank
	assert_that(img.get_pixel(18 * 16 + 11, 8 * 16 + 6)).is_equal(steel_light)  # lower barrel
	assert_that(img.get_pixel(18 * 16 + 5, 8 * 16 + 5)).is_equal(
		img.get_pixel(8 * 16 + 5, 8 * 16 + 5)
	)
	# The launcher: a white rocket nose over its dark bore, in every color.
	for row: int in range(5, 10):
		assert_that(img.get_pixel(19 * 16 + 3, row * 16 + 4)).is_equal(Color("eef8fe"))
		assert_that(img.get_pixel(19 * 16 + 3, row * 16 + 5)).is_equal(Color("52607c"))
	# Blue's chassis strip under the launcher is blue's own dark shade.
	assert_that(img.get_pixel(19 * 16 + 4, 7 * 16 + 10)).is_equal(Color("0077c5"))


func test_buildings_take_their_owners_color() -> void:
	var art := _art()
	assert_that(art.detail_tile(&"city", MapState.NO_OWNER, 0)).is_equal(Vector2i(8, 0))
	assert_that(art.detail_tile(&"city", 0, 0)).is_equal(Vector2i(8, 3))  # red
	assert_that(art.detail_tile(&"city", 1, 0)).is_equal(Vector2i(8, 2))  # blue
	assert_that(art.detail_tile(&"factory", 0, 0)).is_equal(Vector2i(11, 3))
	# The HQ is the spired building (column 14); the airport is the control
	# tower over a runway to its right (column 15).
	assert_that(art.detail_tile(&"hq", 1, 0)).is_equal(Vector2i(14, 2))
	assert_that(art.detail_tile(&"hq", 0, 0)).is_equal(Vector2i(14, 3))
	assert_that(art.detail_tile(&"airport", 0, 0)).is_equal(Vector2i(15, 3))
	assert_that(art.detail_tile(&"airport", MapState.NO_OWNER, 0)).is_equal(Vector2i(15, 0))
	# A team without a color row shows the neutral building.
	assert_that(art.detail_tile(&"city", 7, 0)).is_equal(Vector2i(8, 0))
	# Terrain that stands on the ground, and bare ground.
	assert_that(art.detail_tile(&"forest", MapState.NO_OWNER, 0)).is_equal(Vector2i(4, 6))
	assert_that(art.detail_tile(&"mountain", MapState.NO_OWNER, 0)).is_equal(Vector2i(5, 0))
	assert_that(art.detail_tile(&"plains", MapState.NO_OWNER, 0)).is_equal(ArtSet.NONE)


func test_road_shapes_by_neighbor_mask() -> void:
	var art := _art()
	var n := ArtSet.N
	var e := ArtSet.E
	var s := ArtSet.S
	var w := ArtSet.W
	assert_that(art.detail_tile(&"road", -1, 0)).is_equal(Vector2i(0, 6))  # isolated
	assert_that(art.detail_tile(&"road", -1, n | s)).is_equal(Vector2i(0, 8))  # vertical
	assert_that(art.detail_tile(&"road", -1, e | w)).is_equal(Vector2i(2, 6))  # horizontal
	assert_that(art.detail_tile(&"road", -1, e | s)).is_equal(Vector2i(1, 7))  # corner
	assert_that(art.detail_tile(&"road", -1, n | s | w)).is_equal(Vector2i(3, 8))  # T
	assert_that(art.detail_tile(&"road", -1, n | e | s | w)).is_equal(Vector2i(2, 8))  # crossing
	assert_that(art.detail_tile(&"road", -1, s)).is_equal(Vector2i(0, 7))  # top cap
	# Every one of the 16 shapes is its own tile.
	var seen: Dictionary[Vector2i, bool] = {}
	for mask: int in range(16):
		seen[art.detail_tile(&"road", -1, mask)] = true
	assert_int(seen.size()).is_equal(16)


func test_ground_variants_are_stable_and_varied() -> void:
	var art := _art()
	var used: Dictionary[Vector2i, bool] = {}
	for y: int in range(10):
		for x: int in range(12):
			var c := Vector2i(x, y)
			var tile := art.ground_tile(c)
			assert_that(art.ground_tile(c)).is_equal(tile)  # same coord, same tile
			assert_bool(art.ground_tiles.has(tile)).is_true()
			used[tile] = true
	assert_int(used.size()).is_equal(3)  # plain, tufted and flowered grass all appear


func test_hp_badges_and_cursor() -> void:
	var art := _art()
	assert_that(art.digit_tile(6)).is_equal(Vector2i(6, 10))
	assert_that(art.digit_tile(10)).is_equal(ArtSet.NONE)  # full health shows no badge
	assert_that(art.cursor_tile).is_equal(Vector2i(7, 3))
	assert_that(art.region(Vector2i(7, 3))).is_equal(Rect2(112, 48, 16, 16))


func test_arrow_pieces_follow_the_path() -> void:
	var art := _art()
	# East, east, turn south, turn east: shafts, two corners, a head.
	var path: Array[Vector2i] = [
		Vector2i(2, 3),
		Vector2i(3, 3),
		Vector2i(4, 3),
		Vector2i(4, 4),
		Vector2i(5, 4),
	]
	var expected: Array[Vector2i] = [
		Vector2i(6, 2),  # horizontal shaft through the unit's tile
		Vector2i(6, 2),  # horizontal shaft
		Vector2i(6, 3),  # corner joining west and south
		Vector2i(5, 4),  # corner joining north and east
		Vector2i(7, 2),  # head pointing east
	]
	for i: int in range(path.size()):
		assert_that(art.arrow_piece(path, i)).append_failure_message("step %d" % i).is_equal(
			expected[i]
		)
	var north: Array[Vector2i] = [Vector2i(0, 2), Vector2i(0, 1), Vector2i(0, 0)]
	assert_that(art.arrow_piece(north, 0)).is_equal(Vector2i(4, 3))  # vertical shaft
	assert_that(art.arrow_piece(north, 2)).is_equal(Vector2i(4, 2))  # head pointing north
	var standing: Array[Vector2i] = [Vector2i(0, 0)]
	assert_that(art.arrow_piece(standing, 0)).is_equal(ArtSet.NONE)
