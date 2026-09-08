extends SceneTree

# Deterministic headless CPU profile. Rendering is excluded by design; this
# measures the physics tick (engine Physics 3D + all _physics_process scripts)
# and the per-stage script breakdown.
#
#   full     - scene as shipped
#   noscript - scene scripts disabled: engine-only physics tick floor
#   stride1  - raycast_frame_stride = 1 (every point casts every frame)

var mode := "full"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		mode = args[0]
	call_deferred("_run")


func _run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame
	if mode == "stride1":
		scene.raycast_frame_stride = 1
	if mode == "nojitter":
		scene.speed_magnitude_jitter = 0.0
	if mode == "noscript":
		scene.set_physics_process(false)
		scene.set_process(false)

	# Aim straight down -Z, level. There is no cursor to warp any more.
	scene.debug_set_aim(0.0, 0.0)
	Input.action_press("fire_mayo")
	for _f in 120:
		await physics_frame
	scene.debug_reset_profile()
	scene.debug_profile_enabled = true

	var phys_us := 0
	var n := 0
	var max_points_live := 0
	var sum_points := 0
	Input.action_press("move_right")
	for frame in 480:
		if frame == 160:
			Input.action_release("move_right")
			Input.action_press("move_left")
		if frame == 320:
			Input.action_release("move_left")
			Input.action_press("move_right")
		var t := Time.get_ticks_usec()
		await physics_frame
		phys_us += Time.get_ticks_usec() - t
		n += 1
		max_points_live = maxi(max_points_live, scene._points.size())
		sum_points += scene._points.size()
	Input.action_release("fire_mayo")
	Input.action_release("move_right")
	scene.debug_profile_enabled = false

	var pf: int = maxi(scene.debug_profile_frames, 1)
	print("R mode=%-9s tick_ms=%.3f script_ms=%.3f max_points=%d mean_points=%.1f rays_per_frame=%.2f paint=%d uploads=%d emit=%.3f pts=%.3f cons=%.3f ribbon=%.3f" % [
		mode,
		float(phys_us) / n * 0.001,
		float(scene.debug_timings_us.total) / pf * 0.001,
		max_points_live,
		float(sum_points) / n,
		float(scene.debug_raycast_count) / pf,
		scene._floor.debug_paint_calls,
		scene._floor.debug_texture_uploads,
		float(scene.debug_timings_us.emit_follow) / pf * 0.001,
		float(scene.debug_timings_us.point_physics) / pf * 0.001,
		float(scene.debug_timings_us.constraint) / pf * 0.001,
		float(scene.debug_timings_us.ribbon_update) / pf * 0.001,
	])
	quit(0)
