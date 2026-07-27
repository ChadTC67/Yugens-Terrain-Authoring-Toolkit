@tool
extends MeshInstance3D
class_name MarchingSquaresTerrainChunk

# Explicit preloads avoid tool-script class resolution issues.
const MSTVertexColorHelper := preload("res://addons/MarchingSquaresTerrain/algorithm/terrain/marching_squares_terrain_vertex_color_helper.gd")
const MSTTerrainCell := preload("res://addons/MarchingSquaresTerrain/algorithm/terrain/marching_squares_terrain_cell.gd")
const MSTPrefabCell := preload("res://addons/MarchingSquaresTerrain/algorithm/terrain/prefab/marching_squares_prefab_cell.gd")
const MSTDataHandler := preload("res://addons/MarchingSquaresTerrain/resources/mst_data_handler.gd")
const MAX_WALL_PAINT_STAMPS := 64

enum Mode {CUBIC, POLYHEDRON, ROUNDED_POLYHEDRON, SEMI_ROUND, SPHERICAL}
enum GrassMode {GRASS, GRASSLESS}

const MERGE_MODE = {
	Mode.CUBIC: 0.6,
	Mode.POLYHEDRON: 1.3,
	Mode.ROUNDED_POLYHEDRON: 2.1,
	Mode.SEMI_ROUND: 5.0,
	Mode.SPHERICAL: 20.0,
}

# These two need to be normal export vars or else godot's internal logic crashes the plugin
@export var terrain_system : MarchingSquaresTerrain
@export var chunk_coords : Vector2i = Vector2i.ZERO

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var merge_mode : Mode = Mode.POLYHEDRON: # The max height distance between points before a wall is created between them
	set(mode):
		merge_mode = mode
		if is_inside_tree() and grass_planter and grass_planter.multimesh:
			var grass_mat : ShaderMaterial = grass_planter.multimesh.mesh.material as ShaderMaterial
			if mode == Mode.SEMI_ROUND or mode == Mode.SPHERICAL:
				grass_mat.set_shader_parameter("is_merge_round", true)
			else:
				grass_mat.set_shader_parameter("is_merge_round", false)
			merge_threshold = MERGE_MODE[mode]
			regenerate_all_cells(true)
@export_storage var height_map : Array # Stores the heights from the heightmap
#region cell_geometry storage
# Color maps are now ephemeral and created at runtime
# Persisted via MSTDataHandler
var color_map_0 : PackedColorArray # Stores the colors from vertex_color_0 (ground)
var color_map_1 : PackedColorArray # Stores the colors from vertex_color_1 (ground)
var wall_color_map_0 : PackedColorArray # Stores the colors for wall vertices (slot encoding channel 0)
var wall_color_map_1 : PackedColorArray # Stores the colors for wall vertices (slot encoding channel 1)
var grass_mask_map : PackedColorArray # Stores if a cell should have grass or not
@export_storage var navmesh_permission : PackedByteArray = PackedByteArray()
#endregion

var merge_threshold : float = MERGE_MODE[Mode.POLYHEDRON]

var grass_planter : MarchingSquaresGrassPlanter
var wall_paint_stamp_positions : PackedVector3Array = PackedVector3Array()
var wall_paint_stamp_normals : PackedVector3Array = PackedVector3Array()
var wall_paint_stamp_radii : PackedFloat32Array = PackedFloat32Array()
var wall_paint_stamp_texture_indices : PackedInt32Array = PackedInt32Array()

var global_position_cached : Vector3 = Vector3.ZERO

var cell_generation_mutex : Mutex = Mutex.new()

var bake_material : ShaderMaterial = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/mst_terrain_baked.tres")

#region chunk variables
# Size of the 2 dimensional cell array (xz value) and y scale (y value)
var dimensions : Vector3i:
	get:
		return terrain_system.dimensions
# Unit XZ size of a single cell
var cell_size : Vector2:
	get:
		return terrain_system.cell_size
#endregion

var st : SurfaceTool # The surfacetool used to construct the current terrain

var cell_geometry : Dictionary = {} # Stores all generated tiles so that their geometry can quickly be reused

var needs_update : Array[Array] # Stores which tiles need to be updated because one of their corners' heights was changed.
var _skip_save_on_exit : bool = false # Set to true when chunk is removed temporarily (undo/redo)
var _data_dirty : bool = false # Set to true when source data changes, triggers save in MSTDataHandler

#region temporary storage vars
# Temporary storage for ephemeral resources during scene save
var _temp_mesh : ArrayMesh
var _temp_grass_multimesh : MultiMesh
var _temp_collision_shapes : Array[ConcavePolygonShape3D] = []  # COMMENT: Old scenes may have duplicates
var _temp_height_map : Array  # Source data - saved to external storage, not scene file
#endregion

var _grass_regen_queued: bool = false
var _mesh_regen_queued: bool = false
var _suppress_grass_mode_side_effects: bool = false

#region blend option vars
# Terrain blend options to allow for smooth color and height blend influence at transitions and at different heights
var lower_thresh : float = 0.3 # Sharp bands: < 0.3 = lower color
var upper_thresh : float = 0.7 #, > 0.7 = upper color, middle = blend
var blend_zone := upper_thresh - lower_thresh
#endregion


@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_mode : GrassMode = GrassMode.GRASS:
	set(value):
		grass_mode = value
		if _suppress_grass_mode_side_effects:
			return
		_temp_grass_multimesh = null
		if is_inside_tree():
			_apply_grass_mode()
			if grass_planter:
				_queue_grass_regen()
		mark_dirty()


func _apply_shadow_visibility_settings() -> void:
	cast_shadow = SHADOW_CASTING_SETTING_ON
	if terrain_system == null:
		return
	var world_w := float(max(dimensions.x - 1, 1)) * cell_size.x
	var world_d := float(max(dimensions.z - 1, 1)) * cell_size.y
	var world_h := float(max(dimensions.y, 1))
	extra_cull_margin = max(max(world_w, world_d), world_h)


func _clear_grass_planter() -> void:
	_temp_grass_multimesh = null
	if grass_planter:
		if grass_planter.multimesh:
			grass_planter.multimesh = null
		grass_planter.owner = null
		grass_planter.free()
	grass_planter = null


func _ensure_grass_planter() -> bool:
	grass_planter = get_node_or_null("GrassPlanter")
	if not grass_planter:
		grass_planter = MarchingSquaresGrassPlanter.new()
		if not color_map_0 or not color_map_1:
			generate_color_maps()
		if not grass_mask_map:
			generate_grass_mask_map()
		add_child(grass_planter)
	grass_planter.name = "GrassPlanter"
	grass_planter._chunk = self
	grass_planter.terrain_system = terrain_system
	grass_planter.setup(self)
	EngineWrapper.instance.set_owner_recursive(grass_planter)

	var grass_count_changed := false
	if _temp_grass_multimesh:
		grass_planter.multimesh = _temp_grass_multimesh
	if grass_planter.multimesh == null:
		grass_planter.setup(self)
		grass_count_changed = true
	grass_count_changed = grass_planter.ensure_multimesh_count() or grass_count_changed
	if not grass_planter.multimesh:
		grass_planter.setup(self)
		grass_count_changed = true
	if grass_planter.multimesh:
		grass_planter.multimesh.mesh = terrain_system.grass_mesh
	return grass_count_changed


func _apply_grass_mode() -> void:
	if grass_mode == GrassMode.GRASSLESS:
		_clear_grass_planter()
	else:
		_ensure_grass_planter()

# Called by TerrainSystem parent
func initialize_terrain(should_regenerate_mesh: bool =  true):
	_apply_shadow_visibility_settings()
	needs_update = []
	# Initally all cells will need to be updated to show the newly loaded height
	for z in range(dimensions.z - 1):
		needs_update.append([])
		for x in range(dimensions.x - 1):
			needs_update[z].append(true)

	var has_baked_grass_multimesh := _temp_grass_multimesh != null and grass_mode == GrassMode.GRASS
	var grass_count_changed := false
	if grass_mode == GrassMode.GRASS:
		grass_count_changed = _ensure_grass_planter()
	else:
		_clear_grass_planter()

	# Generate maps if not loaded from external storage (works for both editor and runtime)
	# Validate height_map shape — serialized scenes may contain empty arrays or malformed rows.
	var need_hm := true
	if height_map and height_map is Array and height_map.size() == dimensions.z:
		need_hm = false
		for row in height_map:
			if not (row is Array) or row.size() !=  dimensions.x:
				need_hm = true
				break
	if need_hm:
		generate_height_map()
	# Validate color maps sizes
	if not (color_map_0 is PackedColorArray) or color_map_0.size() !=  dimensions.z * dimensions.x or not (color_map_1 is PackedColorArray) or color_map_1.size() != dimensions.z * dimensions.x:
		generate_color_maps()
	if not (wall_color_map_0 is PackedColorArray) or wall_color_map_0.size() !=  dimensions.z * dimensions.x or not (wall_color_map_1 is PackedColorArray) or wall_color_map_1.size() != dimensions.z * dimensions.x:
		generate_wall_color_maps()
	if not (grass_mask_map is PackedColorArray) or grass_mask_map.size() !=  dimensions.z * dimensions.x:
		generate_grass_mask_map()

	if not mesh and should_regenerate_mesh:
		regenerate_mesh(true)
	elif mesh:
		if terrain_system:
			_apply_chunk_surface_material()
		if not _temp_collision_shapes.is_empty():
			# Legacy scenes stored Exact/triplanar collision faces here. Discard
			# those faces and build the current reduced proxy from height data;
			# the authored mesh itself does not need to be regenerated.
			_temp_collision_shapes.clear()
			rebuild_collision()
		else:
			for child in get_children():
				if child is StaticBody3D:
					child.free()
			rebuild_collision()

	# Respect deferred initialization: chunk creation adds the node first, then paints/seams it,
	# and only after that should the first full mesh/grass build happen.
	var can_generate_grass_now := should_regenerate_mesh or mesh != null or has_baked_grass_multimesh
	if grass_mode == GrassMode.GRASS and grass_planter and can_generate_grass_now and (not has_baked_grass_multimesh or grass_count_changed):
		if mesh != null and not has_baked_grass_multimesh:
			_queue_grass_regen()
		else:
			grass_planter.regenerate_all_cells()

	var has_texture_array_source := (
		terrain_system.get("texture_library") != null
		or str(terrain_system.get("baked_albedo_array_path")) != ""
	)
	if not EngineWrapper.instance.is_editor() and terrain_system.enable_runtime_texture_baking and not has_texture_array_source:
		var baker := MarchingSquaresGeometryBaker.new()
		baker.polygon_texture_resolution = terrain_system.polygon_texture_resolution
		baker.finished.connect(func(mesh_: Mesh, _original: MeshInstance3D, img: Image):
			mesh = mesh_
			var mat : Material
			if terrain_system.bake_material_override:
				mat = terrain_system.bake_material_override.duplicate()
			else:
				mat = bake_material.duplicate()

			if mat is StandardMaterial3D:
				mat.albedo_texture = ImageTexture.create_from_image(img)
			elif mat is ShaderMaterial:
				mat.set_shader_parameter("texture_albedo", ImageTexture.create_from_image(img))
			if mesh and mesh.get_surface_count() > 0:
				mesh.surface_set_material(0, mat)
		, CONNECT_ONE_SHOT)
		baker.bake_geometry_texture(self, get_tree())


