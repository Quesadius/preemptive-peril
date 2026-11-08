class_name ActionError
extends RefCounted
## Why a proposed Action is illegal. Rules.validate() returns null for a
## legal action, otherwise one of these — the code is a StringName the UI
## can map to a display string. (Not in the §2 tree; required by the
## validate() signature in §4.)

const UNKNOWN_ACTION := &"unknown_action"
const UNKNOWN_UNIT := &"unknown_unit"
const NOT_YOUR_TURN := &"not_your_turn"
const UNIT_EXHAUSTED := &"unit_exhausted"
const UNIT_IN_TRANSPORT := &"unit_in_transport"
const VERB_NOT_IMPLEMENTED := &"verb_not_implemented"
const ILLEGAL_PATH := &"illegal_path"
const DESTINATION_OCCUPIED := &"destination_occupied"
const CANNOT_MOVE_AND_FIRE := &"cannot_move_and_fire"
const NO_TARGET := &"no_target"
const TARGET_OUT_OF_RANGE := &"target_out_of_range"
const CANNOT_ATTACK_TARGET := &"cannot_attack_target"
const CANNOT_CAPTURE := &"cannot_capture"
const NOT_CAPTURABLE := &"not_capturable"
const ALREADY_OWNED := &"already_owned"
const UNKNOWN_UNIT_TYPE := &"unknown_unit_type"
const NOT_YOUR_PROPERTY := &"not_your_property"
const CANNOT_BUILD_TYPE := &"cannot_build_type"
const INSUFFICIENT_FUNDS := &"insufficient_funds"
const UNIT_LIMIT_REACHED := &"unit_limit_reached"
const CANNOT_LOAD := &"cannot_load"
const CANNOT_JOIN := &"cannot_join"
const JOIN_TARGET_FULL := &"join_target_full"
const NO_CARGO := &"no_cargo"
const BAD_UNLOAD_TARGET := &"bad_unload_target"
const CANNOT_SUPPLY := &"cannot_supply"
const NOTHING_TO_SUPPLY := &"nothing_to_supply"
const NO_CO := &"no_co"
const POWER_ALREADY_ACTIVE := &"power_already_active"
const INSUFFICIENT_METER := &"insufficient_meter"

var code: StringName = &""


## Wraps a reason code.
func _init(p_code: StringName) -> void:
	code = p_code
