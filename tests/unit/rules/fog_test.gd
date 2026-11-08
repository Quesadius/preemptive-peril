extends GdUnitTestSuite
## Fog rules: vision masks, hiding terrain, honest planning queries, and
## the ambush interruption in apply(). Fixture units have vision 2; the
## fixture forest hides units and the mountain grants +3 vision.


func _fogged(gs: GameState) -> GameState:
	gs.config.fog_enabled = true
	return gs


func test_compute_lights_vision_diamond() -> void:
	var gs := _fogged(BattleFixture.make_state())
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(2, 2))
	var mask := Fog.compute(gs, 0)
	var lit: int = 0
	for i: int in range(mask.size()):
		lit += mask[i]
	assert_int(lit).is_equal(13)  # manhattan <= 2 around the center
	assert_int(mask[gs.map.idx(Vector2i(2, 0))]).is_equal(1)
	assert_int(mask[gs.map.idx(Vector2i(0, 0))]).is_equal(0)
	assert_int(mask[gs.map.idx(Vector2i(4, 4))]).is_equal(0)


func test_mountain_bonus_extends_vision() -> void:
	var gs := _fogged(BattleFixture.make_state())
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(2, 0))  # on the mountain
	var mask := Fog.compute(gs, 0)
	var lit: int = 0
	for i: int in range(mask.size()):
		lit += mask[i]
	# Vision 2 + 3 = 5: everything but the two distance-6 corners.
	assert_int(lit).is_equal(23)
	assert_int(mask[gs.map.idx(Vector2i(0, 4))]).is_equal(0)
	assert_int(mask[gs.map.idx(Vector2i(4, 4))]).is_equal(0)


func test_owned_property_lights_its_tile() -> void:
	var gs := _fogged(BattleFixture.make_econ_state())
	BattleFixture.claim(gs, Vector2i(2, 0), 0)
	var mask := Fog.compute(gs, 0)
	var lit: int = 0
	for i: int in range(mask.size()):
		lit += mask[i]
	assert_int(lit).is_equal(1)
	assert_int(mask[gs.map.idx(Vector2i(2, 0))]).is_equal(1)


func test_forest_hides_units_until_adjacent() -> void:
	var gs := _fogged(BattleFixture.make_state())
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(2, 2))
	var lurker := BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(1, 1))  # forest
	var scout := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(2, 0))  # plains
	# The forest tile is lit (distance 2) but the tank stays hidden…
	assert_bool(Fog.tile_visible(gs, 0, Vector2i(1, 1))).is_true()
	assert_bool(Fog.sees_unit(gs, 0, lurker)).is_false()
	# …while the plains unit at the same distance is plainly seen.
	assert_bool(Fog.sees_unit(gs, 0, scout)).is_true()
	# An adjacent friendly flushes the forest out.
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(2, 1))
	assert_bool(Fog.sees_unit(gs, 0, lurker)).is_true()


func test_fog_off_sees_everything() -> void:
	var gs := BattleFixture.make_state()  # fog defaults off
	var lurker := BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(1, 1))
	assert_bool(Fog.sees_unit(gs, 0, lurker)).is_true()
	assert_bool(Fog.tile_visible(gs, 0, Vector2i(4, 4))).is_true()


func test_more_units_see_monotonically_more() -> void:
	var gs := _fogged(BattleFixture.make_state())
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	var before := Fog.compute(gs, 0)
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(4, 4))
	var after := Fog.compute(gs, 0)
	for i: int in range(before.size()):
		if before[i] == 1:
			assert_int(after[i]).append_failure_message("tile %d went dark" % i).is_equal(1)


func test_state_view_is_honest_under_fog() -> void:
	var gs := _fogged(BattleFixture.make_state())
	var viewer := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(1, 1))  # hidden in forest
	var view := StateView.for_team(gs, 0)
	assert_array(view.visible_units()).has_size(1)  # only the viewer
	assert_object(view.unit_at(Vector2i(1, 1))).is_null()
	for a: Action in view.legal_actions():
		if a is UnitAction:
			assert_int((a as UnitAction).verb).is_not_equal(UnitAction.Verb.ATTACK)
	assert_object(view.unit(viewer.id)).is_same(viewer)


func test_invisible_enemy_does_not_block_planning() -> void:
	var gs := BattleFixture.make_state()
	var mover := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(1, 1))  # forest, distance 2
	# Fog off: the enemy blocks and its tile is unreachable.
	assert_bool(Movement.reachable(gs, mover.id).has(Vector2i(1, 1))).is_false()
	# Fog on: the mover doesn't know it's there, so planning passes through.
	gs.config.fog_enabled = true
	assert_bool(Movement.reachable(gs, mover.id).has(Vector2i(1, 1))).is_true()


