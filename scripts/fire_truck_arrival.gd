extends "res://scripts/press_king_entrance.gd"
## The whole bay is locked until the post-boss arrival, not just a visual gate.
const ESCAPE_DURATION := 12.0
const ESCAPE_SPEED := 22.0
var arrived := false
var bay := Rect2()
var barrier: StaticBody3D
var truck_body: ContaminableObject
var truck_mesh: Mesh
var nav_backup := {}
var nav_locked := false
var final_at := Vector3.ZERO
var wall_bodies: Array[RigidBody3D] = []
var chunk_rest_rotations: Array[Vector3] = []
var breached := false
var impact_count := 0
var vehicle_distance := 0.0
var truck_nav_backup := {}
var wall_span := 0.0
var escape_active := false
var escape_finished := false
var escape_elapsed := 0.0
var escape_root: Node3D
var escape_truck: Node3D
var escape_camera_before := Transform3D.IDENTITY
var escape_fov_before := 75.0
var escape_hud_before := true

func configure(owner_world) -> void:
	world = owner_world
	name = "FireTruckArrival"
	process_priority = 110
	bay = TomatinaMap.rect_world(TomatinaMap.FIRE_BAY)
	wall_at = Vector3(bay.get_center().x,0,bay.end.y)
	final_at = TomatinaMap.fire_truck_box().position
	final_at.y = 0
	_build_facade()
	facade.rotation.y = -PI*.5
	_build_physical_wall()
	_build_titles()
	title.text = "소방차 도착"
	subtitle.text = "생존 팀원과 집결한 뒤 [E] 탑승"
	barrier = StaticBody3D.new()
	barrier.name = "EntireExtractionBayLocked"
	barrier.position = Vector3(bay.get_center().x,3.4,bay.get_center().y)
	add_child(barrier)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	# Overlap the generated side walls instead of ending exactly on their seam.
	# That closes the narrow walkable-looking slots at both ends of the facade.
	shape.size = Vector3(wall_span,6.8,bay.size.y)
	collider.shape = shape
	barrier.add_child(collider)
	truck_body = ContaminableObject.new()
	truck_body.name = "ExtractionTruckBody"
	truck_body.size = TomatinaMap.fire_truck_box().size
	truck_body.position = final_at+Vector3.UP*truck_body.size.y*.5
	truck_body.visible_surface = false
	truck_body.collision_corner_cut = .14
	truck_body.collision_layer = 0
	add_child(truck_body)
	world._walls.append(truck_body)
	var kit: Node3D = load(TomatinaVillageArt.KIT_PATH).instantiate()
	var source := kit.find_child("FireEngine",true,false) as MeshInstance3D
	assert(source != null)
	truck_mesh = source.mesh
	kit.free()
	set_process(false)
	set_physics_process(false)

func sync_navigation() -> void:
	if nav_locked or world._nav == null:
		return
	nav_locked = true
	for y in range(TomatinaMap.FIRE_BAY.position.y,TomatinaMap.FIRE_BAY.end.y):
		for x in range(TomatinaMap.FIRE_BAY.position.x,TomatinaMap.FIRE_BAY.end.x):
			var cell := Vector2i(x,y)
			nav_backup[cell] = world._nav.is_walkable(cell)
			world._nav.grid.set_point_solid(cell,true)

