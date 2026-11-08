class_name BattleFixture
extends RefCounted
## Hand-authored fixtures for movement, combat and rules tests (CLAUDE.md:
## fixtures stay small and hand-verifiable; expected results live in the
## tests, written by hand).
##
## Main map (5x5), x right, y down:
##   y0:  P  F  M  P  P
##   y1:  P  F  P  P  P
##   y2:  P  P  P  S  S
##   y3:  P  P  P  S  S
##   y4:  R  R  R  R  R
##
## Wall map (5x2) for two-budget (points vs fuel) route tradeoffs:
##   y0:  P  M  M  M  P
##   y1:  P  P  P  P  P
##
## Movement costs as clear/rain/snow, -1 impassable, plus defense stars:
##   terrain   foot      treads    air     stars
##   plains    1/1/2     1/2/2     1/1/2   1
##   forest    1/1/2     2/3/3     1/1/2   2
##   mountain  2/2/4     -1        1/1/2   4
##   sea       -1        -1        1/1/2   0
##   road      1/1/1     1/1/1     1/1/2   0
##
## Units (direct, range 1-1, unless noted):
##   infantry  foot   move 3  fuel 99  rifle (secondary, no ammo cost)
##   tank      treads move 4  fuel 70  cannon (primary, 3 ammo) + mg
##   heli      air    move 3  fuel 99  unarmed
##   ranger    foot   move 7  fuel 99  rifle (secondary, no ammo cost)
##   artillery treads move 3  fuel 50  shells (primary, 2 ammo);
##             range 2-3, cannot move and fire, never counters
##
## Base damage: rifle {infantry 55, tank 5, ranger 55}; cannon {tank 55,
## ranger 55}; mg {infantry 40, ranger 40}; shells {infantry 90, tank 70,
## ranger 90}. Nothing can target the heli (exercises no-weapon paths).
## luck_max is 0 so damage values are exact; luck tests override it.

const PLAINS := 0
const FOREST := 1
const MOUNTAIN := 2
const SEA := 3
const ROAD := 4
const CITY := 5
const FACTORY := 6

const INFANTRY := 0
const TANK := 1
const HELI := 2
const RANGER := 3
const ARTILLERY := 4
const APC := 5

## Economy map (5x3): a neutral city at (2,0), factories at (1,1) and
## (3,1), plains elsewhere. Ownership is claimed per test.
const ECON_LAYOUT: Array[int] = [
	PLAINS,
	PLAINS,
	CITY,
	PLAINS,
	PLAINS,
	PLAINS,
	FACTORY,
	PLAINS,
	FACTORY,
	PLAINS,
	PLAINS,
	PLAINS,
	PLAINS,
	PLAINS,
	PLAINS,
]

const LAYOUT: Array[int] = [
	PLAINS,
	FOREST,
	MOUNTAIN,
	PLAINS,
	PLAINS,
	PLAINS,
	FOREST,
	PLAINS,
	PLAINS,
	PLAINS,
	PLAINS,
	PLAINS,
	PLAINS,
	SEA,
	SEA,
	PLAINS,
	PLAINS,
	PLAINS,
	SEA,
	SEA,
	ROAD,
	ROAD,
	ROAD,
	ROAD,
	ROAD,
]

const WALL_LAYOUT: Array[int] = [
	PLAINS,
	MOUNTAIN,
	MOUNTAIN,
	MOUNTAIN,
	PLAINS,
	PLAINS,
	PLAINS,
	PLAINS,
	PLAINS,
	PLAINS,
]


## A fresh two-player state on the main 5x5 map, no units. Seeded rng.
static func make_state() -> GameState:
	return _make_state_on(LAYOUT, 5, 5)


## A fresh two-player state on the 5x2 wall map, no units. Seeded rng.
static func make_wall_state() -> GameState:
	return _make_state_on(WALL_LAYOUT, 5, 2)


## A fresh two-player state on the 5x3 economy map, no units, all
## properties neutral. Seeded rng.
static func make_econ_state() -> GameState:
	return _make_state_on(ECON_LAYOUT, 5, 3)


