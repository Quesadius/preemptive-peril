extends GdUnitTestSuite
## The save format's later versions and the files behind autosave: the weather flag
## and state digest round-trip, a log that replays to a different state
## is refused, version 1 files still load, and saves read, write and
## delete on disk.

const RULESET := "res://data/rulesets/classic.tres"
const SCRATCH := "user://test_autosave_format.json"


func after_test() -> void:
	SaveGame.delete_file(SCRATCH)


func _new_save(weather: bool) -> SaveGame:
	var save := SaveGame.new()
	save.map_key = &"gauntlet"
	save.rng_seed = 7
	save.weather_enabled = weather
	save.player_setup = [{"team": 0, "co": &"vale"}, {"team": 1, "co": &"rook", "is_ai": true}]
	return save


## Applies and logs `action`, keeping the save's digest current.
func _play(save: SaveGame, gs: GameState, action: Action) -> void:
	assert_object(Rules.validate(gs, action)).is_null()
	Rules.apply(gs, action)
	save.record(action, gs.ruleset)
	save.digest = Replay.digest(gs)


func _walk(unit_id: int, path: Array[Vector2i]) -> UnitAction:
	var ua := UnitAction.new()
	ua.unit_id = unit_id
	ua.path = path
	return ua


func test_weather_and_digest_round_trip() -> void:
	var ruleset := load(RULESET) as Ruleset
	var def := MapCatalog.find(&"gauntlet")
	var save := _new_save(true)
	var live := Replay.run(save, ruleset, def)
	assert_bool(live.config.random_weather).is_true()
	# Red's tank starts at (4,10), between its two infantry; it climbs
	# into the forest at (4,9), then both sides end their turns.
	var tank := live.unit_at(Vector2i(4, 10))
	_play(save, live, _walk(tank.id, [Vector2i(4, 10), Vector2i(4, 9)]))
	_play(save, live, EndTurnAction.new())
	_play(save, live, EndTurnAction.new())
	var loaded := SaveGame.from_json(save.to_json())
	assert_int(loaded.version).is_equal(SaveGame.SAVE_VERSION)
	assert_bool(loaded.weather_enabled).is_true()
	assert_that(loaded.digest).is_equal(save.digest)
	assert_int(loaded.action_log.size()).is_equal(3)
	var replayed := Replay.run(loaded, ruleset, def)
	assert_object(replayed).is_not_null()
	assert_bool(replayed.config.random_weather).is_true()
	assert_int(replayed.day).is_equal(2)
	assert_that(replayed.unit_at(Vector2i(4, 9)).id).is_equal(tank.id)
	assert_that(Replay.digest(replayed)).is_equal(Replay.digest(live))
	# Compact output parses to the same save.
	assert_that(SaveGame.from_json(save.to_json("")).to_json()).is_equal(save.to_json())


func test_digest_follows_everything_that_matters() -> void:
	var ruleset := load(RULESET) as Ruleset
	var def := MapCatalog.find(&"gauntlet")
	var a := Replay.run(_new_save(false), ruleset, def)
	var b := Replay.run(_new_save(false), ruleset, def)
	var same := Replay.digest(a)
	assert_that(Replay.digest(b)).is_equal(same)
	assert_that(Replay.digest(a)).is_equal(same)  # reading it changes nothing
	b.units[1].hp = 90
	assert_that(Replay.digest(b)).is_not_equal(same)
	b.units[1].hp = 100
	assert_that(Replay.digest(b)).is_equal(same)
	b.players[1].funds += 1
	assert_that(Replay.digest(b)).is_not_equal(same)
	b.players[1].funds -= 1
	b.map.property_owner[0] = 1
	assert_that(Replay.digest(b)).is_not_equal(same)
	b.map.property_owner[0] = MapState.NO_OWNER
	b.rng.roll_range(0, 9)  # the random sequence moved on
	assert_that(Replay.digest(b)).is_not_equal(same)


func test_a_log_that_replays_elsewhere_is_refused() -> void:
	var ruleset := load(RULESET) as Ruleset
	var def := MapCatalog.find(&"gauntlet")
	var save := _new_save(false)
	var live := Replay.run(save, ruleset, def)
	_play(save, live, EndTurnAction.new())
	_play(save, live, EndTurnAction.new())
	assert_object(Replay.run(SaveGame.from_json(save.to_json()), ruleset, def)).is_not_null()
	# Drop the last action: every remaining one is legal, but the state it
	# reaches isn't the one the save recorded.
	var shortened := SaveGame.from_json(save.to_json())
	shortened.action_log.pop_back()
	assert_object(Replay.run(shortened, ruleset, def)).is_null()
	# The same log under different weather settings is a different match.
	var other_rules := SaveGame.from_json(save.to_json())
	other_rules.digest = "0123456789abcdef0123456789abcdef"
	assert_object(Replay.run(other_rules, ruleset, def)).is_null()


