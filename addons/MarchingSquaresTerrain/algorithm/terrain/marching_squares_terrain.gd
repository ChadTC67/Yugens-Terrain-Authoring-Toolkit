@tool
extends Node3D
class_name MarchingSquaresTerrain

const MSTVertexColorHelper := preload("res://addons/MarchingSquaresTerrain/algorithm/terrain/marching_squares_terrain_vertex_color_helper.gd")
const MarchingSquaresTerrainHelpers := preload("res://addons/MarchingSquaresTerrain/algorithm/terrain/marching_squares_terrain_helpers.gd")
const MarchingSquaresBaker := preload("res://addons/MarchingSquaresTerrain/editor/tools/marching_squares_baker.gd")

# Uses global class_name MSTDataHandler (static utility).

signal chunk_dimensions_changed(value: Vector3i)

enum StorageMode {
	## Saves load time. Loads a pre-built visual mesh from disk.
	## The collision mesh, grass etc. are generated when the scene loads.
	## (faster load, slightly larger files).
	BAKED,
	## Saves disk space. Generates everything from heightmaps when the scene loads.
	## This is overkill for most games.
	## (slower load, smallest files).
	RUNTIME,
}

@export_category("Storage Options")
## The storage mode for terrain data. 
@export var _storage_mode_internal : StorageMode = StorageMode.BAKED
var storage_mode : StorageMode:
	get():
		return _storage_mode_internal
	set(value):
		if _storage_mode_internal != value:
			_storage_mode_internal = value
			# Mark all chunks dirty to force re-save of data/meshes
			if chunks:
				for chunk in chunks.values():
					chunk.mark_dirty()
			print_verbose("[MST] Storage mode changed. All chunks marked for save.")
		notify_property_list_changed()

## If true, storage will include grass data, ignored if storage_mode = RUNTIME
var _bake_grass : bool = true
@export var bake_grass : bool = true:
	get():
		return _bake_grass
	set(value):
		_bake_grass = value
		for chunk in chunks.values():
			chunk.mark_dirty()



## If true, storage will include collision data, ignored if storage_mode = RUNTIME
var _bake_collision : bool = true
@export var bake_collision : bool = true:
	get():
		return _bake_collision
	set(value):
		_bake_collision = value
		for chunk in chunks.values():
			chunk.mark_dirty()



## The folder where this terrain's data is saved. 
## If left empty, it automatically fills with a folder name relative to your scene file.
## Note: Manually setting a path locks the save location even if you rename the terrain node later.
var _data_directory : String = ""
@export_dir var data_directory : String = "":
	get():
		if EngineWrapper.instance.is_editor() and _data_directory.is_empty():
			var auto_path := MSTDataHandler.generate_data_directory(self)
			if not auto_path.is_empty():
				_data_directory = auto_path
		return _data_directory
	set(value):
		_data_directory = value



@export_category("Runtime Baking")
## If this option is true, the textures will be baked into a texture atlas
## at runtime. This will improve rendering performance, but increase cost of generation
## slightly.
@export var enable_runtime_texture_baking : bool = true

## The resolution used per polygon when baking the texture atlas. Increase this value
## when using high-res textures. Higher values increase the baking time and memory usage.
@export var polygon_texture_resolution : int = 32

## Used for overriding the material of the baked terrain texture.
@export var bake_material_override : Material

# ---------------- Texture2DArray baking / library ----------------
@export var texture_library : Resource
@export_storage var baked_albedo_array_path : String = ""
@export_storage var baked_normal_array_path : String = ""
@export_storage var baked_grass_array_path : String = ""
@export var baked_texture_size : int = 512

## True after external storage has been initialized.
## Used to detect when migration from embedded data is needed.
@export_storage var _storage_initialized : bool = false
# One-time quick setup flag: when plugin/terrain is added, auto-create texture library + baked arrays if missing
@export_storage var _auto_quick_setup_done : bool = false

## Tracks the mode used during the last successful save for reporting purposes.
@export_storage var _last_storage_mode : StorageMode = StorageMode.BAKED

## One-time mesh migration flag: walls are now tagged via UV sentinel so shaders reliably detect walls.
## Existing chunks need a one-time regen to pick up the new UV values.
@export_storage var _uv_wall_sentinel_migrated : bool = false

## One-time mesh migration flag (v2): ensures wall UV sentinel uses UV=(2,2) to match shader detection.
@export_storage var _uv_wall_sentinel_v2_migrated : bool = false

## One-time mesh migration flag: wall vertices now compute their dominant materials from wall maps.
## Existing chunks need a one-time regen to pick up corrected wall material indices.
@export_storage var _wall_material_pair_migrated : bool = false

## One-time data migration flag: older chunks may have wall maps defaulted to Texture 1.
## We retarget these unpainted/legacy-initialized wall slots to default_wall_texture.
@export_storage var _default_wall_texture_migrated : bool = false

