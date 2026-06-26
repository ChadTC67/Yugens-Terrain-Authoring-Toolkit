@tool
extends ScrollContainer
class_name MarchingSquaresTextureSettings


signal texture_setting_changed(setting: String, value: Variant)

var plugin : MarchingSquaresTerrainPlugin
var vp_tex_names : MarchingSquaresTextureNames = preload("uid://dd7fens03aosa")
var _built_for_terrain_id: int = 0

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
	# Keep the painter dock narrow; child controls manage their own click targets.
	set_custom_minimum_size(Vector2(205, 0))
	add_theme_constant_override("separation", 5)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER


func _ensure_terrain_arrays(terrain: Object) -> bool:
	if terrain == null:
		return false
	
	# Avoid calling into the terrain script from the editor UI.
	# In editor reload/order edge-cases the selected node can be a plain Node3D or a placeholder script,
	# Which makes method calls like _ensure_texture_slots() fail even though exported properties exist.
	var slots_var = terrain.get("texture_slots")
	if not (slots_var is Array):
		push_error("[MST] Selected node doesn't expose texture_slots. Select the MarchingSquaresTerrain node (with script attached).")
		return false
	if slots_var.size() != MAX_TEXTURE_SLOTS:
		slots_var.resize(MAX_TEXTURE_SLOTS)
	for i in range(MAX_TEXTURE_SLOTS):
		if slots_var[i] == null:
			slots_var[i] = _TEXTURE_SLOT_SCRIPT.new()
		# Default any missing 'active' to true (older saves won't have it).
		if slots_var[i] != null and slots_var[i].get("active") == null:
			slots_var[i].active = true
		# Default slot->base-texture mapping for older slot resources.
		if slots_var[i] != null and slots_var[i].get("terrain_texture_index") == null:
			if i == 15:
				slots_var[i].terrain_texture_index = 15
			elif i < 15:
				slots_var[i].terrain_texture_index = i
			else:
				slots_var[i].terrain_texture_index = 0
		elif slots_var[i] != null:
			slots_var[i].terrain_texture_index = clampi(int(slots_var[i].terrain_texture_index), 0, 15)
		# Default grass fields for older slot resources.
		if slots_var[i] != null and slots_var[i].get("has_grass") == null:
			slots_var[i].has_grass = (i == 0)
		if slots_var[i] != null and slots_var[i].get("grass_texture") == null:
			slots_var[i].grass_texture = null
	
	# Palette-per-slot arrays (all optional, but expected for the UI).
	var slot_color_indices = terrain.get("slot_color_indices")
	if slot_color_indices is Array:
		if slot_color_indices.size() != MAX_TEXTURE_SLOTS:
			slot_color_indices.resize(MAX_TEXTURE_SLOTS)
		for i in range(MAX_TEXTURE_SLOTS):
			if slot_color_indices[i] == null:
				slot_color_indices[i] = []
	
	var slot_blend_modes = terrain.get("slot_blend_modes")
	if slot_blend_modes is Array:
		if slot_blend_modes.size() != MAX_TEXTURE_SLOTS:
			slot_blend_modes.resize(MAX_TEXTURE_SLOTS)
		for i in range(MAX_TEXTURE_SLOTS):
			if slot_blend_modes[i] == null:
				slot_blend_modes[i] = 3
	
	var slot_wet_enabled = terrain.get("slot_wet_enabled")
	if slot_wet_enabled is Array:
		if slot_wet_enabled.size() != MAX_TEXTURE_SLOTS:
			slot_wet_enabled.resize(MAX_TEXTURE_SLOTS)
		for i in range(MAX_TEXTURE_SLOTS):
			if slot_wet_enabled[i] == null:
				slot_wet_enabled[i] = false

	var slot_wet_modes = terrain.get("slot_wet_modes")
	if slot_wet_modes is Array:
		if slot_wet_modes.size() != MAX_TEXTURE_SLOTS:
			slot_wet_modes.resize(MAX_TEXTURE_SLOTS)
		for i in range(MAX_TEXTURE_SLOTS):
			if slot_wet_modes[i] == null:
				slot_wet_modes[i] = 0
			slot_wet_modes[i] = clampi(int(slot_wet_modes[i]), 0, 1)

	var slot_roughnesses = terrain.get("slot_roughnesses")
	if slot_roughnesses is Array:
		if slot_roughnesses.size() != MAX_TEXTURE_SLOTS:
			slot_roughnesses.resize(MAX_TEXTURE_SLOTS)
		for i in range(MAX_TEXTURE_SLOTS):
			if slot_roughnesses[i] == null:
				slot_roughnesses[i] = 1.0
			slot_roughnesses[i] = clampf(float(slot_roughnesses[i]), 0.0, 1.0)
	
	_ensure_slot_noise_arrays(terrain)
	return true


func _ensure_slot_noise_arrays(terrain) -> void:
	var strength_default := 1.0
	var strength_value: Variant = terrain.get("global_noise_strength")
	if strength_value is float or strength_value is int:
		strength_default = float(strength_value)
	var scale_default := 0.037

	var defs: Array = [
		["slot_floor_noise_enabled", false],
		["slot_floor_noise_strengths", strength_default],
		["slot_floor_noise_scales", scale_default],
		["slot_wall_noise_enabled", false],
		["slot_wall_noise_strengths", strength_default],
		["slot_wall_noise_scales", scale_default],
	]
	for def in defs:
		var prop := String(def[0])
		var default_value = def[1]
		var arr = terrain.get(prop)
		if not (arr is Array):
			continue
		if arr.size() != MAX_TEXTURE_SLOTS:
			arr.resize(MAX_TEXTURE_SLOTS)
		for i in range(MAX_TEXTURE_SLOTS):
			if arr[i] == null:
				arr[i] = default_value
			if prop.ends_with("_strengths"):
				arr[i] = clampf(float(arr[i]), 0.0, 1.0)
			elif prop.ends_with("_scales"):
				arr[i] = clampf(float(arr[i]), 0.001, 1.0)


func _get_texture_library(terrain) -> Resource:
	if terrain == null or not terrain.has_method("get"):
		return null
	var lib_res: Resource = terrain.get("texture_library")
	if lib_res != null and lib_res is MSTextureLibraryScript:
		if lib_res.has_method("ensure_length"):
			lib_res.ensure_length()
		return lib_res
	if lib_res is Resource and lib_res.resource_path != null and not str(lib_res.resource_path).is_empty():
		var loaded := ResourceLoader.load(str(lib_res.resource_path))
		if loaded != null and loaded is MSTextureLibraryScript:
			if loaded.has_method("ensure_length"):
				loaded.ensure_length()
			terrain.set("texture_library", loaded)
			return loaded
	return null


func _save_resource_if_external(res: Resource) -> void:
	if res != null and res.resource_path != null and not str(res.resource_path).is_empty():
		ResourceSaver.save(res, res.resource_path)


