extends SceneTree
const Boss = preload("res://scripts/tomatina_press_king.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(11, 7, 13)
	camera.look_at(Vector3(0, 2.0, 0))
	camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50,-30,0)
	world.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("34444d")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.6
	world.add_child(environment)
	var boss = Boss.new()
	world.add_child(boss)
	boss.build_press_king(0.1,0.2)
	boss.position.y = boss.stand_height()
	boss.health = 0
	boss.act = Boss.Act.DEATH
	boss._update_presentation()
	boss.set_process(false)
	var index := 0
	for time in [0.05,0.45,0.95,1.5]:
		boss._update_death_burst(time)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://reports/boss_death_%d.png" % index)
		index += 1
	print("BOSS_DEATH_CAPTURE_OK")
	quit()
