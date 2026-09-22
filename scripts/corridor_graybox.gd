class_name CorridorGraybox
extends Node3D

## Minimum plan distance from a LoD2 building envelope to either selected
## centreline.  Buildings farther away are kept in the Row3 group but hidden
## and never receive a collision body.
@export_range(5.0, 100.0, 1.0, "suffix:m") var corridor_distance_m := 45.0:
	set(value):
		corridor_distance_m = value
		if is_node_ready():
			call_deferred("_apply_corridor")
@export var generate_collisions := true

var inside_building_count := 0
var row3_building_count := 0


func _ready() -> void:
	visible = true
	_apply_corridor()
	if generate_collisions:
		_ensure_terrain_collision()


func _apply_corridor() -> void:
	inside_building_count = 0
	row3_building_count = 0
	for building in _mesh_instances($Buildings):
		var distance := _distance_from_name(building.name)
		if distance <= corridor_distance_m:
			inside_building_count += 1
			building.visible = true
			if building.is_in_group("Row3"):
				building.remove_from_group("Row3")
			if generate_collisions:
				_ensure_mesh_collision(building)
		else:
			row3_building_count += 1
			building.visible = false
			building.add_to_group("Row3")
			_remove_mesh_collisions(building)


func _mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		result.push_back(root as MeshInstance3D)
	for child in root.get_children():
		result.append_array(_mesh_instances(child))
	return result


func _distance_from_name(node_name: StringName) -> float:
	var text := String(node_name)
	var marker := text.rfind("_d")
	if marker < 0:
		return INF
	return float(text.substr(marker + 2).replace("p", "."))


func _ensure_mesh_collision(mesh_instance: MeshInstance3D) -> void:
	for child in mesh_instance.get_children():
		if child is StaticBody3D:
			return
	mesh_instance.create_trimesh_collision()


func _remove_mesh_collisions(mesh_instance: MeshInstance3D) -> void:
	for child in mesh_instance.get_children():
		if child is StaticBody3D:
			child.free()


func _ensure_terrain_collision() -> void:
	for terrain_mesh in _mesh_instances($Terrain):
		_ensure_mesh_collision(terrain_mesh)


func collision_body_count() -> int:
	return _collision_body_count_under(self)


func _collision_body_count_under(root: Node) -> int:
	var count := 1 if root is StaticBody3D else 0
	for child in root.get_children():
		count += _collision_body_count_under(child)
	return count
