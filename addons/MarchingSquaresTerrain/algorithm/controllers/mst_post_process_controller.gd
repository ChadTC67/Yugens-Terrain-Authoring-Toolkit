extends RefCounted
class_name MSTPostProcessController

var terrain


func _init(terrain_owner) -> void:
	terrain = terrain_owner


func rebuild(refresh_chunks: bool = true) -> void:
	if terrain == null:
		return
	if terrain.terrain_material != null:
		terrain.terrain_material.next_pass = _build_chain(MarchingSquaresPostProcessEffect.Target.TERRAIN)
	if terrain.grass_mesh != null and terrain.grass_mesh.material != null:
		terrain.grass_mesh.material.next_pass = _build_chain(MarchingSquaresPostProcessEffect.Target.GRASS)
	if refresh_chunks and terrain.is_inside_tree() and terrain.has_method("refresh_chunk_surface_materials"):
		terrain.refresh_chunk_surface_materials()


func _build_chain(target: int) -> Material:
	var head: Material = null
	var tail: Material = null
	for array_name in ["surface_effects", "overlay_effects"]:
		var effects: Array = terrain.get(array_name)
		for effect in effects:
			if not (effect is MarchingSquaresPostProcessEffect) or not effect.enabled or not effect.has_source():
				continue
			if effect.target != MarchingSquaresPostProcessEffect.Target.BOTH and effect.target != target:
				continue
			var material: Material = effect.build_runtime_material()
			if material == null:
				continue
			material.next_pass = null
			if head == null:
				head = material
			else:
				tail.next_pass = material
			tail = material
	return head