func _save_external_data_before_scene_strip() -> bool:
	if not terrain_system or _skip_save_on_exit:
		return false
	var dir_path := terrain_system.data_directory
	if dir_path == null or dir_path == "":
		return false
	var needs_save := _data_dirty
	if not needs_save:
		needs_save = not MSTDataHandler.metadata_exists(dir_path, chunk_coords)
	if not needs_save:
		return true
	if not MSTDataHandler.ensure_directory_exists(dir_path):
		return false
	if not MSTDataHandler.save_chunk_resources(terrain_system, self):
		return false
	_data_dirty = false
	terrain_system._storage_initialized = true
	return MSTDataHandler.metadata_exists(dir_path, chunk_coords)

func _notification(what: int) -> void:
	if not EngineWrapper.instance.is_editor():
		return

	match what:
		NOTIFICATION_EDITOR_PRE_SAVE:
			var can_strip_scene_data := _save_external_data_before_scene_strip()
			if not can_strip_scene_data:
				push_error("MST: Refusing to strip chunk source data because external save failed for " + str(chunk_coords))
				return
			# Store height_map and clear - source data saved to external storage, not scene
			_skip_save_on_exit = _skip_save_on_exit # Surpress warning
			_temp_height_map = height_map
			height_map = []

			# Clear in-memory cache of generated cell geometry to avoid serializing Vector2i keys
			cell_geometry.clear()

			# Store mesh and clear to prevent serialization
			_temp_mesh = mesh
			mesh = null

			# Store grass multimesh and clear
			if grass_planter and grass_planter.multimesh:
				_temp_grass_multimesh = grass_planter.multimesh
				grass_planter.multimesh = null

			# Handle ALL collision bodies (old scenes may have multiple duplicates!)
			_temp_collision_shapes.clear()
			var bodies_to_free : Array[StaticBody3D] = []
			for child in get_children():
				if child is StaticBody3D:
					for shape_child in child.get_children():
						if shape_child is CollisionShape3D and shape_child.shape is ConcavePolygonShape3D:
							_temp_collision_shapes.append(shape_child.shape)
							shape_child.shape = null  # Clear to prevent sub_resource save
						shape_child.owner = null
					child.owner = null
					bodies_to_free.append(child)
			# Free all bodies (after iteration to avoid modifying while iterating)
			for body in bodies_to_free:
				body.name += "_"
				body.queue_free()

		NOTIFICATION_EDITOR_POST_SAVE:
			# Restore height_map
			if _temp_height_map:
				height_map = _temp_height_map
				_temp_height_map = []

			# Restore mesh
			if _temp_mesh:
				mesh = _temp_mesh
				_temp_mesh = null

			# Restore grass multimesh
			if _temp_grass_multimesh and grass_planter:
				grass_planter.multimesh = _temp_grass_multimesh
				_temp_grass_multimesh = null

			# Recreate ONE collision body (only need one, even if old scene had duplicates)
			if not _temp_collision_shapes.is_empty():
				_temp_collision_shapes.clear()
				rebuild_collision.call_deferred()

		NOTIFICATION_PREDELETE:
			# Safety cleanup - clear owner on ALL collision nodes
			for child in get_children():
				if child is StaticBody3D:
					child.owner = null
					for shape_child in child.get_children():
						if shape_child is CollisionShape3D:
							shape_child.owner = null


func _enter_tree() -> void:
	if not terrain_system:
		return
	# Defensive: clear any serialized runtime caches that can cause variant lookup errors.
	if cell_geometry and cell_geometry.size() > 0:
		# Ensure keys are Vector2i; if not, dump and clear to avoid variant errors on load.
		var keys_valid := true
		for k in cell_geometry.keys():
			if not (k is Vector2i):
				keys_valid = false
				break
		if not keys_valid:
			cell_geometry.clear()
			push_warning("[MST] Cleared unexpected serialized cell_geometry: please re-save the scene to remove runtime caches.")

	if get_parent() !=  terrain_system:
		push_error("Chunk must remain within its parent!")
		return
	var terrain_chunks = terrain_system.get("chunks")
	if terrain_chunks is Dictionary:
		terrain_chunks[chunk_coords] = self


func _exit_tree() -> void:
	# Clear temp references
	_temp_height_map = []
	_temp_mesh = null
	_temp_grass_multimesh = null
	_temp_collision_shapes.clear()

	# Clear owner on ALL collision nodes to prevent serialization edge cases
	if EngineWrapper.instance.is_editor():
		for child in get_children():
			if child is StaticBody3D:
				child.owner = null
				for shape_child in child.get_children():
					if shape_child is CollisionShape3D:
						shape_child.owner = null

	# Only erase if terrain_system still has THIS chunk at chunk_coords
	if terrain_system:
		var terrain_chunks = terrain_system.get("chunks")
		if terrain_chunks is Dictionary and terrain_chunks.get(chunk_coords) == self:
			terrain_chunks.erase(chunk_coords)


func regenerate_mesh(use_threads: bool =  false):
	_apply_shadow_visibility_settings()
	var previous_mesh := mesh
	st = SurfaceTool.new()
	if mesh and mesh.get_surface_count() > 0:
		st.create_from(mesh, 0)
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	st.set_custom_format(1, SurfaceTool.CUSTOM_RGBA_FLOAT)
	st.set_custom_format(2, SurfaceTool.CUSTOM_RGBA_FLOAT)

	var start_time : int = Time.get_ticks_msec()

	generate_terrain_cells(use_threads)

	st.generate_normals()
	st.index()
	# Create a new mesh out of floor, and add the wall surface to it
	var committed_mesh := st.commit()
	var has_valid_surface := committed_mesh != null and committed_mesh.get_surface_count() > 0
	if not has_valid_surface:
		if previous_mesh != null and previous_mesh.get_surface_count() > 0:
			mesh = previous_mesh
			push_warning("[MST] Skipped replacing chunk mesh with an empty surface set. The previous mesh was preserved.")
		else:
			mesh = null
	else:
		mesh = committed_mesh

	if mesh and terrain_system and mesh.get_surface_count() > 0:
		_apply_chunk_surface_material()

	for child in get_children():
		if child is StaticBody3D:
			child.free()
	if mesh != null and mesh.get_surface_count() > 0 and terrain_system != null:
		terrain_system._queue_chunk_collision_rebuild(chunk_coords)

	var elapsed_time : int = Time.get_ticks_msec() - start_time
	print_verbose("Generated terrain in "+str(elapsed_time)+"ms")


func _reset_cell_geometry(cell_coords: Vector2i) -> void:
	cell_geometry[cell_coords] = {
		"verts": PackedVector3Array(),
		"uvs": PackedVector2Array(),
		"uv2s": PackedVector2Array(),
		"color_0s": PackedColorArray(),
		"color_1s": PackedColorArray(),
		"custom_1_values": PackedColorArray(),
		"mat_blend": PackedColorArray(),
		"is_floor": [],
	}


func _create_cell_for_geometry(cell_coords: Vector2i):
	var x := cell_coords.x
	var z := cell_coords.y
	var h00 := 0.0
	var h01 := 0.0
	var h10 := 0.0
	var h11 := 0.0
	if height_map is Array and height_map.size() > z and height_map[z] is Array and height_map[z].size() > x:
		h00 = float(height_map[z][x])
	if height_map is Array and height_map.size() > z and height_map[z] is Array and height_map[z].size() > x + 1:
		h01 = float(height_map[z][x + 1])
	else:
		h01 = h00
	if height_map is Array and height_map.size() > z + 1 and height_map[z + 1] is Array and height_map[z + 1].size() > x:
		h10 = float(height_map[z + 1][x])
	else:
		h10 = h00
	if height_map is Array and height_map.size() > z + 1 and height_map[z + 1] is Array and height_map[z + 1].size() > x + 1:
		h11 = float(height_map[z + 1][x + 1])
	else:
		h11 = h00

	var color_helper := MSTVertexColorHelper.new()
	var cell
	if terrain_system != null and terrain_system.prefab_set != null:
		cell = MSTPrefabCell.new(self, color_helper, h00, h01, h10, h11, merge_threshold)
	else:
		cell = MSTTerrainCell.new(self, color_helper, h00, h01, h10, h11, merge_threshold)
	color_helper.chunk = self
	color_helper.cell = cell
	return cell


func regenerate_cell_geometry(cell_coords: Vector2i) -> void:
	if cell_coords.x < 0 or cell_coords.y < 0 or cell_coords.x >= dimensions.x - 1 or cell_coords.y >= dimensions.z - 1:
		return
	if cell_geometry.is_empty():
		cell_geometry = {}
	global_position_cached = global_position if is_inside_tree() else position
	_reset_cell_geometry(cell_coords)
	var cell = _create_cell_for_geometry(cell_coords)
	var previous_st := st
	st = null
	cell.generate_geometry(cell_coords)
	st = previous_st
	if needs_update.size() > cell_coords.y and needs_update[cell_coords.y].size() > cell_coords.x:
		needs_update[cell_coords.y][cell_coords.x] = false


