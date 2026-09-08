extends Node3D

const StreamVisualScript := preload("res://scripts/stream_visual.gd")
const FloorScript := preload("res://scripts/floor_contamination.gd")
const PlayerScript := preload("res://scripts/player_controller.gd")
const WallScript := preload("res://scripts/contaminable_object.gd")

enum PointPhase { AIR, WALL_FIXED, LANDING }

class MayoPoint:
	var position := Vector3.ZERO
	var last_collision_position := Vector3.ZERO
	var velocity := Vector3.ZERO
	var launch_direction := Vector3.FORWARD
	var age := 0.0
	var distance_travelled := 0.0
	var powered := true
	var phase := PointPhase.AIR
	var landing_age := 0.0
	var fixed_age := 0.0
	var collision_slot := 0

class RibbonPoint:
	var position := Vector3.ZERO
	var opacity := 1.0
	var width_scale := 1.0

class MayoDroplet:
	var active := false
	var position := Vector3.ZERO
	var radius := 0.014
	var expires_at := 0.0

@export_group("Mayo Stream — Reference Values")
@export_range(0.2, 6.0, 0.01, "suffix:m") var stream_range := 1.96
@export_range(0.5, 15.0, 0.1, "suffix:m/s") var extend_speed := 7.0
@export_range(0.025, 0.25, 0.005, "suffix:m") var point_spacing := 0.09
@export_range(0.02, 0.2, 0.001, "suffix:m") var strand_thickness := 0.093
@export_range(0.0, 0.5, 0.01, "suffix:m") var muzzle_forward_offset := 0.15
@export_range(0.02, 1.5, 0.01, "suffix:s") var point_time_lifetime := 0.28
@export var use_time_lifetime := true
@export var use_distance_lifetime := true
@export_range(0.0, 30.0, 0.1, "suffix:m/s²") var gravity_acceleration := 9.8

@export_group("Emission Shape")
@export_range(0.0, 0.05, 0.001, "suffix:m") var lateral_position_jitter := 0.009
@export_range(0.0, 0.08, 0.001, "suffix:rad") var yaw_angle_jitter := 0.018
@export_range(0.0, 0.5, 0.01) var speed_magnitude_jitter := 0.10
@export_range(0.0, 1.0, 0.01) var inherited_player_velocity := 0.22
@export_range(32, 512, 1) var maximum_point_count := 192

@export_group("Collision Budget")
@export_range(1, 4, 1) var raycast_frame_stride := 1
@export_range(0.0, 0.03, 0.001, "suffix:m") var raycast_min_accumulated_motion := 0.004
@export_range(0.2, 4.0, 0.1, "suffix:s") var wall_fixed_hold_time := 1.2

@export_group("Release Pressure")
@export_range(0.0, 1.0, 0.01) var release_pressure_loss := 0.55
@export_range(0.2, 6.0, 0.1) var release_pressure_curve := 1.6

@export_group("Inertial Bend")
@export_range(0.0, 1.0, 0.01) var front_follow := 0.12
@export_range(0.2, 4.0, 0.1) var follow_curve_power := 1.8
@export_range(1, 8, 1) var spacing_constraint_passes := 3

@export_group("Landing and Grid")
@export_range(0.05, 0.5, 0.01, "suffix:m") var grid_cell_size := 0.2
@export_range(1, 2, 1) var landing_brush_radius_cells := 2
@export_range(0.05, 0.5, 0.01, "suffix:s") var landing_transition_time := 0.16
@export_range(0.1, 2.0, 0.05, "suffix:s") var droplet_lifetime := 0.55

@export_group("Third-person Camera")
@export_range(2.0, 10.0, 0.1, "suffix:m") var camera_distance := 6.2
@export_range(10.0, 70.0, 1.0, "suffix:°") var camera_pitch_degrees := 34.0
@export_range(-180.0, 180.0, 1.0, "suffix:°") var camera_yaw_degrees := 0.0
@export_range(0.2, 2.0, 0.05, "suffix:m") var camera_look_height := 0.65
@export_range(35.0, 90.0, 1.0, "suffix:°") var camera_fov := 58.0

