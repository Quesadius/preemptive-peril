class_name Events
extends RefCounted
## Concrete GameEvent types (§5), namespaced as inner classes — the file
## tree keeps them in one file, so presentation matches with
## `event is Events.UnitMoved`. Only the events emitted by implemented
## rules exist; the rest of the §5 contract arrives with its milestones.
##
## Field conventions: ids are unit ids; `interrupted_at` is an index into
## `path` (-1 = uninterrupted); in UnitCounterattacked, `attacker_id` is
## the countering unit (the original defender).


class UnitMoved:
	extends GameEvent
	var unit_id: int
	var path: Array[Vector2i] = []
	var interrupted_at: int = -1

	func _init(p_unit_id: int, p_path: Array[Vector2i], p_interrupted_at: int = -1) -> void:
		unit_id = p_unit_id
		path = p_path
		interrupted_at = p_interrupted_at


class UnitAmbushed:
	extends GameEvent
	var unit_id: int
	var by_unit_id: int
	var coord: Vector2i  # the ambusher's tile

	func _init(p_unit_id: int, p_by_unit_id: int, p_coord: Vector2i) -> void:
		unit_id = p_unit_id
		by_unit_id = p_by_unit_id
		coord = p_coord


class UnitAttacked:
	extends GameEvent
	var attacker_id: int
	var defender_id: int
	var damage: int
	var ammo_used: int

	func _init(p_attacker_id: int, p_defender_id: int, p_damage: int, p_ammo_used: int) -> void:
		attacker_id = p_attacker_id
		defender_id = p_defender_id
		damage = p_damage
		ammo_used = p_ammo_used


class UnitCounterattacked:
	extends GameEvent
	var attacker_id: int
	var defender_id: int
	var damage: int

	func _init(p_attacker_id: int, p_defender_id: int, p_damage: int) -> void:
		attacker_id = p_attacker_id
		defender_id = p_defender_id
		damage = p_damage


class UnitDestroyed:
	extends GameEvent
	var unit_id: int
	var coord: Vector2i
	var team: int  # extension beyond §5: victory checks need the loser

	func _init(p_unit_id: int, p_coord: Vector2i, p_team: int) -> void:
		unit_id = p_unit_id
		coord = p_coord
		team = p_team


class UnitExhausted:
	extends GameEvent
	var unit_id: int

	func _init(p_unit_id: int) -> void:
		unit_id = p_unit_id


class TurnStarted:
	extends GameEvent
	var team: int
	var day: int

	func _init(p_team: int, p_day: int) -> void:
		team = p_team
		day = p_day


class TurnEnded:
	extends GameEvent
	var team: int

	func _init(p_team: int) -> void:
		team = p_team


class UnitCreated:
	extends GameEvent
	var unit_id: int
	var type_id: int
	var team: int
	var coord: Vector2i

	func _init(p_unit_id: int, p_type_id: int, p_team: int, p_coord: Vector2i) -> void:
		unit_id = p_unit_id
		type_id = p_type_id
		team = p_team
		coord = p_coord


class CaptureProgressed:
	extends GameEvent
	var coord: Vector2i
	var unit_id: int
	var points: int
	var total: int

	func _init(p_coord: Vector2i, p_unit_id: int, p_points: int, p_total: int) -> void:
		coord = p_coord
		unit_id = p_unit_id
		points = p_points
		total = p_total


class PropertyCaptured:
	extends GameEvent
	var coord: Vector2i
	var new_team: int
	var old_team: int

	func _init(p_coord: Vector2i, p_new_team: int, p_old_team: int) -> void:
		coord = p_coord
		new_team = p_new_team
		old_team = p_old_team


class FundsChanged:
	extends GameEvent
	var team: int
	var delta: int
	var new_total: int
	var reason: StringName

	func _init(p_team: int, p_delta: int, p_new_total: int, p_reason: StringName) -> void:
		team = p_team
		delta = p_delta
		new_total = p_new_total
		reason = p_reason


class UnitLoaded:
	extends GameEvent
	var unit_id: int
	var carrier_id: int

	func _init(p_unit_id: int, p_carrier_id: int) -> void:
		unit_id = p_unit_id
		carrier_id = p_carrier_id


class UnitUnloaded:
	extends GameEvent
	var unit_id: int
	var carrier_id: int
	var coord: Vector2i

	func _init(p_unit_id: int, p_carrier_id: int, p_coord: Vector2i) -> void:
		unit_id = p_unit_id
		carrier_id = p_carrier_id
		coord = p_coord


class UnitJoined:
	extends GameEvent
	var survivor_id: int
	var absorbed_id: int
	var new_hp: int
	var funds_refund: int

	func _init(p_survivor_id: int, p_absorbed_id: int, p_new_hp: int, p_refund: int) -> void:
		survivor_id = p_survivor_id
		absorbed_id = p_absorbed_id
		new_hp = p_new_hp
		funds_refund = p_refund


class UnitResupplied:
	extends GameEvent
	var unit_id: int
	var fuel: int
	var ammo: int

	func _init(p_unit_id: int, p_fuel: int, p_ammo: int) -> void:
		unit_id = p_unit_id
		fuel = p_fuel
		ammo = p_ammo


class UnitRepaired:
	extends GameEvent
	var unit_id: int
	var hp_restored: int
	var cost: int

	func _init(p_unit_id: int, p_hp_restored: int, p_cost: int) -> void:
		unit_id = p_unit_id
		hp_restored = p_hp_restored
		cost = p_cost


class UnitFuelDrained:
	extends GameEvent
	var unit_id: int  # extension beyond §5: daily drain needs an event too
	var amount: int
	var fuel_left: int

	func _init(p_unit_id: int, p_amount: int, p_fuel_left: int) -> void:
		unit_id = p_unit_id
		amount = p_amount
		fuel_left = p_fuel_left


class PowerCharged:
	extends GameEvent
	var team: int
	var delta: int
	var new_total: int

	func _init(p_team: int, p_delta: int, p_new_total: int) -> void:
		team = p_team
		delta = p_delta
		new_total = p_new_total


class PowerActivated:
	extends GameEvent
	var team: int
	var level: int  # PlayerState.PowerState value
	var co_id: int

	func _init(p_team: int, p_level: int, p_co_id: int) -> void:
		team = p_team
		level = p_level
		co_id = p_co_id


class PowerExpired:
	extends GameEvent
	var team: int

	func _init(p_team: int) -> void:
		team = p_team


class WeatherChanged:
	extends GameEvent
	var new_weather: int  # GameState.Weather value
	var days: int

	func _init(p_new_weather: int, p_days: int) -> void:
		new_weather = p_new_weather
		days = p_days


class PlayerEliminated:
	extends GameEvent
	var team: int
	var reason: StringName

	func _init(p_team: int, p_reason: StringName) -> void:
		team = p_team
		reason = p_reason


class GameEnded:
	extends GameEvent
	var winning_team: int
	var reason: StringName

	func _init(p_winning_team: int, p_reason: StringName) -> void:
		winning_team = p_winning_team
		reason = p_reason