func generate_terrain_cells(use_threads: bool):
	if not cell_geometry:
		cell_geometry = {}
	# Serialized chunks can contain an update grid from an older dimension set.
	# Rebuild it before indexing so generation always matches the current cell grid.
	var cell_rows := dimensions.z - 1
	var cell_columns := dimensions.x - 1
	var needs_update_shape_valid := needs_update.size() == cell_rows
	if needs_update_shape_valid:
		for row in needs_update:
			if not (row is Array) or row.size() != cell_columns:
				needs_update_shape_valid = false
				break
	if not needs_update_shape_valid:
		needs_update = []
		for z in range(cell_rows):
			needs_update.append([])
			for x in range(cell_columns):
				needs_update[z].append(true)

	global_position_cached = global_position if is_inside_tree() else position
	var thread_pool := MarchingSquaresThreadPool.new(max(1, OS.get_processor_count()))

	for z in range(dimensions.z - 1):
		for x in range(dimensions.x - 1):
			var cell_coords = Vector2i(x, z)
			var work_load : Callable
			# If geometry did not change, copy already generated geometry and skip this cell
			if not needs_update[z][x]:
				# If cached geometry is missing or malformed, fallback to regenerating this cell.
				if not cell_geometry.has(cell_coords):
					needs_update[z][x] = true
					# fall through to generation

					# continue to next iteration so generation handles it
					# (avoid executing the cached-copy branch)
					# Note: do NOT call continue here because we want the generation code below to run in this iteration.
					pass
				else:
					work_load =  func():
						cell_generation_mutex.lock()
						# Safely fetch cached arrays; if anything is missing, unlock and bail so generation occurs.
						if not cell_geometry.has(cell_coords):
							cell_generation_mutex.unlock()
							return
						var entry = cell_geometry[cell_coords]
						if not entry.has("verts"):
							cell_generation_mutex.unlock()
							return
						var verts = entry["verts"]
						var uvs = entry["uvs"]
						var uv2s = entry["uv2s"]
						var color_0s = entry["color_0s"]
						var color_1s = entry["color_1s"]
						var custom_1_values = entry["custom_1_values"]
						var mat_blend = entry["mat_blend"]
						var is_floor = entry["is_floor"]
						for i in range(len(verts)):
							st.set_smooth_group(0 if is_floor[i] == true else -1)
							st.set_uv(uvs[i])
							st.set_uv2(uv2s[i])
							st.set_color(color_0s[i])
							st.set_custom(0, color_1s[i])
							st.set_custom(1, custom_1_values[i])
							st.set_custom(2, mat_blend[i])
							st.add_vertex(verts[i])
						cell_generation_mutex.unlock()
					if use_threads:
						thread_pool.enqueue(work_load)
					else:
						work_load.call()
					continue

			# Cell is now being updated
			needs_update[z][x] = false

			# If geometry did change or none exists yet,
			# Create an entry for this cell (will also override any existing one)
			_reset_cell_geometry(cell_coords)
			var cell = _create_cell_for_geometry(cell_coords)

			work_load =  func():
				cell.generate_geometry(cell_coords)
				if not use_threads and EngineWrapper.instance.is_editor() and grass_planter and grass_planter.terrain_system:
					grass_planter.generate_grass_on_cell(cell_coords)
			if use_threads:
				thread_pool.enqueue(work_load)
			else:
				work_load.call()

	if use_threads:
		thread_pool.start()
		thread_pool.wait()


func add_polygons(
	cell_coords : Vector2i,
	pts : PackedVector3Array,
	uvs : PackedVector2Array,
	uv2s : PackedVector2Array,
	color_0s : PackedColorArray,
	color_1s : PackedColorArray,
	custom_1_values : PackedColorArray,
	mat_blends : PackedColorArray,
	floors : PackedByteArray,
	):
		assert(pts.size() % 3 == 0)
		assert(pts.size() == uvs.size())
		assert(pts.size() == uv2s.size())
		assert(pts.size() == color_0s.size())
		assert(pts.size() == color_1s.size())
		assert(pts.size() == custom_1_values.size())
		assert(pts.size() == mat_blends.size())
		assert(pts.size() == floors.size())

		cell_generation_mutex.lock()
		var floor_mode : bool = true
		if st:
			st.set_smooth_group(0)
		for i in range(pts.size()):
			if floor_mode and not floors[i]:
				floor_mode = false
				if st:
					st.set_smooth_group(-1)
			elif not floor_mode and floors[i]:
				floor_mode = true
				if st:
					st.set_smooth_group(0)
			_add_point(cell_coords, pts[i], uvs[i], uv2s[i], color_0s[i], color_1s[i], custom_1_values[i], mat_blends[i], floors[i])
		cell_generation_mutex.unlock()


# Adds a point. Coordinates are relative to the top-left corner (not mesh origin relative)
# UV.x is closeness to the bottom of an edge. UV.Y is closeness to the edge of a cliff
func _add_point(cell_coords: Vector2i, vert: Vector3, uv: Vector2, uv2: Vector2, color_0: Color, color_1: Color, custom_1_value: Color, mat_blend: Color, is_floor: bool):
	if st:
		st.set_color(color_0)
		st.set_custom(0, color_1)
		st.set_custom(1, custom_1_value)
		st.set_custom(2, mat_blend)
		st.set_uv(uv)
		st.set_uv2(uv2)
		st.add_vertex(vert)

	cell_geometry[cell_coords]["verts"].append(vert)
	cell_geometry[cell_coords]["uvs"].append(uv)
	cell_geometry[cell_coords]["uv2s"].append(uv2)
	cell_geometry[cell_coords]["color_0s"].append(color_0)
	cell_geometry[cell_coords]["color_1s"].append(color_1)
	cell_geometry[cell_coords]["custom_1_values"].append(custom_1_value)
	cell_geometry[cell_coords]["mat_blend"].append(mat_blend)
	cell_geometry[cell_coords]["is_floor"].append(is_floor)

#region cell_geometry generators (on being empty)

func generate_height_map(base_height: float = 0.0):
	height_map = []
	height_map.resize(dimensions.z)
	for z in range(dimensions.z):
		height_map[z] = []
		height_map[z].resize(dimensions.x)
		for x in range(dimensions.x):
			height_map[z][x] = base_height

	var noise := terrain_system.noise_hmap
	if noise:
		for z in range(dimensions.z):
			for x in range(dimensions.x):
				var noise_x = (chunk_coords.x * (dimensions.x - 1)) + x
				var noise_z = (chunk_coords.y * (dimensions.z -1)) + z
				var noise_sample = noise.get_noise_2d(noise_x, noise_z)
				height_map[z][x] = base_height + (noise_sample * dimensions.y)


func generate_color_maps():
	color_map_0 = PackedColorArray()
	color_map_1 = PackedColorArray()
	color_map_0.resize(dimensions.z * dimensions.x)
	color_map_1.resize(dimensions.z * dimensions.x)
	for z in range(dimensions.z):
		for x in range(dimensions.x):
			color_map_0[z*dimensions.x + x] = Color(0,0,0,0)
			color_map_1[z*dimensions.x + x] = Color(0,0,0,0)


func generate_wall_color_maps():
	wall_color_map_0 = PackedColorArray()
	wall_color_map_1 = PackedColorArray()
	wall_color_map_0.resize(dimensions.z * dimensions.x)
	wall_color_map_1.resize(dimensions.z * dimensions.x)
	var default_idx := 0
	if terrain_system !=  null:
		default_idx = int(terrain_system.default_wall_texture)
	var cols := MSTVertexColorHelper.texture_index_to_colors(default_idx)
	var c0 : Color = cols[0]
	var c1 : Color = cols[1]
	for z in range(dimensions.z):
		for x in range(dimensions.x):
			wall_color_map_0[z*dimensions.x + x] = c0
			wall_color_map_1[z*dimensions.x + x] = c1


func apply_default_wall_texture(old_idx: int, new_idx: int) -> bool:
	if not wall_color_map_0 or not wall_color_map_1:
		return false
	if old_idx == new_idx:
		return false
	var cols := MSTVertexColorHelper.texture_index_to_colors(new_idx)
	var c0 : Color = cols[0]
	var c1 : Color = cols[1]
	var changed := false
	for i in range(wall_color_map_0.size()):
		var idx := MSTVertexColorHelper.get_texture_index_from_colors(wall_color_map_0[i], wall_color_map_1[i])
		if idx == old_idx:
			wall_color_map_0[i] = c0
			wall_color_map_1[i] = c1
			changed = true
	if changed:
		mark_dirty()
	return changed


func apply_default_wall_to_unpainted(new_idx: int) -> bool:
	# "Unpainted" is defined as wall map still matching ground map.
	if not wall_color_map_0 or not wall_color_map_1:
		return false
	if not color_map_0 or not color_map_1:
		return false
	var cols := MSTVertexColorHelper.texture_index_to_colors(new_idx)
	var c0 : Color = cols[0]
	var c1 : Color = cols[1]
	var changed := false
	var count := min(wall_color_map_0.size(), color_map_0.size())
	for i in range(count):
		var wall_idx := MSTVertexColorHelper.get_texture_index_from_colors(wall_color_map_0[i], wall_color_map_1[i])
		var ground_idx := MSTVertexColorHelper.get_texture_index_from_colors(color_map_0[i], color_map_1[i])
		if wall_idx == ground_idx:
			wall_color_map_0[i] = c0
			wall_color_map_1[i] = c1
			changed = true
	if changed:
		mark_dirty()
	return changed


func apply_default_wall_to_legacy_init(new_idx: int) -> bool:
	# Legacy wall map initialization used Color(1,0,0,0) for BOTH channels to mean "texture 0".
	# This breaks default wall texture behavior and should be treated as unpainted.
	if not wall_color_map_0 or not wall_color_map_1:
		return false
	var legacy := Color(1, 0, 0, 0)
	var cols := MSTVertexColorHelper.texture_index_to_colors(new_idx)
	var c0 : Color = cols[0]
	var c1 : Color = cols[1]
	var changed := false
	for i in range(wall_color_map_0.size()):
		if wall_color_map_0[i] == legacy and wall_color_map_1[i] == legacy:
			wall_color_map_0[i] = c0
			wall_color_map_1[i] = c1
			changed = true
	if changed:
		mark_dirty()
	return changed


func generate_grass_mask_map():
	grass_mask_map = PackedColorArray()
	grass_mask_map.resize(dimensions.z * dimensions.x)
	for z in range(dimensions.z):
		for x in range(dimensions.x):
			grass_mask_map[z*dimensions.x + x] = Color(1.0, 1.0, 1.0, 1.0)

#endregion

#region cell_geometry getters

func get_height(cc: Vector2i) -> float:
	return height_map[cc.y][cc.x]


func get_color_0(cc: Vector2i) -> Color:
	return color_map_0[cc.y*dimensions.x + cc.x]


func get_color_1(cc: Vector2i) -> Color:
	return color_map_1[cc.y*dimensions.x + cc.x]


func get_wall_color_0(cc: Vector2i) -> Color:
	return wall_color_map_0[cc.y*dimensions.x + cc.x]


func get_wall_color_1(cc: Vector2i) -> Color:
	return wall_color_map_1[cc.y*dimensions.x + cc.x]


