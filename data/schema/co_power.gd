class_name COPower
extends Resource
## One activatable commander power (§7): a temporary combat modifier
## with an optional one-shot heal, paid for in meter points.

@export var key: StringName = &""  # stable id for save files
@export var display_name: String = ""
@export_multiline var description: String = ""
## Meter points needed (and consumed) to fire.
@export var meter_cost: int = 300
## Attack/defense bonus percentage points while active.
@export var attack_bonus: int = 10
@export var defense_bonus: int = 10
## Extra luck range while active.
@export var luck_bonus: int = 0
## Internal HP restored to every unit on activation.
@export var heal_hp: int = 0
