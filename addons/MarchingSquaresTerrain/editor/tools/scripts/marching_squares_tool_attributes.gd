@tool
extends ScrollContainer
class_name MarchingSquaresToolAttributes


signal setting_changed(setting: String, value: Variant)
signal terrain_setting_changed(setting: String, value: Variant)

const TEXTURE_PRESETS_PATH : String= "res://addons/MarchingSquaresTerrain/resources/texture_presets/"
const GLOBAL_QUICK_PAINTS_PATH : String = "res://addons/MarchingSquaresTerrain/resources/quick_paints/global/"

enum SettingType {
	CHECKBOX,
	SLIDER,
	OPTION,
	TEXT,
	CHUNK,
	TERRAIN,
	PRESET,
	QUICK_PAINT,
	ERROR,
}

var terrain_settings_data : Dictionary = {
	"dimensions": "Vector3i",
	"cell_size": "Vector2",
	"blend_mode": "OptionButton",
	"blend_sharpness": "EditorSpinSlider",
	"noise_hmap": "EditorResourcePicker",
	"default_wall_texture": "OptionButton",
	"extra_collision_layer": "OptionButton",
	# Grass settings
	"animation_fps": "SpinBox",
	"grass_subdivisions": "SpinBox",
	"grass_size": "Vector2",
	"use_flat_normals": "CheckBox",
	# Special texture settings
	"use_ridge_texture": "CheckBox",
	"use_ledge_texture": "CheckBox",
	"ridge_threshold": "EditorSpinSlider",
	"ledge_threshold": "EditorSpinSlider",
	"prefab_set": "EditorResourcePicker",
	"use_cell_shading": "CheckBox",
}

const TERRAIN_SETTINGS_CHUNK_TAB := [
	"dimensions",
	"cell_size",
	"extra_collision_layer",
	"prefab_set",
]

const TERRAIN_SETTINGS_VERTEX_PAINTER_TAB := [
	"default_wall_texture",
	"blend_sharpness",
	"use_ridge_texture",
	"use_ledge_texture",
	"ridge_threshold",
	"ledge_threshold",
]

const TERRAIN_SETTINGS_ENVIRONMENT_TAB := [
	"noise_hmap",
	"animation_fps",
	"grass_subdivisions",
	"grass_size",
	"use_flat_normals",
	"use_cell_shading",
]

const TERRAIN_SETTINGS_LABEL_OVERRIDES := {
	"blend_sharpness": "Blend Smoothness",
}

const TERRAIN_TAB_VISIBLE_HEIGHT := 132