## Assigns the property at `coord` to `team`.
static func claim(gs: GameState, coord: Vector2i, team: int) -> void:
	gs.map.property_owner[gs.map.idx(coord)] = team


## Gives `team` a hand-built test CO: +10 passive attack, a 300-meter
## power (+10/+10), and a 600-meter super (+20/+20, heal 20, +3 luck).
## Returns the profile for per-test tweaking.
static func give_co(gs: GameState, team: int) -> COProfile:
	var power := COPower.new()
	power.key = &"test_rally"
	power.display_name = "Rally"
	power.meter_cost = 300
	power.attack_bonus = 10
	power.defense_bonus = 10
	var super_power := COPower.new()
	super_power.key = &"test_great_rally"
	super_power.display_name = "Great Rally"
	super_power.meter_cost = 600
	super_power.attack_bonus = 20
	super_power.defense_bonus = 20
	super_power.heal_hp = 20
	super_power.luck_bonus = 3
	var co := COProfile.new()
	co.key = &"test_commander"
	co.display_name = "Test Commander"
	co.passive_attack_bonus = 10
	co.power = power
	co.super_power = super_power
	gs.ruleset.cos.append(co)
	var player := Economy.player_of(gs, team)
	player.co_id = gs.ruleset.cos.size() - 1
	return co


## Adds a unit of `type_id` for `team` at `coord`, full fuel and ammo,
## with `units` and `occupancy` kept in sync.
static func spawn(gs: GameState, type_id: int, team: int, coord: Vector2i) -> UnitState:
	var unit_type: UnitType = gs.ruleset.unit_types[type_id]
	var u := UnitState.new()
	u.id = gs.next_unit_id
	gs.next_unit_id += 1
	u.type_id = type_id
	u.team = team
	u.coord = coord
	u.fuel = unit_type.max_fuel
	u.ammo = unit_type.max_ammo
	gs.units[u.id] = u
	gs.occupancy[coord] = u.id
	return u


static func _make_state_on(layout: Array[int], w: int, h: int) -> GameState:
	var gs := GameState.new()
	gs.ruleset = _make_ruleset()
	gs.config = GameConfig.new()
	gs.map = _make_map(layout, w, h)
	gs.rng = DeterministicRng.new(1)
	for team: int in range(2):
		var p := PlayerState.new()
		p.team = team
		gs.players.append(p)
	return gs


static func _make_map(layout: Array[int], w: int, h: int) -> MapState:
	var m := MapState.new()
	m.width = w
	m.height = h
	var t := PackedInt32Array()
	t.resize(w * h)
	for i: int in range(w * h):
		t[i] = layout[i]
	m.terrain = t
	var owners := PackedInt32Array()
	owners.resize(w * h)
	owners.fill(MapState.NO_OWNER)
	m.property_owner = owners
	return m


static func _pa(clear: int, rain: int, snow: int) -> PackedInt32Array:
	return PackedInt32Array([clear, rain, snow])


static func _make_class(key: StringName) -> MovementClass:
	var mc := MovementClass.new()
	mc.key = key
	mc.display_name = String(key)
	return mc


static func _make_terrain(
	key: StringName,
	stars: int,
	foot: PackedInt32Array,
	treads: PackedInt32Array,
	air: PackedInt32Array
) -> TerrainType:
	var t := TerrainType.new()
	t.key = key
	t.display_name = String(key)
	t.defense_stars = stars
	t.move_costs[&"foot"] = foot
	t.move_costs[&"treads"] = treads
	t.move_costs[&"air"] = air
	return t


static func _make_unit_type(
	key: StringName, movement: int, mclass: MovementClass, max_fuel: int
) -> UnitType:
	var t := UnitType.new()
	t.key = key
	t.display_name = String(key)
	t.movement = movement
	t.movement_class = mclass
	t.max_fuel = max_fuel
	return t


