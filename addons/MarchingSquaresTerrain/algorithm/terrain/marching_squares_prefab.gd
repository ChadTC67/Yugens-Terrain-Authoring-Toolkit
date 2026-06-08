@tool
extends Resource
class_name MarchingSquaresPrefab

enum PrefabBase { FLAT, DIAGONAL, ORTHOGONAL, FILLER }

@export var size : Vector3 = Vector3(0.5, 0.5, 0.5)

@export var base : PrefabBase:
	set(value):
		base = value
		notify_property_list_changed()

@export var top_floor : PackedScene:
	set(value):
		top_floor = value
		_prepare("top_floor", top_floor)

@export var top_floor_half : PackedScene:
	set(value):
		top_floor_half = value
		_prepare("top_floor_half", top_floor_half)

@export var bottom_floor : PackedScene:
	set(value):
		bottom_floor = value
		_prepare("bottom_floor", bottom_floor, true if base==PrefabBase.DIAGONAL else false, true if base==PrefabBase.FILLER else false)		
@export var wall_top: PackedScene:
	set(value):
		wall_top = value
		_prepare("wall_top", wall_top)
		
@export var wall: PackedScene:
	set(value):
		wall = value
		_prepare("wall", wall)
		
@export var orthogonal_orthogonal_cap_left_floor: PackedScene:
	set(value):
		orthogonal_orthogonal_cap_left_floor = value
		_prepare("orthogonal_orthogonal_cap_left_floor", orthogonal_orthogonal_cap_left_floor)
		
@export var orthogonal_orthogonal_cap_left_wall: PackedScene:
	set(value):
		orthogonal_orthogonal_cap_left_wall = value
		_prepare("orthogonal_orthogonal_cap_left_wall", orthogonal_orthogonal_cap_left_wall)
		
@export var orthogonal_orthogonal_cap_right_floor: PackedScene:
	set(value):
		orthogonal_orthogonal_cap_right_floor = value
		_prepare("orthogonal_orthogonal_cap_right_floor", orthogonal_orthogonal_cap_right_floor)
		
@export var orthogonal_orthogonal_cap_right_wall: PackedScene:
	set(value):
		orthogonal_orthogonal_cap_right_wall = value
		_prepare("orthogonal_orthogonal_cap_right_wall", orthogonal_orthogonal_cap_right_wall)
		
@export var diagonal_orthogonal_cap_left_floor: PackedScene:
	set(value):
		diagonal_orthogonal_cap_left_floor = value
		_prepare("diagonal_orthogonal_cap_left_floor", diagonal_orthogonal_cap_left_floor)
		
@export var diagonal_orthogonal_cap_left_wall: PackedScene:
	set(value):
		diagonal_orthogonal_cap_left_wall = value
		_prepare("diagonal_orthogonal_cap_left_wall", diagonal_orthogonal_cap_left_wall)
		
@export var diagonal_orthogonal_cap_right_floor: PackedScene:
	set(value):
		diagonal_orthogonal_cap_right_floor = value
		_prepare("diagonal_orthogonal_cap_right_floor", diagonal_orthogonal_cap_right_floor)
		
@export var diagonal_orthogonal_cap_right_wall: PackedScene:
	set(value):
		diagonal_orthogonal_cap_right_wall = value
		_prepare("diagonal_orthogonal_cap_right_wall", diagonal_orthogonal_cap_right_wall)
		
@export var diagonal_diagonal_cap_left_floor: PackedScene:
	set(value):
		diagonal_diagonal_cap_left_floor = value
		_prepare("diagonal_diagonal_cap_left_floor", diagonal_diagonal_cap_left_floor)
		
@export var diagonal_diagonal_cap_left_wall: PackedScene:
	set(value):
		diagonal_diagonal_cap_left_wall = value
		_prepare("diagonal_diagonal_cap_left_wall", diagonal_diagonal_cap_left_wall)
		
@export var diagonal_diagonal_cap_right_floor: PackedScene:
	set(value):
		diagonal_diagonal_cap_right_floor = value
		_prepare("diagonal_diagonal_cap_right_floor", diagonal_diagonal_cap_right_floor)
		
@export var diagonal_diagonal_cap_right_wall: PackedScene:
	set(value):
		diagonal_diagonal_cap_right_wall = value
		_prepare("diagonal_diagonal_cap_right_wall", diagonal_diagonal_cap_right_wall)
		

class PrefabData:
	var arrays : Array
	var mesh : ArrayMesh
	var weights : Dictionary[String, PackedFloat32Array]
	var size : Vector3


func get_data(key: String) -> PrefabData:
	if _arrays.has(key):
		return _arrays[key]
	return null


var _arrays: Dictionary[String, PrefabData] = {}