func _build_facade() -> void:
	facade = Node3D.new()
	facade.name = "ExtractionWallAndRubble"
	facade.position = wall_at
	add_child(facade)
	# The old facade stopped exactly at the extraction-bay rectangle.  Its end
	# posts did not overlap the neighbouring street walls, so perspective exposed
	# a visible slot beside each post.  Carry the masonry two metres into both
	# flanks and make the collision barrier use this same span.
	wall_span = bay.size.x + 4.0
	var width := wall_span
	var plaster := _material(Color("bfaa8e"))
	var brick := _material(Color("986b50"))
	var dark_stone := _material(Color("6f6257"))
	for z in [-width*.5+.35,width*.5-.35]:
		_box(facade,Vector3(-.08,3.4,z),Vector3(1.05,6.8,1.25),dark_stone)
	var columns := 16
	var course_width := width/float(columns)
	for row in 4:
		for column in columns:
			# Overlapping courses are deliberately irregular in depth and colour,
			# but never separated along the span: this is a real barricade, not a
			# row of decorative panels with cracks between them.
			var jitter := float(posmod(row*13+column*7,5)-2)*.025
			var at := Vector3(.04+float(posmod(row*5+column*3,4))*.055,
				.84+row*1.67,-width*.5+(column+.5)*course_width+jitter)
			var finish := brick if row==0 or (row+column)%7==0 else plaster
			chunks.append(_box(facade,at,Vector3(.78,1.74,course_width+.16),finish))
			chunk_rests.append(at)
			chunk_rest_rotations.append(Vector3.ZERO)
	# A deep rubble apron makes the closure read as a hurriedly reinforced
	# collapse.  These pieces join the breakable rigid bodies, so the truck must
	# physically throw them aside with the wall rather than ghosting through art.
	for i in 15:
		var z := -width*.46+float(i)*width*.92/14.0
		var at := Vector3(.62+float(i%3)*.18,.32+float(i%2)*.08,z)
		var rock := _box(facade,at,Vector3(1.35+float(i%2)*.25,.72,course_width*1.45),
			brick if i%3 else dark_stone)
		rock.rotation = Vector3(.08*float(i%2),.07*float((i%5)-2),.04*float((i%3)-1))
		chunks.append(rock)
		chunk_rests.append(at)
		chunk_rest_rotations.append(rock.rotation)
	dust = CPUParticles3D.new()
	dust.emitting = false
	dust.one_shot = true
	dust.explosiveness = .95
	dust.amount = 40
	dust.lifetime = 1.4
	dust.direction = Vector3.FORWARD
	dust.spread = 65
	dust.initial_velocity_min = 2
	dust.initial_velocity_max = 6
	dust.gravity = Vector3(0,-2,0)
	var puff := SphereMesh.new()
	puff.radius = .35
	puff.height = .7
	puff.radial_segments = 8
	puff.rings = 4
	puff.material = _material(Color("a7947d"))
	dust.mesh = puff
	dust.position = wall_at+Vector3.UP*3
	add_child(dust)

func _truck_visual() -> Node3D:
	var holder := AnimatableBody3D.new()
	holder.name = "ArrivalFireEngine"
	holder.collision_layer = 64
	holder.collision_mask = 32
	holder.sync_to_physics = false
	var hull := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = truck_body.size
	hull.shape = box
	hull.position.y = truck_body.size.y*.5
	holder.add_child(hull)
	var mesh := MeshInstance3D.new()
	mesh.mesh = truck_mesh
	var material := ShaderMaterial.new()
	material.shader = TomatinaVillageArt.TOON_SHADER
	mesh.material_override = material
	var bounds := truck_mesh.get_aabb()
	var scale := truck_body.size/bounds.size
	var offset := bounds.get_center()
	offset.y = bounds.position.y
	mesh.transform = Transform3D(Basis().scaled(scale),-offset*scale)
	holder.add_child(mesh)
	return holder

func start(at: Vector3) -> void:
	if played or active:
		return
	played = true
	active = true
	elapsed = 0
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
	actor = _truck_visual()
	actor.rotation.y = 0
	actor.position = Vector3(final_at.x,0,wall_at.z-27.0)
	add_child(actor)
	actor.hide()
	layer.show()
	set_process(true)
	set_physics_process(true)


## Everyone is already gathered at the engine when this begins.  It is an
## in-engine film rather than a prerecorded clip: the chosen player characters
## ride the same fire engine down a long recycled-looking festival road, so a
## one-to-four-player party sees its actual roster escaping together.
func start_escape() -> void:
	if escape_active or escape_finished or not arrived:
		return
	escape_active = true
	escape_elapsed = 0.0
	escape_camera_before = world._camera.global_transform
	escape_fov_before = world._camera.fov
	escape_hud_before = is_instance_valid(world._hud_layer) and world._hud_layer.visible
	world.set_gameplay_input_enabled(false)
	for shooter in world._shooters.values():
		shooter.player.frozen = true
		shooter.player.velocity = Vector3.ZERO
		shooter.firing = false
	if is_instance_valid(world._hud_layer):
		world._hud_layer.hide()
	if is_instance_valid(actor):
		actor.hide()
	_build_escape_road()
	title.text = "축제를 빠져나갑니다"
	subtitle.text = "모두 탑승 완료 · 부뇰 외곽 도로"
	layer.show()
	set_process(true)