func get_wall_color_map_state() -> Dictionary:
	return {
		"color_0": wall_color_map_0.duplicate(),
		"color_1": wall_color_map_1.duplicate(),
	}


func get_grass_mask(cc: Vector2i) -> Color:
	return grass_mask_map[cc.y*dimensions.x + cc.x]

#endregion


func get_nav_walkable_faces_for_permission(max_slope_degrees: float, permission: Variant = null) -> PackedVector3Array:
	var faces := PackedVector3Array()
	var fallback_faces := PackedVector3Array()
	if cell_geometry.is_empty():
		return faces
	var max_angle := deg_to_rad(clampf(max_slope_degrees, 0.0, 89.0))
	var min_triangle_area := maxf(cell_size.x * cell_size.y * 0.00005, 0.000001)
	var max_x := float(dimensions.x - 1) * cell_size.x
	var max_z := float(dimensions.z - 1) * cell_size.y
	var epsilon := maxf(minf(cell_size.x, cell_size.y) * 0.001, 0.0001)
	var seen_triangles := {}
	for entry_key in cell_geometry.keys():
		if not (entry_key is Vector2i):
			continue
		if permission != null:
			var permission_index: int = entry_key.y * maxi(dimensions.x - 1, 1) + entry_key.x
			if permission_index < 0 or permission_index >= permission.size() or permission[permission_index] == 0:
				continue
		var entry: Dictionary = cell_geometry[entry_key]
		if not entry.has("verts") or not entry.has("is_floor"):
			continue
		var verts: PackedVector3Array = entry["verts"]
		var floor_flags: Array = entry["is_floor"]
		for tri_index in range(int(verts.size() / 3)):
			var base := tri_index * 3
			if base + 2 >= verts.size() or base + 2 >= floor_flags.size():
				continue
			if not (bool(floor_flags[base]) and bool(floor_flags[base + 1]) and bool(floor_flags[base + 2])):
				continue
			var a := verts[base]
			var b := verts[base + 1]
			var c := verts[base + 2]
			fallback_faces.append_array([a, b, c])
			a = _snap_nav_vertex_to_chunk_bounds(a, max_x, max_z, epsilon)
			b = _snap_nav_vertex_to_chunk_bounds(b, max_x, max_z, epsilon)
			c = _snap_nav_vertex_to_chunk_bounds(c, max_x, max_z, epsilon)
			var cross := (b - a).cross(c - a)
			if cross.length() * 0.5 < min_triangle_area:
				continue
			var normal := cross.normalized()
			if normal.dot(Vector3.UP) <= 0.0 or acos(clampf(normal.dot(Vector3.UP), -1.0, 1.0)) > max_angle:
				continue
			var key := _make_nav_triangle_key(a, b, c)
			if seen_triangles.has(key):
				continue
			seen_triangles[key] = true
			faces.append(a)
			faces.append(b)
			faces.append(c)
	return fallback_faces if faces.is_empty() else faces


func _snap_nav_vertex_to_chunk_bounds(vertex: Vector3, max_x: float, max_z: float, epsilon: float) -> Vector3:
	var result := vertex
	if absf(result.x) <= epsilon:
		result.x = 0.0
	elif absf(result.x - max_x) <= epsilon:
		result.x = max_x
	if absf(result.z) <= epsilon:
		result.z = 0.0
	elif absf(result.z - max_z) <= epsilon:
		result.z = max_z
	return result


func _make_nav_triangle_key(a: Vector3, b: Vector3, c: Vector3) -> String:
	var points := [
		"%d,%d,%d" % [roundi(a.x * 1000.0), roundi(a.y * 1000.0), roundi(a.z * 1000.0)],
		"%d,%d,%d" % [roundi(b.x * 1000.0), roundi(b.y * 1000.0), roundi(b.z * 1000.0)],
		"%d,%d,%d" % [roundi(c.x * 1000.0), roundi(c.y * 1000.0), roundi(c.z * 1000.0)],
	]
	points.sort()
	return "|".join(points)


func get_nav_walkable_faces(max_slope_degrees: float) -> PackedVector3Array:
	return get_nav_walkable_faces_for_permission(max_slope_degrees, null)


#region cell_geometry setters

# Draw to height.
# Returns the coordinates of all additional chunks affected by this height change.
# Empty for inner points, neightoring edge for non-corner edges, and 3 other corners for corner points.
func draw_height(x: int, z: int, y: float):
	# Contains chunks that were updated
	height_map[z][x] = y
	mark_dirty()
	notify_needs_update(z, x)
	notify_needs_update(z, x-1)
	notify_needs_update(z-1, x)
	notify_needs_update(z-1, x-1)


func draw_color_0(x: int, z: int, color: Color):
	color_map_0[z*dimensions.x + x] = color
	mark_dirty()
	notify_needs_update(z, x)
	notify_needs_update(z, x-1)
	notify_needs_update(z-1, x)
	notify_needs_update(z-1, x-1)


func draw_color_1(x: int, z: int, color: Color):
	color_map_1[z*dimensions.x + x] = color
	mark_dirty()
	notify_needs_update(z, x)
	notify_needs_update(z, x-1)
	notify_needs_update(z-1, x)
	notify_needs_update(z-1, x-1)


func draw_wall_color_0(x: int, z: int, color: Color):
	wall_color_map_0[z*dimensions.x + x] = color
	mark_dirty()
	notify_needs_update(z, x)
	notify_needs_update(z, x-1)
	notify_needs_update(z-1, x)
	notify_needs_update(z-1, x-1)


func draw_wall_color_1(x: int, z: int, color: Color):
	wall_color_map_1[z*dimensions.x + x] = color
	mark_dirty()
	notify_needs_update(z, x)
	notify_needs_update(z, x-1)
	notify_needs_update(z-1, x)
	notify_needs_update(z-1, x-1)


func draw_grass_mask(x: int, z: int, masked: Color):
	grass_mask_map[z*dimensions.x + x] = masked
	mark_dirty()
	notify_needs_update(z, x)
	notify_needs_update(z, x-1)
	notify_needs_update(z-1, x)
	notify_needs_update(z-1, x-1)


func set_wall_color_map_state(state: Dictionary, use_threads: bool = false) -> void:
	wall_color_map_0 = state.get("color_0", PackedColorArray()).duplicate()
	wall_color_map_1 = state.get("color_1", PackedColorArray()).duplicate()
	mark_dirty()
	regenerate_all_cells(use_threads)


func get_wall_paint_stamp_state() -> Dictionary:
	return {
		"positions": wall_paint_stamp_positions.duplicate(),
		"normals": wall_paint_stamp_normals.duplicate(),
		"radii": wall_paint_stamp_radii.duplicate(),
		"texture_indices": wall_paint_stamp_texture_indices.duplicate(),
	}


func set_wall_paint_stamp_state(state: Dictionary) -> void:
	wall_paint_stamp_positions = state.get("positions", PackedVector3Array())
	wall_paint_stamp_normals = state.get("normals", PackedVector3Array())
	wall_paint_stamp_radii = state.get("radii", PackedFloat32Array())
	wall_paint_stamp_texture_indices = state.get("texture_indices", PackedInt32Array())
	mark_dirty()
	_apply_chunk_surface_material()


func append_wall_paint_stamp_to_state(state: Dictionary, world_pos: Vector3, world_normal: Vector3, radius: float, texture_idx: int) -> Dictionary:
	var positions: PackedVector3Array = state.get("positions", PackedVector3Array()).duplicate()
	var normals: PackedVector3Array = state.get("normals", PackedVector3Array()).duplicate()
	var radii: PackedFloat32Array = state.get("radii", PackedFloat32Array()).duplicate()
	var texture_indices: PackedInt32Array = state.get("texture_indices", PackedInt32Array()).duplicate()
	if positions.size() >= MAX_WALL_PAINT_STAMPS:
		positions.remove_at(0)
		normals.remove_at(0)
		radii.remove_at(0)
		texture_indices.remove_at(0)
	positions.append(world_pos)
	normals.append(world_normal.normalized())
	radii.append(maxf(radius, 0.001))
	texture_indices.append(clampi(texture_idx, 0, 255))
	return {
		"positions": positions,
		"normals": normals,
		"radii": radii,
		"texture_indices": texture_indices,
	}


func append_wall_paint_stamp(world_pos: Vector3, world_normal: Vector3, radius: float, texture_idx: int) -> Dictionary:
	return append_wall_paint_stamp_to_state(get_wall_paint_stamp_state(), world_pos, world_normal, radius, texture_idx)

#endregion


func _apply_chunk_surface_material() -> void:
	if mesh == null or terrain_system == null or mesh.get_surface_count() <= 0:
		return
	var base_mat := terrain_system.get_chunk_surface_material()
	if base_mat == null or not (base_mat is ShaderMaterial):
		mesh.surface_set_material(0, base_mat)
		return
	var mat: ShaderMaterial = (base_mat as ShaderMaterial).duplicate(true)
	_sync_wall_paint_shader_params(mat)
	mesh.surface_set_material(0, mat)


func refresh_surface_material() -> void:
	_apply_chunk_surface_material()


func queue_mesh_regen(use_threads: bool = false) -> void:
	if _mesh_regen_queued:
		return
	_mesh_regen_queued = true
	call_deferred("_run_deferred_mesh_regen", use_threads)


func _run_deferred_mesh_regen(use_threads: bool = false) -> void:
	_mesh_regen_queued = false
	if not is_inside_tree():
		return
	regenerate_mesh(use_threads)


func _queue_grass_regen() -> void:
	if _grass_regen_queued:
		return
	_grass_regen_queued = true
	call_deferred("_run_deferred_grass_regen")


func _run_deferred_grass_regen() -> void:
	_grass_regen_queued = false
	if grass_mode != GrassMode.GRASS or not is_inside_tree() or not is_instance_valid(grass_planter):
		return
	grass_planter.regenerate_all_cells()


