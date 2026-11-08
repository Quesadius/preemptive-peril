extends GdUnitTestSuite
## State invariants after every action (CLAUDE.md), plus the replay
## determinism guarantee, on a scripted four-unit battle. Full fuzzing
## over generated actions arrives with ActionGenerator.


## Fixture battle: tank + infantry (team 0) vs tank + artillery (team 1).
func _battle_state() -> GameState:
	var gs := BattleFixture.make_state()
	BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(1, 2))  # id 1
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))  # id 2
	BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(2, 2))  # id 3
	BattleFixture.spawn(gs, BattleFixture.ARTILLERY, 1, Vector2i(3, 1))  # id 4
	return gs


## Six plies covering move, direct combat, indirect fire, a kill, and two
## turn changes. Unit ids match _battle_state comments.
func _script() -> Array[Action]:
	var walk := UnitAction.new()
	walk.unit_id = 2
	walk.path = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)]
	var poke := UnitAction.new()
	poke.unit_id = 1
	poke.path = [Vector2i(1, 2)]
	poke.verb = UnitAction.Verb.ATTACK
	poke.target_coord = Vector2i(2, 2)
	var shell := UnitAction.new()
	shell.unit_id = 4
	shell.path = [Vector2i(3, 1)]
	shell.verb = UnitAction.Verb.ATTACK
	shell.target_coord = Vector2i(1, 2)
	var finish := UnitAction.new()
	finish.unit_id = 3
	finish.path = [Vector2i(2, 2)]
	finish.verb = UnitAction.Verb.ATTACK
	finish.target_coord = Vector2i(1, 2)
	return [walk, poke, EndTurnAction.new(), shell, finish, EndTurnAction.new()]


func _check_invariants(gs: GameState) -> void:
	# occupancy <-> units agree, one unit per tile.
	for coord: Vector2i in gs.occupancy:
		var uid: int = gs.occupancy[coord]
		(
			assert_bool(gs.units.has(uid))
			. append_failure_message("stale occupancy %s" % str(coord))
			. is_true()
		)
		assert_that(gs.units[uid].coord).is_equal(coord)
	var unloaded: int = 0
	for uid: int in gs.units:
		var u: UnitState = gs.units[uid]
		var t: UnitType = gs.ruleset.unit_types[u.type_id]
		if u.carrier_id == -1:
			unloaded += 1
			assert_int(gs.occupancy.get(u.coord, -1)).is_equal(uid)
		else:
			# Loaded: the carrier exists, lists this passenger, and they
			# share a tile the passenger doesn't occupy.
			assert_bool(gs.units.has(u.carrier_id)).is_true()
			var carrier: UnitState = gs.units[u.carrier_id]
			assert_bool(carrier.cargo.has(uid)).is_true()
			assert_that(u.coord).is_equal(carrier.coord)
		assert_int(u.hp).is_between(1, 100)
		assert_int(u.fuel).is_between(0, t.max_fuel)
		assert_int(u.ammo).is_between(0, t.max_ammo)
		assert_int(u.cargo.size()).is_between(0, t.transport_capacity)
		for cid: int in u.cargo:
			assert_bool(gs.units.has(cid)).is_true()
			assert_int(gs.units[cid].carrier_id).is_equal(uid)
	assert_int(gs.occupancy.size()).is_equal(unloaded)
	for p: PlayerState in gs.players:
		assert_bool(p.funds >= 0).is_true()
	# Capture progress only exists under a live, capture-capable unit of
	# a team that doesn't own the tile, and only below the threshold.
	for coord: Vector2i in gs.map.capture_progress:
		var progress: int = gs.map.capture_progress[coord]
		assert_int(progress).is_between(1, gs.ruleset.capture_threshold - 1)
		var capturer := gs.unit_at(coord)
		(
			assert_object(capturer)
			. append_failure_message("orphan capture progress at %s" % str(coord))
			. is_not_null()
		)
		if capturer != null:
			var ct: UnitType = gs.ruleset.unit_types[capturer.type_id]
			assert_bool(ct.capture_capable).is_true()
			var owner_team: int = gs.map.property_owner[gs.map.idx(coord)]
			assert_bool(owner_team != capturer.team).is_true()


func test_scripted_battle_preserves_invariants() -> void:
	var gs := _battle_state()
	_check_invariants(gs)
	var step: int = 0
	for action: Action in _script():
		step += 1
		(
			assert_object(Rules.validate(gs, action))
			. append_failure_message("step %d should be legal" % step)
			. is_null()
		)
		Rules.apply(gs, action)
		_check_invariants(gs)
	# The battle ended as traced by hand: team 0's tank fell on step 5.
	assert_bool(gs.units.has(1)).is_false()
	assert_int(gs.units.size()).is_equal(3)
	assert_int(gs.day).is_equal(2)
	assert_int(gs.current_player).is_equal(0)


