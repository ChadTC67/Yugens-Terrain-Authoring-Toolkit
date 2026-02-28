@icon("uid://sx50shr1w2g0")
@tool
extends MarchingSquaresPlanter
class_name MarchingSquaresVegetationPlanter


var terrain_system : MarchingSquaresTerrain

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var vegetation_mesh : Mesh = null:
	set(value):
		vegetation_mesh = value
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var mesh_size : Vector3 = Vector3(1.0, 1.0, 1.0):
	set(value):
		mesh_size = value
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var mesh_position : Vector3 = Vector3(0.0, 0.0, 0.0):
	set(value):
		mesh_position = value
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var mesh_rotation : Vector3 = Vector3(0.0, 0.0, 0.0):
	set(value):
		mesh_rotation = value

# Outline related exports
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var use_outlines : bool = false:
	set(value):
		use_outlines = value
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var inner_outline_color : Color = Color(0.0, 0.0, 0.0, 1.0):
	set(value):
		inner_outline_color = value
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var outer_outline_color : Color = Color(1.0, 1.0, 1.0, 1.0):
	set(value):
		outer_outline_color = value

@export_storage var planted_chunks : Dictionary = {} 
var populated_chunks : Array[MarchingSquaresTerrainChunk]
var cell_data : Dictionary


func setup(redo: bool = true):
	if not terrain_system:
		printerr("SETUP FAILED - no terrain system found for VegetationPlanter")
		return
	
	if (redo and multimesh) or not multimesh:
		multimesh = MultiMesh.new()
	multimesh.instance_count = 0
	
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.instance_count = populated_chunks.size() * ((terrain_system.dimensions.x-1) * (terrain_system.dimensions.z-1) * terrain_system.grass_subdivisions * terrain_system.grass_subdivisions)
	if vegetation_mesh:
		multimesh.mesh = vegetation_mesh
	else:
		multimesh.mesh = BoxMesh.new() # Create a temporary box
	multimesh.mesh.size = mesh_size
	
	cast_shadow = SHADOW_CASTING_SETTING_ON
