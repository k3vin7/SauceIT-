extends SceneTree

# Whipping the aim while firing is MEANT to tear the strand.
#
# A fast turn fans consecutive points sideways. The spacing constraint only
# corrects the gap projected along the strand, so it cannot close a lateral
# fan, and the gap crosses Strand Break Spacing. The strand splits there and
# stays split, because the same check also stops the constraint pulling that
# pair back together.
#
# This is intended, not a defect: exempting the burst still leaving the nozzle
# would keep it in one piece, and that was tried and rejected. The checks below
# pin the tearing down so it does not get "fixed" again.

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

	# A steady aim must stay in one piece; only turning should tear it.
	var steady := await _whip(scene, 0.0, threshold)
	print("%6.0f deg/s -> %d AIR segments, largest gap %.3f m, %d pairs past the threshold" % [
		0.0, steady.segments, steady.largest_gap, steady.over_threshold])
	_check(steady.segments == 1, "a steady aim tore the strand into %d pieces" % steady.segments)
	_check(steady.over_threshold == 0, "a steady aim already stretched a pair past the threshold")

	# Turning fast must tear it, and harder turns must tear it into more pieces.
	var previous := 1
	for rate in [480.0, 720.0, 1080.0]:
		var result := await _whip(scene, rate, threshold)
		print("%6.0f deg/s -> %d AIR segments, largest gap %.3f m, %d pairs past the threshold" % [
			rate, result.segments, result.largest_gap, result.over_threshold])
		_check(result.segments > 1,
			"turning at %.0f deg/s did not tear the strand" % rate)
		_check(result.segments >= previous,
			"turning at %.0f deg/s tore the strand into fewer pieces (%d) than the slower turn (%d)" % [
				rate, result.segments, previous])
		previous = result.segments

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
	Input.action_release("fire_mayo")
	var largest_gap := 0.0
	var over_threshold := 0
	for i in scene._points.size() - 1:
		var a = scene._points[i]
		var b = scene._points[i + 1]
		if a.phase != 0 or b.phase != 0 or a.burst_index != b.burst_index:
			continue
		var gap: float = a.position.distance_to(b.position)
		largest_gap = maxf(largest_gap, gap)
		if gap > threshold:
			over_threshold += 1
	var result := {
		"segments": scene._segments_for_phase(0, scene._camera.global_position).size(),
		"largest_gap": largest_gap,
		"over_threshold": over_threshold,
	}
	await physics_frame
	return result
