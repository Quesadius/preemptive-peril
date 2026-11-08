class_name UnitState
extends RefCounted
## Per-unit mutable data.
##
## Internal HP runs 1..100; the displayed 1..10 value exists only through
## display_hp(). Advance Wars scales attack output and terrain defense by
## the displayed value while tracking damage at internal granularity, so
## presentation must never read `hp` raw.

var id: int
var type_id: int  # index into ruleset.unit_types
var team: int
var coord: Vector2i
var hp: int = 100  # internal 1..100
var fuel: int
var ammo: int
var has_moved: bool = false
var has_acted: bool = false  # exhausted this turn
var cargo: Array[int] = []  # unit ids being transported
var carrier_id: int = -1  # -1 if not loaded


## Displayed HP on the 1..10 scale used by combat and the UI.
func display_hp() -> int:
	return int(ceil(hp / 10.0))


## Deep copy; the cargo id list is duplicated.
func clone() -> UnitState:
	var copy := UnitState.new()
	copy.id = id
	copy.type_id = type_id
	copy.team = team
	copy.coord = coord
	copy.hp = hp
	copy.fuel = fuel
	copy.ammo = ammo
	copy.has_moved = has_moved
	copy.has_acted = has_acted
	copy.cargo.assign(cargo)
	copy.carrier_id = carrier_id
	return copy