func _sync_texture_library_from_slots(terrain, lib_res) -> void:
	if terrain == null or lib_res == null or not _ensure_terrain_arrays(terrain):
		return
	if lib_res.has_method("ensure_length"):
		lib_res.ensure_length()
	for i in range(min(MAX_TEXTURE_SLOTS, terrain.texture_slots.size())):
		var slot = terrain.texture_slots[i]
		if slot == null:
			continue
		if i < lib_res.albedo_textures.size():
			lib_res.albedo_textures[i] = slot.texture if slot.texture is Texture2D else null
		if i < lib_res.grass_textures.size():
			lib_res.grass_textures[i] = slot.grass_texture if slot.grass_texture is Texture2D else null
	_save_resource_if_external(lib_res)


func _sync_slot_legacy_fields(terrain, slot_idx: int) -> void:
	if terrain == null or slot_idx < 0 or slot_idx >= 15:
		return
	var slot = terrain.texture_slots[slot_idx] if slot_idx < terrain.texture_slots.size() else null
	var tex: Texture2D = slot.texture if slot != null and slot.texture is Texture2D else null
	var scale = float(slot.scale) if slot != null and slot.get("scale") != null else 1.0
	var was_batch = terrain.get("is_batch_updating") if terrain.has_method("get") else null
	if was_batch != null:
		terrain.set("is_batch_updating", true)
	terrain.set("texture_%d" % (slot_idx + 1), tex)
	terrain.set("texture_scale_%d" % (slot_idx + 1), scale)
	if was_batch != null:
		terrain.set("is_batch_updating", was_batch)


func _refresh_slot_runtime(terrain, p_refresh_ui: bool = false) -> void:
	if terrain == null:
		return
	terrain.set("baked_albedo_array_path", "")
	terrain.set("baked_normal_array_path", "")
	terrain.set("baked_grass_array_path", "")
	if terrain.has_method("rebuild_texture_array"):
		terrain.rebuild_texture_array()
	if terrain.has_method("rebuild_grass_texture_array"):
		terrain.rebuild_grass_texture_array()
	if terrain.has_method("_push_tex_scales"):
		terrain._push_tex_scales()
	if terrain.has_method("_rebuild_palette_uniforms"):
		terrain._rebuild_palette_uniforms()
	if terrain.has_method("_request_grass_regen"):
		terrain._request_grass_regen()
	if terrain.current_texture_preset != null and not terrain.current_texture_preset.resource_path.is_empty():
		terrain.save_to_preset()
	if plugin and plugin.ui and plugin.ui.tool_attributes:
		plugin.ui.tool_attributes.show_tool_attributes(plugin.ui.active_tool)
	if p_refresh_ui:
		call_deferred("add_texture_settings")


func _apply_slot_albedo(terrain, slot_idx: int, resource: Variant, p_refresh_ui: bool = false) -> void:
	if terrain == null or slot_idx < 0 or slot_idx >= MAX_TEXTURE_SLOTS or slot_idx == 15:
		return
	var texture: Texture2D = resource if resource is Texture2D else null
	if not _ensure_terrain_arrays(terrain):
		return
	if terrain.texture_slots[slot_idx] == null:
		terrain.texture_slots[slot_idx] = _TEXTURE_SLOT_SCRIPT.new()
	terrain.texture_slots[slot_idx].active = true
	terrain.texture_slots[slot_idx].texture = texture
	if slot_idx < 15:
		terrain.texture_slots[slot_idx].terrain_texture_index = slot_idx
	_sync_slot_legacy_fields(terrain, slot_idx)
	var lib_res := _get_texture_library(terrain)
	if lib_res != null and slot_idx < lib_res.albedo_textures.size():
		lib_res.albedo_textures[slot_idx] = texture
		_save_resource_if_external(lib_res)
	_refresh_slot_runtime(terrain, p_refresh_ui)


func _apply_slot_normal(terrain, slot_idx: int, resource: Variant) -> void:
	if terrain == null or slot_idx < 0 or slot_idx >= MAX_TEXTURE_SLOTS or slot_idx == 15:
		return
	var texture: Texture2D = resource if resource is Texture2D else null
	if not _ensure_terrain_arrays(terrain):
		return
	var lib_res := _get_texture_library(terrain)
	if lib_res != null and slot_idx < lib_res.normal_textures.size():
		lib_res.normal_textures[slot_idx] = texture
		_save_resource_if_external(lib_res)
	_refresh_slot_runtime(terrain, false)


func _is_slot_inactive(slot_obj) -> bool:
	return slot_obj == null or bool(slot_obj.get("active")) == false


func _reset_slot_palette_state(terrain, slot_idx: int) -> void:
	if slot_idx >= 0 and slot_idx < terrain.slot_color_indices.size():
		terrain.slot_color_indices[slot_idx] = []
	if slot_idx >= 0 and slot_idx < terrain.slot_blend_modes.size():
		terrain.slot_blend_modes[slot_idx] = 3
	if terrain.get("slot_wet_enabled") is Array and slot_idx >= 0 and slot_idx < terrain.slot_wet_enabled.size():
		terrain.slot_wet_enabled[slot_idx] = false
	if terrain.get("slot_wet_modes") is Array and slot_idx >= 0 and slot_idx < terrain.slot_wet_modes.size():
		terrain.slot_wet_modes[slot_idx] = 0
	if terrain.get("slot_roughnesses") is Array and slot_idx >= 0 and slot_idx < terrain.slot_roughnesses.size():
		terrain.slot_roughnesses[slot_idx] = 1.0
	if terrain.get("slot_floor_noise_enabled") is Array and slot_idx >= 0 and slot_idx < terrain.slot_floor_noise_enabled.size():
		terrain.slot_floor_noise_enabled[slot_idx] = false
	if terrain.get("slot_floor_noise_strengths") is Array and slot_idx >= 0 and slot_idx < terrain.slot_floor_noise_strengths.size():
		terrain.slot_floor_noise_strengths[slot_idx] = terrain.global_noise_strength
	if terrain.get("slot_floor_noise_scales") is Array and slot_idx >= 0 and slot_idx < terrain.slot_floor_noise_scales.size():
		terrain.slot_floor_noise_scales[slot_idx] = 0.037
	if terrain.get("slot_wall_noise_enabled") is Array and slot_idx >= 0 and slot_idx < terrain.slot_wall_noise_enabled.size():
		terrain.slot_wall_noise_enabled[slot_idx] = false
	if terrain.get("slot_wall_noise_strengths") is Array and slot_idx >= 0 and slot_idx < terrain.slot_wall_noise_strengths.size():
		terrain.slot_wall_noise_strengths[slot_idx] = terrain.global_noise_strength
	if terrain.get("slot_wall_noise_scales") is Array and slot_idx >= 0 and slot_idx < terrain.slot_wall_noise_scales.size():
		terrain.slot_wall_noise_scales[slot_idx] = 0.037


