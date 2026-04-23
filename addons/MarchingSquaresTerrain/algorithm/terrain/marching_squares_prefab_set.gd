@tool
class_name MarchingSquaresPrefabSet
extends Resource

@export var flats : Array[MarchingSquaresPrefab]

@export var diagonals : Array[MarchingSquaresPrefab]

@export var orthogonals : Array[MarchingSquaresPrefab]

@export var fillers : Array[MarchingSquaresPrefab]

func get_random_flat() -> MarchingSquaresPrefab:
	return _random(flats)
	
func get_random_diagonal() -> MarchingSquaresPrefab:
	return _random(diagonals)
	
func get_random_orthogonal() -> MarchingSquaresPrefab:
	return _random(orthogonals)
	
func get_random_filler() -> MarchingSquaresPrefab:
	return _random(fillers)
	
func _random(array: Array[MarchingSquaresPrefab]) -> MarchingSquaresPrefab:
	var i := randi_range(0, array.size()-1)
	return array[i]
