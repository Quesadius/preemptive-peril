class_name COProfile
extends Resource
## A commanding officer (§7): day-to-day passive combat modifiers plus a
## normal and a super power. PlayerState.co_id indexes Ruleset.cos.

@export var key: StringName = &""  # stable id for save files
@export var display_name: String = ""
## Passive modifier percentage points, applied every day.
@export var passive_attack_bonus: int = 0
@export var passive_defense_bonus: int = 0
## Extra passive luck range.
@export var passive_luck_bonus: int = 0
@export var power: COPower
@export var super_power: COPower
