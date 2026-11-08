class_name DamageTable
extends Resource
## Base damage a weapon deals per defender unit type, keyed by
## UnitType.key (StringName, never an array index — §7). A defender key
## absent from the table means the weapon cannot target that unit at all.

@export var key: StringName = &""  # stable id for save files
@export var base_damage: Dictionary[StringName, int] = {}
