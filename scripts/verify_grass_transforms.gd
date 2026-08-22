extends SceneTree

const GRASS_PLANTER_SCRIPT := preload("res://addons/MarchingSquaresTerrain/algorithm/grass/marching_squares_grass_planter.gd")
const GRASS_SHADER := preload("res://addons/MarchingSquaresTerrain/resources/shaders/mst_grass.gdshader")


func _initialize() -> void:
	_verify.call_deferred()


func _verify() -> void:
	var hidden_transform := GRASS_PLANTER_SCRIPT._get_hidden_grass_transform()
	assert(not is_zero_approx(hidden_transform.basis.determinant()))
	assert(hidden_transform.origin.y < 0.0)

	var shader_code := GRASS_SHADER.code
	assert(shader_code.contains("VERTEX * model_scale"))
	assert(shader_code.contains("length(MODEL_MATRIX[0].xyz)"))

	print("Grass transform verification passed")
	quit()
