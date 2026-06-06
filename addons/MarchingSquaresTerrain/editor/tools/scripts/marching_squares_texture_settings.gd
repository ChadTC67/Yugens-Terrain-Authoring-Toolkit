@tool
extends ScrollContainer
class_name MarchingSquaresTextureSettings


signal texture_setting_changed(setting: String, value: Variant)

var plugin : MarchingSquaresTerrainPlugin
var vp_tex_names : MarchingSquaresTextureNames = preload("uid://dd7fens03aosa")

const MAX_TEXTURE_SLOTS := 256

# Avoid hard class_name dependency in headless/script-cache runs.
const _TEXTURE_SLOT_SCRIPT := preload("res://addons/MarchingSquaresTerrain/resources/marching_squares_texture_slot.gd")
const MarchingSquaresBaker := preload("res://addons/MarchingSquaresTerrain/editor/tools/marching_squares_baker.gd")
const MarchingSquaresTerrainHelpers := preload("res://addons/MarchingSquaresTerrain/algorithm/terrain/marching_squares_terrain_helpers.gd")
const MSTextureLibraryScript := preload("res://addons/MarchingSquaresTerrain/resources/marching_squares_terrain_texture_library.gd")

const VAR_NAMES : Array[Dictionary] = [
	{
		"tex_var": "texture_1",
		"scale_var": "texture_scale_1",
		"sprite_var": "grass_sprite_tex_1",
	},
	{
		"tex_var": "texture_2",
		"scale_var": "texture_scale_2",
		"sprite_var": "grass_sprite_tex_2",
		"use_grass_var": "tex2_has_grass",
	},
	{
		"tex_var": "texture_3",
		"scale_var": "texture_scale_3",
		"sprite_var": "grass_sprite_tex_3",
		"use_grass_var": "tex3_has_grass",
	},
	{
		"tex_var": "texture_4",
		"scale_var": "texture_scale_4",
		"sprite_var": "grass_sprite_tex_4",
		"use_grass_var": "tex4_has_grass",
	},
	{
		"tex_var": "texture_5",
		"scale_var": "texture_scale_5",
		"sprite_var": "grass_sprite_tex_5",
		"use_grass_var": "tex5_has_grass",
	},
	{
		"tex_var": "texture_6",
		"scale_var": "texture_scale_6",
		"sprite_var": "grass_sprite_tex_6",
		"use_grass_var": "tex6_has_grass",
	},
	{
		"tex_var": "texture_7",
		"scale_var": "texture_scale_7",
	},
	{
		"tex_var": "texture_8",
		"scale_var": "texture_scale_8",
	},
	{
		"tex_var": "texture_9",
		"scale_var": "texture_scale_9",
	},
	{
		"tex_var": "texture_10",
		"scale_var": "texture_scale_10",
	},
	{
		"tex_var": "texture_11",
		"scale_var": "texture_scale_11",
	},
	{
		"tex_var": "texture_12",
		"scale_var": "texture_scale_12",
	},
	{
		"tex_var": "texture_13",
		"scale_var": "texture_scale_13",
	},
	{
		"tex_var": "texture_14",
		"scale_var": "texture_scale_14",
	},
	{
		"tex_var": "texture_15",
		"scale_var": "texture_scale_15",
	},
]


func _ready() -> void:
	# Slightly wider by default so controls on the right edge are easier to click.
	set_custom_minimum_size(Vector2(260, 0))
	add_theme_constant_override("separation", 5)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER


