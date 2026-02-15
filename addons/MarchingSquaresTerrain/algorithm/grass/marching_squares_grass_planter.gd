@icon("uid://sx50shr1w2g0")
@tool
extends MultiMeshInstance3D
class_name MarchingSquaresGrassPlanter

var _chunk : MarchingSquaresTerrainChunk
var terrain_system : MarchingSquaresTerrain

# Push grass points slightly inward when they're right next to a steep wall drop.
# This preserves normal random scattering on flat floors.
const _WALL_PUSH_SAMPLE_STEP_FRACTION: float = 0.25
const _WALL_PUSH_MAX_FRACTION: float = 0.18
const _WALL_PUSH_DROP_TRIGGER_FACTOR: float = 0.6
const _MIN_NORMAL_LENGTH_SQUARED: float = 0.000001


func _safe_normalized(vec: Vector3, fallback: Vector3) -> Vector3:
	return vec.normalized() if vec.length_squared() > _MIN_NORMAL_LENGTH_SQUARED else fallback


func _build_grass_basis(normal: Vector3) -> Basis:
	var up := _safe_normalized(normal, Vector3.UP)
	var right := Vector3.FORWARD.cross(up)
	if right.length_squared() <= _MIN_NORMAL_LENGTH_SQUARED:
		right = Vector3.RIGHT.cross(up)
	right = _safe_normalized(right, Vector3.RIGHT)
	var forward := _safe_normalized(up.cross(right), Vector3.FORWARD)
	return Basis(right, forward, -up)


func _sample_height_local(x: float, z: float) -> float:
	if not _chunk or not terrain_system or not _chunk.height_map:
		return 0.0
	var cs := terrain_system.cell_size
	if cs.x == 0.0 or cs.y == 0.0:
		return 0.0

	var gx := clampf(x / cs.x, 0.0, float(_chunk.dimensions.x - 1))
	var gz := clampf(z / cs.y, 0.0, float(_chunk.dimensions.z - 1))
	var x0 := int(floor(gx))
	var z0 := int(floor(gz))
	var x1 := mini(x0 + 1, _chunk.dimensions.x - 1)
	var z1 := mini(z0 + 1, _chunk.dimensions.z - 1)
	var tx := gx - float(x0)
	var tz := gz - float(z0)

	var h00: float = float(_chunk.height_map[z0][x0])
	var h10: float = float(_chunk.height_map[z0][x1])
	var h01: float = float(_chunk.height_map[z1][x0])
	var h11: float = float(_chunk.height_map[z1][x1])
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func _wall_push_offset(p: Vector3) -> Vector3:
	if not _chunk or not terrain_system:
		return Vector3.ZERO
	var cs := terrain_system.cell_size
	var cell_min := minf(cs.x, cs.y)
	if cell_min <=  0.0001:
		return Vector3.ZERO

	var step := cell_min * _WALL_PUSH_SAMPLE_STEP_FRACTION
	var h := _sample_height_local(p.x, p.z)
	var drop_trigger := float(_chunk.merge_threshold) * _WALL_PUSH_DROP_TRIGGER_FACTOR

	var best_drop := 0.0
	var dir := Vector3.ZERO

	var drop_px := h - _sample_height_local(p.x + step, p.z)
	if drop_px > best_drop:
		best_drop = drop_px
		dir = Vector3(-1, 0, 0)
	var drop_nx := h - _sample_height_local(p.x - step, p.z)
	if drop_nx > best_drop:
		best_drop = drop_nx
		dir = Vector3(1, 0, 0)
	var drop_pz := h - _sample_height_local(p.x, p.z + step)
	if drop_pz > best_drop:
		best_drop = drop_pz
		dir = Vector3(0, 0, -1)
	var drop_nz := h - _sample_height_local(p.x, p.z - step)
	if drop_nz > best_drop:
		best_drop = drop_nz
		dir = Vector3(0, 0, 1)

	if best_drop <=  drop_trigger:
		return Vector3.ZERO

	var push_max := cell_min * _WALL_PUSH_MAX_FRACTION
	# Scale push by how "wall-like" the drop is, so small slopes don't get biased.
	var t := clampf((best_drop - drop_trigger) / maxf(drop_trigger, 0.0001), 0.0, 1.0)
	return dir * (push_max * t)


