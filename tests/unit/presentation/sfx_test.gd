extends GdUnitTestSuite
## Sound: the synthesized effects are well-formed and identical on every
## build; the AudioDirector honors the sound switch; and the battle asks
## for the right effects — without letting the player hear what fog
## hides. The dummy audio driver plays nothing in tests; they listen to
## the director's sfx_requested signal instead.

const KEYS: Array[StringName] = [
	&"select",
	&"cancel",
	&"move",
	&"attack",
	&"destroy",
	&"capture",
	&"captured",
	&"build",
	&"power",
	&"turn",
	&"victory",
	&"defeat",
]

var _heard: Array[StringName] = []


func _director() -> Node:
	return get_tree().root.get_node("AudioDirector")


func _store() -> Node:
	return get_tree().root.get_node("SettingsStore")


func before_test() -> void:
	_heard = []
	_store().apply_loaded({"sound_on": true})  # in memory only
	_director().sfx_requested.connect(_on_sfx)


func after_test() -> void:
	_director().sfx_requested.disconnect(_on_sfx)
	_store().reload()  # back to what's on disk


func _on_sfx(key: StringName) -> void:
	_heard.append(key)


func _rig() -> Battle:
	var battle: Battle = auto_free(Battle.assemble())
	add_child(battle)
	battle.event_player.skip_animations = true
	return battle


func test_every_effect_is_a_short_well_formed_clip() -> void:
	var effects := SfxSynth.build_all()
	assert_int(effects.size()).is_equal(KEYS.size())
	for key: StringName in KEYS:
		var wav := effects[key] as AudioStreamWAV
		assert_object(wav).append_failure_message(String(key)).is_not_null()
		assert_int(wav.format).is_equal(AudioStreamWAV.FORMAT_16_BITS)
		assert_int(wav.mix_rate).is_equal(22050)
		assert_bool(wav.stereo).is_false()
		var seconds: float = wav.data.size() / 2.0 / wav.mix_rate
		assert_float(seconds).append_failure_message(String(key)).is_between(0.05, 1.0)
		# Audible, and inside the 16-bit range with headroom: no clipping.
		var peak: int = 0
		for i: int in range(0, wav.data.size(), 2):
			peak = maxi(peak, absi(wav.data.decode_s16(i)))
		assert_int(peak).append_failure_message(String(key)).is_between(3000, 30000)
		# Each clip ends at (near) silence, so nothing clicks off.
		assert_int(absi(wav.data.decode_s16(wav.data.size() - 2))).is_less(400)


func test_synthesis_is_the_same_every_time() -> void:
	var first := SfxSynth.build_all()
	var second := SfxSynth.build_all()
	for key: StringName in KEYS:
		var a := (first[key] as AudioStreamWAV).data
		var b := (second[key] as AudioStreamWAV).data
		assert_bool(a == b).append_failure_message(String(key)).is_true()
	# The select blip is 0.06 s at 22050 Hz: 1323 samples, 2 bytes each.
	assert_int((first[&"select"] as AudioStreamWAV).data.size()).is_equal(2646)


func test_director_honors_the_sound_switch_and_unknown_keys() -> void:
	var director := _director()
	assert_int(director.registry.size()).is_equal(KEYS.size())
	director.play_sfx(&"select")
	director.play_sfx(&"kazoo")  # no such effect: ignored
	assert_array(_heard).contains_exactly([&"select"])
	_store().apply_loaded({"sound_on": false})
	director.play_sfx(&"select")
	assert_array(_heard).contains_exactly([&"select"])  # nothing new


func test_a_fight_sounds_like_one() -> void:
	# Select the tank, open its menu, attack and kill the last enemy.
	var b := _rig()
	var gs := BattleFixture.make_state()
	BattleFixture.spawn(gs, BattleFixture.TANK, 0, Vector2i(1, 2))
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 1, Vector2i(2, 2)).hp = 20
	b.load_state(gs)
	b.cursor.move_to(Vector2i(1, 2))
	b.controller.confirm()  # select the tank
	b.controller.confirm()  # stay put: the verb menu opens
	b.hud.action_menu.choose_selected()  # Attack: on to target select
	b.controller.cancel()  # back to the menu...
	b.hud.action_menu.choose_selected()  # ...and Attack again
	b.controller.confirm()  # fire
	var expected: Array[StringName] = [
		&"select",  # unit picked up
		&"select",  # menu opened
		&"select",  # Attack chosen
		&"cancel",
		&"select",  # Attack chosen again
		&"attack",
		&"destroy",
		&"victory",
	]
	assert_array(_heard).contains_exactly(expected)


func test_fog_keeps_unseen_actions_silent() -> void:
	# Red's infantry at (0,0) sees 2 tiles. A blue tank moving far away
	# makes no sound; one moving in plain sight does. Turn starts and
	# changes of ownership are public either way.
	var b := _rig()
	var gs := BattleFixture.make_state()
	gs.config.fog_enabled = true
	BattleFixture.spawn(gs, BattleFixture.INFANTRY, 0, Vector2i(0, 0))
	var hidden := BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(4, 4))
	var seen := BattleFixture.spawn(gs, BattleFixture.TANK, 1, Vector2i(0, 2))
	b.load_state(gs)
	var player := b.event_player
	var far_path: Array[Vector2i] = [Vector2i(4, 4), Vector2i(3, 4)]
	var near_path: Array[Vector2i] = [Vector2i(0, 2), Vector2i(0, 1)]
	assert_that(player.sound_for(Events.UnitMoved.new(hidden.id, far_path, -1))).is_equal(&"")
	assert_that(player.sound_for(Events.UnitMoved.new(seen.id, near_path, -1))).is_equal(&"move")
	assert_that(player.sound_for(Events.UnitAttacked.new(hidden.id, seen.id, 10, 0))).is_equal(
		&"attack"
	)
	# A unit built out of sight is silent; one built on a lit tile isn't.
	var dark_build := Events.UnitCreated.new(9, BattleFixture.TANK, 1, Vector2i(4, 0))
	var lit_build := Events.UnitCreated.new(9, BattleFixture.TANK, 1, Vector2i(1, 0))
	assert_that(player.sound_for(dark_build)).is_equal(&"")
	assert_that(player.sound_for(lit_build)).is_equal(&"build")
	assert_that(player.sound_for(Events.TurnStarted.new(1, 2))).is_equal(&"turn")
	assert_that(player.sound_for(Events.PropertyCaptured.new(Vector2i(4, 4), 1, 0))).is_equal(
		&"captured"
	)
	assert_that(player.sound_for(Events.UnitExhausted.new(seen.id))).is_equal(&"")
