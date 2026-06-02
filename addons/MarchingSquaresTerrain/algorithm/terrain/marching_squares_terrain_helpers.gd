@tool
extends RefCounted

const MAX_TEXTURE_SLOTS := 256
const VOID_TEXTURE_SLOT := 15

# NOTE: Avoid hard type-hints here; headless/script-cache builds may not resolve global class_names reliably.
const _TEXTURE_SLOT_SCRIPT := preload("res://addons/MarchingSquaresTerrain/resources/marching_squares_texture_slot.gd")
const VOID_TEXTURE := preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/void_texture.tres")
const MSTVertexColorHelper := preload("res://addons/MarchingSquaresTerrain/algorithm/terrain/marching_squares_terrain_vertex_color_helper.gd")


# ---------------- Texture Slots / Texture Arrays ----------------

static func ensure_texture_slots(terrain) -> void:
	if terrain.texture_slots == null:
		terrain.texture_slots = []
	if terrain.texture_slots.size() != MAX_TEXTURE_SLOTS:
		terrain.texture_slots.resize(MAX_TEXTURE_SLOTS)
	for i in range(MAX_TEXTURE_SLOTS):
		if terrain.texture_slots[i] == null:
			terrain.texture_slots[i] = _TEXTURE_SLOT_SCRIPT.new()
		# Default any missing 'active' to true (older saves won't have it).
		if terrain.texture_slots[i] != null and terrain.texture_slots[i].get("active") == null:
			terrain.texture_slots[i].active = true
		
		# Slot->base texture mapping (older saves won't have it).
		if terrain.texture_slots[i] != null and terrain.texture_slots[i].get("terrain_texture_index") == null:
			if i == VOID_TEXTURE_SLOT:
				terrain.texture_slots[i].terrain_texture_index = VOID_TEXTURE_SLOT
			elif i < 15:
				terrain.texture_slots[i].terrain_texture_index = i
			else:
				terrain.texture_slots[i].terrain_texture_index = 0
		elif terrain.texture_slots[i] != null:
			terrain.texture_slots[i].terrain_texture_index = clampi(int(terrain.texture_slots[i].terrain_texture_index), 0, 15)
		
		# Default any missing grass fields (older saves / older slot resources).
		# Slot 0 (Texture 1) defaults to having grass enabled.
		if terrain.texture_slots[i] != null and terrain.texture_slots[i].get("has_grass") == null:
			terrain.texture_slots[i].has_grass = (i == 0)
		# grass_texture can be null; only coerce if the key is missing (avoid nil variants).
		if terrain.texture_slots[i] != null and terrain.texture_slots[i].get("grass_texture") == null:
			terrain.texture_slots[i].grass_texture = null

	# Ensure legacy VOID slot always has a valid texture.
	if terrain.texture_slots.size() > VOID_TEXTURE_SLOT and terrain.texture_slots[VOID_TEXTURE_SLOT] and terrain.texture_slots[VOID_TEXTURE_SLOT].texture == null:
		terrain.texture_slots[VOID_TEXTURE_SLOT].texture = VOID_TEXTURE


static func maybe_migrate_legacy_textures(terrain) -> void:
	# One-time migration: if slots are empty/uninitialized, copy old exported vars into slots 0..14.
	var any_slot_set := false
	for i in range(mini(15, terrain.texture_slots.size())):
		var s = terrain.texture_slots[i]
		if s != null and s.texture != null:
			any_slot_set = true
			break

	var legacy_textures: Array[Texture2D] = [
		terrain.texture_1, terrain.texture_2, terrain.texture_3, terrain.texture_4, terrain.texture_5,
		terrain.texture_6, terrain.texture_7, terrain.texture_8, terrain.texture_9, terrain.texture_10,
		terrain.texture_11, terrain.texture_12, terrain.texture_13, terrain.texture_14, terrain.texture_15,
	]
	var any_legacy_set := false
	for t in legacy_textures:
		if t != null:
			any_legacy_set = true
			break

	if any_slot_set or not any_legacy_set:
		return

	for i in range(15):
		if terrain.texture_slots[i] == null:
			terrain.texture_slots[i] = _TEXTURE_SLOT_SCRIPT.new()
		terrain.texture_slots[i].texture = legacy_textures[i]

	# Legacy scales -> slot scales
	var legacy_scales: Array[float] = [
		terrain.texture_scale_1, terrain.texture_scale_2, terrain.texture_scale_3, terrain.texture_scale_4, terrain.texture_scale_5,
		terrain.texture_scale_6, terrain.texture_scale_7, terrain.texture_scale_8, terrain.texture_scale_9, terrain.texture_scale_10,
		terrain.texture_scale_11, terrain.texture_scale_12, terrain.texture_scale_13, terrain.texture_scale_14, terrain.texture_scale_15,
	]
	for i in range(15):
		terrain.texture_slots[i].scale = legacy_scales[i]


