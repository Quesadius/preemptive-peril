extends GdUnitTestSuite
## The shipped maps: the catalog finds them, each builds a playable match
## on the classic ruleset, and each is fair — both sides get one HQ, the
## same properties, and the same opening army.

const RULESET := "res://data/rulesets/classic.tres"


func _setup() -> Array[Dictionary]:
	return [{"team": 0, "co": &"vale"}, {"team": 1, "co": &"rook", "is_ai": true}]


func test_catalog_lists_maps_by_name_and_finds_by_key() -> void:
	var names: Array[String] = []
	for def: MapDefinition in MapCatalog.all():
		names.append(def.display_name)
	var expected: Array[String] = ["Crossroads", "Gauntlet", "Highlands"]
	assert_array(names).contains_exactly(expected)
	assert_that(MapCatalog.find(&"gauntlet").display_name).is_equal("Gauntlet")
	assert_object(MapCatalog.find(&"atlantis")).is_null()


func test_map_sizes() -> void:
	# Gauntlet is the phone map: 8 tiles wide fits a 390px-wide screen at
	# 1.5x (8 x 32 x 1.5 = 384).
	var gauntlet := MapCatalog.find(&"gauntlet")
	assert_that(Vector2i(gauntlet.width, gauntlet.height)).is_equal(Vector2i(8, 12))
	var highlands := MapCatalog.find(&"highlands")
	assert_that(Vector2i(highlands.width, highlands.height)).is_equal(Vector2i(18, 12))
	var crossroads := MapCatalog.find(&"crossroads")
	assert_that(Vector2i(crossroads.width, crossroads.height)).is_equal(Vector2i(12, 10))


func test_every_map_is_playable_and_fair() -> void:
	var ruleset := load(RULESET) as Ruleset
	for def: MapDefinition in MapCatalog.all():
		var gs := Replay.state_from_map(def, ruleset, GameConfig.new(), 1, _setup())
		assert_object(gs).append_failure_message(String(def.key)).is_not_null()
		# Owned terrain per team, by terrain key.
		var holdings: Array[Dictionary] = [{}, {}]
		for i: int in range(gs.map.property_owner.size()):
			var team: int = gs.map.property_owner[i]
			if team < 0:
				continue
			var key: StringName = ruleset.terrain_types[gs.map.terrain[i]].key
			holdings[team][key] = holdings[team].get(key, 0) + 1
		assert_that(holdings[0]).append_failure_message(String(def.key)).is_equal(holdings[1])
		assert_int(holdings[0].get(&"hq", 0)).append_failure_message(String(def.key)).is_equal(1)
		assert_bool(holdings[0].get(&"factory", 0) >= 1).is_true()
		# Opening armies, by unit key.
		var armies: Array[Dictionary] = [{}, {}]
		for uid: int in gs.units:
			var unit: UnitState = gs.units[uid]
			var unit_key: StringName = ruleset.unit_types[unit.type_id].key
			armies[unit.team][unit_key] = armies[unit.team].get(unit_key, 0) + 1
		assert_that(armies[0]).append_failure_message(String(def.key)).is_equal(armies[1])
		assert_bool(armies[0].is_empty()).is_false()
		assert_bool(ActionGenerator.generate(gs).size() > 1).is_true()


func test_highlands_has_airports_to_fight_over() -> void:
	# One airport in each base and two unowned in the middle.
	var ruleset := load(RULESET) as Ruleset
	var gs := Replay.state_from_map(
		MapCatalog.find(&"highlands"), ruleset, GameConfig.new(), 1, _setup()
	)
	var owners: Array[int] = []
	for i: int in range(gs.map.terrain.size()):
		if ruleset.terrain_types[gs.map.terrain[i]].key == &"airport":
			owners.append(gs.map.property_owner[i])
	owners.sort()
	assert_array(owners).contains_exactly([-1, -1, 0, 1])
	assert_that(ruleset.terrain_types[gs.map.terrain_at(Vector2i(1, 2))].key).is_equal(&"airport")
	assert_int(gs.map.property_owner[gs.map.idx(Vector2i(1, 2))]).is_equal(0)
