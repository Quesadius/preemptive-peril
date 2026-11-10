class_name Ruleset
extends Resource
## The balance root — one resource that will reference every balance table.
##
## Near-complete per §7: `damage_tables` stays deferred — tables are
## embedded in their weapons rather than registered globally.

@export var unit_types: Array[UnitType] = []
@export var terrain_types: Array[TerrainType] = []
@export var movement_classes: Array[MovementClass] = []
@export var cos: Array[COProfile] = []
@export var starting_funds: int = 0
## Head starts a new match may hand a player in place of starting_funds
## (the new-match screen's per-side choice).
@export var starting_funds_options: PackedInt32Array = PackedInt32Array()
@export var funds_per_property: int = 1000
@export var luck_max: int = 9
## Percent chance of weather rolling in at each clear day start (only
## with GameConfig.random_weather on).
@export var weather_chance: int = 10
@export var capture_threshold: int = 20
@export var repair_hp_per_turn: int = 20  # internal HP
@export var max_units_per_player: int = 50
