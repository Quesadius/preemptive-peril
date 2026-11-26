class_name MissionCatalog
extends RefCounted
## Handcrafted Campaign Missions (escalating asymmetric scenarios) and
## Tactical Puzzles ("Win in N Turns" challenges). Each entry builds a
## self-contained MapDefinition + MatchOptions recipe.


class MissionDef:
	var key: StringName = &""
	var display_name: String = ""
	var briefing: String = ""
	var is_puzzle: bool = false
	var turn_limit: int = 0  # > 0 for puzzles: must win by this day
	var par_days: int = 10
	var player_co: StringName = &"vale"
	var enemy_co: StringName = &"rook"
	var difficulty: StringName = &"normal"
	var player_funds: int = 0
	var enemy_funds: int = 0
	var fog: bool = false
	var weather: bool = false
	var initial_player_meter: int = 0
	var map: MapDefinition


const PALETTE_KEYS: Dictionary[String, StringName] = {
	".": &"plains",
	"=": &"road",
	"f": &"forest",
	"^": &"mountain",
	"c": &"city",
	"F": &"factory",
	"H": &"hq",
	"A": &"airport",
	"~": &"sea",
	"r": &"river",
	"B": &"bridge",
	"P": &"port",
	"T": &"comms_tower",
	"S": &"silo",
}


## All campaign missions in story order.
static func missions() -> Array[MissionDef]:
	return [
		_m1_first_blood(),
		_m2_bridgehead(),
		_m3_silo_race(),
		_m4_fog_ambush(),
		_m5_iron_armada(),
		_m6_citadel_siege(),
	]


## All tactical puzzles in difficulty order.
static func puzzles() -> Array[MissionDef]:
	return [
		_p1_bridge_breach(),
		_p2_missile_strike(),
		_p3_artillery_check(),
		_p4_lightning_rush(),
	]


## Finds a mission or puzzle by key, or null.
static func find(key: StringName) -> MissionDef:
	for m: MissionDef in missions():
		if m.key == key:
			return m
	for p: MissionDef in puzzles():
		if p.key == key:
			return p
	return null


static func _make_map(
	key: StringName,
	display_name: String,
	rows: Array[String],
	owners: Dictionary[Vector2i, int],
	units: Array[Dictionary]
) -> MapDefinition:
	var h: int = rows.size()
	var w: int = rows[0].length()
	var palette: Array[StringName] = []
	var terrain := PackedInt32Array()
	terrain.resize(w * h)
	var prop_owner := PackedInt32Array()
	prop_owner.resize(w * h)
	prop_owner.fill(-1)
	for y: int in range(h):
		for x: int in range(w):
			var ch: String = rows[y].substr(x, 1)
			var tkey: StringName = PALETTE_KEYS[ch]
			var idx: int = palette.find(tkey)
			if idx < 0:
				idx = palette.size()
				palette.append(tkey)
			terrain[y * w + x] = idx
			var c := Vector2i(x, y)
			if owners.has(c):
				prop_owner[y * w + x] = owners[c]
	var def := MapDefinition.new()
	def.key = key
	def.display_name = display_name
	def.width = w
	def.height = h
	def.terrain_palette = palette
	def.terrain = terrain
	def.property_owner = prop_owner
	def.starting_units = units
	return def


# =============================================================================
# CAMPAIGN MISSIONS
# =============================================================================


static func _m1_first_blood() -> MissionDef:
	var m := MissionDef.new()
	m.key = &"m1_first_blood"
	m.display_name = "1. First Blood"
	m.briefing = "Seize the highway towns and capture Vale's outpost HQ."
	m.par_days = 8
	m.player_co = &"vale"
	m.enemy_co = &"vale"
	m.difficulty = &"easy"
	m.player_funds = 3000
	m.map = _make_map(
		m.key,
		m.display_name,
		[
			"..f...f...",
			".HF===c.c.",
			"..=.^...=.",
			"..=c..c.=.",
			"..=...^.=.",
			".c.c===FH.",
			"..f...f...",
		],
		{Vector2i(1, 1): 0, Vector2i(2, 1): 0, Vector2i(7, 5): 1, Vector2i(8, 5): 1},
		[
			{"team": 0, "type": &"infantry", "x": 3, "y": 1},
			{"team": 0, "type": &"tank", "x": 2, "y": 2},
			{"team": 0, "type": &"mech", "x": 2, "y": 3},
			{"team": 1, "type": &"infantry", "x": 6, "y": 5},
			{"team": 1, "type": &"tank", "x": 7, "y": 4},
		]
	)
	return m


