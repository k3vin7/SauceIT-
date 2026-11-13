extends SceneTree
var failures: Array[String] = []
func _initialize() -> void:
	MayoTutorial.disabled = true
	call_deferred("run")
func run() -> void:
	var scene = load("res://stage_2_tomatina.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_first_person(true)
	var max_error := 0.0
	var resting := Transform3D()
	for running in [false, true]:
		scene.debug_set_input(Vector2(0, -1), running, false)
		var start := Time.get_ticks_msec()
		var first := true
		while Time.get_ticks_msec() - start < 1800:
			await RenderingServer.frame_post_draw
			var shooter = scene._local
			var relative: Transform3D = scene._camera.global_transform.affine_inverse() * shooter.weapon_sway.global_transform
			if first:
				resting = relative
				first = false
			max_error = maxf(max_error, relative.origin.distance_to(resting.origin))
			if shooter.weapon_sway.get_parent() != shooter.camera_viewmodel:
				failures.append("bottle visual still under physics body")
			if shooter.first_person_arms.get_parent() != scene._camera:
				failures.append("arms still under physics body")
			if shooter.viewmodel_muzzle.get_parent() != shooter.weapon:
				failures.append("authoritative muzzle detached")
	if max_error > 0.0001:
		failures.append("camera-relative bottle drift: %f" % max_error)
	root.get_texture().get_image().save_png("res://reports/bottle_stable_walk_run.png")
	# Switching cameras must hide the detached viewmodel, not leave a floating bottle.
	scene.set_first_person(false)
	await RenderingServer.frame_post_draw
	if scene._local.camera_viewmodel.visible:
		failures.append("first-person bottle visible in third person")
	print("maximum walk/run camera-relative drift (m): ", max_error)
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("BOTTLE_STABILITY_OK")
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