func _ensure_terrain_arrays(terrain: Object) -> bool:
	if terrain == null:
		return false
	
	# Avoid calling into the terrain script from the editor UI.
	# In editor reload/order edge-cases the selected node can be a plain Node3D or a placeholder script,
	# which makes method calls like _ensure_texture_slots() fail even though exported properties exist.
	var slots_var := terrain.get("texture_slots")
	if not (slots_var is Array):
		push_error("[MST] Selected node doesn't expose texture_slots. Select the MarchingSquaresTerrain node (with script attached).")
		return false
	if slots_var.size() !=  MAX_TEXTURE_SLOTS:
		slots_var.resize(MAX_TEXTURE_SLOTS)
	for i in range(MAX_TEXTURE_SLOTS):
		if slots_var[i] == null:
			slots_var[i] = _TEXTURE_SLOT_SCRIPT.new()
		# Default any missing 'active' to true (older saves won't have it).
		if slots_var[i] !=  null and slots_var[i].get("active") == null:
			slots_var[i].active = true
		# Default slot->base-texture mapping for older slot resources.
		if slots_var[i] !=  null and slots_var[i].get("terrain_texture_index") == null:
			if i == 15:
				slots_var[i].terrain_texture_index = 15
			elif i < 15:
				slots_var[i].terrain_texture_index = i
			else:
				slots_var[i].terrain_texture_index = 0
		elif slots_var[i] !=  null:
			slots_var[i].terrain_texture_index = clampi(int(slots_var[i].terrain_texture_index), 0, 15)
		# Default grass fields for older slot resources.
		if slots_var[i] !=  null and slots_var[i].get("has_grass") == null:
			slots_var[i].has_grass = (i == 0)
		if slots_var[i] !=  null and slots_var[i].get("grass_texture") == null:
			slots_var[i].grass_texture = null
	
	# Palette-per-slot arrays (all optional, but expected for the UI).
	var slot_color_indices := terrain.get("slot_color_indices")
	if slot_color_indices is Array:
		if slot_color_indices.size() !=  MAX_TEXTURE_SLOTS:
			slot_color_indices.resize(MAX_TEXTURE_SLOTS)
		for i in range(MAX_TEXTURE_SLOTS):
			if slot_color_indices[i] == null:
				slot_color_indices[i] = []
	
	var slot_blend_modes := terrain.get("slot_blend_modes")
	if slot_blend_modes is Array:
		if slot_blend_modes.size() !=  MAX_TEXTURE_SLOTS:
			slot_blend_modes.resize(MAX_TEXTURE_SLOTS)
		for i in range(MAX_TEXTURE_SLOTS):
			if slot_blend_modes[i] == null:
				slot_blend_modes[i] = 3
	
	var slot_has_outline := terrain.get("slot_has_outline")
	if slot_has_outline is Array:
		if slot_has_outline.size() !=  MAX_TEXTURE_SLOTS:
			slot_has_outline.resize(MAX_TEXTURE_SLOTS)
		for i in range(MAX_TEXTURE_SLOTS):
			if slot_has_outline[i] == null:
				slot_has_outline[i] = false
	
	var slot_outline_modes := terrain.get("slot_outline_modes")
	if slot_outline_modes is Array:
		if slot_outline_modes.size() !=  MAX_TEXTURE_SLOTS:
			slot_outline_modes.resize(MAX_TEXTURE_SLOTS)
		for i in range(MAX_TEXTURE_SLOTS):
			if slot_outline_modes[i] == null:
				slot_outline_modes[i] = 0
			slot_outline_modes[i] = clampi(int(slot_outline_modes[i]), 0, 1)
	
	var slot_outline_widths := terrain.get("slot_outline_widths")
	if slot_outline_widths is Array:
		if slot_outline_widths.size() !=  MAX_TEXTURE_SLOTS:
			slot_outline_widths.resize(MAX_TEXTURE_SLOTS)
		var default_w := 6.0
		var ow := terrain.get("outline_width")
		if ow is float or ow is int:
			default_w = float(ow)
		for i in range(MAX_TEXTURE_SLOTS):
			if slot_outline_widths[i] == null:
				slot_outline_widths[i] = default_w
			slot_outline_widths[i] = clampf(float(slot_outline_widths[i]), 0.25, 32.0)
	
	var slot_wet_enabled := terrain.get("slot_wet_enabled")
	if slot_wet_enabled is Array:
		if slot_wet_enabled.size() !=  MAX_TEXTURE_SLOTS:
			slot_wet_enabled.resize(MAX_TEXTURE_SLOTS)
		for i in range(MAX_TEXTURE_SLOTS):
			if slot_wet_enabled[i] == null:
				slot_wet_enabled[i] = false

	var slot_wet_modes := terrain.get("slot_wet_modes")
	if slot_wet_modes is Array:
		if slot_wet_modes.size() !=  MAX_TEXTURE_SLOTS:
			slot_wet_modes.resize(MAX_TEXTURE_SLOTS)
		for i in range(MAX_TEXTURE_SLOTS):
			if slot_wet_modes[i] == null:
				slot_wet_modes[i] = 0
			slot_wet_modes[i] = clampi(int(slot_wet_modes[i]), 0, 1)

	var slot_roughnesses := terrain.get("slot_roughnesses")
	if slot_roughnesses is Array:
		if slot_roughnesses.size() !=  MAX_TEXTURE_SLOTS:
			slot_roughnesses.resize(MAX_TEXTURE_SLOTS)
		for i in range(MAX_TEXTURE_SLOTS):
			if slot_roughnesses[i] == null:
				slot_roughnesses[i] = 1.0
			slot_roughnesses[i] = clampf(float(slot_roughnesses[i]), 0.0, 1.0)
	
	return true


