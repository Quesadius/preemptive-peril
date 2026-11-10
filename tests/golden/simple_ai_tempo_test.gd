extends GdUnitTestSuite
## SimpleAI's tempo: it presses when it isn't outgunned, keeps units off
## tiles they would block, and — the guard that matters — two copies of
## it always finish a match on every shipped map instead of staring each
## other down. Scores in the comments are worked out by hand.


func _choose(gs: GameState, team: int) -> Action:
	return SimpleAI.new().choose_action(StateView.for_team(gs, team))


func _dest(action: Action) -> Vector2i:
	var ua := action as UnitAction
	return ua.path[ua.path.size() - 1]


func test_presses_at_parity_and_holds_when_outgunned() -> void:
	# Red tank at (0,0), blue tank at (4,4): too far to shoot (reach 4,
	# gap 8). Blue's cannon (55 vs tanks) covers (2,2), (1,3) and (0,4) —
	# each 4 tiles nearer, worth 48 — but not (1,1), 2 nearer, worth 24.
	#   Even armies: the AI presses; the threat costs 385 x 0.05 = 19.25,
	#   so (2,2) scores 28.75 and wins.
	#   Add an unarmed blue heli (9000): 7000 < 80% of 16000, no press;
	#   the threat costs 192.5, and the safe (1,1) wins with 24.
	var even := BattleFixture.make_state()
	BattleFixture.spawn(even, BattleFixture.TANK, 0, Vector2i(0, 0))
	BattleFixture.spawn(even, BattleFixture.TANK, 1, Vector2i(4, 4))
	assert_that(_dest(_choose(even, 0))).is_equal(Vector2i(2, 2))
	var outgunned := BattleFixture.make_state()
	BattleFixture.spawn(outgunned, BattleFixture.TANK, 0, Vector2i(0, 0))
	BattleFixture.spawn(outgunned, BattleFixture.TANK, 1, Vector2i(4, 4))
	BattleFixture.spawn(outgunned, BattleFixture.HELI, 1, Vector2i(3, 4))
	assert_that(_dest(_choose(outgunned, 0))).is_equal(Vector2i(1, 1))


func test_units_clear_their_own_factory() -> void:
	# A tank left on red's factory at (1,1) blocks every build. With no
	# enemy to march on, moving off is worth 200 anywhere that isn't
	# itself in the way; (0,0) is the first such tile in row-major order.
	var gs := BattleFixture.make_econ_state()
	BattleFixture.claim(gs, Vector2i(1, 1), 0)
	BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(1, 1))
	var action := _choose(gs, 0) as UnitAction
	assert_object(action).is_not_null()
	assert_int(action.verb).is_equal(UnitAction.Verb.WAIT)
	assert_that(_dest(action)).is_equal(Vector2i(0, 0))


func test_units_that_cannot_capture_keep_off_properties_to_take() -> void:
	# A tank parked on the neutral city at (2,0) stops red's infantry
	# from ever capturing it: it moves off (200), and not onto the neutral
	# factories either.
	var gs := BattleFixture.make_econ_state()
	BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(2, 0))
	var dest := _dest(_choose(gs, 0))
	var terrain: TerrainType = gs.ruleset.terrain_types[gs.map.terrain_at(dest)]
	assert_bool(terrain.capturable).is_false()
	# An infantry on the same city has business there: it captures.
	var foot := BattleFixture.make_econ_state()
	BattleFixture.spawn(foot, BattleFixture.INFANTRY, 0, Vector2i(2, 0))
	var action := _choose(foot, 0) as UnitAction
	assert_int(action.verb).is_equal(UnitAction.Verb.CAPTURE)
	assert_that(_dest(action)).is_equal(Vector2i(2, 0))


func test_fires_from_a_tile_that_blocks_nothing() -> void:
	# Blue infantry at (2,1), ringed by the city (2,0), two factories and
	# the plains at (2,2). Red's tank starts on the city and could shoot
	# from there, but every property spot costs 200 for being in the way:
	# it drives round to (2,2) and fires from the plains.
	var gs := BattleFixture.make_econ_state()
	BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(2, 0))
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(2, 1))
	var action := _choose(gs, 0) as UnitAction
	assert_int(action.verb).is_equal(UnitAction.Verb.ATTACK)
	assert_that(action.target_coord).is_equal(Vector2i(2, 1))
	assert_that(_dest(action)).is_equal(Vector2i(2, 2))


func test_two_ais_finish_a_match_on_every_shipped_map() -> void:
	# Evenly matched copies of the AI used to freeze: nobody stepped into
	# range, factories stayed blocked, tanks sat on the HQ their infantry
	# needed. Every map must now reach a winner well inside 1500 actions.
	var ruleset := load("res://data/rulesets/classic.tres") as Ruleset
	for def: MapDefinition in MapCatalog.all():
		var setup: Array[Dictionary] = [
			{"team": 0, "co": &"vale", "is_ai": true},
			{"team": 1, "co": &"rook", "is_ai": true},
		]
		var gs := Replay.state_from_map(def, ruleset, GameConfig.new(), 1, setup)
		var ai := SimpleAI.new()
		var winner: int = -1
		var actions: int = 0
		while winner < 0 and actions < 1500:
			var view := StateView.for_team(gs, gs.active_player().team)
			var action := ai.choose_action(view)
			assert_object(view.validate(action)).is_null()
			for e: GameEvent in view.apply(action):
				if e is Events.GameEnded:
					winner = (e as Events.GameEnded).winning_team
			actions += 1
		(
			assert_bool(winner >= 0)
			. append_failure_message(
				"%s: no winner after %d actions (day %d)" % [def.key, actions, gs.day]
			)
			. is_true()
		)
