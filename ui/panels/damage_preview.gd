class_name DamagePreviewPanel
extends PanelContainer
## Predicted damage and counterattack for the hovered target during
## TARGET_SELECT (§9 calls this non-negotiable for playability). Values
## come straight from Combat.preview — luckless, like the AW forecast.

var _label: Label


func _init() -> void:
	_label = Label.new()
	add_child(_label)
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


## The forecast line, for tests.
func text() -> String:
	return _label.text
