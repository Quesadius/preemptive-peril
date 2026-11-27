extends GdUnitTestSuite
## The battle view drawing with the Tiny Battle ArtSet, on a hand-painted
## 5x5 board (BattleFixture's main map plus a few painted tiles):
##   y0:  P  F  M  P  P
##   y1:  P  F  P  P  P
##   y2:  Fa HQ C  S  S     factory neutral, HQ blue, city red
##   y3:  P  P  R  S  S     a road spur north off the bottom road
##   y4:  R  R  R  R  R


func _rig() -> Battle:
	var battle: Battle = auto_free(Battle.assemble(Battle.default_art()))
	add_child(battle)
	battle.event_player.skip_animations = true
	return battle


func _painted() -> GameState:
	var gs := BattleFixture.make_state()
	var paint: Dictionary[Vector2i, int] = {
		Vector2i(0, 2): BattleFixture.FACTORY,
		Vector2i(1, 2): BattleFixture.HQ,
		Vector2i(2, 2): BattleFixture.CITY,
		Vector2i(2, 3): BattleFixture.ROAD,
	}
	for c: Vector2i in paint:
		gs.map.terrain[gs.map.idx(c)] = paint[c]
	BattleFixture.claim(gs, Vector2i(1, 2), 1)
	BattleFixture.claim(gs, Vector2i(2, 2), 0)
	return gs


func test_ground_details_and_fallback() -> void:
	var b := _rig()
	b.load_state(_painted())
	var renderer := b.map_renderer
	var ground := renderer.terrain_layer
	var detail := renderer.detail_layer
	var art := renderer.art_set
	assert_that(ground.scale).is_equal(Vector2(0.5, 0.5))  # 64px HD art in 32px tiles
	assert_that(detail.scale).is_equal(Vector2(0.5, 0.5))
	# Plains: grass from the sheet, nothing on top.
	assert_int(ground.get_cell_source_id(Vector2i(0, 0))).is_equal(MapRenderer.ART_SOURCE)
	assert_bool(art.ground_tiles.has(ground.get_cell_atlas_coords(Vector2i(0, 0)))).is_true()
	assert_int(detail.get_cell_source_id(Vector2i(0, 0))).is_equal(-1)
	# Trees and the hill stand on grass.
	assert_that(detail.get_cell_atlas_coords(Vector2i(1, 0))).is_equal(Vector2i(4, 6))
	assert_that(detail.get_cell_atlas_coords(Vector2i(2, 0))).is_equal(Vector2i(5, 0))
	# Buildings in their owners' colors: neutral factory, blue HQ, red city.
	assert_that(detail.get_cell_atlas_coords(Vector2i(0, 2))).is_equal(Vector2i(11, 0))
	assert_that(detail.get_cell_atlas_coords(Vector2i(1, 2))).is_equal(Vector2i(10, 2))
	assert_that(detail.get_cell_atlas_coords(Vector2i(2, 2))).is_equal(Vector2i(8, 3))
	# Ownership shows on the buildings, so the tint layer stays empty.
	assert_array(renderer.property_layer.get_used_cells()).is_empty()
	# Sea auto-tiles its shoreline edges: (3,2) has land N+W -> NW corner (0,1),
	# and (4,2) has land N only (off-board E counts as sea) -> N edge (1,1).
	assert_int(ground.get_cell_source_id(Vector2i(3, 2))).is_equal(MapRenderer.ART_SOURCE)
	assert_that(ground.get_cell_atlas_coords(Vector2i(3, 2))).is_equal(Vector2i(0, 1))
	assert_that(ground.get_cell_atlas_coords(Vector2i(4, 2))).is_equal(Vector2i(1, 1))
	assert_int(detail.get_cell_source_id(Vector2i(3, 2))).is_equal(-1)


