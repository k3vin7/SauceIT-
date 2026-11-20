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
	await process_frame
	var intro = scene._boss_entrance
	check(intro != null, "entrance was not built")
	var spawn: Vector3 = intro.spawn_point()
	scene._player.position = TomatinaMap.at_cell(Vector2(29,35)) + Vector3.UP * 1.28
	scene._update_camera()
	intro.start(spawn)
	intro.set_process(false)
	check(intro.active and scene._player.frozen and not scene._input_enabled, "cutscene did not freeze input")
	var health: float = scene._player.health
	scene._damage_player(scene._player,30.0)
	check(scene._player.health == health, "player took cutscene damage")
	var capture := "--capture" in OS.get_cmdline_user_args()
	if capture:
		scene.process_mode = Node.PROCESS_MODE_DISABLED
	var index := 0
	for time in [0.1,0.35,0.7,1.6,2.4,3.8,5.6]:
		scene._update_camera()
		intro.present(time)
		check(scene._camera.global_transform.is_finite(), "invalid cutscene camera")
		if is_equal_approx(time,0.35):
			check(intro.blackout.modulate.a > 0.99, "camera cut was not covered by blackout")
			var shot_to_wall: Vector3 = (intro.wall_at + Vector3(0,3.5,0) - scene._camera.global_position).normalized()
			check((-scene._camera.global_basis.z).dot(shot_to_wall) > 0.999,
				"entrance camera was not square to the wall")
			check(absf(scene._camera.global_position.z-intro.wall_at.z) < 0.001,
				"entrance camera still viewed the boss from the side")
		if is_equal_approx(time,0.7):
			check(intro.blackout.modulate.a < 0.5, "blackout did not reveal the frontal wall shot")
		if capture:
			await process_frame
			scene._update_camera()
			intro.present(time)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://reports/boss_intro_%d.png" % index)
		index += 1
	check(intro.actor.visible and intro.title.modulate.a < 0.01, "intro phases failed")
	check(not intro.wall_skins[0].visible and not intro.wall_skins[1].visible,
		"seam-hiding wall skin remained after the breach")
	check(not intro.house_details[0].visible,
		"house facade details remained floating after the breach")
	intro.finish()
	check(not intro.active and scene._input_enabled and not scene._player.frozen, "cutscene did not restore input")
	check(not intro.layer.visible, "name card remained after cutscene")
	intro.start(spawn)
	check(not intro.active, "duplicate event restarted cutscene")
	intro.reset_intro()
	check(not intro.played, "checkpoint did not reset intro")
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("BOSS_ENTRANCE_OK")
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
