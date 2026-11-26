class_name Threat
extends RefCounted
## "What can reach/hit this tile" queries (§2). danger_zone() powers the
## UI's enemy-range inspection; the inverse per-tile query joins it when
## AI stage 3 needs it. Built on Movement and Combat so there is exactly
## one implementation of range legality.


## Every tile `unit_id` could attack with its next action: the union of
## attack rings over every destination it could actually stop on (just
## its own tile for units that cannot move and fire). Empty for unarmed
## units and for dry ones with no ammo-free fallback. When `viewer_team`
## >= 0, reachability and stoppable occupancy use only what `viewer_team`
## can see under fog — never leaking hidden enemies or enemy vision.
## Deterministic row-major order.
static func danger_zone(
	state: GameState,
	unit_id: int,
	viewer_team: int = -1,
	viewer_mask: PackedByteArray = PackedByteArray()
) -> Array[Vector2i]:
	var unit: UnitState = state.units[unit_id]
	if not _armed(state, unit):
		return []
	var unit_type: UnitType = state.ruleset.unit_types[unit.type_id]
	var stands: Array[Vector2i] = [unit.coord]
	if unit_type.can_move_and_fire:
		stands = []
		var mask := viewer_mask
		if viewer_team >= 0 and mask.is_empty():
			mask = Fog.mask_for(state, viewer_team)
		var reach := Movement.reachable(state, unit_id, viewer_team, mask)
		for dest: Vector2i in reach:
			var occupant: UnitState = (
				Fog.known_occupant(state, viewer_team, dest, mask)
				if viewer_team >= 0
				else state.unit_at(dest)
			)
			if occupant == null or occupant == unit:
				stands.append(dest)
	var zone: Dictionary[Vector2i, bool] = {}
	for stand: Vector2i in stands:
		for c: Vector2i in Combat.attackable_tiles(state, unit_id, stand):
			zone[c] = true
	var out: Array[Vector2i] = []
	out.assign(zone.keys())
	out.sort_custom(_row_major)
	return out


## The combined danger zone of every enemy `viewing_team` can see —
## the full-board threat overlay. Loaded passengers project nothing;
## under fog, hidden enemies stay out and enemy reachability never leaks
## hidden units or enemy vision (an honest map, not an oracle).
## Deterministic row-major order.
static func team_danger_zone(state: GameState, viewing_team: int) -> Array[Vector2i]:
	var zone: Dictionary[Vector2i, bool] = {}
	var mask := Fog.mask_for(state, viewing_team)
	for uid: int in state.units:
		var unit: UnitState = state.units[uid]
		if unit.team == viewing_team or unit.carrier_id != -1:
			continue
		if not Fog.sees_unit(state, viewing_team, unit, mask):
			continue
		for c: Vector2i in danger_zone(state, uid, viewing_team, mask):
			zone[c] = true
	var out: Array[Vector2i] = []
	out.assign(zone.keys())
	out.sort_custom(_row_major)
	return out


## True when the unit has any weapon it could actually fire: a damage
## table with entries, and ammo if the weapon needs it.
static func _armed(state: GameState, unit: UnitState) -> bool:
	var unit_type: UnitType = state.ruleset.unit_types[unit.type_id]
	for w: WeaponProfile in [unit_type.primary_weapon, unit_type.secondary_weapon]:
		if w == null or w.damage_table == null or w.damage_table.base_damage.is_empty():
			continue
		if w.uses_ammo and unit.ammo <= 0:
			continue
		return true
	return false


static func _row_major(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)