func test_roads_join_their_neighbors() -> void:
	var b := _rig()
	b.load_state(_painted())
	var renderer := b.map_renderer
	var detail := renderer.detail_layer
	# (0,4): only east is road, so the road dead-ends facing west and runs
	# off that edge; south is off-board too, but nothing leads there.
	assert_int(renderer.road_mask(b.state, Vector2i(0, 4))).is_equal(ArtSet.E | ArtSet.W)
	assert_that(detail.get_cell_atlas_coords(Vector2i(0, 4))).is_equal(Vector2i(2, 6))
	# (2,4): the spur joins from the north — a T opening north, east, west.
	var tee: int = ArtSet.N | ArtSet.E | ArtSet.W
	assert_int(renderer.road_mask(b.state, Vector2i(2, 4))).is_equal(tee)
	assert_that(detail.get_cell_atlas_coords(Vector2i(2, 4))).is_equal(Vector2i(2, 9))
	# (2,3): the spur's end, capped at the top (the city isn't road).
	assert_int(renderer.road_mask(b.state, Vector2i(2, 3))).is_equal(ArtSet.S)
	assert_that(detail.get_cell_atlas_coords(Vector2i(2, 3))).is_equal(Vector2i(0, 7))


func test_units_wear_team_sprites_and_unmapped_types_keep_placeholders() -> void:
	var b := _rig()
	var gs := BattleFixture.make_state()
	var red := BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(0, 0))
	var blue := BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(4, 0))
	var heli := BattleFixture.spawn(gs, BattleFixture.HELI, 0, Vector2i(0, 1))
	b.load_state(gs)
	var red_view := b.unit_layer.view_for(red.id)
	assert_that(red_view.art_tile).is_equal(Vector2i(8, 8))
	assert_bool(red_view.art_flipped()).is_false()
	assert_that(red_view.tag).is_equal("")
	var blue_view := b.unit_layer.view_for(blue.id)
	assert_that(blue_view.art_tile).is_equal(Vector2i(8, 7))
	assert_bool(blue_view.art_flipped()).is_true()  # blue faces its enemy
	# The set has no helicopter mapping: placeholder body and glyph.
	var heli_view := b.unit_layer.view_for(heli.id)
	assert_that(heli_view.art_tile).is_equal(ArtSet.NONE)
	assert_that(heli_view.type_label).is_equal("HE")


func test_borrowed_sprites_carry_their_tag() -> void:
	# A hand-built set that lends the tank sprite to the ranger.
	var art := ArtSet.new()
	art.sheet = Battle.default_art().sheet
	art.unit_columns[&"ranger"] = 8
	art.team_unit_rows.assign([8, 7])
	art.unit_tags[&"ranger"] = "RG"
	var battle: Battle = auto_free(Battle.assemble(art))
	add_child(battle)
	var gs := BattleFixture.make_state()
	var ranger := BattleFixture.spawn(gs, BattleFixture.RANGER, 0, Vector2i(0, 0))
	battle.load_state(gs)
	var view := battle.unit_layer.view_for(ranger.id)
	assert_that(view.art_tile).is_equal(Vector2i(8, 8))
	assert_that(view.tag).is_equal("RG")


func test_coastal_port_sits_on_water_edge_and_under_bridge_uses_arch_water() -> void:
	var b := _rig()
	var def := MapCatalog.find(&"archipelago")
	b.load_map(def)
	var renderer := b.map_renderer
	var ground := renderer.terrain_layer
	var detail := renderer.detail_layer
	# Team 0 Port at (8,2) sits on the north shoreline of the sea: water edge
	# (1,1) on terrain_layer underneath the red port crane (12,3) on detail_layer.
	assert_that(ground.get_cell_atlas_coords(Vector2i(8, 2))).is_equal(Vector2i(1, 1))
	assert_that(detail.get_cell_atlas_coords(Vector2i(8, 2))).is_equal(Vector2i(12, 3))
	# Team 1 Port at (5,7) sits on the south shoreline (1,3) with blue crane (12,2).
	assert_that(ground.get_cell_atlas_coords(Vector2i(5, 7))).is_equal(Vector2i(1, 3))
	assert_that(detail.get_cell_atlas_coords(Vector2i(5, 7))).is_equal(Vector2i(12, 2))
	# Under-bridge tile (4,8) triggers for open water directly south of a horizontal bridge.
	assert_that(renderer.art_set.base_tile_for(&"sea", Vector2i(5, 5), 15, 0, true)).is_equal(
		Vector2i(4, 8)
	)
	# Inner corner (0,4) triggers for open water with land on NE diagonal only.
	assert_that(renderer.art_set.base_tile_for(&"sea", Vector2i(5, 5), 15, 1, false)).is_equal(
		Vector2i(0, 4)
	)
