extends "res://scripts/press_king_entrance.gd"
## The whole bay is locked until the post-boss arrival, not just a visual gate.
var arrived := false
var bay := Rect2()
var barrier: StaticBody3D
var truck_body: ContaminableObject
var truck_mesh: Mesh
var nav_backup := {}
var nav_locked := false
var final_at := Vector3.ZERO
var wall_bodies: Array[RigidBody3D] = []
var breached := false
var impact_count := 0
var vehicle_distance := 0.0
var truck_nav_backup := {}

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
	shape.size = Vector3(bay.size.x,6.8,bay.size.y)
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
	var width := bay.size.x
	var plaster := _material(Color("bfaa8e"))
	var brick := _material(Color("986b50"))
	for z in [-width*.5-.4,width*.5+.4]:
		_box(facade,Vector3(0,3.4,z),Vector3(.8,6.8,.8),plaster)
	for row in 4:
		for column in 14:
			var at := Vector3(0,.84+row*1.68,-width*.5+(column+.5)*width/14)
			chunks.append(_box(facade,at,Vector3(.65,1.65,width/14-.02),plaster if row>0 else brick))
			chunk_rests.append(at)
	for i in 9:
		var rock := _box(facade,Vector3(.5,.3,-width*.45+i*width*.1125),Vector3(1.1,.6,1.6),brick)
		rock.rotation = Vector3(.1,.25*i,.12)
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
		wall_bodies[i].rotation = Vector3.ZERO

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