func setup(chunk: MarchingSquaresTerrainChunk, redo: bool =  true) -> void:
	_chunk = chunk
	terrain_system = _chunk.terrain_system if _chunk else null

	if not _chunk or not terrain_system:
		push_error("SETUP FAILED - no chunk or terrain system found for GrassPlanter")
		return

	if (redo and multimesh) or not multimesh:
		multimesh = MultiMesh.new()

	multimesh.instance_count = 0
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true

	multimesh.instance_count = (_chunk.dimensions.x - 1) * (_chunk.dimensions.z - 1) * terrain_system.grass_subdivisions * terrain_system.grass_subdivisions

	# Mesh assignment
	if terrain_system.grass_mesh:
		multimesh.mesh = terrain_system.grass_mesh
	else:
		multimesh.mesh = QuadMesh.new()

	# Only QuadMesh has size/center_offset. If user provides a custom mesh, don't touch it.
	if multimesh.mesh is QuadMesh:
		var q := multimesh.mesh as QuadMesh
		q.size = terrain_system.grass_size * (terrain_system.cell_size.x + terrain_system.cell_size.y) / 4.0
		# Pivot so the quad grows "up" from the ground
		q.center_offset.y = q.size.y * 0.5

	cast_shadow = SHADOW_CASTING_SETTING_OFF


func ensure_multimesh_count() -> bool:
	if not multimesh or not _chunk or not terrain_system:
		return false

	var expected := (_chunk.dimensions.x - 1) * (_chunk.dimensions.z - 1) * terrain_system.grass_subdivisions * terrain_system.grass_subdivisions
	if multimesh.instance_count !=  expected:
		multimesh.instance_count = expected
		return true
	return false


func regenerate_all_cells() -> void:
	# Safety checks
	if not _chunk:
		push_error("_chunk not set while regenerating cells")
		return

	if not terrain_system:
		push_error("terrain_system not set while regenerating cells")
		return

	if not multimesh:
		setup(_chunk)

	if not _chunk.cell_geometry:
		_chunk.regenerate_mesh()

	for z in range(terrain_system.dimensions.z - 1):
		for x in range(terrain_system.dimensions.x - 1):
			generate_grass_on_cell(Vector2i(x, z))