func _shrink_visible_texture_slots(terrain) -> void:
	while int(terrain.visible_texture_slot_count) > 1:
		var last_idx := int(terrain.visible_texture_slot_count) - 1
		if last_idx == 15:
			break
		var last_slot = terrain.texture_slots[last_idx] if last_idx < terrain.texture_slots.size() else null
		if not _is_slot_inactive(last_slot):
			break
		terrain.visible_texture_slot_count = last_idx


func _set_modal_preview_texture(preview: TextureRect, terrain, texture: Texture2D, max_size: int = 256) -> void:
	if preview == null:
		return
	if texture == null:
		preview.texture = null
		return
	if terrain == null or not terrain.has_method("_get_decompressed_image"):
		preview.texture = texture
		return
	var img: Image = terrain._get_decompressed_image(texture)
	if img == null:
		preview.texture = texture
		return
	var iw: int = img.get_width()
	var ih: int = img.get_height()
	if iw <= 0 or ih <= 0:
		preview.texture = texture
		return
	if iw > max_size or ih > max_size:
		var nw: int = iw
		var nh: int = ih
		if iw >= ih:
			nw = max_size
			nh = max(1, int(round(float(ih) * float(nw) / float(iw))))
		else:
			nh = max_size
			nw = max(1, int(round(float(iw) * float(nh) / float(ih))))
		img.resize(nw, nh, Image.INTERPOLATE_BILINEAR)
		var preview_texture := ImageTexture.new()
		preview_texture.create_from_image(img)
		preview.texture = preview_texture
	else:
		preview.texture = texture


func _clear_slot(terrain, slot_idx: int, p_refresh_ui: bool = true) -> void:
	if terrain == null or slot_idx < 0 or slot_idx >= MAX_TEXTURE_SLOTS or slot_idx == 15:
		return
	if not _ensure_terrain_arrays(terrain):
		return
	if terrain.texture_slots[slot_idx] == null:
		terrain.texture_slots[slot_idx] = _TEXTURE_SLOT_SCRIPT.new()
	terrain.texture_slots[slot_idx].active = false
	terrain.texture_slots[slot_idx].texture = null
	terrain.texture_slots[slot_idx].scale = 1.0
	terrain.texture_slots[slot_idx].terrain_texture_index = (slot_idx if slot_idx < 15 else 0)
	_reset_slot_palette_state(terrain, slot_idx)
	_sync_slot_legacy_fields(terrain, slot_idx)
	_shrink_visible_texture_slots(terrain)
	var lib_res := _get_texture_library(terrain)
	if lib_res != null:
		if slot_idx < lib_res.albedo_textures.size():
			lib_res.albedo_textures[slot_idx] = null
		if slot_idx < lib_res.normal_textures.size():
			lib_res.normal_textures[slot_idx] = null
		_save_resource_if_external(lib_res)
	_refresh_slot_runtime(terrain, p_refresh_ui)


func _make_slot_preview(texture: Texture2D, size: int = 64) -> TextureRect:
	var thumb := TextureRect.new()
	thumb.texture = texture
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.custom_minimum_size = Vector2(size, size)
	thumb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return thumb