static func _m2_bridgehead() -> MissionDef:
	var m := MissionDef.new()
	m.key = &"m2_bridgehead"
	m.display_name = "2. Bridgehead"
	m.briefing = "Rook holds the east bank. Shell the bridges with Artillery and break through!"
	m.par_days = 10
	m.player_co = &"nova"
	m.enemy_co = &"rook"
	m.difficulty = &"normal"
	m.player_funds = 5000
	m.map = _make_map(
		m.key,
		m.display_name,
		[
			"..f..r..f...",
			".HF==B==c...",
			".F.^.r.^.c..",
			"..c..r..T...",
			"..^..r..^...",
			".c===B===FH.",
			"..f..r..f...",
		],
		{
			Vector2i(1, 1): 0,
			Vector2i(2, 1): 0,
			Vector2i(1, 2): 0,
			Vector2i(9, 5): 1,
			Vector2i(10, 5): 1,
			Vector2i(8, 3): 1,
		},
		[
			{"team": 0, "type": &"infantry", "x": 3, "y": 1},
			{"team": 0, "type": &"tank", "x": 4, "y": 1},
			{"team": 0, "type": &"artillery", "x": 3, "y": 2},
			{"team": 0, "type": &"mech", "x": 3, "y": 5},
			{"team": 1, "type": &"tank", "x": 6, "y": 1},
			{"team": 1, "type": &"artillery", "x": 7, "y": 2},
			{"team": 1, "type": &"infantry", "x": 7, "y": 5},
			{"team": 1, "type": &"tank", "x": 6, "y": 5},
		]
	)
	return m


static func _m3_silo_race() -> MissionDef:
	var m := MissionDef.new()
	m.key = &"m3_silo_race"
	m.display_name = "3. Silo Race"
	m.briefing = "Beat Blitz to the central Missile Silos before his spearhead rolls over you!"
	m.par_days = 10
	m.player_co = &"vale"
	m.enemy_co = &"blitz"
	m.difficulty = &"normal"
	m.player_funds = 4000
	m.enemy_funds = 4000
	m.map = _make_map(
		m.key,
		m.display_name,
		[
			"..f======f..",
			".HF.c..c.F..",
			"..=..S...=..",
			"..=.T..T.=..",
			"..=...S..=..",
			"..F.c..c.FH.",
			"..f======f..",
		],
		{
			Vector2i(1, 1): 0,
			Vector2i(2, 1): 0,
			Vector2i(2, 5): 0,
			Vector2i(9, 1): 1,
			Vector2i(9, 5): 1,
			Vector2i(10, 5): 1,
		},
		[
			{"team": 0, "type": &"infantry", "x": 3, "y": 2},
			{"team": 0, "type": &"apc", "x": 2, "y": 2},
			{"team": 0, "type": &"tank", "x": 3, "y": 4},
			{"team": 1, "type": &"infantry", "x": 8, "y": 4},
			{"team": 1, "type": &"tank", "x": 8, "y": 2},
			{"team": 1, "type": &"recon", "x": 7, "y": 2},
		]
	)
	return m


static func _m4_fog_ambush() -> MissionDef:
	var m := MissionDef.new()
	m.key = &"m4_fog_ambush"
	m.display_name = "4. Fog Ambush"
	m.briefing = "Shade's scouts lurk in the woods under Fog of War. Scout ahead with Recons!"
	m.par_days = 11
	m.player_co = &"shade"
	m.enemy_co = &"shade"
	m.difficulty = &"normal"
	m.fog = true
	m.player_funds = 5000
	m.map = _make_map(
		m.key,
		m.display_name,
		[
			"..ff....ff..",
			".HF=f..f=c..",
			"..=.fccf.=..",
			".c=f.TT.f=c.",
			"..=.fccf.=..",
			"..c=f..f=FH.",
			"..ff....ff..",
		],
		{Vector2i(1, 1): 0, Vector2i(2, 1): 0, Vector2i(9, 5): 1, Vector2i(10, 5): 1},
		[
			{"team": 0, "type": &"recon", "x": 3, "y": 1},
			{"team": 0, "type": &"infantry", "x": 2, "y": 2},
			{"team": 0, "type": &"tank", "x": 3, "y": 3},
			{"team": 0, "type": &"artillery", "x": 1, "y": 2},
			{"team": 1, "type": &"recon", "x": 7, "y": 2},
			{"team": 1, "type": &"tank", "x": 7, "y": 4},
			{"team": 1, "type": &"infantry", "x": 8, "y": 5},
			{"team": 1, "type": &"artillery", "x": 9, "y": 4},
		]
	)
	return m