func generate_grass_on_cell(cell_coords: Vector2i) -> void:
	# Safety checks
	if not _chunk:
		push_error("Couldn't find a reference to _chunk")
		return

	if not terrain_system:
		push_error("Couldn't find a reference to terrain_system")
		return

	if not _chunk.cell_geometry:
		push_error("Couldn't find a reference to cell_geometry")
		return

	if not _chunk.cell_geometry.has(cell_coords):
		push_error("Couldn't find a reference to cell_coords")
		return

	var cell_geometry = _chunk.cell_geometry[cell_coords]

	if not cell_geometry.has("verts") or not cell_geometry.has("uvs") or not cell_geometry.has("color_1s") or not cell_geometry.has("custom_1_values") or not cell_geometry.has("mat_blend") or not cell_geometry.has("is_floor"):
		push_error("cell_geometry missing required data: verts, uvs, color_1s (CUSTOM0), custom_1_values (CUSTOM1), mat_blend (CUSTOM2), is_floor")
		return

	ensure_multimesh_count()

	var points: Array[Vector2] = []
	var count := terrain_system.grass_subdivisions * terrain_system.grass_subdivisions

	for sz in range(terrain_system.grass_subdivisions):
		for sx in range(terrain_system.grass_subdivisions):
			# Edge detection so grass doesn't bleed through other textures
			var edge_margin := 0.12
			var slotx := lerpf(edge_margin, 1.0 - edge_margin, randf())
			var slotz := lerpf(edge_margin, 1.0 - edge_margin, randf())
			points.append(Vector2(
				(cell_coords.x + (sx + slotx) / terrain_system.grass_subdivisions) * terrain_system.cell_size.x,
				(cell_coords.y + (sz + slotz) / terrain_system.grass_subdivisions) * terrain_system.cell_size.y
			))

	var index : int = (cell_coords.y * (_chunk.dimensions.x - 1) + cell_coords.x) * count
	var end_index : int = index + count

	for slot in range(index, end_index):
		if slot >=  multimesh.instance_count:
			break
		_hide_grass_instance(slot)

	var verts : PackedVector3Array = cell_geometry["verts"]
	var uvs : PackedVector2Array = cell_geometry["uvs"]
	var custom_0_values : PackedColorArray = cell_geometry["color_1s"] # CUSTOM0
	var custom_1_values : PackedColorArray = cell_geometry["custom_1_values"] # CUSTOM1
	var mat_blend : PackedColorArray = cell_geometry["mat_blend"] # CUSTOM2
	var is_floor : Array = cell_geometry["is_floor"]

	for i in range(0, len(verts), 3):
		if i + 2 >=  len(verts):
			continue # Skip incomplete triangle

		# Only place grass on floors
		if not is_floor[i]:
			continue

		var a := verts[i]
		var b := verts[i + 1]
		var c := verts[i + 2]

		var v0 := Vector2(c.x - a.x, c.z - a.z)
		var v1 := Vector2(b.x - a.x, b.z - a.z)

		var dot00 := v0.dot(v0)
		var dot01 := v0.dot(v1)
		var dot11 := v1.dot(v1)
		var invDenom := 1.0 / (dot00 * dot11 - dot01 * dot01)

		var point_index := 0
		while point_index < len(points):
			var v2 := Vector2(points[point_index].x - a.x, points[point_index].y - a.z)
			var dot02 := v0.dot(v2)
			var dot12 := v1.dot(v2)

			var u := (dot11 * dot02 - dot01 * dot12) * invDenom
			if u < 0:
				point_index += 1
				continue

			var v := (dot00 * dot12 - dot01 * dot02) * invDenom
			if v < 0:
				point_index += 1
				continue

			if u + v <=  1:
				# Barycentric weights: wa for vertex a, wb for b, wc for c
				var wa := 1.0 - u - v
				var wb := u
				var wc := v

				# Order is irrelevant here, so use swap-remove to avoid O(n) PackedArray shifts
				# for every accepted blade during full chunk grass generation.
				var last_idx := points.size() - 1
				points[point_index] = points[last_idx]
				points.pop_back()
				var p := a * (1 - u - v) + b * u + c * v

				# If we're near a steep wall drop, nudge grass points inward so blades don't clip the wall.
				var push := _wall_push_offset(p)
				p += push

				# Interpolated material blend payload (CUSTOM2) + extra weight (CUSTOM0.r)
				var raw_blend := mat_blend[i] * wa + mat_blend[i + 1] * wb + mat_blend[i + 2] * wc
				var raw_custom0 := custom_0_values[i] * wa + custom_0_values[i + 1] * wb + custom_0_values[i + 2] * wc

				# Check grass mask first - green channel forces grass ON, red channel masks grass OFF
				var mask := custom_1_values[i] * wa + custom_1_values[i + 1] * wb + custom_1_values[i + 2] * wc
				var is_masked : bool = mask.r < 0.9999
				var force_grass_on : bool = mask.g >= 0.9999

				var mat_a := clampi(int(round(raw_blend.r)), 0, 255)
				var mat_b := clampi(int(round(raw_blend.g)), 0, 255)
				var mat_c := clampi(int(round(raw_blend.b)), 0, 255)
				var w_a := clamp(raw_blend.a, 0.0, 1.0)
				var w_b := clamp(raw_custom0.r, 0.0, 1.0)
				var w_c := clamp(1.0 - w_a - w_b, 0.0, 1.0)

				# Only spawn grass when we're mostly on a single material (prevents edge bleed).
				var dominant_mat := mat_a
				var confidence := w_a
				if w_b > confidence:
					dominant_mat = mat_b
					confidence = w_b
				if w_c > confidence:
					dominant_mat = mat_c
					confidence = w_c

				var texture_id := dominant_mat + 1
				var on_grass_tex := _has_grass_for_texture(texture_id, force_grass_on)

				var ground_uv := uvs[i] * wa + uvs[i + 1] * wb + uvs[i + 2] * wc

				if on_grass_tex and not is_masked:
					_create_grass_instance(index, p, a, b, c, texture_id, ground_uv)
				else:
					_hide_grass_instance(index)

				index += 1
			else:
				point_index += 1

	# Fill remaining points with hidden instances
	while index < end_index:
		if index >=  multimesh.instance_count:
			return
		_hide_grass_instance(index)
		index += 1


