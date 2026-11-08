extends GdUnitTestSuite
## Tests for UnitState, in particular the internal-to-displayed HP mapping.


func test_spec_defaults() -> void:
	var u := UnitState.new()
	assert_int(u.hp).is_equal(100)
	assert_bool(u.has_moved).is_false()
	assert_bool(u.has_acted).is_false()
	assert_array(u.cargo).is_empty()
	assert_int(u.carrier_id).is_equal(-1)


func test_display_hp_hand_table() -> void:
	# Pairs of (internal hp, displayed hp) = ceil(hp / 10), worked out by hand.
	var cases: Array[Vector2i] = [
		Vector2i(100, 10),
		Vector2i(91, 10),
		Vector2i(90, 9),
		Vector2i(81, 9),
		Vector2i(80, 8),
		Vector2i(55, 6),
		Vector2i(50, 5),
		Vector2i(45, 5),
		Vector2i(41, 5),
		Vector2i(40, 4),
		Vector2i(11, 2),
		Vector2i(10, 1),
		Vector2i(9, 1),
		Vector2i(1, 1),
	]
	for pair: Vector2i in cases:
		var u := UnitState.new()
		u.hp = pair.x
		assert_int(u.display_hp()).append_failure_message("hp=%d" % pair.x).is_equal(pair.y)


func test_clone_copies_all_fields() -> void:
	var u := UnitState.new()
	u.id = 7
	u.type_id = 2
	u.team = 1
	u.coord = Vector2i(3, 4)
	u.hp = 55
	u.fuel = 40
	u.ammo = 6
	u.has_moved = true
	u.has_acted = true
	u.cargo.assign([11, 12])
	u.carrier_id = 5
	var c := u.clone()
	assert_object(c).is_not_same(u)
	assert_int(c.id).is_equal(7)
	assert_int(c.type_id).is_equal(2)
	assert_int(c.team).is_equal(1)
	assert_that(c.coord).is_equal(Vector2i(3, 4))
	assert_int(c.hp).is_equal(55)
	assert_int(c.fuel).is_equal(40)
	assert_int(c.ammo).is_equal(6)
	assert_bool(c.has_moved).is_true()
	assert_bool(c.has_acted).is_true()
	assert_array(c.cargo).contains_exactly([11, 12])
	assert_int(c.carrier_id).is_equal(5)


func test_clone_cargo_is_independent() -> void:
	var u := UnitState.new()
	u.cargo.assign([1])
	var c := u.clone()
	u.cargo.append(2)
	assert_array(c.cargo).contains_exactly([1])
	c.cargo.append(3)
	assert_array(u.cargo).contains_exactly([1, 2])
