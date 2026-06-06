@tool
class_name BrushPatternCalculator

## Calculates which cells fall within a brush and their falloff samples.
## Used by both plugin (for editing) and gizmo (for visualization).
class BrushBounds:
	var chunk_tl : Vector2i
	var chunk_br : Vector2i
	var cell_tl : Vector2i
	var cell_br : Vector2i


static func calculate_bounds(pos: Vector3, brush_size: float, terrain: MarchingSquaresTerrain) -> BrushBounds:
	var bounds := BrushBounds.new()
	
	# brush_size is treated as a radius everywhere (gizmo scale, UI). Using /2 here caused
	# the painted region to be much smaller/sparser than the visible brush circle.
	var pos_tl := Vector2(
		pos.x - brush_size,
		pos.z - brush_size
	)
	var pos_br := Vector2(
		pos.x + brush_size,
		pos.z + brush_size
	)
	
	var chunk_size_x : float = (terrain.dimensions.x - 1) * terrain.cell_size.x
	var chunk_size_z : float = (terrain.dimensions.z - 1) * terrain.cell_size.y
	
	bounds.chunk_tl = Vector2i(floori(pos_tl.x / chunk_size_x), floori(pos_tl.y / chunk_size_z))
	bounds.chunk_br = Vector2i(floori(pos_br.x / chunk_size_x), floori(pos_br.y / chunk_size_z))
	
	bounds.cell_tl = Vector2i(
		floori(pos_tl.x / terrain.cell_size.x - bounds.chunk_tl.x * (terrain.dimensions.x - 1)),
		floori(pos_tl.y / terrain.cell_size.y - bounds.chunk_tl.y * (terrain.dimensions.z - 1))
	)
	# +1 so that x_max/z_max can be used as an exclusive range bound.
	bounds.cell_br = Vector2i(
		floori(pos_br.x / terrain.cell_size.x - bounds.chunk_br.x * (terrain.dimensions.x - 1)) + 1,
		floori(pos_br.y / terrain.cell_size.y - bounds.chunk_br.y * (terrain.dimensions.z - 1)) + 1
	)
	
	return bounds


static func calculate_max_distance(brush_size: float, brush_index: int) -> float:
	# brush_size is a radius.
	var max_distance : float = brush_size
	match brush_index:
		0: # Round brush
			max_distance *= max_distance
		1: # Square brush (use bounding circle of the square)
			max_distance *= max_distance * 2
	return max_distance


static func calculate_falloff_sample(
	world_pos: Vector2,
	brush_pos: Vector2,
	brush_size: float,
	brush_index: int,
	max_distance: float,
	use_falloff: bool,
	falloff_curve: Curve
	) -> float:
	
	var distance_squared := brush_pos.distance_squared_to(world_pos)
	if distance_squared > max_distance:
		return -1.0  # Outside brush
	
	if not use_falloff:
		return 1.0
	
	var t : float = 0.0
	match brush_index:
		0: # Round brush (linear by radius, not squared-distance)
			var denom: float = max(brush_size, 0.0001)
			var dist: float = sqrt(distance_squared)
			t = 1.0 - clamp(dist / denom, 0.0, 1.0)
		1: # Square brush
			var local: Vector2 = world_pos - brush_pos
			var denom: float = max(brush_size, 0.0001)
			var uv: Vector2 = local / denom
			var d : float = max(abs(uv.x), abs(uv.y))
			t = 1.0 - clamp(d, 0.0, 1.0)
	
	# IMPORTANT: allow true endpoints so a full-strength stroke can reach the target.
	# Soften falloff: apply a square-root easing to expand the brush's effective area (gentler falloff).
	t = pow(t, 0.5)
	return falloff_curve.sample(clamp(t, 0.0, 1.0))


## Calculate world position for a cell in a chunk.
## p_centered=true returns the center of the cell (half-cell offset). This is useful for Vertex Paint
## so round brushes look less octagon-y on low-resolution grids.
static func cell_to_world_pos(chunk_coords: Vector2i, cell_coords: Vector2i, terrain: MarchingSquaresTerrain, p_centered: bool =  false) -> Vector2:
	var world_x : float = (chunk_coords.x * (terrain.dimensions.x - 1) + cell_coords.x) * terrain.cell_size.x
	var world_z : float = (chunk_coords.y * (terrain.dimensions.z - 1) + cell_coords.y) * terrain.cell_size.y
	if p_centered:
		world_x += terrain.cell_size.x * 0.5
		world_z += terrain.cell_size.y * 0.5
	return Vector2(world_x, world_z)


## Helper function that calculates a global cell from a world position
static func world_to_global_cell(world_pos: Vector2, terrain: MarchingSquaresTerrain) -> Vector2i:
	var cell_size := terrain.cell_size
	return Vector2i(floori(world_pos.x / cell_size.x), floori(world_pos.y / cell_size.y))


## Calculate the corresponding local cell and chunk coords for a global cell
static func global_cell_to_local(global_cell: Vector2i, terrain: MarchingSquaresTerrain) -> Dictionary:
	var chunk_size := Vector2i(terrain.dimensions.x - 1, terrain.dimensions.z - 1)
	var chunk := Vector2i(floori(float(global_cell.x) / chunk_size.x), floori(float(global_cell.y) / chunk_size.y))
	var local_cell := Vector2i(posmod(global_cell.x, chunk_size.x), posmod(global_cell.y, chunk_size.y))
	
	return {
		"chunk": chunk,
		"cell": local_cell
	}


## Get cell range for a specific chunk within the brush bounds
static func get_cell_range_for_chunk(chunk_coords: Vector2i, bounds: BrushBounds, terrain: MarchingSquaresTerrain) -> Dictionary:
	var x_min : int = bounds.cell_tl.x if chunk_coords.x == bounds.chunk_tl.x else 0
	var x_max : int = bounds.cell_br.x if chunk_coords.x == bounds.chunk_br.x else terrain.dimensions.x
	var z_min : int = bounds.cell_tl.y if chunk_coords.y == bounds.chunk_tl.y else 0
	var z_max : int = bounds.cell_br.y if chunk_coords.y == bounds.chunk_br.y else terrain.dimensions.z
	return {"x_min": x_min, "x_max": x_max, "z_min": z_min, "z_max": z_max}




