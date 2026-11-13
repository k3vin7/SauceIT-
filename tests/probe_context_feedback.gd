extends SceneTree
var failures: Array[String] = []
func _initialize() -> void:
	MayoTutorial.disabled = true
	call_deferred("run")
func check(value: bool, text: String) -> void:
	if not value:
		failures.append(text)
func run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame
	scene.set_physics_process(false)
	var hud = scene._health_hud
	hud.set_process(false)
	var scans: int = hud.pickup_scan_count
	for frame in 60:
		hud._process(1.0 / 60.0)
	check(hud.pickup_scan_count - scans <= 11, "pickup searches ran more than 10Hz")
	for i in 8:
		hud.notify_action("알림 %d" % i)
	check(hud.feedback_rows.size() == 3, "feedback queue exceeded visual budget")
	hud.notify_action("협동 처치")
	hud.notify_action("협동 처치")
	check(hud.feedback_rows.back().count == 2, "repeated feedback did not merge")
	hud._process(3.0)
	check(hud.feedback_rows.is_empty(), "expired feedback remained")
	var body = scene._local.player
	var at: Vector3 = body.global_position - scene._camera.global_basis.z * 1.5
	var tomato = scene._make_healing_tomato(at)
	scene._healing_tomatoes[12345] = {"node": tomato}
	hud._refresh_pickups()
	check(hud._pickup_target == tomato, "visible reachable tomato was not selected")
	tomato.queue_free()
	scene._healing_tomatoes.erase(12345)
	await process_frame
	hud._refresh_pickups()
	check(not is_instance_valid(hud._pickup_target), "removed pickup retained its prompt")
	var peer: int = scene._local.peer_id
	scene.apply_enemy_shake(0, PackedInt32Array([peer]), 0.0, 0.0, 2)
	check(hud.feedback_rows.size() == 1, "confirmed kill did not notify local player")
	scene.apply_enemy_shake(0, PackedInt32Array([peer + 100]), 0.0, 0.0, 2)
	check(hud.feedback_rows.back().count == 1, "another player's kill leaked into local feedback")
	check(not scene.show_key_legend, "help panel covers play area by default")
	var render := "--capture" in OS.get_cmdline_user_args()
	if render:
		hud.notify_action("협동 처치", Color("83e7c1"))
		for i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://reports/context_feedback.png")
	scene.queue_free()
	await process_frame
	if failures.is_empty():
		print("CONTEXT_FEEDBACK_OK")
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