func test_ambush_stops_move_and_charges_actual_fuel() -> void:
	var gs := _fogged(BattleFixture.make_state())
	var mover := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	var trap := BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(0, 3))  # dark plains
	var walk := UnitAction.new()
	walk.unit_id = mover.id
	walk.path = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3)]
	assert_object(Rules.validate(gs, walk)).is_null()  # the player can't know
	var events := Rules.apply(gs, walk)
	assert_array(events).has_size(3)
	var moved := events[0] as Events.UnitMoved
	assert_int(moved.interrupted_at).is_equal(2)
	var ambush := events[1] as Events.UnitAmbushed
	assert_object(ambush).is_not_null()
	assert_int(ambush.by_unit_id).is_equal(trap.id)
	assert_that(ambush.coord).is_equal(Vector2i(0, 3))
	assert_object(events[2] as Events.UnitExhausted).is_not_null()
	assert_that(mover.coord).is_equal(Vector2i(0, 2))
	assert_int(mover.fuel).is_equal(97)  # two tiles actually entered
	assert_bool(mover.has_acted).is_true()


func test_ambush_cancels_the_ordered_verb() -> void:
	var gs := _fogged(BattleFixture.make_econ_state())
	var ranger := BattleFixture.spawn(gs, BattleFixture.RANGER, 0, Vector2i(0, 2))
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(2, 0))  # squatting the city, dark
	var grab := UnitAction.new()
	grab.unit_id = ranger.id
	grab.path = [Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(2, 1), Vector2i(2, 0)]
	grab.verb = UnitAction.Verb.CAPTURE
	assert_object(Rules.validate(gs, grab)).is_null()
	var events := Rules.apply(gs, grab)
	for e: GameEvent in events:
		assert_bool(e is Events.CaptureProgressed).is_false()  # order cancelled
	assert_that(ranger.coord).is_equal(Vector2i(2, 1))
	assert_bool(gs.map.capture_progress.is_empty()).is_true()
	assert_bool(ranger.has_acted).is_true()


func test_ambush_backtracks_over_occupied_tiles() -> void:
	# Shared team vision means an ally adjacent to the blocker would
	# normally reveal it (and validation would refuse the path) — so this
	# scenario can only exist with blind units. Vision 0 pins the
	# defensive backtrack in the ambush walk.
	var gs := _fogged(BattleFixture.make_state())
	gs.ruleset.unit_types[BattleFixture.INFANTRY].vision = 0
	var mover := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 2))  # ally mid-path
	BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(0, 3))  # unseen blocker
	var walk := UnitAction.new()
	walk.unit_id = mover.id
	walk.path = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3)]
	assert_object(Rules.validate(gs, walk)).is_null()
	Rules.apply(gs, walk)
	# The tile before the blocker holds the ally, so the mover falls back
	# one more.
	assert_that(mover.coord).is_equal(Vector2i(0, 1))
	assert_int(mover.fuel).is_equal(98)


func test_mask_for_follows_the_fog_setting() -> void:
	var gs := BattleFixture.make_state()
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(2, 2))
	assert_bool(Fog.mask_for(gs, 0).is_empty()).is_true()  # fog off: no mask needed
	gs.config.fog_enabled = true
	assert_bool(Fog.mask_for(gs, 0) == Fog.compute(gs, 0)).is_true()


func test_sees_at_lit_tiles_hiding_terrain_and_bounds() -> void:
	var gs := _fogged(BattleFixture.make_state())
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(2, 2))  # vision 2
	assert_bool(Fog.sees_at(gs, 0, Vector2i(2, 0))).is_true()  # lit mountain
	assert_bool(Fog.sees_at(gs, 0, Vector2i(4, 4))).is_false()  # distance 4: dark
	# The forest at (1,1) is lit (distance 2) but hides without a neighbor.
	assert_bool(Fog.sees_at(gs, 0, Vector2i(1, 1))).is_false()
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(1, 2))  # now adjacent
	assert_bool(Fog.sees_at(gs, 0, Vector2i(1, 1))).is_true()
	assert_bool(Fog.sees_at(gs, 0, Vector2i(-1, 0))).is_false()
	assert_bool(Fog.sees_at(gs, 0, Vector2i(5, 5))).is_false()
	gs.config.fog_enabled = false
	assert_bool(Fog.sees_at(gs, 0, Vector2i(4, 4))).is_true()


func test_precomputed_mask_gives_the_same_answers() -> void:
	var gs := _fogged(BattleFixture.make_state())
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(2, 2))
	var lit := BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(2, 0))
	var dark := BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(4, 4))
	var hidden := BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(1, 1))  # forest
	var mask := Fog.mask_for(gs, 0)
	var expected: Array[bool] = [true, false, false]
	var foes: Array[UnitState] = [lit, dark, hidden]
	for i: int in range(foes.size()):
		var foe := foes[i]
		assert_bool(Fog.sees_unit(gs, 0, foe)).is_equal(expected[i])
		assert_bool(Fog.sees_unit(gs, 0, foe, mask)).is_equal(expected[i])
		var known := Fog.known_occupant(gs, 0, foe.coord, mask)
		assert_bool(known == foe).is_equal(expected[i])
