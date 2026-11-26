class_name COProfile
extends Resource
## A commanding officer (§7): day-to-day passive modifiers plus a normal
## and a super power. PlayerState.co_id indexes Ruleset.cos.

@export var key: StringName = &""  # stable id for save files
@export var display_name: String = ""
@export_multiline var description: String = ""
## Passive modifier percentage points, applied every day.
@export var passive_attack_bonus: int = 0
@export var passive_defense_bonus: int = 0
## Extra passive luck range.
@export var passive_luck_bonus: int = 0
## Unit-role passive attack modifiers (percentage points).
@export var passive_direct_attack_bonus: int = 0
@export var passive_indirect_attack_bonus: int = 0
@export var passive_air_attack_bonus: int = 0
## Extra movement points / indirect max range / fog vision every turn.
@export var passive_movement_bonus: int = 0
@export var passive_indirect_range_bonus: int = 0
@export var passive_vision_bonus: int = 0
## Extra defense percentage points per terrain defense star.
@export var passive_terrain_defense_bonus: int = 0
## Unit purchase cost multiplier (100 = normal, 85 = 15% discount).
@export var cost_percent: int = 100
## Extra daily property income percentage points (0 = normal, 20 = +20%).
@export var income_bonus_percent: int = 0
## When true, units always pay Clear-weather terrain movement costs.
@export var ignores_weather: bool = false
## When true, airborne units consume half their normal daily fuel (min 1).
@export var air_fuel_halved: bool = false
@export var power: COPower
@export var super_power: COPower
