extends SceneTree
var failures: Array[String] = []
func _initialize() -> void:
	MayoTutorial.disabled = true
	call_deferred("run")
func check(ok: bool, text: String) -> void:
	if not ok: failures.append(text)
func run() -> void:
	var scene = load("res://stage_2_tomatina.tscn").instantiate()
	root.add_child(scene)
	await physics_frame
	var audited := 0
	for child in scene.get_children():
		if child is ContaminableObject and str(child.name).begins_with("Prop"):
			audited += 1
			check(not str(child.name).contains("CrushedTomatoes"), "floor smear blocks walking")
			var collider := child.get_node("WallCollision") as CollisionShape3D
			check(collider.shape is ConvexPolygonShape3D, "prop still has sharp box corners")
			if collider.shape is ConvexPolygonShape3D:
				for point in collider.shape.points:
					check(absf(point.x) <= child.size.x*0.5+0.001 and absf(point.z) <= child.size.z*0.5+0.001, "collision protrudes outside prop bounds")
	check(audited > 30,"prop audit did not cover map")
	scene.queue_free()
	await process_frame
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var floor := StaticBody3D.new()
	world.add_child(floor)
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(100,1,100)
	floor_collision.shape = floor_shape
	floor_collision.position.y = -0.5
	floor.add_child(floor_collision)
	for size in [Vector3(2.6,1.2,1.1),Vector3(7.3,2.9,3),Vector3(3,2,2.4),Vector3(3,3.2,6.4)]:
		var prop := ContaminableObject.new()
		prop.size = size
		prop.cell_size = 0.5
		prop.collision_corner_cut = 0.14
		prop.position.y = size.y*0.5
		world.add_child(prop)
		var player := MayoPlayer.new()
		player.use_injected_input = true
		player.input_move = Vector2(1,1).normalized()
		player.collision_layer = 2
		player.collision_mask = 1
		player.position = Vector3(-size.x*0.5-0.8,1.28,-size.z*0.5-0.8)
		var shape := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = MayoPlayer.CAPSULE_RADIUS
		capsule.height = MayoPlayer.CAPSULE_HEIGHT
		shape.shape = capsule
		player.add_child(shape)
		world.add_child(player)
		for frame in 180:
			# First press into the corner, then steer along its side to escape.
			if frame == 30:
				player.input_move = Vector2(0,1)
			await physics_frame
		check(player.position.z > size.z*0.5 + 0.65, "player stuck sliding around prop %s at %s" % [size,player.position])
		check(player.position.is_finite(),"invalid player position")
		player.queue_free()
		prop.queue_free()
		await process_frame
	print("audited prop colliders: ",audited)
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("PROP_COLLISION_OK")
	viewport.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
