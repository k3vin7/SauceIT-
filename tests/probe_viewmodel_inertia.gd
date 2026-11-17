extends SceneTree
func _initialize() -> void:
	MayoTutorial.disabled = true
	call_deferred("run")
func run() -> void:
	var world = load("res://stage_2_tomatina.tscn").instantiate()
	root.add_child(world)
	var shooter = world._local
	shooter.bottle_pickup_left = 0.0
	shooter.bottle_kick = 1.0
	shooter.bottle_pressure = 1.0
	shooter.sway_pitch = 0.1
	shooter.sway_yaw = 0.1
	shooter.was_firing = true
	world._apply_nozzle_sway(shooter)
	assert(shooter.weapon_sway.transform == Transform3D.IDENTITY, "legacy firing sway remains")
	shooter.bottle_shake_pose = 1.0
	shooter.bottle_shake_show = 1.0
	world._apply_nozzle_sway(shooter)
	assert(shooter.weapon_sway.transform != Transform3D.IDENTITY, "intentional shaking removed")
	var motion = world._viewmodel_inertia
	shooter.player.velocity = Vector3.ZERO
	for frame in 60:
		motion.advance(1.0 / 60, shooter, true, 1.0)
	assert(motion.pose == Transform3D.IDENTITY, "standing fire has inertia")
	world.queue_free()
	await process_frame
	print("VIEWMODEL_INERTIA_OK")
	quit()