extends SceneTree

const RANGE := preload("res://stage_range.tscn")

var failures: Array[String] = []


func _initialize() -> void:
	MayoTutorial.disabled = true
	call_deferred("_run")


func _run() -> void:
	var world = RANGE.instantiate()
	root.add_child(world)
	await process_frame
	var shooter = world._local
	world.catch_chance = 0.0
	shooter.sauce_kind = ContaminationGrid.KIND_KETCHUP
	world._apply_sauce_look(shooter)
	for part in world.SauceParts.STREAM_AIM_RECOIL:
		world.request_range_part(part)
		var pitches := [-35.0, -50.0, -65.0, -78.0, -85.0, -30.0] \
			if part == world.SauceParts.Part.STANDARD else [-65.0, -85.0]
		for pitch in pitches:
			await _check_stream(world, shooter, part, pitch)
	await _check_projectiles(world, shooter)
	_check_ribbon_buffer(world)
	_check_release_curve(world)
	_check_landing_droplet_pool(world)

	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("CLOSE_FLOOR_STREAM_OK")
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _check_stream(world, shooter, part: int, pitch: float) -> void:
	shooter.sauce = 1.0
	shooter.fire_cooldown = 0.0
	shooter.points.clear()
	Input.action_press("fire_mayo")
	var visible_ticks := 0
	var confirmed_floor := 0
	for tick in 20:
		world.debug_set_aim(0.0, pitch)
		await physics_frame
		await process_frame
		if tick < 6:
			continue
		for point in shooter.points:
			if point.phase == world.PointPhase.LANDING and point.landed_on_floor:
				confirmed_floor += 1
		if shooter.air_visual.visible:
			visible_ticks += 1
		var contact = world._near_floor_stream_contact(shooter, world._camera.global_position, -world._camera.global_basis.z)
		if contact != null:
			var strip: Array = world._floor_nozzle_strip(shooter, contact)
			if not strip[0].position.is_equal_approx(world._first_person_tip(shooter, shooter.sauce_part)) \
					or not strip[-1].position.is_equal_approx(contact.position):
				failures.append("fallback strip did not join the visible mouth and actual impact")
				break
	if visible_ticks != 14 or confirmed_floor == 0:
		failures.append("stream part %d at %.0f degrees showed on %d/14 frames with %d floor contacts" % [
			part, pitch, visible_ticks, confirmed_floor])
	print("stream part %d pitch %.0f: %d/14 frames, floor contacts %d" % [part, pitch, visible_ticks, confirmed_floor])
	Input.action_release("fire_mayo")
	for tick in 28:
		await physics_frame
	await process_frame
	if shooter.air_visual.visible or shooter.nozzle_visual.visible:
		failures.append("pitch %.0f left a stream after release and settling" % pitch)



func _check_projectiles(world, shooter) -> void:
	world.set_physics_process(false)
	var system = world._sauce_parts
	var step := 1.0 / 60.0
	for part in world.SauceParts.PROJECTILES:
		world.request_range_part(part)
		for pitch in [-55.0, -70.0, -85.0]:
			system.reset()
			shooter.aim_recoil_pitch = 0.0
			shooter.aim_recoil_pending = 0.0
			world.debug_set_aim(0.0, pitch)
			for tick in 3:
				await physics_frame
			world._pending_splats.clear()
			var reports_before := _report_count(world)
			world._fire_part_volley(shooter)
			if _report_count(world) != reports_before + 1:
				failures.append("projectile %d did not play exactly one launch sound" % part)
			var shot: Dictionary = system._projectiles[-1]
			var ribbon: StreamVisual = shot.node
			var mesh_seen := false
			for tick in 12:
				system.advance_projectiles(step, true)
				mesh_seen = mesh_seen or ribbon.visible
				if not system._close_impact_ribbons.is_empty() or system._projectiles.is_empty():
					break
			if not mesh_seen or world._pending_splats.is_empty() or system._projectiles.size() != 0:
				failures.append("projectile %d at %.0f degrees was invisible or never painted the floor" % [part, pitch])
			if not system._close_impact_ribbons.is_empty():
				var trace: Dictionary = system._close_impact_ribbons[0]
				if not ribbon.custom_aabb.has_point(trace.muzzle) or not ribbon.custom_aabb.has_point(trace.contact):
					failures.append("the projectile ribbon did not join its muzzle and impact")
			system.advance_projectiles(0.10, false)
			if ribbon.visible or not system._close_impact_ribbons.is_empty():
				failures.append("the short projectile impact outlived its visible interval")
			print("projectile part %d pitch %.0f: visible %s, floor splats %d" % [
				part, pitch, mesh_seen, world._pending_splats.size() / 4])

	world.request_range_part(world.SauceParts.Part.BURST)
	shooter.sauce = 1.0
	shooter.part_cooldown = 0.0
	shooter.part_shots_left = 0
	shooter.part_trigger_down = false
	shooter.bottle_pickup_left = 0.0
	world.muted = false
	var reports := _report_count(world, world.spray_start_sound)
	shooter.firing = true
	world._advance_part_trigger(shooter, step)
	shooter.firing = false
	for tick in 20:
		world._advance_part_trigger(shooter, step)
	var fired := _report_count(world, world.spray_start_sound) - reports
	if fired != world.SauceParts.BURST_SHOTS:
		failures.append("expected three burst shot reports, got %d" % fired)
	print("burst shot reports: ", fired)


