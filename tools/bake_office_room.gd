extends SceneTree

## Regenerate after editing the office in the editor:
## godot --headless --path . --script res://tools/bake_office_room.gd
const SOURCE := "res://maps/command.tscn"
const DESTINATION := "res://maps/command_runtime.scn"
const KEEP_PATHS := ["MapScreen/Screen", "Locker/Body", "SlotMachine/Upper"]


func _initialize() -> void:
	call_deferred("_bake")


func _bake() -> void:
	var office := (load(SOURCE) as PackedScene).instantiate() as Node3D
	root.add_child(office)
	await process_frame
	var groups := {}
	for node in office.find_children("*", "CSGShape3D", true, false):
		var shape := node as CSGShape3D
		if not shape.is_root_shape():
			continue
		var mesh := shape.bake_static_mesh()
		if mesh == null or mesh.get_surface_count() == 0:
			push_error("Cannot bake office shape %s" % office.get_path_to(shape))
			quit(1)
			return
		var parent := shape.get_parent() as Node3D
		var slot_part := parent.name == &"SlotMachine" and (
			str(shape.name).begins_with("Symbol") or str(shape.name).begins_with("Bulb")
			or str(shape.name).begins_with("Lever"))
		var separate := shape.use_collision or slot_part or not shape.visible \
			or shape.get_child_count() > 0 or str(office.get_path_to(shape)) in KEEP_PATHS
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface)
			if material is BaseMaterial3D and material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				separate = true
			if material is ShaderMaterial and material.shader.code.contains("ALPHA"):
				separate = true
		if separate:
			_replace_shape(office, parent, shape, mesh)
		else:
			var surfaces: Dictionary = groups.get_or_add(parent, {})
			for index in mesh.get_surface_count():
				var material := mesh.surface_get_material(index)
				if not surfaces.has(material):
					var builder := SurfaceTool.new()
					builder.begin(Mesh.PRIMITIVE_TRIANGLES)
					builder.set_material(material)
					surfaces[material] = builder
				surfaces[material].append_from(mesh, index, shape.transform)
			shape.free()
	for parent: Node3D in groups:
		var batch_mesh := ArrayMesh.new()
		for builder: SurfaceTool in groups[parent].values():
			builder.commit(batch_mesh)
		var batch := MeshInstance3D.new()
		batch.name = "BakedDecor"
		batch.mesh = batch_mesh
		parent.add_child(batch)
		batch.owner = office
	var scene := PackedScene.new()
	var error := scene.pack(office)
	if error == OK:
		error = ResourceSaver.save(scene, DESTINATION, ResourceSaver.FLAG_COMPRESS)
	if error == OK:
		print("OFFICE_ROOM_BAKED ", DESTINATION)
	else:
		push_error("Could not save the baked office: %s" % error_string(error))
	office.queue_free()
	await process_frame
	quit(0 if error == OK else 1)


func _replace_shape(office: Node3D, parent: Node3D, shape: CSGShape3D, mesh: ArrayMesh) -> void:
	var replacement := MeshInstance3D.new()
	replacement.name = shape.name
	replacement.transform = shape.transform
	replacement.visible = shape.visible
	replacement.cast_shadow = shape.cast_shadow
	replacement.mesh = mesh
	replacement.material_override = shape.material_override
	var collision_shape: Shape3D
	if shape.use_collision:
		if shape is CSGBox3D and shape.get_child_count() == 0:
			var box := BoxShape3D.new()
			box.size = shape.size
			collision_shape = box
		else:
			collision_shape = shape.bake_collision_shape()
		var body := StaticBody3D.new()
		body.collision_layer = shape.collision_layer
		body.collision_mask = shape.collision_mask
		body.collision_priority = shape.collision_priority
		replacement.add_child(body)
		var collider := CollisionShape3D.new()
		collider.shape = collision_shape
		body.add_child(collider)
	parent.remove_child(shape)
	parent.add_child(replacement)
	replacement.owner = office
	for child in replacement.find_children("*", "", true, false):
		child.owner = office
	for child in shape.get_children():
		# CSG descendants have already been baked into the replacement mesh.
		if child is CSGShape3D:
			continue
		shape.remove_child(child)
		replacement.add_child(child)
		child.owner = office
	shape.free()
