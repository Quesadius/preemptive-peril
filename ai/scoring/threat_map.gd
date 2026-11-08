class_name ThreatMap
extends RefCounted
## Stage-2 scoring map (§10): for a given unit type, how hard could the
## enemy hit each tile next turn? For every visible enemy: the union of
## its reachable destinations' attack rings, carrying the best base
## damage its weapons land on the queried type. Values are base damage
## (0..130); tiles no enemy can touch are absent.


## Threat against `versus_type_id` for `team`, from everything the view
## can see. Deterministic; cache per decision loop, not here. Enemy
## movement doesn't depend on the queried type, so callers building
## several maps per decision can share `reach_cache` (enemy id ->
## reachable set) across calls; it is filled on demand.
static func compute(
	view: StateView, team: int, versus_type_id: int, reach_cache: Dictionary[int, Dictionary] = {}
) -> Dictionary[Vector2i, int]:
	var out: Dictionary[Vector2i, int] = {}
	var versus_key: StringName = view.ruleset().unit_types[versus_type_id].key
	for enemy: UnitState in view.visible_units():
		if enemy.team == team:
			continue
		var base: int = _best_base(view.ruleset(), enemy, versus_key)
		if base <= 0:
			continue
		var enemy_type: UnitType = view.ruleset().unit_types[enemy.type_id]
		var stands: Array[Vector2i] = [enemy.coord]
		if enemy_type.can_move_and_fire:
			if not reach_cache.has(enemy.id):
				reach_cache[enemy.id] = view.reachable_of(enemy.id)
			stands = []
			stands.assign(reach_cache[enemy.id].keys())
		for stand: Vector2i in stands:
			var ring := Grid.coords_in_range(
				stand, enemy_type.attack_range_min, enemy_type.attack_range_max
			)
			for c: Vector2i in ring:
				if not view.map().in_bounds(c):
					continue
				if not out.has(c) or out[c] < base:
					out[c] = base
	return out


## The strongest base damage `enemy` can put on `versus_key`, assuming
## it keeps its ammo. 0 when it cannot hurt that type at all.
static func _best_base(ruleset: Ruleset, enemy: UnitState, versus_key: StringName) -> int:
	var enemy_type: UnitType = ruleset.unit_types[enemy.type_id]
	var best: int = 0
	for w: WeaponProfile in [enemy_type.primary_weapon, enemy_type.secondary_weapon]:
		if w == null or w.damage_table == null:
			continue
		if w.uses_ammo and enemy.ammo <= 0:
			continue
		if w.damage_table.base_damage.has(versus_key):
			best = maxi(best, w.damage_table.base_damage[versus_key])
	return best
