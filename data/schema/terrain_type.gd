class_name TerrainType
extends Resource
## Terrain definition (architecture §7).

@export var key: StringName = &""  # stable id for save files
@export var display_name: String = ""
@export_range(0, 4) var defense_stars: int = 0
@export var is_property: bool = false
@export var capturable: bool = false
@export var income: int = 0
@export var repairs_classes: Array[MovementClass] = []
@export var builds: StringName = &""  # non-empty if a production facility
@export var hides_units: bool = false  # forest / reef
@export var vision_bonus: int = 0  # mountains
## Movement cost per movement-class key, one PackedInt32Array entry per
## weather (indexed by GameState.Weather). -1 = impassable. A class absent
## from the dictionary cannot enter this terrain at all.
@export var move_costs: Dictionary[StringName, PackedInt32Array] = {}