var _points: Array[MayoPoint] = []
var _emit_distance := 0.0
var _attack_direction := Vector3.FORWARD
var _rng := RandomNumberGenerator.new()
var _player: MayoPlayer
var _muzzle: Marker3D
var _camera: Camera3D
var _floor: FloorContamination
var _walls: Array[ContaminableObject] = []
var _air_visual: StreamVisual
var _wall_visual: StreamVisual
var _landing_visual: StreamVisual
var _shadow_visual: StreamVisual
var _droplet_multimesh: MultiMesh
var _droplets: Array[MayoDroplet] = []
var _active_droplet_indices := PackedInt32Array()
var _droplet_buffer := PackedFloat32Array()
var _droplet_buffer_dirty := false
var _droplet_cursor := 0
var _next_collision_slot := 0
var _was_firing := false
var debug_profile_enabled := false
var debug_profile_frames := 0
var debug_raycast_count := 0
var debug_max_points := 0
var debug_timings_us := {
	"emit_follow": 0,
	"point_physics": 0,
	"constraint": 0,
	"ribbon_update": 0,
	"total": 0,
}


func _ready() -> void:
	_rng.seed = 0x4d41594f
	_build_world()
	_floor.configure(grid_cell_size, landing_brush_radius_cells)
	for wall in _walls:
		wall.configure(grid_cell_size, landing_brush_radius_cells)
	_update_camera()


func _physics_process(delta: float) -> void:
	var frame_started := Time.get_ticks_usec() if debug_profile_enabled else 0
	var step_started := frame_started
	_update_aim()
	var firing := Input.is_action_pressed("fire_mayo")
	if firing:
		_apply_inertial_follow(_player.frame_movement)
		_emit_distance += extend_speed * delta
		while _emit_distance >= point_spacing:
			_emit_distance -= point_spacing
			_emit_point()
	else:
		_emit_distance = 0.0
		if _was_firing:
			_apply_release_pressure_loss()
	_was_firing = firing
	if debug_profile_enabled:
		debug_timings_us.emit_follow += Time.get_ticks_usec() - step_started
		step_started = Time.get_ticks_usec()

	_simulate_points(delta)
	_simulate_droplets(delta)
	if debug_profile_enabled:
		debug_timings_us.point_physics += Time.get_ticks_usec() - step_started
		step_started = Time.get_ticks_usec()
	if firing:
		_enforce_spacing_constraint()
	if debug_profile_enabled:
		debug_timings_us.constraint += Time.get_ticks_usec() - step_started
		step_started = Time.get_ticks_usec()
	_trim_safety_cap()
	_update_visuals()
	if debug_profile_enabled:
		debug_timings_us.ribbon_update += Time.get_ticks_usec() - step_started
		debug_timings_us.total += Time.get_ticks_usec() - frame_started
		debug_profile_frames += 1
		debug_max_points = maxi(debug_max_points, _points.size())


func _process(_delta: float) -> void:
	_update_camera()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()


func _build_world() -> void:
	_build_environment()

	_floor = FloorScript.new()
	_floor.name = "FloorContamination"
	_floor.floor_size = Vector2(12.0, 12.0)
	_floor.cell_size = grid_cell_size
	_floor.landing_brush_radius_cells = landing_brush_radius_cells
	add_child(_floor)

	# The default centre aim is left open for the ballistic-to-floor test. Aim to
	# the right-hand slab to validate wall attachment and trailing-point pressure.
	_create_wall("ImpactWall", Vector3(2.35, 1.1, -0.72), Vector3(1.65, 2.2, 0.18), Color("886b61"))
	_create_wall("LeftGuide", Vector3(-3.6, 0.75, 0.8), Vector3(0.16, 1.5, 4.0), Color("6b7b84"))
	_create_wall("RightBlock", Vector3(3.0, 0.7, 2.1), Vector3(0.9, 1.4, 0.9), Color("6b7b84"))

	_player = PlayerScript.new()
	_player.name = "Player"
	_player.position = Vector3(0.0, 0.64, 1.55)
	add_child(_player)
	_build_player_body()

	_camera = Camera3D.new()
	_camera.name = "ThirdPersonCamera"
	_camera.current = true
	_camera.fov = camera_fov
	_camera.near = 0.05
	add_child(_camera)

	var mayo_material := StandardMaterial3D.new()
	mayo_material.albedo_color = Color("fff0a8")
	mayo_material.roughness = 0.28
	mayo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mayo_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var landing_material := mayo_material.duplicate() as StandardMaterial3D
	landing_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	landing_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var shadow_material := StandardMaterial3D.new()
	shadow_material.albedo_color = Color(0.08, 0.07, 0.055, 0.18)
	shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	shadow_material.no_depth_test = false
	shadow_material.render_priority = -1

	_air_visual = _make_stream_visual("AirRibbon", mayo_material)
	_wall_visual = _make_stream_visual("WallFixedRibbon", mayo_material)
	_landing_visual = _make_stream_visual("LandingRibbon", landing_material)
	_shadow_visual = _make_stream_visual("ProjectedShadow", shadow_material)
	_build_droplet_pool(mayo_material)