static func _m5_iron_armada() -> MissionDef:
	var m := MissionDef.new()
	m.key = &"m5_iron_armada"
	m.display_name = "5. Iron Armada"
	m.briefing = "Command Ports and Airports to shatter Aero's air-sea blockade!"
	m.par_days = 12
	m.player_co = &"aero"
	m.enemy_co = &"aero"
	m.difficulty = &"normal"
	m.player_funds = 10000
	m.enemy_funds = 8000
	m.map = _make_map(
		m.key,
		m.display_name,
		[
			"~~~..====..~~~",
			"~~.HF=c.P..~~~",
			"~.PA..~~~.B.~~",
			"~..=..~c~.=..~",
			"~..=.~.T.~=..~",
			"~~.B..~~~..AP~",
			"~~~..P.c=FH.~~",
			"~~~..====..~~~",
		],
		{
			Vector2i(3, 1): 0,
			Vector2i(4, 1): 0,
			Vector2i(2, 2): 0,
			Vector2i(3, 2): 0,
			Vector2i(9, 6): 1,
			Vector2i(10, 6): 1,
			Vector2i(11, 5): 1,
			Vector2i(12, 5): 1,
		},
		[
			{"team": 0, "type": &"cruiser", "x": 1, "y": 2},
			{"team": 0, "type": &"battleship", "x": 1, "y": 3},
			{"team": 0, "type": &"copter", "x": 4, "y": 2},
			{"team": 0, "type": &"infantry", "x": 5, "y": 1},
			{"team": 1, "type": &"cruiser", "x": 12, "y": 4},
			{"team": 1, "type": &"copter", "x": 10, "y": 5},
			{"team": 1, "type": &"anti_air", "x": 9, "y": 5},
			{"team": 1, "type": &"infantry", "x": 8, "y": 6},
		]
	)
	return m


static func _m6_citadel_siege() -> MissionDef:
	var m := MissionDef.new()
	m.key = &"m6_citadel_siege"
	m.display_name = "6. Citadel Siege"
	m.briefing = "Storm Nova's fortified central citadel with two flanking factories!"
	m.par_days = 12
	m.player_co = &"midas"
	m.enemy_co = &"nova"
	m.difficulty = &"hard"
	m.player_funds = 10000
	m.enemy_funds = 5000
	m.map = _make_map(
		m.key,
		m.display_name,
		[
			".F==c....c==F.",
			".H..=.^^.=..A.",
			"..c.=cTTc=.c..",
			"..f.=.FH.=.f..",
			"..c.=c..c=.c..",
			"....=....=....",
			"..===.S..===..",
		],
		{
			Vector2i(1, 0): 0,
			Vector2i(1, 1): 0,
			Vector2i(12, 0): 0,
			Vector2i(12, 1): 0,
			Vector2i(6, 3): 1,
			Vector2i(7, 3): 1,
			Vector2i(6, 2): 1,
			Vector2i(7, 2): 1,
			Vector2i(5, 2): 1,
			Vector2i(8, 2): 1,
		},
		[
			{"team": 0, "type": &"md_tank", "x": 2, "y": 0},
			{"team": 0, "type": &"tank", "x": 11, "y": 0},
			{"team": 0, "type": &"infantry", "x": 3, "y": 1},
			{"team": 0, "type": &"copter", "x": 11, "y": 1},
			{"team": 1, "type": &"rockets", "x": 6, "y": 2},
			{"team": 1, "type": &"artillery", "x": 7, "y": 2},
			{"team": 1, "type": &"md_tank", "x": 6, "y": 4},
			{"team": 1, "type": &"anti_air", "x": 7, "y": 4},
		]
	)
	return m


