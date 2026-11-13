extends Node3D
## Deterministic six-second introduction; visual debris never enters physics.
const DURATION := 6.2
const BREAK_TIME := 2.1
var world
var active := false
var played := false
var elapsed := 0.0
var spawn_at := Vector3.ZERO
var wall_at := Vector3.ZERO
var actor: Node3D
var rig: AnimationPlayer
var chunks: Array[MeshInstance3D] = []
var chunk_rests: Array[Vector3] = []
var removed_instances: Array[Dictionary] = []
var facade: Node3D
var dust: CPUParticles3D
var layer: CanvasLayer
var title: Label
var subtitle: Label
var top_bar: ColorRect
var bottom_bar: ColorRect
var start_camera := Transform3D.IDENTITY
var frozen_before := {}
var input_before := true
var hud_before := true
var prior_fov := 75.0

func configure(owner_world) -> void:
	world = owner_world
	name = "PressKingEntrance"
	process_priority = 100
	wall_at = Vector3(world._plaza_rect.position.x + 0.12, 0.0, world._plaza_rect.get_center().y)
	var best_gap := -1.0
	for row in [25.5,27.5,29.5,31.5]:
		var candidate := Vector3(wall_at.x,0,TomatinaMap.at_cell(Vector2(20,row)).z)
		var gap := INF
		for truck in TomatinaMap.parked_trucks():
			var at: Vector3 = truck.position
			gap = minf(gap, candidate.distance_squared_to(at))
		if gap > best_gap:
			best_gap = gap
			wall_at = candidate
	_build_facade()
	_build_titles()
	set_process(false)

func _box(parent: Node3D, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = at
	parent.add_child(mesh)
	return mesh

func _material(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.95
	return result

func _build_facade() -> void:
	facade = Node3D.new()
	facade.name = "BreakablePlazaWall"
	add_child(facade)
	facade.position = wall_at
	var plaster := _material(Color("d4ad7e"))
	var brick := _material(Color("9b5940"))
	var darkness := _material(Color("161512"))
	# Permanent opening, pillars and broken masonry remain after the scene.
	_box(facade, Vector3(-0.18, 3.6, 0), Vector3(0.2, 7.2, 8.4), darkness)
	for z in [-4.7,4.7]:
		_box(facade, Vector3(0, 4.2, z), Vector3(0.8, 8.4, 1.0), plaster)
	_box(facade, Vector3(0, 7.7, 0), Vector3(0.9, 1.0, 8.5), brick)
	for row in 5:
		for column in 6:
			var at := Vector3(0.2, 0.72 + row * 1.38, -3.5 + column * 1.4)
			var mesh := _box(facade, at, Vector3(0.5, 1.36, 1.38), plaster if row > 0 else brick)
			chunks.append(mesh)
			chunk_rests.append(at)
	dust = CPUParticles3D.new()
	dust.one_shot = true
	dust.explosiveness = 0.92
	dust.amount = 45
	dust.lifetime = 1.7
	dust.emitting = false
	dust.direction = Vector3.RIGHT
	dust.spread = 65.0
	dust.initial_velocity_min = 3.0
	dust.initial_velocity_max = 8.0
	dust.gravity = Vector3(0,-2,0)
	dust.scale_amount_min = 0.4
	dust.scale_amount_max = 1.2
	var puff := SphereMesh.new()
	puff.radius = 0.4
	puff.height = 0.8
	puff.radial_segments = 8
	puff.rings = 4
	puff.material = _material(Color("aa967d"))
	dust.mesh = puff
	dust.position = wall_at + Vector3(0.4,3,0)
	add_child(dust)

func _build_titles() -> void:
	layer = CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	for upper in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(bar)
		if upper: top_bar = bar
		else: bottom_bar = bar
	title = Label.new()
	title.text = "토마토 압착왕"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color("fff0d3"))
	title.add_theme_color_override("font_shadow_color", Color.BLACK)
	title.add_theme_constant_override("shadow_offset_y", 3)
	layer.add_child(title)
	subtitle = Label.new()
	subtitle.text = "광장을 짓누르는 붉은 폭군"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 19)
	subtitle.add_theme_color_override("font_color", Color("eda064"))
	layer.add_child(subtitle)
	layer.hide()

func start(at: Vector3) -> void:
	if played or active:
		return
	played = true
	active = true
	elapsed = 0.0
	spawn_at = at
	start_camera = world._camera.global_transform
	prior_fov = world._camera.fov
	input_before = world._input_enabled
	world._input_enabled = false
	if is_instance_valid(world._hud_layer):
		hud_before = world._hud_layer.visible
		world._hud_layer.hide()
	for shooter in world._shooters.values():
		frozen_before[shooter.peer_id] = shooter.player.frozen
		shooter.player.frozen = true
		shooter.player.velocity = Vector3.ZERO
		shooter.firing = false
		shooter.was_firing = false
	actor = world.PressKing.make_visual()
	actor.name = "EntranceBossVisual"
	add_child(actor)
	actor.hide()
	rig = world.PressKing.rig_player(actor)
	layer.show()
	set_process(true)