func _build_environment() -> void:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("18212a")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b5c5d4")
	environment.ambient_light_energy = 0.72
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.name = "KeyLight"
	sun.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	sun.light_color = Color("fff1d1")
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)


func _build_player_body() -> void:
	var collision := CollisionShape3D.new()
	var capsule_shape := CapsuleShape3D.new()
	capsule_shape.radius = 0.32
	capsule_shape.height = 1.28
	collision.shape = capsule_shape
	_player.add_child(collision)

	var body := MeshInstance3D.new()
	body.name = "CapsuleBody"
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.radius = 0.32
	capsule_mesh.height = 1.28
	body.mesh = capsule_mesh
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = Color("33495b")
	body_material.roughness = 0.75
	body.material_override = body_material
	_player.add_child(body)

	var nozzle := MeshInstance3D.new()
	nozzle.name = "Nozzle"
	var nozzle_mesh := CylinderMesh.new()
	nozzle_mesh.top_radius = 0.055
	nozzle_mesh.bottom_radius = 0.075
	nozzle_mesh.height = 0.28
	nozzle.mesh = nozzle_mesh
	nozzle.rotation_degrees.x = 90.0
	nozzle.position = Vector3(0.0, 0.19, -0.44)
	var nozzle_material := StandardMaterial3D.new()
	nozzle_material.albedo_color = Color("d9e2e8")
	nozzle_material.roughness = 0.38
	nozzle.material_override = nozzle_material
	_player.add_child(nozzle)

	_muzzle = Marker3D.new()
	_muzzle.name = "Muzzle"
	_muzzle.position = Vector3(0.0, 0.19, -0.58)
	_player.add_child(_muzzle)


func _create_wall(wall_name: String, wall_position: Vector3, wall_size: Vector3, color: Color) -> void:
	var wall := WallScript.new()
	wall.name = wall_name
	wall.position = wall_position
	wall.size = wall_size
	wall.body_color = color
	wall.cell_size = grid_cell_size
	wall.impact_brush_radius_cells = landing_brush_radius_cells
	add_child(wall)
	_walls.push_back(wall)


func _make_stream_visual(visual_name: String, material: Material) -> StreamVisual:
	var visual := StreamVisualScript.new() as StreamVisual
	visual.name = visual_name
	visual.setup(material, maximum_point_count)
	add_child(visual)
	return visual


func _update_camera() -> void:
	if not is_instance_valid(_camera) or not is_instance_valid(_player):
		return
	_camera.fov = camera_fov
	var yaw := deg_to_rad(camera_yaw_degrees)
	var pitch := deg_to_rad(camera_pitch_degrees)
	var horizontal := cos(pitch) * camera_distance
	var offset := Vector3(sin(yaw) * horizontal, sin(pitch) * camera_distance, cos(yaw) * horizontal)
	var target := _player.global_position + Vector3.UP * camera_look_height
	_camera.global_position = target + offset
	_camera.look_at(target, Vector3.UP)


func _update_aim() -> void:
	if not is_instance_valid(_camera):
		return
	var mouse := get_viewport().get_mouse_position()
	var ray_origin := _camera.project_ray_origin(mouse)
	var ray_direction := _camera.project_ray_normal(mouse)
	if absf(ray_direction.y) > 0.0001:
		var distance := (0.0 - ray_origin.y) / ray_direction.y
		if distance > 0.0:
			var target := ray_origin + ray_direction * distance
			var flat := target - _player.global_position
			flat.y = 0.0
			if flat.length_squared() > 0.04:
				_attack_direction = flat.normalized()
	var desired_yaw := atan2(-_attack_direction.x, -_attack_direction.z)
	_player.rotation.y = desired_yaw