# =============================================================================
# TACTICAL PUZZLES ("Win in N Turns")
# =============================================================================


static func _p1_bridge_breach() -> MissionDef:
	var p := MissionDef.new()
	p.key = &"p1_bridge_breach"
	p.display_name = "Puzzle 1: Bridge Breach"
	p.briefing = "Win in 1 turn! Shell the enemy Tank blocking the bridge, then finish it off."
	p.is_puzzle = true
	p.turn_limit = 1
	p.par_days = 1
	p.player_co = &"nova"
	p.enemy_co = &"vale"
	p.map = _make_map(
		p.key,
		p.display_name,
		[
			"...r...",
			".H=B=H.",
			"...r...",
			"...r...",
		],
		{Vector2i(1, 1): 0, Vector2i(5, 1): 1},
		[
			{"team": 0, "type": &"artillery", "x": 1, "y": 1},
			{"team": 0, "type": &"md_tank", "x": 2, "y": 1},
			{"team": 1, "type": &"tank", "x": 3, "y": 1},
		]
	)
	return p


static func _p2_missile_strike() -> MissionDef:
	var p := MissionDef.new()
	p.key = &"p2_missile_strike"
	p.display_name = "Puzzle 2: Silo Strike"
	p.briefing = "Win in 1 turn! Launch the Missile Silo to soften the defenders, then wipe them out."
	p.is_puzzle = true
	p.turn_limit = 1
	p.par_days = 1
	p.player_co = &"vale"
	p.enemy_co = &"vale"
	p.map = _make_map(
		p.key,
		p.display_name,
		[
			"........",
			".H.S..H.",
			"....===.",
			"........",
		],
		{Vector2i(1, 1): 0, Vector2i(6, 1): 1},
		[
			{"team": 0, "type": &"infantry", "x": 2, "y": 1},
			{"team": 0, "type": &"bomber", "x": 3, "y": 2},
			{"team": 0, "type": &"md_tank", "x": 4, "y": 2},
			{"team": 1, "type": &"md_tank", "x": 6, "y": 1},
			{"team": 1, "type": &"tank", "x": 6, "y": 2},
		]
	)
	return p


static func _p3_artillery_check() -> MissionDef:
	var p := MissionDef.new()
	p.key = &"p3_artillery_check"
	p.display_name = "Puzzle 3: Range Extension"
	p.briefing = ("Win in 1 turn! Activate Nova's Firestorm (+2 range) to destroy the enemy Rocket!")
	p.is_puzzle = true
	p.turn_limit = 1
	p.par_days = 1
	p.player_co = &"nova"
	p.enemy_co = &"vale"
	p.initial_player_meter = 600
	p.map = _make_map(
		p.key,
		p.display_name,
		[
			"....r....",
			".H..r..H.",
			"....r....",
		],
		{Vector2i(1, 1): 0, Vector2i(7, 1): 1},
		[
			{"team": 0, "type": &"rockets", "x": 1, "y": 1},
			{"team": 0, "type": &"artillery", "x": 2, "y": 1},
			{"team": 1, "type": &"rockets", "x": 7, "y": 1},
		]
	)
	return p


static func _p4_lightning_rush() -> MissionDef:
	var p := MissionDef.new()
	p.key = &"p4_lightning_rush"
	p.display_name = "Puzzle 4: Double Strike"
	p.briefing = "Win in 1 turn! Strike, then fire Blitz's Super to refresh and finish!"
	p.is_puzzle = true
	p.turn_limit = 1
	p.par_days = 1
	p.player_co = &"blitz"
	p.enemy_co = &"rook"
	p.initial_player_meter = 600
	p.map = _make_map(
		p.key,
		p.display_name,
		[
			".........",
			".H=====H.",
			".........",
		],
		{Vector2i(1, 1): 0, Vector2i(7, 1): 1},
		[
			{"team": 0, "type": &"md_tank", "x": 2, "y": 1},
			{"team": 1, "type": &"md_tank", "x": 7, "y": 1},
		]
	)
	return p