func _add_texture_preset_options(preset_button: OptionButton, base_path: String) -> void:
	var dir := DirAccess.open(base_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name == "." or file_name == "..":
			file_name = dir.get_next()
			continue
		var path := base_path.path_join(file_name)
		if dir.current_is_dir():
			_add_texture_preset_options(preset_button, path)
		elif file_name.ends_with(".tres") or file_name.ends_with(".res"):
			if file_name == "texture_library.tres":
				file_name = dir.get_next()
				continue
			var resource := load(path)
			if resource is MarchingSquaresTexturePreset:
				preset_button.add_item(_resource_label_from_file(path, "preset_name", path.get_file().get_basename()))
				preset_button.set_item_metadata(preset_button.item_count - 1, path)
		file_name = dir.get_next()
	dir.list_dir_end()


func _resource_label_from_file(path: String, property_name: String, fallback: String) -> String:
	if not path.ends_with(".tres"):
		return fallback
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return fallback
	var needle := property_name + " = "
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.begins_with(needle):
			var value := line.substr(needle.length()).strip_edges()
			return value.trim_prefix("\"").trim_suffix("\"")
	return fallback


func _get_vertex_paint_material_slots() -> Array[int]:
	var slots: Array[int] = []
	var terrain = plugin.current_terrain_node if plugin != null else null
	if terrain == null:
		slots.append(0)
		return slots

	slots.append(15)
	var highest_active_slot := 0
	for slot_idx in range(plugin.MAX_TEXTURE_SLOTS):
		if slot_idx == 15:
			continue
		var slot_obj = terrain.texture_slots[slot_idx] if slot_idx < terrain.texture_slots.size() else null
		var is_active := slot_idx == 0
		if slot_obj != null and slot_obj.get("active") != null:
			is_active = bool(slot_obj.get("active")) or slot_idx == 0
		if is_active:
			highest_active_slot = slot_idx

	for slot_idx in range(highest_active_slot + 1):
		if slot_idx == 15:
			continue
		var slot_obj = terrain.texture_slots[slot_idx] if slot_idx < terrain.texture_slots.size() else null
		var is_active := slot_idx == 0
		if slot_obj != null and slot_obj.get("active") != null:
			is_active = bool(slot_obj.get("active"))
		if slot_idx == 0 or is_active:
			slots.append(slot_idx)

	if slots.is_empty():
		slots.append(0)
	return slots


func _get_visible_texture_option_slots(include_void: bool = false) -> Array[int]:
	var slots: Array[int] = []
	var terrain = plugin.current_terrain_node if plugin != null else null
	if terrain == null:
		for slot_idx in range(6):
			if slot_idx == 15 and not include_void:
				continue
			slots.append(slot_idx)
		return slots

	var visible_count := 6
	if terrain.get("visible_texture_slot_count") != null:
		visible_count = clampi(int(terrain.get("visible_texture_slot_count")), 6, plugin.MAX_TEXTURE_SLOTS)

	for slot_idx in range(visible_count):
		if slot_idx == 15 and not include_void:
			continue
		slots.append(slot_idx)

	if slots.is_empty():
		slots.append(0)
	return slots


func _get_vertex_paint_material_label(slot_idx: int, terrain_names: Array) -> String:
	if slot_idx >= 0 and slot_idx < terrain_names.size():
		return str(terrain_names[slot_idx])
	return "Texture " + str(slot_idx + 1)

var plugin : MarchingSquaresTerrainPlugin
var attribute_list : MarchingSquaresToolAttributesList
var settings : Dictionary = {}

var last_setting_type : SettingType = SettingType.ERROR
var selected_chunk : MarchingSquaresTerrainChunk
var current_available_chunks : Array[MarchingSquaresTerrainChunk] = []

var hbox_container


func _ready() -> void:
	set_custom_minimum_size(Vector2(0, 35))
	add_theme_constant_override("separation", 5)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED


func show_tool_attributes(tool_index: int) -> void:
	hbox_container = HBoxContainer.new()
	hbox_container.add_theme_constant_override("separation", 5)
	hbox_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox_container.size_flags_vertical = Control.SIZE_FILL

	if not visible:
		return

	for child in get_children():
		child.queue_free()
	settings.clear()

	if not plugin.toolbar.toolbox:
		return

	var tool := plugin.toolbar.toolbox.tools.get(tool_index)
	var tool_attributes : MarchingSquaresToolAttributeSettings = tool.get("attributes")
	var type_map = {
		"slider": SettingType.SLIDER,
		"checkbox": SettingType.CHECKBOX,
		"option": SettingType.OPTION,
		"text": SettingType.TEXT,
		"chunk": SettingType.CHUNK,
		"terrain": SettingType.TERRAIN,
		"preset": SettingType.PRESET,
		"quick_paint": SettingType.QUICK_PAINT,
	}

	var new_attributes := []
	if tool_attributes.brush_type:
		new_attributes.append(attribute_list.brush_type)
	if tool_attributes.vp_falloff_mode:
		new_attributes.append(attribute_list.vp_falloff_mode)
	if tool_attributes.size:
		new_attributes.append(attribute_list.size)
	if tool_attributes.ease_value:
		new_attributes.append(attribute_list.ease_value)
	if tool_attributes.height:
		new_attributes.append(attribute_list.height)
	if tool_attributes.strength:
		new_attributes.append(attribute_list.strength)
	if tool_attributes.flatten:
		new_attributes.append(attribute_list.flatten)
	if tool_attributes.falloff:
		new_attributes.append(attribute_list.falloff)
	if tool_attributes.mask_mode:
		new_attributes.append(attribute_list.mask_mode)
	if tool_attributes.material:
		new_attributes.append(attribute_list.material)
	if tool_attributes.texture_preset:
		new_attributes.append(attribute_list.texture_preset)
	if tool_attributes.quick_paint_selection:
		new_attributes.append(attribute_list.quick_paint_selection)
	if tool_attributes.paint_walls:
		new_attributes.append(attribute_list.paint_walls)
	if tool_attributes.chunk_management:
		new_attributes.append(attribute_list.chunk_management)
	if tool_attributes.terrain_settings:
		new_attributes.append(attribute_list.terrain_settings)

	# Rebuild material names from the preset or fallback to defaults
	var terrain_names : Array = []
	if plugin.current_terrain_node and plugin.current_terrain_node.current_texture_preset and plugin.current_terrain_node.current_texture_preset.new_tex_names:
		terrain_names = plugin.current_terrain_node.current_texture_preset.new_tex_names.texture_names
	else:
		terrain_names = attribute_list.vp_tex_names.texture_names  # fallback
	var material_options: Array[String] = []
	for slot_idx in _get_vertex_paint_material_slots():
		material_options.append(_get_vertex_paint_material_label(slot_idx, terrain_names))
	attribute_list.material["options"] = material_options

	for attribute in new_attributes:
		var setting_dict : Dictionary = attribute
		if setting_dict.has("type") and setting_dict["type"] is String:
			setting_dict["type"] = type_map.get(setting_dict["type"], SettingType.ERROR)
		add_setting(setting_dict)

	add_child(hbox_container)
	last_setting_type = SettingType.ERROR # Reset the setting type for correct VSeparators

	plugin.gizmo_plugin.trigger_redraw(plugin.current_terrain_node)


func add_setting(p_params: Dictionary) -> void:
	var setting_name : String = p_params.get("name", "")
	var setting_type : SettingType = p_params.get("type", SettingType.ERROR)
	var label_text : String = p_params.get("label", setting_name)

	if last_setting_type != SettingType.ERROR:
		if last_setting_type == SettingType.SLIDER and setting_type == SettingType.SLIDER:
			pass
		elif last_setting_type != setting_type:
			hbox_container.add_child(VSeparator.new())

	var add_label := true
	if setting_type == SettingType.CHUNK or setting_type == SettingType.TERRAIN:
		add_label = false
	if add_label:
		var label := Label.new()
		label.set_text(label_text + ':')
		label.set_vertical_alignment(VERTICAL_ALIGNMENT_CENTER)
		label.set_custom_minimum_size(Vector2(50, 25))

		var c_cont := CenterContainer.new()
		c_cont.set_custom_minimum_size(Vector2(50, 35))
		c_cont.add_child(label, true)
		hbox_container.add_child(c_cont, true)

	var cont
	var saved_setting_value := _get_setting_value(setting_name)
	match setting_type:
		SettingType.CHECKBOX:
			var checkbox := CheckBox.new()
			checkbox.set_flat(true)
			checkbox.button_pressed = p_params.get("default", false) # Fallback base value
			if saved_setting_value is not String and str(saved_setting_value) !=  "ERROR":
				checkbox.button_pressed = saved_setting_value
			checkbox.toggled.connect(func(pressed): _on_setting_changed(setting_name, pressed))
			checkbox.set_custom_minimum_size(Vector2(25, 25))

			cont = CenterContainer.new()
			cont.set_custom_minimum_size(Vector2(35, 35))
			cont.add_child(checkbox, true)
			hbox_container.add_child(cont, true)
		SettingType.SLIDER:
			var range_data := p_params.get("range", Vector3(1.0, 50.0, 0.5))
			var cell_scale_factor := clamp(((plugin.current_terrain_node.cell_size.x + plugin.current_terrain_node.cell_size.y) / 4.0), 0.3, 1.0)
			var dimensions_scale_factor := clamp((((plugin.current_terrain_node.dimensions.x / 33) + (plugin.current_terrain_node.dimensions.z / 33)) / 2.0), 0.5, 2.0)
			var scale_factor : float = dimensions_scale_factor * cell_scale_factor
			var default_value := p_params.get("default", 10.0) # Fallback base value
			if setting_name == "size":
				range_data *= scale_factor
				default_value *= scale_factor
			var range_min = range_data.x
			var range_max = range_data.y
			var range_step = range_data.z
			if saved_setting_value is not String and str(saved_setting_value) !=  "ERROR":
				default_value = saved_setting_value

			cont = MarginContainer.new()
			cont.set_custom_minimum_size(Vector2(80, 35))
			if setting_name == "height" or setting_name == "ease_value":
				var spin_slider := EditorSpinSlider.new()
				spin_slider.set_flat(true)
				spin_slider.allow_greater = true
				spin_slider.allow_lesser = true
				spin_slider.set_min(range_min)
				spin_slider.set_max(range_max)
				spin_slider.set_step(range_step)
				spin_slider.set_value(default_value)
				spin_slider.value_changed.connect(func(value): _on_setting_changed(setting_name, value))
				spin_slider.set_custom_minimum_size(Vector2(80, 35))

				cont.add_theme_constant_override("margin_top", -5)
				cont.add_child(spin_slider, true)
			else:
				var hslider := HSlider.new()
				hslider.set_min(range_min)
				hslider.set_max(range_max)
				hslider.set_step(range_step)
				hslider.set_value(default_value)
				hslider.value_changed.connect(func(value): _on_setting_changed(setting_name, value))
				hslider.set_custom_minimum_size(Vector2(80, 35))

				cont.add_theme_constant_override("margin_right", 10)
				cont.add_theme_constant_override("margin_left", -3)
				cont.add_child(hslider, true)
			hbox_container.add_child(cont, true)
		SettingType.OPTION:
			var options : Array = p_params.get("options", [])
			var option_button := OptionButton.new()
			var material_slots: Array[int] = []
			if setting_name == "material":
				material_slots = _get_vertex_paint_material_slots()
				for idx in range(mini(options.size(), material_slots.size())):
					option_button.add_item(str(options[idx]))
					option_button.set_item_metadata(option_button.item_count - 1, material_slots[idx])
			else:
				for option in options:
					option_button.add_item(option)
			var default_value := p_params.get("default", 0) # Fallback base value
			if saved_setting_value is not String and str(saved_setting_value) !=  "ERROR":
				default_value = saved_setting_value
			if setting_name == "material":
				var selected_idx := 0
				for item_idx in range(option_button.item_count):
					if int(option_button.get_item_metadata(item_idx)) == int(default_value):
						selected_idx = item_idx
						break
				option_button.selected = selected_idx
			else:
				option_button.selected = default_value

			option_button.set_flat(true)
			if setting_name == "material":
				option_button.item_selected.connect(func(index):
					var slot_idx = option_button.get_item_metadata(index)
					_on_setting_changed(setting_name, int(slot_idx))
				)
			else:
				option_button.item_selected.connect(func(index): _on_setting_changed(setting_name, index))
			option_button.set_custom_minimum_size(Vector2(65, 35))

			cont = CenterContainer.new()
			cont.set_custom_minimum_size(Vector2(65, 35))
			cont.add_child(option_button, true)
			hbox_container.add_child(cont, true)
		SettingType.TEXT:
			var line_edit := LineEdit.new()
			line_edit.set_flat(true)
			line_edit.expand_to_text_length = true
			line_edit.placeholder_text = p_params.get("default", "New text here...")
			line_edit.text_submitted.connect(func(new_text): _on_setting_changed(setting_name, new_text))
			line_edit.text_submitted.connect(func(_text): line_edit.clear())
			line_edit.set_custom_minimum_size(Vector2(25, 25))

			cont = CenterContainer.new()
			cont.set_custom_minimum_size(Vector2(35, 35))
			cont.add_child(line_edit, true)
			hbox_container.add_child(cont, true)
		SettingType.PRESET:
			var preset_button := OptionButton.new()
			preset_button.add_item("None") # First option is no preset
			preset_button.set_item_metadata(0, null)
			if setting_name == "texture_preset":
				_add_texture_preset_options(preset_button, TEXTURE_PRESETS_PATH)

				preset_button.set_flat(true)
				preset_button.item_selected.connect(func(index):
					var selected_texture_preset = preset_button.get_item_metadata(index)
					if selected_texture_preset is String:
						selected_texture_preset = load(selected_texture_preset)
					_on_setting_changed(setting_name, selected_texture_preset)
				)
				preset_button.set_custom_minimum_size(Vector2(100, 35))

				# Sync dropdown selection with current plugin.current_texture_preset
				var terrain := MarchingSquaresTerrainPlugin.instance.current_terrain_node
				var current_texture_preset = terrain.current_texture_preset if terrain else null
				if current_texture_preset == null:
					preset_button.select(0)  # Select "None"
				else:
					# Find matching preset in dropdown
					for i in range(preset_button.item_count):
						var item_meta = preset_button.get_item_metadata(i)
						var matches_current := false
						if item_meta is String:
							matches_current = item_meta == current_texture_preset.resource_path
						else:
							matches_current = item_meta == current_texture_preset
						if matches_current:
							preset_button.select(i)
							break

				cont = CenterContainer.new()
				cont.set_custom_minimum_size(Vector2(100, 35))
				cont.add_child(preset_button, true)
				hbox_container.add_child(cont, true)
			else: # Can be used for e.g. terrain settings presets in the future:
				pass
		SettingType.QUICK_PAINT:
			var quick_paint_button := OptionButton.new()
			quick_paint_button.add_item("None")  # First option is no paint. #TODO Doesn't seem to work right now and needs to be fixed later.
			quick_paint_button.set_item_metadata(0, null)

			# 1. Load GLOBAL quick paints from folder (always available)
			var dir := DirAccess.open(GLOBAL_QUICK_PAINTS_PATH)
			if dir:
				dir.list_dir_begin()
				var file_name := dir.get_next()
				while file_name !=  "":
					if file_name.ends_with(".tres") or file_name.ends_with(".res"):
						var quick_paint_path := GLOBAL_QUICK_PAINTS_PATH + file_name
						quick_paint_button.add_item(_resource_label_from_file(quick_paint_path, "paint_name", file_name.get_basename()))
						quick_paint_button.set_item_metadata(quick_paint_button.item_count - 1, quick_paint_path)
					file_name = dir.get_next()
				dir.list_dir_end()

			# 2. Load PRESET-SPECIFIC quick paints (if preset is selected and has any)
			var terrain := MarchingSquaresTerrainPlugin.instance.current_terrain_node
			if terrain and terrain.current_texture_preset:
				var preset := terrain.current_texture_preset
				if preset.quick_paints.size() > 0:
					quick_paint_button.add_separator()  # Visual separator
					for quick_paint in preset.quick_paints:
						if quick_paint:
							quick_paint_button.add_item(quick_paint.paint_name)
							quick_paint_button.set_item_metadata(quick_paint_button.item_count - 1, quick_paint)

			quick_paint_button.set_flat(true)
			quick_paint_button.item_selected.connect(func(index):
				var selected_quick_paint = quick_paint_button.get_item_metadata(index)
				if selected_quick_paint is String:
					selected_quick_paint = load(selected_quick_paint)
				_on_setting_changed(setting_name, selected_quick_paint)
			)
			quick_paint_button.set_custom_minimum_size(Vector2(100, 35))

			# Sync dropdown selection with current plugin.current_quick_paint
			var current_quick_paint = _get_setting_value(setting_name)
			if current_quick_paint == null:
				quick_paint_button.select(0)  # Select "None"
			else:
				# Find matching quick paint in dropdown
				for i in range(quick_paint_button.item_count):
					var item_meta = quick_paint_button.get_item_metadata(i)
					var matches_current := false
					if item_meta is String:
						matches_current = current_quick_paint is Resource and item_meta == current_quick_paint.resource_path
					else:
						matches_current = item_meta == current_quick_paint
					if matches_current:
						quick_paint_button.select(i)
						break

			cont = CenterContainer.new()
			cont.set_custom_minimum_size(Vector2(100, 35))
			cont.add_child(quick_paint_button, true)
			hbox_container.add_child(cont, true)
		SettingType.CHUNK:
			if plugin.current_terrain_node.get_child_count() == 0:
				return

			current_available_chunks.clear()

			var terrain_children : Array = plugin.current_terrain_node.get_children()
			var chunk_button := OptionButton.new()
			for child in terrain_children:
				if child is MarchingSquaresTerrainChunk:
					chunk_button.add_item("Chunk " + str(child.chunk_coords))
					current_available_chunks.append(child)
			chunk_button.selected = current_available_chunks.find(plugin.selected_chunk) if not current_available_chunks.is_empty() and plugin.selected_chunk else -1
			if not current_available_chunks.is_empty() and plugin.selected_chunk:
				selected_chunk = plugin.selected_chunk

			var option_button := OptionButton.new()
			option_button.set_flat(true)
			option_button.set_custom_minimum_size(Vector2(65, 35))
			for mode in MarchingSquaresTerrainChunk.Mode:
				option_button.add_item(_format_constant_string(mode))
			option_button.selected = plugin.selected_chunk.merge_mode if not current_available_chunks.is_empty() and plugin.selected_chunk else -1
			option_button.item_selected.connect(_on_chunk_mode_changed)

			chunk_button.set_flat(true)
			chunk_button.item_selected.connect(func(chunk): _on_chunk_selected(option_button, chunk_button.get_item_text(chunk)))
			chunk_button.set_custom_minimum_size(Vector2(65, 35))

			var mult_apply_button := Button.new()
			mult_apply_button.set_custom_minimum_size(Vector2(65, 30))
			mult_apply_button.pressed.connect(_apply_mode_to_all_chunks)
			mult_apply_button.text = "Apply mode to all chunks"

			cont = CenterContainer.new()
			cont.set_custom_minimum_size(Vector2(65, 35))
			cont.add_child(chunk_button, true)
			hbox_container.add_child(cont, true)

			var v_sep := VSeparator.new()
			hbox_container.add_child(v_sep, true)

			cont = CenterContainer.new()
			cont.set_custom_minimum_size(Vector2(65, 35))
			cont.add_child(option_button, true)
			hbox_container.add_child(cont, true)

			v_sep = VSeparator.new()
			hbox_container.add_child(v_sep, true)

			cont = MarginContainer.new()
			cont.set_custom_minimum_size(Vector2(65, 35))
			cont.add_theme_constant_override("margin_bottom", 3)
			cont.add_child(mult_apply_button, true)
			hbox_container.add_child(cont, true)
		SettingType.TERRAIN:
			hbox_container.add_child(_create_terrain_settings_tabs(), true)
		SettingType.ERROR: # Fallback
			push_error("Couldn't load tool attributes setting")

	last_setting_type = setting_type


func _create_terrain_settings_tabs() -> Control:
	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_FILL
	tabs.set_custom_minimum_size(Vector2(0, TERRAIN_TAB_VISIBLE_HEIGHT + 36))

	tabs.add_child(_create_chunk_tab())
	tabs.set_tab_title(tabs.get_tab_count() - 1, "Chunk")

	tabs.add_child(_create_vertex_painter_tab())
	tabs.set_tab_title(tabs.get_tab_count() - 1, "Vertex Painter")

	tabs.add_child(_create_environment_tab())
	tabs.set_tab_title(tabs.get_tab_count() - 1, "Environment")

	tabs.add_child(_create_shader_tab())
	tabs.set_tab_title(tabs.get_tab_count() - 1, "Shader")

	return tabs


func _create_chunk_tab() -> Control:
	var page := VBoxContainer.new()
	page.name = "Chunk"
	page.add_theme_constant_override("separation", 8)
	page.add_child(_create_tab_scroll(_create_terrain_settings_list(TERRAIN_SETTINGS_CHUNK_TAB)), true)
	return page


func _create_vertex_painter_tab() -> Control:
	var page := VBoxContainer.new()
	page.name = "VertexPainter"
	page.add_theme_constant_override("separation", 8)
	page.add_child(_create_tab_scroll(_create_terrain_settings_list(TERRAIN_SETTINGS_VERTEX_PAINTER_TAB)), true)
	return page


func _create_environment_tab() -> Control:
	var page := VBoxContainer.new()
	page.name = "Environment"
	page.add_theme_constant_override("separation", 8)
	page.add_child(_create_tab_scroll(_create_terrain_settings_list(TERRAIN_SETTINGS_ENVIRONMENT_TAB)), true)
	return page


func _create_shader_tab() -> Control:
	var page := VBoxContainer.new()
	page.name = "Shader"
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_FILL

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(spacer, true)

	var label := Label.new()
	label.text = "Shader settings coming soon."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(label, true)

	var spacer_bottom := Control.new()
	spacer_bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(spacer_bottom, true)

	return page


func _create_tab_scroll(content: Control) -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.set_custom_minimum_size(Vector2(0, TERRAIN_TAB_VISIBLE_HEIGHT))
	scroll.custom_minimum_size.y = TERRAIN_TAB_VISIBLE_HEIGHT
	scroll.add_child(content, true)
	scroll.set_deferred("scroll_vertical", 0)
	return scroll


func _create_terrain_settings_list(setting_names: Array) -> Control:
	var wrapper := HBoxContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	var left_spacer := Control.new()
	left_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.add_child(left_spacer, true)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.set_custom_minimum_size(Vector2(520, 0))
	list.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	list.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	for setting_name_variant in setting_names:
		var setting_name := str(setting_name_variant)
		if not terrain_settings_data.has(setting_name):
			continue
		list.add_child(_create_terrain_setting_row(setting_name), true)

	wrapper.add_child(list, true)

	var right_spacer := Control.new()
	right_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.add_child(right_spacer, true)

	return wrapper


func _create_terrain_setting_row(setting: String) -> Control:
	var editor_setting = terrain_settings_data[setting]
	var s_value := plugin.current_terrain_node.get(setting)

	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label := Label.new()
	var label_text := TERRAIN_SETTINGS_LABEL_OVERRIDES.get(setting, _make_editor_name(setting))
	label.set_text(str(label_text) + ':')
	label.set_vertical_alignment(VERTICAL_ALIGNMENT_CENTER)
	label.set_custom_minimum_size(Vector2(170, 25))

	var label_c_cont := CenterContainer.new()
	label_c_cont.set_custom_minimum_size(Vector2(170, 35))
	label_c_cont.add_child(label, true)
	hbox.add_child(label_c_cont, true)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	var ts_cont : Control
	match editor_setting:
		"Vector2":
			var editor_vec2 := _make_vector_editor(editor_setting, s_value, setting)
			ts_cont = CenterContainer.new()
			ts_cont.set_custom_minimum_size(Vector2(130, 35))
			ts_cont.add_child(editor_vec2, true)
		"Vector3i":
			var editor_vec3i := _make_vector_editor(editor_setting, s_value, setting)
			ts_cont = CenterContainer.new()
			ts_cont.set_custom_minimum_size(Vector2(185, 35))
			ts_cont.add_child(editor_vec3i, true)
		"SpinBox":
			var spin_box := SpinBox.new()
			spin_box.value = plugin.current_terrain_node.get(setting)
			spin_box.value_changed.connect(func(value): _on_terrain_setting_changed(setting, value))
			spin_box.set_custom_minimum_size(Vector2(70, 25))

			ts_cont = CenterContainer.new()
			ts_cont.set_custom_minimum_size(Vector2(80, 35))
			ts_cont.add_child(spin_box, true)
		"EditorSpinSlider":
			var spin_slider := EditorSpinSlider.new()
			spin_slider.set_flat(true)
			spin_slider.set_min(0.0)
			if setting == "wall_threshold":
				spin_slider.set_max(0.5)
			else:
				spin_slider.set_max(1.0)
			spin_slider.set_step(0.01)
			spin_slider.set_value(s_value)
			spin_slider.value_changed.connect(func(value): _on_terrain_setting_changed(setting, value))
			spin_slider.set_custom_minimum_size(Vector2(120, 35))

			ts_cont = MarginContainer.new()
			ts_cont.set_custom_minimum_size(Vector2(120, 35))
			ts_cont.add_theme_constant_override("margin_top", -5)
			ts_cont.add_child(spin_slider, true)
		"EditorResourcePicker":
			var editor_r_picker := EditorResourcePicker.new()
			if setting == "noise_hmap":
				editor_r_picker.set_base_type("Noise")
			elif setting == "prefab_set":
				editor_r_picker.set_base_type("MarchingSquaresPrefabSet")
			else:
				editor_r_picker.set_base_type("Texture2D")
			editor_r_picker.edited_resource = plugin.current_terrain_node.get(setting)
			_hide_textures(editor_r_picker)
			editor_r_picker.resource_changed.connect(func(resource): _on_terrain_setting_changed(setting, resource))
			editor_r_picker.set_custom_minimum_size(Vector2(120, 25))

			ts_cont = CenterContainer.new()
			ts_cont.set_custom_minimum_size(Vector2(130, 35))
			ts_cont.add_child(editor_r_picker, true)
		"ColorPickerButton":
			var c_pick_button := ColorPickerButton.new()
			c_pick_button.color = plugin.current_terrain_node.get(setting)
			c_pick_button.color_changed.connect(func(color): _on_terrain_setting_changed(setting, color))
			c_pick_button.set_custom_minimum_size(Vector2(105, 25))

			ts_cont = CenterContainer.new()
			ts_cont.set_custom_minimum_size(Vector2(115, 35))
			ts_cont.add_child(c_pick_button, true)
		"CheckBox":
			var checkbox := CheckBox.new()
			checkbox.set_flat(true)
			checkbox.button_pressed = plugin.current_terrain_node.get(setting)
			checkbox.toggled.connect(func(pressed): _on_terrain_setting_changed(setting, pressed))
			checkbox.set_custom_minimum_size(Vector2(25, 25))

			ts_cont = CenterContainer.new()
			ts_cont.set_custom_minimum_size(Vector2(35, 35))
			ts_cont.add_child(checkbox, true)
		"OptionButton":
			var option_button := OptionButton.new()
			option_button.set_flat(true)
			if setting == "default_wall_texture":
				var terrain_names : Array = []
				if plugin.current_terrain_node and plugin.current_terrain_node.current_texture_preset and plugin.current_terrain_node.current_texture_preset.new_tex_names:
					terrain_names = plugin.current_terrain_node.current_texture_preset.new_tex_names.texture_names
				else:
					terrain_names = attribute_list.vp_tex_names.texture_names
				var wall_slots := _get_visible_texture_option_slots(false)
				for slot_idx in wall_slots:
					option_button.add_item(_get_vertex_paint_material_label(slot_idx, terrain_names))
					option_button.set_item_metadata(option_button.item_count - 1, slot_idx)
			elif setting == "blend_mode":
				option_button.add_item("Smoothed")
			elif setting == "extra_collision_layer":
				for i in range(24):
					option_button.add_item(str(i + 9))

			if setting == "extra_collision_layer":
				option_button.selected = plugin.current_terrain_node.get(setting) - 9
			elif setting == "default_wall_texture":
				var current_slot := int(plugin.current_terrain_node.get(setting))
				var selected_idx := 0
				for item_idx in range(option_button.item_count):
					if int(option_button.get_item_metadata(item_idx)) == current_slot:
						selected_idx = item_idx
						break
				option_button.selected = selected_idx
			elif setting == "blend_mode":
				option_button.selected = 0
			else:
				option_button.selected = plugin.current_terrain_node.get(setting)

			if setting == "default_wall_texture":
				option_button.item_selected.connect(func(index):
					_on_terrain_setting_changed(setting, int(option_button.get_item_metadata(index)))
				)
			else:
				option_button.item_selected.connect(func(index): _on_terrain_setting_changed(setting, index))
			option_button.set_custom_minimum_size(Vector2(120, 35))

			ts_cont = CenterContainer.new()
			ts_cont.set_custom_minimum_size(Vector2(130, 35))
			ts_cont.add_child(option_button, true)
		"LineEdit":
			var line_edit := LineEdit.new()
			line_edit.set_flat(true)
			line_edit.text = str(plugin.current_terrain_node.get(setting))
			line_edit.placeholder_text = "(auto - scene relative)"
			line_edit.text_submitted.connect(func(new_text): _on_terrain_setting_changed(setting, new_text))
			line_edit.set_custom_minimum_size(Vector2(200, 25))

			ts_cont = CenterContainer.new()
			ts_cont.set_custom_minimum_size(Vector2(210, 35))
			ts_cont.add_child(line_edit, true)
		"FolderPicker":
			var folder_hbox := HBoxContainer.new()
			folder_hbox.add_theme_constant_override("separation", 4)

			var path_edit := LineEdit.new()
			path_edit.set_flat(true)
			path_edit.text = str(plugin.current_terrain_node.get(setting))
			path_edit.placeholder_text = "(auto - scene relative)"
			path_edit.text_submitted.connect(func(new_text): _on_terrain_setting_changed(setting, new_text))
			path_edit.set_custom_minimum_size(Vector2(180, 25))
			folder_hbox.add_child(path_edit, true)

			var browse_btn := Button.new()
			browse_btn.text = "..."
			browse_btn.tooltip_text = "Browse for folder"
			browse_btn.set_custom_minimum_size(Vector2(30, 25))
			browse_btn.pressed.connect(func(): _open_folder_dialog(setting, path_edit))
			folder_hbox.add_child(browse_btn, true)

			ts_cont = CenterContainer.new()
			ts_cont.set_custom_minimum_size(Vector2(220, 35))
			ts_cont.add_child(folder_hbox, true)
		_:
			ts_cont = Control.new()

	hbox.add_child(ts_cont, true)
	return hbox


func _get_setting_value(p_setting_name: String) -> Variant:
	match p_setting_name:
		"brush_type":
			return plugin.current_brush_index
		"vp_falloff_mode":
			return plugin.vp_falloff_mode == plugin.VertexPaintFalloffMode.DITHERED
		"size":
			return plugin.brush_size
		"ease_value":
			return plugin.ease_value
		"height":
			return plugin.height
		"strength":
			return plugin.strength
		"flatten":
			return plugin.flatten
		"falloff":
			return plugin.falloff
		"mask_mode":
			return plugin.should_mask_grass
		"material":
			return plugin.vertex_color_idx
		"texture_preset":
			return plugin.current_texture_preset
		"quick_paint_selection":
			return plugin.current_quick_paint
		"paint_walls":
			return plugin.paint_walls_mode
		"chunk_management":
			pass
		"terrain_settings":
			pass
		_:
			push_error("Couldn't find tool attributes setting name")
	return "ERROR"


func _open_folder_dialog(setting_name: String, path_edit: LineEdit) -> void:
	var dialog := EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	dialog.title = "Select Directory"

	# Set initial path from current value or project root
	var current_path : String = path_edit.text
	if current_path.is_empty():
		dialog.current_dir = "res://"
	else:
		dialog.current_dir = current_path.get_base_dir()

	dialog.dir_selected.connect(func(dir: String):
		path_edit.text = dir
		_on_terrain_setting_changed(setting_name, dir)
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())

	# Add to editor base control for proper modal behavior
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered(Vector2i(600, 400))

#region on-signal functions

func _on_setting_changed(p_setting_name: String, p_value: Variant) -> void:
	emit_signal("setting_changed", p_setting_name, p_value)


func _on_terrain_setting_changed(p_setting_name: String, p_value: Variant) -> void:
	emit_signal("terrain_setting_changed", p_setting_name, p_value)


func _on_chunk_selected(option_button: OptionButton, p_chunk: String) -> void:
	var terrain := plugin.current_terrain_node
	if terrain == null:
		selected_chunk = null
		plugin.selected_chunk = null
		option_button.selected = -1
		return

	var chunk := terrain.find_child(p_chunk) as MarchingSquaresTerrainChunk
	if chunk == null:
		selected_chunk = null
		plugin.selected_chunk = null
		option_button.selected = -1
		return

	option_button.selected = int(chunk.merge_mode)
	selected_chunk = chunk
	plugin.selected_chunk = selected_chunk

	plugin.gizmo_plugin.trigger_redraw(terrain)


func _apply_mode_to_all_chunks() -> void:
	if plugin.current_terrain_node == null:
		return
	if selected_chunk == null:
		return
	for child in plugin.current_terrain_node.get_children():
		if child is MarchingSquaresTerrainChunk:
			_change_chunk_mode(child, int(selected_chunk.merge_mode))


func _on_chunk_mode_changed(m_mode: int) -> void:
	_change_chunk_mode(selected_chunk, m_mode)


func _change_chunk_mode(_chunk: MarchingSquaresTerrainChunk, m_mode: int) -> void:
	match MarchingSquaresTerrainChunk.Mode.find_key(m_mode):
		"CUBIC":
			_chunk.merge_mode = MarchingSquaresTerrainChunk.Mode.CUBIC
		"POLYHEDRON":
			_chunk.merge_mode = MarchingSquaresTerrainChunk.Mode.POLYHEDRON
		"ROUNDED_POLYHEDRON":
			_chunk.merge_mode = MarchingSquaresTerrainChunk.Mode.ROUNDED_POLYHEDRON
		"SEMI_ROUND":
			_chunk.merge_mode = MarchingSquaresTerrainChunk.Mode.SEMI_ROUND
		"SPHERICAL":
			_chunk.merge_mode = MarchingSquaresTerrainChunk.Mode.SPHERICAL

#endregion

#region UI-helpers

func _make_vector_editor(type: String, value: Variant, setting_name: String) -> HBoxContainer:
	var hbox_cont := HBoxContainer.new()

	if type == "Vector2":
		var spin_x := make_spinbox(value.x, 0.1)
		var spin_y := make_spinbox(value.y, 0.1)

		var handler_x := func(v):
			var updated_val = Vector2(v, spin_y.value)
			_on_terrain_setting_changed(setting_name, updated_val)
		var handler_y := func(v):
			var updated_val = Vector2(spin_x.value, v)
			_on_terrain_setting_changed(setting_name, updated_val)

		spin_x.value_changed.connect(handler_x)
		spin_y.value_changed.connect(handler_y)

		hbox_cont.add_child(spin_x)
		hbox_cont.add_child(spin_y)

	elif type == "Vector3i":
		var spin_x := make_spinbox(value.x, 1.0)
		var spin_y := make_spinbox(value.y, 1.0)
		var spin_z := make_spinbox(value.z, 1.0)

		var handler_x := func(v):
			var updated_val = Vector3i(int(v), int(spin_y.value), int(spin_z.value))
			_on_terrain_setting_changed(setting_name, updated_val)
		var handler_y := func(v):
			var updated_val = Vector3i(int(spin_x.value), int(v), int(spin_z.value))
			_on_terrain_setting_changed(setting_name, updated_val)
		var handler_z := func(v):
			var updated_val = Vector3i(int(spin_x.value), int(spin_y.value), int(v))
			_on_terrain_setting_changed(setting_name, updated_val)

		spin_x.value_changed.connect(handler_x)
		spin_y.value_changed.connect(handler_y)
		spin_z.value_changed.connect(handler_z)

		hbox_cont.add_child(spin_x)
		hbox_cont.add_child(spin_y)
		hbox_cont.add_child(spin_z)

	return hbox_cont


func make_spinbox(val: float, step: float) -> SpinBox:
	var spin_box := SpinBox.new()
	spin_box.set_step(step)
	spin_box.set_value(float(val))
	spin_box.set_custom_minimum_size(Vector2(50, 25))
	return spin_box


func _make_editor_name(var_name: String) -> String:
	if var_name == "blend_sharpness":
		return "Smoothness"
	var loose_words := var_name.split("_")
	for word in loose_words:
		loose_words[loose_words.find(word)] = word.capitalize()
	return " ".join(loose_words)


func _hide_textures(texture_node: Node) -> void:
	var texture_button := texture_node.get_child(0) as Button
	texture_button.visible = false


func _format_constant_string(text: String) -> String:
	var words := text.to_lower().split("_")
	for i in words.size():
		words[i] = words[i].capitalize()
	return " ".join(words)

#endregion
