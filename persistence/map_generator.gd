class_name MapGenerator
extends RefCounted
## Seeded symmetric random skirmish map generator. Every generated map is
## 180-degree rotationally symmetric (guaranteed fair holdings and opening
## armies) and deterministic for a given (preset, seed).

const PRESETS: Array[StringName] = [&"open", &"river", &"mountains", &"islands"]

const PRESET_NAMES: Dictionary[StringName, String] = {
	&"open": "Open Plains",
	&"river": "River Crossing",
	&"mountains": "Mountain Pass",
	&"islands": "Coastal Sea",
}


## Builds a deterministic symmetric MapDefinition for `preset` and `seed_val`.
static func generate(preset: StringName, seed_val: int, w: int = 12, h: int = 10) -> MapDefinition:
	var rng := DeterministicRng.new(maxi(1, abs(seed_val)))
	var palette: Array[StringName] = [
		&"plains",
		&"road",
		&"forest",
		&"mountain",
		&"city",
		&"factory",
		&"hq",
		&"airport",
		&"sea",
		&"river",
		&"bridge",
		&"port",
		&"comms_tower",
		&"silo",
	]
	var terrain := PackedInt32Array()
	terrain.resize(w * h)
	terrain.fill(0)
	var owners := PackedInt32Array()
	owners.resize(w * h)
	owners.fill(-1)

	# 1. Paint symmetric natural terrain on the left half, mirrored 180 degrees.
	@warning_ignore("integer_division")
	var mid_x: int = w / 2
	for y: int in range(h):
		for x: int in range(mid_x):
			var roll: int = rng.roll_range(0, 99)
			var tid: int = 0
			match preset:
				&"mountains":
					if roll < 22:
						tid = 3  # mountain
					elif roll < 38:
						tid = 2  # forest
				&"river":
					if x == mid_x - 1:
						tid = 9  # river down the center
					elif roll < 18:
						tid = 2
					elif roll < 26:
						tid = 3
				&"islands":
					if x == mid_x - 1 and y > 1 and y < h - 2:
						tid = 8  # central sea channel
					elif y == 0 or y == h - 1:
						tid = 8 if x > 2 else 0
					elif roll < 16:
						tid = 2
					elif roll < 22:
						tid = 3
				_:
					if roll < 18:
						tid = 2  # forest
					elif roll < 28:
						tid = 3  # mountain
			_set_sym(terrain, w, h, Vector2i(x, y), tid)

	# 2. Carve guaranteed road + bridge corridors across the map.
	var lane_a: int = 2
	var lane_b: int = h - 3
	for x: int in range(1, w - 1):
		for ly: int in [lane_a, lane_b]:
			var cur: int = terrain[ly * w + x]
			if cur == 8 or cur == 9:
				terrain[ly * w + x] = 10  # bridge
			else:
				terrain[ly * w + x] = 1  # road
	for y: int in range(1, h - 1):
		for lx: int in [2, w - 3]:
			var cur: int = terrain[y * w + lx]
			if cur != 8 and cur != 9 and cur != 10:
				terrain[y * w + lx] = 1

	# 3. Place bases symmetrically (HQ, 2 Factories, optional Airport/Port).
	_place_owned_sym(terrain, owners, w, h, Vector2i(1, 1), 6)  # HQ
	_place_owned_sym(terrain, owners, w, h, Vector2i(1, 2), 5)  # Factory 1
	_place_owned_sym(terrain, owners, w, h, Vector2i(2, 1), 5)  # Factory 2
	if preset == &"islands":
		_place_owned_sym(terrain, owners, w, h, Vector2i(mid_x - 2, 1), 11)  # Port
		_set_sym(terrain, w, h, Vector2i(mid_x - 1, 1), 8)  # adjacent sea for port
		_place_owned_sym(terrain, owners, w, h, Vector2i(1, 4), 7)  # Airport
	elif preset == &"mountains":
		_place_owned_sym(terrain, owners, w, h, Vector2i(1, 3), 7)  # Airport

	# 4. Place symmetric neutral cities, a Comms Tower, and a Missile Silo.
	var city_candidates: Array[Vector2i] = [
		Vector2i(3, 1),
		Vector2i(1, h - 2),
		Vector2i(3, h - 3),
		Vector2i(4, 3),
		Vector2i(2, h - 2),
	]
	var placed: int = 0
	for c: Vector2i in city_candidates:
		if placed >= 3:
			break
		if c.x < mid_x and owners[c.y * w + c.x] == -1 and terrain[c.y * w + c.x] < 8:
			_set_sym(terrain, w, h, c, 4)  # city
			placed += 1

	# Contested center Comms Tower & Silo (off-water)
	@warning_ignore("integer_division")
	var cy: int = h / 2
	var comms_c := Vector2i(maxi(3, mid_x - 2), cy - 1)
	var silo_c := Vector2i(maxi(3, mid_x - 2), cy + 1)
	if owners[comms_c.y * w + comms_c.x] == -1:
		_set_sym(terrain, w, h, comms_c, 12)  # comms_tower
	if owners[silo_c.y * w + silo_c.x] == -1:
		_set_sym(terrain, w, h, silo_c, 13)  # silo

	# 5. Balanced symmetric starting army.
	var units: Array[Dictionary] = []
	var spawns: Array[Dictionary] = [
		{"type": &"infantry", "x": 2, "y": 2},
		{"type": &"infantry", "x": 3, "y": 2},
		{"type": &"tank", "x": 2, "y": 3},
	]
	if preset == &"river":
		spawns.append({"type": &"artillery", "x": 1, "y": 3})
	elif preset == &"mountains":
		spawns.append({"type": &"mech", "x": 3, "y": 3})
	elif preset == &"islands":
		spawns.append({"type": &"cruiser", "x": mid_x - 1, "y": 1})
	else:
		spawns.append({"type": &"recon", "x": 3, "y": 3})

	for s: Dictionary in spawns:
		var sx: int = s["x"]
		var sy: int = s["y"]
		units.append({"team": 0, "type": s["type"], "x": sx, "y": sy})
		units.append({"team": 1, "type": s["type"], "x": w - 1 - sx, "y": h - 1 - sy})

	var def := MapDefinition.new()
	def.key = StringName("random_%s_%d" % [String(preset), seed_val])
	def.display_name = "%s #%d" % [PRESET_NAMES.get(preset, "Random"), seed_val % 1000]
	def.width = w
	def.height = h
	def.terrain_palette = palette
	def.terrain = terrain
	def.property_owner = owners
	def.starting_units = units
	return def


static func _set_sym(grid: PackedInt32Array, w: int, h: int, c: Vector2i, val: int) -> void:
	grid[c.y * w + c.x] = val
	grid[(h - 1 - c.y) * w + (w - 1 - c.x)] = val


static func _place_owned_sym(
	terrain: PackedInt32Array, owners: PackedInt32Array, w: int, h: int, c: Vector2i, tid: int
) -> void:
	terrain[c.y * w + c.x] = tid
	owners[c.y * w + c.x] = 0
	var mc := Vector2i(w - 1 - c.x, h - 1 - c.y)
	terrain[mc.y * w + mc.x] = tid
	owners[mc.y * w + mc.x] = 1
