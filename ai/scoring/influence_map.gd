class_name InfluenceMap
extends RefCounted
## Stage-2 territory reading (§10): cost-weighted presence, spread three
## tiles with linear falloff. Positive = your side of the board,
## negative = theirs. Coarse on purpose — it shades decisions, it
## doesn't make them.

const SPREAD := 3


## Influence for `team` over every tile touched by anyone's presence.
static func compute(view: StateView, team: int) -> Dictionary[Vector2i, int]:
	var out: Dictionary[Vector2i, int] = {}
	for unit: UnitState in view.visible_units():
		@warning_ignore("integer_division")
		var weight: int = view.ruleset().unit_types[unit.type_id].cost / 100
		var polarity: int = 1 if unit.team == team else -1
		for c: Vector2i in Grid.coords_in_range(unit.coord, 0, SPREAD):
			if not view.map().in_bounds(c):
				continue
			var falloff: int = SPREAD + 1 - Grid.manhattan(unit.coord, c)
			@warning_ignore("integer_division")
			var add: int = polarity * weight * falloff / (SPREAD + 1)
			out[c] = out.get(c, 0) + add
	return out
