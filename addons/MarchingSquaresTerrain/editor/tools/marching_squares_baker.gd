@tool
extends EditorScript
class_name MarchingSquaresBaker

const DEFAULT_SIZE := 512
const PLACEHOLDER_ALBEDO := Color(1, 1, 1, 1)
const PLACEHOLDER_NORMAL := Color(0.5, 0.5, 1.0, 1.0) # Neutral normal

# Returns dictionary: { "albedo_path": path, "normal_path": path, "grass_path": path }
func _bake_array(lib: MSTextureLibrary, textures: Array, out_dir: String, filename: String, size: int) -> String:
	var images := []
	var fill_color := PLACEHOLDER_ALBEDO
	if filename.find("normal") !=  -1:
		fill_color = PLACEHOLDER_NORMAL
	for i in range(lib.max_slots):
		var tex = null
		if i < textures.size():
			tex = textures[i]
		var img: Image
		if tex !=  null and tex is Texture2D:
			# Get source image and normalize mipmap usage/format so all images match when building the array.
			var src: Image = tex.get_image()
			if src !=  null:
				# Create a normalized image with consistent mipmap usage (no mipmaps) and same format.
				var w: int = src.get_width()
				var h: int = src.get_height()
				img = Image.create(w, h, false, src.get_format())
				# Copy pixels
				img.blit_rect(src, Rect2i(0, 0, w, h), Vector2i(0, 0))
				# Resize to target size
				img.resize(size, size, Image.INTERPOLATE_LANCZOS)
			else:
				img = Image.create(size, size, false, Image.FORMAT_RGBA8)
				img.fill(fill_color)
		else:
			img = Image.create(size, size, false, Image.FORMAT_RGBA8)
			img.fill(fill_color)
		images.append(img)
	var arr := Texture2DArray.new()
	var err := arr.create_from_images(images)
	if err !=  OK:
		push_error("MarchingSquaresBaker: Failed to create Texture2DArray (%s)" % str(err))
		return ""
	var out_path := out_dir.path_join(filename)
	# Ensure output directory exists (convert to absolute path for DirAccess helpers)
	var out_abs := ProjectSettings.globalize_path(out_dir)
	if not DirAccess.dir_exists_absolute(out_abs):
		DirAccess.make_dir_recursive_absolute(out_abs)
	# Save resource (ResourceSaver.save expects (resource, path) in this project)
	var res_save := ResourceSaver.save(arr, out_path)
	if res_save !=  OK:
		push_error("MarchingSquaresBaker: Failed to save %s (err=%s)" % [out_path, str(res_save)])
		return ""
	return out_path

func bake_library(lib: MSTextureLibrary, out_dir: String, size: int =  DEFAULT_SIZE) -> Dictionary:
	if lib == null:
		push_error("MarchingSquaresBaker: No MSTextureLibrary provided.")
		return {}
	# If lib is a placeholder Resource in the editor, attempt to load the real resource from disk.
	if not (lib is MSTextureLibrary):
		if lib is Resource and lib.resource_path and str(lib.resource_path) !=  "":
			var loaded_lib = ResourceLoader.load(str(lib.resource_path))
			if loaded_lib and loaded_lib is MSTextureLibrary:
				lib = loaded_lib
			else:
				push_error("MarchingSquaresBaker: texture_library is not a valid MSTextureLibrary resource.")
				return {}
		else:
			push_error("MarchingSquaresBaker: texture_library is not a MSTextureLibrary instance.")
			return {}
	# Ensure library arrays are sized
	lib.ensure_length()

	var results := {}
	# Ensure output directory exists (use absolute path for DirAccess helpers)
	var out_abs := ProjectSettings.globalize_path(out_dir)
	if not DirAccess.dir_exists_absolute(out_abs):
		DirAccess.make_dir_recursive_absolute(out_abs)

	results["albedo_path"] = _bake_array(lib, lib.albedo_textures, out_dir, "baked_albedo_array.res", size)
	results["normal_path"] = _bake_array(lib, lib.normal_textures, out_dir, "baked_normal_array.res", size)
	results["grass_path"] = _bake_array(lib, lib.grass_textures, out_dir, "baked_grass_array.res", size)
	return results

# EditorScript entry for manual runs (optional)
func _run():
	print("MarchingSquaresBaker: run() called — not automatically invoked by code preview.")
