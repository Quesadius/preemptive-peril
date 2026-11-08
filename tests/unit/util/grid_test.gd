extends GdUnitTestSuite
## Tests for Grid. All expected values are hand-computed.


func test_manhattan_zero_for_identical_coords() -> void:
	assert_int(Grid.manhattan(Vector2i(3, 4), Vector2i(3, 4))).is_equal(0)


func test_manhattan_known_values() -> void:
	# |0 - 3| + |0 - 4| = 7
	assert_int(Grid.manhattan(Vector2i.ZERO, Vector2i(3, 4))).is_equal(7)
	# |-2 - 1| + |5 - 1| = 3 + 4 = 7
	assert_int(Grid.manhattan(Vector2i(-2, 5), Vector2i(1, 1))).is_equal(7)
	# A single step.
	assert_int(Grid.manhattan(Vector2i(2, 2), Vector2i(2, 3))).is_equal(1)


func test_manhattan_is_symmetric() -> void:
	var a := Vector2i(-3, 7)
	var b := Vector2i(4, -1)
	assert_int(Grid.manhattan(a, b)).is_equal(Grid.manhattan(b, a))


func test_neighbors_in_nesw_order() -> void:
	var got: Array[Vector2i] = Grid.neighbors(Vector2i(2, 2))
	var expected: Array[Vector2i] = [
		Vector2i(2, 1),
		Vector2i(3, 2),
		Vector2i(2, 3),
		Vector2i(1, 2),
	]
	assert_array(got).contains_exactly(expected)


func test_neighbors_is_not_bounds_filtered() -> void:
	var got: Array[Vector2i] = Grid.neighbors(Vector2i.ZERO)
	var expected: Array[Vector2i] = [
		Vector2i(0, -1),
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(-1, 0),
	]
	assert_array(got).contains_exactly(expected)


func test_in_bounds_5x5() -> void:
	assert_bool(Grid.in_bounds(Vector2i(0, 0), 5, 5)).is_true()
	assert_bool(Grid.in_bounds(Vector2i(4, 4), 5, 5)).is_true()
	assert_bool(Grid.in_bounds(Vector2i(4, 0), 5, 5)).is_true()
	assert_bool(Grid.in_bounds(Vector2i(-1, 0), 5, 5)).is_false()
	assert_bool(Grid.in_bounds(Vector2i(0, -1), 5, 5)).is_false()
	assert_bool(Grid.in_bounds(Vector2i(5, 0), 5, 5)).is_false()
	assert_bool(Grid.in_bounds(Vector2i(0, 5), 5, 5)).is_false()


func test_idx_row_major_width_5() -> void:
	assert_int(Grid.idx(Vector2i(0, 0), 5)).is_equal(0)
	assert_int(Grid.idx(Vector2i(4, 0), 5)).is_equal(4)
	assert_int(Grid.idx(Vector2i(0, 1), 5)).is_equal(5)
	assert_int(Grid.idx(Vector2i(2, 3), 5)).is_equal(17)
	assert_int(Grid.idx(Vector2i(4, 4), 5)).is_equal(24)


func test_from_idx_inverts_idx_on_5x5() -> void:
	for i: int in range(25):
		var c := Grid.from_idx(i, 5)
		assert_int(Grid.idx(c, 5)).is_equal(i)
	assert_that(Grid.from_idx(17, 5)).is_equal(Vector2i(2, 3))


func test_coords_in_range_radius_one_with_center() -> void:
	# min 0 includes the center; rows scan top to bottom, left to right.
	var got: Array[Vector2i] = Grid.coords_in_range(Vector2i.ZERO, 0, 1)
	var expected: Array[Vector2i] = [
		Vector2i(0, -1),
		Vector2i(-1, 0),
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(0, 1),
	]
	assert_array(got).contains_exactly(expected)


func test_coords_in_range_ring_excludes_inner_diamond() -> void:
	# Exactly distance 1 from (2, 2): the four cardinals, in scan order.
	var got: Array[Vector2i] = Grid.coords_in_range(Vector2i(2, 2), 1, 1)
	var expected: Array[Vector2i] = [
		Vector2i(2, 1),
		Vector2i(1, 2),
		Vector2i(3, 2),
		Vector2i(2, 3),
	]
	assert_array(got).contains_exactly(expected)


func test_coords_in_range_artillery_annulus() -> void:
	# 2..3 ring: 8 tiles at distance 2 plus 12 at distance 3 = 20.
	var center := Vector2i(10, 10)
	var got: Array[Vector2i] = Grid.coords_in_range(center, 2, 3)
	assert_array(got).has_size(20)
	for c: Vector2i in got:
		assert_int(Grid.manhattan(center, c)).is_between(2, 3)


func test_coords_in_range_empty_when_min_exceeds_max() -> void:
	assert_array(Grid.coords_in_range(Vector2i.ZERO, 2, 1)).is_empty()