func _emit_point() -> void:
	var point := MayoPoint.new()
	var angle := _rng.randf_range(-yaw_angle_jitter, yaw_angle_jitter)
	var direction := _attack_direction.rotated(Vector3.UP, angle).normalized()
	var lateral := Vector3.UP.cross(direction).normalized()
	var jitter := _rng.randf_range(-lateral_position_jitter, lateral_position_jitter)
	point.position = _muzzle.global_position + direction * muzzle_forward_offset + lateral * jitter
	point.last_collision_position = point.position
	# Speed jitter is independent of the yaw jitter above: it spreads where a
	# point runs out of pressure, and so spreads the landing point along the
	# strand axis rather than across it.
	var speed := extend_speed * (1.0 + _rng.randf_range(-speed_magnitude_jitter, speed_magnitude_jitter))
	point.velocity = direction * speed + Vector3(_player.velocity.x, 0.0, _player.velocity.z) * inherited_player_velocity
	point.launch_direction = direction
	point.collision_slot = _next_collision_slot
	_next_collision_slot = (_next_collision_slot + 1) % maxi(raycast_frame_stride, 1)
	_points.push_back(point)


func _apply_inertial_follow(player_movement: Vector3) -> void:
	if player_movement.length_squared() <= 0.00000001 or _points.is_empty():
		return
	var denominator := maxf(float(_points.size() - 1), 1.0)
	for i in _points.size():
		var point := _points[i]
		if point.phase != PointPhase.AIR:
			continue
		var t := float(i) / denominator
		var follow := lerpf(front_follow, 1.0, pow(t, follow_curve_power))
		point.position += player_movement * follow


## Releasing the trigger drops the line pressure. The front of the strand is
## already coasting on its own momentum and keeps its speed, while the points
## still at the muzzle lose the most, so the trail that lands afterwards starts
## at full range and is drawn back toward the player.
func _apply_release_pressure_loss() -> void:
	if release_pressure_loss <= 0.0 or _points.is_empty():
		return
	var denominator := maxf(float(_points.size() - 1), 1.0)
	for i in _points.size():
		var point := _points[i]
		if point.phase != PointPhase.AIR:
			continue
		# Index 0 is the front tip; the last index is the muzzle.
		var t := float(i) / denominator
		point.velocity *= 1.0 - release_pressure_loss * pow(t, release_pressure_curve)
		# Nothing is being pushed any more, so gravity takes over immediately.
		point.powered = false


func _simulate_points(delta: float) -> void:
	var space_state := get_world_3d().direct_space_state
	var physics_frame := int(Engine.get_physics_frames())
	var stride := maxi(raycast_frame_stride, 1)
	for point in _points:
		if point.phase == PointPhase.WALL_FIXED:
			point.fixed_age += delta
			continue
		if point.phase == PointPhase.LANDING:
			point.landing_age += delta
			continue

		point.age += delta
		if point.powered:
			var time_expired := use_time_lifetime and point.age >= point_time_lifetime
			var distance_expired := use_distance_lifetime and point.distance_travelled >= stream_range
			if time_expired or distance_expired:
				point.powered = false
		if not point.powered:
			point.velocity.y -= gravity_acceleration * delta

		var previous := point.position
		var next := previous + point.velocity * delta
		point.distance_travelled += previous.distance_to(next)
		var accumulated_motion := point.last_collision_position.distance_to(next)
		var scheduled := physics_frame % stride == point.collision_slot % stride
		var near_floor := next.y <= strand_thickness * 1.25
		var must_catch_up := accumulated_motion >= point_spacing * float(stride + 1)
		var should_cast := accumulated_motion >= raycast_min_accumulated_motion \
			and (scheduled or near_floor or must_catch_up)
		if should_cast:
			var query := PhysicsRayQueryParameters3D.create(point.last_collision_position, next)
			query.exclude = [_player.get_rid()]
			query.collide_with_areas = false
			if debug_profile_enabled:
				debug_raycast_count += 1
			var hit := space_state.intersect_ray(query)
			if not hit.is_empty():
				var collider := hit.collider as Node
				if collider != null and collider.is_in_group("mayo_floor"):
					_begin_landing(point, hit.position)
				else:
					if collider is ContaminableObject:
						collider.paint_mayo(hit.position, hit.normal)
					point.position = hit.position + hit.normal * (strand_thickness * 0.5)
					point.last_collision_position = point.position
					point.velocity = Vector3.ZERO
					point.phase = PointPhase.WALL_FIXED
			else:
				point.position = next
				point.last_collision_position = next
		else:
			point.position = next

	for i in range(_points.size() - 1, -1, -1):
		var point := _points[i]
		if point.phase == PointPhase.LANDING and point.landing_age >= landing_transition_time:
			_spawn_landing_droplets(point.position)
			_points.remove_at(i)
		elif point.phase == PointPhase.WALL_FIXED and point.fixed_age >= wall_fixed_hold_time:
			_points.remove_at(i)
		elif point.position.y < -1.0:
			_points.remove_at(i)


