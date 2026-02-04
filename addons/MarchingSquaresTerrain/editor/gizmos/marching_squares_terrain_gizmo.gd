extends EditorNode3DGizmo
class_name MarchingSquaresTerrainGizmo


const BrushPatternCalculator = preload("uid://bli1mnri3jwpa")

var lines : PackedVector3Array = PackedVector3Array()

var addchunk_material : Material
var removechunk_material : Material
var highlightchunk_material : Material
var brush_material : Material

var terrain_plugin : MarchingSquaresTerrainPlugin


func _redraw():
	lines.clear()
	clear()
	addchunk_material = get_plugin().get_material("addchunk", self)
	removechunk_material = get_plugin().get_material("removechunk", self)
	highlightchunk_material = get_plugin().get_material("highlightchunk", self)
	brush_material = get_plugin().get_material("brush", self)

	var terrain_system := get_node_3d()
	terrain_plugin = MarchingSquaresTerrainPlugin.instance
	if terrain_plugin == null or not is_instance_valid(terrain_plugin):
		return
	if terrain_system == null or not is_instance_valid(terrain_system):
		return

	# Only draw the gizmo if this is the only selected node
	if len(EditorInterface.get_selection().get_selected_nodes()) !=  1:
		return
	if EditorInterface.get_selection().get_selected_nodes()[0] !=  terrain_system:
		return

	var chunks_var := terrain_system.get("chunks")
	if not (chunks_var is Dictionary):
		# Script reload/order edge-case: selected node can be a plain Node3D.
		return
	var chunks: Dictionary = chunks_var

	# If these aren't present, the script isn't ready (avoid editor crashes).
	var dims_v = terrain_system.get("dimensions")
	var cell_size_v = terrain_system.get("cell_size")
	if not (dims_v is Vector3i) or not (cell_size_v is Vector2):
		return
	var dims: Vector3i = dims_v
	var cell_size: Vector2 = cell_size_v

	# Selected chunk gizmo lines
	if terrain_plugin.mode == terrain_plugin.TerrainToolMode.CHUNK_MANAGEMENT and is_instance_valid(terrain_plugin.selected_chunk) and is_instance_valid(terrain_plugin.current_terrain_node):
		if terrain_plugin.current_terrain_node.find_child("Chunk " + str(terrain_plugin.selected_chunk.chunk_coords)):
			add_chunk_lines(terrain_system, chunks, terrain_plugin.selected_chunk.chunk_coords, highlightchunk_material)
		else:
			lines.clear()

	# Chunk management gizmo lines
	if chunks.is_empty():
		if terrain_plugin.is_chunk_plane_hovered:
			add_chunk_lines(terrain_system, chunks, terrain_plugin.current_hovered_chunk, addchunk_material)
	else:
		for chunk_coords: Vector2i in chunks:
			try_add_chunk(terrain_system, chunks, Vector2i(chunk_coords.x-1, chunk_coords.y))
			try_add_chunk(terrain_system, chunks, Vector2i(chunk_coords.x+1, chunk_coords.y))
			try_add_chunk(terrain_system, chunks, Vector2i(chunk_coords.x, chunk_coords.y-1))
			try_add_chunk(terrain_system, chunks, Vector2i(chunk_coords.x, chunk_coords.y+1))
			try_add_chunk(terrain_system, chunks, chunk_coords)

	var pos : Vector3 = terrain_plugin.brush_position
	var cursor_chunk_coords : Vector2i
	var cursor_cell_coords : Vector2i

	if terrain_plugin.is_setting and not terrain_plugin.draw_height_set:
		terrain_plugin.draw_height_set = true

		var chunk_x: int = int(floor(pos.x / (float(dims.x - 1) * cell_size.x)))
		var chunk_z: int = int(floor(pos.z / (float(dims.z - 1) * cell_size.y)))
		cursor_chunk_coords = Vector2i(chunk_x, chunk_z)

		var x: int = int(floor(((pos.x + cell_size.x/2.0) / cell_size.x) - float(chunk_x) * float(dims.x - 1)))
		var z: int = int(floor(((pos.z + cell_size.y/2.0) / cell_size.y) - float(chunk_z) * float(dims.z - 1)))
		cursor_cell_coords = Vector2i(x, z)

		# When setting, if there is no pattern and alt not held, go to draw mode
		var has_pattern : bool = not terrain_plugin.current_draw_pattern.is_empty()
		if not has_pattern and not Input.is_key_pressed(KEY_ALT):
			terrain_plugin.current_draw_pattern.clear()
			terrain_plugin.is_setting = false
			terrain_plugin.is_drawing = true
			terrain_plugin.draw_height = pos.y

		# Otherwise, drag that pattern's height
		else:
			# If alt held, ONLY drag the cursor cell
			if Input.is_key_pressed(KEY_ALT) and chunks.has(cursor_chunk_coords):
				terrain_plugin.current_draw_pattern.clear()
				terrain_plugin.current_draw_pattern[cursor_chunk_coords] = {}
				terrain_plugin.current_draw_pattern[cursor_chunk_coords][cursor_cell_coords] = chunks[cursor_chunk_coords].get_height(cursor_cell_coords)
				terrain_plugin.draw_height = pos.y
			terrain_plugin.base_position = pos

	if terrain_plugin.is_drawing and not terrain_plugin.draw_height_set:
		terrain_plugin.draw_height_set = true
		terrain_plugin.draw_height = terrain_plugin.brush_position.y

	var terrain_chunk_hovered : bool = terrain_plugin.terrain_hovered

	# Check if we're in wall painting mode
	var is_wall_painting : bool = terrain_plugin.paint_walls_mode and terrain_plugin.mode == terrain_plugin.TerrainToolMode.VERTEX_PAINTING

	# Set the BRUSH_VISUAL's size dynamically
	if terrain_plugin.BRUSH_VISUAL !=  null and (terrain_plugin.BRUSH_VISUAL is PlaneMesh or terrain_plugin.BRUSH_VISUAL is QuadMesh):
		terrain_plugin.BRUSH_VISUAL.size = Vector2(1.0, 1.0) * (cell_size.x + cell_size.y) / 4.0

	if terrain_chunk_hovered:
		if terrain_plugin.mode == terrain_plugin.TerrainToolMode.BRIDGE and not terrain_plugin.curve3d_mode and (terrain_plugin.is_drawing or terrain_plugin.is_setting or terrain_plugin.is_making_bridge):
			terrain_plugin.rebuild_bridge_line_pattern(pos)

		# Brush radius visualization
		# brush_size is a radius; these visuals are unit-sized (cylinder radius ~0.5 / plane size 1),
		# so we scale by 2x to make the visible radius match the painted radius.
		var brush_transform : Transform3D
		brush_transform = Transform3D(Vector3.RIGHT * terrain_plugin.brush_size * 2.0, Vector3.UP, Vector3.BACK * terrain_plugin.brush_size * 2.0, pos)

		if is_wall_painting:
			var viewport := EditorInterface.get_editor_viewport_3d()
			var editor_camera := viewport.get_camera_3d()
			var mouse_pos := viewport.get_mouse_position()

			var ray_origin := editor_camera.project_ray_origin(mouse_pos)
			var ray_dir := editor_camera.project_ray_normal(mouse_pos)

			var space := terrain_system.get_world_3d().direct_space_state
			var query := PhysicsRayQueryParameters3D.create(
				ray_origin,
				ray_origin + ray_dir * 10000.0
			)

			query.collide_with_areas = false
			query.collide_with_bodies = true
			var hit_result = space.intersect_ray(query)
			var wall_normal : Vector3 = Vector3.BACK
			if hit_result:
				wall_normal = hit_result.normal
				terrain_plugin.brush_surface_normal = (terrain_system.global_transform.basis.inverse() * wall_normal).normalized()
			else:
				terrain_plugin.brush_surface_normal = Vector3.UP

			var basis := _create_brush_basis(wall_normal, terrain_plugin.brush_size * 2.0)
			if wall_normal.y > 0.5:
				basis.z = Vector3.ZERO
			brush_transform = Transform3D(basis, pos)

		if terrain_plugin.mode == terrain_plugin.TerrainToolMode.VERTEX_PAINTING:
			if terrain_plugin.paint_walls_mode:
				add_mesh(terrain_plugin.BRUSH_RADIUS_VISUAL, terrain_plugin.BRUSH_RADIUS_MATERIAL, brush_transform)
		elif terrain_plugin.mode not in [terrain_plugin.TerrainToolMode.SMOOTH, terrain_plugin.TerrainToolMode.GRASS_MASK, terrain_plugin.TerrainToolMode.DEBUG_BRUSH, terrain_plugin.TerrainToolMode.CHUNK_MANAGEMENT, terrain_plugin.TerrainToolMode.HEIGHTMAP, terrain_plugin.TerrainToolMode.POPULATE]:
			add_mesh(terrain_plugin.BRUSH_RADIUS_VISUAL, terrain_plugin.BRUSH_RADIUS_MATERIAL, brush_transform)
		
		var already_set_once : bool = false
		if not terrain_plugin.current_draw_pattern.is_empty():
			already_set_once = true

		pos = terrain_plugin.brush_position

		var bounds = BrushPatternCalculator.calculate_bounds(pos, terrain_plugin.brush_size, terrain_system)
		var max_distance : float = BrushPatternCalculator.calculate_max_distance(terrain_plugin.brush_size, terrain_plugin.current_brush_index)
		var brush_pos : Vector2 = Vector2(pos.x, pos.z)

		for chunk_z in range(bounds.chunk_tl.y, bounds.chunk_br.y + 1):
			for chunk_x in range(bounds.chunk_tl.x, bounds.chunk_br.x + 1):
				cursor_chunk_coords = Vector2i(chunk_x, chunk_z)
				if not chunks.has(cursor_chunk_coords):
					continue
				var chunk : MarchingSquaresTerrainChunk = chunks[cursor_chunk_coords]
				
				var cell_range : Dictionary = BrushPatternCalculator.get_cell_range_for_chunk(cursor_chunk_coords, bounds, terrain_system)
				
				var first_cell : Vector2i = Vector2i(cell_range.x_min, cell_range.z_min)
				var last_cell : Vector2i = Vector2i(cell_range.x_max, cell_range.z_max) - Vector2i.ONE
				
				for z in range(cell_range.z_min, cell_range.z_max):
					for x in range(cell_range.x_min, cell_range.x_max):
						cursor_cell_coords = Vector2i(x, z)
						var world_pos : Vector2 = BrushPatternCalculator.cell_to_world_pos(
							cursor_chunk_coords,
							cursor_cell_coords,
							terrain_system
						)

						var use_falloff := terrain_plugin.falloff
						if terrain_plugin.mode == terrain_plugin.TerrainToolMode.VERTEX_PAINTING:
							use_falloff = (terrain_plugin.vp_falloff_mode == terrain_plugin.VertexPaintFalloffMode.DITHERED)
						if terrain_plugin.mode in [terrain_plugin.TerrainToolMode.HEIGHTMAP, terrain_plugin.TerrainToolMode.GRASS_MASK]:
							use_falloff = false
						var sample : float = BrushPatternCalculator.calculate_falloff_sample(
							world_pos, brush_pos, terrain_plugin.brush_size, terrain_plugin.current_brush_index,
							max_distance, use_falloff, terrain_plugin.falloff_curve
						)
						if is_wall_painting:
							var wall_sample_pos := BrushPatternCalculator.cell_to_wall_sample_pos(
								cursor_chunk_coords,
								cursor_cell_coords,
								terrain_system,
								pos
							)
							sample = BrushPatternCalculator.calculate_wall_falloff_sample(
								wall_sample_pos,
								pos,
								terrain_plugin.brush_surface_normal,
								terrain_plugin.brush_size,
								terrain_plugin.current_brush_index,
								max_distance,
								use_falloff,
								terrain_plugin.falloff_curve
							)

						if sample < 0:
							continue  # Outside brush

						var y : float
						if not terrain_plugin.current_draw_pattern.is_empty() and terrain_plugin.flatten:
							y = terrain_plugin.draw_height
						else:
							# height_map can be empty while chunks initialize (or after errors).
							if chunk.height_map.size() > z and z >=  0 and chunk.height_map[z].size() > x and x >= 0:
								y = chunk.height_map[z][x]
							else:
								y = 0.0
						
						var pixel : Color
						if terrain_plugin.mode == terrain_plugin.TerrainToolMode.HEIGHTMAP:
							if terrain_plugin.flatten:
								y = terrain_plugin.brush_position.y
							var img_size := terrain_plugin.current_heightmap_image.get_size()
							var index : Vector2i = cursor_cell_coords - first_cell
							var sample_area := last_cell - first_cell + Vector2i.ONE
							var sample_size := (sample_area.x + sample_area.y) / 2.0
							var scale : Vector2 = (img_size / sample_size)
							var p_coords := Vector2i(scale * Vector2(index) + scale / 2)
							p_coords.x = clampi(p_coords.x, 0, img_size.x - 1)
							p_coords.y = clampi(p_coords.y, 0, img_size.y - 1)
							pixel = terrain_plugin.current_heightmap_image.get_pixel(p_coords.x, p_coords.y)
							y += terrain_plugin.brush_size / terrain_system.cell_size.x * pixel.r

						var draw_position := Vector3(world_pos.x, y, world_pos.y)
						var draw_transform := Transform3D(Vector3.RIGHT*sample, Vector3.UP*sample, Vector3.BACK*sample, draw_position)
						# Only draw ground brush squares if NOT in wall paint mode
						if not is_wall_painting and terrain_plugin.mode != terrain_plugin.TerrainToolMode.CHUNK_MANAGEMENT:
							if terrain_plugin.mode == terrain_plugin.TerrainToolMode.HEIGHTMAP and pixel.r == 0.0:
								pass
							else:
								add_mesh(terrain_plugin.BRUSH_VISUAL, brush_material, draw_transform)
						
						if terrain_plugin.mode in [terrain_plugin.TerrainToolMode.HEIGHTMAP] and already_set_once:
							continue
						
						# Draw to current pattern
						if terrain_plugin.is_drawing:
							if not terrain_plugin.current_draw_pattern.has(cursor_chunk_coords):
								terrain_plugin.current_draw_pattern[cursor_chunk_coords] = {}
							if terrain_plugin.current_draw_pattern[cursor_chunk_coords].has(cursor_cell_coords):
								var prev_sample = terrain_plugin.current_draw_pattern[cursor_chunk_coords][cursor_cell_coords]
								if sample > prev_sample:
									terrain_plugin.current_draw_pattern[cursor_chunk_coords][cursor_cell_coords] = sample
							else:
								terrain_plugin.current_draw_pattern[cursor_chunk_coords][cursor_cell_coords] = sample

	var height_diff : float
	if terrain_plugin.is_setting and terrain_plugin.draw_height_set:
		height_diff = terrain_plugin.brush_position.y - terrain_plugin.draw_height

	if not terrain_plugin.current_draw_pattern.is_empty():
		for draw_chunk_coords : Vector2i in terrain_plugin.current_draw_pattern:
			var chunk = chunks[draw_chunk_coords]
			var draw_chunk_dict : Dictionary = terrain_plugin.current_draw_pattern[draw_chunk_coords]
			
			var first_draw_cell : Vector2i
			var last_draw_cell : Vector2i
			for draw_cell_coords: Vector2i in draw_chunk_dict:
				if not first_draw_cell:
					first_draw_cell = draw_cell_coords
				last_draw_cell.x = maxi(last_draw_cell.x, draw_cell_coords.x)
				last_draw_cell.y = maxi(last_draw_cell.y, draw_cell_coords.y)
			
			for draw_coords: Vector2i in draw_chunk_dict:
				var draw_x: float = (float(draw_chunk_coords.x) * float(dims.x - 1) + float(draw_coords.x)) * cell_size.x
				var draw_z: float = (float(draw_chunk_coords.y) * float(dims.z - 1) + float(draw_coords.y)) * cell_size.y
				var draw_y := terrain_plugin.draw_height if terrain_plugin.flatten else 0.0
				if not terrain_plugin.flatten:
					var dz := draw_coords.y
					var dx := draw_coords.x
					if chunk.height_map.size() > dz and dz >= 0 and chunk.height_map[dz].size() > dx and dx >= 0:
						draw_y = chunk.height_map[dz][dx]
				
				var pixel : Color
				if terrain_plugin.mode == terrain_plugin.TerrainToolMode.HEIGHTMAP:
					var img_size := terrain_plugin.current_heightmap_image.get_size()
					var index : Vector2i = draw_coords - first_draw_cell
					var sample_area := last_draw_cell - first_draw_cell + Vector2i.ONE
					var sample_size := (sample_area.x + sample_area.y) / 2.0
					var scale : Vector2 = (img_size / sample_size)
					var p_coords := Vector2i(scale * Vector2(index) + scale / 2)
					p_coords.x = clampi(p_coords.x, 0, img_size.x - 1)
					p_coords.y = clampi(p_coords.y, 0, img_size.y - 1)
					pixel = terrain_plugin.current_heightmap_image.get_pixel(p_coords.x, p_coords.y)
					draw_y += terrain_plugin.brush_size / terrain_system.cell_size.x * pixel.r
				
				var sample : float = draw_chunk_dict[draw_coords]
				
				# If setting, also show a square at the height to set to
				if terrain_plugin.is_setting and terrain_plugin.draw_height_set:
					var draw_position := Vector3(draw_x, draw_y + height_diff * sample, draw_z)
					var draw_transform := Transform3D(Vector3.RIGHT*sample, Vector3.UP*sample, Vector3.BACK*sample, draw_position)
					if not is_wall_painting and terrain_plugin.mode !=  terrain_plugin.TerrainToolMode.CHUNK_MANAGEMENT:
						if terrain_plugin.mode == terrain_plugin.TerrainToolMode.HEIGHTMAP and pixel.r == 0.0:
							pass
						else:
							add_mesh(terrain_plugin.BRUSH_VISUAL, null, draw_transform)
				else:
					var draw_position := Vector3(draw_x, draw_y, draw_z)
					var draw_transform := Transform3D(Vector3.RIGHT*sample, Vector3.UP*sample, Vector3.BACK*sample, draw_position)
					if not is_wall_painting and terrain_plugin.mode !=  terrain_plugin.TerrainToolMode.CHUNK_MANAGEMENT:
						if terrain_plugin.mode == terrain_plugin.TerrainToolMode.HEIGHTMAP and pixel.r == 0.0:
							pass
						else:
							add_mesh(terrain_plugin.BRUSH_VISUAL, null, draw_transform)


