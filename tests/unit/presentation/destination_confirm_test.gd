extends GdUnitTestSuite
## Confirming a destination: an ally's tile opens LOAD / JOIN when legal
## and refuses the stop otherwise; a hidden enemy's tile takes the order
## like open ground (the ambush resolves it) so confirming never reveals
## what fog hides.


func _rig() -> Battle:
	var battle: Battle = auto_free(Battle.assemble())
	add_child(battle)
	battle.event_player.skip_animations = true
	return battle


func _phase(b: Battle) -> BattleController.State:
	return b.controller.phase()


func _menu(b: Battle) -> ActionMenu:
	return b.hud.action_menu


func _choose(b: Battle, label: String) -> void:
	var items := _menu(b).items()
	var idx := items.find(label)
	assert_int(idx).append_failure_message("menu lacks %s in %s" % [label, str(items)]).is_between(
		0, 100
	)
	while _menu(b).selected_index() != idx:
		_menu(b).move_selection(1)
	_menu(b).choose_selected()


func test_load_and_join_via_menu() -> void:
	var b := _rig()
	var gs := BattleFixture.make_econ_state()
	var apc := BattleFixture.spawn(gs, BattleFixture.APC, 0, Vector2i(2, 2))
	var rider := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(1, 2))
	var twin := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	var hurt := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 1))
	hurt.hp = 40
	b.load_state(gs)
	# Onto the APC: the menu offers exactly Load.
	b.cursor.move_to(Vector2i(1, 2))
	b.controller.confirm()
	b.cursor.move_to(Vector2i(2, 2))
	b.controller.confirm()
	assert_that(_phase(b)).is_equal(BattleController.State.ACTION_MENU)
	var load_only: Array[String] = ["Load"]
	assert_array(_menu(b).items()).contains_exactly(load_only)
	_choose(b, "Load")
	assert_int(rider.carrier_id).is_equal(apc.id)
	assert_array(apc.cargo).contains_exactly([rider.id])
	assert_object(b.unit_layer.view_for(rider.id)).is_null()
	# Onto a damaged twin: exactly Join; 100 + 40 internal HP caps at 100.
	b.cursor.move_to(Vector2i(0, 0))
	b.controller.confirm()
	b.cursor.move_to(Vector2i(0, 1))
	b.controller.confirm()
	var join_only: Array[String] = ["Join"]
	assert_array(_menu(b).items()).contains_exactly(join_only)
	_choose(b, "Join")
	assert_bool(b.state.units.has(twin.id)).is_false()
	assert_int(hurt.hp).is_equal(100)


func test_full_health_ally_tile_refuses_the_stop() -> void:
	var b := _rig()
	var gs := BattleFixture.make_state()
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 1))  # full HP: no Join
	b.load_state(gs)
	b.cursor.move_to(Vector2i(0, 0))
	b.controller.confirm()
	b.cursor.move_to(Vector2i(0, 1))
	b.controller.confirm()
	assert_that(_phase(b)).is_equal(BattleController.State.CHOOSING_DESTINATION)


func test_hidden_enemy_destination_takes_the_order() -> void:
	# Refusing to stop on a dark tile would reveal who's there: the order
	# goes through and the ambush resolves it. The tank at (0,3) is
	# beyond the infantry's vision 2; the move halts on (0,2).
	var b := _rig()
	var gs := BattleFixture.make_state()
	gs.config.fog_enabled = true
	var mine := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(0, 3))
	b.load_state(gs)
	b.cursor.move_to(Vector2i(0, 0))
	b.controller.confirm()
	b.cursor.move_to(Vector2i(0, 3))
	b.controller.confirm()
	assert_that(_phase(b)).is_equal(BattleController.State.ACTION_MENU)
	_choose(b, "Wait")
	assert_that(mine.coord).is_equal(Vector2i(0, 2))
	assert_bool(mine.has_acted).is_true()