func _begin_landing(point: MayoPoint, hit_position: Vector3) -> void:
	point.position = hit_position + Vector3.UP * 0.008
	point.last_collision_position = point.position
	point.velocity = Vector3.ZERO
	point.powered = false
	point.phase = PointPhase.LANDING
	point.landing_age = 0.0
	_floor.paint_mayo(hit_position)


func _enforce_spacing_constraint() -> void:
	if _points.size() < 2:
		return
	for _pass in spacing_constraint_passes:
		for i in _points.size() - 1:
			var front := _points[i]
			var back := _points[i + 1]
			var direction := (front.launch_direction + back.launch_direction).normalized()
			if direction.length_squared() < 0.000001:
				direction = _attack_direction
			var projected_gap := (front.position - back.position).dot(direction)
			if projected_gap <= point_spacing:
				continue
			var correction := direction * (projected_gap - point_spacing)
			var front_free := front.phase == PointPhase.AIR
			var back_free := back.phase == PointPhase.AIR
			if front_free and back_free:
				front.position -= correction * 0.5
				back.position += correction * 0.5
			elif front_free:
				front.position -= correction
			elif back_free:
				back.position += correction


func _trim_safety_cap() -> void:
	while _points.size() > maximum_point_count:
		_points.pop_front()


func _update_visuals() -> void:
	var air_segments := _segments_for_phase(PointPhase.AIR)
	var wall_segments := _segments_for_phase(PointPhase.WALL_FIXED)
	var landing_segments := _segments_for_phase(PointPhase.LANDING)
	var shadow_segments := _shadow_segments()
	var camera_position := _camera.global_position
	var mayo_tint := Color("fff0a8")
	_air_visual.update_ribbon(air_segments, camera_position, strand_thickness, mayo_tint)
	_wall_visual.update_ribbon(wall_segments, camera_position, strand_thickness, mayo_tint)
	_landing_visual.update_ribbon(landing_segments, camera_position, strand_thickness, mayo_tint, 0.004)
	_shadow_visual.update_ribbon(shadow_segments, camera_position, strand_thickness * 0.72,
		Color(0.08, 0.07, 0.055, 0.18), 0.012)


func _segments_for_phase(phase: PointPhase) -> Array:
	var result: Array = []
	var current: Array = []
	for point in _points:
		if point.phase == phase:
			var visual_point := RibbonPoint.new()
			visual_point.position = point.position
			if phase == PointPhase.LANDING:
				var progress := clampf(point.landing_age / landing_transition_time, 0.0, 1.0)
				visual_point.opacity = 1.0 - progress
				visual_point.width_scale = 1.0 - progress
			current.push_back(visual_point)
		else:
			if not current.is_empty():
				result.push_back(current)
				current = []
	if not current.is_empty():
		result.push_back(current)
	return result


func _shadow_segments() -> Array:
	var result: Array = []
	var current: Array = []
	for point in _points:
		if point.phase == PointPhase.WALL_FIXED:
			if not current.is_empty():
				result.push_back(current)
				current = []
			continue
		var visual_point := RibbonPoint.new()
		visual_point.position = Vector3(point.position.x, 0.0, point.position.z)
		if point.phase == PointPhase.LANDING:
			var progress := clampf(point.landing_age / landing_transition_time, 0.0, 1.0)
			visual_point.opacity = 1.0 - progress
			visual_point.width_scale = 1.0 - progress
		current.push_back(visual_point)
	if not current.is_empty():
		result.push_back(current)
	return result