func add_texture_settings() -> void:
	for child in get_children():
		child.queue_free()
	
	var terrain := plugin.current_terrain_node
	if terrain == null:
		_built_for_terrain_id = 0
		return
	_built_for_terrain_id = terrain.get_instance_id()
	
	# Ensure slot/palette arrays are initialized before we build UI.
	if not _ensure_terrain_arrays(terrain):
		return
	
	var vbox := VBoxContainer.new()
	# Keep the inspector-side painter narrow enough that it does not steal viewport space.
	vbox.set_custom_minimum_size(Vector2(190, 0))

	# Bake button: create external Texture2DArray resources from a linked MSTextureLibrary.
	var bake_btn := Button.new()
	bake_btn.text = "Bake Texture Arrays"
	bake_btn.tooltip_text = "Bake assigned textures into external Texture2DArray .res files (uses texture_library on the terrain)."
	bake_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bake_btn.pressed.connect(self._on_bake_pressed)
	vbox.add_child(bake_btn, true)

	var preset := terrain.current_texture_preset
	var names : Array[String] = []
	if preset and preset.new_tex_names:
		MarchingSquaresTerrainPlugin._ensure_texture_names_resource(preset.new_tex_names)
		names = preset.new_tex_names.get("texture_names")
	elif vp_tex_names:
		MarchingSquaresTerrainPlugin._ensure_texture_names_resource(vp_tex_names)
		names = vp_tex_names.get("texture_names")
	
	# "Ghost" slot: Global Noise (not a texture slot).
	var gn_label := Label.new()
	gn_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gn_label.text = "Global Noise"
	gn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gn_label.set_custom_minimum_size(Vector2(160, 25))
	gn_label.tooltip_text = "Texture used by the shader's global noise multiplier (not a texture slot)"
	vbox.add_child(gn_label, true)

	var gn_picker := EditorResourcePicker.new()
	gn_picker.set_base_type("Texture2D")
	var gn_tex: Texture2D = terrain.get("global_noise_texture")
	if gn_tex != null and not (gn_tex is Texture2D):
		gn_tex = null
	gn_picker.edited_resource = gn_tex
	gn_picker.set_custom_minimum_size(Vector2(150, 25))
	gn_picker.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	gn_picker.resource_changed.connect(func(resource):
		if resource != null and not (resource is Texture2D):
			resource = null
		terrain.set("global_noise_texture", resource)
	)
	gn_picker.resource_selected.connect(func(resource: Resource, inspect: bool):
		if inspect and resource != null:
			EditorInterface.inspect_object(resource)
	)
	var gn_picker_center := CenterContainer.new()
	gn_picker_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gn_picker_center.add_child(gn_picker)
	vbox.add_child(gn_picker_center, true)

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
	var gn_strength_val = terrain.get("global_noise_strength")
	if gn_strength_val is float or gn_strength_val is int:
		gn_strength_slider.set_value(float(gn_strength_val))
	else:
		gn_strength_slider.set_value(1.0)
	gn_strength_slider.value_changed.connect(func(v): terrain.set("global_noise_strength", float(v)))
	gn_strength_slider.set_custom_minimum_size(Vector2(95, 25))
	gn_strength_hbox.add_child(gn_strength_slider)
	gn_strength_hbox.visible = false

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
	var gn_scale_val = terrain.get("global_noise_scale")
	if gn_scale_val is float or gn_scale_val is int:
		gn_scale_slider.set_value(float(gn_scale_val))
	else:
		gn_scale_slider.set_value(0.037)
	gn_scale_slider.value_changed.connect(func(v): terrain.set("global_noise_scale", float(v)))
	gn_scale_slider.set_custom_minimum_size(Vector2(95, 25))
	gn_scale_hbox.add_child(gn_scale_slider)
	gn_scale_hbox.visible = false

	var gn_scroll_hbox := HBoxContainer.new()
	gn_scroll_hbox.set_custom_minimum_size(Vector2(150, 20))
	var gn_scroll_label := Label.new()
	gn_scroll_label.text = "Scroll:"
	gn_scroll_label.set_custom_minimum_size(Vector2(70, 20))
	gn_scroll_hbox.add_child(gn_scroll_label)
	var gn_scroll_slider := EditorSpinSlider.new()
	gn_scroll_slider.set_flat(true)
	gn_scroll_slider.set_min(0.0)
	gn_scroll_slider.set_max(10.0)
	gn_scroll_slider.set_step(0.1)
	var gn_scroll_val = terrain.get("global_noise_scroll")
	if gn_scroll_val is float or gn_scroll_val is int:
		gn_scroll_slider.set_value(float(gn_scroll_val))
	else:
		gn_scroll_slider.set_value(0.0)
	gn_scroll_slider.value_changed.connect(func(v): terrain.set("global_noise_scroll", float(v)))
	gn_scroll_slider.set_custom_minimum_size(Vector2(95, 25))
	gn_scroll_hbox.add_child(gn_scroll_slider)
	vbox.add_child(gn_scroll_hbox, true)

	vbox.add_child(HSeparator.new())

	var visible_count := clampi(int(terrain.visible_texture_slot_count), 1, 256)
	
	# Compact slot list. Per-slot editing lives in _open_slot_modal().
	var actions_v := VBoxContainer.new()
	actions_v.set_custom_minimum_size(Vector2(120, 56))
	actions_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var add_compact := Button.new()
	add_compact.text = "+ Add Texture"
	add_compact.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_compact.pressed.connect(func():
		if not _ensure_terrain_arrays(terrain):
			return
		var made_active := false
		for idx in range(clampi(int(terrain.visible_texture_slot_count), 1, 256)):
			if idx == 0 or idx == 15:
				continue
			var s = terrain.texture_slots[idx]
			if s != null and bool(s.get("active")) == false:
				s.active = true
				made_active = true
				break
		if not made_active:
			terrain.visible_texture_slot_count = mini(int(terrain.visible_texture_slot_count) + 1, 256)
		if terrain.current_texture_preset != null and not terrain.current_texture_preset.resource_path.is_empty():
			terrain.save_to_preset()
		call_deferred("add_texture_settings")
	)
	actions_v.add_child(add_compact)
	var export_compact := MarchingSquaresTexturePresetExporter.new()
	export_compact.current_terrain_node = terrain
	export_compact.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions_v.add_child(export_compact)
	var grid := GridContainer.new()
	grid.columns = 1
	grid.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	for i in range(visible_count):
		var slot_idx := i
		var slot_obj = terrain.texture_slots[slot_idx] if slot_idx < terrain.texture_slots.size() else null
		# Hide inactive slots (except reserved ones).
		if slot_idx != 0 and slot_idx != 15 and _is_slot_inactive(slot_obj):
			continue
		var __si := slot_idx
		var tile := VBoxContainer.new()
		tile.set_custom_minimum_size(Vector2(136, 156))
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var tex_var : Texture2D = slot_obj.texture if slot_obj != null else null
		if tex_var != null and not (tex_var is Texture2D):
			tex_var = null
		var thumb := _make_slot_preview(tex_var, 96)
		var thumb_center := CenterContainer.new()
		thumb_center.add_child(thumb)
		tile.add_child(thumb_center)
		var nameplate := PanelContainer.new()
		nameplate.set_custom_minimum_size(Vector2(132, 24))
		nameplate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var lbl := Label.new()
		lbl.text = names[slot_idx] if slot_idx < names.size() else ("Texture " + str(slot_idx + 1))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		lbl.clip_text = true
		lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		lbl.set_custom_minimum_size(Vector2(124, 20))
		nameplate.add_child(lbl)
		var nameplate_center := CenterContainer.new()
		nameplate_center.add_child(nameplate)
		tile.add_child(nameplate_center)
		var btn_h := HBoxContainer.new()
		btn_h.alignment = BoxContainer.ALIGNMENT_CENTER
		var edit_btn := Button.new()
		edit_btn.text = "Edit"
		edit_btn.set_custom_minimum_size(Vector2(48, 24))
		edit_btn.pressed.connect(func(): _open_slot_modal(__si))
		btn_h.add_child(edit_btn)
		var rem_btn := Button.new()
		rem_btn.text = "X"
		rem_btn.set_custom_minimum_size(Vector2(28, 24))
		rem_btn.disabled = slot_idx == 0 or slot_idx == 15
		rem_btn.pressed.connect(func(): _clear_slot(terrain, __si, true))
		btn_h.add_child(rem_btn)
		var btn_center := CenterContainer.new()
		btn_center.add_child(btn_h)
		tile.add_child(btn_center)
		grid.add_child(tile)
	vbox.add_child(grid, true)
	vbox.add_child(actions_v, true)
	add_child(vbox, true)


func is_built_for_current_terrain() -> bool:
	var terrain := plugin.current_terrain_node if plugin != null else null
	return terrain != null and _built_for_terrain_id == terrain.get_instance_id() and get_child_count() > 0
	
