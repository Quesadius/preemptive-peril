extends GdUnitTestSuite
## SimpleAI behavior pins and the §12 golden match. The targeted tests
## pin individual decisions on crafted states; the golden match plays a
## fixed AI-vs-AI battle to the end and pins the whole action log. When
## the AI changes on purpose, re-pin GOLDEN_LOG_MD5 from the failure
## message, which prints the fresh log.

const GOLDEN_LOG_MD5 := "626f75ff79f276c2b2053644a13554d3"
const GOLDEN_MAX_PLIES := 200


func _act_key(a: Action) -> String:
	if a is EndTurnAction:
		return "end"
	if a is PowerAction:
		return "power:%d" % (a as PowerAction).power_level
	if a is BuildAction:
		var b := a as BuildAction
		return "build:%d:%s" % [b.unit_type_id, str(b.coord)]
	var ua := a as UnitAction
	var dest: Vector2i = ua.path[ua.path.size() - 1]
	return "u%d:%d:%s:%s" % [ua.unit_id, ua.verb, str(dest), str(ua.target_coord)]


func test_prefers_kill_over_poke() -> void:
	# A killable straggler beats a meatier target that survives and pays
	# nothing back.
	var gs := BattleFixture.make_state()
	BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(1, 2))
	var weak := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(1, 1))
	weak.hp = 20
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(2, 2))
	var ai := SimpleAI.new()
	var action := ai.choose_action(StateView.for_team(gs, 0)) as UnitAction
	assert_object(action).is_not_null()
	assert_int(action.verb).is_equal(UnitAction.Verb.ATTACK)
	assert_that(action.target_coord).is_equal(Vector2i(1, 1))


func test_prefers_finishing_capture_over_fighting() -> void:
	var gs := BattleFixture.make_econ_state()
	var inf := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(2, 0))
	gs.map.capture_progress[Vector2i(2, 0)] = 10
	BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(2, 1))
	var ai := SimpleAI.new()
	var action := ai.choose_action(StateView.for_team(gs, 0)) as UnitAction
	assert_object(action).is_not_null()
	assert_int(action.unit_id).is_equal(inf.id)
	assert_int(action.verb).is_equal(UnitAction.Verb.CAPTURE)


func test_builds_when_rich_preferring_big_units() -> void:
	# With its two capturers already in the army (spent for this turn)
	# and no enemy in sight, the priciest unit that can fight wins: the
	# tank (7000). The dearer heli (9000) and the APC are unarmed, and the
	# AI doesn't buy what can neither fight nor capture.
	var gs := BattleFixture.make_econ_state()
	BattleFixture.claim(gs, Vector2i(1, 1), 0)
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(4, 2)).has_acted = true
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(4, 1)).has_acted = true
	gs.players[0].funds = 16000
	var ai := SimpleAI.new()
	var action := ai.choose_action(StateView.for_team(gs, 0)) as BuildAction
	assert_object(action).is_not_null()
	assert_int(action.unit_type_id).is_equal(BattleFixture.TANK)


func test_advances_toward_objective_when_idle() -> void:
	# Lone infantry, nothing in range: it should march on the neutral
	# enemy rather than end the turn. The main map has no properties, so
	# marching on the distant foe is the only worthwhile move.
	var gs := BattleFixture.make_state()
	var inf := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	var foe := BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(4, 4))
	var ai := SimpleAI.new()
	var action := ai.choose_action(StateView.for_team(gs, 0)) as UnitAction
	assert_object(action).is_not_null()
	assert_int(action.verb).is_equal(UnitAction.Verb.WAIT)
	var dest: Vector2i = action.path[action.path.size() - 1]
	var before: int = Grid.manhattan(inf.coord, foe.coord)
	assert_bool(Grid.manhattan(dest, foe.coord) < before).is_true()


func test_golden_match_is_deterministic_and_ends() -> void:
	var first := _play_match()
	var second := _play_match()
	assert_array(second).contains_exactly(first)
	assert_that(first[first.size() - 1]).is_equal("GAME_ENDED")
	var joined := "|".join(first)
	(
		assert_that(joined.md5_text())
		. append_failure_message("golden log drifted; new log:\n%s" % joined)
		. is_equal(GOLDEN_LOG_MD5)
	)


func _golden_state() -> GameState:
	var gs := BattleFixture.make_state()
	BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(1, 2))
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(2, 2))
	BattleFixture.spawn(gs, BattleFixture.ARTILLERY, 1, Vector2i(3, 1))
	return gs


func _play_match() -> Array[String]:
	var gs := _golden_state()
	var ai := SimpleAI.new()
	var log: Array[String] = []
	for _ply: int in range(GOLDEN_MAX_PLIES):
		var view := StateView.for_team(gs, gs.active_player().team)
		var action := ai.choose_action(view)
		(
			assert_object(view.validate(action))
			. append_failure_message("AI proposed illegal action %s" % _act_key(action))
			. is_null()
		)
		log.append(_act_key(action))
		var events := view.apply(action)
		var over := false
		for e: GameEvent in events:
			if e is Events.GameEnded:
				over = true
		if over:
			log.append("GAME_ENDED")
			return log
	return log