func _build_escape_road() -> void:
	escape_root = Node3D.new()
	escape_root.name = "TomatinaEscapeRoad"
	escape_root.position = Vector3(0.0, 180.0, -40.0)
	add_child(escape_root)
	var asphalt := _material(Color("353a3d"))
	var shoulder := _material(Color("b9a47d"))
	var stripe := _material(Color("eee4c7"))
	var field := _material(Color("6f8b55"))
	var trunk := _material(Color("76513b"))
	var leaves := _material(Color("3f6d48"))
	var village := [_material(Color("c9826c")), _material(Color("d8ad73")),
		_material(Color("83a06d")), _material(Color("7996a3"))]
	var roof := _material(Color("793b32"))
	var flags := [_material(Color("d9473f")), _material(Color("e5bd45")),
		_material(Color("4b8f91")), _material(Color("e9dfad"))]
	for segment in 34:
		var z := -20.0 + float(segment) * 20.0
		_box(escape_root, Vector3(0.0, -0.24, z), Vector3(18.0, 0.42, 20.2), asphalt)
		_box(escape_root, Vector3(-11.0, -0.30, z), Vector3(4.0, 0.30, 20.2), shoulder)
		_box(escape_root, Vector3(11.0, -0.30, z), Vector3(4.0, 0.30, 20.2), shoulder)
		_box(escape_root, Vector3(-18.0, -0.46, z), Vector3(10.0, 0.20, 20.2), field)
		_box(escape_root, Vector3(18.0, -0.46, z), Vector3(10.0, 0.20, 20.2), field)
		for dash in 2:
			_box(escape_root, Vector3(0.0, 0.012, z - 5.0 + dash * 10.0),
				Vector3(0.24, 0.025, 4.8), stripe)
		for side in [-1.0, 1.0]:
			if segment < 5:
				# The first seconds still belong to Buñol: pastel festival fronts,
				# low roofs and bunting recede behind the truck before open country.
				var house_at := Vector3(side * 15.0, 2.35, z)
				_box(escape_root, house_at, Vector3(7.2, 4.8, 12.5),
					village[(segment + (0 if side < 0.0 else 2)) % village.size()])
				_box(escape_root, house_at + Vector3.UP * 3.0,
					Vector3(7.7, 1.25, 13.0), roof)
			else:
				var offset := float(posmod(segment * 7 + int(side), 5)) * 0.55
				var tree_at := Vector3(side * (14.0 + offset), 1.4,
					z + float((segment * 9) % 7) - 3.0)
				_box(escape_root, tree_at, Vector3(0.55, 3.0, 0.55), trunk)
				var crown := MeshInstance3D.new()
				var crown_mesh := SphereMesh.new()
				crown_mesh.radius = 2.0 + float(segment % 3) * 0.25
				crown_mesh.height = crown_mesh.radius * 1.65
				crown_mesh.radial_segments = 8
				crown_mesh.rings = 5
				crown_mesh.material = leaves
				crown.mesh = crown_mesh
				crown.position = tree_at + Vector3.UP * 2.4
				escape_root.add_child(crown)
		if segment < 4:
			for flag in 9:
				_box(escape_root, Vector3(-8.0 + flag * 2.0, 7.2, z + 4.0),
					Vector3(0.72, 0.82 + float(flag % 2) * 0.28, 0.10),
					flags[(segment + flag) % flags.size()])
	escape_truck = _truck_visual()
	escape_truck.name = "EscapingFireEngine"
	escape_truck.collision_layer = 0
	escape_truck.collision_mask = 0
	escape_truck.position = Vector3(2.8, 0.0, 0.0)
	escape_root.add_child(escape_truck)
	_build_escape_riders()