func _open_slot_modal(slot_idx: int) -> void:
	var terrain := plugin.current_terrain_node
	if terrain == null:
		return
	var existing := get_tree().get_root().get_node_or_null("mst_slot_modal")
	if existing:
		existing.queue_free()
	var dialog := AcceptDialog.new()
	dialog.name = "mst_slot_modal"
	dialog.title = "Edit Texture %d" % (slot_idx + 1)
	dialog.min_size = Vector2i(780, 520)
	var body := HBoxContainer.new()
	body.name = "modal_body"
	body.set_custom_minimum_size(Vector2(840, 0))
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.name = "modal_left"
	v.set_custom_minimum_size(Vector2(300, 0))
	v.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# Name
	var name_lbl := Label.new()
	name_lbl.text = "Texture Name"
	var name_edit := LineEdit.new()
	name_edit.name = "name_edit"
	# Fill with preset or default name
	var preset := terrain.current_texture_preset
	var names : Array = []
	if preset and preset.new_tex_names:
		MarchingSquaresTerrainPlugin._ensure_texture_names_resource(preset.new_tex_names)
		names = preset.new_tex_names.get("texture_names")
	elif vp_tex_names:
		names = vp_tex_names.get("texture_names")
	name_edit.text = names[slot_idx] if slot_idx < names.size() else ("Texture " + str(slot_idx + 1))
	v.add_child(name_lbl)
	v.add_child(name_edit)
	# Preview
	var preview_lbl := Label.new()
	preview_lbl.text = "Preview"
	var preview := TextureRect.new()
	preview.name = "preview"
	# Force a compact preview container so very large textures don't resize the modal
	preview.set_custom_minimum_size(Vector2(256, 256))
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Container with fixed minimum size to clamp the preview area
	var preview_container := CenterContainer.new()
	preview_container.set_custom_minimum_size(Vector2(256, 256))
	preview_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	preview_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Ensure content is clipped so a large texture can't expand the dialog
	preview_container.clip_contents = true
	# Keep the preview fixed-size; TextureRect's natural texture size must not drive modal layout.
	preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	preview.set_custom_minimum_size(Vector2(256, 256))
	preview_container.add_child(preview)
	v.add_child(preview_lbl)
	v.add_child(preview_container)
	# Inline color preview overlay inside preview (bottom-right)
	var overlay_v := VBoxContainer.new()
	overlay_v.name = "preview_overlay"
	overlay_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overlay_v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	overlay_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var overlay_spacer := Control.new()
	overlay_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	overlay_v.add_child(overlay_spacer)
	var overlay_h := HBoxContainer.new()
	overlay_h.name = "preview_overlay_h"
	var overlay_h_spacer := Control.new()
	overlay_h_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overlay_h.add_child(overlay_h_spacer)
	# Add color swatches for this slot (show up to 6 for compactness)
	var sidxs_local: Array = terrain.slot_color_indices[slot_idx]
	var max_swatches: int = min(sidxs_local.size(), 6)
	for i_sw in range(max_swatches):
		var cr := ColorRect.new()
		cr.name = "color_preview_rect_%d" % i_sw
		var pidx_local: int = int(sidxs_local[i_sw])
		if pidx_local >= 0 and pidx_local < terrain.palette_colors.size():
			cr.color = terrain.palette_colors[pidx_local]
		else:
			cr.color = Color(1, 1, 1)
		cr.set_custom_minimum_size(Vector2(36, 36))
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay_h.add_child(cr)
	overlay_v.add_child(overlay_h)
	preview.add_child(overlay_v)
	# Ensure initial swatch color reflects first palette color if available
	var initial_sw : ColorRect = preview.get_node_or_null("preview_overlay/preview_overlay_h/color_preview_rect_0") as ColorRect
	if initial_sw != null:
		var sidxs: Array = terrain.slot_color_indices[slot_idx]
		if sidxs.size() > 0:
			var first_p : int = int(sidxs[0])
			if first_p >= 0 and first_p < terrain.palette_colors.size():
				initial_sw.color = terrain.palette_colors[first_p]
	# Position swatch after layout
	call_deferred("_position_preview_swatch", preview, initial_sw)
	# Texture picker
	var alb_label := Label.new()
	alb_label.text = "Albedo Map"
	v.add_child(alb_label)
	var picker := EditorResourcePicker.new()
	picker.name = "tex_picker"
	picker.set_base_type("Texture2D")
	var existing_tex: Texture2D = null
	if terrain.texture_slots.size() > slot_idx and terrain.texture_slots[slot_idx] != null:
		existing_tex = terrain.texture_slots[slot_idx].texture if terrain.texture_slots[slot_idx].texture is Texture2D else null
	if existing_tex == null:
		var lib_for_preview := _get_texture_library(terrain)
		if lib_for_preview != null and lib_for_preview is MSTextureLibraryScript and slot_idx < lib_for_preview.albedo_textures.size():
			existing_tex = lib_for_preview.albedo_textures[slot_idx] if lib_for_preview.albedo_textures[slot_idx] is Texture2D else null
	if existing_tex != null:
		picker.edited_resource = existing_tex
		_set_modal_preview_texture(preview, terrain, existing_tex, 256)
	picker.resource_changed.connect(func(res):
		var preview_tex: Texture2D = res if res is Texture2D else null
		_set_modal_preview_texture(preview, terrain, preview_tex, 256)
		_apply_slot_albedo(terrain, slot_idx, res, false)
		# Reposition the inline swatch after the preview may have resized
		call_deferred("_position_preview_swatch", preview, preview.get_node_or_null("preview_overlay/preview_overlay_h/color_preview_rect_0"))
	)
	v.add_child(picker)

	# Normal picker (modal)
	var nrm_label := Label.new()
	nrm_label.text = "Normal Map"
	v.add_child(nrm_label)
	var lib_res_modal: Resource = terrain.get("texture_library") if terrain.has_method("get") else null
	var initial_norm_modal: Texture2D = null
	if lib_res_modal != null and lib_res_modal is MSTextureLibraryScript and slot_idx < lib_res_modal.normal_textures.size():
		var maybe_nrm_modal = lib_res_modal.normal_textures[slot_idx]
		if maybe_nrm_modal != null and maybe_nrm_modal is Texture2D:
			initial_norm_modal = maybe_nrm_modal
	var nrm_picker_modal := EditorResourcePicker.new()
	nrm_picker_modal.set_base_type("Texture2D")
	nrm_picker_modal.edited_resource = initial_norm_modal
	nrm_picker_modal.set_custom_minimum_size(Vector2(100, 25))
	nrm_picker_modal.resource_changed.connect(func(resource):
		_apply_slot_normal(terrain, slot_idx, resource)
	)
	v.add_child(nrm_picker_modal)

	# Advanced collapsible
	body.add_child(v)

	var right_panel := VBoxContainer.new()
	right_panel.name = "modal_right"
	right_panel.set_custom_minimum_size(Vector2(420, 0))
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var adv_label := Label.new()
	adv_label.text = "Advanced"
	right_panel.add_child(adv_label)

	var adv_scroll := ScrollContainer.new()
	adv_scroll.name = "adv_scroll"
	adv_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	adv_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	adv_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	adv_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	adv_scroll.set_custom_minimum_size(Vector2(420, 0))

	var adv_vbox := VBoxContainer.new()
	adv_vbox.name = "adv_vbox"
	adv_vbox.visible = true
	adv_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	adv_vbox.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	adv_vbox.set_custom_minimum_size(Vector2(400, 0))
	# Reuse existing palette builder inside modal for parity
	_build_palette_ui(adv_vbox, terrain, slot_idx)

	# Inline status area
	var status_lbl := Label.new()
	status_lbl.name = "status_label"
	status_lbl.text = ""
	adv_vbox.add_child(status_lbl)

	adv_scroll.add_child(adv_vbox)
	right_panel.add_child(adv_scroll)
	body.add_child(right_panel)

	dialog.add_child(body)
	dialog.confirmed.connect(func(): _on_slot_modal_confirmed(slot_idx))
	# Parent modal to the scene root so rebuilding this panel won't free it
	var root := get_tree().get_root()
	if root != null:
		root.add_child(dialog)
	else:
		add_child(dialog)
	dialog.popup_centered(Vector2i(900, 620))
	# Ensure modal content is fully laid out and in-sync
	call_deferred("_refresh_slot_modal", slot_idx)
	var modal_preview := _find_modal_node(dialog, "preview")
	call_deferred("_position_preview_swatch", modal_preview, modal_preview.get_node_or_null("preview_overlay/preview_overlay_h/color_preview_rect_0") if modal_preview != null else null)

