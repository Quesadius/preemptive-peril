extends GdUnitTestSuite
## Headless checks of the first-render milestone: the assembled battle
## tree presents the demo state correctly — tile cells, overlay tints,
## unit views, cursor clamps, camera limits. Pixels need eyes, cell data
## and node state do not.


func _battle() -> Battle:
	var battle: Battle = auto_free(Battle.assemble())
	add_child(battle)
	return battle


func test_terrain_layer_matches_map() -> void:
	var b := _battle()
	assert_object(b.state).is_not_null()
	assert_int(b.state.map.width).is_equal(10)
	assert_int(b.state.map.height).is_equal(8)
	var layer := b.map_renderer.terrain_layer
	assert_int(layer.get_used_cells().size()).is_equal(80)
	# Spot checks against the DEMO_TERRAIN layout, atlas x = terrain id.
	assert_that(layer.get_cell_atlas_coords(Vector2i(0, 0))).is_equal(Vector2i(0, 0))  # plains
	assert_that(layer.get_cell_atlas_coords(Vector2i(3, 3))).is_equal(Vector2i(1, 0))  # road
	assert_that(layer.get_cell_atlas_coords(Vector2i(4, 1))).is_equal(Vector2i(3, 0))  # mountain
	assert_that(layer.get_cell_atlas_coords(Vector2i(1, 1))).is_equal(Vector2i(4, 0))  # city
	assert_that(layer.get_cell_atlas_coords(Vector2i(1, 2))).is_equal(Vector2i(5, 0))  # factory


func test_property_overlay_tints_owned_only() -> void:
	var b := _battle()
	var overlay := b.map_renderer.property_layer
	var owned := overlay.get_used_cells()
	assert_array(owned).has_size(4)
	assert_array(owned).contains([Vector2i(1, 1), Vector2i(1, 2), Vector2i(8, 1), Vector2i(8, 2)])
	# Atlas x = terrain count (7, HQ included) + owning team.
	assert_that(overlay.get_cell_atlas_coords(Vector2i(1, 1))).is_equal(Vector2i(7, 0))
	assert_that(overlay.get_cell_atlas_coords(Vector2i(8, 1))).is_equal(Vector2i(8, 0))
	# The neutral city carries no tint.
	assert_int(overlay.get_cell_source_id(Vector2i(1, 5))).is_equal(-1)


func test_unit_views_match_units() -> void:
	var b := _battle()
	assert_int(b.state.units.size()).is_equal(8)
	assert_int(b.unit_layer.get_child_count()).is_equal(8)
	for uid: int in b.state.units:
		var unit: UnitState = b.state.units[uid]
		var view := b.unit_layer.view_for(uid)
		assert_object(view).append_failure_message("no view for unit %d" % uid).is_not_null()
		assert_that(view.position).is_equal(MapRenderer.world_pos(unit.coord))
		assert_int(view.team).is_equal(unit.team)
		assert_int(view.display_hp).is_equal(unit.display_hp())
		assert_bool(view.exhausted).is_equal(unit.has_acted)
	# The demo's damaged infantry shows a pip value of 6; the exhausted
	# mech is tinted grey.
	var hurt := b.unit_layer.view_for(5)
	assert_int(hurt.display_hp).is_equal(6)
	var tired := b.unit_layer.view_for(2)
	assert_bool(tired.exhausted).is_true()
	assert_bool(tired.modulate.is_equal_approx(Color(0.6, 0.6, 0.6))).is_true()
	# Placeholder identity cues: glyph from the display name, silhouette
	# from the movement class (demo ids: 1 md tank, 2 mech, 5 infantry).
	assert_that(b.unit_layer.view_for(1).type_label).is_equal("MD")
	assert_that(b.unit_layer.view_for(1).body_shape).is_equal(UnitView.BodyShape.RECT)
	assert_that(b.unit_layer.view_for(2).type_label).is_equal("ME")
	assert_that(b.unit_layer.view_for(2).body_shape).is_equal(UnitView.BodyShape.CIRCLE)
	assert_that(b.unit_layer.view_for(5).type_label).is_equal("IN")
	# Every glyph on the board is unique per type, or the cue is useless.
	var glyphs: Dictionary[String, int] = {}
	for uid: int in b.state.units:
		var seen := b.unit_layer.view_for(uid)
		glyphs[seen.type_label] = glyphs.get(seen.type_label, 0) + 1
	assert_int(glyphs.size()).is_equal(5)  # five distinct demo types


