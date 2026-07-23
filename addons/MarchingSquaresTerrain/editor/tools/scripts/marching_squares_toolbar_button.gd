@tool
extends Button
class_name MarchingSquaresToolbarButton


var tooltip := ""


func _make_custom_tooltip(_for_text: String) -> Object:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	panel.set_custom_minimum_size(Vector2(500, 150))
	
	var rich := RichTextLabel.new()
	rich.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rich.bbcode_enabled = true
	rich.fit_content = true
	rich.scroll_active = false
	rich.text = tooltip
	
	panel.add_child(rich)
	return panel
