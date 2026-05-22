@tool
class_name MarchingSquaresHeightmapImporter
extends RefCounted


static func run(
	terrain: MarchingSquaresTerrain,
	heightmap_image: Texture2D,
	chunks_x: int,
	chunks_z: int,
	max_height: int,
	merge_mode: int,
	caller: Node
) -> void:
	# --- Build progress dialog ---
	var base_control := EditorInterface.get_base_control()

	var dialog := Popup.new()
	dialog.exclusive = true
	dialog.unresizable = true
	var window_size := DisplayServer.window_get_size()
	dialog.size = Vector2i(int(window_size.x * 0.3), int(window_size.y * 0.2))
	# Inherit the full editor theme so all child controls (Button, ProgressBar,
	# Label) automatically match the current editor colour scheme.
	dialog.theme = base_control.get_theme()

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = base_control.get_theme_color("base_color", "Editor")
	panel_style.corner_radius_top_left = 10
	panel_style.corner_radius_top_right = 10
	panel_style.corner_radius_bottom_left = 10
	panel_style.corner_radius_bottom_right = 10
	panel_style.content_margin_left = 12
	panel_style.content_margin_right = 12
	panel_style.content_margin_top = 12
	panel_style.content_margin_bottom = 12

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", panel_style)
	dialog.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	var status_label := Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.text = "Initializing..."
	vbox.add_child(status_label)

	var progress_bar := ProgressBar.new()
	progress_bar.min_value = 0.0
	progress_bar.max_value = 100.0
	progress_bar.value = 0.0
	vbox.add_child(progress_bar)

	var ok_button := Button.new()
	ok_button.text = "OK"
	ok_button.visible = false
	ok_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok_button.pressed.connect(dialog.queue_free)
	vbox.add_child(ok_button)

	# Only allow closing (via Escape) once the import is finished.
	dialog.close_requested.connect(func():
		if ok_button.visible:
			dialog.queue_free()
	)

	base_control.add_child(dialog)
	dialog.popup_centered()
	await caller.get_tree().process_frame

	var finish_error := func(msg: String) -> void:
		status_label.add_theme_color_override("font_color", base_control.get_theme_color("error_color", "Editor"))
		status_label.text = msg
		ok_button.visible = true

	var finish_ok := func(chunks_made: int) -> void:
		status_label.text = "Done! Created %d chunks." % chunks_made
		progress_bar.value = 100.0
		dialog.queue_free()

	# --- Read terrain properties ---
	var dims : Vector3i = terrain.dimensions
	var data_dir : String = terrain.data_directory

	# Handle data_directory pointing to the TerrainData root instead of the UID subfolder
	var _scene_path := caller.get_tree().edited_scene_root.scene_file_path
	var _scene_dir  := _scene_path.get_base_dir()
	var _scene_name := _scene_path.get_file().get_basename()
	var _terrain_data_root := _scene_dir.path_join(_scene_name + "_TerrainData")
	if data_dir.simplify_path() == _terrain_data_root.simplify_path():
		terrain.data_directory = ""
		data_dir = terrain.data_directory

	if data_dir.is_empty():
		finish_error.call("Terrain has no data directory.\nSave the scene first.")
		return

	# --- Load and validate the heightmap image ---
	if not heightmap_image:
		finish_error.call("No heightmap image assigned.")
		return

	var image : Image = heightmap_image.get_image()
	if not image:
		finish_error.call("Failed to get an Image from the assigned texture.")
		return

	if image.is_compressed():
		image.decompress()

	var img_w : int = image.get_width()
	var img_h : int = image.get_height()

	if img_w < 2 or img_h < 2:
		finish_error.call("Image is too small (minimum 2×2).")
		return

	# --- Calculate the full height grid ---
	var cells_x : int = dims.x - 1
	var cells_z : int = dims.z - 1
	var grid_w : int = chunks_x * cells_x + 1
	var grid_h : int = chunks_z * cells_z + 1

	var total_chunks : int = chunks_x * chunks_z
	var step_pct : float = 100.0 / float(total_chunks + 1)

	# --- Resample heightmap (1 step of total_chunks + 1) ---
	status_label.text = "Resampling heightmap..."
	var full_grid : Array = []
	full_grid.resize(grid_h)

	for gz in grid_h:
		var row : Array = []
		row.resize(grid_w)
		for gx in grid_w:
			var sx : float = float(gx) / float(grid_w - 1) * float(img_w - 1)
			var sz : float = float(gz) / float(grid_h - 1) * float(img_h - 1)
			var luminance : float = _sample_bilinear(image, sx, sz, img_w, img_h)
			row[gx] = roundf(luminance * max_height)
		full_grid[gz] = row
		if gz % 10 == 0:
			progress_bar.value = float(gz) / float(grid_h) * step_pct
			await caller.get_tree().process_frame

	# --- Calculate chunk coordinate offset for centering ---
	@warning_ignore("integer_division")
	var offset_x : int = -(chunks_x / 2)
	@warning_ignore("integer_division")
	var offset_z : int = -(chunks_z / 2)

	# --- Ensure data directory exists ---
	if not DirAccess.dir_exists_absolute(data_dir):
		var err := DirAccess.make_dir_recursive_absolute(data_dir)
		if err != OK:
			finish_error.call("Failed to create data directory:\n%s" % data_dir)
			return

	# --- Remove existing chunks that overlap with the import grid ---
	status_label.text = "Removing existing chunks..."
	progress_bar.value = step_pct
	for cz in chunks_z:
		for cx in chunks_x:
			var coords := Vector2i(cx + offset_x, cz + offset_z)
			if terrain.chunks.has(coords):
				var old_chunk = terrain.chunks[coords]
				terrain.chunks.erase(coords)
				old_chunk.queue_free()

	# --- Create and save each chunk ---
	var saved_count : int = 0
	for cz in chunks_z:
		for cx in chunks_x:
			var coords := Vector2i(cx + offset_x, cz + offset_z)

			# Build the height_map for this chunk
			var height_map : Array = []
			height_map.resize(dims.z)
			var start_gx : int = cx * cells_x
			var start_gz : int = cz * cells_z

			for lz in dims.z:
				var row : Array = []
				row.resize(dims.x)
				for lx in dims.x:
					row[lx] = full_grid[start_gz + lz][start_gx + lx]
				height_map[lz] = row

			# Create the chunk node and add it to the terrain.
			# Pre-generate all color maps so they exist when the grass
			# planter triggers mesh generation inside initialize_terrain.
			# Without this, wall_color_maps are empty when the mesh is
			# built, causing cliffs to use the ground texture instead of
			# the wall texture.
			var chunk := MarchingSquaresTerrainChunk.new()
			chunk.name = "Chunk %s" % str(coords)
			chunk.terrain_system = terrain
			chunk.merge_mode = merge_mode as MarchingSquaresTerrainChunk.Mode
			chunk.height_map = height_map
			chunk._data_dirty = false
			chunk.generate_color_maps()
			chunk.generate_grass_mask_map()
			# Set wall colors to the terrain's default wall texture.
			# The plugin's generate_wall_color_maps() uses Color(1,0,0,0) which
			# maps to texture slot 0 (ground), so we build the wall arrays manually.
			var wall_colors := MSTDataHandler._texture_idx_to_colors(terrain.default_wall_texture)
			var cell_count : int = dims.x * dims.z
			chunk.wall_color_map_0 = PackedColorArray()
			chunk.wall_color_map_0.resize(cell_count)
			chunk.wall_color_map_1 = PackedColorArray()
			chunk.wall_color_map_1.resize(cell_count)
			for i in cell_count:
				chunk.wall_color_map_0[i] = wall_colors[0]
				chunk.wall_color_map_1[i] = wall_colors[1]

			terrain.add_chunk(coords, chunk, null, true)
			MSTDataHandler.save_chunk_resources(terrain, chunk)

			saved_count += 1
			var pct := float(saved_count + 1) * step_pct
			status_label.text = "Creating chunks... %d / %d" % [saved_count, total_chunks]
			progress_bar.value = pct
			await caller.get_tree().process_frame

	terrain._storage_initialized = true
	finish_ok.call(saved_count)


static func _sample_bilinear(image: Image, sx: float, sz: float, img_w: int, img_h: int) -> float:
	var x0 : int = clampi(int(sx), 0, img_w - 1)
	var z0 : int = clampi(int(sz), 0, img_h - 1)
	var x1 : int = clampi(x0 + 1, 0, img_w - 1)
	var z1 : int = clampi(z0 + 1, 0, img_h - 1)

	var fx : float = sx - float(x0)
	var fz : float = sz - float(z0)

	var c00 : float = image.get_pixel(x0, z0).get_luminance()
	var c10 : float = image.get_pixel(x1, z0).get_luminance()
	var c01 : float = image.get_pixel(x0, z1).get_luminance()
	var c11 : float = image.get_pixel(x1, z1).get_luminance()

	var top : float = lerpf(c00, c10, fx)
	var bot : float = lerpf(c01, c11, fx)
	return lerpf(top, bot, fz)
