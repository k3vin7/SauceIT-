extends SceneTree
func _initialize() -> void:
	MayoTutorial.disabled = true
	call_deferred("run")

func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	var world = load("res://stage_2_tomatina.tscn").instantiate()
	root.add_child(world)
	await process_frame
	world.set_physics_process(false)
	world.set_process(false)
	world._local.player.frozen = true
	world.set_first_person(true)
	world._view_layout = Rect2()
	world._layout_view()
	var team = preload("res://scripts/player_bot_team.gd").new()
	world.add_child(team)
	team.configure(world, false)
	team.set_physics_process(false)
	team._update_hud()
	for peer in world._shooters:
		if world._shooters[peer] != world._local:
			world._shooters[peer].player.hide()
	var animation = preload("res://scripts/viewmodel_animation.gd").new()
	world.add_child(animation)
	world._viewmodel_animation = animation
	world._viewmodel_inertia.reset()
	var label := Label.new()
	label.position = Vector2(850, 32)
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_outline_size", 6)
	world._hud_layer.add_child(label)
	var sheet := Image.create(1280, 1080, false, Image.FORMAT_RGB8)
	var clips := ["idle", "fire_start", "shake_loop", "jump", "land", "run"]
	DirAccess.make_dir_recursive_absolute("res://reports/viewmodel_preview_frames")
	for index in clips.size():
		var clip: String = clips[index]
		animation.reset()
		world._local.bottle_shake_pose = 1.0 if clip == "shake_loop" else 0.0
		world._local.bottle_shake_show = 0.0
		world._apply_nozzle_sway(world._local)
		var player: AnimationPlayer = animation.action_player if clip in ["fire_start", "shake_loop"] else animation.movement_player
		player.play(clip)
		player.seek(animation.LIBRARY.get_animation(clip).length * 0.34, true)
		player.pause()
		animation.pose = animation.movement.transform * animation.action.transform
		world._place_viewmodel()
		world._update_camera()
		world._sync_camera_viewmodel()
		label.text = clip
		for frame in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var shot := root.get_texture().get_image()
		shot.save_png("res://reports/viewmodel_%s.png" % clip)
		shot.resize(640, 360)
		shot.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(shot, Rect2i(0, 0, 640, 360), Vector2i((index % 2) * 640, (index / 2) * 360))
		for sample in 16:
			player.seek(animation.LIBRARY.get_animation(clip).length * sample / 16.0, true)
			animation.pose = animation.movement.transform * animation.action.transform
			world._sync_camera_viewmodel()
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://reports/viewmodel_preview_frames/frame_%03d.png" % (index * 16 + sample))
	sheet.save_png("res://reports/viewmodel_animation_sheet.png")
	print("VIEWMODEL_ANIMATION_CAPTURE_OK")
	quit()