func _create_brush_basis(normal: Vector3, brush_size: float) -> Basis:
	var n := normal.normalized()

	var tangent := Vector3.UP.cross(n)
	if tangent.length_squared() < 0.001:
		tangent = Vector3.RIGHT.cross(n)

	tangent = tangent.normalized()
	var bitangent := n.cross(tangent)

	tangent *= brush_size
	bitangent *= brush_size

	return Basis(tangent, n, bitangent)


func try_add_chunk(terrain_system, chunks: Dictionary, coords: Vector2i):
	var terrain_plugin := MarchingSquaresTerrainPlugin.instance

	if Input.is_key_pressed(KEY_CTRL):
		return

	# Add chunk
	if (terrain_plugin.mode == terrain_plugin.TerrainToolMode.CHUNK_MANAGEMENT or Input.is_key_pressed(KEY_SHIFT)) and not chunks.has(coords) and terrain_plugin.is_chunk_plane_hovered and terrain_plugin.current_hovered_chunk == coords:
		add_chunk_lines(terrain_system, chunks, coords, addchunk_material)

	# Remove chunk (Manage Chunk tool only)
	elif terrain_plugin.mode == terrain_plugin.TerrainToolMode.CHUNK_MANAGEMENT and terrain_plugin.is_chunk_plane_hovered and terrain_plugin.current_hovered_chunk == coords:
		add_chunk_lines(terrain_system, chunks, coords, removechunk_material)