func _sync_wall_paint_shader_params(mat: ShaderMaterial) -> void:
	var positions: Array[Vector4] = []
	var data_b: Array[Vector4] = []
	var stamp_count := min(
		wall_paint_stamp_positions.size(),
		min(wall_paint_stamp_normals.size(), min(wall_paint_stamp_radii.size(), wall_paint_stamp_texture_indices.size()))
	)
	stamp_count = mini(stamp_count, MAX_WALL_PAINT_STAMPS)
	for i in range(MAX_WALL_PAINT_STAMPS):
		if i < stamp_count:
			var p := wall_paint_stamp_positions[i]
			var n := wall_paint_stamp_normals[i].normalized()
			positions.append(Vector4(p.x, p.y, p.z, float(wall_paint_stamp_radii[i])))
			data_b.append(Vector4(n.x, n.y, n.z, float(wall_paint_stamp_texture_indices[i])))
		else:
			positions.append(Vector4.ZERO)
			data_b.append(Vector4.ZERO)
	mat.set_shader_parameter("wall_paint_count", stamp_count)
	mat.set_shader_parameter("wall_paint_stamps_a", positions)
	mat.set_shader_parameter("wall_paint_stamps_b", data_b)
	mat.set_shader_parameter("wall_paint_plane_thickness", maxf(minf(cell_size.x, cell_size.y) * 0.08, 0.03))
	mat.set_shader_parameter("wall_paint_blend_width", maxf(minf(cell_size.x, cell_size.y) * 0.18, 0.06))

func notify_needs_update(z: int, x: int):
	if z < 0 or z >=  terrain_system.dimensions.z-1 or x < 0 or x >= terrain_system.dimensions.x-1:
		return

	needs_update[z][x] = true


## Mark chunk as having modified source data - triggers save in MSTDataHandler.
func mark_dirty() -> void:
	_data_dirty = true
	if terrain_system != null and terrain_system.has_method("invalidate_navmesh_preview"):
		terrain_system.invalidate_navmesh_preview()
	if terrain_system != null and terrain_system.has_method("invalidate_navmesh_chunk"):
		terrain_system.invalidate_navmesh_chunk(chunk_coords)


func _create_simplified_collision_shape() -> ConcavePolygonShape3D:
	if terrain_system == null:
		return null
	return _create_simplified_proxy_collision_shape()


func _get_uniform_flat_chunk_height() -> Variant:
	if not (height_map is Array) or height_map.size() < dimensions.z:
		return null
	var uniform_height: Variant = null
	for z in range(dimensions.z - 1):
		for x in range(dimensions.x - 1):
			var cell_height := _get_flat_cell_height(z, x)
			if cell_height == null:
				return null
			if uniform_height == null:
				uniform_height = float(cell_height)
			elif not is_equal_approx(float(uniform_height), float(cell_height)):
				return null
	return uniform_height


func _get_global_flat_chunk_merge() -> Variant:
	if terrain_system == null:
		return null
	var terrain_chunks = terrain_system.get("chunks")
	if not terrain_chunks is Dictionary:
		return null
	var own_height := _get_uniform_flat_chunk_height()
	if own_height == null:
		return null

	var matching: Dictionary = {}
	for key in terrain_chunks.keys():
		if not (key is Vector2i):
			continue
		var candidate: MarchingSquaresTerrainChunk = terrain_chunks.get(key)
		if candidate == null or not is_instance_valid(candidate):
			continue
		var candidate_height := candidate._get_uniform_flat_chunk_height()
		if candidate_height != null and is_equal_approx(float(candidate_height), float(own_height)):
			matching[key] = true
	if not matching.has(chunk_coords):
		return null

	var visited: Dictionary = {chunk_coords: true}
	var pending: Array[Vector2i] = [chunk_coords]
	var min_coords := chunk_coords
	var max_coords := chunk_coords
	while not pending.is_empty():
		var current: Vector2i = pending.pop_back()
		min_coords.x = mini(min_coords.x, current.x)
		min_coords.y = mini(min_coords.y, current.y)
		max_coords.x = maxi(max_coords.x, current.x)
		max_coords.y = maxi(max_coords.y, current.y)
		for direction in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			var neighbor_coords: Vector2i = current + direction
			if matching.has(neighbor_coords) and not visited.has(neighbor_coords):
				visited[neighbor_coords] = true
				pending.append(neighbor_coords)

	for z in range(min_coords.y, max_coords.y + 1):
		for x in range(min_coords.x, max_coords.x + 1):
			if not visited.has(Vector2i(x, z)):
				return null
	return {
		"height": float(own_height),
		"min_coords": min_coords,
		"max_coords": max_coords,
	}


func _create_simplified_proxy_collision_shape() -> ConcavePolygonShape3D:
	if not (height_map is Array) or height_map.size() < dimensions.z:
		return null

	var faces: Array[Vector3] = []
	var base_height := INF
	for z in range(dimensions.z):
		if not (height_map[z] is Array) or height_map[z].size() < dimensions.x:
			return null
		for x in range(dimensions.x):
			base_height = minf(base_height, float(height_map[z][x]))

	var extra_thickness := terrain_system.collision_thickness
	base_height -= extra_thickness
	var cell_rows := dimensions.z - 1
	var cell_cols := dimensions.x - 1

	var global_flat_merge = _get_global_flat_chunk_merge()
	if global_flat_merge != null and is_zero_approx(extra_thickness):
		var merge_min: Vector2i = global_flat_merge["min_coords"]
		if chunk_coords != merge_min:
			return null
		var merge_max: Vector2i = global_flat_merge["max_coords"]
		var merged_width := (merge_max.x - merge_min.x + 1) * cell_cols
		var merged_depth := (merge_max.y - merge_min.y + 1) * cell_rows
		_append_merged_top_surface(faces, 0, 0, merged_width, merged_depth, float(global_flat_merge["height"]))
		var merged_shape := ConcavePolygonShape3D.new()
		merged_shape.set_faces(PackedVector3Array(faces))
		return merged_shape

	var merged_cells: Array = []
	merged_cells.resize(cell_rows)
	for z in range(cell_rows):
		merged_cells[z] = []
		merged_cells[z].resize(cell_cols)
		for x in range(cell_cols):
			merged_cells[z][x] = false

	for z in range(cell_rows):
		for x in range(cell_cols):
			if bool(merged_cells[z][x]):
				continue

			var flat_height := _get_flat_cell_height(z, x)
			if flat_height == null:
				_append_cell_top_surface(faces, z, x)
				_append_exact_cell_wall_triangles(faces, Vector2i(x, z))
				continue
			if _should_keep_flat_cell_unmerged(z, x, float(flat_height)):
				merged_cells[z][x] = true
				_append_cell_top_surface(faces, z, x)
				_append_merged_wall_strips(faces, z, x, 1, 1, float(flat_height), base_height)
				continue

			var width := 1
			while x + width < cell_cols:
				if bool(merged_cells[z][x + width]):
					break
				if _get_flat_cell_height(z, x + width) != flat_height:
					break
				if _should_keep_flat_cell_unmerged(z, x + width, float(flat_height)):
					break
				width += 1
			var depth := 1
			var can_extend := true
			while z + depth < cell_rows and can_extend:
				can_extend = true
				for check_x in range(x, x + width):
					if bool(merged_cells[z + depth][check_x]):
						can_extend = false
						break
					if _get_flat_cell_height(z + depth, check_x) != flat_height:
						can_extend = false
						break
					if _should_keep_flat_cell_unmerged(z + depth, check_x, float(flat_height)):
						can_extend = false
						break
				if can_extend:
					depth += 1
			for mark_z in range(z, z + depth):
				for mark_x in range(x, x + width):
					merged_cells[mark_z][mark_x] = true
			_append_merged_top_surface(faces, z, x, width, depth, float(flat_height))
			_append_merged_wall_strips(faces, z, x, width, depth, float(flat_height), base_height)

	for z in range(cell_rows):
		for x in range(cell_cols):
			if is_zero_approx(extra_thickness):
				continue
			var x0 := float(x) * cell_size.x
			var x1 := float(x + 1) * cell_size.x
			var z0 := float(z) * cell_size.y
			var z1 := float(z + 1) * cell_size.y
			var p00 := Vector3(x0, float(height_map[z][x]), z0)
			var p10 := Vector3(x1, float(height_map[z][x + 1]), z0)
			var p01 := Vector3(x0, float(height_map[z + 1][x]), z1)
			var p11 := Vector3(x1, float(height_map[z + 1][x + 1]), z1)
			var b00 := Vector3(x0, base_height, z0)
			var b10 := Vector3(x1, base_height, z0)
			var b01 := Vector3(x0, base_height, z1)
			var b11 := Vector3(x1, base_height, z1)
			if z == 0:
				_append_proxy_quad(faces, p10, p00, b00, b10)
			if x == 0:
				_append_proxy_quad(faces, p00, p01, b01, b00)
			if x == cell_cols - 1:
				_append_proxy_quad(faces, p11, p10, b10, b11)
			if z == cell_rows - 1:
				_append_proxy_quad(faces, p01, p11, b11, b01)
	if not is_zero_approx(extra_thickness):
		var max_x := float(cell_cols) * cell_size.x
		var max_z := float(cell_rows) * cell_size.y
		_append_proxy_quad(faces, Vector3(0.0, base_height, max_z), Vector3(max_x, base_height, max_z), Vector3(max_x, base_height, 0.0), Vector3(0.0, base_height, 0.0))
	if faces.is_empty():
		return null
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(PackedVector3Array(faces))
	return shape


func _get_flat_cell_height(z: int, x: int) -> Variant:
	var h00 := float(height_map[z][x])
	var h10 := float(height_map[z][x + 1])
	var h01 := float(height_map[z + 1][x])
	var h11 := float(height_map[z + 1][x + 1])
	if is_equal_approx(h00, h10) and is_equal_approx(h00, h01) and is_equal_approx(h00, h11):
		return h00
	return null


func _should_keep_flat_cell_unmerged(z: int, x: int, flat_height: float) -> bool:
	for dir in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		var info := _get_adjacent_edge_info(z, x, dir)
		if not bool(info.get("has_cell", false)):
			continue
		var neighbor_height = info.get("flat_height", null)
		if neighbor_height == null:
			return true
		if not is_equal_approx(float(neighbor_height), flat_height):
			return true
	return false


func _has_adjacent_cell(local_z: int, local_x: int, dir: Vector2i) -> bool:
	var target_x := local_x + dir.x
	var target_z := local_z + dir.y
	if target_x >= 0 and target_x < dimensions.x - 1 and target_z >= 0 and target_z < dimensions.z - 1:
		return true
	if terrain_system == null:
		return false
	var dx := -1 if target_x < 0 else (1 if target_x >= dimensions.x - 1 else 0)
	var dz := -1 if target_z < 0 else (1 if target_z >= dimensions.z - 1 else 0)
	var terrain_chunks = terrain_system.get("chunks")
	return terrain_chunks is Dictionary and is_instance_valid(terrain_chunks.get(chunk_coords + Vector2i(dx, dz)))


