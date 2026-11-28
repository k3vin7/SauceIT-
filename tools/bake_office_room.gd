extends SceneTree

## Regenerate after editing the office in the editor:
## godot --headless --path . --script res://tools/bake_office_room.gd
const SOURCE := "res://maps/command.tscn"
const DESTINATION := "res://maps/command_runtime.scn"
const KEEP_PATHS := ["MapScreen/Screen", "Locker/Body", "SlotMachine/Upper",
	"ShowerBooth/Curtain", "ShowerBooth/ShowerHead"]
## The baked room carries a list of its boxes under this metadata key, for the
## firing range to lay sauce on (`PracticeRange.walls`): [transform, size, solid]
## per box, `solid` being whether a body is stopped by it.
const SAUCE_BOXES := "sauce_boxes"
## Too small to show a splat, or round enough that a box around it would hang
## paint in the air.
const SAUCE_MIN_SIDE := 0.15
const SAUCE_MAX_RADIUS := 0.25
## Things that move after the bake, or are not things at all.
const SAUCE_SKIP := ["ShowerBooth/Curtain", "ShowerBooth/ShowerHead", "DoctorHologram", "Locker/Door",
	"SlotMachine/Symbol", "SlotMachine/Bulb", "SlotMachine/Lever"]


func _initialize() -> void:
	call_deferred("_bake")


func _bake() -> void:
	var office := (load(SOURCE) as PackedScene).instantiate() as Node3D
	root.add_child(office)
	await process_frame
	office.set_meta(SAUCE_BOXES, _sauce_boxes(office))
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


## Every box in the room that sauce can be shown on, in the room's own space.
## Floors are left out: the range's floor grid already covers them.
func _sauce_boxes(office: Node3D) -> Array:
	var boxes: Array = []
	for node in office.find_children("*", "CSGShape3D", true, false):
		var shape := node as CSGShape3D
		var path := str(office.get_path_to(shape))
		if not shape.is_root_shape() or not shape.is_visible_in_tree() or shape.get_child_count() > 0 \
				or str(shape.name).begins_with("Floor"):
			continue
		var skipped := false
		for prefix: String in SAUCE_SKIP:
			if path.begins_with(prefix):
				skipped = true
		var material := shape.material_override
		if material == null and shape is CSGPrimitive3D:
			material = shape.get("material")
		if material is BaseMaterial3D and material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			skipped = true
		if material is ShaderMaterial and material.shader.code.contains("ALPHA"):
			skipped = true
		if skipped:
			continue
		var size := Vector3.ZERO
		if shape is CSGBox3D:
			size = (shape as CSGBox3D).size
		elif shape is CSGCylinder3D and (shape as CSGCylinder3D).radius <= SAUCE_MAX_RADIUS:
			var cylinder := shape as CSGCylinder3D
			size = Vector3(cylinder.radius * 2.0, cylinder.height, cylinder.radius * 2.0)
		else:
			continue
		var place := office.global_transform.affine_inverse() * shape.global_transform
		size *= place.basis.get_scale()
		var sides := [size.x, size.y, size.z]
		sides.sort()
		if sides[1] < SAUCE_MIN_SIDE:
			continue
		boxes.append([Transform3D(place.basis.orthonormalized(), place.origin), size, shape.use_collision])
	return boxes


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
