class_name MovementClass
extends Resource
## How a unit moves. The `key` selects this class's row in
## TerrainType.move_costs; the cost numbers themselves live on the terrain,
## not here.

@export var key: StringName = &""  # stable id for save files
@export var display_name: String = ""