static func _make_weapon(
	key: StringName, uses_ammo: bool, damage: Dictionary[StringName, int]
) -> WeaponProfile:
	var table := DamageTable.new()
	table.key = key
	table.base_damage = damage
	var w := WeaponProfile.new()
	w.key = key
	w.display_name = String(key)
	w.uses_ammo = uses_ammo
	w.damage_table = table
	return w


static func _make_ruleset() -> Ruleset:
	var foot := _make_class(&"foot")
	var treads := _make_class(&"treads")
	var air := _make_class(&"air")
	var rifle := _make_weapon(&"rifle", false, {&"infantry": 55, &"tank": 5, &"ranger": 55})
	var cannon := _make_weapon(&"cannon", true, {&"tank": 55, &"ranger": 55})
	var mg := _make_weapon(&"mg", false, {&"infantry": 40, &"ranger": 40})
	var shells := _make_weapon(&"shells", true, {&"infantry": 90, &"tank": 70, &"ranger": 90})
	var infantry := _make_unit_type(&"infantry", 3, foot, 99)
	infantry.secondary_weapon = rifle
	infantry.capture_capable = true
	infantry.cost = 1000
	var tank := _make_unit_type(&"tank", 4, treads, 70)
	tank.primary_weapon = cannon
	tank.secondary_weapon = mg
	tank.max_ammo = 3
	tank.cost = 7000
	var heli := _make_unit_type(&"heli", 3, air, 99)
	heli.cost = 9000
	var ranger := _make_unit_type(&"ranger", 7, foot, 99)
	ranger.secondary_weapon = rifle
	ranger.capture_capable = true
	ranger.cost = 2000
	var artillery := _make_unit_type(&"artillery", 3, treads, 50)
	artillery.primary_weapon = shells
	artillery.max_ammo = 2
	artillery.attack_range_min = 2
	artillery.attack_range_max = 3
	artillery.can_move_and_fire = false
	artillery.cost = 6000
	var apc := _make_unit_type(&"apc", 6, treads, 70)
	apc.cost = 5000
	apc.transport_capacity = 1
	apc.transportable_classes = [foot]
	apc.supply_capable = true
	apc.fuel_per_turn = 0
	for buildable: UnitType in [infantry, tank, heli, ranger, artillery, apc]:
		buildable.built_at = [&"factory"]
	var rs := Ruleset.new()
	rs.luck_max = 0  # exact damage in tests; luck tests override
	rs.movement_classes.assign([foot, treads, air])
	(
		rs
		. terrain_types
		. assign(
			[
				_make_terrain(&"plains", 1, _pa(1, 1, 2), _pa(1, 2, 2), _pa(1, 1, 2)),
				_make_terrain(&"forest", 2, _pa(1, 1, 2), _pa(2, 3, 3), _pa(1, 1, 2)),
				_make_terrain(&"mountain", 4, _pa(2, 2, 4), _pa(-1, -1, -1), _pa(1, 1, 2)),
				_make_terrain(&"sea", 0, _pa(-1, -1, -1), _pa(-1, -1, -1), _pa(1, 1, 2)),
				_make_terrain(&"road", 0, _pa(1, 1, 1), _pa(1, 1, 1), _pa(1, 1, 2)),
				_make_property_terrain(&"city", &"", [foot, treads]),
				_make_property_terrain(&"factory", &"factory", [foot, treads]),
			]
		)
	)
	rs.unit_types.assign([infantry, tank, heli, ranger, artillery, apc])
	rs.terrain_types[FOREST].hides_units = true
	rs.terrain_types[MOUNTAIN].vision_bonus = 3
	return rs


static func _make_property_terrain(
	key: StringName, builds: StringName, repairs: Array[MovementClass]
) -> TerrainType:
	var t := _make_terrain(key, 3, _pa(1, 1, 1), _pa(1, 1, 1), _pa(1, 1, 2))
	t.is_property = true
	t.capturable = true
	t.income = 1000
	t.builds = builds
	t.repairs_classes.assign(repairs)
	return t
