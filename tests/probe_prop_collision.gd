extends SceneTree
var failures: Array[String] = []
func _initialize() -> void:
	MayoTutorial.disabled = true
	call_deferred("run")
func check(ok: bool, text: String) -> void:
	if not ok: failures.append(text)
func run() -> void:
	var edited_prop := TomatinaMapProp.new()
	var wall := TomatinaMapWall.new()
	edited_prop.size = Vector3(2, 2, 4)
	wall.size = edited_prop.size
	var basis := Basis(Vector3.UP, PI * 0.5) * Basis.from_scale(Vector3(2, 1.5, 0.5))
	var placement := Transform3D(basis, Vector3(4, 5, 6))
	for box: Dictionary in [edited_prop.to_box(placement), wall.to_box(placement)]:
		check((box.size as Vector3).is_equal_approx(Vector3(2, 3, 4))
			and (box.position as Vector3).is_equal_approx(Vector3(4, 6.5, 6)),
			"an edited collider lost its scale or rotated footprint")
	edited_prop.free()
	wall.free()
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
	var first: int = scene.get_child_count()
	scene._fill_narrow_slots([
		{"size": Vector3(2, 2, 2), "position": Vector3(2000, 6, 0)},
		{"size": Vector3(2, 2, 2), "position": Vector3(2003, 6, 0)},
	])
	check(scene.get_child_count() == first + 1, "the elevated gap did not get a single filler")
	if scene.get_child_count() == first + 1:
		var fill := scene.get_child(first) as StaticBody3D
		var shape := (fill.get_child(0) as CollisionShape3D).shape as BoxShape3D
		check(is_equal_approx(fill.position.y - shape.size.y * 0.5, 5.0),
			"the gap filler blocks the passage below raised props")
	var origin := Vector3(2000, 30, 0)
	var velocity := Vector3(24, 0, 0)
	var space: PhysicsDirectSpaceState3D = scene.get_world_3d().direct_space_state
	var clear_arc: Array[Vector3] = scene.play_support._mortar_path(origin, velocity, origin, 9.8, 2.0, 1.0 / 60.0, space)
	var blocker := CharacterBody3D.new()
	blocker.position = origin + Vector3(4, 0, 0)
	var blocker_collision := CollisionShape3D.new()
	blocker_collision.shape = BoxShape3D.new()
	blocker.add_child(blocker_collision)
	scene.add_child(blocker)
	await physics_frame
	var blocked_arc: Array[Vector3] = scene.play_support._mortar_path(origin, velocity, origin, 9.8, 2.0, 1.0 / 60.0, space)
	check(blocked_arc.back().x < origin.x + 4.1 and clear_arc.back().x > origin.x + 10.0,
		"the cached mortar guide ignored a new moving collider")
	blocker.position.z += 5.0
	await physics_frame
	var open_arc: Array[Vector3] = scene.play_support._mortar_path(origin, velocity, origin, 9.8, 2.0, 1.0 / 60.0, space)
	check(open_arc == clear_arc, "the mortar guide kept a stale moving collision")
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