static func maybe_migrate_legacy_grass(terrain) -> void:
	# One-time migration: copy legacy grass exports into slots 0..5.
	# Legacy behavior: Texture 1 grass always on; textures 2-6 are toggleable.
	if terrain._grass_slots_migrated:
		return
	terrain._grass_slots_migrated = true
	ensure_texture_slots(terrain)

	# Ensure slots exist.
	for i in range(6):
		if terrain.texture_slots[i] == null:
			terrain.texture_slots[i] = _TEXTURE_SLOT_SCRIPT.new()

	# Sprites (legacy exports) -> slots
	terrain.texture_slots[0].grass_texture = terrain.grass_sprite_tex_1
	terrain.texture_slots[1].grass_texture = terrain.grass_sprite_tex_2
	terrain.texture_slots[2].grass_texture = terrain.grass_sprite_tex_3
	terrain.texture_slots[3].grass_texture = terrain.grass_sprite_tex_4
	terrain.texture_slots[4].grass_texture = terrain.grass_sprite_tex_5
	terrain.texture_slots[5].grass_texture = terrain.grass_sprite_tex_6

	# Has grass flags -> slots (cast to bool; older scenes can deserialize these as Nil)
	# Use Variant locals ("=") instead of inferred (":=") to avoid type-inference errors on Nil.
	var t1 = terrain.tex1_has_grass
	if t1 == null:
		t1 = true
	var t2 = terrain.tex2_has_grass
	if t2 == null:
		t2 = true
	var t3 = terrain.tex3_has_grass
	if t3 == null:
		t3 = true
	var t4 = terrain.tex4_has_grass
	if t4 == null:
		t4 = true
	var t5 = terrain.tex5_has_grass
	if t5 == null:
		t5 = true
	var t6 = terrain.tex6_has_grass
	if t6 == null:
		t6 = true
	terrain.texture_slots[0].has_grass = bool(t1)
	terrain.texture_slots[1].has_grass = bool(t2)
	terrain.texture_slots[2].has_grass = bool(t3)
	terrain.texture_slots[3].has_grass = bool(t4)
	terrain.texture_slots[4].has_grass = bool(t5)
	terrain.texture_slots[5].has_grass = bool(t6)


static func set_legacy_texture_slot(terrain, slot_idx: int, tex: Texture2D) -> void:
	ensure_texture_slots(terrain)
	if slot_idx < 0 or slot_idx >= 15:
		return
	terrain.texture_slots[slot_idx].texture = tex
	rebuild_texture_array(terrain)


static func set_legacy_texture_scale(terrain, slot_idx: int, scale: float) -> void:
	ensure_texture_slots(terrain)
	if slot_idx < 0 or slot_idx >= 15:
		return
	terrain.texture_slots[slot_idx].scale = scale
	push_tex_scales(terrain)


static func push_tex_scales(terrain) -> void:
	ensure_texture_slots(terrain)
	var scales := PackedFloat32Array()
	scales.resize(MAX_TEXTURE_SLOTS)
	for i in range(MAX_TEXTURE_SLOTS):
		scales[i] = float(terrain.texture_slots[i].scale) if terrain.texture_slots[i] != null else 1.0
	terrain.terrain_material.set_shader_parameter("tex_scales", scales)


