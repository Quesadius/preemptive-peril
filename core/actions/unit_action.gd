class_name UnitAction
extends Action
## A unit's move and its terminal verb as ONE atomic action (§4) — never
## split a move from what the unit does at the destination. The full path
## is carried (not just the destination) so fog ambushes can interrupt
## mid-path and the renderer can draw the exact traced arrow.

enum Verb { WAIT, ATTACK, CAPTURE, LOAD, UNLOAD, SUPPLY, JOIN, LAUNCH, REPAIR }

var unit_id: int
var path: Array[Vector2i] = []  # full path incl. start; last element is destination
var verb: int = Verb.WAIT
var target_coord: Vector2i  # attack target, unload destination
var cargo_index: int = -1  # which passenger, for UNLOAD