func test_sync_pools_and_prunes() -> void:
	var b := _battle()
	var moved: UnitState = b.state.units[1]
	var before := b.unit_layer.view_for(1)
	# Move one unit and delete another, then re-sync.
	b.state.occupancy.erase(moved.coord)
	moved.coord = Vector2i(4, 6)
	b.state.occupancy[moved.coord] = moved.id
	var gone: UnitState = b.state.units[8]
	b.state.occupancy.erase(gone.coord)
	b.state.units.erase(gone.id)
	b.unit_layer.sync(b.state)
	var after := b.unit_layer.view_for(1)
	assert_object(after).is_same(before)  # pooled, not recreated
	assert_that(after.position).is_equal(MapRenderer.world_pos(Vector2i(4, 6)))
	assert_object(b.unit_layer.view_for(8)).is_null()
	assert_int(b.unit_layer.get_child_count()).is_equal(7)


func test_cursor_clamps_and_signals() -> void:
	var b := _battle()
	assert_that(b.cursor.coord).is_equal(Vector2i(5, 4))  # centered by present()
	var emissions: Array[Vector2i] = []
	b.cursor.moved.connect(func(c: Vector2i) -> void: emissions.append(c))
	b.cursor.move_to(Vector2i(50, 50))
	assert_that(b.cursor.coord).is_equal(Vector2i(9, 7))
	assert_that(b.cursor.position).is_equal(MapRenderer.world_pos(Vector2i(9, 7)))
	b.cursor.move_to(Vector2i(9, 7))  # no change, no signal
	assert_array(emissions).has_size(1)
	b.cursor.move_to(Vector2i(-3, 2))
	assert_that(b.cursor.coord).is_equal(Vector2i(0, 2))
	assert_array(emissions).has_size(2)


func test_camera_fits_and_centers_the_demo_map() -> void:
	var b := _battle()
	var cam := b.camera_rig.camera
	# The expectations below assume the configured 1280x720 viewport.
	assert_that(get_viewport().get_visible_rect().size).is_equal(Vector2(1280, 720))
	# Fit: min(1280/320, 720/256) = 2.8125, snapped down to 2.5 — the
	# whole 320x256 demo map is on screen.
	assert_that(cam.zoom).is_equal(Vector2(2.5, 2.5))
	# View (512x288) exceeds the map on both axes, so the limits center
	# it instead of pinning to a corner.
	assert_int(cam.limit_left).is_equal(-96)
	assert_int(cam.limit_right).is_equal(416)
	assert_int(cam.limit_top).is_equal(-16)
	assert_int(cam.limit_bottom).is_equal(272)
	assert_that(cam.position).is_equal(MapRenderer.world_pos(Vector2i(5, 4)))


func test_zoom_controls_step_and_clamp() -> void:
	var b := _battle()
	var rig := b.camera_rig
	assert_float(rig.zoom_level).is_equal_approx(2.5, 0.001)  # fitted at load
	rig.zoom_in()
	assert_float(rig.zoom_level).is_equal_approx(3.0, 0.001)
	assert_that(rig.camera.zoom).is_equal(Vector2(3, 3))
	rig.set_zoom(99.0)
	assert_float(rig.zoom_level).is_equal_approx(rig.zoom_max, 0.001)
	rig.set_zoom(0.0)
	assert_float(rig.zoom_level).is_equal_approx(rig.zoom_min, 0.001)
	assert_that(rig.camera.zoom).is_equal(Vector2(rig.zoom_min, rig.zoom_min))


func test_load_map_before_ready_is_not_clobbered() -> void:
	# The -s boot calls load_map from SceneTree._initialize, BEFORE any
	# _ready has fired: load_map must self-load the ruleset, and _ready's
	# demo must yield to the already-loaded match.
	var battle: Battle = auto_free(Battle.assemble())
	var def := load("res://data/maps/crossroads.tres") as MapDefinition
	battle.load_map(def)  # not in the tree yet, ruleset not yet loaded
	assert_object(battle.state).is_not_null()
	add_child(battle)  # _ready fires now
	assert_int(battle.state.map.width).is_equal(12)  # still Crossroads
	assert_int(battle.state.units.size()).is_equal(6)
	assert_int(battle.state.players[1].co_id).is_equal(1)  # Rook, not demo