func _build_escape_riders() -> void:
	var riders: Array = world._shooters.values()
	riders.sort_custom(func(a, b): return a.spawn_slot < b.spawn_slot)
	var seats := [Vector3(-0.85, 3.05, -1.15), Vector3(0.85, 3.05, -1.15),
		Vector3(-0.85, 3.05, -2.45), Vector3(0.85, 3.05, -2.45)]
	for index in mini(riders.size(), seats.size()):
		var shooter = riders[index]
		if not is_instance_valid(shooter.player_visual):
			continue
		var rider := shooter.player_visual.duplicate(Node.DUPLICATE_USE_INSTANTIATION) as Node3D
		if rider == null:
			continue
		rider.name = "EscapeRider%d" % shooter.peer_id
		rider.position = seats[index]
		rider.rotation = Vector3(0.0, PI, 0.0)
		rider.visible = true
		escape_truck.add_child(rider)
		var animations := rider.find_children("*", "AnimationPlayer", true, false)
		if not animations.is_empty():
			var animation := animations[0] as AnimationPlayer
			if animation.has_animation(&"Idle"):
				animation.play(&"Idle")


func _process(delta: float) -> void:
	if not escape_active:
		super._process(delta)
		return
	escape_elapsed = minf(escape_elapsed + delta, ESCAPE_DURATION)
	var distance := escape_elapsed * ESCAPE_SPEED
	escape_truck.position.z = distance
	escape_truck.rotation.z = sin(escape_elapsed * 2.1) * 0.008
	# Like a travelling end-credit shot, the vehicle stays readable while the
	# framing opens from a close three-quarter departure to a calm, wide road.
	var close_offset := Vector3(9.4, 4.9, -10.5)
	var follow_offset := Vector3(1.8, 6.0, -16.8)
	var wide_offset := Vector3(-7.5, 8.1, -21.5)
	var camera_offset := close_offset.lerp(follow_offset,
		smoothstep(1.6, 4.0, escape_elapsed)).lerp(wide_offset,
		smoothstep(8.0, 11.4, escape_elapsed))
	camera_offset.y += sin(escape_elapsed * 2.4) * 0.08
	var camera_at := escape_root.global_position + escape_truck.position + camera_offset
	var focus := escape_root.global_position + escape_truck.position + Vector3(0.0, 2.6, 5.5)
	world._camera.global_transform = Transform3D(
		Basis.looking_at((focus - camera_at).normalized()), camera_at)
	world._camera.fov = lerpf(60.0, 70.0, smoothstep(4.0, ESCAPE_DURATION, escape_elapsed))
	var viewport_size: Vector2 = world.get_viewport().get_visible_rect().size
	var bars := 1.0 - smoothstep(10.7, ESCAPE_DURATION, escape_elapsed)
	top_bar.size = Vector2(viewport_size.x, 58.0 * bars)
	bottom_bar.position = Vector2(0.0, viewport_size.y - 90.0 * bars)
	bottom_bar.size = Vector2(viewport_size.x, 90.0 * bars)
	title.position = Vector2(0.0, viewport_size.y - 173.0)
	title.size = Vector2(viewport_size.x, 60.0)
	subtitle.position = Vector2(0.0, viewport_size.y - 119.0)
	subtitle.size = Vector2(viewport_size.x, 34.0)
	_update_escape_title_card()
	var alpha := _escape_title_alpha()
	title.modulate.a = alpha
	subtitle.modulate.a = alpha
	for shooter in world._shooters.values():
		if is_instance_valid(shooter.camera_viewmodel): shooter.camera_viewmodel.hide()
		if is_instance_valid(shooter.first_person_arms): shooter.first_person_arms.hide()
	if escape_elapsed >= ESCAPE_DURATION:
		_finish_escape()


func _update_escape_title_card() -> void:
	if escape_elapsed < 3.4:
		title.text = "축제를 빠져나갑니다"
		subtitle.text = "모두 탑승 완료 · 부뇰 시내"
	elif escape_elapsed < 7.2:
		title.text = "LA TOMATINA"
		subtitle.text = "토마토 범벅이 된 채, 전원 생환"
	else:
		title.text = "SAUCE IT!"
		subtitle.text = "임무 기록을 정리하는 중…"


func _escape_title_alpha() -> float:
	for window in [[0.45, 1.05, 2.75, 3.35], [3.55, 4.15, 6.45, 7.05],
			[7.45, 8.05, 10.55, 11.25]]:
		if escape_elapsed >= float(window[0]) and escape_elapsed <= float(window[3]):
			return smoothstep(float(window[0]), float(window[1]), escape_elapsed) \
				* (1.0 - smoothstep(float(window[2]), float(window[3]), escape_elapsed))
	return 0.0