func add_texture_settings() -> void:
	for child in get_children():
		child.queue_free()
	
	var terrain := plugin.current_terrain_node
	if terrain == null:
		return
	
	# Ensure slot/palette arrays are initialized before we build UI.
	if not _ensure_terrain_arrays(terrain):
		return
	
	var vbox := VBoxContainer.new()
	# Wider panel so palette weight sliders fit without being clipped.
	vbox.set_custom_minimum_size(Vector2(300, 0))

	# Bake button: create external Texture2DArray resources from a linked MSTextureLibrary.
	var bake_row := HBoxContainer.new()
	bake_row.add_theme_constant_override("separation", -8)
	var bake_btn := Button.new()
	bake_btn.text = "Bake Texture Arrays"
	bake_btn.tooltip_text = "Bake assigned textures into external Texture2DArray .res files (uses texture_library on the terrain)."
	bake_btn.pressed.connect(self._on_bake_pressed)
	bake_row.add_child(bake_btn)

	# Quick Setup: auto-create library, bake into same folder, assign and set BAKED
	var quick_btn := Button.new()
	quick_btn.text = "Quick Setup (Auto)"
	quick_btn.tooltip_text = "Auto-create MSTextureLibrary, bake arrays into the terrain data folder, assign and switch to BAKED mode."
	quick_btn.pressed.connect(self._on_quick_setup_pressed)
	quick_btn.focus_mode = Control.FOCUS_NONE
	quick_btn.set_custom_minimum_size(Vector2(160, 25))
	bake_row.add_child(quick_btn)

	vbox.add_child(bake_row, true)

	var preset := terrain.current_texture_preset
	var names : Array[String] = []
	if preset and preset.new_tex_names:
		MarchingSquaresTerrainPlugin._ensure_texture_names_resource(preset.new_tex_names)
		names = preset.new_tex_names.get("texture_names")
	elif vp_tex_names:
		MarchingSquaresTerrainPlugin._ensure_texture_names_resource(vp_tex_names)
		names = vp_tex_names.get("texture_names")
	
	# "Ghost" slot: Global Noise (not a texture slot).
	var gn_name_row := HBoxContainer.new()
	gn_name_row.add_theme_constant_override("separation", -16)
	var gn_label := Label.new()
	gn_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gn_label.text = "Global Noise"
	gn_label.set_custom_minimum_size(Vector2(220, 25))
	gn_label.tooltip_text = "Texture used by the shader's global noise multiplier (not a texture slot)"
	gn_name_row.add_child(gn_label, true)
	vbox.add_child(gn_name_row, true)

	var gn_picker := EditorResourcePicker.new()
	gn_picker.set_base_type("Texture2D")
	var gn_tex: Texture2D = terrain.get("global_noise_texture")
	if gn_tex !=  null and not (gn_tex is Texture2D):
		gn_tex = null
	gn_picker.edited_resource = gn_tex
	gn_picker.set_custom_minimum_size(Vector2(100, 25))
	gn_picker.resource_changed.connect(func(resource):
		if resource !=  null and not (resource is Texture2D):
			resource = null
		terrain.set("global_noise_texture", resource)
	)
	vbox.add_child(gn_picker, true)

	# Strength/scale controls for Global Noise (stored on the terrain node).
	var gn_strength_hbox := HBoxContainer.new()
	gn_strength_hbox.set_custom_minimum_size(Vector2(150, 20))
	var gn_strength_label := Label.new()
	gn_strength_label.text = "Strength:"
	gn_strength_label.set_custom_minimum_size(Vector2(70, 20))
	gn_strength_hbox.add_child(gn_strength_label)
	var gn_strength_slider := EditorSpinSlider.new()
	gn_strength_slider.set_flat(true)
	gn_strength_slider.set_min(0.0)
	gn_strength_slider.set_max(1.0)
	gn_strength_slider.set_step(0.01)
	var gn_strength_val := terrain.get("global_noise_strength")
	if gn_strength_val is float or gn_strength_val is int:
		gn_strength_slider.set_value(float(gn_strength_val))
	else:
		gn_strength_slider.set_value(1.0)
	gn_strength_slider.value_changed.connect(func(v): terrain.set("global_noise_strength", float(v)))
	gn_strength_slider.set_custom_minimum_size(Vector2(95, 25))
	gn_strength_hbox.add_child(gn_strength_slider)
	vbox.add_child(gn_strength_hbox, true)

	var gn_scale_hbox := HBoxContainer.new()
	gn_scale_hbox.set_custom_minimum_size(Vector2(150, 20))
	var gn_scale_label := Label.new()
	gn_scale_label.text = "Scale:"
	gn_scale_label.set_custom_minimum_size(Vector2(70, 20))
	gn_scale_hbox.add_child(gn_scale_label)
	var gn_scale_slider := EditorSpinSlider.new()
	gn_scale_slider.set_flat(true)
	gn_scale_slider.set_min(0.001)
	gn_scale_slider.set_max(1.0)
	gn_scale_slider.set_step(0.001)
	var gn_scale_val := terrain.get("global_noise_scale")
	if gn_scale_val is float or gn_scale_val is int:
		gn_scale_slider.set_value(float(gn_scale_val))
	else:
		gn_scale_slider.set_value(0.037)
	gn_scale_slider.value_changed.connect(func(v): terrain.set("global_noise_scale", float(v)))
	gn_scale_slider.set_custom_minimum_size(Vector2(95, 25))
	gn_scale_hbox.add_child(gn_scale_slider)
	vbox.add_child(gn_scale_hbox, true)

	vbox.add_child(HSeparator.new())

	var visible_count := clampi(int(terrain.visible_texture_slot_count), 1, 256)
	
	for i in range(visible_count):
		var slot_idx := i
		var slot_obj = terrain.texture_slots[slot_idx] if slot_idx < terrain.texture_slots.size() else null
		# Hide inactive slots (except reserved ones).
		if slot_idx !=  0 and slot_idx != 15 and slot_obj != null and bool(slot_obj.get("active")) == false:
			continue
		
		# Slot display name (saved in preset.new_tex_names when a preset is active)
		var name_row := HBoxContainer.new()
		# Negative separation makes the X "push into" the name field visually.
		name_row.add_theme_constant_override("separation", -16)
		
		var name_edit := LineEdit.new()
		name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_edit.text = names[slot_idx] if slot_idx < names.size() else ("Texture " + str(slot_idx + 1))
		name_edit.placeholder_text = "Texture %d" % (slot_idx + 1)
		name_edit.set_custom_minimum_size(Vector2(220, 25))
		name_edit.tooltip_text = "Rename this texture slot (saved in the active preset)"
		
		var remove_btn := Button.new()
		remove_btn.text = "X"
		remove_btn.flat = true
		remove_btn.focus_mode = Control.FOCUS_NONE
		remove_btn.set_custom_minimum_size(Vector2(22, 25))
		remove_btn.tooltip_text = "Deactivate (clear) this texture slot"
		
		# Texture 1 and Void are reserved.
		if slot_idx == 0:
			remove_btn.disabled = true
			remove_btn.tooltip_text = "Texture 1 is reserved"
		if slot_idx == 15:
			name_edit.text = "Void"
			name_edit.editable = false
			name_edit.tooltip_text = "Void (reserved)"
			remove_btn.disabled = true
			remove_btn.tooltip_text = "Void is reserved"
		
		# Only persist names into a real preset resource.
		var persist_name := func(p_idx: int):
			if preset == null or preset.new_tex_names == null:
				return
			MarchingSquaresTerrainPlugin._ensure_texture_names_resource(preset.new_tex_names)
			var n := preset.new_tex_names.get("texture_names")
			if n is Array and p_idx < n.size():
				n[p_idx] = name_edit.text
				preset.new_tex_names.set("texture_names", n)
			# Refresh dropdowns (Material + Default Wall)
			if plugin and plugin.ui and plugin.ui.tool_attributes:
				plugin.ui.tool_attributes.show_tool_attributes(plugin.ui.active_tool)
			if preset.resource_path !=  null and not str(preset.resource_path).is_empty():
				ResourceSaver.save(preset)
		
		var deactivate_slot := func(p_idx: int):
			if terrain == null:
				return
			if p_idx == 15:
				return
			
			if not _ensure_terrain_arrays(terrain):
				return
			
			if terrain.texture_slots[p_idx] == null:
				terrain.texture_slots[p_idx] = _TEXTURE_SLOT_SCRIPT.new()
			terrain.texture_slots[p_idx].active = false
			terrain.texture_slots[p_idx].texture = null
			terrain.texture_slots[p_idx].scale = 1.0
			terrain.texture_slots[p_idx].terrain_texture_index = (p_idx if p_idx < 15 else 0)
			
			# Reset per-slot palette/outline settings too (so the slot truly clears).
			if p_idx >=  0 and p_idx < terrain.slot_color_indices.size():
				terrain.slot_color_indices[p_idx] = []
			if p_idx >=  0 and p_idx < terrain.slot_blend_modes.size():
				terrain.slot_blend_modes[p_idx] = 3
			if p_idx >=  0 and p_idx < terrain.slot_has_outline.size():
				terrain.slot_has_outline[p_idx] = false
			if p_idx >=  0 and p_idx < terrain.slot_outline_modes.size():
				terrain.slot_outline_modes[p_idx] = 0
			if p_idx >=  0 and p_idx < terrain.slot_outline_widths.size():
				var ow := terrain.get("outline_width")
				terrain.slot_outline_widths[p_idx] = float(ow) if (ow is float or ow is int) else 6.0
			if terrain.get("slot_wet_enabled") is Array and p_idx >=  0 and p_idx < terrain.slot_wet_enabled.size():
				terrain.slot_wet_enabled[p_idx] = false
			if terrain.get("slot_wet_modes") is Array and p_idx >=  0 and p_idx < terrain.slot_wet_modes.size():
				terrain.slot_wet_modes[p_idx] = 0
			if terrain.get("slot_roughnesses") is Array and p_idx >=  0 and p_idx < terrain.slot_roughnesses.size():
				terrain.slot_roughnesses[p_idx] = 1.0
			
			# Keep legacy properties in sync for slots 1..15 so presets save correctly.
			if p_idx >=  0 and p_idx < 15:
				terrain.set("texture_%d" % (p_idx + 1), null)
				terrain.set("texture_scale_%d" % (p_idx + 1), 1.0)
				# Clear legacy grass toggle for slots 2..6 (indices 1..5)
				if p_idx >=  1 and p_idx <= 5:
					terrain.set("tex%d_has_grass" % (p_idx + 1), false)
			else:
				# Non-base slots do not require rebuilding the terrain Texture2DArray anymore.
				terrain._push_tex_scales()
			
			# Push palette lookup textures to materials.
			terrain._rebuild_palette_uniforms()
			
			if terrain.current_texture_preset !=  null and not terrain.current_texture_preset.resource_path.is_empty():
				terrain.save_to_preset()
			
			# Refresh UI + dropdowns.
			if plugin and plugin.ui and plugin.ui.tool_attributes:
				plugin.ui.tool_attributes.show_tool_attributes(plugin.ui.active_tool)
			call_deferred("add_texture_settings")
		
		name_edit.text_submitted.connect(func(_t, p_idx := slot_idx): persist_name.call(p_idx))
		name_edit.focus_exited.connect(func(p_idx := slot_idx): persist_name.call(p_idx))
		remove_btn.pressed.connect(func(p_idx := slot_idx): deactivate_slot.call(p_idx))
		
		name_row.add_child(name_edit, true)
		name_row.add_child(remove_btn, false)
		vbox.add_child(name_row, true)
		
		# Terrain texture picker (slot-based)
		var slot = terrain.texture_slots[i]
		var tex_var : Texture2D = slot.texture if slot != null else null
		if tex_var !=  null and not (tex_var is Texture2D):
			tex_var = null
		
		# For the reserved Void slot, don't allow editing the texture.
		if slot_idx == 15:
			var void_tex_label := Label.new()
			void_tex_label.text = "(Void texture is reserved)"
			vbox.add_child(void_tex_label, true)
		else:
			# Show per-slot albedo + normal pickers bound to MSTextureLibrary (for all slots except Void)
			var adv_h := HBoxContainer.new()
			adv_h.set_custom_minimum_size(Vector2(300, 24))
			# Albedo picker
			var alb_picker := EditorResourcePicker.new()
			alb_picker.set_base_type("Texture2D")
			var lib_res: Resource = terrain.get("texture_library") if terrain.has_method("get") else null
			var initial_albedo: Texture2D = null
			if lib_res !=  null and lib_res is MSTextureLibrary and slot_idx < lib_res.albedo_textures.size():
				var maybe_alb = lib_res.albedo_textures[slot_idx]
				if maybe_alb !=  null and maybe_alb is Texture2D:
					initial_albedo = maybe_alb
			else:
				if tex_var !=  null and tex_var is Texture2D:
					initial_albedo = tex_var
			alb_picker.edited_resource = initial_albedo
			alb_picker.resource_changed.connect(func(resource, p_idx :=  slot_idx):
				if resource !=  null and not (resource is Texture2D):
					resource = null
				if not _ensure_terrain_arrays(terrain):
					return
				if terrain.texture_slots[p_idx] == null:
					terrain.texture_slots[p_idx] = _TEXTURE_SLOT_SCRIPT.new()
				terrain.texture_slots[p_idx].texture = resource
				# Also write into MSTextureLibrary if present
				if lib_res !=  null and lib_res is MSTextureLibrary and p_idx != 15:
					lib_res.albedo_textures[p_idx] = resource
					if lib_res.resource_path !=  null and not str(lib_res.resource_path).is_empty():
						ResourceSaver.save(lib_res, lib_res.resource_path)
				# Invalidate any previously-baked arrays so the runtime will rebuild from the updated library/slots
				terrain.set("baked_albedo_array_path", "")
				terrain.set("baked_normal_array_path", "")
				# Rebuild arrays so materials update
				terrain.rebuild_texture_array()
			)
			alb_picker.set_custom_minimum_size(Vector2(140, 25))
			adv_h.add_child(alb_picker)
			# Normal picker
			var nrm_picker := EditorResourcePicker.new()
			nrm_picker.set_base_type("Texture2D")
			var initial_norm: Texture2D = null
			if lib_res !=  null and lib_res is MSTextureLibrary and slot_idx < lib_res.normal_textures.size():
				var maybe_nrm = lib_res.normal_textures[slot_idx]
				if maybe_nrm !=  null and maybe_nrm is Texture2D:
					initial_norm = maybe_nrm
			nrm_picker.edited_resource = initial_norm
			nrm_picker.resource_changed.connect(func(resource, p_idx :=  slot_idx):
				if resource !=  null and not (resource is Texture2D):
					resource = null
				if not _ensure_terrain_arrays(terrain):
					return
				# Also write into MSTextureLibrary if present
				if lib_res !=  null and lib_res is MSTextureLibrary and p_idx != 15:
					lib_res.normal_textures[p_idx] = resource
					if lib_res.resource_path !=  null and not str(lib_res.resource_path).is_empty():
						ResourceSaver.save(lib_res, lib_res.resource_path)
				# Clear baked normal array so runtime will pick up updated normals from the library
				terrain.set("baked_normal_array_path", "")
				# Rebuild runtime arrays so material updates (normals require rebuild)
				if terrain.has_method("rebuild_texture_array"):
					terrain.rebuild_texture_array()			)
			nrm_picker.set_custom_minimum_size(Vector2(140, 25))
			adv_h.add_child(nrm_picker)
			vbox.add_child(adv_h, true)
		
		# Grass settings are built next to outline settings in _build_palette_ui() for each slot.
		
		# Scale slider (slot-based)
		var scale_value : float = float(slot.scale) if slot != null else 1.0
		var scale_hbox := HBoxContainer.new()
		scale_hbox.set_custom_minimum_size(Vector2(150, 20))
		
		var scale_label := Label.new()
		scale_label.text = "Scale:"
		scale_label.set_custom_minimum_size(Vector2(40, 20))
		scale_hbox.add_child(scale_label)
		
		var c_cont_2 := CenterContainer.new()
		var scale_slider := HSlider.new()
		scale_slider.min_value = 0.1
		scale_slider.max_value = 40.0
		scale_slider.step = 0.1
		scale_slider.set_custom_minimum_size(Vector2(80, 20))
		scale_slider.drag_ended.connect(func(val): _on_slider_drag_ended(val))
		c_cont_2.add_child(scale_slider, true)
		scale_slider.set_value_no_signal(scale_value)
		scale_slider.value_changed.connect(func(val, p_idx :=  slot_idx):
			if not _ensure_terrain_arrays(terrain):
				return
			if terrain.texture_slots[p_idx] == null:
				terrain.texture_slots[p_idx] = _TEXTURE_SLOT_SCRIPT.new()
			terrain.texture_slots[p_idx].scale = float(val)
			
			# Keep legacy properties in sync for slots 1..15 so presets save correctly.
			if p_idx >=  0 and p_idx < 15:
				terrain.set("texture_scale_%d" % (p_idx + 1), float(val))
			else:
				terrain._push_tex_scales()
			
			if terrain.current_texture_preset !=  null and not terrain.current_texture_preset.resource_path.is_empty():
				terrain.save_to_preset()
		)
		scale_hbox.add_child(c_cont_2, true)
		
		var scale_value_label := Label.new()
		scale_value_label.text = str(scale_value)
		scale_value_label.set_custom_minimum_size(Vector2(25, 20))
		scale_slider.value_changed.connect(func(val): scale_value_label.text = str(snapped(val, 0.1)))
		scale_hbox.add_child(scale_value_label)
		
		vbox.add_child(scale_hbox, true)
		
		# Palette UI for ALL visible slots
		_build_palette_ui(vbox, terrain, i)
		
		vbox.add_child(HSeparator.new())
	
	# Reveal more slots without rendering all 256 controls by default.
	var add_button := Button.new()
	add_button.text = "+ Add Texture"
	add_button.pressed.connect(func():
		if not _ensure_terrain_arrays(terrain):
			return
		
		# Prefer re-enabling the first inactive slot that is already in-range.
		var made_active := false
		for idx in range(clampi(int(terrain.visible_texture_slot_count), 1, 256)):
			if idx == 0 or idx == 15:
				continue
			var s = terrain.texture_slots[idx]
			if s !=  null and bool(s.get("active")) == false:
				s.active = true
				made_active = true
				break
		
		# Otherwise, extend the visible range by one.
		if not made_active:
			terrain.visible_texture_slot_count = mini(int(terrain.visible_texture_slot_count) + 1, 256)
		
		if terrain.current_texture_preset !=  null and not terrain.current_texture_preset.resource_path.is_empty():
			terrain.save_to_preset()
		call_deferred("add_texture_settings")
	)
	vbox.add_child(add_button, true)
	
	var m_cont := MarginContainer.new()
	m_cont.add_theme_constant_override("margin_bottom", 7)
	var export_button := MarchingSquaresTexturePresetExporter.new()
	export_button.current_terrain_node = terrain
	m_cont.add_child(export_button, true)
	vbox.add_child(m_cont, true)
	
	add_child(vbox, true)
	

