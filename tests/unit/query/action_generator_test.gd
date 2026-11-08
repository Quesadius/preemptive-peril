extends GdUnitTestSuite
## ActionGenerator tests, including the §12 contract: every generated
## action passes validate(), and every canonical-path action that passes
## validate() is generated.


## The scripted four-unit battle used across suites: tank + infantry
## (team 0) vs tank + artillery (team 1).
func _battle_state() -> GameState:
	var gs := BattleFixture.make_state()
	BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(1, 2))
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(2, 2))
	BattleFixture.spawn(gs, BattleFixture.ARTILLERY, 1, Vector2i(3, 1))
	return gs


func _key(a: Action) -> String:
	if a is EndTurnAction:
		return "end_turn"
	if a is PowerAction:
		return "power|%d" % (a as PowerAction).power_level
	if a is BuildAction:
		var b := a as BuildAction
		return "build|%d|%s" % [b.unit_type_id, str(b.coord)]
	var ua := a as UnitAction
	var dest: Vector2i = ua.path[ua.path.size() - 1]
	var target: Vector2i = ua.target_coord if ua.verb == UnitAction.Verb.ATTACK else Vector2i.ZERO
	return "%d|%s|%d|%s" % [ua.unit_id, str(dest), ua.verb, str(target)]


func test_parity_holds_with_capture_and_build() -> void:
	# Both §12 directions on the economy map, now that CAPTURE and
	# BuildAction exist: everything generated validates, and every
	# canonical-path action or build that validates is generated.
	var gs := BattleFixture.make_econ_state()
	BattleFixture.claim(gs, Vector2i(1, 1), 0)
	gs.players[0].funds = 2500
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(2, 1))
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(4, 0))
	var generated := {}
	for a: Action in ActionGenerator.generate(gs):
		assert_object(Rules.validate(gs, a)).append_failure_message(_key(a)).is_null()
		generated[_key(a)] = true
	var checked: int = 0
	var verbs: Array[int] = [UnitAction.Verb.WAIT, UnitAction.Verb.CAPTURE]
	for uid: int in gs.units:
		for y: int in range(3):
			for x: int in range(5):
				var path := Movement.path_to(gs, uid, Vector2i(x, y))
				if path.is_empty():
					continue
				for verb: int in verbs:
					var probe := UnitAction.new()
					probe.unit_id = uid
					probe.path = path
					probe.verb = verb
					if Rules.validate(gs, probe) == null:
						checked += 1
						(
							assert_bool(generated.has(_key(probe)))
							. append_failure_message("missing " + _key(probe))
							. is_true()
						)
				for ty: int in range(3):
					for tx: int in range(5):
						var attack := UnitAction.new()
						attack.unit_id = uid
						attack.path = path
						attack.verb = UnitAction.Verb.ATTACK
						attack.target_coord = Vector2i(tx, ty)
						if Rules.validate(gs, attack) == null:
							checked += 1
							(
								assert_bool(generated.has(_key(attack)))
								. append_failure_message("missing " + _key(attack))
								. is_true()
							)
	for type_id: int in range(gs.ruleset.unit_types.size()):
		for y: int in range(3):
			for x: int in range(5):
				var build := BuildAction.new()
				build.unit_type_id = type_id
				build.coord = Vector2i(x, y)
				if Rules.validate(gs, build) == null:
					checked += 1
					(
						assert_bool(generated.has(_key(build)))
						. append_failure_message("missing " + _key(build))
						. is_true()
					)
	assert_int(checked).is_between(5, 2000)


func test_verbs_at_menu_cases() -> void:
	var gs := BattleFixture.make_state()
	var inf := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 1))  # ally
	var enemy := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(2, 1))
	# Next to the enemy: ATTACK first, then WAIT.
	var fighting: Array[int] = [UnitAction.Verb.ATTACK, UnitAction.Verb.WAIT]
	assert_array(ActionGenerator.verbs_at(gs, inf.id, Vector2i(1, 1))).contains_exactly(fighting)
	# Out of reach of anything: WAIT only.
	var idle: Array[int] = [UnitAction.Verb.WAIT]
	assert_array(ActionGenerator.verbs_at(gs, inf.id, Vector2i(1, 0))).contains_exactly(idle)
	# Ally-occupied and unreachable destinations offer nothing.
	assert_array(ActionGenerator.verbs_at(gs, inf.id, Vector2i(0, 1))).is_empty()
	assert_array(ActionGenerator.verbs_at(gs, inf.id, Vector2i(4, 4))).is_empty()
	# Enemy units offer nothing while it isn't their turn.
	assert_array(ActionGenerator.verbs_at(gs, enemy.id, Vector2i(2, 1))).is_empty()