func _get_adjacent_flat_cell_height(local_z: int, local_x: int, dir: Vector2i) -> Variant:
	var target_x := local_x + dir.x
	var target_z := local_z + dir.y
	if target_x >= 0 and target_x < dimensions.x - 1 and target_z >= 0 and target_z < dimensions.z - 1:
		return _get_flat_cell_height(target_z, target_x)
	if terrain_system == null:
		return null
	var offset := Vector2i.ZERO
	if target_x < 0:
		offset.x = -1
		target_x = dimensions.x - 2
	elif target_x >= dimensions.x - 1:
		offset.x = 1
		target_x = 0
	if target_z < 0:
		offset.y = -1
		target_z = dimensions.z - 2
	elif target_z >= dimensions.z - 1:
		offset.y = 1
		target_z = 0
	var terrain_chunks = terrain_system.get("chunks")
	var neighbor: MarchingSquaresTerrainChunk = terrain_chunks.get(chunk_coords + offset) if terrain_chunks is Dictionary else null
	if neighbor == null or not is_instance_valid(neighbor):
		return null
	return neighbor._get_flat_cell_height(target_z, target_x)


func _append_cell_top_surface(faces: Array[Vector3], z: int, x: int) -> void:
	if _append_exact_cell_floor_triangles(faces, Vector2i(x, z)):
		return
	var x0 := float(x) * cell_size.x
	var x1 := float(x + 1) * cell_size.x
	var z0 := float(z) * cell_size.y
	var z1 := float(z + 1) * cell_size.y
	_append_top_surface_cell(faces, Vector3(x0, float(height_map[z][x]), z0), Vector3(x1, float(height_map[z][x + 1]), z0), Vector3(x1, float(height_map[z + 1][x + 1]), z1), Vector3(x0, float(height_map[z + 1][x]), z1))


func _append_exact_cell_floor_triangles(faces: Array[Vector3], cell_coords: Vector2i) -> bool:
	if not cell_geometry.has(cell_coords):
		return false
	var entry: Dictionary = cell_geometry[cell_coords]
	if not entry.has("verts") or not entry.has("is_floor"):
		return false
	var verts: PackedVector3Array = entry["verts"]
	var floor_flags: Array = entry["is_floor"]
	var appended := false
	for tri_index in range(int(verts.size() / 3)):
		var base := tri_index * 3
		if base + 2 >= floor_flags.size():
			break
		if not (bool(floor_flags[base]) and bool(floor_flags[base + 1]) and bool(floor_flags[base + 2])):
			continue
		faces.append(verts[base])
		faces.append(verts[base + 1])
		faces.append(verts[base + 2])
		appended = true
	return appended


func _append_exact_cell_wall_triangles(faces: Array[Vector3], cell_coords: Vector2i) -> bool:
	if not cell_geometry.has(cell_coords):
		return false
	var entry: Dictionary = cell_geometry[cell_coords]
	if not entry.has("verts") or not entry.has("is_floor"):
		return false
	var verts: PackedVector3Array = entry["verts"]
	var floor_flags: Array = entry["is_floor"]
	if verts.is_empty() or floor_flags.is_empty():
		return false
	var appended := false
	for tri_index in range(int(verts.size() / 3)):
		var base := tri_index * 3
		if base + 2 >= floor_flags.size():
			break
		if bool(floor_flags[base]) and bool(floor_flags[base + 1]) and bool(floor_flags[base + 2]):
			continue
		var a := verts[base]
		var b := verts[base + 1]
		var c := verts[base + 2]
		if _exact_wall_is_on_populated_chunk_seam(a, b, c, cell_coords):
			continue
		faces.append(verts[base])
		faces.append(verts[base + 1])
		faces.append(verts[base + 2])
		appended = true
	return appended


func _exact_wall_is_on_populated_chunk_seam(a: Vector3, b: Vector3, c: Vector3, cell_coords: Vector2i) -> bool:
	var max_x := float(dimensions.x - 1) * cell_size.x
	var max_z := float(dimensions.z - 1) * cell_size.y
	var terrain_chunks = terrain_system.get("chunks") if terrain_system != null else null
	if not terrain_chunks is Dictionary:
		return false

	var on_left := is_zero_approx(a.x) and is_zero_approx(b.x) and is_zero_approx(c.x)
	var on_right := is_equal_approx(a.x, max_x) and is_equal_approx(b.x, max_x) and is_equal_approx(c.x, max_x)
	var on_top := is_zero_approx(a.z) and is_zero_approx(b.z) and is_zero_approx(c.z)
	var on_bottom := is_equal_approx(a.z, max_z) and is_equal_approx(b.z, max_z) and is_equal_approx(c.z, max_z)
	if cell_coords.x == 0 and on_left:
		if is_instance_valid(terrain_chunks.get(chunk_coords + Vector2i(-1, 0))):
			return true
	if cell_coords.x == dimensions.x - 2 and on_right:
		if is_instance_valid(terrain_chunks.get(chunk_coords + Vector2i(1, 0))):
			return true
	if cell_coords.y == 0 and on_top:
		if is_instance_valid(terrain_chunks.get(chunk_coords + Vector2i(0, -1))):
			return true
	if cell_coords.y == dimensions.z - 2 and on_bottom:
		if is_instance_valid(terrain_chunks.get(chunk_coords + Vector2i(0, 1))):
			return true
	return false


func _append_merged_top_surface(faces: Array[Vector3], start_z: int, start_x: int, width: int, depth: int, height: float) -> void:
	var x0 := float(start_x) * cell_size.x
	var x1 := float(start_x + width) * cell_size.x
	var z0 := float(start_z) * cell_size.y
	var z1 := float(start_z + depth) * cell_size.y
	_append_top_surface_cell(faces, Vector3(x0, height, z0), Vector3(x1, height, z0), Vector3(x1, height, z1), Vector3(x0, height, z1))


func _append_merged_wall_strips(faces: Array[Vector3], start_z: int, start_x: int, width: int, depth: int, top_height: float, fallback_bottom: float) -> void:
	_append_horizontal_edge_walls(faces, start_z, start_x, width, top_height, fallback_bottom, true)
	_append_horizontal_edge_walls(faces, start_z + depth - 1, start_x, width, top_height, fallback_bottom, false)
	_append_vertical_edge_walls(faces, start_z, start_x, depth, top_height, fallback_bottom, true)
	_append_vertical_edge_walls(faces, start_z, start_x + width - 1, depth, top_height, fallback_bottom, false)


func _append_horizontal_edge_walls(faces: Array[Vector3], z: int, start_x: int, width: int, top_height: float, fallback_bottom: float, north: bool) -> void:
	var merged_bottom = _try_get_flat_horizontal_edge_bottom(z, start_x, width, north, fallback_bottom)
	if merged_bottom != null:
		if float(merged_bottom) < top_height:
			_append_horizontal_wall_quad(faces, start_x, start_x + width, z if north else z + 1, top_height, float(merged_bottom), north)
		return
	for x in range(start_x, start_x + width):
		var info := _get_adjacent_edge_info(z, x, Vector2i(0, -1 if north else 1))
		var bottom_a := fallback_bottom
		var bottom_b := fallback_bottom
		if not bool(info.get("has_cell", false)):
			continue
		bottom_a = minf(top_height, float(info.get("edge_start", top_height)))
		bottom_b = minf(top_height, float(info.get("edge_end", top_height)))
		if bottom_a < top_height or bottom_b < top_height:
			var z_edge := z if north else z + 1
			var x0 := float(x) * cell_size.x
			var x1 := float(x + 1) * cell_size.x
			var world_z := float(z_edge) * cell_size.y
			var top_a := Vector3(x0, top_height, world_z)
			var top_b := Vector3(x1, top_height, world_z)
			var low_a := Vector3(x0, bottom_a, world_z)
			var low_b := Vector3(x1, bottom_b, world_z)
			if north:
				_append_proxy_quad(faces, top_b, top_a, low_a, low_b)
			else:
				_append_proxy_quad(faces, top_a, top_b, low_b, low_a)


func _append_vertical_edge_walls(faces: Array[Vector3], start_z: int, x: int, depth: int, top_height: float, fallback_bottom: float, west: bool) -> void:
	var merged_bottom = _try_get_flat_vertical_edge_bottom(start_z, x, depth, west, fallback_bottom)
	if merged_bottom != null:
		if float(merged_bottom) < top_height:
			_append_vertical_wall_quad(faces, start_z, start_z + depth, x if west else x + 1, top_height, float(merged_bottom), west)
		return
	for z in range(start_z, start_z + depth):
		var info := _get_adjacent_edge_info(z, x, Vector2i(-1 if west else 1, 0))
		var bottom_a := fallback_bottom
		var bottom_b := fallback_bottom
		if not bool(info.get("has_cell", false)):
			continue
		bottom_a = minf(top_height, float(info.get("edge_start", top_height)))
		bottom_b = minf(top_height, float(info.get("edge_end", top_height)))
		if bottom_a < top_height or bottom_b < top_height:
			var x_edge := x if west else x + 1
			var z0 := float(z) * cell_size.y
			var z1 := float(z + 1) * cell_size.y
			var world_x := float(x_edge) * cell_size.x
			var top_a := Vector3(world_x, top_height, z0)
			var top_b := Vector3(world_x, top_height, z1)
			var low_a := Vector3(world_x, bottom_a, z0)
			var low_b := Vector3(world_x, bottom_b, z1)
			if west:
				_append_proxy_quad(faces, top_a, top_b, low_b, low_a)
			else:
				_append_proxy_quad(faces, top_b, top_a, low_a, low_b)


func _get_adjacent_edge_info(local_z: int, local_x: int, dir: Vector2i) -> Dictionary:
	var info := {"has_cell": false, "flat_height": null, "edge_start": 0.0, "edge_end": 0.0}
	info["edge_start"] = _get_shared_edge_vertex_height(local_z, local_x, dir, false)
	info["edge_end"] = _get_shared_edge_vertex_height(local_z, local_x, dir, true)
	var target_x := local_x + dir.x
	var target_z := local_z + dir.y
	if target_x >= 0 and target_x < dimensions.x - 1 and target_z >= 0 and target_z < dimensions.z - 1:
		info["has_cell"] = true
		info["flat_height"] = _get_flat_cell_height(target_z, target_x)
		return info
	if terrain_system == null:
		return info
	var offset := Vector2i.ZERO
	if target_x < 0:
		offset.x = -1
		target_x = dimensions.x - 2
	elif target_x >= dimensions.x - 1:
		offset.x = 1
		target_x = 0
	if target_z < 0:
		offset.y = -1
		target_z = dimensions.z - 2
	elif target_z >= dimensions.z - 1:
		offset.y = 1
		target_z = 0
	var terrain_chunks = terrain_system.get("chunks")
	var neighbor: MarchingSquaresTerrainChunk = terrain_chunks.get(chunk_coords + offset) if terrain_chunks is Dictionary else null
	if neighbor == null or not is_instance_valid(neighbor):
		return info
	info["has_cell"] = true
	info["flat_height"] = _get_flat_cell_height_from_chunk(neighbor, target_z, target_x)
	return info