#region grass property getters

func _get_terrain_image(texture_id: int) -> Image:
	var slot_idx := clampi(texture_id - 1, 0, 255)
	var terrain_texture : Texture2D = null

	if terrain_system and terrain_system.texture_slots.size() > slot_idx and terrain_system.texture_slots[slot_idx] !=  null:
		terrain_texture = terrain_system.texture_slots[slot_idx].texture
	if not _is_valid_texture2d(terrain_texture):
		terrain_texture = _get_library_albedo_texture(slot_idx)

	if not _is_valid_texture2d(terrain_texture):
		return null

	var img : Image = terrain_texture.get_image()
	if img:
		img.decompress()
	return img


func _is_valid_texture2d(tex) -> bool:
	if tex == null or not (tex is Texture2D):
		return false
	return tex.get_class() != "Texture2D"


func _get_library_albedo_texture(slot_idx: int) -> Texture2D:
	if terrain_system == null or not terrain_system.has_method("get"):
		return null
	var lib = terrain_system.get("texture_library")
	if lib == null:
		return null
	if lib is Resource and lib.resource_path != null and not str(lib.resource_path).is_empty():
		var loaded = ResourceLoader.load(str(lib.resource_path))
		if loaded != null:
			lib = loaded
	if not (lib is MSTextureLibrary):
		return null
	if lib.has_method("ensure_length"):
		lib.ensure_length()
	if slot_idx < 0 or slot_idx >= lib.albedo_textures.size():
		return null
	var tex = lib.albedo_textures[slot_idx]
	return tex as Texture2D if _is_valid_texture2d(tex) else null


func _get_texture_id(vc_col_0: Color, vc_col_1: Color) -> int:
	var id : int = 1
	if vc_col_0.r > 0.9999:
		if vc_col_1.r > 0.9999:
			id = 1
		elif vc_col_1.g > 0.9999:
			id = 2
		elif vc_col_1.b > 0.9999:
			id = 3
		elif vc_col_1.a > 0.9999:
			id = 4
	elif vc_col_0.g > 0.9999:
		if vc_col_1.r > 0.9999:
			id = 5
		elif vc_col_1.g > 0.9999:
			id = 6
		elif vc_col_1.b > 0.9999:
			id = 7
		elif vc_col_1.a > 0.9999:
			id = 8
	elif vc_col_0.b > 0.9999:
		if vc_col_1.r > 0.9999:
			id = 9
		elif vc_col_1.g > 0.9999:
			id = 10
		elif vc_col_1.b > 0.9999:
			id = 11
		elif vc_col_1.a > 0.9999:
			id = 12
	elif vc_col_0.a > 0.9999:
		if vc_col_1.r > 0.9999:
			id = 13
		elif vc_col_1.g > 0.9999:
			id = 14
		elif vc_col_1.b > 0.9999:
			id = 15
		elif vc_col_1.a > 0.9999:
			id = 16
	return id


## Checks if the given texture ID should have grass placed on it.
func _has_grass_for_texture(texture_id: int, force_grass_on: bool) -> bool:
	if force_grass_on:
		return true
	if terrain_system == null:
		return false

	# Prefer the PR1 slot-based flags (texture_slots[].has_grass) so toggles actually work.
	var slot_idx := texture_id - 1
	if slot_idx >=  0 and slot_idx < terrain_system.texture_slots.size():
		var slot = terrain_system.texture_slots[slot_idx]
		if slot !=  null and slot.get("has_grass") != null:
			return bool(slot.has_grass)

	# Fallback to legacy exported flags.
	if texture_id == 1:
		return bool(terrain_system.tex1_has_grass) if terrain_system.get("tex1_has_grass") != null else true
	if texture_id < 2 or texture_id > 6:
		return false

	var has_grass_flags := [
		terrain_system.tex2_has_grass,
		terrain_system.tex3_has_grass,
		terrain_system.tex4_has_grass,
		terrain_system.tex5_has_grass,
		terrain_system.tex6_has_grass
	]
	return bool(has_grass_flags[texture_id - 2])