func _build_droplet_pool(mayo_material: Material) -> void:
	const POOL_SIZE := 512
	var droplet_mesh := SphereMesh.new()
	droplet_mesh.radius = 0.5
	droplet_mesh.height = 1.0
	droplet_mesh.radial_segments = 8
	droplet_mesh.rings = 4
	droplet_mesh.material = mayo_material

	_droplet_multimesh = MultiMesh.new()
	_droplet_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_droplet_multimesh.mesh = droplet_mesh
	_droplet_multimesh.instance_count = POOL_SIZE
	_droplet_buffer.resize(POOL_SIZE * 12)
	_droplet_buffer.fill(0.0)
	_droplet_multimesh.buffer = _droplet_buffer
	var instance := MultiMeshInstance3D.new()
	instance.name = "LandingDropletPool"
	instance.add_to_group("mayo_droplets")
	instance.multimesh = _droplet_multimesh
	instance.custom_aabb = AABB(Vector3(-12.0, -1.0, -12.0), Vector3(24.0, 5.0, 24.0))
	add_child(instance)

	_droplets.resize(POOL_SIZE)
	for i in POOL_SIZE:
		_droplets[i] = MayoDroplet.new()


func _spawn_landing_droplets(position: Vector3) -> void:
	if _droplet_multimesh == null:
		return
	var expires_at := Time.get_ticks_msec() * 0.001 + droplet_lifetime
	for _i in 7:
		var droplet := _droplets[_droplet_cursor]
		if not droplet.active:
			_active_droplet_indices.push_back(_droplet_cursor)
		_droplet_cursor = (_droplet_cursor + 1) % _droplets.size()
		var angle := _rng.randf_range(0.0, TAU)
		var spread_radius := sqrt(_rng.randf()) * 0.12
		droplet.active = true
		droplet.expires_at = expires_at
		droplet.radius = _rng.randf_range(0.014, 0.03)
		droplet.position = position + Vector3(cos(angle) * spread_radius, droplet.radius, sin(angle) * spread_radius)
		_write_droplet_buffer((_droplet_cursor - 1 + _droplets.size()) % _droplets.size(),
			droplet.position, droplet.radius * 2.0)
	_droplet_buffer_dirty = true


func _simulate_droplets(_delta: float) -> void:
	if _droplet_multimesh == null or _active_droplet_indices.is_empty():
		return
	var current_time := Time.get_ticks_msec() * 0.001
	for active_index in range(_active_droplet_indices.size() - 1, -1, -1):
		var i := _active_droplet_indices[active_index]
		var droplet := _droplets[i]
		if current_time >= droplet.expires_at:
			droplet.active = false
			_write_droplet_buffer(i, Vector3.ZERO, 0.0)
			_active_droplet_indices.remove_at(active_index)
			_droplet_buffer_dirty = true
	if _droplet_buffer_dirty:
		_droplet_multimesh.buffer = _droplet_buffer
		_droplet_buffer_dirty = false


func _write_droplet_buffer(index: int, position: Vector3, uniform_scale: float) -> void:
	var offset := index * 12
	# MultiMesh 3D transform buffer: three rows of (basis xyz, origin).
	_droplet_buffer[offset] = uniform_scale
	_droplet_buffer[offset + 1] = 0.0
	_droplet_buffer[offset + 2] = 0.0
	_droplet_buffer[offset + 3] = position.x
	_droplet_buffer[offset + 4] = 0.0
	_droplet_buffer[offset + 5] = uniform_scale
	_droplet_buffer[offset + 6] = 0.0
	_droplet_buffer[offset + 7] = position.y
	_droplet_buffer[offset + 8] = 0.0
	_droplet_buffer[offset + 9] = 0.0
	_droplet_buffer[offset + 10] = uniform_scale
	_droplet_buffer[offset + 11] = position.z


func debug_reset_profile() -> void:
	debug_profile_frames = 0
	debug_raycast_count = 0
	debug_max_points = 0
	for key in debug_timings_us:
		debug_timings_us[key] = 0
	if is_instance_valid(_floor):
		_floor.debug_paint_calls = 0
		_floor.debug_texture_uploads = 0
	for wall in _walls:
		wall.debug_paint_calls = 0
		wall.debug_texture_uploads = 0