func _get_shared_edge_vertex_height(local_z: int, local_x: int, dir: Vector2i, second_vertex: bool) -> float:
	if dir.y < 0:
		return float(height_map[local_z][local_x + (1 if second_vertex else 0)])
	if dir.y > 0:
		return float(height_map[local_z + 1][local_x + (1 if second_vertex else 0)])
	if dir.x < 0:
		return float(height_map[local_z + (1 if second_vertex else 0)][local_x])
	return float(height_map[local_z + (1 if second_vertex else 0)][local_x + 1])


func _get_flat_cell_height_from_chunk(chunk: MarchingSquaresTerrainChunk, z: int, x: int) -> Variant:
	if chunk == null or not (chunk.height_map is Array) or chunk.height_map.size() <= z + 1:
		return null
	if not (chunk.height_map[z] is Array) or not (chunk.height_map[z + 1] is Array):
		return null
	if chunk.height_map[z].size() <= x + 1 or chunk.height_map[z + 1].size() <= x + 1:
		return null
	var h00 := float(chunk.height_map[z][x])
	var h10 := float(chunk.height_map[z][x + 1])
	var h01 := float(chunk.height_map[z + 1][x])
	var h11 := float(chunk.height_map[z + 1][x + 1])
	if is_equal_approx(h00, h10) and is_equal_approx(h00, h01) and is_equal_approx(h00, h11):
		return h00
	return null


func _try_get_flat_horizontal_edge_bottom(z: int, start_x: int, width: int, north: bool, fallback_bottom: float) -> Variant:
	var bottom: Variant = null
	for x in range(start_x, start_x + width):
		var info := _get_adjacent_edge_info(z, x, Vector2i(0, -1 if north else 1))
		if not bool(info.get("has_cell", false)):
			return null
		var neighbor_height = info.get("flat_height", null)
		if neighbor_height == null:
			return null
		if bottom == null:
			bottom = neighbor_height
		elif not is_equal_approx(float(bottom), float(neighbor_height)):
			return null
	return bottom


func _try_get_flat_vertical_edge_bottom(start_z: int, x: int, depth: int, west: bool, fallback_bottom: float) -> Variant:
	var bottom: Variant = null
	for z in range(start_z, start_z + depth):
		var info := _get_adjacent_edge_info(z, x, Vector2i(-1 if west else 1, 0))
		if not bool(info.get("has_cell", false)):
			return null
		var neighbor_height = info.get("flat_height", null)
		if neighbor_height == null:
			return null
		if bottom == null:
			bottom = neighbor_height
		elif not is_equal_approx(float(bottom), float(neighbor_height)):
			return null
	return bottom


func _append_horizontal_wall_quad(faces: Array[Vector3], start_x: int, end_x: int, z: int, top_height: float, bottom_height: float, north: bool) -> void:
	var x0 := float(start_x) * cell_size.x
	var x1 := float(end_x) * cell_size.x
	var world_z := float(z) * cell_size.y
	var top_a := Vector3(x0, top_height, world_z)
	var top_b := Vector3(x1, top_height, world_z)
	var bottom_a := Vector3(x0, bottom_height, world_z)
	var bottom_b := Vector3(x1, bottom_height, world_z)
	if north:
		_append_proxy_quad(faces, top_b, top_a, bottom_a, bottom_b)
	else:
		_append_proxy_quad(faces, top_a, top_b, bottom_b, bottom_a)


func _append_horizontal_wall_segment_quad(faces: Array[Vector3], start_x: int, end_x: int, z: int, top_height: float, bottom_a_height: float, bottom_b_height: float, north: bool) -> void:
	var x0 := float(start_x) * cell_size.x
	var x1 := float(end_x) * cell_size.x
	var world_z := float(z) * cell_size.y
	var top_a := Vector3(x0, top_height, world_z)
	var top_b := Vector3(x1, top_height, world_z)
	var bottom_a := Vector3(x0, bottom_a_height, world_z)
	var bottom_b := Vector3(x1, bottom_b_height, world_z)
	if north:
		_append_proxy_quad(faces, top_b, top_a, bottom_a, bottom_b)
	else:
		_append_proxy_quad(faces, top_a, top_b, bottom_b, bottom_a)


func _append_vertical_wall_quad(faces: Array[Vector3], start_z: int, end_z: int, x: int, top_height: float, bottom_height: float, west: bool) -> void:
	var z0 := float(start_z) * cell_size.y
	var z1 := float(end_z) * cell_size.y
	var world_x := float(x) * cell_size.x
	var top_a := Vector3(world_x, top_height, z0)
	var top_b := Vector3(world_x, top_height, z1)
	var bottom_a := Vector3(world_x, bottom_height, z0)
	var bottom_b := Vector3(world_x, bottom_height, z1)
	if west:
		_append_proxy_quad(faces, top_a, top_b, bottom_b, bottom_a)
	else:
		_append_proxy_quad(faces, top_b, top_a, bottom_a, bottom_b)


func _append_vertical_wall_segment_quad(faces: Array[Vector3], start_z: int, end_z: int, x: int, top_height: float, bottom_a_height: float, bottom_b_height: float, west: bool) -> void:
	var z0 := float(start_z) * cell_size.y
	var z1 := float(end_z) * cell_size.y
	var world_x := float(x) * cell_size.x
	var top_a := Vector3(world_x, top_height, z0)
	var top_b := Vector3(world_x, top_height, z1)
	var bottom_a := Vector3(world_x, bottom_a_height, z0)
	var bottom_b := Vector3(world_x, bottom_b_height, z1)
	if west:
		_append_proxy_quad(faces, top_a, top_b, bottom_b, bottom_a)
	else:
		_append_proxy_quad(faces, top_b, top_a, bottom_a, bottom_b)


func _legacy_get_collision_cell_plane(z: int, x: int) -> Vector3:
	var h00 := float(height_map[z][x])
	var h10 := float(height_map[z][x + 1])
	var h01 := float(height_map[z + 1][x])
	var sx := (h10 - h00) / maxf(cell_size.x, 0.0001)
	var sz := (h01 - h00) / maxf(cell_size.y, 0.0001)
	var intercept := h00 - sx * (float(x) * cell_size.x) - sz * (float(z) * cell_size.y)
	return Vector3(sx, sz, intercept)


func _legacy_collision_planes_match(a: Vector3, b: Vector3) -> bool:
	return absf(a.x - b.x) <= 0.0005 and absf(a.y - b.y) <= 0.0005 and absf(a.z - b.z) <= 0.0005


func _legacy_collision_plane_height(plane: Vector3, x: float, z: float) -> float:
	return plane.z + plane.x * x + plane.y * z


func _legacy_append_collision_exposed_walls(faces: Array[Vector3], wall_edges: Dictionary, x: int, z: int, base_height: float) -> void:
	var edges := [
		{"key": "n:%d:%d" % [x, z], "dir": Vector2i(0, -1), "a": Vector2i(x, z), "b": Vector2i(x + 1, z)},
		{"key": "w:%d:%d" % [x, z], "dir": Vector2i(-1, 0), "a": Vector2i(x, z), "b": Vector2i(x, z + 1)},
		{"key": "e:%d:%d" % [x + 1, z], "dir": Vector2i(1, 0), "a": Vector2i(x + 1, z), "b": Vector2i(x + 1, z + 1)},
		{"key": "s:%d:%d" % [x, z + 1], "dir": Vector2i(0, 1), "a": Vector2i(x + 1, z + 1), "b": Vector2i(x, z + 1)},
	]
	for edge in edges:
		var key: String = edge["key"]
		if wall_edges.has(key):
			continue
		var a_grid: Vector2i = edge["a"]
		var b_grid: Vector2i = edge["b"]
		var a_height := float(height_map[a_grid.y][a_grid.x])
		var b_height := float(height_map[b_grid.y][b_grid.x])
		var neighbor_heights := _legacy_get_collision_neighbor_edge_heights(x, z, edge["dir"])
		var bottom_a := base_height
		var bottom_b := base_height
		if neighbor_heights != null:
			bottom_a = float(neighbor_heights[0])
			bottom_b = float(neighbor_heights[1])
			if (a_height + b_height) * 0.5 <= (bottom_a + bottom_b) * 0.5 + 0.0005:
				continue
		wall_edges[key] = true
		var top_a := Vector3(float(a_grid.x) * cell_size.x, a_height, float(a_grid.y) * cell_size.y)
		var top_b := Vector3(float(b_grid.x) * cell_size.x, b_height, float(b_grid.y) * cell_size.y)
		var low_a := Vector3(top_a.x, minf(a_height, bottom_a), top_a.z)
		var low_b := Vector3(top_b.x, minf(b_height, bottom_b), top_b.z)
		_append_proxy_quad(faces, top_a, top_b, low_b, low_a)


func _legacy_get_collision_neighbor_edge_heights(x: int, z: int, direction: Vector2i) -> Variant:
	var neighbor_x := x + direction.x
	var neighbor_z := z + direction.y
	if neighbor_x >= 0 and neighbor_x < dimensions.x - 1 and neighbor_z >= 0 and neighbor_z < dimensions.z - 1:
		if direction.y < 0:
			return [float(height_map[z][x]), float(height_map[z][x + 1])]
		if direction.y > 0:
			return [float(height_map[z + 1][x]), float(height_map[z + 1][x + 1])]
		if direction.x < 0:
			return [float(height_map[z + 1][x]), float(height_map[z][x])]
		return [float(height_map[z][x + 1]), float(height_map[z + 1][x + 1])]
	if terrain_system == null:
		return null
	var offset := Vector2i.ZERO
	var edge_x := x
	var edge_z := z
	if direction.x < 0:
		offset.x = -1
		edge_x = dimensions.x - 1
	elif direction.x > 0:
		offset.x = 1
		edge_x = 0
	if direction.y < 0:
		offset.y = -1
		edge_z = dimensions.z - 1
	elif direction.y > 0:
		offset.y = 1
		edge_z = 0
	var terrain_chunks = terrain_system.get("chunks")
	var neighbor: MarchingSquaresTerrainChunk = terrain_chunks.get(chunk_coords + offset) if terrain_chunks is Dictionary else null
	if neighbor == null or not is_instance_valid(neighbor):
		return null
	if direction.y != 0:
		return [float(neighbor.height_map[edge_z][x]), float(neighbor.height_map[edge_z][x + 1])]
	return [float(neighbor.height_map[z][edge_x]), float(neighbor.height_map[z + 1][edge_x])]


