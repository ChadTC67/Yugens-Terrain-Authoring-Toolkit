@tool
extends EditorScript
class_name MarchingSquaresBaker

const DEFAULT_SIZE := 512
const PLACEHOLDER_ALBEDO := Color(1, 1, 1, 1)
const PLACEHOLDER_NORMAL := Color(0.5, 0.5, 1.0, 1.0)
const PLACEHOLDER_GRASS := Color(0, 0, 0, 0)
const MSTextureLibraryScript := preload("res://addons/MarchingSquaresTerrain/resources/marching_squares_terrain_texture_library.gd")
const MarchingSquaresTerrainHelpers := preload("res://addons/MarchingSquaresTerrain/algorithm/terrain/marching_squares_terrain_helpers.gd")
const MSTVertexColorHelper := preload("res://addons/MarchingSquaresTerrain/algorithm/terrain/marching_squares_terrain_vertex_color_helper.gd")

func _normalize_array_image(source: Image, size: int, fill_color: Color) -> Image:
	var img: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(fill_color)
	if source == null:
		return img

	var src: Image = source.duplicate() as Image
	if src == null:
		return img
	if src.is_compressed():
		var decompress_err: int = src.decompress()
		if decompress_err != OK:
			push_warning("MarchingSquaresBaker: Failed to decompress texture image (err=%s); using placeholder layer." % str(decompress_err))
			return img
	if src.get_format() != Image.FORMAT_RGBA8:
		src.convert(Image.FORMAT_RGBA8)
	if src.get_width() != size or src.get_height() != size:
		src.resize(size, size, Image.INTERPOLATE_LANCZOS)
	img.blit_rect(src, Rect2i(0, 0, size, size), Vector2i(0, 0))
	return img

func _highest_texture_slot(textures: Array) -> int:
	var highest := -1
	for i in range(textures.size()):
		if MarchingSquaresTerrainHelpers.is_valid_texture2d(textures[i]):
			highest = i
	return highest


func _required_layer_count(lib) -> int:
	var highest := max(
		_highest_texture_slot(lib.albedo_textures),
		max(_highest_texture_slot(lib.normal_textures), _highest_texture_slot(lib.grass_textures))
	)
	# Slot 15 is reserved for VOID, and the shader samples by slot index.
	return clampi(max(highest + 1, 16), 1, lib.max_slots)


## Returns paths for the baked albedo, normal, and grass Texture2DArray resources.
func _bake_array(lib, textures: Array, out_dir: String, filename: String, size: int, layer_count: int) -> String:
	var images := []
	var fill_color := PLACEHOLDER_ALBEDO
	if filename.find("normal") != -1:
		fill_color = PLACEHOLDER_NORMAL
	elif filename.find("grass") != -1:
		fill_color = PLACEHOLDER_GRASS
	for i in range(layer_count):
		var tex = null
		if i < textures.size():
			tex = textures[i]
		var img: Image
		if MarchingSquaresTerrainHelpers.is_valid_texture2d(tex):
			var src: Image = MSTVertexColorHelper.get_decompressed_image(tex)
			img = _normalize_array_image(src, size, fill_color)
		else:
			img = Image.create(size, size, false, Image.FORMAT_RGBA8)
			img.fill(fill_color)
		images.append(img)
	var arr := Texture2DArray.new()
	var err := arr.create_from_images(images)
	if err != OK:
		push_error("MarchingSquaresBaker: Failed to create Texture2DArray (%s)" % str(err))
		return ""
	var out_path := out_dir.path_join(filename)
	# Ensure the output directory exists.
	var out_abs := ProjectSettings.globalize_path(out_dir)
	if not DirAccess.dir_exists_absolute(out_abs):
		DirAccess.make_dir_recursive_absolute(out_abs)
	var res_save := ResourceSaver.save(arr, out_path)
	if res_save != OK:
		push_error("MarchingSquaresBaker: Failed to save %s (err=%s)" % [out_path, str(res_save)])
		return ""
	return out_path

func bake_library(lib, out_dir: String, albedo_size: int = DEFAULT_SIZE, grass_size: int = DEFAULT_SIZE) -> Dictionary:
	if lib == null:
		push_error("MarchingSquaresBaker: No MSTextureLibrary provided.")
		return {}
	# If lib is a placeholder Resource in the editor, attempt to load the real resource from disk.
	if not (lib is MSTextureLibraryScript):
		if lib is Resource and lib.resource_path and str(lib.resource_path) != "":
			var loaded_lib = ResourceLoader.load(str(lib.resource_path))
			if loaded_lib and loaded_lib is MSTextureLibraryScript:
				lib = loaded_lib
			else:
				push_error("MarchingSquaresBaker: texture_library is not a valid MSTextureLibrary resource.")
				return {}
		else:
			push_error("MarchingSquaresBaker: texture_library is not a MSTextureLibrary instance.")
			return {}
	lib.ensure_length()
	var layer_count := _required_layer_count(lib)

	var results := {}
	var out_abs := ProjectSettings.globalize_path(out_dir)
	if not DirAccess.dir_exists_absolute(out_abs):
		DirAccess.make_dir_recursive_absolute(out_abs)

	results["albedo_path"] = _bake_array(lib, lib.albedo_textures, out_dir, "baked_albedo_array.res", albedo_size, layer_count)
	results["normal_path"] = _bake_array(lib, lib.normal_textures, out_dir, "baked_normal_array.res", albedo_size, layer_count)
	results["grass_path"] = _bake_array(lib, lib.grass_textures, out_dir, "baked_grass_array.res", grass_size, layer_count)
	return results

func _run() -> void:
	pass