func test_threat_map_hand_values() -> void:
	# Enemy artillery at (3,1) cannot move and fire, so its threat is
	# exactly its 2..3 ring, at shells' base vs the queried type.
	var gs := BattleFixture.make_state()
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 4))
	BattleFixture.spawn(gs, BattleFixture.ARTILLERY, 1, Vector2i(3, 1))
	var view := StateView.for_team(gs, 0)
	var threat := ThreatMap.compute(view, 0, BattleFixture.INFANTRY)
	assert_int(threat.get(Vector2i(1, 1), 0)).is_equal(90)  # distance 2
	assert_int(threat.get(Vector2i(3, 4), 0)).is_equal(90)  # distance 3
	assert_bool(threat.has(Vector2i(2, 1))).is_false()  # inside min range
	assert_bool(threat.has(Vector2i(3, 1))).is_false()  # its own tile
	# An unarmed enemy projects nothing.
	var quiet := BattleFixture.make_state()
	BattleFixture.spawn(quiet, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	BattleFixture.spawn(quiet, BattleFixture.HELI, 1, Vector2i(4, 4))
	var no_threat := ThreatMap.compute(StateView.for_team(quiet, 0), 0, BattleFixture.TANK)
	assert_bool(no_threat.is_empty()).is_true()


func test_wounded_unit_retreats_out_of_the_ring() -> void:
	# A battered tank sits in artillery range with every adjacent firing
	# spot blocked: the only sane move is out of the ring, and stage-2
	# scoring finds it.
	var gs := BattleFixture.make_state()
	var tank := BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(1, 1))
	tank.hp = 30
	var arty := BattleFixture.spawn(gs, BattleFixture.ARTILLERY, 1, Vector2i(3, 1))
	for blocker: Vector2i in [Vector2i(3, 0), Vector2i(2, 1), Vector2i(4, 1)]:
		var pal := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, blocker)
		pal.has_acted = true
	var ai := SimpleAI.new()
	var action := ai.choose_action(StateView.for_team(gs, 0)) as UnitAction
	assert_object(action).is_not_null()
	assert_int(action.unit_id).is_equal(tank.id)
	assert_int(action.verb).is_equal(UnitAction.Verb.WAIT)
	var dest: Vector2i = action.path[action.path.size() - 1]
	var d: int = Grid.manhattan(dest, arty.coord)
	assert_bool(d < 2 or d > 3).is_true()  # out of the shells' ring


func test_influence_map_signs_and_falloff() -> void:
	var gs := BattleFixture.make_state()
	BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(0, 0))
	BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(4, 4))
	var influence := InfluenceMap.compute(StateView.for_team(gs, 0), 0)
	assert_bool(influence[Vector2i(0, 0)] > 0).is_true()
	assert_bool(influence[Vector2i(4, 4)] < 0).is_true()
	assert_bool(influence[Vector2i(0, 0)] > influence[Vector2i(2, 0)]).is_true()  # falloff


func test_threat_map_shared_reach_cache() -> void:
	# A shared cache fills per mobile enemy and changes no values;
	# artillery (can't move and fire) never needs a search.
	var gs := BattleFixture.make_state()
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	var tank := BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(2, 2))
	var arty := BattleFixture.spawn(gs, BattleFixture.ARTILLERY, 1, Vector2i(0, 4))
	var view := StateView.for_team(gs, 0)
	var cache: Dictionary[int, Dictionary] = {}
	var vs_infantry := ThreatMap.compute(view, 0, BattleFixture.INFANTRY, cache)
	var vs_tank := ThreatMap.compute(view, 0, BattleFixture.TANK, cache)
	assert_bool(cache.has(tank.id)).is_true()
	assert_bool(cache.has(arty.id)).is_false()
	assert_int(cache.size()).is_equal(1)
	assert_bool(vs_infantry == ThreatMap.compute(view, 0, BattleFixture.INFANTRY)).is_true()
	assert_bool(vs_tank == ThreatMap.compute(view, 0, BattleFixture.TANK)).is_true()


func test_takes_the_enemy_hq_over_a_kill() -> void:
	# An infantry one step from finishing a capture at (2,0), and a tank
	# next to a 1-HP enemy tank. The kill is worth 10/100 * 7000 + 30%
	# bounty = 2800; finishing an ordinary city only 1200, so the AI
	# shoots. Make the tile blue's HQ and the capture wins outright.
	var gs := BattleFixture.make_econ_state()
	BattleFixture.claim(gs, Vector2i(2, 0), 1)
	var inf := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(2, 0))
	gs.map.capture_progress[Vector2i(2, 0)] = 10
	BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(0, 2))
	var weak := BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(1, 2))
	weak.hp = 10
	var ai := SimpleAI.new()
	var on_city := ai.choose_action(StateView.for_team(gs, 0)) as UnitAction
	assert_int(on_city.verb).is_equal(UnitAction.Verb.ATTACK)
	gs.map.terrain[gs.map.idx(Vector2i(2, 0))] = BattleFixture.HQ
	var on_hq := ai.choose_action(StateView.for_team(gs, 0)) as UnitAction
	assert_int(on_hq.verb).is_equal(UnitAction.Verb.CAPTURE)
	assert_int(on_hq.unit_id).is_equal(inf.id)
