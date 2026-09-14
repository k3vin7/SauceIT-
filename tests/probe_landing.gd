extends SceneTree

# Reports where points actually land, to check two things:
#   * sustained fire disperses landings instead of stacking them on one spot
#   * after release, landings walk from max range back toward the muzzle

var mode := "full"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		mode = args[0]
	call_deferred("_run")


func _run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame
	if mode == "nojitter":
		scene.speed_magnitude_jitter = 0.0
	if mode == "noloss":
		scene.release_pressure_loss = 0.0
	print("mode=%s speed_magnitude_jitter=%.2f release_pressure_loss=%.2f curve=%.1f" % [
		mode, scene.speed_magnitude_jitter, scene.release_pressure_loss, scene.release_pressure_curve])

	# Record every floor landing with its range from the muzzle and its time.
	var landings: Array = []
	var muzzle_flat: Vector3 = scene._muzzle.global_position
	muzzle_flat.y = 0.0
	var seen := {}
	var release_frame := 180
	# Aim straight down -Z, level. There is no cursor to warp any more.
	scene.debug_set_aim(0.0, 0.0)
	Input.action_press("fire_mayo")
	for frame in 420:
		if frame == release_frame:
			Input.action_release("fire_mayo")
		await physics_frame
		for point in scene._points:
			if point.phase == 1:
				var key: int = point.get_instance_id()
				if not seen.has(key):
					seen[key] = true
					var flat: Vector3 = point.position
					flat.y = 0.0
					landings.push_back([frame, flat.distance_to(muzzle_flat), point.phase])

	var sustained: Array[float] = []
	var after: Array = []
	for entry in landings:
		if entry[2] != 1:
			continue
		if entry[0] < release_frame:
			sustained.push_back(entry[1])
		else:
			after.push_back(entry)

	print("SUSTAINED landings=%d range_min=%.3f range_max=%.3f spread=%.3f m stddev=%.3f m" % [
		sustained.size(), sustained.min(), sustained.max(),
		sustained.max() - sustained.min(), _stddev(sustained)])

	# Bucket the post-release landings into 4 equal time slices.
	print("AFTER RELEASE (%d landings) mean range per time slice:" % after.size())
	if after.is_empty():
		quit(0)
	var first: int = after[0][0]
	var last: int = after[-1][0]
	var span := maxi(last - first, 1)
	for slice in 4:
		var lo := first + span * slice / 4
		var hi := first + span * (slice + 1) / 4
		var vals: Array[float] = []
		for entry in after:
			if entry[0] >= lo and (entry[0] < hi or (slice == 3 and entry[0] <= hi)):
				vals.push_back(entry[1])
		if vals.is_empty():
			continue
		print("  t=%+.2f..%+.2fs  n=%2d  mean_range=%.3f m  [%.2f .. %.2f]" % [
			float(lo - release_frame) / 60.0, float(hi - release_frame) / 60.0,
			vals.size(), _mean(vals), vals.min(), vals.max()])
	quit(0)


func _mean(a: Array[float]) -> float:
	var s := 0.0
	for v in a:
		s += v
	return s / maxi(a.size(), 1)


func _stddev(a: Array[float]) -> float:
	if a.size() < 2:
		return 0.0
	var m := _mean(a)
	var acc := 0.0
	for v in a:
		acc += (v - m) * (v - m)
	return sqrt(acc / float(a.size()))