func test_replay_reproduces_identical_state() -> void:
	# Same seed + same actions = identical end state, luck and all.
	var a := _battle_state()
	var b := _battle_state()
	a.ruleset.luck_max = 9
	b.ruleset.luck_max = 9
	for action: Action in _script():
		# Luck can kill a unit a step early, making a scripted follow-up
		# illegal — honor apply()'s precondition and skip it on BOTH
		# states (they are identical, so they always agree).
		if Rules.validate(a, action) != null:
			continue
		Rules.apply(a, action)
		Rules.apply(b, action)
	assert_int(b.day).is_equal(a.day)
	assert_int(b.current_player).is_equal(a.current_player)
	assert_int(b.weather).is_equal(a.weather)
	assert_int(b.next_unit_id).is_equal(a.next_unit_id)
	assert_int(b.units.size()).is_equal(a.units.size())
	for uid: int in a.units:
		var ua: UnitState = a.units[uid]
		var ub: UnitState = b.units[uid]
		assert_that(ub.coord).is_equal(ua.coord)
		assert_int(ub.hp).is_equal(ua.hp)
		assert_int(ub.fuel).is_equal(ua.fuel)
		assert_int(ub.ammo).is_equal(ua.ammo)
		assert_bool(ub.has_acted).is_equal(ua.has_acted)
	assert_int(b.occupancy.size()).is_equal(a.occupancy.size())
	for coord: Vector2i in a.occupancy:
		assert_int(b.occupancy.get(coord, -1)).is_equal(a.occupancy[coord])
	for i: int in range(a.players.size()):
		assert_int(b.players[i].funds).is_equal(a.players[i].funds)
	# Even the RNG position matches: the next draw would be identical.
	var next_a: int = a.rng.clone().roll_range(0, 1000000)
	var next_b: int = b.rng.clone().roll_range(0, 1000000)
	assert_int(next_b).is_equal(next_a)


func test_random_legal_walk_preserves_invariants() -> void:
	# §12: generate random legal sequences, assert invariants after each.
	# The chooser is its own seeded rng — state.rng may only advance
	# inside Rules.apply(). Fixed seeds keep the walk reproducible.
	var gs := _battle_state()
	gs.ruleset.luck_max = 9
	var chooser := DeterministicRng.new(7)
	for _ply: int in range(40):
		var actions := ActionGenerator.generate(gs)
		var action: Action = actions[chooser.roll_range(0, actions.size() - 1)]
		assert_object(Rules.validate(gs, action)).is_null()
		Rules.apply(gs, action)
		_check_invariants(gs)


func test_random_legal_walk_with_economy() -> void:
	# Same walk on the economy map: capture, build, and income now join
	# movement and combat under the invariant checks. Seeds fixed.
	var gs := BattleFixture.make_econ_state()
	BattleFixture.claim(gs, Vector2i(1, 1), 0)
	BattleFixture.claim(gs, Vector2i(3, 1), 1)
	gs.players[0].funds = 5000
	gs.players[1].funds = 5000
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(4, 2))
	BattleFixture.spawn(gs, BattleFixture.APC, 0, Vector2i(2, 2))
	gs.ruleset.luck_max = 9
	var chooser := DeterministicRng.new(11)
	for _ply: int in range(60):
		var actions := ActionGenerator.generate(gs)
		var action: Action = actions[chooser.roll_range(0, actions.size() - 1)]
		assert_object(Rules.validate(gs, action)).is_null()
		Rules.apply(gs, action)
		_check_invariants(gs)


func test_random_legal_walk_under_fog() -> void:
	# The fogged walk: honest generation, ambush interruptions, and the
	# same invariants after every ply. Seeds fixed.
	var gs := BattleFixture.make_econ_state()
	gs.config.fog_enabled = true
	BattleFixture.claim(gs, Vector2i(1, 1), 0)
	BattleFixture.claim(gs, Vector2i(3, 1), 1)
	gs.players[0].funds = 4000
	gs.players[1].funds = 4000
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 2))
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(4, 0))
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(4, 2))
	gs.ruleset.luck_max = 9
	var chooser := DeterministicRng.new(13)
	for _ply: int in range(60):
		var actions := ActionGenerator.generate(gs)
		var action: Action = actions[chooser.roll_range(0, actions.size() - 1)]
		assert_object(Rules.validate(gs, action)).is_null()
		Rules.apply(gs, action)
		_check_invariants(gs)