func _find_modal_node(root: Node, node_name: String) -> Node:
	if root == null:
		return null
	if root.name == node_name:
		return root
	for child in root.get_children():
		var found: Node = _find_modal_node(child, node_name)
		if found != null:
			return found
	return null

func _refresh_slot_modal(slot_idx: int) -> void:
	# Rebuild only the adv_vbox inside the open slot modal so changes appear immediately without closing.
	var dlg := get_tree().get_root().get_node_or_null("mst_slot_modal")
	if dlg == null:
		return
	var adv_vbox := _find_modal_node(dlg, "adv_vbox") as VBoxContainer
	if adv_vbox == null:
		# Fallback: close+reopen if we can't locate the container reliably
		dlg.queue_free()
		call_deferred("_open_slot_modal", slot_idx)
		return
	# Clear existing children safely
	for c in adv_vbox.get_children():
		adv_vbox.remove_child(c)
		c.queue_free()
	# Rebuild UI in-place
	var terrain := plugin.current_terrain_node
	if terrain == null:
		return
	_build_palette_ui(adv_vbox, terrain, slot_idx)
	_refresh_modal_preview_swatches(dlg, terrain, slot_idx)
	# Ensure a status_label exists (modal expects it)
	if not adv_vbox.has_node("status_label"):
		var status_lbl := Label.new()
		status_lbl.name = "status_label"
		status_lbl.text = ""
		adv_vbox.add_child(status_lbl)
	# Make sure visibility remains as before (don't force toggle)
	# Done.

func _refresh_modal_preview_swatches(dlg: Node, terrain, slot_idx: int) -> void:
	var preview_node := _find_modal_node(dlg, "preview") as TextureRect
	if preview_node == null:
		return
	var overlay_h := preview_node.get_node_or_null("preview_overlay/preview_overlay_h") as HBoxContainer
	if overlay_h == null:
		return
	for child in overlay_h.get_children():
		if str(child.name).begins_with("color_preview_rect_"):
			overlay_h.remove_child(child)
			child.queue_free()
	var sidxs: Array = terrain.slot_color_indices[slot_idx]
	var max_swatches: int = min(sidxs.size(), 6)
	for i_sw in range(max_swatches):
		var cr := ColorRect.new()
		cr.name = "color_preview_rect_%d" % i_sw
		var pidx: int = int(sidxs[i_sw])
		cr.color = terrain.palette_colors[pidx] if pidx >= 0 and pidx < terrain.palette_colors.size() else Color(1, 1, 1)
		cr.set_custom_minimum_size(Vector2(36, 36))
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay_h.add_child(cr)
	call_deferred("_position_preview_swatch", preview_node, preview_node.get_node_or_null("preview_overlay/preview_overlay_h/color_preview_rect_0"))

