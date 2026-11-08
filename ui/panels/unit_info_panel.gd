class_name UnitInfoPanel
extends PanelContainer
## Type, HP, fuel, ammo, and cargo of the unit under the cursor (§9).
## Hidden when the tile is empty. Reads display_hp(), never raw hp.

var _title_label: Label
var _stats_label: Label


func _init() -> void:
	var box := VBoxContainer.new()
	_title_label = Label.new()
	_stats_label = Label.new()
	box.add_child(_title_label)
	box.add_child(_stats_label)
	add_child(box)
	visible = false


## Shows `unit`, or hides the panel when null.
func show_unit(state: GameState, unit: UnitState) -> void:
	if unit == null:
		visible = false
		return
	visible = true
	var unit_type: UnitType = state.ruleset.unit_types[unit.type_id]
	_title_label.text = "%s  (Team %d)" % [unit_type.display_name, unit.team]
	var ammo_text := str(unit.ammo) if unit_type.max_ammo > 0 else "-"
	var cargo_text := "  Cargo %d" % unit.cargo.size() if not unit.cargo.is_empty() else ""
	_stats_label.text = (
		"HP %d  Fuel %d  Ammo %s%s" % [unit.display_hp(), unit.fuel, ammo_text, cargo_text]
	)


## The title line, for tests.
func title_text() -> String:
	return _title_label.text


## The stats line, for tests.
func stats_text() -> String:
	return _stats_label.text
