extends Node3D
## Deterministic six-second introduction; visual debris never enters physics.
const HOUSE_WALL_SHADER := preload(
	"res://assets/props/Stage2_TomatinaVillage/press_king_house_wall.gdshader")
const DURATION := 6.2
const BREAK_TIME := 2.1
const BLACKOUT_IN_END := 0.18
const BLACKOUT_HOLD_END := 0.48
const BLACKOUT_OUT_END := 0.82
const RETURN_START := 5.0
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
var wall_skins: Array[MeshInstance3D] = []
var house_details: Array[MeshInstance3D] = []
var removed_instances: Array[Dictionary] = []
var facade: Node3D
var dust: CPUParticles3D
var layer: CanvasLayer
var title: Label
var subtitle: Label
var top_bar: ColorRect
var bottom_bar: ColorRect
var blackout: ColorRect
var start_camera := Transform3D.IDENTITY
var frozen_before := {}
var input_before := true
var hud_before := true
var prior_fov := 75.0

func configure(owner_world) -> void:
	world = owner_world
	name = "PressKingEntrance"
	process_priority = 100
	# The authored house and the batched street boundary overlap at different
	# depths.  This presentation plane lines up with the HouseHoney roof from the
	# frontal shot while staying in front of that generic boundary surface.
	wall_at = Vector3(world._plaza_rect.position.x+0.12,0.0,
		world._plaza_rect.get_center().y)
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

func _material(color: Color, weathered := false, masonry := false) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = HOUSE_WALL_SHADER
	result.set_shader_parameter(&"base_color",color)
	result.set_shader_parameter(&"weathered",weathered)
	result.set_shader_parameter(&"masonry",masonry)
	return result

func _build_facade() -> void:
	facade = Node3D.new()
	facade.name = "BreakableHouseFront"
	add_child(facade)
	facade.position = wall_at
	# Exact palette of the HouseHoney instance generated at cell (20, 29).
	var plaster := _material(Color("deba73"),true)
	var stone := _material(Color("a8998c"),true,true)
	var roof := _material(Color("b77856"))
	var glass := _material(Color("416071"))
	var shutters := _material(Color("8b4c51"))
	var terracotta := _material(Color("b85737"))
	var darkness := _material(Color("161512"))
	# This is the actual street-facing wall of the house already placed behind
	# the boundary.  Its roof and body remain; only this facade bursts inward to
	# reveal the dark interior.  No freestanding doorway or side pillars remain.
	# Just behind the 0.48 m front finish, but still a few centimetres ahead of
	# the batched street wall so the breached interior fully covers that surface.
	_box(facade, Vector3(0.39,3.6,0), Vector3(0.12,7.2,8.4), darkness)
	_box(facade, Vector3(0.0,7.26,0), Vector3(0.78,0.24,8.8), roof)
	for row in 5:
		for column in 6:
			var at := Vector3(0.2,0.72 + row*1.44,-3.5 + column*1.4)
			var mesh := _box(facade,at,Vector3(0.5,1.42,1.38),plaster if row > 0 else stone)
			chunks.append(mesh)
			chunk_rests.append(at)
	# A paper-thin finish hides the joins between breakable blocks until impact.
	wall_skins.append(_box(facade,Vector3(0.47,4.32,0),Vector3(0.02,5.74,8.38),plaster))
	wall_skins.append(_box(facade,Vector3(0.47,0.72,0),Vector3(0.02,1.42,8.38),stone))
	# Windows and flower boxes make this read as the existing house facade. They
	# disappear with the plaster at impact while the house roof stays standing.
	for window_z in [-2.35,2.35]:
		house_details.append(_box(facade,Vector3(0.50,4.15,window_z),Vector3(0.04,1.45,1.18),glass))
		for side in [-1.0,1.0]:
			house_details.append(_box(facade,Vector3(0.54,4.15,window_z+side*0.78),
				Vector3(0.08,1.56,0.30),shutters))
		house_details.append(_box(facade,Vector3(0.60,3.31,window_z),
			Vector3(0.20,0.28,1.48),terracotta))
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
	blackout = ColorRect.new()
	blackout.color = Color.BLACK
	blackout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blackout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blackout.modulate.a = 0.0
	layer.add_child(blackout)
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
	# Swap the generic multimesh street boundary for the matching breakable
	# HouseHoney frontage before the blackout reveals the shot.
	_remove_old_wall()
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
	if not removed_instances.is_empty():
		return
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
	# Face the breach square-on from the plaza.  The boss travels along +X out
	# of the wall, straight toward the lens, instead of being introduced from
	# its right flank.
	var shot_at := wall_at + Vector3(15.0,4.7,0.0)
	var shot := Transform3D(Basis.looking_at((focus - shot_at).normalized()), shot_at)
	# Hold the player's view only while the screen fades down.  The cut to the
	# frontal shot happens under full black, so there is no visible sideways
	# camera travel at the beginning of the introduction.
	var pose := start_camera if t < BLACKOUT_IN_END else shot
	if t >= BREAK_TIME:
		if not actor.visible:
			_remove_old_wall()
			for skin in wall_skins:
				skin.hide()
			for detail in house_details:
				detail.hide()
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
			pose.origin += (pose.basis.x*sin(burst*90)+pose.basis.y*cos(burst*74)) \
				* 0.12 * (1.0-burst/0.4)
		var look_at := actor.global_position + Vector3.UP * 3.0
		pose.basis = pose.basis.slerp(Basis.looking_at((look_at-pose.origin).normalized()), smoothstep(2.1,3.4,t)*0.7)
	if t > RETURN_START:
		# The normal camera has already been placed by the world this frame.
		pose = pose.interpolate_with(camera.global_transform, smoothstep(RETURN_START,DURATION,t))
	camera.global_transform = pose
	camera.fov = 62.0 if t >= BLACKOUT_IN_END else prior_fov
	camera.fov = lerpf(camera.fov,prior_fov,smoothstep(RETURN_START,DURATION,t))
	var size: Vector2 = world.get_viewport().get_visible_rect().size
	blackout.position = Vector2.ZERO
	blackout.size = size
	blackout.modulate.a = smoothstep(0.0,BLACKOUT_IN_END,t) \
		* (1.0-smoothstep(BLACKOUT_HOLD_END,BLACKOUT_OUT_END,t))
	var bars := 1.0 - smoothstep(RETURN_START,DURATION,t)
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
	for skin in wall_skins:
		skin.show()
	for detail in house_details:
		detail.show()


func spawn_point() -> Vector3:
	return wall_at + Vector3(StreetMap.CELL * 1.5,0,0)

func restore_breached() -> void:
	if played:
		return
	played = true
	_remove_old_wall()
	for skin in wall_skins:
		skin.hide()
	for detail in house_details:
		detail.hide()
	for i in chunks.size():
		chunks[i].position = chunk_rests[i] + Vector3(4.0 + i%5,0,(float(i%6)-2.5)*1.7)
		chunks[i].position.y = 0.18
		chunks[i].rotation = Vector3(0.7,1.1,0.9)*(1+i%4)