#region global terrain settings
# Terrain Settings
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var dimensions : Vector3i = Vector3i(33, 32, 33): # Total amount of height values in X and Z direction, and total height range
	set(value):
		dimensions = value
		terrain_material.set_shader_parameter("chunk_size", value)
		if EngineWrapper.instance.is_editor():
			emit_signal("chunk_dimensions_changed", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var cell_size : Vector2 = Vector2(2.0, 2.0): # XZ Unit size of each cell
	set(value):
		cell_size = value
		terrain_material.set_shader_parameter("cell_size", value)
		grass_size = grass_size
@export_custom(PROPERTY_HINT_RANGE, "0, 2", PROPERTY_USAGE_STORAGE) var blend_mode : int =  0:
	set(value):
		blend_mode = value
		if value == 1 or value == 2:
			terrain_material.set_shader_parameter("use_hard_textures", true)
		else:
			terrain_material.set_shader_parameter("use_hard_textures", false)
		terrain_material.set_shader_parameter("blend_mode", value)
		for chunk: MarchingSquaresTerrainChunk in chunks.values():
			chunk.regenerate_all_cells(true)

# Texture boundary waviness (blend noise). This controls ONLY the blend jitter/waves.
# Outlines stay clean/stable regardless.
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var blend_noise_enabled: bool =  false:
	set(value):
		blend_noise_enabled = bool(value)
		if is_batch_updating:
			return
		_apply_blend_noise_settings()

# Saved "on" strength so the toggle can restore your previous value.
@export_storage var _blend_noise_strength_saved: float = 0.2

func _apply_blend_noise_settings() -> void:
	if terrain_material == null:
		return
	if blend_noise_enabled:
		var s := float(_blend_noise_strength_saved)
		if s <=  0.0:
			s = 0.2
		terrain_material.set_shader_parameter("blend_noise_strength", s)
	else:
		var current := terrain_material.get_shader_parameter("blend_noise_strength")
		if current !=  null:
			var cs := float(current)
			if cs > 0.0:
				_blend_noise_strength_saved = cs
		terrain_material.set_shader_parameter("blend_noise_strength", 0.0)

@export_custom(PROPERTY_HINT_RANGE, "9, 32", PROPERTY_USAGE_STORAGE) var extra_collision_layer : int =  9:
	set(value):
		extra_collision_layer = value
		for chunk: MarchingSquaresTerrainChunk in chunks.values():
			chunk.regenerate_all_cells(true)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var use_cell_shading : bool =  true:
	set(value):
		use_cell_shading = value
		terrain_material.set_shader_parameter("use_cell_shading", value)
		var grass_mat := grass_mesh.material as ShaderMaterial
		grass_mat.set_shader_parameter("use_cell_shading", value)

# Backwards/forwards compat: scenes/presets may reference either "use_flat_normals" (shader) or legacy "flat_normals".
# Default is false (smooth normals).
var _use_flat_normals : bool = false
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var use_flat_normals : bool =  false:
	get():
		return _use_flat_normals
	set(value):
		_apply_flat_normals(bool(value))
var flat_normals : bool =  false:
	get():
		return _use_flat_normals
	set(value):
		_apply_flat_normals(bool(value))

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var wall_threshold : float = 0.0: # Determines what part of the terrain's mesh are walls
	set(value):
		wall_threshold = value
		terrain_material.set_shader_parameter("wall_threshold", value)
		var grass_mat := grass_mesh.material as ShaderMaterial
		grass_mat.set_shader_parameter("wall_threshold", value)
		for chunk: MarchingSquaresTerrainChunk in chunks.values():
			if chunk.grass_planter:
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var ridge_threshold: float =  1.0:
	set(value):
		ridge_threshold = value
		terrain_material.set_shader_parameter("ridge_threshold", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var ledge_threshold: float =  1.0:
	set(value):
		ledge_threshold = value
		terrain_material.set_shader_parameter("ledge_threshold", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var use_ridge_texture: bool =  true:
	set(value):
		use_ridge_texture = value
		terrain_material.set_shader_parameter("use_ridge_texture", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var use_ledge_texture: bool =  true:
	set(value):
		use_ledge_texture = value
		terrain_material.set_shader_parameter("use_ledge_texture", value)

# Convenience: texture used by the shader's global noise multiplier.
# Defaults to the same noise used for ridge/ledge so porting feels consistent.
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var global_noise_texture: Texture2D = EngineWrapper.load_resource("uid://dbnc04k3n0sro") as Texture2D:
	set(value):
		global_noise_texture = value
		if terrain_material !=  null:
			terrain_material.set_shader_parameter("global_noise_texture", value)
		_sync_global_noise_to_grass()

@export_custom(PROPERTY_HINT_RANGE, "0.0, 1.0, 0.01", PROPERTY_USAGE_STORAGE) var global_noise_strength: float =  1.0:
	set(value):
		global_noise_strength = clampf(float(value), 0.0, 1.0)
		if terrain_material !=  null:
			terrain_material.set_shader_parameter("global_noise_strength", global_noise_strength)
		_sync_global_noise_to_grass()

@export_custom(PROPERTY_HINT_RANGE, "0.001, 1.0, 0.001", PROPERTY_USAGE_STORAGE) var global_noise_scale: float =  0.037:
	set(value):
		global_noise_scale = clampf(float(value), 0.001, 1.0)
		if terrain_material !=  null:
			terrain_material.set_shader_parameter("global_noise_scale", global_noise_scale)
		_sync_global_noise_to_grass()


@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var noise_hmap : Noise # used to generate smooth initial heights for more natrual looking terrain. if null, initial terrain will be flat

# Grass settings
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var animation_fps : int =  0:
	set(value):
		animation_fps = clamp(value, 0, 30)
		var grass_mat := grass_mesh.material as ShaderMaterial
		grass_mat.set_shader_parameter("fps", clamp(value, 0, 30))
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_subdivisions : int =  3:
	set(value):
		grass_subdivisions = value
		for chunk: MarchingSquaresTerrainChunk in chunks.values():
			if not chunk.grass_planter or not chunk.grass_planter.multimesh:
				continue
			chunk.grass_planter.multimesh.instance_count = (dimensions.x-1) * (dimensions.z-1) * grass_subdivisions * grass_subdivisions
			chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_size : Vector2 =  Vector2(1.0, 1.0):
	set(value):
		grass_size = value
		var scale_factor := (cell_size.x + cell_size.y) / 4.0
		var scaled_value := value * scale_factor

		# Update the shared grass mesh first (safe even before chunks initialize).
		if grass_mesh:
			grass_mesh.size = scaled_value
			grass_mesh.center_offset.y = scaled_value.y / 2.0

		# Chunks may not have created GrassPlanter/Multimesh yet during early startup.
		for chunk: MarchingSquaresTerrainChunk in chunks.values():
			if not chunk or not chunk.grass_planter or not chunk.grass_planter.multimesh or not chunk.grass_planter.multimesh.mesh:
				continue
			chunk.grass_planter.multimesh.mesh.size = scaled_value
			chunk.grass_planter.multimesh.mesh.center_offset.y = scaled_value.y / 2.0
#endregion

#region vertex painting texture settings
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_1 : Texture2D =  null:
	set(value):
		texture_1 = value
		if not is_batch_updating:
			_set_legacy_texture_slot(0, value)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_2 : Texture2D =  null:
	set(value):
		texture_2 = value
		if not is_batch_updating:
			_set_legacy_texture_slot(1, value)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_3 : Texture2D =  null:
	set(value):
		texture_3 = value
		if not is_batch_updating:
			_set_legacy_texture_slot(2, value)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_4 : Texture2D =  null:
	set(value):
		texture_4 = value
		if not is_batch_updating:
			_set_legacy_texture_slot(3, value)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_5 : Texture2D =  null:
	set(value):
		texture_5 = value
		if not is_batch_updating:
			_set_legacy_texture_slot(4, value)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_6 : Texture2D =  null:
	set(value):
		texture_6 = value
		if not is_batch_updating:
			_set_legacy_texture_slot(5, value)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_7 : Texture2D = null:
	set(value):
		texture_7 = value
		if not is_batch_updating:
			_set_legacy_texture_slot(6, value)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_8 : Texture2D = null:
	set(value):
		texture_8 = value
		if not is_batch_updating:
			_set_legacy_texture_slot(7, value)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_9 : Texture2D = null:
	set(value):
		texture_9 = value
		if not is_batch_updating:
			_set_legacy_texture_slot(8, value)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_10 : Texture2D = null:
	set(value):
		texture_10 = value
		if not is_batch_updating:
			_set_legacy_texture_slot(9, value)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_11 : Texture2D = null:
	set(value):
		texture_11 = value
		if not is_batch_updating:
			_set_legacy_texture_slot(10, value)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_12 : Texture2D = null:
	set(value):
		texture_12 = value
		if not is_batch_updating:
			_set_legacy_texture_slot(11, value)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_13 : Texture2D = null:
	set(value):
		texture_13 = value
		if not is_batch_updating:
			_set_legacy_texture_slot(12, value)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_14 : Texture2D = null:
	set(value):
		texture_14 = value
		if not is_batch_updating:
			_set_legacy_texture_slot(13, value)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_15 : Texture2D = null:
	set(value):
		texture_15 = value
		if not is_batch_updating:
			_set_legacy_texture_slot(14, value)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
#endregion

#region texture slots (256)
const MAX_TEXTURE_SLOTS := 256
# Keep legacy VOID behavior for now (texture_15 in the old system).
const VOID_TEXTURE_SLOT := 15

# NOTE: Avoid hard type-hints here; headless/script-cache builds may not resolve global class_names reliably.
const _TEXTURE_SLOT_SCRIPT := preload("res://addons/MarchingSquaresTerrain/resources/marching_squares_texture_slot.gd")

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_slots: Array = []
@export_custom(PROPERTY_HINT_RANGE, "1,256,1", PROPERTY_USAGE_STORAGE) var visible_texture_slot_count: int = 6

# Runtime-built Texture2DArrays. Intentionally NOT stored in scenes (prevents .tscn bloat).
var _runtime_texture_array: Texture2DArray = null
var _runtime_grass_texture_array: Texture2DArray = null

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NO_EDITOR) var texture_array: Texture2DArray:
	get:
		return _runtime_texture_array
	set(value):
		# Ignore any serialized value from older scenes; we always rebuild at runtime.
		pass

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NO_EDITOR) var grass_texture_array: Texture2DArray:
	get:
		return _runtime_grass_texture_array
	set(value):
		pass

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var _grass_slots_migrated: bool = false

# Warn about normalization/mismatches only once per slot to avoid editor spam.
var _warned_texture_array_slots: Dictionary = {}
var _warned_grass_array_slots: Dictionary = {}
#endregion

#region grass textures (legacy exports -> slot grass_texture)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_sprite_tex_1 : Texture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/grass_leaf_sprite.png"):
	set(value):
		grass_sprite_tex_1 = value
		if not is_batch_updating:
			_ensure_texture_slots()
			_maybe_migrate_legacy_grass()
			texture_slots[0].grass_texture = value
			rebuild_grass_texture_array()
			_request_grass_regen()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_sprite_tex_2 : Texture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/grass_leaf_sprite.png"):
	set(value):
		grass_sprite_tex_2 = value
		if not is_batch_updating:
			_ensure_texture_slots()
			_maybe_migrate_legacy_grass()
			texture_slots[1].grass_texture = value
			rebuild_grass_texture_array()
			_request_grass_regen()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_sprite_tex_3 : Texture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/grass_leaf_sprite.png"):
	set(value):
		grass_sprite_tex_3 = value
		if not is_batch_updating:
			_ensure_texture_slots()
			_maybe_migrate_legacy_grass()
			texture_slots[2].grass_texture = value
			rebuild_grass_texture_array()
			_request_grass_regen()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_sprite_tex_4 : Texture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/grass_leaf_sprite.png"):
	set(value):
		grass_sprite_tex_4 = value
		if not is_batch_updating:
			_ensure_texture_slots()
			_maybe_migrate_legacy_grass()
			texture_slots[3].grass_texture = value
			rebuild_grass_texture_array()
			_request_grass_regen()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_sprite_tex_5 : Texture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/grass_leaf_sprite.png"):
	set(value):
		grass_sprite_tex_5 = value
		if not is_batch_updating:
			_ensure_texture_slots()
			_maybe_migrate_legacy_grass()
			texture_slots[4].grass_texture = value
			rebuild_grass_texture_array()
			_request_grass_regen()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_sprite_tex_6 : Texture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/grass_leaf_sprite.png"):
	set(value):
		grass_sprite_tex_6 = value
		if not is_batch_updating:
			_ensure_texture_slots()
			_maybe_migrate_legacy_grass()
			texture_slots[5].grass_texture = value
			rebuild_grass_texture_array()
			_request_grass_regen()
#endregion

#region has grass variables (legacy exports -> slot has_grass)
# Texture 1 was historically always-on; now exposed so "Base Grass" can be disabled.
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex1_has_grass : bool =  true:
	set(value):
		tex1_has_grass = bool(value) if value != null else true
		if not is_batch_updating:
			_ensure_texture_slots()
			_maybe_migrate_legacy_grass()
			texture_slots[0].has_grass = tex1_has_grass
			_request_grass_regen()

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex2_has_grass : bool =  true:
	set(value):
		tex2_has_grass = bool(value) if value != null else true
		if not is_batch_updating:
			_ensure_texture_slots()
			_maybe_migrate_legacy_grass()
			texture_slots[1].has_grass = tex2_has_grass
			_request_grass_regen()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex3_has_grass : bool =  true:
	set(value):
		tex3_has_grass = bool(value) if value != null else true
		if not is_batch_updating:
			_ensure_texture_slots()
			_maybe_migrate_legacy_grass()
			texture_slots[2].has_grass = tex3_has_grass
			_request_grass_regen()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex4_has_grass : bool =  true:
	set(value):
		tex4_has_grass = bool(value) if value != null else true
		if not is_batch_updating:
			_ensure_texture_slots()
			_maybe_migrate_legacy_grass()
			texture_slots[3].has_grass = tex4_has_grass
			_request_grass_regen()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex5_has_grass : bool =  true:
	set(value):
		tex5_has_grass = bool(value) if value != null else true
		if not is_batch_updating:
			_ensure_texture_slots()
			_maybe_migrate_legacy_grass()
			texture_slots[4].has_grass = tex5_has_grass
			_request_grass_regen()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex6_has_grass : bool =  true:
	set(value):
		tex6_has_grass = bool(value) if value != null else true
		if not is_batch_updating:
			_ensure_texture_slots()
			_maybe_migrate_legacy_grass()
			texture_slots[5].has_grass = tex6_has_grass
			_request_grass_regen()
#endregion

#region texture albedos
#These are just for migration into the Palette system
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex1_color_1 : Color = Color("647851ff")

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex2_color_1 : Color = Color("647851ff")

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex3_color_1 : Color = Color("647851ff")

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex4_color_1 : Color = Color("647851ff")

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex5_color_1 : Color = Color("647851ff")

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex6_color_1 : Color = Color("c4a57aff")  # Light-brown default for Texture 6 (base wall)

#endregion

#region texture scales
# Per-texture UV scaling (applied in shader)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_1 : float =  1.0:
	set(value):
		texture_scale_1 = value
		if not is_batch_updating:
			_set_legacy_texture_scale(0, value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_2 : float =  1.0:
	set(value):
		texture_scale_2 = value
		if not is_batch_updating:
			_set_legacy_texture_scale(1, value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_3 : float =  1.0:
	set(value):
		texture_scale_3 = value
		if not is_batch_updating:
			_set_legacy_texture_scale(2, value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_4 : float =  1.0:
	set(value):
		texture_scale_4 = value
		if not is_batch_updating:
			_set_legacy_texture_scale(3, value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_5 : float =  1.0:
	set(value):
		texture_scale_5 = value
		if not is_batch_updating:
			_set_legacy_texture_scale(4, value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_6 : float =  1.0:
	set(value):
		texture_scale_6 = value
		if not is_batch_updating:
			_set_legacy_texture_scale(5, value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_7 : float =  1.0:
	set(value):
		texture_scale_7 = value
		if not is_batch_updating:
			_set_legacy_texture_scale(6, value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_8 : float =  1.0:
	set(value):
		texture_scale_8 = value
		if not is_batch_updating:
			_set_legacy_texture_scale(7, value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_9 : float =  1.0:
	set(value):
		texture_scale_9 = value
		if not is_batch_updating:
			_set_legacy_texture_scale(8, value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_10 : float =  1.0:
	set(value):
		texture_scale_10 = value
		if not is_batch_updating:
			_set_legacy_texture_scale(9, value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_11 : float =  1.0:
	set(value):
		texture_scale_11 = value
		if not is_batch_updating:
			_set_legacy_texture_scale(10, value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_12 : float =  1.0:
	set(value):
		texture_scale_12 = value
		if not is_batch_updating:
			_set_legacy_texture_scale(11, value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_13 : float =  1.0:
	set(value):
		texture_scale_13 = value
		if not is_batch_updating:
			_set_legacy_texture_scale(12, value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_14 : float =  1.0:
	set(value):
		texture_scale_14 = value
		if not is_batch_updating:
			_set_legacy_texture_scale(13, value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_15 : float =  1.0:
	set(value):
		texture_scale_15 = value
		if not is_batch_updating:
			_set_legacy_texture_scale(14, value)
#endregion

@export_storage var current_texture_preset : MarchingSquaresTexturePreset = null

# Palette System
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var palette_colors: Array[Color] = []
# Per palette-index weight (0-100). Used to control per-slot palette distribution.
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var palette_weights: Array[float] = []
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var slot_color_indices: Array = [
	[], [], [], [], [], [], [], [], [], [], [], [], [], [], []
]
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var slot_blend_modes: Array[int] = [3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3]

@export_category("Vertex Painter")
# Outline settings (per texture slot)
# slot_has_outline[slot] enables a thin edge/foam line where that texture blends with another.
# slot_outline_modes[slot]: 0 = darken Color 1, 1 = use last palette color
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var slot_has_outline: Array[bool] = [false, false, false, false, false, false, false, false, false, false, false, false, false, false, false]
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var slot_outline_modes: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
# slot_outline_widths[slot] controls the thickness of the per-material "foam" outline when textures meet.
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var slot_outline_widths: Array[float] = [
	6.0, 6.0, 6.0, 6.0, 6.0,
	6.0, 6.0, 6.0, 6.0, 6.0,
	6.0, 6.0, 6.0, 6.0, 6.0,
]

# Wetness controls (per texture slot)
# slot_wet_enabled[slot] toggles wetness effects on/off for that slot.
# slot_wet_modes[slot]: 0 = Wet (darken only), 1 = Glossy puddles (noise-masked).
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var slot_wet_enabled: Array[bool] = [
	false, false, false, false, false,
	false, false, false, false, false,
	false, false, false, false, false,
]
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var slot_wet_modes: Array[int] = [
	0, 0, 0, 0, 0,
	0, 0, 0, 0, 0,
	0, 0, 0, 0, 0,
]

# slot_roughnesses[slot] controls surface roughness (0 = shiny/wet, 1 = matte/dry).
# (UI presents this as "Wetness" by storing roughness = 1 - wetness)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var slot_roughnesses: Array[float] = [
	1.0, 1.0, 1.0, 1.0, 1.0,
	1.0, 1.0, 1.0, 1.0, 1.0,
	1.0, 1.0, 1.0, 1.0, 1.0,
]

@export_custom(PROPERTY_HINT_RANGE, "0.25,32.0,0.25", PROPERTY_USAGE_STORAGE) var outline_width: float =  6.0:
	set(value):
		outline_width = clampf(value, 0.25, 32.0)
		if not is_batch_updating and terrain_material:
			terrain_material.set_shader_parameter("outline_width", outline_width)


# Default wall texture slot (0-15) used when no quick paint is active
# Default is 5 (Texture 6 in 1-indexed UI terms)
@export_storage var default_wall_texture : int =  5:
	set(value):
		var old := default_wall_texture
		default_wall_texture = clampi(int(value), 0, 255)
		if is_batch_updating:
			return
		_apply_default_wall_texture_change(old, default_wall_texture)


func _apply_default_wall_texture_change(old_idx: int, new_idx: int) -> void:
	if chunks.is_empty():
		return
	for chunk: MarchingSquaresTerrainChunk in chunks.values():
		var changed: bool = bool(chunk.apply_default_wall_texture(old_idx, new_idx))
		# Also update "unpainted" wall cells (those matching ground) to follow the new default.
		changed = bool(chunk.apply_default_wall_to_unpainted(new_idx)) or changed
		if changed:
			chunk.regenerate_all_cells(true)

signal load_finished

var void_texture := preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/void_texture.tres")

var terrain_material : ShaderMaterial = null
var grass_mesh : QuadMesh = null 

var is_batch_updating : bool = false

var chunks : Dictionary = {}


func _sync_global_noise_to_grass() -> void:
	if grass_mesh == null or terrain_material == null:
		return
	var grass_mat := grass_mesh.material as ShaderMaterial
	if grass_mat == null:
		return
	grass_mat.set_shader_parameter("global_noise_texture", global_noise_texture)
	for p in ["global_noise_scale", "global_noise_strength", "global_noise_scroll", "wind_direction", "wind_speed"]:
		var v := terrain_material.get_shader_parameter(p)
		if v !=  null:
			grass_mat.set_shader_parameter(p, v)


func _validate_property(property: Dictionary) -> void:
	if property.name in ["bake_grass", "bake_collision"]:
		if storage_mode !=  StorageMode.BAKED:
			property.usage = PROPERTY_USAGE_NO_EDITOR


func _init() -> void:
	# Create unique copies of shared resources for this node instance
	# This prevents texture/material changes from affecting other MarchingSquaresTerrain nodes
	terrain_material = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/mst_terrain_shader.tres").duplicate(true)
	terrain_material.set_shader_parameter("global_noise_texture", global_noise_texture)
	terrain_material.set_shader_parameter("global_noise_strength", global_noise_strength)
	terrain_material.set_shader_parameter("global_noise_scale", global_noise_scale)
	var base_grass_mesh := preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/mst_grass_mesh.tres")
	grass_mesh = base_grass_mesh.duplicate(true)
	grass_mesh.material = base_grass_mesh.material.duplicate(true)
	_sync_global_noise_to_grass()
	print_verbose("Last storage mode: ", _last_storage_mode)

	# Sync shader state for scenes/presets that set flat normals.
	_apply_flat_normals(_use_flat_normals)

	_ensure_texture_slots()
	_maybe_migrate_legacy_textures()
	rebuild_texture_array()
	_push_tex_scales()
	_ensure_palette_settings()
	_rebuild_palette_uniforms()



func get_chunk_surface_material() -> Material:
	return terrain_material


var _grass_regen_timer: Timer = null
var _grass_regen_pending: bool = false


func _request_grass_regen() -> void:
	if is_batch_updating:
		return

	# Coalesce editor slider drags into a single grass rebuild.
	if EngineWrapper.instance.is_editor():
		# Tool scripts can run while the node is not inside the scene tree (e.g. during load).
		# Timers cannot be started until we're inside the tree.
		if not is_inside_tree():
			_grass_regen_pending = true
			return
		if _grass_regen_timer == null:
			_grass_regen_timer = Timer.new()
			_grass_regen_timer.name = "_mst_grass_regen_timer"
			_grass_regen_timer.one_shot = true
			add_child(_grass_regen_timer)
			_grass_regen_timer.timeout.connect(_apply_grass_regen)
		_grass_regen_timer.wait_time = 0.12
		_grass_regen_timer.start()
		return

	_apply_grass_regen()


func _apply_grass_regen() -> void:
	for chunk: MarchingSquaresTerrainChunk in chunks.values():
		if chunk and chunk.grass_planter:
			chunk.grass_planter.regenerate_all_cells()


func _apply_flat_normals(p_enabled: bool) -> void:
	_use_flat_normals = p_enabled
	# Terrain shader expects "use_flat_normals".
	if terrain_material !=  null:
		terrain_material.set_shader_parameter("use_flat_normals", _use_flat_normals)
	# Grass instances use this flag when generating normals.
	_request_grass_regen()


func _ensure_texture_slots() -> void:
	MarchingSquaresTerrainHelpers.ensure_texture_slots(self)


func _ensure_palette_settings() -> void:
	MarchingSquaresTerrainHelpers.ensure_palette_settings(self)


func _maybe_migrate_legacy_textures() -> void:
	MarchingSquaresTerrainHelpers.maybe_migrate_legacy_textures(self)


func _maybe_migrate_legacy_grass() -> void:
	MarchingSquaresTerrainHelpers.maybe_migrate_legacy_grass(self)


func _set_legacy_texture_slot(slot_idx: int, tex: Texture2D) -> void:
	MarchingSquaresTerrainHelpers.set_legacy_texture_slot(self, slot_idx, tex)


func _set_legacy_texture_scale(slot_idx: int, scale: float) -> void:
	MarchingSquaresTerrainHelpers.set_legacy_texture_scale(self, slot_idx, scale)


func _push_tex_scales() -> void:
	MarchingSquaresTerrainHelpers.push_tex_scales(self)


func _get_decompressed_image(tex: Texture2D) -> Image:
	return MSTVertexColorHelper.get_decompressed_image(tex)


func _warn_once(cache: Dictionary, key, message: String) -> void:
	MSTVertexColorHelper.warn_once(cache, key, message)


func _normalize_image_for_texture_array(src: Image, w: int, h: int) -> Image:
	return MSTVertexColorHelper.normalize_image_for_texture_array(src, w, h)


func rebuild_texture_array() -> void:
	MarchingSquaresTerrainHelpers.rebuild_texture_array(self)


func rebuild_grass_texture_array() -> void:
	MarchingSquaresTerrainHelpers.rebuild_grass_texture_array(self)


func _notification(what: int) -> void:
	# Save all dirty chunks to external storage before scene save
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		if EngineWrapper.instance.is_editor():
			MSTDataHandler.save_all_chunks(self)


func _enter_tree() -> void:
	_deferred_enter_tree.call_deferred()


func _initialize_data_directory() -> void:
	var copy_from_dir := ""
	if EngineWrapper.instance.is_editor() and not data_directory.is_empty() and not MSTDataHandler.is_data_directory_unique(self):
		copy_from_dir = data_directory
		data_directory = ""
	
	if EngineWrapper.instance.is_editor() and (data_directory.is_empty()):
		var auto_path := MSTDataHandler.generate_data_directory(self)
		if not auto_path.is_empty():
			data_directory = auto_path
	if copy_from_dir:
		MSTDataHandler.copy_recursive(copy_from_dir, data_directory)


func _deferred_enter_tree() -> void:
	_initialize_data_directory()
	
	print_verbose("Terrain data dir: ", data_directory)
	
	# Populate chunks dictionary from scene children
	# NOTE: Chunks can legitimately be "dirty" in editor (e.g. after property edits).
	# Never abort initialization because that prevents terrain from loading/rendering.
	for chunk in get_children():
		if chunk is MarchingSquaresTerrainChunk:
			pass
	chunks.clear()
	for chunk in get_children():
		if chunk is MarchingSquaresTerrainChunk:
			chunks[chunk.chunk_coords] = chunk
			chunk.terrain_system = self
			chunk.grass_planter = null
	
	# Load external data if storage was previously initialized
	if _storage_initialized:
		MSTDataHandler.load_terrain_data(self)
	elif EngineWrapper.instance.is_editor() and MSTDataHandler.needs_migration(self):
		# Auto-migrate embedded data to external storage (editor only)
		MSTDataHandler.migrate_to_external_storage(self)
	
	# Apply all persisted textures/colors to this terrain's unique shader materials
	# This is needed because _init() creates fresh duplicated materials that don't have
	# the terrain's saved texture values - only the base resource defaults
	# IMPORTANT: do this BEFORE chunk initialization so runtime texture baking sees correct uniforms.
	migrate_colors_to_palette()
	force_batch_update()
	
	# One-time editor migrations: regenerate meshes so new wall tagging/material selection is present in geometry.

	# Auto Quick Setup: when the terrain is created in the editor for the first time,
	# create a MSTextureLibrary and baked arrays if none exist. This makes plugin usable
	# immediately without pressing UI buttons.
	if EngineWrapper.instance.is_editor() and not _auto_quick_setup_done:
		# Only run if no library and no baked paths are present
		var need_lib := (texture_library == null)
		var need_baked := (baked_albedo_array_path == "" or baked_normal_array_path == "")
		if need_lib or need_baked:
			_auto_quick_setup_done = true
			# Build MSTextureLibrary from existing texture_slots
			var lib: MSTextureLibrary = MSTextureLibrary.new()
			lib.max_slots = 256
			lib.ensure_length()
			if texture_slots is Array:
				for i in range(lib.max_slots):
					var slot = texture_slots[i] if i < texture_slots.size() else null
					if slot !=  null and slot.texture != null and slot.texture is Texture2D:
						lib.albedo_textures[i] = slot.texture
						# If slot provides a normal field, prefer that.
						if slot.has_method("get") and slot.get("normal_texture") !=  null:
							var nt = slot.get("normal_texture")
							if nt is Texture2D:
								lib.normal_textures[i] = nt
				# Save library
				var out_dir := data_directory
				if out_dir == null or out_dir == "":
					out_dir = "res://scenes"
				var lib_path := out_dir.path_join("mst_texture_library.tres")
				ResourceSaver.save(lib, lib_path)
				# Load saved lib resource and assign
				var lib_res := ResourceLoader.load(lib_path)
				if lib_res !=  null:
					texture_library = lib_res
					# Bake arrays into same folder if missing
					var baker := MarchingSquaresBaker.new()
					var bake_size := int(baked_texture_size) if baked_texture_size != null else 512
					var results := baker.bake_library(lib_res, out_dir, bake_size)
					if results and results.has("albedo_path"):
						baked_albedo_array_path = results["albedo_path"]
					if results and results.has("normal_path"):
						baked_normal_array_path = results["normal_path"]
					if results and results.has("grass_path"):
						baked_grass_array_path = results["grass_path"]
					# Switch to baked storage for best perf
					storage_mode = StorageMode.BAKED
					# Rebuild runtime arrays
					rebuild_texture_array()
					rebuild_grass_texture_array()
					print_verbose("[MST] Auto Quick Setup completed: library + baked arrays created at ", out_dir)
				else:
					print_verbose("[MST] Auto Quick Setup: failed to save/load MSTextureLibrary")

	# Initialize all chunks (regenerate mesh/grass from loaded data)
	var force_regen_for_wall_fixes : bool = false
	var force_regen_for_default_wall : bool = false
	if EngineWrapper.instance.is_editor():
		if not _uv_wall_sentinel_migrated:
			_uv_wall_sentinel_migrated = true
			force_regen_for_wall_fixes = true
		if not _uv_wall_sentinel_v2_migrated:
			_uv_wall_sentinel_v2_migrated = true
			force_regen_for_wall_fixes = true
		if not _wall_material_pair_migrated:
			_wall_material_pair_migrated = true
			force_regen_for_wall_fixes = true
		if not _default_wall_texture_migrated:
			_default_wall_texture_migrated = true
			force_regen_for_default_wall = true
	
	# Initialize all chunks (regenerate mesh/grass from loaded data)
	for chunk : MarchingSquaresTerrainChunk in chunks.values():
		chunk.initialize_terrain(true)
		if force_regen_for_wall_fixes:
			chunk.regenerate_mesh(true)
		if force_regen_for_default_wall:
			var changed_default := bool(chunk.apply_default_wall_to_unpainted(default_wall_texture))
			changed_default = bool(chunk.apply_default_wall_to_legacy_init(default_wall_texture)) or changed_default
			if changed_default:
				chunk.regenerate_all_cells(true)
	
	# If any tool-script setters tried to schedule work before we entered the tree,
	# flush it now.
	if _grass_regen_pending:
		_grass_regen_pending = false
		_apply_grass_regen()
	
	load_finished.emit()


func _exit_tree() -> void:
	# Ensure editor-time terrain data is saved when the terrain node is removed or scene switched.
	if EngineWrapper.instance.is_editor():
		# Only attempt save if data_directory is known (generated on enter_tree)
		if data_directory !=  null and data_directory != "":
			MSTDataHandler.save_all_chunks(self)
		# Clear chunks map to avoid holding references after exit
		chunks.clear()
		# Let children handle their own cleanup (chunk._exit_tree will run)

func has_chunk(x: int, z: int) -> bool:
	return chunks.has(Vector2i(x, z))


func add_new_chunk(chunk_x: int, chunk_z: int, plugin):
	var chunk_coords := Vector2i(chunk_x, chunk_z)
	var new_chunk := MarchingSquaresTerrainChunk.new()
	new_chunk.name = "Chunk "+str(chunk_coords)
	new_chunk.terrain_system = self
	
	new_chunk.generate_height_map(plugin.height)
	new_chunk.mark_dirty()
	
	add_chunk(chunk_coords, new_chunk, plugin, false)
	
	if plugin.current_quick_paint:
		plugin.current_draw_pattern.clear()
		plugin.current_draw_pattern[chunk_coords] = {}
		
		for z in range(dimensions.z):
			for x in range(dimensions.x):
				var cell := Vector2i(x, z)
				plugin.current_draw_pattern[chunk_coords][cell] = 1.0
		
		plugin.draw_pattern(self) # Apply the current selected quick paint to the new chunk on creation
		plugin.current_draw_pattern.clear()
	
	var chunk_left : MarchingSquaresTerrainChunk = chunks.get(Vector2i(chunk_x-1, chunk_z))
	if chunk_left and not chunk_left.height_map.is_empty() and not new_chunk.height_map.is_empty():
		for z in range(0, dimensions.z):
			if z < chunk_left.height_map.size() and z < new_chunk.height_map.size() and chunk_left.height_map[z].size() >=  dimensions.x and new_chunk.height_map[z].size() >= 1:
				new_chunk.height_map[z][0] = chunk_left.height_map[z][dimensions.x - 1]
	
	var chunk_right : MarchingSquaresTerrainChunk = chunks.get(Vector2i(chunk_x+1, chunk_z))
	if chunk_right and not chunk_right.height_map.is_empty() and not new_chunk.height_map.is_empty():
		for z in range(0, dimensions.z):
			if z < chunk_right.height_map.size() and z < new_chunk.height_map.size() and chunk_right.height_map[z].size() >=  1 and new_chunk.height_map[z].size() >= dimensions.x:
				new_chunk.height_map[z][dimensions.x - 1] = chunk_right.height_map[z][0]
	
	var chunk_up : MarchingSquaresTerrainChunk = chunks.get(Vector2i(chunk_x, chunk_z-1))
	if chunk_up and not chunk_up.height_map.is_empty() and not new_chunk.height_map.is_empty():
		if chunk_up.height_map.size() >=  dimensions.z and new_chunk.height_map.size() >= 1:
			for x in range(0, dimensions.x):
				if x < chunk_up.height_map[dimensions.z - 1].size() and x < new_chunk.height_map[0].size():
					new_chunk.height_map[0][x] = chunk_up.height_map[dimensions.z - 1][x]
	
	var chunk_down : MarchingSquaresTerrainChunk = chunks.get(Vector2i(chunk_x, chunk_z+1))
	if chunk_down and not chunk_down.height_map.is_empty() and not new_chunk.height_map.is_empty():
		if chunk_down.height_map.size() >=  1 and new_chunk.height_map.size() >= dimensions.z:
			for x in range(0, dimensions.x):
				if x < chunk_down.height_map[0].size() and x < new_chunk.height_map[dimensions.z - 1].size():
					new_chunk.height_map[dimensions.z - 1][x] = chunk_down.height_map[0][x]
	
	new_chunk.regenerate_mesh()


func remove_chunk(x: int, z: int, plugin):
	var chunk_coords := Vector2i(x, z)
	var chunk : MarchingSquaresTerrainChunk = chunks[chunk_coords]
	chunks.erase(chunk_coords)  # Use chunk_coords, not chunk object
	chunk.free()
	
	if plugin.selected_chunk and plugin.selected_chunk.chunk_coords == chunk.chunk_coords:
		var temp_chunk := MarchingSquaresTerrainChunk.new()
		temp_chunk.chunk_coords = Vector2i(99999, 99999)
		plugin.selected_chunk = temp_chunk
		for child in get_children():
			if child is MarchingSquaresTerrainChunk:
				plugin.selected_chunk = child
				break
	plugin.ui.tool_attributes.show_tool_attributes(plugin.TerrainToolMode.CHUNK_MANAGEMENT)
	plugin.gizmo_plugin.trigger_redraw(self)


# Remove a chunk but still keep it in memory (so that undo can restore it)
func remove_chunk_from_tree(x: int, z: int, plugin):
	var chunk_coords := Vector2i(x, z)
	var chunk : MarchingSquaresTerrainChunk = chunks[chunk_coords]
	chunks.erase(chunk_coords)  # Use chunk_coords, not chunk object
	chunk._skip_save_on_exit = true  # Prevent mesh save during undo/redo
	remove_child(chunk)
	chunk.owner = null
	
	if plugin.selected_chunk and plugin.selected_chunk.chunk_coords == chunk.chunk_coords:
		var temp_chunk := MarchingSquaresTerrainChunk.new()
		temp_chunk.chunk_coords = Vector2i(99999, 99999)
		plugin.selected_chunk = temp_chunk
		for child in get_children():
			if child is MarchingSquaresTerrainChunk:
				plugin.selected_chunk = child
				break
	plugin.ui.tool_attributes.show_tool_attributes(plugin.TerrainToolMode.CHUNK_MANAGEMENT)
	plugin.gizmo_plugin.trigger_redraw(self)


func add_chunk(coords: Vector2i, chunk: MarchingSquaresTerrainChunk, plugin, regenerate_mesh: bool =  true):
	chunk.terrain_system = self
	chunk.chunk_coords = coords
	chunk._skip_save_on_exit = false  # Reset flag when chunk is re-added (undo restores chunk)
	add_child(chunk)
	chunks[coords] = chunk
	
	# Use position instead of global_position to avoid "is_inside_tree()" errors
	# when multiple scenes with MarchingSquaresTerrain are open in editor tabs.
	# Since chunks are direct children of terrain, position equals global_position.
	chunk.position = Vector3(
		coords.x * ((dimensions.x - 1) * cell_size.x),
		0,
		coords.y * ((dimensions.z - 1) * cell_size.y)
	)
	
	EngineWrapper.instance.set_owner_recursive(chunk)
	chunk.initialize_terrain(regenerate_mesh)
	print_verbose("[MST] Added new chunk to terrain system at ", chunk)
	if plugin:
		if not plugin.selected_chunk or plugin.selected_chunk.chunk_coords == Vector2i(99999, 99999):
			plugin.selected_chunk = chunk
		plugin.ui.tool_attributes.show_tool_attributes(plugin.TerrainToolMode.CHUNK_MANAGEMENT)
		plugin.gizmo_plugin.trigger_redraw(self)

#region texture (set) functions

# WARNING: this function is currently not being used anymore. [Q] Yūgen: was that intentional?
# This (legacy) function is mainly there to ensure the plugin works on startup in a new project
func _ensure_textures() -> void:
	var grass_mat := grass_mesh.material as ShaderMaterial
	# Keep legacy behavior of ensuring textures are hooked up on startup,
	# but now via Texture2DArray.
	var need_tex_array := terrain_material.get_shader_parameter("vc_tex_array") == null
	if need_tex_array:
		_ensure_texture_slots()
		_maybe_migrate_legacy_textures()
		rebuild_texture_array()
		_push_tex_scales()

	# Even if the texture array exists (existing projects), we still need to ensure
	# the palette/slot lookup textures are present; otherwise the shader may sample defaults.
	var need_palette := (
		terrain_material.get_shader_parameter("palette_colors_tex") == null
		or terrain_material.get_shader_parameter("palette_weights_tex") == null
		or terrain_material.get_shader_parameter("palette_meta_tex") == null
		or terrain_material.get_shader_parameter("palette_outline_width_tex") == null
		or terrain_material.get_shader_parameter("slot_tex_index_tex") == null
	)
	if need_palette:
		_ensure_texture_slots()
		_ensure_palette_settings()
		_rebuild_palette_uniforms()

	# PR1 grass shader expects 6 separate textures (grass_texture_1..6).
	if grass_mat.get_shader_parameter("grass_texture_1") == null:
		_ensure_texture_slots()
		_maybe_migrate_legacy_grass()
		rebuild_grass_texture_array()


func migrate_colors_to_palette() -> void:
	MarchingSquaresTerrainHelpers.migrate_colors_to_palette(self)


func _ensure_palette_weights() -> void:
	MarchingSquaresTerrainHelpers.ensure_palette_weights(self)


func _rebuild_palette_uniforms() -> void:
	MarchingSquaresTerrainHelpers.rebuild_palette_uniforms(self)


func _push_slot_blend_modes() -> void:
	# Blend modes are packed into palette_meta_tex now.
	_rebuild_palette_uniforms()


func _ensure_outline_settings() -> void:
	_ensure_palette_settings()


func _push_slot_outline_settings() -> void:
	# Outline flags/modes are packed into palette_meta_tex now.
	_rebuild_palette_uniforms()


## Applies all shader parameters and regenerates grass once
## Call this after setting is_batch_updating = true and changing properties
func force_batch_update() -> void:
	var grass_mat := grass_mesh.material as ShaderMaterial
	
	# TERRAIN MATERIAL - Core parameters
	terrain_material.set_shader_parameter("chunk_size", dimensions)
	terrain_material.set_shader_parameter("cell_size", cell_size)
	
	# TERRAIN MATERIAL - Texture2DArray + per-slot scales
	_ensure_texture_slots()
	_maybe_migrate_legacy_textures()
	rebuild_texture_array()
	_push_tex_scales()
	_ensure_palette_settings()
	_rebuild_palette_uniforms()
	
	# GRASS MATERIAL - Grass Textures (Texture2DArray)
	_maybe_migrate_legacy_grass()
	rebuild_grass_texture_array()
	
	terrain_material.set_shader_parameter("outline_width", outline_width)
	terrain_material.set_shader_parameter("global_noise_texture", global_noise_texture)
	terrain_material.set_shader_parameter("global_noise_strength", global_noise_strength)
	terrain_material.set_shader_parameter("global_noise_scale", global_noise_scale)
	_sync_global_noise_to_grass()
	_apply_blend_noise_settings()


## Syncs and saves current UI texture values to the given preset resource
## Called by marching_squares_ui.gd when saving monitoring settings changes
func save_to_preset() -> void:
	if current_texture_preset == null or current_texture_preset.resource_path.is_empty():
		return
	
	# Terrain textures
	current_texture_preset.new_textures.terrain_textures[0] = texture_1
	current_texture_preset.new_textures.terrain_textures[1] = texture_2
	current_texture_preset.new_textures.terrain_textures[2] = texture_3
	current_texture_preset.new_textures.terrain_textures[3] = texture_4
	current_texture_preset.new_textures.terrain_textures[4] = texture_5
	current_texture_preset.new_textures.terrain_textures[5] = texture_6
	current_texture_preset.new_textures.terrain_textures[6] = texture_7
	current_texture_preset.new_textures.terrain_textures[7] = texture_8
	current_texture_preset.new_textures.terrain_textures[8] = texture_9
	current_texture_preset.new_textures.terrain_textures[9] = texture_10
	current_texture_preset.new_textures.terrain_textures[10] = texture_11
	current_texture_preset.new_textures.terrain_textures[11] = texture_12
	current_texture_preset.new_textures.terrain_textures[12] = texture_13
	current_texture_preset.new_textures.terrain_textures[13] = texture_14
	current_texture_preset.new_textures.terrain_textures[14] = texture_15
	
	# Texture scales
	current_texture_preset.new_textures.texture_scales[0] = texture_scale_1
	current_texture_preset.new_textures.texture_scales[1] = texture_scale_2
	current_texture_preset.new_textures.texture_scales[2] = texture_scale_3
	current_texture_preset.new_textures.texture_scales[3] = texture_scale_4
	current_texture_preset.new_textures.texture_scales[4] = texture_scale_5
	current_texture_preset.new_textures.texture_scales[5] = texture_scale_6
	current_texture_preset.new_textures.texture_scales[6] = texture_scale_7
	current_texture_preset.new_textures.texture_scales[7] = texture_scale_8
	current_texture_preset.new_textures.texture_scales[8] = texture_scale_9
	current_texture_preset.new_textures.texture_scales[9] = texture_scale_10
	current_texture_preset.new_textures.texture_scales[10] = texture_scale_11
	current_texture_preset.new_textures.texture_scales[11] = texture_scale_12
	current_texture_preset.new_textures.texture_scales[12] = texture_scale_13
	current_texture_preset.new_textures.texture_scales[13] = texture_scale_14
	current_texture_preset.new_textures.texture_scales[14] = texture_scale_15
	
	# Grass sprites (slot-based)
	_ensure_texture_slots()
	_maybe_migrate_legacy_grass()
	if current_texture_preset.new_textures.grass_sprites.size() !=  MAX_TEXTURE_SLOTS:
		current_texture_preset.new_textures.grass_sprites.resize(MAX_TEXTURE_SLOTS)
	for i in range(MAX_TEXTURE_SLOTS):
		current_texture_preset.new_textures.grass_sprites[i] = texture_slots[i].grass_texture if texture_slots[i] != null else null
	
	# Palette system
	current_texture_preset.new_textures.grass_colors.resize(128)
	for i in range(128):
		current_texture_preset.new_textures.grass_colors[i] = palette_colors[i]
	_ensure_palette_weights()
	current_texture_preset.palette_weights = palette_weights.duplicate()
	current_texture_preset.slot_color_indices = slot_color_indices.duplicate(true)
	current_texture_preset.slot_blend_modes = slot_blend_modes.duplicate()
	_ensure_outline_settings()
	current_texture_preset.slot_has_outline = slot_has_outline.duplicate()
	current_texture_preset.slot_outline_modes = slot_outline_modes.duplicate()
	current_texture_preset.slot_outline_widths = slot_outline_widths.duplicate()
	current_texture_preset.slot_wet_enabled = slot_wet_enabled.duplicate()
	current_texture_preset.slot_wet_modes = slot_wet_modes.duplicate()
	current_texture_preset.slot_roughnesses = slot_roughnesses.duplicate()
	
	# Has grass flags (slot-based)
	_ensure_texture_slots()
	_maybe_migrate_legacy_grass()
	if current_texture_preset.new_textures.has_grass.size() !=  MAX_TEXTURE_SLOTS:
		current_texture_preset.new_textures.has_grass.resize(MAX_TEXTURE_SLOTS)
	for i in range(MAX_TEXTURE_SLOTS):
		current_texture_preset.new_textures.has_grass[i] = bool(texture_slots[i].has_grass) if texture_slots[i] != null else false

	# Slot->base texture mapping (slot-based)
	if current_texture_preset.new_textures.get("terrain_texture_indices") is Array:
		if current_texture_preset.new_textures.terrain_texture_indices.size() !=  MAX_TEXTURE_SLOTS:
			current_texture_preset.new_textures.terrain_texture_indices.resize(MAX_TEXTURE_SLOTS)
		for i in range(MAX_TEXTURE_SLOTS):
			var s = texture_slots[i]
			var idx := 0
			if i == VOID_TEXTURE_SLOT:
				idx = VOID_TEXTURE_SLOT
			elif s !=  null and s.get("terrain_texture_index") != null:
				idx = clampi(int(s.terrain_texture_index), 0, 15)
			else:
				idx = i if i < 15 else 0
			current_texture_preset.new_textures.terrain_texture_indices[i] = idx

	ResourceSaver.save(current_texture_preset)


func load_from_preset(preset: MarchingSquaresTexturePreset) -> void:
	if preset == null:
		return
	
	var has_real_palette_data := false
	for arr in preset.slot_color_indices:
		if arr.size() > 0:
			has_real_palette_data = true
			break

	if (preset.slot_color_indices.size() == 15 or preset.slot_color_indices.size() == MAX_TEXTURE_SLOTS) and has_real_palette_data:
		slot_color_indices = preset.slot_color_indices.duplicate(true)
		if preset.new_textures.grass_colors.size() == 128:
			palette_colors = preset.new_textures.grass_colors.duplicate()
		if preset.palette_weights.size() == 128:
			palette_weights = preset.palette_weights.duplicate()
		else:
			palette_weights.resize(128)
			for i in range(128):
				palette_weights[i] = 100.0
	else:
		# Old preset — reset everything to clean defaults
		slot_color_indices = [[0], [1], [2], [3], [4], [5], [], [], [], [], [], [], [], [], []]
		palette_colors.resize(128)
		palette_weights.resize(128)
		for i in range(128):
			palette_colors[i] = Color("647851ff")
			palette_weights[i] = 100.0

	if preset.slot_blend_modes.size() == 15 or preset.slot_blend_modes.size() == MAX_TEXTURE_SLOTS:
		slot_blend_modes = preset.slot_blend_modes.duplicate()
	else:
		slot_blend_modes = [3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3]

	if preset.slot_has_outline.size() == 15 or preset.slot_has_outline.size() == MAX_TEXTURE_SLOTS:
		slot_has_outline = preset.slot_has_outline.duplicate()
	else:
		slot_has_outline = [false, false, false, false, false, false, false, false, false, false, false, false, false, false, false]

	if preset.slot_outline_modes.size() == 15 or preset.slot_outline_modes.size() == MAX_TEXTURE_SLOTS:
		slot_outline_modes = preset.slot_outline_modes.duplicate()
	else:
		slot_outline_modes = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

	if preset.get("slot_outline_widths") is Array and (preset.slot_outline_widths.size() == 15 or preset.slot_outline_widths.size() == MAX_TEXTURE_SLOTS):
		slot_outline_widths = preset.slot_outline_widths.duplicate()
	else:
		slot_outline_widths = [6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0]

	if preset.get("slot_wet_enabled") is Array and (preset.slot_wet_enabled.size() == 15 or preset.slot_wet_enabled.size() == MAX_TEXTURE_SLOTS):
		slot_wet_enabled = preset.slot_wet_enabled.duplicate()
	else:
		slot_wet_enabled = [false, false, false, false, false, false, false, false, false, false, false, false, false, false, false]

	if preset.get("slot_wet_modes") is Array and (preset.slot_wet_modes.size() == 15 or preset.slot_wet_modes.size() == MAX_TEXTURE_SLOTS):
		slot_wet_modes = preset.slot_wet_modes.duplicate()
	else:
		slot_wet_modes = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

	if preset.get("slot_roughnesses") is Array and (preset.slot_roughnesses.size() == 15 or preset.slot_roughnesses.size() == MAX_TEXTURE_SLOTS):
		slot_roughnesses = preset.slot_roughnesses.duplicate()
	else:
		slot_roughnesses = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]

	_ensure_outline_settings()
	terrain_material.set_shader_parameter("outline_width", outline_width)

	_rebuild_palette_uniforms()
	_push_slot_blend_modes()
	_push_slot_outline_settings()

	# Apply textures + grass from the preset.
	is_batch_updating = true
	_ensure_texture_slots()
	_maybe_migrate_legacy_textures()
	_maybe_migrate_legacy_grass()

	# Terrain textures (first 15)
	if preset.new_textures !=  null and preset.new_textures.terrain_textures.size() >= 15:
		texture_1 = preset.new_textures.terrain_textures[0]
		texture_2 = preset.new_textures.terrain_textures[1]
		texture_3 = preset.new_textures.terrain_textures[2]
		texture_4 = preset.new_textures.terrain_textures[3]
		texture_5 = preset.new_textures.terrain_textures[4]
		texture_6 = preset.new_textures.terrain_textures[5]
		texture_7 = preset.new_textures.terrain_textures[6]
		texture_8 = preset.new_textures.terrain_textures[7]
		texture_9 = preset.new_textures.terrain_textures[8]
		texture_10 = preset.new_textures.terrain_textures[9]
		texture_11 = preset.new_textures.terrain_textures[10]
		texture_12 = preset.new_textures.terrain_textures[11]
		texture_13 = preset.new_textures.terrain_textures[12]
		texture_14 = preset.new_textures.terrain_textures[13]
		texture_15 = preset.new_textures.terrain_textures[14]

		for i in range(15):
			if texture_slots[i] == null:
				texture_slots[i] = _TEXTURE_SLOT_SCRIPT.new()
			texture_slots[i].texture = preset.new_textures.terrain_textures[i]

	# Texture scales (first 15)
	if preset.new_textures !=  null and preset.new_textures.texture_scales.size() >= 15:
		texture_scale_1 = preset.new_textures.texture_scales[0]
		texture_scale_2 = preset.new_textures.texture_scales[1]
		texture_scale_3 = preset.new_textures.texture_scales[2]
		texture_scale_4 = preset.new_textures.texture_scales[3]
		texture_scale_5 = preset.new_textures.texture_scales[4]
		texture_scale_6 = preset.new_textures.texture_scales[5]
		texture_scale_7 = preset.new_textures.texture_scales[6]
		texture_scale_8 = preset.new_textures.texture_scales[7]
		texture_scale_9 = preset.new_textures.texture_scales[8]
		texture_scale_10 = preset.new_textures.texture_scales[9]
		texture_scale_11 = preset.new_textures.texture_scales[10]
		texture_scale_12 = preset.new_textures.texture_scales[11]
		texture_scale_13 = preset.new_textures.texture_scales[12]
		texture_scale_14 = preset.new_textures.texture_scales[13]
		texture_scale_15 = preset.new_textures.texture_scales[14]

		for i in range(15):
			if texture_slots[i] == null:
				texture_slots[i] = _TEXTURE_SLOT_SCRIPT.new()
			texture_slots[i].scale = float(preset.new_textures.texture_scales[i])

	# Grass sprites + has-grass flags (slot-based 0..255)
	# IMPORTANT: if an older preset does not contain these arrays, do NOT wipe existing grass.
	var p_sprites: Array = []
	var p_has: Array = []
	if preset.new_textures !=  null and preset.new_textures.get("grass_sprites") is Array:
		p_sprites = preset.new_textures.grass_sprites
	if preset.new_textures !=  null and preset.new_textures.get("has_grass") is Array:
		p_has = preset.new_textures.has_grass

	var has_sprite_data := p_sprites.size() > 0
	var has_flag_data := p_has.size() > 0
	for i in range(MAX_TEXTURE_SLOTS):
		if texture_slots[i] == null:
			texture_slots[i] = _TEXTURE_SLOT_SCRIPT.new()
		if has_sprite_data and i < p_sprites.size():
			texture_slots[i].grass_texture = p_sprites[i]
		if has_flag_data and i < p_has.size():
			texture_slots[i].has_grass = bool(p_has[i])
		elif not has_flag_data:
			# Default only when the preset provides no flags at all.
			texture_slots[i].has_grass = (i < 6)

	# Slot->base texture mapping (0..15 per slot)
	var p_map: Array = []
	if preset.new_textures !=  null and preset.new_textures.get("terrain_texture_indices") is Array:
		p_map = preset.new_textures.terrain_texture_indices
	for i in range(MAX_TEXTURE_SLOTS):
		if texture_slots[i] == null:
			texture_slots[i] = _TEXTURE_SLOT_SCRIPT.new()
		var idx := i if i < 15 else 0
		if i == VOID_TEXTURE_SLOT:
			idx = VOID_TEXTURE_SLOT
		if i < p_map.size() and p_map[i] !=  null:
			idx = clampi(int(p_map[i]), 0, 15)
		texture_slots[i].terrain_texture_index = idx

	# Keep legacy inspector fields in sync (first 6)
	if p_sprites.size() > 0:
		grass_sprite_tex_1 = p_sprites[0] if p_sprites.size() > 0 else grass_sprite_tex_1
		grass_sprite_tex_2 = p_sprites[1] if p_sprites.size() > 1 else grass_sprite_tex_2
		grass_sprite_tex_3 = p_sprites[2] if p_sprites.size() > 2 else grass_sprite_tex_3
		grass_sprite_tex_4 = p_sprites[3] if p_sprites.size() > 3 else grass_sprite_tex_4
		grass_sprite_tex_5 = p_sprites[4] if p_sprites.size() > 4 else grass_sprite_tex_5
		grass_sprite_tex_6 = p_sprites[5] if p_sprites.size() > 5 else grass_sprite_tex_6
	if p_has.size() > 0:
		tex1_has_grass = bool(p_has[0]) if p_has.size() > 0 else tex1_has_grass
		tex2_has_grass = bool(p_has[1]) if p_has.size() > 1 else tex2_has_grass
		tex3_has_grass = bool(p_has[2]) if p_has.size() > 2 else tex3_has_grass
		tex4_has_grass = bool(p_has[3]) if p_has.size() > 3 else tex4_has_grass
		tex5_has_grass = bool(p_has[4]) if p_has.size() > 4 else tex5_has_grass
		tex6_has_grass = bool(p_has[5]) if p_has.size() > 5 else tex6_has_grass

	is_batch_updating = false

	# Applying a preset can be frequent (scrolling presets). Avoid heavy work unless needed.
	# Terrain textures/palette always need a refresh.
	rebuild_texture_array()
	_push_tex_scales()
	_ensure_palette_settings()
	_rebuild_palette_uniforms()

	# Only rebuild the 256-layer grass Texture2DArray when the preset actually provides sprite data.
	if has_sprite_data:
		rebuild_grass_texture_array()

	_request_grass_regen()

#endregion
