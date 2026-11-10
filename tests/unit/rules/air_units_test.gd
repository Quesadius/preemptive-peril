extends GdUnitTestSuite
## Air units on the real classic data: what flies ignores the ground
## under it (defense stars, forest cover, mountain lookouts), burns fuel
## every turn, and lives off airports. Expected numbers are worked out by
## hand from the classic tables; previews are luckless.

const CLASSIC := "res://data/rulesets/classic.tres"

const PLAINS := 0
const FOREST := 2
const MOUNTAIN := 3
const FACTORY := 5
const AIRPORT := 7

const INFANTRY := 0
const TANK := 2
const ANTI_AIR := 7
const COPTER := 9
const BOMBER := 10


## A one-row, two-player state on the classic ruleset.
func _strip(cells: Array[int]) -> GameState:
	var gs := GameState.new()
	gs.ruleset = load(CLASSIC) as Ruleset
	gs.config = GameConfig.new()
	gs.rng = DeterministicRng.new(1)
	var map := MapState.new()
	map.width = cells.size()
	map.height = 1
	map.terrain = PackedInt32Array(cells)
	var owners := PackedInt32Array()
	owners.resize(cells.size())
	owners.fill(MapState.NO_OWNER)
	map.property_owner = owners
	gs.map = map
	for team: int in range(2):
		var p := PlayerState.new()
		p.team = team
		gs.players.append(p)
	return gs


func test_air_roster_is_wired_to_airports() -> void:
	var gs := _strip([AIRPORT, FACTORY, PLAINS])
	var rs := gs.ruleset
	for id: int in [COPTER, BOMBER]:
		var flyer: UnitType = rs.unit_types[id]
		assert_bool(flyer.movement_class.airborne).is_true()
		assert_bool(flyer.crashes_without_fuel).is_true()
		assert_bool(flyer.fuel_per_turn > 0).is_true()
		assert_array(flyer.built_at).contains_exactly([&"airport"])
	assert_bool(rs.unit_types[TANK].movement_class.airborne).is_false()
	var airport: TerrainType = rs.terrain_types[AIRPORT]
	assert_that(airport.builds).is_equal(&"airport")
	assert_int(airport.repairs_classes.size()).is_equal(1)
	assert_that(airport.repairs_classes[0].key).is_equal(&"air")
	# An owned airport builds aircraft and nothing else; a factory builds
	# everything but aircraft.
	gs.map.property_owner[0] = 0
	gs.map.property_owner[1] = 0
	gs.players[0].funds = 30000
	assert_array(Economy.buildable_units(gs, Vector2i(0, 0))).contains_exactly([COPTER, BOMBER])
	var from_factory := Economy.buildable_units(gs, Vector2i(1, 0))
	assert_int(from_factory.size()).is_equal(9)
	assert_bool(from_factory.has(COPTER) or from_factory.has(BOMBER)).is_false()


func test_flyers_get_no_terrain_defense() -> void:
	# Anti-air (vulcan) from the plains at (1,0):
	#   a copter over the 4-star mountain: 120 x 1.0 = 120, stars ignored;
	#   an infantry ON the mountain: 105 x (100 - 4 x 10)% = 63.
	var gs := _strip([MOUNTAIN, PLAINS, MOUNTAIN])
	var gun := Ids.create_unit(gs, ANTI_AIR, 0, Vector2i(1, 0))
	var copter := Ids.create_unit(gs, COPTER, 1, Vector2i(0, 0))
	var climber := Ids.create_unit(gs, INFANTRY, 1, Vector2i(2, 0))
	assert_int(Combat.preview(gs, gun.id, copter.id).damage).is_equal(120)
	assert_int(Combat.preview(gs, gun.id, climber.id).damage).is_equal(63)
	# And the other way: the copter's missiles hit a tank in the 2-star
	# forest for 55 x 80% = 44; the tank's MG answers at 6 displayed HP
	# for 10 x 0.6 = 6, with nothing shaved off for the mountain below.
	var duel := _strip([MOUNTAIN, FOREST])
	var hunter := Ids.create_unit(duel, COPTER, 0, Vector2i(0, 0))
	var tank := Ids.create_unit(duel, TANK, 1, Vector2i(1, 0))
	var preview := Combat.preview(duel, hunter.id, tank.id)
	assert_int(preview.damage).is_equal(44)
	assert_bool(preview.can_counter).is_true()
	assert_int(preview.counter_damage).is_equal(6)