func _on_texture_setting_changed(p_setting_name: String, p_value: Variant) -> void:
	emit_signal("texture_setting_changed", p_setting_name, p_value)


func _build_palette_ui(vbox: VBoxContainer, terrain: MarchingSquaresTerrain, slot: int) -> void:
	# Blend mode dropdown
	var blend_hbox := HBoxContainer.new()
	var blend_label := Label.new()
	blend_label.text = "Blend:"
	blend_label.set_custom_minimum_size(Vector2(50, 20))
	blend_hbox.add_child(blend_label)
	
	var blend_opt := OptionButton.new()
	blend_opt.add_item("Gradient", 0)
	blend_opt.add_item("Retro", 1)
	blend_opt.add_item("Dithered", 2)
	blend_opt.add_item("Stippled", 3)
	blend_opt.selected = terrain.slot_blend_modes[slot]
	blend_opt.set_custom_minimum_size(Vector2(95, 25))
	blend_opt.item_selected.connect(func(idx):
		terrain.slot_blend_modes[slot] = idx
		terrain._rebuild_palette_uniforms()
		terrain.save_to_preset()
	)
	blend_hbox.add_child(blend_opt)
	vbox.add_child(blend_hbox, true)
	
	# Color rows
	var slot_indices : Array = terrain.slot_color_indices[slot]
	for ci in range(slot_indices.size()):
		var palette_idx : int = slot_indices[ci]
		var c_hbox := HBoxContainer.new()
		c_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c_hbox.set_custom_minimum_size(Vector2(0, 25))
		
		var c_label := Label.new()
		c_label.text = "Color " + str(ci + 1) + ":"
		c_label.set_custom_minimum_size(Vector2(50, 20))
		c_hbox.add_child(c_label)
		
		var c_btn := ColorPickerButton.new()
		c_btn.color = terrain.palette_colors[palette_idx]
		c_btn.set_custom_minimum_size(Vector2(65, 25))
		c_btn.color_changed.connect(func(new_color, pidx =  palette_idx):
			terrain.palette_colors[pidx] = new_color
			terrain._rebuild_palette_uniforms()
			terrain.save_to_preset()
		)
		c_hbox.add_child(c_btn)
		
		# Only show weights once a slot has 2+ colors
		if slot_indices.size() > 1:
			terrain._ensure_palette_weights()
			var w_label := Label.new()
			w_label.text = str(int(round(terrain.palette_weights[palette_idx]))) + "%"
			w_label.set_custom_minimum_size(Vector2(32, 20))
			c_hbox.add_child(w_label)
			
			var w_slider := HSlider.new()
			w_slider.min_value = 0.0
			w_slider.max_value = 100.0
			w_slider.step = 1.0
			w_slider.value = clampf(float(terrain.palette_weights[palette_idx]), 0.0, 100.0)
			w_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			w_slider.set_custom_minimum_size(Vector2(90, 25))
			w_slider.value_changed.connect(func(val, s =  slot, pidx = palette_idx):
				if not is_instance_valid(terrain) or not is_instance_valid(plugin.current_terrain_node) or plugin.current_terrain_node !=  terrain:
					return
				terrain._ensure_palette_weights()
				var indices: Array = terrain.slot_color_indices[s]
				if indices.size() <=  1:
					return
				
				var new_v := clampf(float(val), 0.0, 100.0)
				terrain.palette_weights[pidx] = new_v
				w_label.text = str(int(round(new_v))) + "%"
				
				var remaining := 100.0 - new_v
				var others: Array = []
				var total_other := 0.0
				for idx in indices:
					if idx == pidx:
						continue
					others.append(idx)
					total_other += float(terrain.palette_weights[idx])
				
				if others.size() > 0:
					if total_other <=  0.0001:
						var each := remaining / float(others.size())
						for idx in others:
							terrain.palette_weights[idx] = each
					else:
						for idx in others:
							terrain.palette_weights[idx] = float(terrain.palette_weights[idx]) / total_other * remaining
				
				terrain._rebuild_palette_uniforms()
			)
			w_slider.drag_ended.connect(func(_ended):
				if not is_instance_valid(terrain) or not is_instance_valid(plugin.current_terrain_node) or plugin.current_terrain_node !=  terrain:
					return
				terrain.save_to_preset()
				add_texture_settings()
			)
			c_hbox.add_child(w_slider)
		
		var remove_btn := Button.new()
		remove_btn.text = "X"
		remove_btn.set_custom_minimum_size(Vector2(25, 25))
		remove_btn.pressed.connect(func(s =  slot, ci_idx = ci):
			if not is_instance_valid(terrain) or not is_instance_valid(plugin.current_terrain_node) or plugin.current_terrain_node !=  terrain:
				return
			terrain.slot_color_indices[s].remove_at(ci_idx)
			terrain._ensure_palette_weights()
			var indices: Array = terrain.slot_color_indices[s]
			if indices.size() > 0:
				var each := 100.0 / float(indices.size())
				for idx in indices:
					terrain.palette_weights[idx] = each
			terrain._rebuild_palette_uniforms()
			terrain.save_to_preset()
			add_texture_settings()
		)
		c_hbox.add_child(remove_btn)
		vbox.add_child(c_hbox, true)
	
	# Add Color button
	var add_btn := Button.new()
	add_btn.text = "+ Add Color"
	add_btn.set_custom_minimum_size(Vector2(150, 25))
	add_btn.pressed.connect(func(s =  slot):
		if not is_instance_valid(terrain) or not is_instance_valid(plugin.current_terrain_node) or plugin.current_terrain_node !=  terrain:
			return
		# Find first unused palette index
		var used : Array = []
		for si in range(15):
			for idx in terrain.slot_color_indices[si]:
				used.append(idx)
		var next_idx := 0
		while next_idx < 128 and next_idx in used:
			next_idx += 1
		if next_idx >=  128:
			push_error("[MST] Palette is full (128 colors max)")
			return
		terrain.palette_colors[next_idx] = Color("647851ff")
		terrain.slot_color_indices[s].append(next_idx)
		terrain._ensure_palette_weights()
		var indices: Array = terrain.slot_color_indices[s]
		var each := 100.0 / float(max(indices.size(), 1))
		for idx in indices:
			terrain.palette_weights[idx] = each
		terrain._rebuild_palette_uniforms()
		terrain.save_to_preset()
		add_texture_settings()
	)
	vbox.add_child(add_btn, true)

	# Grass settings (slot-based)
	var slot_res = terrain.texture_slots[slot]
	var has_grass_var := bool(slot_res.has_grass) if slot_res != null else (slot == 0)
	var grass_cb := CheckBox.new()
	grass_cb.text = "Has Grass"
	grass_cb.set_flat(true)
	grass_cb.button_pressed = has_grass_var
	grass_cb.set_custom_minimum_size(Vector2(25, 15))

	var grass_center := CenterContainer.new()
	grass_center.set_custom_minimum_size(Vector2(25, 25))
	grass_center.add_child(grass_cb, true)
	vbox.add_child(grass_center, true)

	var grass_picker := EditorResourcePicker.new()
	grass_picker.set_base_type("Texture2D")
	var grass_tex_var : Texture2D = slot_res.grass_texture if slot_res != null else null
	if grass_tex_var !=  null and not (grass_tex_var is Texture2D):
		grass_tex_var = null
	grass_picker.edited_resource = grass_tex_var
	grass_picker.visible = grass_cb.button_pressed
	grass_picker.set_custom_minimum_size(Vector2(100, 25))
	vbox.add_child(grass_picker, true)

	grass_cb.toggled.connect(func(pressed: bool, p_idx :=  slot):
		grass_picker.visible = pressed
		if not _ensure_terrain_arrays(terrain):
			return
		if terrain.texture_slots[p_idx] == null:
			terrain.texture_slots[p_idx] = _TEXTURE_SLOT_SCRIPT.new()
		terrain.texture_slots[p_idx].has_grass = pressed

		# Keep legacy properties in sync for slots 1..6 so presets/UI stay compatible.
		if p_idx >=  0 and p_idx < 6:
			terrain.set("tex%d_has_grass" % (p_idx + 1), pressed)
		else:
			if terrain.has_method("_request_grass_regen"):
				terrain._request_grass_regen()

		if terrain.current_texture_preset !=  null and not terrain.current_texture_preset.resource_path.is_empty():
			terrain.save_to_preset()
	)

	grass_picker.resource_changed.connect(func(resource, p_idx :=  slot):
		if resource !=  null and not (resource is Texture2D):
			resource = null
		if not _ensure_terrain_arrays(terrain):
			return
		if terrain.texture_slots[p_idx] == null:
			terrain.texture_slots[p_idx] = _TEXTURE_SLOT_SCRIPT.new()
		terrain.texture_slots[p_idx].grass_texture = resource

		# Keep legacy properties in sync for slots 1..6 so presets/UI stay compatible.
		if p_idx >=  0 and p_idx < 6:
			terrain.set("grass_sprite_tex_%d" % (p_idx + 1), resource)
		else:
			if terrain.has_method("rebuild_grass_texture_array"):
				terrain.rebuild_grass_texture_array()
			if terrain.has_method("_request_grass_regen"):
				terrain._request_grass_regen()

		if terrain.current_texture_preset !=  null and not terrain.current_texture_preset.resource_path.is_empty():
			terrain.save_to_preset()
	)

	# Wetness (per slot)
	var wet_cb := CheckBox.new()
	wet_cb.text = "Wetness"
	wet_cb.set_flat(true)
	wet_cb.button_pressed = bool(terrain.slot_wet_enabled[slot]) if (terrain.get("slot_wet_enabled") is Array and slot >= 0 and slot < terrain.slot_wet_enabled.size()) else false
	wet_cb.set_custom_minimum_size(Vector2(25, 15))
	var wet_center := CenterContainer.new()
	wet_center.set_custom_minimum_size(Vector2(25, 25))
	wet_center.add_child(wet_cb, true)
	vbox.add_child(wet_center, true)

	var wet_mode_hbox := HBoxContainer.new()
	wet_mode_hbox.set_custom_minimum_size(Vector2(150, 20))
	var wet_mode_label := Label.new()
	wet_mode_label.text = "Mode:"
	wet_mode_label.set_custom_minimum_size(Vector2(50, 20))
	wet_mode_hbox.add_child(wet_mode_label)
	var wet_mode_opt := OptionButton.new()
	wet_mode_opt.add_item("Wet", 0)
	wet_mode_opt.add_item("Glossy Puddles", 1)
	wet_mode_opt.selected = int(terrain.slot_wet_modes[slot]) if (terrain.get("slot_wet_modes") is Array and slot >= 0 and slot < terrain.slot_wet_modes.size()) else 0
	wet_mode_opt.set_custom_minimum_size(Vector2(95, 25))
	wet_mode_hbox.add_child(wet_mode_opt)
	wet_mode_hbox.visible = wet_cb.button_pressed
	vbox.add_child(wet_mode_hbox, true)

	var wetness_hbox := HBoxContainer.new()
	wetness_hbox.set_custom_minimum_size(Vector2(150, 20))
	var wetness_label := Label.new()
	wetness_label.text = "Wetness:"
	wetness_label.set_custom_minimum_size(Vector2(70, 20))
	wetness_hbox.add_child(wetness_label)
	var wetness_slider := EditorSpinSlider.new()
	wetness_slider.set_flat(true)
	wetness_slider.set_min(0.0)
	wetness_slider.set_max(1.0)
	wetness_slider.set_step(0.05)
	# Stored as roughness: roughness = 1 - wetness.
	if terrain.get("slot_roughnesses") is Array and slot >=  0 and slot < terrain.slot_roughnesses.size():
		wetness_slider.set_value(1.0 - float(terrain.slot_roughnesses[slot]))
	else:
		wetness_slider.set_value(0.0)
	wetness_slider.set_custom_minimum_size(Vector2(95, 25))
	wetness_hbox.add_child(wetness_slider)
	wetness_hbox.visible = wet_cb.button_pressed
	vbox.add_child(wetness_hbox, true)

	wet_cb.toggled.connect(func(pressed: bool):
		if not _ensure_terrain_arrays(terrain):
			return
		if terrain.get("slot_wet_enabled") is Array and slot >=  0 and slot < terrain.slot_wet_enabled.size():
			terrain.slot_wet_enabled[slot] = pressed
		wet_mode_hbox.visible = pressed
		wetness_hbox.visible = pressed
		terrain._rebuild_palette_uniforms()
		terrain.save_to_preset()
	)

	wet_mode_opt.item_selected.connect(func(idx: int):
		if not _ensure_terrain_arrays(terrain):
			return
		if terrain.get("slot_wet_modes") is Array and slot >=  0 and slot < terrain.slot_wet_modes.size():
			terrain.slot_wet_modes[slot] = idx
		terrain._rebuild_palette_uniforms()
		terrain.save_to_preset()
	)

	wetness_slider.value_changed.connect(func(value: float):
		if not _ensure_terrain_arrays(terrain):
			return
		if terrain.get("slot_roughnesses") is Array and slot >=  0 and slot < terrain.slot_roughnesses.size():
			terrain.slot_roughnesses[slot] = clampf(1.0 - float(value), 0.0, 1.0)
		terrain._rebuild_palette_uniforms()
		terrain.save_to_preset()
	)

	# Outline settings removed by user request.
	# Outline flags remain in the backend but are no longer exposed in the UI.


