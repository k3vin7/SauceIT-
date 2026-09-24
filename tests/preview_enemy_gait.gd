extends Node3D

const OUTPUT_DIR := "res://reports/gait_preview"
const FRAME_COUNT := 24

var _enemy: MayoEnemy
var _frame := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))

	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("d6d9de")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = 0.7
	environment.environment = settings
	add_child(environment)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52.0, -32.0, 0.0)
	light.light_energy = 1.4
	light.shadow_enabled = true
	add_child(light)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(16.0, 16.0)
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("777b82")
	ground_material.roughness = 0.92
	plane.material = ground_material
	ground.mesh = plane
	add_child(ground)

	var camera := Camera3D.new()
	# Side-on makes the palm plane and elbow loading readable. A three-quarter
	# view hides the far hand's fingers behind its palm and can make a correct
	# flat contact look like a clenched fist.
	camera.position = Vector3(7.2, 2.9, 0.0)
	camera.look_at_from_position(camera.position, Vector3(0.0, 1.55, 0.0))
	camera.fov = 46.0
	add_child(camera)
	camera.current = true

	_enemy = MayoEnemy.new()
	_enemy.authority = false
	_enemy.set_physics_process(false)
	add_child(_enemy)
	_enemy.build(0.1, 0.2, Color("4d3f6b"))
	_enemy.position = Vector3(0.0, _enemy.stand_height(), 0.9)
	_enemy._set_locomotion_animation(true)
	_enemy._gait.strength = 1.0

	# Let imported materials, skinning and the modifier settle before sampling.
	for _wait in 4:
		await get_tree().process_frame
	await _capture_cycle()
	get_tree().quit()


func _capture_cycle() -> void:
	var stride: float = _enemy._gait.stride_in_use()
	for index in FRAME_COUNT:
		var phase := float(index) / float(FRAME_COUNT)
		_enemy._ground_covered = phase * stride
		_enemy._gait.phase = phase
		_enemy.position.z = 0.9 - phase * stride
		var clip := _enemy._animation_player.get_animation(_enemy._walk_animation)
		_enemy._animation_player.seek(phase * clip.length, true)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		image.resize(960, 540, Image.INTERPOLATE_LANCZOS)
		image.save_png(ProjectSettings.globalize_path(
			"%s/frame_%02d.png" % [OUTPUT_DIR, index]))