func _remove_old_wall() -> void:
	var art: Node = world.get_node_or_null("TomatinaVillageArt")
	if art == null:
		return
	for batch in art.get_children():
		if not batch is MultiMeshInstance3D or not str(batch.name).begins_with("BoundaryWall"):
			continue
		for index in batch.multimesh.instance_count:
			var pose: Transform3D = batch.multimesh.get_instance_transform(index)
			var at: Vector3 = batch.global_transform * pose.origin
			if absf(at.x - wall_at.x) < 2.0 and absf(at.z - wall_at.z) < 5.0:
				removed_instances.append({"batch": batch, "index": index, "pose": pose})
				batch.multimesh.set_instance_transform(index, Transform3D(Basis().scaled(Vector3.ZERO), pose.origin))

func _process(delta: float) -> void:
	if not active:
		return
	elapsed += delta
	present(elapsed)
	if elapsed >= DURATION:
		finish()

func present(t: float) -> void:
	var camera: Camera3D = world._camera
	var focus := wall_at + Vector3(0,3.5,0)
	var shot_at := wall_at + Vector3(15,5.5,14)
	var shot := Transform3D(Basis.looking_at((focus - shot_at).normalized()), shot_at)
	var move := smoothstep(0.65,1.8,t)
	var pose := start_camera.interpolate_with(shot, move)
	if t < 0.8:
		pose.origin += Vector3(sin(t*83),cos(t*97),0) * 0.045 * sin(t/0.8*PI)
	if t >= BREAK_TIME:
		if not actor.visible:
			_remove_old_wall()
			actor.show()
			rig.play(&"Walk")
			dust.restart()
			world._play_combat_warning(wall_at,85.0,0.65)
		var burst := t - BREAK_TIME
		var emerge := smoothstep(0.0,1.2,burst)
		actor.global_position = (wall_at - Vector3(3.2,0,0)).lerp(spawn_at,emerge)
		actor.rotation.y = PI * 0.5
		if burst > 1.2 and rig.current_animation != "Idle":
			rig.play(&"Idle",0.15)
		for i in chunks.size():
			var origin := chunk_rests[i]
			var velocity := Vector3(5.0+(i%5)*0.8, 3.0+(i%4)*0.8, (float(i%6)-2.5)*1.25)
			var point := origin + velocity * burst + Vector3.DOWN * 6.5 * burst * burst
			point.y = maxf(0.18,point.y)
			chunks[i].position = point
			chunks[i].rotation = Vector3(0.7,1.1,0.9) * minf(burst,1.3) * (1.0+i%4)
		if burst < 0.4:
			pose.origin += Vector3(sin(burst*90),cos(burst*74),0) * 0.12 * (1.0-burst/0.4)
		var look_at := actor.global_position + Vector3.UP * 3.0
		pose.basis = pose.basis.slerp(Basis.looking_at((look_at-pose.origin).normalized()), smoothstep(2.1,3.4,t)*0.7)
	if t > 5.1:
		# The normal camera has already been placed by the world this frame.
		pose = pose.interpolate_with(camera.global_transform, smoothstep(5.1,DURATION,t))
	camera.global_transform = pose
	camera.fov = lerpf(prior_fov,62.0,smoothstep(0.65,1.8,t))
	camera.fov = lerpf(camera.fov,prior_fov,smoothstep(5.1,DURATION,t))
	var size: Vector2 = world.get_viewport().get_visible_rect().size
	var bars := 1.0 - smoothstep(5.1,DURATION,t)
	top_bar.position = Vector2.ZERO
	top_bar.size = Vector2(size.x,58*bars)
	bottom_bar.position = Vector2(0,size.y-90*bars)
	bottom_bar.size = Vector2(size.x,90*bars)
	title.position = Vector2(0,size.y-173)
	title.size = Vector2(size.x,60)
	subtitle.position = Vector2(0,size.y-119)
	subtitle.size = Vector2(size.x,34)
	var alpha := smoothstep(3.0,3.5,t)*(1.0-smoothstep(4.8,5.25,t))
	title.modulate.a = alpha
	subtitle.modulate.a = alpha
	for shooter in world._shooters.values():
		if is_instance_valid(shooter.camera_viewmodel): shooter.camera_viewmodel.hide()
		if is_instance_valid(shooter.first_person_arms): shooter.first_person_arms.hide()

func finish() -> void:
	if not active:
		return
	active = false
	set_process(false)
	layer.hide()
	if is_instance_valid(actor): actor.queue_free()
	world._input_enabled = input_before
	if is_instance_valid(world._hud_layer): world._hud_layer.visible = hud_before
	for shooter in world._shooters.values():
		shooter.player.frozen = frozen_before.get(shooter.peer_id,false)
	world._update_camera()
	world._sync_camera_viewmodel()

func reset_intro() -> void:
	finish()
	played = false
	for entry in removed_instances:
		if is_instance_valid(entry.batch): entry.batch.multimesh.set_instance_transform(entry.index,entry.pose)
	removed_instances.clear()
	for i in chunks.size():
		chunks[i].position = chunk_rests[i]
		chunks[i].rotation = Vector3.ZERO


func spawn_point() -> Vector3:
	return wall_at + Vector3(StreetMap.CELL * 1.5,0,0)

func restore_breached() -> void:
	if played:
		return
	played = true
	_remove_old_wall()
	for i in chunks.size():
		chunks[i].position = chunk_rests[i] + Vector3(4.0 + i%5,0,(float(i%6)-2.5)*1.7)
		chunks[i].position.y = 0.18
		chunks[i].rotation = Vector3(0.7,1.1,0.9)*(1+i%4)
