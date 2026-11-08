class_name UnitType
extends Resource
## Unit definition (architecture §7).

@export var key: StringName = &""  # stable id for save files
@export var display_name: String = ""
@export var sprite_frames: SpriteFrames
@export var cost: int = 1000
@export var movement: int = 3
@export var movement_class: MovementClass
@export var vision: int = 2
@export var max_fuel: int = 99
@export var fuel_per_turn: int = 0  # daily drain (air/sea units)
@export var crashes_without_fuel: bool = false
@export var primary_weapon: WeaponProfile
@export var secondary_weapon: WeaponProfile
@export var max_ammo: int = 0
@export_range(0, 5) var attack_range_min: int = 1
@export_range(0, 8) var attack_range_max: int = 1
@export var can_move_and_fire: bool = true
@export var capture_capable: bool = false
@export var supply_capable: bool = false
@export var transport_capacity: int = 0
@export var transportable_classes: Array[MovementClass] = []
@export var built_at: Array[StringName] = []  # &"factory", &"port", &"airport"
