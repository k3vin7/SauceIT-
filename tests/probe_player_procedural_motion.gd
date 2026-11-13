extends SceneTree
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	for variant in 4:
		scene.set_character_variant(scene._local.peer_id, variant)
		await process_frame
		var motion = scene._local.procedural_motion
		if motion == null:
			failures.append("missing modifier %d" % variant)
			continue
		for label in ["LeftArm", "RightArm", "LeftFoot", "RightFoot", "SauceTubeSocket"]:
			if motion.bones.get(label, -1) < 0:
				failures.append("missing %s on %d" % [label, variant])
		var rig: Skeleton3D = motion.get_skeleton()
		var upper: int = motion.bones["RightArm"]
		var middle: int = motion.bones["RightForeArm"]
		var tip: int = motion.bones["RightHand"]
		var a := rig.get_bone_global_pose(upper).origin
		var b := rig.get_bone_global_pose(middle).origin
		var c := rig.get_bone_global_pose(tip).origin
		var length_a := a.distance_to(b)
		var length_b := b.distance_to(c)
		var target := a + Vector3(0.1, -0.3, 0.2).normalized() * (length_a + length_b) * 0.75
		motion._solve("RightArm", "RightForeArm", "RightHand", rig.global_transform * target, Vector3.RIGHT)
		var solved := rig.get_bone_global_pose(tip).origin
		if solved.distance_to(target) > 0.01:
			failures.append("hand missed reachable target on %d" % variant)
		if absf(rig.get_bone_global_pose(upper).origin.distance_to(rig.get_bone_global_pose(middle).origin) - length_a) > 0.01:
			failures.append("upper arm stretched on %d" % variant)
		motion.reach_for(scene._local.player.global_position + Vector3(0.4, 0.0, -0.8))
		for frame in 35:
			scene._local.was_firing = frame < 12
			motion._process_modification()
			var skeleton: Skeleton3D = motion.get_skeleton()
			for bone in skeleton.get_bone_count():
				if not skeleton.get_bone_global_pose(bone).is_finite():
					failures.append("nonfinite pose %d" % variant)
			await process_frame

	if failures.is_empty():
		print("PROCEDURAL_MOTION_OK")
	else:
		for failure in failures:
			push_error(failure)
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
