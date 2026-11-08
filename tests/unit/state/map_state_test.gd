extends GdUnitTestSuite
## Tests for MapState on hand-built fixtures no larger than 5x5.


func _make_map(w: int, h: int) -> MapState:
	var m := MapState.new()
	m.width = w
	m.height = h
	var t := PackedInt32Array()
	t.resize(w * h)
	m.terrain = t
	var owners := PackedInt32Array()
	owners.resize(w * h)
	owners.fill(MapState.NO_OWNER)
	m.property_owner = owners
	return m


func test_idx_row_major() -> void:
	var m := _make_map(5, 5)
	assert_int(m.idx(Vector2i(0, 0))).is_equal(0)
	assert_int(m.idx(Vector2i(4, 0))).is_equal(4)
	assert_int(m.idx(Vector2i(0, 1))).is_equal(5)
	assert_int(m.idx(Vector2i(3, 2))).is_equal(13)
	assert_int(m.idx(Vector2i(4, 4))).is_equal(24)


func test_in_bounds_rectangular() -> void:
	var m := _make_map(5, 3)
	assert_bool(m.in_bounds(Vector2i(0, 0))).is_true()
	assert_bool(m.in_bounds(Vector2i(4, 2))).is_true()
	assert_bool(m.in_bounds(Vector2i(5, 0))).is_false()
	assert_bool(m.in_bounds(Vector2i(0, 3))).is_false()
	assert_bool(m.in_bounds(Vector2i(-1, 1))).is_false()
	assert_bool(m.in_bounds(Vector2i(1, -1))).is_false()


func test_terrain_at_reads_written_tile() -> void:
	var m := _make_map(5, 5)
	m.terrain[m.idx(Vector2i(2, 1))] = 3
	assert_int(m.terrain_at(Vector2i(2, 1))).is_equal(3)
	assert_int(m.terrain_at(Vector2i(1, 2))).is_equal(0)


func test_is_property_false_when_unowned() -> void:
	var m := _make_map(5, 5)
	for y: int in range(5):
		for x: int in range(5):
			assert_bool(m.is_property(Vector2i(x, y))).is_false()


func test_is_property_true_once_owned() -> void:
	var m := _make_map(5, 5)
	m.property_owner[m.idx(Vector2i(1, 1))] = 0
	assert_bool(m.is_property(Vector2i(1, 1))).is_true()
	assert_bool(m.is_property(Vector2i(2, 1))).is_false()


func test_capture_progress_starts_empty() -> void:
	assert_int(_make_map(5, 5).capture_progress.size()).is_equal(0)


func test_clone_is_deep() -> void:
	var m := _make_map(5, 5)
	m.terrain[0] = 9
	m.property_owner[3] = 1
	m.capture_progress[Vector2i(1, 1)] = 10
	var c := m.clone()
	assert_int(c.width).is_equal(5)
	assert_int(c.height).is_equal(5)
	assert_int(c.terrain_at(Vector2i(0, 0))).is_equal(9)
	assert_bool(c.is_property(Vector2i(3, 0))).is_true()
	assert_int(c.capture_progress[Vector2i(1, 1)]).is_equal(10)
	# Mutating the original must not leak into the clone…
	m.terrain[0] = 2
	m.property_owner[3] = MapState.NO_OWNER
	m.capture_progress[Vector2i(1, 1)] = 19
	assert_int(c.terrain_at(Vector2i(0, 0))).is_equal(9)
	assert_bool(c.is_property(Vector2i(3, 0))).is_true()
	assert_int(c.capture_progress[Vector2i(1, 1)]).is_equal(10)
	# …and mutating the clone must not leak back.
	c.terrain[24] = 5
	assert_int(m.terrain_at(Vector2i(4, 4))).is_equal(0)