func _on_slot_modal_confirmed(slot_idx: int) -> void:
	var dialog := get_tree().get_root().get_node_or_null("mst_slot_modal")
	if dialog == null:
		return
	var name_edit := _find_modal_node(dialog, "name_edit") as LineEdit
	var picker := _find_modal_node(dialog, "tex_picker") as EditorResourcePicker
	var terrain := plugin.current_terrain_node
	if terrain == null:
		dialog.queue_free()
		return
	if not _ensure_terrain_arrays(terrain):
		dialog.queue_free()
		return
	if terrain.texture_slots[slot_idx] == null:
		terrain.texture_slots[slot_idx] = _TEXTURE_SLOT_SCRIPT.new()
	# Texture changes are applied immediately by the picker callbacks.

	# Persist name into preset if available
	var preset := terrain.current_texture_preset
	if preset != null and preset.new_tex_names != null:
		MarchingSquaresTerrainPlugin._ensure_texture_names_resource(preset.new_tex_names)
		var n := preset.new_tex_names.get("texture_names")
		if n is Array and slot_idx < n.size():
			n[slot_idx] = (name_edit.text if name_edit != null else n[slot_idx])
			preset.new_tex_names.set("texture_names", n)
			if preset.resource_path != null and not str(preset.resource_path).is_empty():
				ResourceSaver.save(preset)
	dialog.queue_free()
	call_deferred("add_texture_settings")

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
		# Compact row: preview, picker, weight bar, percent, slider, remove
		var c_hbox := HBoxContainer.new()
		c_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c_hbox.set_custom_minimum_size(Vector2(0, 28))
		
		# Small numeric label
		var c_label := Label.new()
		c_label.text = str(ci + 1)
		c_label.set_custom_minimum_size(Vector2(20, 20))
		c_label.tooltip_text = "Color index"
		c_hbox.add_child(c_label)
		
		# Color picker
		var c_btn := ColorPickerButton.new()
		c_btn.color = terrain.palette_colors[palette_idx]
		c_btn.set_custom_minimum_size(Vector2(60, 24))
		c_btn.focus_mode = Control.FOCUS_NONE
		c_btn.color_changed.connect(func(new_color, s = slot, ci_local = ci):
			if not is_instance_valid(terrain) or not is_instance_valid(plugin.current_terrain_node) or plugin.current_terrain_node != terrain:
				return
			# Resolve palette index at current position (handles reindexing after removes)
			var pidx: int = int(terrain.slot_color_indices[s][ci_local])
			terrain.palette_colors[pidx] = new_color
			# Update shared modal color preview if present.
			var dlg := get_tree().get_root().get_node_or_null("mst_slot_modal")
			if dlg != null:
				var preview_node := _find_modal_node(dlg, "preview")
				if preview_node != null:
					var sw_name := "preview_overlay/preview_overlay_h/color_preview_rect_%d" % ci_local
					var gpreview: ColorRect = preview_node.get_node_or_null(sw_name) as ColorRect
					if gpreview != null:
						gpreview.color = new_color
			terrain._rebuild_palette_uniforms()
			terrain.save_to_preset()
		)
		c_hbox.add_child(c_btn)
		
		# Inline weight display (only if multiple colors)
		if slot_indices.size() > 1:
			terrain._ensure_palette_weights()
			var w_label := Label.new()
			w_label.text = str(int(round(terrain.palette_weights[palette_idx]))) + "%"
			w_label.set_custom_minimum_size(Vector2(36, 20))
			c_hbox.add_child(w_label)
			
			var w_slider := HSlider.new()
			w_slider.min_value = 0.0
			w_slider.max_value = 100.0
			w_slider.step = 1.0
			w_slider.value = clampf(float(terrain.palette_weights[palette_idx]), 0.0, 100.0)
			w_slider.set_custom_minimum_size(Vector2(90, 20))
			w_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			w_slider.focus_mode = Control.FOCUS_NONE
			w_slider.value_changed.connect(func(val, s = slot, ci_local = ci):
				if not is_instance_valid(terrain) or not is_instance_valid(plugin.current_terrain_node) or plugin.current_terrain_node != terrain:
					return
				terrain._ensure_palette_weights()
				var indices: Array = terrain.slot_color_indices[s]
				if indices.size() <= 1:
					return
				# Resolve palette index for this row.
				var pidx: int = int(indices[ci_local])
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
					if total_other <= 0.0001:
						var each := remaining / float(others.size())
						for idx in others:
							terrain.palette_weights[idx] = each
					else:
						for idx in others:
							terrain.palette_weights[idx] = float(terrain.palette_weights[idx]) / total_other * remaining
				terrain._rebuild_palette_uniforms()
			)
			w_slider.drag_ended.connect(func(_ended):
				if not is_instance_valid(terrain) or not is_instance_valid(plugin.current_terrain_node) or plugin.current_terrain_node != terrain:
					return
				terrain.save_to_preset()
				add_texture_settings()
			)
			c_hbox.add_child(w_slider)
		
		var remove_btn := Button.new()
		remove_btn.text = "X"
		remove_btn.set_custom_minimum_size(Vector2(22, 22))
		remove_btn.pressed.connect(func(s = slot, ci_idx = ci):
			if not is_instance_valid(terrain) or not is_instance_valid(plugin.current_terrain_node) or plugin.current_terrain_node != terrain:
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
			# Refresh modal in-place if open
			if get_tree().get_root().has_node("mst_slot_modal"):
				call_deferred("_refresh_slot_modal", s)
			# Refresh main panel as well (deferred to avoid freeing modal)
			call_deferred("add_texture_settings")
		)
		c_hbox.add_child(remove_btn)
		vbox.add_child(c_hbox, true)
	
	# Add Color button
	var add_btn := Button.new()
	add_btn.text = "+ Add Color"
	add_btn.set_custom_minimum_size(Vector2(150, 25))
	add_btn.pressed.connect(func(s = slot):
		if not is_instance_valid(terrain) or not is_instance_valid(plugin.current_terrain_node) or plugin.current_terrain_node != terrain:
			return
		# Find first unused palette index
		var used : Array = []
		for si in range(15):
			for idx in terrain.slot_color_indices[si]:
				used.append(idx)
		var next_idx := 0
		while next_idx < 128 and next_idx in used:
			next_idx += 1
		if next_idx >= 128:
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
		var dlg := get_tree().get_root().get_node_or_null("mst_slot_modal")
		if dlg != null:
			var preview_node := _find_modal_node(dlg, "preview")
			if preview_node != null:
				# Try to update the newly added swatch (or first swatch if it's not yet present)
				var new_count: int = int(terrain.slot_color_indices[s].size())
				var sw_idx: int = min(new_count - 1, 5)
				if sw_idx < 0:
					sw_idx = 0
				var sw_name := "preview_overlay/preview_overlay_h/color_preview_rect_%d" % sw_idx
				var gpreview: ColorRect = preview_node.get_node_or_null(sw_name) as ColorRect
				if gpreview != null:
					gpreview.color = terrain.palette_colors[next_idx]
		if dlg != null:
			# Prefer in-place refresh of the modal's advanced vbox so multi-adds work without closing.
			call_deferred("_refresh_slot_modal", s)
			# Also refresh main UI after current frame so compact list updates if needed.
			call_deferred("add_texture_settings")
		else:
			call_deferred("add_texture_settings")
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
	if grass_tex_var != null and not (grass_tex_var is Texture2D):
		grass_tex_var = null
	grass_picker.edited_resource = grass_tex_var
	grass_picker.visible = grass_cb.button_pressed
	grass_picker.set_custom_minimum_size(Vector2(100, 25))
	vbox.add_child(grass_picker, true)

	var __s_grass = slot
	grass_cb.toggled.connect(func(pressed: bool):
		grass_picker.visible = pressed
		if not _ensure_terrain_arrays(terrain):
			return
		if terrain.texture_slots[__s_grass] == null:
			terrain.texture_slots[__s_grass] = _TEXTURE_SLOT_SCRIPT.new()
		terrain.texture_slots[__s_grass].has_grass = pressed

		# Always request a grass regen when toggling Has Grass so scene reflects change immediately.
		if terrain.has_method("_request_grass_regen"):
			terrain._request_grass_regen()

		# Keep legacy properties in sync for slots 1..6 so presets/UI stay compatible.
		if __s_grass >= 0 and __s_grass < 6:
			terrain.set("tex%d_has_grass" % (__s_grass + 1), pressed)

		if terrain.current_texture_preset != null and not terrain.current_texture_preset.resource_path.is_empty():
			terrain.save_to_preset()
	)

	var __s_grass2 = slot
	grass_picker.resource_changed.connect(func(resource):
		if resource != null and not (resource is Texture2D):
			resource = null
		if not _ensure_terrain_arrays(terrain):
			return
		if terrain.texture_slots[__s_grass2] == null:
			terrain.texture_slots[__s_grass2] = _TEXTURE_SLOT_SCRIPT.new()
		terrain.texture_slots[__s_grass2].grass_texture = resource

		# Keep legacy properties in sync for slots 1..6 so presets/UI stay compatible.
		if __s_grass2 >= 0 and __s_grass2 < 6:
			terrain.set("grass_sprite_tex_%d" % (__s_grass2 + 1), resource)
		var lib_res := _get_texture_library(terrain)
		if lib_res != null and __s_grass2 < lib_res.grass_textures.size():
			lib_res.grass_textures[__s_grass2] = resource
			_save_resource_if_external(lib_res)
		terrain.set("baked_grass_array_path", "")
		# Always rebuild grass arrays + request regen so scene updates immediately when a grass texture is changed
		if terrain.has_method("rebuild_grass_texture_array"):
			terrain.rebuild_grass_texture_array()
		if terrain.has_method("_request_grass_regen"):
			terrain._request_grass_regen()

		if terrain.current_texture_preset != null and not terrain.current_texture_preset.resource_path.is_empty():
			terrain.save_to_preset()
	)

	_build_slot_noise_ui(vbox, terrain, slot)

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
	if terrain.get("slot_roughnesses") is Array and slot >= 0 and slot < terrain.slot_roughnesses.size():
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
		if terrain.get("slot_wet_enabled") is Array and slot >= 0 and slot < terrain.slot_wet_enabled.size():
			terrain.slot_wet_enabled[slot] = pressed
		wet_mode_hbox.visible = pressed
		wetness_hbox.visible = pressed
		terrain._rebuild_palette_uniforms()
		terrain.save_to_preset()
	)

	wet_mode_opt.item_selected.connect(func(idx: int):
		if not _ensure_terrain_arrays(terrain):
			return
		if terrain.get("slot_wet_modes") is Array and slot >= 0 and slot < terrain.slot_wet_modes.size():
			terrain.slot_wet_modes[slot] = idx
		terrain._rebuild_palette_uniforms()
		terrain.save_to_preset()
	)

	wetness_slider.value_changed.connect(func(value: float):
		if not _ensure_terrain_arrays(terrain):
			return
		if terrain.get("slot_roughnesses") is Array and slot >= 0 and slot < terrain.slot_roughnesses.size():
			terrain.slot_roughnesses[slot] = clampf(1.0 - float(value), 0.0, 1.0)
		terrain._rebuild_palette_uniforms()
		terrain.save_to_preset()
	)

