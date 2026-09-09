extends SceneTree

# Burst boundary checks:
#   1. a new burst does not join the ribbon of one still falling, including
#      after a pause too short for the distance rule to catch
#   2. a falling burst is not dragged toward the new one
#   3. a burst bends on its own weighting, whether or not an older burst is
#      still in the array

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.push_back(message)


func _run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process_unhandled_input(false)
	scene.debug_set_aim(0.0, 0.0)

	# --- 2. a released burst must fall the same whether or not you fire again
	var free_fall := await _tail_travel(scene, false)
	await _settle(scene)
	var with_second := await _tail_travel(scene, true)
	print("released burst tail travel over 12 frames: %.3f m alone, %.3f m while a new burst fires" % [
		free_fall, with_second])
	_check(free_fall > 0.3, "control burst did not fall, so the comparison is meaningless")
	_check(with_second < free_fall * 1.05 + 0.01,
		"falling burst was dragged by the new burst: %.3f m vs %.3f m in free fall" % [
			with_second, free_fall])

	# --- 1a. long pause: the two bursts must be separate ribbon segments
	await _settle(scene)
	var long_pause := await _two_bursts(scene, 14)
	print("long pause:  gap %.3f m (threshold %.3f m) -> AIR segments = %d, sizes %s" % [
		long_pause.gap, long_pause.threshold, long_pause.segments.size(),
		str(long_pause.segments.map(func(seg): return seg.size()))])
	_check(long_pause.segments.size() >= 2, "the two bursts were drawn as one ribbon segment")

	# --- 1b. short pause: gap stays under the distance threshold, so only the
	# burst index can separate them
	await _settle(scene)
	var short_pause := await _two_bursts(scene, 3)
	print("short pause: gap %.3f m (threshold %.3f m) -> AIR segments = %d, sizes %s" % [
		short_pause.gap, short_pause.threshold, short_pause.segments.size(),
		str(short_pause.segments.map(func(seg): return seg.size()))])
	_check(short_pause.gap < short_pause.threshold,
		"short pause gap %.3f m exceeded the distance threshold, so this case does not test the burst index" % short_pause.gap)
	_check(short_pause.segments.size() >= 2,
		"a short pause left both bursts in one ribbon segment: the burst index is not separating them")

	# --- 3. bend must not depend on what else is in the array
	await _settle(scene)
	var lone_bow := await _strafe_bow(scene, false)
	await _settle(scene)
	var trailing_bow := await _strafe_bow(scene, true)
	print("bow after 20 frames of strafing fire: %.4f m alone, %.4f m with an older burst still alive" % [
		lone_bow, trailing_bow])
	_check(lone_bow > 0.05, "strafing while firing produced no bow at all")
	_check(trailing_bow > lone_bow * 0.6,
		"an older burst in the array flattened the new strand's bend: %.4f m vs %.4f m alone" % [
			trailing_bow, lone_bow])

	if failures.is_empty():
		print("MAYO_BURST_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _settle(scene) -> void:
	for action in ["fire_mayo", "move_right"]:
		if Input.is_action_pressed(action):
			Input.action_release(action)
	scene._points.clear()
	for _f in 20:
		await physics_frame
	scene._rng.seed = 0x4d41594f


## Fires a burst, releases it, and returns how far its muzzle-end point travels
## over the next 12 frames. With `second_burst`, a new burst is fired during
## those frames, which is what must not change the answer.
func _tail_travel(scene, second_burst: bool) -> float:
	scene._rng.seed = 0x4d41594f
	Input.action_press("fire_mayo")
	for _f in 20:
		await physics_frame
	Input.action_release("fire_mayo")
	for _f in 14:
		await physics_frame
	var count: int = scene._points.size()
	if count == 0:
		return 0.0
	var before: Vector3 = scene._points[count - 1].position
	if second_burst:
		Input.action_press("fire_mayo")
	for _f in 12:
		await physics_frame
	if second_burst:
		Input.action_release("fire_mayo")
	if scene._points.size() < count:
		return 0.0
	return before.distance_to(scene._points[count - 1].position)


## Fires a burst, pauses for `pause_frames`, then starts a second one and
## reports the gap between them and the resulting AIR ribbon segments.
func _two_bursts(scene, pause_frames: int) -> Dictionary:
	Input.action_press("fire_mayo")
	for _f in 18:
		await physics_frame
	Input.action_release("fire_mayo")
	for _f in pause_frames:
		await physics_frame
	var count: int = scene._points.size()
	var tail: Vector3 = scene._points[count - 1].position
	Input.action_press("fire_mayo")
	await physics_frame
	var head: Vector3 = scene._points[scene._points.size() - 1].position
	Input.action_release("fire_mayo")
	return {
		"gap": tail.distance_to(head),
		"threshold": scene.point_spacing * scene.strand_break_spacing,
		"segments": scene._segments_for_phase(0, scene._camera.global_position),
	}


## Bow of a burst fired while strafing. With `trailing`, an earlier burst is
## left falling in the array first, which must not change the result.
func _strafe_bow(scene, trailing: bool) -> float:
	if trailing:
		Input.action_press("fire_mayo")
		for _f in 18:
			await physics_frame
		Input.action_release("fire_mayo")
		for _f in 3:
			await physics_frame
	Input.action_press("fire_mayo")
	Input.action_press("move_right")
	for _f in 20:
		await physics_frame
	var burst: int = scene._burst_index
	Input.action_release("move_right")
	Input.action_release("fire_mayo")
	var air: Array = []
	for point in scene._points:
		if point.phase == 0 and point.burst_index == burst:
			air.push_back(point.position)
	return _bow_of(air)


## Largest deviation of a strand from the straight line joining its ends.
func _bow_of(air: Array) -> float:
	if air.size() < 3:
		return 0.0
	var first: Vector3 = air[0]
	var axis: Vector3 = air[-1] - first
	if axis.length_squared() < 0.000001:
		return 0.0
	axis = axis.normalized()
	var worst := 0.0
	for position in air:
		var offset: Vector3 = position - first
		worst = maxf(worst, (offset - axis * offset.dot(axis)).length())
	return worst