func _finish_escape() -> void:
	if not escape_active:
		return
	escape_active = false
	escape_finished = true
	set_process(false)
	layer.hide()
	world.finish_truck_escape()

func present(t: float) -> void:
	var camera: Camera3D = world._camera
	var shot_at := wall_at+Vector3(16,6.5,15)
	var focus := wall_at+Vector3.UP*2.7
	var shot := Transform3D(Basis.looking_at((focus-shot_at).normalized()),shot_at)
	var pose := start_camera.interpolate_with(shot,smoothstep(.55,1.6,t))
	if t<.6:
		pose.origin += Vector3(sin(t*77),cos(t*91),0)*.035
	if breached:
		var burst := t-impact_time
		if burst<.35:
			pose.origin += Vector3(sin(burst*83),cos(burst*71),0)*.15*(1-burst/.35)
	if t>5.1:
		pose = pose.interpolate_with(camera.global_transform,smoothstep(5.1,DURATION,t))
	camera.global_transform = pose
	camera.fov = lerpf(lerpf(prior_fov,64.0,smoothstep(.55,1.6,t)),prior_fov,smoothstep(5.1,DURATION,t))
	var size: Vector2 = world.get_viewport().get_visible_rect().size
	var bars := 1-smoothstep(5.1,DURATION,t)
	top_bar.size = Vector2(size.x,58*bars)
	bottom_bar.position = Vector2(0,size.y-90*bars)
	bottom_bar.size = Vector2(size.x,90*bars)
	title.position = Vector2(0,size.y-173)
	title.size = Vector2(size.x,60)
	subtitle.position = Vector2(0,size.y-119)
	subtitle.size = Vector2(size.x,34)
	var alpha := smoothstep(3.6,4.0,t)*(1-smoothstep(4.9,5.3,t))
	title.modulate.a = alpha
	subtitle.modulate.a = alpha
	for shooter in world._shooters.values():
		if is_instance_valid(shooter.camera_viewmodel): shooter.camera_viewmodel.hide()
		if is_instance_valid(shooter.first_person_arms): shooter.first_person_arms.hide()

func finish() -> void:
	if not active or not breached: return
	set_physics_process(false)
	var truck := actor
	actor = null
	super.finish()
	actor = truck
	actor.position = final_at
	actor.show()
	actor.collision_layer = 0
	actor.collision_mask = 0
	for body in wall_bodies:
		body.freeze = true
		body.collision_layer = 0
	arrived = true
	barrier.collision_layer = 0
	truck_body.collision_layer = 1
	for cell: Vector2i in nav_backup:
		world._nav.grid.set_point_solid(cell,not nav_backup[cell])
	var footprint := TomatinaMap._box_cells([TomatinaMap.fire_truck_box()] as Array[Dictionary])
	for cell in footprint:
		truck_nav_backup[cell] = world._nav.is_walkable(cell)
		world._nav.grid.set_point_solid(cell,true)
	# Keep the arriving vehicle from enclosing a frozen teammate at its stop.
	if world._is_authority():
		for shooter in world._shooters.values():
			var gap: Vector3 = (shooter.player.global_position-final_at).abs()
			if gap.x<truck_body.size.x*.5+.7 and gap.z<truck_body.size.z*.5+.7:
				shooter.player.global_position.x = final_at.x+(-1 if shooter.player.global_position.x<final_at.x else 1)*(truck_body.size.x*.5+1.0)
				shooter.player.reset_physics_interpolation()

