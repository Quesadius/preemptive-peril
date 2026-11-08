class_name BuildAction
extends Action
## Builds a unit at one of the active player's production facilities
## (§4): the coord must be an owned, unoccupied factory-like property
## whose build key appears in the unit type's `built_at`.

var unit_type_id: int
var coord: Vector2i