## Gets the texture scale for the given texture ID.
func _get_texture_scale(texture_id: int) -> float:
	if terrain_system == null:
		return 1.0
	var slot_idx := clampi(texture_id - 1, 0, 255)
	if slot_idx >= 0 and slot_idx < terrain_system.texture_slots.size():
		var slot = terrain_system.texture_slots[slot_idx]
		if slot != null and slot.get("scale") != null:
			return maxf(float(slot.scale), 0.001)

	var scales := [
		terrain_system.texture_scale_1,
		terrain_system.texture_scale_2,
		terrain_system.texture_scale_3,
		terrain_system.texture_scale_4,
		terrain_system.texture_scale_5,
		terrain_system.texture_scale_6
	]
	var legacy_idx := clampi(texture_id - 1, 0, 5)
	return scales[legacy_idx]


func _encode_grass_slot_id(texture_id: int) -> float:
	var slot_idx := clampi(texture_id - 1, 0, 255)
	return float(slot_idx) / 255.0


## Samples the terrain texture color at the given world position.
func _sample_terrain_texture_color(world_pos: Vector3, texture_id: int, tex_scale: float) -> Color:
	var terrain_image := _get_terrain_image(texture_id)
	if not terrain_image:
		return Color.WHITE

	var uv_x : float = clamp(world_pos.x / ((terrain_system.dimensions.x - 1) * terrain_system.cell_size.x), 0.0, 1.0)
	var uv_y : float = clamp(world_pos.z / ((terrain_system.dimensions.z - 1) * terrain_system.cell_size.y), 0.0, 1.0)

	uv_x = abs(fmod(uv_x * tex_scale, 1.0))
	uv_y = abs(fmod(uv_y * tex_scale, 1.0))

	var px := int(uv_x * (terrain_image.get_width() - 1))
	var py := int(uv_y * (terrain_image.get_height() - 1))
	var color := terrain_image.get_pixelv(Vector2(px, py))
	if _format_needs_conversion(terrain_image.get_format()):
		return color.srgb_to_linear()
	return color


func _format_needs_conversion(fmt: Image.Format) -> bool:
	match(fmt):
		Image.FORMAT_RGB8, \
		Image.FORMAT_RGBA8, \
		Image.FORMAT_DXT1, \
		Image.FORMAT_DXT3, \
		Image.FORMAT_DXT5, \
		Image.FORMAT_BPTC_RGBA, \
		Image.FORMAT_ETC2_RGB8, \
		Image.FORMAT_ETC2_RGBA8, \
		Image.FORMAT_ETC2_RGB8A1:
			return true
	return false

#endregion


#region grass placement helpers

## Creates a grass instance at the given position with proper transform and color.
func _create_grass_instance(index: int, world_pos: Vector3, a: Vector3, b: Vector3, c: Vector3, texture_id: int, ground_uv: Vector2) -> void:
	var edge1 := b - a
	var edge2 := c - a

	var normal : Vector3
	var use_flat := false
	if terrain_system !=  null:
		var flat_val = terrain_system.get("use_flat_normals")
		if flat_val == null:
			flat_val = terrain_system.get("flat_normals")
		use_flat = bool(flat_val) if flat_val != null else false
	if use_flat:
		normal = -Vector3.UP
	else:
		normal = _safe_normalized(edge1.cross(edge2), Vector3.UP)

	var instance_basis := _build_grass_basis(normal)

	# PR1: no per-blade size variation (kept for PR2/PR4 scope).
	var height_s := 1.0
	var width_s := 1.0

	var scaled_basis := instance_basis.scaled(Vector3(width_s, height_s, width_s))
	multimesh.set_instance_transform(index, Transform3D(scaled_basis, world_pos))

	var packed_uv := Vector2(clampf(ground_uv.x, 0.0, 1.0), clampf(ground_uv.y, 0.0, 1.0))
	multimesh.set_instance_custom_data(index, Color(packed_uv.x, packed_uv.y, 1.0, _encode_grass_slot_id(texture_id)))


## Hides a grass instance by scaling it to zero.
func _hide_grass_instance(index: int) -> void:
	multimesh.set_instance_transform(index, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))

#endregion
