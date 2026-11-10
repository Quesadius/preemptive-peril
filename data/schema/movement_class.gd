class_name MovementClass
extends Resource
## How a unit moves. The `key` selects this class's row in
## TerrainType.move_costs; the cost numbers themselves live on the terrain,
## not here.

@export var key: StringName = &""  # stable id for save files
@export var display_name: String = ""
## Flying classes are above the terrain, not on it: no defense stars, no
## concealment from hiding terrain, no vision bonus from what is below.
@export var airborne: bool = false
