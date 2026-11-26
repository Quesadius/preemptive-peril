class_name COPower
extends Resource
## One activatable commander power (§7): a temporary combat/tactical
## modifier with optional one-shot effects, paid for in meter points.

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
## Extra movement points / indirect max range / fog vision while active.
@export var movement_bonus: int = 0
@export var indirect_range_bonus: int = 0
@export var vision_bonus: int = 0
## Extra defense percentage points per terrain star while active.
@export var terrain_defense_bonus: int = 0
## Ignore weather movement slowdowns while active.
@export var ignores_weather: bool = false
## When true, all friendly units that already acted this turn can act again.
@export var refresh_units: bool = false
## One-shot bonus funds as a percentage of the player's current daily income.
@export var bonus_funds_percent: int = 0