func test_bombers_fear_only_anti_air() -> void:
	var gs := _strip([PLAINS, PLAINS, PLAINS, PLAINS])
	var bomber := Ids.create_unit(gs, BOMBER, 1, Vector2i(1, 0))
	var tank := Ids.create_unit(gs, TANK, 0, Vector2i(0, 0))
	var gun := Ids.create_unit(gs, ANTI_AIR, 0, Vector2i(2, 0))
	var copter := Ids.create_unit(gs, COPTER, 0, Vector2i(3, 0))
	assert_object(Combat.usable_weapon(gs, tank, bomber)).is_null()
	assert_object(Combat.usable_weapon(gs, copter, bomber)).is_null()
	assert_int(Combat.preview(gs, gun.id, bomber.id).damage).is_equal(75)
	# The bomber flattens the tank (105 x 90% on 1-star plains = 94) and
	# takes nothing back: no tank weapon can reach it.
	var run := Combat.preview(gs, bomber.id, tank.id)
	assert_int(run.damage).is_equal(94)
	assert_bool(run.can_counter).is_false()


func test_forests_hide_ground_units_but_not_flyers() -> void:
	# The viewer at (2,0) sees 2 tiles each way. Both forests are lit and
	# neither has a viewer adjacent: the infantry in one stays hidden,
	# the copter over the other is in plain sight.
	var gs := _strip([FOREST, PLAINS, PLAINS, PLAINS, FOREST])
	gs.config.fog_enabled = true
	Ids.create_unit(gs, INFANTRY, 0, Vector2i(2, 0))
	var lurker := Ids.create_unit(gs, INFANTRY, 1, Vector2i(0, 0))
	var copter := Ids.create_unit(gs, COPTER, 1, Vector2i(4, 0))
	assert_bool(Fog.sees_unit(gs, 0, lurker)).is_false()
	assert_bool(Fog.sees_unit(gs, 0, copter)).is_true()
	var mask := Fog.mask_for(gs, 0)
	assert_bool(Fog.sees_unit(gs, 0, copter, mask)).is_true()


func test_mountains_extend_vision_for_climbers_not_flyers() -> void:
	# On the mountain at (0,0): infantry sees 2 + 3 = 5 tiles out (6 lit
	# on this strip); a copter overhead sees its plain 3 (4 lit).
	var cells: Array[int] = [MOUNTAIN, PLAINS, PLAINS, PLAINS, PLAINS, PLAINS, PLAINS, PLAINS]
	var on_foot := _strip(cells)
	on_foot.config.fog_enabled = true
	Ids.create_unit(on_foot, INFANTRY, 0, Vector2i(0, 0))
	var overhead := _strip(cells)
	overhead.config.fog_enabled = true
	Ids.create_unit(overhead, COPTER, 0, Vector2i(0, 0))
	var lit_on_foot: int = 0
	for b: int in Fog.compute(on_foot, 0):
		lit_on_foot += b
	var lit_overhead: int = 0
	for b: int in Fog.compute(overhead, 0):
		lit_overhead += b
	assert_int(lit_on_foot).is_equal(6)
	assert_int(lit_overhead).is_equal(4)


func test_fuel_burns_each_turn_and_airports_refill() -> void:
	var gs := _strip([AIRPORT, PLAINS, PLAINS, PLAINS])
	gs.map.property_owner[0] = 0
	var parked := Ids.create_unit(gs, COPTER, 0, Vector2i(0, 0))
	parked.fuel = 10
	parked.ammo = 0
	var cruising := Ids.create_unit(gs, BOMBER, 0, Vector2i(1, 0))
	cruising.fuel = 6
	var doomed := Ids.create_unit(gs, BOMBER, 0, Vector2i(2, 0))
	doomed.fuel = 5
	var events := TurnFlow.begin_turn(gs, 0)
	# On its airport: refilled to 99 fuel and 6 missiles, then the day's
	# 2 fuel burns.
	assert_int(parked.fuel).is_equal(97)
	assert_int(parked.ammo).is_equal(6)
	# In the air: 6 - 5 leaves the bomber 1 fuel...
	assert_int(cruising.fuel).is_equal(1)
	# ...and 5 - 5 leaves the other none: it crashes.
	assert_bool(gs.units.has(doomed.id)).is_false()
	var crashes: int = 0
	for e: GameEvent in events:
		if e is Events.UnitDestroyed and (e as Events.UnitDestroyed).unit_id == doomed.id:
			crashes += 1
	assert_int(crashes).is_equal(1)