func _check_ribbon_buffer(world) -> void:
	var ribbon := StreamVisual.new()
	world.add_child(ribbon)
	ribbon.setup(world.SAUCE_STREAM_MATERIALS[ContaminationGrid.KIND_KETCHUP], 128)
	var strand: Array = []
	for index in 100:
		strand.append({"position": Vector3(float(index) * 0.1, 1.0, 0.0), "width_scale": 1.0})
	var short_strand := strand.slice(0, 4)
	var camera_position := Vector3(0.0, 1.0, 4.0)
	ribbon.update_ribbon([short_strand], camera_position, Vector3.FORWARD, 0.1)
	var small := ribbon.mesh
	ribbon.update_ribbon([strand], camera_position, Vector3.FORWARD, 0.1)
	var large := ribbon.mesh
	if large == small or not ribbon.custom_aabb.has_point(strand[-1].position):
		failures.append("growing ribbon lost its tail or did not resize its buffer")
	ribbon.update_ribbon([short_strand], camera_position, Vector3.FORWARD, 0.1)
	if ribbon.mesh != small or ribbon.custom_aabb.has_point(strand[-1].position):
		failures.append("shrinking ribbon did not reuse the small buffer and update its bounds")
	ribbon.update_ribbon([strand], camera_position, Vector3.FORWARD, 0.1)
	if ribbon.mesh != large or not ribbon.custom_aabb.has_point(strand[-1].position):
		failures.append("growing ribbon again did not reuse the large buffer and restore bounds")
	# Almost coincident samples can request a full cap on a multi-point strand.
	var position: Vector3 = strand[0].position
	var adjacent := {"position": position + Vector3.DOWN * 0.000001, "width_scale": 1.0}
	ribbon.update_ribbon([[strand[0], adjacent]], camera_position, Vector3.FORWARD, 0.1)
	if not ribbon.visible or not ribbon.custom_aabb.has_point(position):
		failures.append("almost coincident ribbon samples lost their shared cap")
	ribbon.queue_free()


func _check_release_curve(world) -> void:
	var end = world.NozzleRibbonEnd.new()
	var anchor = world.MayoPoint.new()
	anchor.position = Vector3(3.0, 2.0, -4.0)
	end.anchor = anchor
	var original := [Vector3.ZERO, Vector3(0.25, 0.4, 0.05), Vector3(0.55, 0.1, 0.2)]
	for position: Vector3 in original:
		var point = world.RibbonPoint.new()
		point.position = anchor.position + position
		end.path.append(point)
	var tick := Engine.get_physics_frames()
	if not world._has_releasing_nozzle_end(end, tick):
		failures.append("the nozzle strip vanished on its release tick")
		return
	var initial: Array = world._released_nozzle_path(end, tick)
	for index in original.size():
		if not initial[index].position.is_equal_approx(anchor.position + original[index]):
			failures.append("the nozzle strip lost its last curve on release")
			break
	anchor.position.z -= 0.3
	var next: Array = world._released_nozzle_path(end, tick + 1)
	if not next[0].position.is_equal_approx(anchor.position) \
			or next[-1].position.distance_to(next[0].position) >= original[-1].length():
		failures.append("the detached strip did not follow the stream while shortening")


func _check_landing_droplet_pool(world) -> void:
	var pool := LandingDropletPool.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	pool.build(world, StandardMaterial3D.new(), 4, 16, 12)
	pool.spawn(Vector3.ZERO, 0, Color.WHITE, 2, 0.10, 0.02, 0.02, rng, 0.0)
	pool.spawn(Vector3.RIGHT * 4.0, 1, Color.YELLOW, 1, 1.0, 0.02, 0.02, rng, 0.0)
	pool.advance(0.02)
	if pool.multimesh.visible_instance_count != 3:
		failures.append("the landing pool submitted inactive slots")
	pool.advance(0.20)
	var survivor := pool.droplets[2]
	if pool.multimesh.visible_instance_count != 1 or survivor.render_index != 0 \
			or not is_equal_approx(pool._buffer[3], survivor.position.x) or pool._buffer[14] != Color.YELLOW.b:
		failures.append("a surviving droplet lost its live transform or sauce tint after compaction")
	pool.advance(2.0)
	if pool.multimesh.visible_instance_count != 0:
		failures.append("expired landing drops were still submitted")
	pool.instance.queue_free()


func _report_count(world, clip: AudioStream = null) -> int:
	var count := 0
	for node in world.get_children():
		if node is AudioStreamPlayer3D and node.playing and (clip == null or node.stream == clip):
			count += 1
	return count