func _build_slot_noise_ui(vbox: VBoxContainer, terrain: MarchingSquaresTerrain, slot: int) -> void:
	if not _ensure_terrain_arrays(terrain):
		return
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	_add_slot_noise_column(row, terrain, slot, "Floor Noise", "slot_floor_noise_enabled", "slot_floor_noise_strengths", "slot_floor_noise_scales")
	_add_slot_noise_column(row, terrain, slot, "Wall Noise", "slot_wall_noise_enabled", "slot_wall_noise_strengths", "slot_wall_noise_scales")
	vbox.add_child(row, true)


func _add_slot_noise_column(parent: HBoxContainer, terrain: MarchingSquaresTerrain, slot: int, label_text: String, enabled_prop: String, strength_prop: String, scale_prop: String) -> void:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.set_custom_minimum_size(Vector2(140, 0))
	parent.add_child(col, true)

	var enabled_arr: Array = terrain.get(enabled_prop)
	var strength_arr: Array = terrain.get(strength_prop)
	var scale_arr: Array = terrain.get(scale_prop)
	var enabled := bool(enabled_arr[slot]) if slot >= 0 and slot < enabled_arr.size() else false

	var cb := CheckBox.new()
	cb.text = label_text
	cb.set_flat(true)
	cb.button_pressed = enabled
	col.add_child(cb, true)

	var strength_row := HBoxContainer.new()
	var strength_label := Label.new()
	strength_label.text = "Strength:"
	strength_label.set_custom_minimum_size(Vector2(62, 20))
	strength_row.add_child(strength_label)
	var strength_slider := EditorSpinSlider.new()
	strength_slider.set_flat(true)
	strength_slider.set_min(0.0)
	strength_slider.set_max(1.0)
	strength_slider.set_step(0.01)
	strength_slider.set_value(clampf(float(strength_arr[slot]), 0.0, 1.0))
	strength_slider.set_custom_minimum_size(Vector2(72, 24))
	strength_row.add_child(strength_slider)
	strength_row.visible = enabled
	col.add_child(strength_row, true)

	var scale_row := HBoxContainer.new()
	var scale_label := Label.new()
	scale_label.text = "Scale:"
	scale_label.set_custom_minimum_size(Vector2(62, 20))
	scale_row.add_child(scale_label)
	var scale_slider := EditorSpinSlider.new()
	scale_slider.set_flat(true)
	scale_slider.set_min(0.001)
	scale_slider.set_max(1.0)
	scale_slider.set_step(0.001)
	scale_slider.set_value(clampf(float(scale_arr[slot]), 0.001, 1.0))
	scale_slider.set_custom_minimum_size(Vector2(72, 24))
	scale_row.add_child(scale_slider)
	scale_row.visible = enabled
	col.add_child(scale_row, true)

	cb.toggled.connect(func(pressed: bool):
		if not _ensure_terrain_arrays(terrain):
			return
		var current_enabled: Array = terrain.get(enabled_prop)
		current_enabled[slot] = pressed
		strength_row.visible = pressed
		scale_row.visible = pressed
		terrain._rebuild_palette_uniforms()
		terrain.save_to_preset()
	)
	strength_slider.value_changed.connect(func(value: float):
		if not _ensure_terrain_arrays(terrain):
			return
		var current_strengths: Array = terrain.get(strength_prop)
		current_strengths[slot] = clampf(float(value), 0.0, 1.0)
		terrain._rebuild_palette_uniforms()
		terrain.save_to_preset()
	)
	scale_slider.value_changed.connect(func(value: float):
		if not _ensure_terrain_arrays(terrain):
			return
		var current_scales: Array = terrain.get(scale_prop)
		current_scales[slot] = clampf(float(value), 0.001, 1.0)
		terrain._rebuild_palette_uniforms()
		terrain.save_to_preset()
	)


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
	var lib = terrain.get("texture_library") if terrain.has_method("get") else null
	if lib == null:
		push_error("[MST] Terrain has no texture_library assigned. Assign an MSTextureLibrary resource first.")
		return
	_sync_texture_library_from_slots(terrain, lib)
	var out_dir := "res://scenes/baked_texture_arrays"
	# If the terrain has a data_directory, prefer saving alongside it (convert Windows paths to resource-style).
	if terrain.get("data_directory") != null and terrain.get("data_directory") != "":
		out_dir = str(terrain.get("data_directory")).replace("\\", "/")
		if out_dir.ends_with("/"):
			out_dir = out_dir + "baked_texture_arrays"
		else:
			out_dir = out_dir + "/baked_texture_arrays"

	var baker := MarchingSquaresBaker.new()
	var runtime_size := int(terrain.get("runtime_baked_texture_size")) if terrain.get("runtime_baked_texture_size") != null else int(terrain.get("baked_texture_size"))
	var grass_size := int(terrain.get("baked_grass_texture_size")) if terrain.get("baked_grass_texture_size") != null else 64
	var results := baker.bake_library(lib, out_dir, runtime_size, grass_size)
	if results.size() == 0:
		push_error("[MST] Baking failed or produced no results.")
		return
	if results.has("albedo_path") and results["albedo_path"] != "":
		terrain.set("baked_albedo_array_path", results["albedo_path"])
	if results.has("normal_path") and results["normal_path"] != "":
		terrain.set("baked_normal_array_path", results["normal_path"])
	if results.has("grass_path") and results["grass_path"] != "":
		terrain.set("baked_grass_array_path", results["grass_path"])

	# Rebuild runtime arrays so material uses the newly baked resources.
	MarchingSquaresTerrainHelpers.rebuild_texture_array(terrain)
	MarchingSquaresTerrainHelpers.rebuild_grass_texture_array(terrain)


# Helper: position the small color swatch inside the preview control (bottom-right)
func _position_preview_swatch(preview: Control, swatch: Control) -> void:
	if preview == null or swatch == null:
		return
	var psize: Vector2 = preview.get_size()
	if psize.x <= 0 or psize.y <= 0:
		# Try again later after layout
		call_deferred("_position_preview_swatch", preview, swatch)
		return
	var sw := Vector2(36, 36)
	if swatch.has_method("set_custom_minimum_size"):
		swatch.set_custom_minimum_size(sw)
	else:
		swatch.size = sw
	var padding := Vector2(8, 8)
	var pos := Vector2(max(0, psize.x - sw.x - padding.x), max(0, psize.y - sw.y - padding.y))
	swatch.position = pos