func _legacy_get_flat_collision_cell_height(z: int, x: int) -> Variant:
	var h00 := float(height_map[z][x])
	var h10 := float(height_map[z][x + 1])
	var h01 := float(height_map[z + 1][x])
	var h11 := float(height_map[z + 1][x + 1])
	if is_equal_approx(h00, h10) and is_equal_approx(h00, h01) and is_equal_approx(h00, h11):
		return h00
	return null


func _legacy_append_collision_region_walls(faces: Array[Vector3], start_x: int, start_z: int, width: int, depth: int, top_height: float, bottom_height: float, exact_cell: bool = false) -> void:
	var edges := [
		{"dir": Vector2i(0, -1), "a": Vector3(float(start_x) * cell_size.x, top_height, float(start_z) * cell_size.y), "b": Vector3(float(start_x + width) * cell_size.x, top_height, float(start_z) * cell_size.y), "north": true},
		{"dir": Vector2i(-1, 0), "a": Vector3(float(start_x) * cell_size.x, top_height, float(start_z + depth) * cell_size.y), "b": Vector3(float(start_x) * cell_size.x, top_height, float(start_z) * cell_size.y), "north": false},
		{"dir": Vector2i(1, 0), "a": Vector3(float(start_x + width) * cell_size.x, top_height, float(start_z) * cell_size.y), "b": Vector3(float(start_x + width) * cell_size.x, top_height, float(start_z + depth) * cell_size.y), "north": false},
		{"dir": Vector2i(0, 1), "a": Vector3(float(start_x + width) * cell_size.x, top_height, float(start_z + depth) * cell_size.y), "b": Vector3(float(start_x) * cell_size.x, top_height, float(start_z + depth) * cell_size.y), "north": true},
	]
	for edge in edges:
		var edge_start: Vector3 = edge["a"]
		var edge_end: Vector3 = edge["b"]
		var neighbor_height = _legacy_get_collision_neighbor_height(start_x, start_z, width, depth, edge["dir"], top_height)
		if neighbor_height != null and float(neighbor_height) >= top_height:
			continue
		var edge_bottom := bottom_height if neighbor_height == null else minf(top_height, float(neighbor_height))
		if edge_bottom >= top_height:
			continue
		_append_proxy_quad(faces, edge_start, edge_end, Vector3(edge_end.x, edge_bottom, edge_end.z), Vector3(edge_start.x, edge_bottom, edge_start.z))


func _legacy_get_collision_neighbor_height(start_x: int, start_z: int, width: int, depth: int, direction: Vector2i, top_height: float) -> Variant:
	var local_x := start_x + (width - 1 if direction.x > 0 else 0)
	var local_z := start_z + (depth - 1 if direction.y > 0 else 0)
	var neighbor_x := local_x + direction.x
	var neighbor_z := local_z + direction.y
	if neighbor_x >= 0 and neighbor_x < dimensions.x - 1 and neighbor_z >= 0 and neighbor_z < dimensions.z - 1:
		return _legacy_get_flat_collision_cell_height(neighbor_z, neighbor_x)
	if terrain_system == null:
		return null
	var chunk_offset := Vector2i.ZERO
	if neighbor_x < 0:
		chunk_offset.x = -1
		neighbor_x = dimensions.x - 2
	elif neighbor_x >= dimensions.x - 1:
		chunk_offset.x = 1
		neighbor_x = 0
	if neighbor_z < 0:
		chunk_offset.y = -1
		neighbor_z = dimensions.z - 2
	elif neighbor_z >= dimensions.z - 1:
		chunk_offset.y = 1
		neighbor_z = 0
	var terrain_chunks = terrain_system.get("chunks")
	var neighbor_chunk: MarchingSquaresTerrainChunk = terrain_chunks.get(chunk_coords + chunk_offset) if terrain_chunks is Dictionary else null
	if neighbor_chunk == null or not is_instance_valid(neighbor_chunk):
		return null
	return neighbor_chunk._legacy_get_flat_collision_cell_height(neighbor_z, neighbor_x)


func _legacy_append_collision_exact_walls(faces: Array[Vector3], cell_coords: Vector2i) -> void:
	if not cell_geometry.has(cell_coords):
		return
	var entry: Dictionary = cell_geometry[cell_coords]
	if not entry.has("verts") or not entry.has("is_floor"):
		return
	var verts: PackedVector3Array = entry["verts"]
	var floor_flags: Array = entry["is_floor"]
	for tri_index in range(int(verts.size() / 3)):
		var base := tri_index * 3
		if base + 2 >= floor_flags.size():
			break
		if bool(floor_flags[base]) and bool(floor_flags[base + 1]) and bool(floor_flags[base + 2]):
			continue
		var a := verts[base]
		var b := verts[base + 1]
		var c := verts[base + 2]
		var normal := (b - a).cross(c - a)
		if normal.length_squared() <= 0.000001 or absf(normal.normalized().y) > 0.35:
			continue
		var min_x := float(cell_coords.x) * cell_size.x - 0.001
		var max_x := float(cell_coords.x + 1) * cell_size.x + 0.001
		var min_z := float(cell_coords.y) * cell_size.y - 0.001
		var max_z := float(cell_coords.y + 1) * cell_size.y + 0.001
		var in_cell := true
		for vertex in [a, b, c]:
			if vertex.x < min_x or vertex.x > max_x or vertex.z < min_z or vertex.z > max_z:
				in_cell = false
				break
		if not in_cell:
			continue
		faces.append(a)
		faces.append(b)
		faces.append(c)


func _append_top_surface_cell(faces: Array[Vector3], p00: Vector3, p10: Vector3, p11: Vector3, p01: Vector3) -> void:
	faces.append(p00)
	faces.append(p10)
	faces.append(p11)
	faces.append(p00)
	faces.append(p11)
	faces.append(p01)


func _append_proxy_quad(faces: Array[Vector3], a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	faces.append(a)
	faces.append(b)
	faces.append(c)
	faces.append(a)
	faces.append(c)
	faces.append(d)


func _create_collision_body_from_shape(shape: ConcavePolygonShape3D) -> void:
	if shape == null:
		return
	var body := StaticBody3D.new()
	body.name = name + "_col"
	body.visible = false
	body.collision_layer = 17
	if terrain_system != null:
		body.set_collision_layer_value(terrain_system.extra_collision_layer, true)
	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "CollisionShape3D"
	collision_shape.shape = shape
	collision_shape.visible = false
	body.add_child(collision_shape)
	add_child(body)
	if EngineWrapper.instance.is_editor():
		var scene_root := EngineWrapper.instance.get_root_for_node(self)
		if scene_root != null:
			body.owner = scene_root
			collision_shape.owner = scene_root
		for group in get_groups():
			if group.begins_with("navmesh_"):
				body.add_to_group(group)


## Recreate collision body after scene save (deferred call for proper physics refresh).
func rebuild_collision() -> void:
	if not is_inside_tree():
		return
	for child in get_children():
		if child is StaticBody3D:
			child.free()
	var shape := _create_simplified_collision_shape()
	if shape == null:
		if terrain_system != null:
			terrain_system._refresh_collision_stats()
		return
	_create_collision_body_from_shape(shape)
	_apply_collision_layers()


func force_full_collision_rebuild() -> void:
	regenerate_mesh(false)


func get_collision_triangle_count() -> int:
	for child in get_children():
		if child is StaticBody3D:
			for shape_child in child.get_children():
				if shape_child is CollisionShape3D and shape_child.shape is ConcavePolygonShape3D:
					return int((shape_child.shape as ConcavePolygonShape3D).get_faces().size() / 3)
	return 0


func _recreate_collision_body() -> void:
	if not is_inside_tree() or _temp_collision_shapes.is_empty():
		_temp_collision_shapes.clear()
		return

	for child in get_children():
		if child is StaticBody3D:
			child.free()

	# Only create ONE body with the FIRST shape
	var shape : ConcavePolygonShape3D = null
	if _temp_collision_shapes.size() > 0 and _temp_collision_shapes[0] !=  null:
		shape = _temp_collision_shapes[0]
	_temp_collision_shapes.clear()
	if shape == null:
		# Nothing to create
		return

	_create_collision_body_from_shape(shape)


func _apply_collision_layers() -> void:
	for child in get_children():
		if child is StaticBody3D:
			child.visible = false
			child.collision_layer = 17
			child.set_collision_layer_value(terrain_system.extra_collision_layer, true)
			for _child in child.get_children():
				if _child is CollisionShape3D:
					_child.set_visible(false)


func regenerate_all_cells(use_threads: bool):
	for z in range(dimensions.z-1):
		for x in range(dimensions.x-1):
			needs_update[z][x] = true

	regenerate_mesh(use_threads)


@export_tool_button("Export GLB") var bake =  func():
	var tree := get_tree()

	var baker = MarchingSquaresGeometryBaker.new()
	baker.polygon_texture_resolution = terrain_system.polygon_texture_resolution

	var f := func(bakedMesh: Mesh, original: MeshInstance3D, bakedTexture: Image):
		var dialog := FileDialog.new()
		get_tree().root.add_child(dialog)
		dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		dialog.access = FileDialog.ACCESS_FILESYSTEM

		var inst := MeshInstance3D.new()
		inst.mesh = bakedMesh
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = ImageTexture.create_from_image(bakedTexture)
		if inst.mesh and inst.mesh.get_surface_count() > 0:
			inst.mesh.surface_set_material(0, mat)
		var file_selected := func(path: String):
			var state := GLTFState.new()
			var doc := GLTFDocument.new()
			doc.append_from_scene(inst, state)
			doc.write_to_filesystem(state, path)
			dialog.queue_free()
		dialog.add_filter("*.glb", "GLB file")
		dialog.connect("file_selected", file_selected)
		dialog.popup_centered()

	baker.finished.connect(f, CONNECT_ONE_SHOT)
	baker.bake_geometry_texture(self, tree)
	
	await baker.finished
	baker.finished.disconnect(f)
	regenerate_mesh()


func world_to_cell(world_pos: Vector3) -> Vector2i:
	var local := to_local(world_pos)
	
	var x := int(floor(local.x / terrain_system.cell_size.x))
	var z := int(floor(local.z / terrain_system.cell_size.y))
	
	x = clamp(x, 0, dimensions.x - 2)
	z = clamp(z, 0, dimensions.z - 2)
	
	return Vector2i(x, z)
