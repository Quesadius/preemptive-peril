extends GdUnitTestSuite
## COs and powers: activation rules, combat modifiers, meter charging,
## and expiry. The fixture CO (BattleFixture.give_co) carries +10 passive
## attack, a 300-meter +10/+10 power, and a 600-meter +20/+20 super with
## heal 20. All damage numbers hand-computed, luck 0.


func test_classic_commanders_load() -> void:
	var rs := load("res://data/rulesets/classic.tres") as Ruleset
	assert_int(rs.cos.size()).is_equal(2)
	assert_that(rs.cos[0].key).is_equal(&"vale")
	assert_that(rs.cos[1].key).is_equal(&"rook")
	for co: COProfile in rs.cos:
		assert_object(co.power).is_not_null()
		assert_object(co.super_power).is_not_null()
		assert_bool(co.power.meter_cost < co.super_power.meter_cost).is_true()
	assert_int(rs.cos[1].passive_defense_bonus).is_equal(10)


func test_power_validate_matrix() -> void:
	var gs := BattleFixture.make_state()
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	var action := PowerAction.new()
	assert_that(Rules.validate(gs, action).code).is_equal(ActionError.NO_CO)
	BattleFixture.give_co(gs, 0)
	assert_that(Rules.validate(gs, action).code).is_equal(ActionError.INSUFFICIENT_METER)
	gs.players[0].power_meter = 300
	assert_object(Rules.validate(gs, action)).is_null()
	Rules.apply(gs, action)
	gs.players[0].power_meter = 300
	assert_that(Rules.validate(gs, action).code).is_equal(ActionError.POWER_ALREADY_ACTIVE)


func test_super_activation_heals_and_burns_meter() -> void:
	var gs := BattleFixture.make_state()
	BattleFixture.give_co(gs, 0)
	var hurt := BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	hurt.hp = 50
	var near_full := BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(1, 0))
	near_full.hp = 95
	gs.players[0].power_meter = 600
	var action := PowerAction.new()
	action.power_level = PlayerState.PowerState.SUPER
	assert_object(Rules.validate(gs, action)).is_null()
	var events := Rules.apply(gs, action)
	var activated := events[0] as Events.PowerActivated
	assert_object(activated).is_not_null()
	assert_int(activated.level).is_equal(PlayerState.PowerState.SUPER)
	assert_int(hurt.hp).is_equal(70)
	assert_int(near_full.hp).is_equal(100)  # heal clamps
	assert_int(gs.players[0].power_meter).is_equal(0)
	assert_int(gs.players[0].power_state).is_equal(PlayerState.PowerState.SUPER)


func test_modifiers_change_damage() -> void:
	var gs := BattleFixture.make_state()
	BattleFixture.give_co(gs, 0)
	var mine := BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(1, 2))
	var theirs := BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(2, 2))
	# Passive +10 attack: 55 * 1.10 * 0.9 = 54.45 -> 54 (baseline 49).
	assert_int(Combat.preview(gs, mine.id, theirs.id).damage).is_equal(54)
	# Active power adds +10 more: 55 * 1.2 * 0.9 = 59.4 -> 59.
	gs.players[0].power_meter = 300
	Rules.apply(gs, PowerAction.new())
	assert_int(Combat.preview(gs, mine.id, theirs.id).damage).is_equal(59)


func test_enemy_defense_power_mitigates() -> void:
	var gs := BattleFixture.make_state()
	BattleFixture.give_co(gs, 0)
	BattleFixture.give_co(gs, 1)
	var mine := BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(1, 2))
	var theirs := BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(2, 2))
	# Defender burning the +20 defense super: (200 - 120 - 10)/100 = 0.7,
	# attacker keeps passive 1.1: 55 * 1.1 * 0.7 = 42.35 -> 42.
	gs.players[1].power_state = PlayerState.PowerState.SUPER
	assert_int(Combat.preview(gs, mine.id, theirs.id).damage).is_equal(42)


func test_meter_charges_from_both_sides_of_an_exchange() -> void:
	var gs := BattleFixture.make_state()
	BattleFixture.give_co(gs, 0)
	BattleFixture.give_co(gs, 1)
	var mine := BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(1, 2))
	var theirs := BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(2, 2))
	var attack := UnitAction.new()
	attack.unit_id = mine.id
	attack.path = [Vector2i(1, 2)]
	attack.verb = UnitAction.Verb.ATTACK
	attack.target_coord = Vector2i(2, 2)
	var events := Rules.apply(gs, attack)
	var charges: int = 0
	for e: GameEvent in events:
		if e is Events.PowerCharged:
			charges += 1
	# Hit 54 (both sides +10 passive attack), counter 27: taker full,
	# dealer half, each way.
	assert_int(charges).is_equal(4)
	assert_int(gs.players[0].power_meter).is_equal(54)  # 27 + 27
	assert_int(gs.players[1].power_meter).is_equal(67)  # 54 + 13


func test_no_charge_while_a_power_burns() -> void:
	var gs := BattleFixture.make_state()
	BattleFixture.give_co(gs, 0)
	var mine := BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(1, 2))
	var theirs := BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(2, 2))
	gs.players[0].power_meter = 300
	Rules.apply(gs, PowerAction.new())
	assert_int(gs.players[0].power_meter).is_equal(0)
	var attack := UnitAction.new()
	attack.unit_id = mine.id
	attack.path = [Vector2i(1, 2)]
	attack.verb = UnitAction.Verb.ATTACK
	attack.target_coord = Vector2i(2, 2)
	Rules.apply(gs, attack)
	assert_int(gs.players[0].power_meter).is_equal(0)  # burning powers don't charge
	assert_object(theirs).is_not_null()


func test_power_expires_at_next_own_turn_start() -> void:
	var gs := BattleFixture.make_state()
	BattleFixture.give_co(gs, 0)
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	gs.players[0].power_meter = 300
	Rules.apply(gs, PowerAction.new())
	Rules.apply(gs, EndTurnAction.new())  # team 1's day: still burning
	assert_int(gs.players[0].power_state).is_equal(PlayerState.PowerState.CO_POWER)
	var events := Rules.apply(gs, EndTurnAction.new())  # team 0 wakes: expiry
	var expired := false
	for e: GameEvent in events:
		expired = expired or e is Events.PowerExpired
	assert_bool(expired).is_true()
	assert_int(gs.players[0].power_state).is_equal(PlayerState.PowerState.NONE)


func test_generator_and_ai_reach_for_powers() -> void:
	var gs := BattleFixture.make_state()
	BattleFixture.give_co(gs, 0)
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	gs.players[0].power_meter = 600
	var power_actions := ActionGenerator.powers(gs)
	assert_int(power_actions.size()).is_equal(2)  # normal and super both legal
	for a: Action in power_actions:
		assert_object(Rules.validate(gs, a)).is_null()
	var ai := SimpleAI.new()
	var choice := ai.choose_action(StateView.for_team(gs, 0))
	assert_bool(choice is PowerAction).is_true()