# Draw chunk ui lines inside and around a chunk
func add_chunk_lines(terrain_system, chunks: Dictionary, coords: Vector2i, material: Material):
	var dims_v = terrain_system.get("dimensions")
	var cell_size_v = terrain_system.get("cell_size")
	if not (dims_v is Vector3i) or not (cell_size_v is Vector2):
		return
	var dims: Vector3i = dims_v
	var cell_size: Vector2 = cell_size_v

	var dx: float = float(dims.x - 1) * cell_size.x
	var dz: float = float(dims.z - 1) * cell_size.y
	var x: float = float(coords.x) * dx
	var z: float = float(coords.y) * dz
	dx += x
	dz += z

	lines.clear()
	if not chunks.has(Vector2i(coords.x, coords.y-1)):
		lines.append(Vector3(x,0,z))
		lines.append(Vector3(dx,0,z))
	if not chunks.has(Vector2i(coords.x+1, coords.y)):
		lines.append(Vector3(dx,0,z))
		lines.append(Vector3(dx,0,dz))
	if not chunks.has(Vector2i(coords.x, coords.y+1)):
		lines.append(Vector3(dx,0,dz))
		lines.append(Vector3(x,0,dz))
	if not chunks.has(Vector2i(coords.x-1, coords.y)):
		lines.append(Vector3(x,0,dz))
		lines.append(Vector3(x,0,z))

	if material == removechunk_material:
		lines.append(Vector3(x,0,z))
		lines.append(Vector3(dx,0,dz))
		lines.append(Vector3(dx,0,z))
		lines.append(Vector3(x,0,dz))

	if material == addchunk_material:
		lines.append(Vector3(lerp(x, dx, 0.25), 0, lerp(z, dz, 0.5)))
		lines.append(Vector3(lerp(x, dx, 0.75), 0, lerp(z, dz, 0.5)))
		lines.append(Vector3(lerp(x, dx, 0.5), 0, lerp(z, dz, 0.25)))
		lines.append(Vector3(lerp(x, dx, 0.5), 0, lerp(z, dz, 0.75)))

	if material == highlightchunk_material:
		lines.append(Vector3(lerp(x, dx, 0.25), 0, lerp(z, dz, 0.25)))
		lines.append(Vector3(lerp(x, dx, 0.75), 0, lerp(z, dz, 0.25)))
		lines.append(Vector3(lerp(x, dx, 0.25), 0, lerp(z, dz, 0.25)))
		lines.append(Vector3(lerp(x, dx, 0.25), 0, lerp(z, dz, 0.75)))

		lines.append(Vector3(lerp(x, dx, 0.75), 0, lerp(z, dz, 0.25)))
		lines.append(Vector3(lerp(x, dx, 0.75), 0, lerp(z, dz, 0.75)))
		lines.append(Vector3(lerp(x, dx, 0.25), 0, lerp(z, dz, 0.75)))
		lines.append(Vector3(lerp(x, dx, 0.75), 0, lerp(z, dz, 0.75)))

	add_lines(lines, material, false)
