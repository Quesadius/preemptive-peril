class_name WeaponProfile
extends Resource
## Weapon definition. A weapon can hit exactly the unit types its damage
## table lists; primary weapons typically consume ammo, secondaries don't.

@export var key: StringName = &""  # stable id for save files
@export var display_name: String = ""
@export var damage_table: DamageTable
@export var uses_ammo: bool = true
