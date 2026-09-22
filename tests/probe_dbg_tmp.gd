extends SceneTree
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame
	scene.debug_clear_enemies()
	scene.set_process_unhandled_input(false)
	var p: MayoPlayer = scene._player
	var f: FloorContamination = scene._floor
	p.global_position = Vector3(0.0, scene.spawn_position_for(0).y, 3.0)
	await physics_frame
	# Same patch the probe paints.
	var patch := Vector3(p.global_position.x, 0.0, p.global_position.z - 1.2)
	var passes := ceili(float(f.slip_thickness)/float(maxi(f.thickness_per_splat,1))) + 4
	for _pass in passes:
		for i in range(-2, 3):
			f.paint_mayo(patch + Vector3(float(i)*0.1, 0.0, 0.0))
			f.paint_mayo(patch + Vector3(0.0, 0.0, float(i)*0.1))
	print("patch thickness %d, slippery=%s" % [f.thickness_at(patch), str(f.is_slippery_at(patch))])
	scene.debug_input_override = true
	scene.debug_set_input(Vector2(0.0, -1.0), true, false)
	var seq := []
	var last := -1
	var run := 0
	for _fr in 260:
		await physics_frame
		if p.state != last:
			if last >= 0:
				seq.append("%d x%d" % [last, run])
			last = p.state
			run = 0
		run += 1
	seq.append("%d x%d" % [last, run])
	print("state sequence (0=normal 1=stumble 2=fall 3=down 4=standup): %s" % str(seq))
	print("ended at %.2v, still slippery there=%s" % [p.global_position, str(f.is_slippery_at(p.global_position))])
	quit(0)