func test_verbs_at_indirect_and_unarmed() -> void:
	var gs := BattleFixture.make_state()
	var arty := BattleFixture.spawn(gs, BattleFixture.ARTILLERY, 0, Vector2i(0, 2))
	var heli := BattleFixture.spawn(gs, BattleFixture.HELI, 0, Vector2i(2, 3))
	BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(2, 2))
	# Standing still the artillery has the tank at range 2.
	var fighting: Array[int] = [UnitAction.Verb.ATTACK, UnitAction.Verb.WAIT]
	assert_array(ActionGenerator.verbs_at(gs, arty.id, Vector2i(0, 2))).contains_exactly(fighting)
	# After moving, an indirect cannot fire.
	var idle: Array[int] = [UnitAction.Verb.WAIT]
	assert_array(ActionGenerator.verbs_at(gs, arty.id, Vector2i(0, 3))).contains_exactly(idle)
	# The unarmed heli adjacent to an enemy still only waits.
	assert_array(ActionGenerator.verbs_at(gs, heli.id, Vector2i(2, 3))).contains_exactly(idle)


func test_for_unit_hand_counted_enumeration() -> void:
	# Infantry at (0,0), ally at (0,1), enemy infantry at (2,1). Reachable
	# dests: the 9-tile baseline minus the enemy tile. Hand count per dest
	# (ATTACK per target + WAIT): (0,0)=1, (1,0)=1, (0,1)=ally 0, (1,1)=2,
	# (0,2)=1, (2,0)=2, (1,2)=1, (0,3)=1 — 9 actions, 2 of them attacks.
	var gs := BattleFixture.make_state()
	var inf := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 1))
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(2, 1))
	var actions := ActionGenerator.for_unit(gs, inf.id)
	assert_array(actions).has_size(9)
	var attacks: int = 0
	for a: Action in actions:
		var ua := a as UnitAction
		assert_object(Rules.validate(gs, ua)).append_failure_message(_key(ua)).is_null()
		if ua.verb == UnitAction.Verb.ATTACK:
			attacks += 1
			assert_that(ua.target_coord).is_equal(Vector2i(2, 1))
	assert_int(attacks).is_equal(2)


func test_for_unit_empty_when_unable_to_act() -> void:
	var gs := BattleFixture.make_state()
	var inf := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	var enemy := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(4, 4))
	assert_array(ActionGenerator.for_unit(gs, enemy.id)).is_empty()
	inf.has_acted = true
	assert_array(ActionGenerator.for_unit(gs, inf.id)).is_empty()


func test_generate_covers_all_units_and_ends_with_end_turn() -> void:
	var gs := _battle_state()
	var all := ActionGenerator.generate(gs)
	var per_unit: int = (
		ActionGenerator.for_unit(gs, 1).size() + ActionGenerator.for_unit(gs, 2).size()
	)
	assert_int(all.size()).is_equal(per_unit + 1)
	assert_object(all[all.size() - 1] as EndTurnAction).is_not_null()
	for a: Action in all:
		if a is UnitAction:
			assert_int(gs.units[(a as UnitAction).unit_id].team).is_equal(0)
	# Exhausting a unit removes exactly its share.
	gs.units[2].has_acted = true
	var fewer := ActionGenerator.generate(gs)
	assert_int(fewer.size()).is_equal(ActionGenerator.for_unit(gs, 1).size() + 1)


func test_every_generated_action_validates() -> void:
	var gs := _battle_state()
	for a: Action in ActionGenerator.generate(gs):
		assert_object(Rules.validate(gs, a)).append_failure_message(_key(a)).is_null()


func test_every_validated_action_is_generated() -> void:
	# The reverse §12 direction, modulo canonical paths: enumerate every
	# (unit, dest, verb, target) combo on the map, keep those validate()
	# accepts with the canonical path, and require each in generate().
	var gs := _battle_state()
	var generated := {}
	for a: Action in ActionGenerator.generate(gs):
		generated[_key(a)] = true
	assert_bool(generated.has("end_turn")).is_true()
	var checked: int = 0
	for uid: int in gs.units:
		for y: int in range(5):
			for x: int in range(5):
				var path := Movement.path_to(gs, uid, Vector2i(x, y))
				if path.is_empty():
					continue
				var wait := UnitAction.new()
				wait.unit_id = uid
				wait.path = path
				if Rules.validate(gs, wait) == null:
					checked += 1
					(
						assert_bool(generated.has(_key(wait)))
						. append_failure_message("missing " + _key(wait))
						. is_true()
					)
				for ty: int in range(5):
					for tx: int in range(5):
						var attack := UnitAction.new()
						attack.unit_id = uid
						attack.path = path
						attack.verb = UnitAction.Verb.ATTACK
						attack.target_coord = Vector2i(tx, ty)
						if Rules.validate(gs, attack) == null:
							checked += 1
							(
								assert_bool(generated.has(_key(attack)))
								. append_failure_message("missing " + _key(attack))
								. is_true()
							)
	# The sweep must have found real legal actions, not vacuously passed.
	assert_int(checked).is_between(10, 1000)
