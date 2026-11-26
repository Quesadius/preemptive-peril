class_name DamagePreviewPanel
extends PanelContainer
## Predicted damage and counterattack for the hovered target during
## TARGET_SELECT (§9 calls this non-negotiable for playability). Values
## come straight from Combat.preview — luckless, like the AW forecast.

var _label: Label
var _detail_label: Label


func _init() -> void:
	var box := VBoxContainer.new()
	_label = Label.new()
	_detail_label = Label.new()
	_detail_label.modulate = Color(0.82, 0.88, 0.96, 0.85)
	_detail_label.add_theme_font_size_override("font_size", 12)
	box.add_child(_label)
	box.add_child(_detail_label)
	add_child(box)
	visible = false


## Shows the forecast, or hides the panel when null / no usable weapon.
func show_preview(preview: Combat.DamagePreview) -> void:
	if preview == null or not preview.has_ammo:
		visible = false
		return
	visible = true
	var text := "DMG %.1f" % preview.damage_display
	if preview.can_counter:
		text += "  counter %.1f" % (preview.counter_damage / 10.0)
	_label.text = text
	var details: Array[String] = []
	if preview.kills_defender:
		details.append("KILL!")
	if preview.attacker_mod != 100:
		details.append("ATK %d%%" % preview.attacker_mod)
	if preview.defender_mod != 100:
		details.append("DEF %d%%" % preview.defender_mod)
	if preview.defender_stars > 0:
		details.append("Cover " + "*".repeat(preview.defender_stars))
	_detail_label.text = "  ".join(details)
	_detail_label.visible = not details.is_empty()


## The primary forecast line, for tests.
func text() -> String:
	return _label.text


## The tactical detail line (kill flag, CO mods, terrain cover), for tests.
func detail_text() -> String:
	return _detail_label.text