func _prepare(key: String, scene: PackedScene, is_diag_floor: bool = false, is_cap_floor: bool = false) -> void:
	if not scene:
		return
	var _inst : Node3D = scene.instantiate()
	var n := _inst.name
	var inst = _inst.get_child(0) as MeshInstance3D
	
	if not inst or not inst.mesh:
		return
	if not inst.mesh is ArrayMesh:
		push_warning(resource_name, ":", " ", key, " Mesh is not an ArrayMesh")
		return
	
	var data := PrefabData.new()
	data.arrays = inst.mesh.surface_get_arrays(0)
	data.weights = {}
	data.mesh = inst.mesh
	
	var verts : PackedVector3Array = data.arrays[Mesh.ARRAY_VERTEX]
	var weights_proto := PackedFloat32Array()
	weights_proto.resize(verts.size())
	var weights: Dictionary[String, PackedFloat32Array] = {
		"a": weights_proto,
		"a2": weights_proto.duplicate(),
		"b": weights_proto.duplicate(),
		"b2": weights_proto.duplicate(),
		"c": weights_proto.duplicate(),
		"c2": weights_proto.duplicate(),
		"d": weights_proto.duplicate(),
		"d2": weights_proto.duplicate(),
	}
	
	data.size = size
	for i in verts.size():
		var u : float = verts[i].x / size.x
		var v : float = verts[i].y / size.y
		var w : float = verts[i].z / size.z

		
		var iu := 1.0 - u
		var iv := 1.0 - v
		var iw := 1.0 - w
		
		weights["a2"][i] = iu * iv * iw # w000     a .────────.b        y
		weights["c2"][i] = iu * iv * w  # w001      / :      / │        │ 
		weights["a"][i] = iu * v  * iw  # w010   c ┌──+─────┐d │        │
		weights["c"][i] = iu * v  * w   # w011     │  :     │  │       ,└───> x
		weights["b2"][i] = u  * iv * iw # w100   a2│ ,:.....│..│ b2   /  a2 = origin
		weights["d2"][i] = u  * iv * w  # w101     │:       │ /      z
		weights["b"][i] = u  * v  * iw  # w110  c2 └────────┘ d2   
		weights["d"][i] = u  * v  * w   # w111     
		
		
		if is_diag_floor:# key.begins_with("m1.2"):
			weights["d"][i] = 0
			weights["a2"][i] = 0
		if is_cap_floor: #key.begins_with("m3.2"):
			weights["b2"][i] = 0
			weights["c2"][i] = 0
			
		# Normalize the weights
		var sum := 0.0
		for k in ["a","b","c","d","a2","b2","c2","d2"]:
			sum += weights[k][i]
		for k in ["a","b","c","d","a2","b2","c2","d2"]:
			weights[k][i] /= sum
				
	data.weights = weights
	_arrays[key] = data

func _validate_property(property: Dictionary) -> void:
	match base:
		PrefabBase.FLAT when property.name in [
				"top_floor_half",
				"wall_top", 
				"wall",
				"bottom_floor", 
				"orthogonal_orthogonal_cap_left_floor",
				"orthogonal_orthogonal_cap_left_wall",
				"orthogonal_orthogonal_cap_right_floor",
				"orthogonal_orthogonal_cap_right_wall",
				"diagonal_orthogonal_cap_left_floor",
				"diagonal_orthogonal_cap_left_wall",
				"diagonal_orthogonal_cap_right_floor",
				"diagonal_orthogonal_cap_right_wall",
				"diagonal_diagonal_cap_left_floor",
				"diagonal_diagonal_cap_left_wall",
				"diagonal_diagonal_cap_right_floor",
				"diagonal_diagonal_cap_right_wall"]:
			property.usage = PROPERTY_USAGE_NO_EDITOR
		PrefabBase.DIAGONAL when property.name in [
				"top_floor_half",
				"orthogonal_orthogonal_cap_left_floor",
				"orthogonal_orthogonal_cap_left_wall",
				"orthogonal_orthogonal_cap_right_floor",
				"orthogonal_orthogonal_cap_right_wall",
				"diagonal_orthogonal_cap_left_floor",
				"diagonal_orthogonal_cap_left_wall",
				"diagonal_orthogonal_cap_right_floor",
				"diagonal_orthogonal_cap_right_wall",
				"diagonal_diagonal_cap_left_floor",
				"diagonal_diagonal_cap_left_wall",
				"diagonal_diagonal_cap_right_floor",
				"diagonal_diagonal_cap_right_wall"]:
			property.usage = PROPERTY_USAGE_NO_EDITOR
		PrefabBase.ORTHOGONAL when property.name in [
				"top_floor_half",
				"diagonal_orthogonal_cap_left_floor",
				"diagonal_orthogonal_cap_left_wall",
				"diagonal_orthogonal_cap_right_floor",
				"diagonal_orthogonal_cap_right_wall",
				"diagonal_diagonal_cap_left_floor",
				"diagonal_diagonal_cap_left_wall",
				"diagonal_diagonal_cap_right_floor",
				"diagonal_diagonal_cap_right_wall"]:
			property.usage = PROPERTY_USAGE_NO_EDITOR
		PrefabBase.FILLER when property.name in [
				"orthogonal_orthogonal_cap_left_floor",
				"orthogonal_orthogonal_cap_left_wall",
				"orthogonal_orthogonal_cap_right_floor",
				"orthogonal_orthogonal_cap_right_wall"]:
			property.usage = PROPERTY_USAGE_NO_EDITOR
		