static func rebuild_texture_array(terrain) -> void:
	# Build ONLY the 16 base layers used by the shader (0..15). All 0..255 slots map
	# onto these base layers via slot_tex_index_tex.
	ensure_texture_slots(terrain)
	var canonical_w := 1
	var canonical_h := 1

	# Find canonical size from the first non-null base texture (0..14).
	for i in range(15):
		var tex = terrain.texture_slots[i].texture if terrain.texture_slots[i] != null else null
		if tex == null:
			continue
		var img := MSTVertexColorHelper.get_decompressed_image(tex)
		if img == null:
			continue
		canonical_w = img.get_width()
		canonical_h = img.get_height()
		break

	# IMPORTANT: The terrain shader uses alpha scissoring. If placeholder layers are
	# transparent, the floor disappears. Use an opaque white placeholder so palette
	# tinting still renders even when a base texture is unset.
	var placeholder := Image.create_empty(canonical_w, canonical_h, false, Image.FORMAT_RGBA8)
	placeholder.fill(Color(1, 1, 1, 1))
	var void_placeholder := Image.create_empty(canonical_w, canonical_h, false, Image.FORMAT_RGBA8)
	void_placeholder.fill(Color(0, 0, 0, 0))

	var images: Array[Image] = []
	images.resize(16)
	for i in range(16):
		var is_void := i == VOID_TEXTURE_SLOT
		var slot_placeholder := (void_placeholder if is_void else placeholder)

		var tex = terrain.texture_slots[i].texture if (i < terrain.texture_slots.size() and terrain.texture_slots[i] != null) else null
		if is_void:
			# Force VOID layer to be transparent.
			images[i] = void_placeholder.duplicate()
			continue
		if tex == null:
			images[i] = slot_placeholder.duplicate()
			continue

		var src := MSTVertexColorHelper.get_decompressed_image(tex)
		if src == null:
			images[i] = slot_placeholder.duplicate()
			continue

		var needs_norm := src.get_width() != canonical_w or src.get_height() != canonical_h or src.get_format() != Image.FORMAT_RGBA8 or src.get_mipmap_count() > 1
		if needs_norm:
			MSTVertexColorHelper.warn_once(
				terrain._warned_texture_array_slots,
				i,
				"[MST] Base texture %d mismatches size/format/mipmaps; auto-normalizing to %dx%d RGBA8." % [i, canonical_w, canonical_h]
			)

		var img := MSTVertexColorHelper.normalize_image_for_texture_array(src, canonical_w, canonical_h)
		images[i] = img if img != null else slot_placeholder.duplicate()

	var arr := Texture2DArray.new()
	var err := arr.create_from_images(images)
	if err != OK:
		push_warning("[MST] Failed to build terrain Texture2DArray (err=%s)." % str(err))
		return

	terrain._runtime_texture_array = arr
	terrain.terrain_material.set_shader_parameter("vc_tex_array", terrain._runtime_texture_array)


static func rebuild_grass_texture_array(terrain) -> void:
	# PR1: The current grass shader (mst_grass.gdshader) expects 6 individual sprite textures
	# (grass_texture_1..6). The Texture2DArray path is not used by that shader.
	ensure_texture_slots(terrain)
	maybe_migrate_legacy_grass(terrain)
	if terrain.grass_mesh == null or terrain.grass_mesh.material == null:
		return

	var grass_mat := terrain.grass_mesh.material as ShaderMaterial

	var t1: Texture2D = terrain.grass_sprite_tex_1
	var t2: Texture2D = terrain.grass_sprite_tex_2
	var t3: Texture2D = terrain.grass_sprite_tex_3
	var t4: Texture2D = terrain.grass_sprite_tex_4
	var t5: Texture2D = terrain.grass_sprite_tex_5
	var t6: Texture2D = terrain.grass_sprite_tex_6

	if terrain.texture_slots.size() >= 6:
		var s0 = terrain.texture_slots[0]
		if s0 != null and s0.get("grass_texture") != null and s0.grass_texture != null:
			t1 = s0.grass_texture
		var s1 = terrain.texture_slots[1]
		if s1 != null and s1.get("grass_texture") != null and s1.grass_texture != null:
			t2 = s1.grass_texture
		var s2 = terrain.texture_slots[2]
		if s2 != null and s2.get("grass_texture") != null and s2.grass_texture != null:
			t3 = s2.grass_texture
		var s3 = terrain.texture_slots[3]
		if s3 != null and s3.get("grass_texture") != null and s3.grass_texture != null:
			t4 = s3.grass_texture
		var s4 = terrain.texture_slots[4]
		if s4 != null and s4.get("grass_texture") != null and s4.grass_texture != null:
			t5 = s4.grass_texture
		var s5 = terrain.texture_slots[5]
		if s5 != null and s5.get("grass_texture") != null and s5.grass_texture != null:
			t6 = s5.grass_texture

	grass_mat.set_shader_parameter("grass_texture_1", t1)
	grass_mat.set_shader_parameter("grass_texture_2", t2)
	grass_mat.set_shader_parameter("grass_texture_3", t3)
	grass_mat.set_shader_parameter("grass_texture_4", t4)
	grass_mat.set_shader_parameter("grass_texture_5", t5)
	grass_mat.set_shader_parameter("grass_texture_6", t6)

	terrain._runtime_grass_texture_array = null


# ---------------- Palette Helpers ----------------