func reset_intro() -> void:
	if escape_active:
		world._camera.global_transform = escape_camera_before
		world._camera.fov = escape_fov_before
		if is_instance_valid(world._hud_layer):
			world._hud_layer.visible = escape_hud_before
	if escape_active or escape_finished:
		world.set_gameplay_input_enabled(true)
		for shooter in world._shooters.values():
			shooter.player.frozen = false
	if is_instance_valid(escape_root):
		escape_root.queue_free()
	escape_root = null
	escape_truck = null
	escape_active = false
	escape_finished = false
	escape_elapsed = 0.0
	layer.hide()
	if active:
		set_physics_process(false)
		super.finish()
	if is_instance_valid(actor): actor.queue_free()
	actor = null
	played = false
	arrived = false
	barrier.collision_layer = 1
	truck_body.collision_layer = 0
	breached = false
	impact_count = 0
	vehicle_distance = 0
	for cell in truck_nav_backup:
		world._nav.grid.set_point_solid(cell,not truck_nav_backup[cell])
	truck_nav_backup.clear()
	for cell: Vector2i in nav_backup: world._nav.grid.set_point_solid(cell,true)
	for i in wall_bodies.size():
		wall_bodies[i].freeze = true
		wall_bodies[i].collision_layer = 32
		wall_bodies[i].position = chunk_rests[i]
		wall_bodies[i].rotation = chunk_rest_rotations[i]

func restore_arrival() -> void:
	if arrived: return
	if not active: start(final_at)
	_break_wall(Vector3.BACK*10,false)
	present(DURATION)
	finish()


func in_reach(player: MayoPlayer) -> bool:
	if not arrived or active or not is_instance_valid(player): return false
	var offset := (player.global_position-final_at).abs()-truck_body.size*.5
	return Vector2(maxf(offset.x,0),maxf(offset.z,0)).length() <= 2.8


var impact_time := 0.0
func _build_physical_wall() -> void:
	for i in chunks.size():
		var mesh := chunks[i]
		var body := RigidBody3D.new()
		body.name = "RescueWallBrick%d" % i
		body.mass = 5.0
		body.freeze = true
		body.collision_layer = 32
		body.collision_mask = 65 # Ground and moving vehicle; debris never traps players.
		body.continuous_cd = true
		body.linear_damp = .8
		body.angular_damp = 1.4
		facade.add_child(body)
		body.transform = mesh.transform
		mesh.reparent(body,false)
		mesh.transform = Transform3D.IDENTITY
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = (mesh.mesh as BoxMesh).size
		collider.shape = shape
		body.add_child(collider)
		wall_bodies.append(body)

func _physics_process(delta: float) -> void:
	if not active or not is_instance_valid(actor) or elapsed<1.5: return
	actor.show()
	var before: Vector3 = actor.global_position
	var start := Vector3(final_at.x,0,wall_at.z-27.0)
	var wanted := start.lerp(final_at,smoothstep(1.5,4.3,elapsed))
	actor.global_position = wanted
	vehicle_distance += before.distance_to(wanted)
	if breached: return
	# The moving front bumper must physically meet the masonry before release.
	var bumper := BoxShape3D.new()
	bumper.size = Vector3(truck_body.size.x,2.5,.8)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = bumper
	query.collision_mask = 32
	query.transform = Transform3D(Basis.IDENTITY,wanted+Vector3(0,1.5,truck_body.size.z*.5))
	query.exclude = [(actor as CollisionObject3D).get_rid()]
	var contact := get_world_3d().direct_space_state.intersect_shape(query,4)
	var old_front := before+Vector3(0,1.5,truck_body.size.z*.5)
	var new_front := wanted+Vector3(0,1.5,truck_body.size.z*.5)
	var ray := PhysicsRayQueryParameters3D.create(old_front,new_front,32)
	var swept := get_world_3d().direct_space_state.intersect_ray(ray) if old_front.distance_squared_to(new_front)>.00001 else {}
	if not contact.is_empty() or not swept.is_empty():
		_break_wall((wanted-before)/maxf(delta,.0001),true)

func _break_wall(vehicle_velocity: Vector3, effects: bool) -> void:
	if breached: return
	breached = true
	impact_count += 1
	impact_time = elapsed
	barrier.collision_layer = 0
	if effects:
		dust.restart()
		world._play_combat_warning(wall_at,90.0,.8)
	for i in wall_bodies.size():
		var body := wall_bodies[i]
		body.freeze = false
		var impulse := Vector3((float(i%7)-3)*.45,2.0+i%3,clampf(vehicle_velocity.z*.6,5.0,11.0))*body.mass
		body.apply_central_impulse(impulse)
		body.apply_torque_impulse(Vector3(1+i%3,.5,1)*body.mass*.4)
