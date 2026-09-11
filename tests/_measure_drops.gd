extends SceneTree
func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var spacing := 0.09 if args.is_empty() else args[0].to_float()
	for shooters in [1, 2]:
		var scene = load("res://main.tscn").instantiate()
		root.add_child(scene)
		await physics_frame
		scene.set_process_unhandled_input(false)
		scene.point_spacing = spacing
		scene.maximum_point_count = roundi(192.0 * 0.09 / spacing)
		# Open floor, well clear of the walls: a strand that hits a wall paints it
		# but never lands, and so never throws droplets.
		scene._local.player.global_position = Vector3(-1.0, 0.64, 4.0)
		scene.debug_set_aim(0.0, -30.0)
		scene.debug_set_input(Vector2.ZERO, false, true)
		for extra in range(2, 2 + shooters - 1):
			var mark = scene.create_avatar(extra, 1, false)
			mark.player.global_position = Vector3(0.8 * float(extra - 1), 0.64, 4.0)
			mark.aim_pitch = deg_to_rad(-30.0)
			mark.firing = true
		var peak := 0
		var landings_before: int = scene.debug_droplet_spawns
		scene.debug_profile_enabled = true
		for _f in 240:
			await physics_frame
			peak = maxi(peak, scene._active_droplet_indices.size())
		var frames := 240.0
		print("spacing %.3f, %d shooter(s): peak live droplets %d of %d   (%.0f landings/s x %d = %.0f droplets/s, life %.2f s -> %.0f expected)" % [
			spacing, shooters, peak, scene._droplets.size(),
			float(scene.debug_droplet_spawns - landings_before) / frames * 60.0,
			scene.droplets_per_landing if "droplets_per_landing" in scene else 7,
			float(scene.debug_droplet_spawns - landings_before) / frames * 60.0 * (scene.droplets_per_landing if "droplets_per_landing" in scene else 7),
			scene.droplet_lifetime,
			float(scene.debug_droplet_spawns - landings_before) / frames * 60.0 * (scene.droplets_per_landing if "droplets_per_landing" in scene else 7) * scene.droplet_lifetime])
		scene.queue_free()
		await physics_frame
	quit(0)