static func ensure_palette_settings(terrain) -> void:
	# Expand palette-per-slot structures to 256 so shader uniform arrays are always valid.
	if terrain.slot_color_indices.size() != MAX_TEXTURE_SLOTS:
		terrain.slot_color_indices.resize(MAX_TEXTURE_SLOTS)
	for i in range(MAX_TEXTURE_SLOTS):
		if terrain.slot_color_indices[i] == null:
			terrain.slot_color_indices[i] = []

	if terrain.slot_blend_modes.size() != MAX_TEXTURE_SLOTS:
		terrain.slot_blend_modes.resize(MAX_TEXTURE_SLOTS)
	for i in range(MAX_TEXTURE_SLOTS):
		if terrain.slot_blend_modes[i] == null:
			terrain.slot_blend_modes[i] = 3

	if terrain.slot_has_outline.size() != MAX_TEXTURE_SLOTS:
		terrain.slot_has_outline.resize(MAX_TEXTURE_SLOTS)
	if terrain.slot_outline_modes.size() != MAX_TEXTURE_SLOTS:
		terrain.slot_outline_modes.resize(MAX_TEXTURE_SLOTS)
	if terrain.slot_outline_widths.size() != MAX_TEXTURE_SLOTS:
		terrain.slot_outline_widths.resize(MAX_TEXTURE_SLOTS)
	if terrain.slot_wet_enabled.size() != MAX_TEXTURE_SLOTS:
		terrain.slot_wet_enabled.resize(MAX_TEXTURE_SLOTS)
	if terrain.slot_wet_modes.size() != MAX_TEXTURE_SLOTS:
		terrain.slot_wet_modes.resize(MAX_TEXTURE_SLOTS)
	if terrain.slot_roughnesses.size() != MAX_TEXTURE_SLOTS:
		terrain.slot_roughnesses.resize(MAX_TEXTURE_SLOTS)
	for i in range(MAX_TEXTURE_SLOTS):
		if terrain.slot_has_outline[i] == null:
			terrain.slot_has_outline[i] = false
		if terrain.slot_outline_modes[i] == null:
			terrain.slot_outline_modes[i] = 0
		terrain.slot_outline_modes[i] = clampi(int(terrain.slot_outline_modes[i]), 0, 1)
		if terrain.slot_outline_widths[i] == null:
			terrain.slot_outline_widths[i] = terrain.outline_width
		terrain.slot_outline_widths[i] = clampf(float(terrain.slot_outline_widths[i]), 0.25, 32.0)
		if terrain.slot_wet_enabled[i] == null:
			terrain.slot_wet_enabled[i] = false
		if terrain.slot_wet_modes[i] == null:
			terrain.slot_wet_modes[i] = 0
		terrain.slot_wet_modes[i] = clampi(int(terrain.slot_wet_modes[i]), 0, 1)
		if terrain.slot_roughnesses[i] == null:
			terrain.slot_roughnesses[i] = 1.0
		terrain.slot_roughnesses[i] = clampf(float(terrain.slot_roughnesses[i]), 0.0, 1.0)


static func ensure_palette_weights(terrain) -> void:
	if terrain.palette_weights.size() != 128:
		terrain.palette_weights.resize(128)
	for i in range(128):
		if terrain.palette_weights[i] == null:
			terrain.palette_weights[i] = 100.0
		terrain.palette_weights[i] = clampf(float(terrain.palette_weights[i]), 0.0, 100.0)


static func migrate_colors_to_palette(terrain) -> void:
	if terrain.palette_colors.size() > 0:
		return  # Already migrated, skip

	terrain.palette_colors.resize(128)
	terrain.palette_colors[0] = terrain.tex1_color_1
	terrain.palette_colors[1] = terrain.tex2_color_1
	terrain.palette_colors[2] = terrain.tex3_color_1
	terrain.palette_colors[3] = terrain.tex4_color_1
	terrain.palette_colors[4] = terrain.tex5_color_1
	terrain.palette_colors[5] = terrain.tex6_color_1

	for i in range(6, 128):
		terrain.palette_colors[i] = Color("647851ff")

	terrain.palette_weights.resize(128)
	for i in range(128):
		terrain.palette_weights[i] = 100.0

	terrain.slot_color_indices = [[0], [1], [2], [3], [4], [5], [], [], [], [], [], [], [], [], []]


static func rebuild_palette_uniforms(terrain) -> void:
	# IMPORTANT: We cannot store slot palette data in large uniform arrays on all GPUs.
	# Some devices have a 64KB uniform buffer limit and will break when we use vec4[2048].
	# Instead, we upload palette data via small lookup textures.
	ensure_palette_weights(terrain)
	ensure_palette_settings(terrain)
	ensure_texture_slots(terrain)
	MSTVertexColorHelper.rebuild_palette_uniforms(terrain)