func _on_slider_drag_ended(ended: bool) -> void:
	if plugin == null or plugin.current_terrain_node == null:
		return
	for chunk: MarchingSquaresTerrainChunk in plugin.current_terrain_node.chunks.values():
		chunk.grass_planter.regenerate_all_cells()

func _on_bake_pressed() -> void:
	var terrain := plugin.current_terrain_node
	if terrain == null:
		push_error("[MST] No terrain selected to bake textures for.")
		return
	var lib := terrain.get("texture_library") if terrain.has_method("get") else null
	if lib == null:
		push_error("[MST] Terrain has no texture_library assigned. Assign an MSTextureLibrary resource first.")
		return
	var out_dir := "res://scenes/baked_texture_arrays"
	# If the terrain has a data_directory, prefer saving alongside it (convert Windows paths to resource-style).
	if terrain.get("data_directory") !=  null and terrain.get("data_directory") != "":
		out_dir = str(terrain.get("data_directory")).replace("", "/")
		if out_dir.ends_with("/"):
			out_dir = out_dir + "baked_texture_arrays"
		else:
			out_dir = out_dir + "/baked_texture_arrays"

	var baker := MarchingSquaresBaker.new()
	var results := baker.bake_library(lib, out_dir, int(terrain.get("baked_texture_size")))
	if results.size() == 0:
		push_error("[MST] Baking failed or produced no results.")
		return
	if results.has("albedo_path") and results["albedo_path"] !=  "":
		terrain.set("baked_albedo_array_path", results["albedo_path"])
	if results.has("normal_path") and results["normal_path"] !=  "":
		terrain.set("baked_normal_array_path", results["normal_path"])
	if results.has("grass_path") and results["grass_path"] !=  "":
		terrain.set("baked_grass_array_path", results["grass_path"])

	# Rebuild runtime arrays so material uses the newly baked resources.
	MarchingSquaresTerrainHelpers.rebuild_texture_array(terrain)
	MarchingSquaresTerrainHelpers.rebuild_grass_texture_array(terrain)


