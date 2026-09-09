extends SceneTree

# Whipping the aim while firing must not tear the strand.
#
# A fast turn fans consecutive points sideways. The spacing constraint only
# corrects the gap projected along the strand, so it cannot close a lateral
# fan, and the gap crosses the distance break threshold at ordinary flick
# speeds. The burst still leaving the nozzle is therefore exempt from that
# threshold; a released one is not.

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
	var threshold: float = scene.point_spacing * scene.strand_break_spacing
	print("break threshold = %.3f m (%.1f x point_spacing)" % [threshold, scene.strand_break_spacing])

	var exercised := false
	# 480 deg/s is an ordinary flick at the default sensitivity: 400 px in 0.1 s.
	for rate in [0.0, 240.0, 480.0, 720.0, 1080.0]:
		var result := await _whip(scene, rate, threshold)
		print("%6.0f deg/s -> %d AIR segments, largest gap %.3f m, %d pairs past the threshold" % [
			rate, result.segments, result.largest_gap, result.over_threshold])
		if result.over_threshold > 0:
			exercised = true
		_check(result.phase_splits == 0,
			"a point changed phase at %.0f deg/s, so this case no longer isolates the distance rule" % rate)
		_check(result.segments == 1,
			"the strand tore into %d pieces while turning at %.0f deg/s" % [result.segments, rate])
	_check(exercised,
		"no turn rate pushed a pair past the break threshold, so the exemption was never tested")

	# A released strand must still be allowed to rupture.
	Input.action_release("fire_mayo")
	for _f in 24:
		await physics_frame
	var released: Array = scene._segments_for_phase(0, scene._camera.global_position)
	var stretched := 0
	for i in scene._points.size() - 1:
		var a = scene._points[i]
		var b = scene._points[i + 1]
		if a.phase == 0 and b.phase == 0 and a.burst_index == b.burst_index \
				and a.position.distance_to(b.position) > threshold:
			stretched += 1
	print("after release: %d AIR segments, %d stretched pairs" % [released.size(), stretched])
	if stretched > 0:
		_check(released.size() > 1,
			"a released strand with %d over-stretched pairs was still drawn as one piece" % stretched)

	if failures.is_empty():
		print("MAYO_WHIP_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _whip(scene, rate: float, threshold: float) -> Dictionary:
	scene._points.clear()
	scene.debug_set_aim(0.0, -8.0)
	Input.action_press("fire_mayo")
	for _f in 26:
		scene.debug_set_aim(rad_to_deg(scene._aim_yaw) + rate / 60.0, -8.0)
		await physics_frame
	var largest_gap := 0.0
	var over_threshold := 0
	var phase_splits := 0
	for i in scene._points.size() - 1:
		var a = scene._points[i]
		var b = scene._points[i + 1]
		if a.phase != 0 or b.phase != 0:
			phase_splits += 1
			continue
		if a.burst_index != b.burst_index:
			continue
		var gap: float = a.position.distance_to(b.position)
		largest_gap = maxf(largest_gap, gap)
		if gap > threshold:
			over_threshold += 1
	return {
		"segments": scene._segments_for_phase(0, scene._camera.global_position).size(),
		"largest_gap": largest_gap,
		"over_threshold": over_threshold,
		"phase_splits": phase_splits,
	}
