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


func _report_count(world, clip: AudioStream = null) -> int:
	var count := 0
	for node in world.get_children():
		if node is AudioStreamPlayer3D and node.playing and (clip == null or node.stream == clip):
			count += 1
	return count

