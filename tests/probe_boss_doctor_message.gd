extends SceneTree
func _initialize() -> void:
	MayoTutorial.disabled = true
	call_deferred("run")
func run() -> void:
	var world = load("res://stage_2_tomatina.tscn").instantiate()
	root.add_child(world)
	await process_frame
	var message = world._hud_layer.get_node("BossDoctorMessage")
	assert(not message.visible)
	var index = world.tutorial_spawn_enemy(MayoTutorial.KIND_PRESS_KING, TomatinaMap.at_cell(Vector2(23.5,29.5)))
	world._input_enabled = false
	message._process(0.1)
	assert(not message.visible and message.seen_boss_id == 0)
	world._input_enabled = true
	message._process(0.1)
	assert(message.visible and message.remaining > 9)
	message._process(11)
	assert(not message.visible)
	message._process(0.1)
	assert(not message.visible)
	world._press_king.health = 0
	message._process(0.1)
	assert(not message.visible)
	world.queue_free()
	await process_frame
	print("BOSS_DOCTOR_MESSAGE_OK")
	quit()