func test_version_1_saves_still_load() -> void:
	var old := SaveGame.from_json(
		'{"version": 1, "map": "gauntlet", "seed": 3, "players": [{"team": 0}, {"team": 1}]}'
	)
	assert_object(old).is_not_null()
	assert_int(old.version).is_equal(1)
	assert_bool(old.weather_enabled).is_false()
	assert_that(old.digest).is_equal("")
	# With no digest to hold it to, the log is only checked for legality.
	var gs := Replay.run(old, load(RULESET) as Ruleset, MapCatalog.find(&"gauntlet"))
	assert_object(gs).is_not_null()
	assert_object(SaveGame.from_json('{"version": 4}')).is_null()  # from the future
	assert_object(SaveGame.from_json('{"version": 2, "weather": "sometimes"}')).is_null()
	assert_object(SaveGame.from_json('{"version": 2, "digest": 12}')).is_null()


func test_saves_read_write_and_delete_on_disk() -> void:
	assert_object(SaveGame.read_file(SCRATCH)).is_null()  # nothing there yet
	var save := _new_save(true)
	save.digest = "abc"
	assert_bool(save.write_file(SCRATCH)).is_true()
	var back := SaveGame.read_file(SCRATCH)
	assert_object(back).is_not_null()
	assert_that(back.to_json()).is_equal(save.to_json())
	SaveGame.delete_file(SCRATCH)
	assert_object(SaveGame.read_file(SCRATCH)).is_null()
	SaveGame.delete_file(SCRATCH)  # deleting nothing is fine
	# An implausibly large file is refused without being parsed.
	var bloat := FileAccess.open(SCRATCH, FileAccess.WRITE)
	var filler := PackedByteArray()
	filler.resize(SaveGame.MAX_FILE_BYTES + 1)
	bloat.store_buffer(filler)
	bloat.close()
	assert_object(SaveGame.read_file(SCRATCH)).is_null()


func test_version_3_carries_funds_income_and_ai_level() -> void:
	var save := _new_save(false)
	save.player_setup = [
		{"team": 0, "co": &"vale", "funds": 5000},
		{"team": 1, "co": &"rook", "is_ai": true, "funds": 10000, "income": 150, "ai": &"hard"},
	]
	var loaded := SaveGame.from_json(save.to_json())
	assert_int(loaded.version).is_equal(3)
	assert_that(loaded.player_setup[0]).is_equal(
		{"team": 0, "co": &"vale", "is_ai": false, "funds": 5000}
	)
	assert_int(loaded.player_setup[1]["funds"]).is_equal(10000)
	assert_int(loaded.player_setup[1]["income"]).is_equal(150)
	assert_that(loaded.player_setup[1]["ai"]).is_equal(&"hard")
	var gs := Replay.run(loaded, load(RULESET) as Ruleset, MapCatalog.find(&"gauntlet"))
	assert_int(gs.players[0].funds).is_equal(5000)
	assert_int(gs.players[1].funds).is_equal(10000)
	assert_int(gs.players[0].income_percent).is_equal(100)
	assert_int(gs.players[1].income_percent).is_equal(150)
	# Mistyped or impossible values are refused, not coerced.
	var head := '{"version": 3, "map": "gauntlet", "players": [{"team": 0, '
	assert_object(SaveGame.from_json(head + '"funds": "lots"}]}')).is_null()
	assert_object(SaveGame.from_json(head + '"income": 1.5}]}')).is_null()
	assert_object(SaveGame.from_json(head + '"ai": 3}]}')).is_null()
	var broke := SaveGame.from_json(head + '"funds": -5}, {"team": 1}]}')
	assert_object(broke).is_not_null()  # well-typed...
	(
		assert_object(Replay.run(broke, load(RULESET) as Ruleset, MapCatalog.find(&"gauntlet")))
		. is_null()
	)
	var free_lunch := SaveGame.from_json(head + '"income": 0}, {"team": 1}]}')
	(
		assert_object(
			Replay.run(free_lunch, load(RULESET) as Ruleset, MapCatalog.find(&"gauntlet"))
		)
		. is_null()
	)