func _on_quick_setup_pressed() -> void:
	var terrain := plugin.current_terrain_node
	if terrain == null:
		push_error("[MST] No terrain selected for Quick Setup.")
		return
	# Use terrain data_directory if available, else fallback to scenes folder
	var out_dir := "res://scenes"
	if terrain.get("data_directory") !=  null and str(terrain.get("data_directory")).length() > 0:
		out_dir = str(terrain.get("data_directory")).replace("", "/")

	# Ensure output directory exists on disk
	var out_abs := ProjectSettings.globalize_path(out_dir)
	if not DirAccess.dir_exists_absolute(out_abs):
		DirAccess.make_dir_recursive_absolute(out_abs)

	# Build MSTextureLibrary from current terrain slots
	var lib := MSTextureLibraryScript.new()
	lib.max_slots = MAX_TEXTURE_SLOTS
	lib.ensure_length()
	if terrain.has_method("get") and terrain.get("texture_slots") is Array:
		for i in range(MAX_TEXTURE_SLOTS):
			var slot = terrain.texture_slots[i] if i < terrain.texture_slots.size() else null
			# Never populate the reserved Void slot (index 15)
			if i == 15:
				continue
			if slot !=  null and slot.texture != null and slot.texture is Texture2D:
				lib.albedo_textures[i] = slot.texture
			# Copy normal if the slot exposes a normal_texture field
			if slot !=  null and slot.has_method("get") and slot.get("normal_texture") != null and slot.get("normal_texture") is Texture2D:
				lib.normal_textures[i] = slot.get("normal_texture")
			if slot !=  null and slot.has_grass and slot.grass_texture != null and slot.grass_texture is Texture2D:
				lib.grass_textures[i] = slot.grass_texture

	# Save MSTextureLibrary next to the terrain data directory
	var lib_path := out_dir.path_join("mst_texture_library.tres")
	var save_res := ResourceSaver.save(lib, lib_path)
	if save_res !=  OK:
		push_error("[MST] Failed to save MSTextureLibrary: %s" % str(save_res))
		return

	# Assign the saved library resource to the terrain
	var lib_res := ResourceLoader.load(lib_path)
	if lib_res == null:
		push_error("[MST] Failed to load saved MSTextureLibrary at %s" % lib_path)
		return
	terrain.set("texture_library", lib_res)

	# Run baker to create baked arrays into the same folder
	var baker := MarchingSquaresBaker.new()
	var bake_size := int(terrain.get("baked_texture_size")) if terrain.get("baked_texture_size") != null else 512
	var results := baker.bake_library(lib_res, out_dir, bake_size)
	if results.size() == 0:
		push_error("[MST] Quick Setup: Baking failed or produced no results.")
		return
	if results.has("albedo_path") and results["albedo_path"] !=  "":
		terrain.set("baked_albedo_array_path", results["albedo_path"])
	if results.has("normal_path") and results["normal_path"] !=  "":
		terrain.set("baked_normal_array_path", results["normal_path"])
	if results.has("grass_path") and results["grass_path"] !=  "":
		terrain.set("baked_grass_array_path", results["grass_path"])

	# Switch to BAKED mode and rebuild runtime arrays
	terrain.set("storage_mode", MarchingSquaresTerrain.StorageMode.BAKED)
	MarchingSquaresTerrainHelpers.rebuild_texture_array(terrain)
	MarchingSquaresTerrainHelpers.rebuild_grass_texture_array(terrain)
	call_deferred("add_texture_settings")
	push_warning("[MST] Quick Setup completed. Library and baked arrays saved to: %s" % out_dir)
