extends SceneTree

# What a frame of painting actually sends to the GPU.
#
# Headless cannot time an upload -- there is no GPU, so `texture.update` is a
# no-op and timing it reports a number that means nothing. What it *can* count
# is bytes, and bytes are the thing that changed: the floor used to be one
# texture, so any cell changing meant re-sending the whole mask.
#
# Why tiles and not a dirty rectangle: Godot's public API has no partial update
# for a 2D texture. `ImageTexture.update` replaces the whole texture, so knowing
# exactly which cells changed buys nothing on its own -- the upload is
# all-or-nothing per texture. Making the textures smaller is the only lever, and
# that is what a tile is.

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
	await physics_frame
	scene.set_process_unhandled_input(false)
	scene.debug_clear_enemies()
	scene.debug_input_override = true
	var floor_node: FloorContamination = scene._floor
	var grid: ContaminationGrid = floor_node.grid

	var whole := grid.width * grid.height
	print("floor mask %dx%d = %.1f M cells (%.1f MB), %d tiles of %d cells" % [
		grid.width, grid.height, whole / 1e6, whole / 1048576.0,
		grid.tile_count(), floor_node.tile_cells])
	_check(grid.tile_count() > 1, "the floor is a single tile, so nothing is partial")

	# --- one splat costs one tile, not the whole floor ---
	grid.clear()
	grid.upload_if_dirty()
	var last_total: int = grid.bytes_uploaded_total
	floor_node.paint_mayo(floor_node.to_global(Vector3(3.0, 0.0, 3.0)))
	grid.upload_if_dirty()
	var one_splat := grid.bytes_uploaded_total - last_total
	print("one splat: %d bytes uploaded (%.0f KB); the whole mask is %.1f MB" % [
		one_splat, one_splat / 1024.0, whole / 1048576.0])
	_check(one_splat > 0, "a splat uploaded nothing at all")
	_check(one_splat < whole / 8,
		"a splat sent %d bytes of a %d-byte mask: that is not a partial upload"
			% [one_splat, whole])

	# --- and a real frame of firing ---
	grid.clear()
	grid.upload_if_dirty()
	scene._local.sauce = 1.0
	scene.debug_set_aim(0.0, -38.0)
	await physics_frame
	scene.debug_set_input(Vector2(0.0, -1.0), false, true)
	# Measured as differences of the running total, not by reading "what the
	# last upload cost". The floor uploads from `_process`, which runs on
	# rendered frames, so on any frame this loop looks at, that value may be
	# left over from an upload several frames ago -- which is how an earlier
	# version of this check reported the whole mask being sent every frame when
	# a single tile was.
	var frames := 0
	var painting_frames := 0
	var worst := 0
	var total := 0
	last_total = grid.bytes_uploaded_total
	for _f in 120:
		scene._local.sauce = 1.0
		await physics_frame
		frames += 1
		var sent := grid.bytes_uploaded_total - last_total
		last_total = grid.bytes_uploaded_total
		if sent > 0:
			painting_frames += 1
			worst = maxi(worst, sent)
			total += sent
	scene.debug_set_input(Vector2.ZERO, false, false)
	var mean := 0 if painting_frames == 0 else total / painting_frames
	print("firing for %d frames: %d of them uploaded, mean %.0f KB, worst %.0f KB" % [
		frames, painting_frames, mean / 1024.0, worst / 1024.0])
	print("  before tiling the same frames would each have sent %.1f MB" % (whole / 1048576.0))
	print("  saving on the worst frame: %.0fx" % (float(whole) / maxf(float(worst), 1.0)))
	_check(painting_frames > 0, "firing at the floor uploaded nothing, so this tests nothing")
	_check(worst < whole / 4,
		"the worst painting frame sent %d bytes of a %d-byte mask" % [worst, whole])

	# --- frames with nothing landing send nothing ---
	# The strand is still in the air when the trigger comes up and goes on
	# landing for a while, so the wait is for it to drain rather than for a
	# count of frames -- letting go is not the same thing as nothing arriving.
	for _f in 240:
		await physics_frame
		if scene._points.is_empty():
			break
	last_total = grid.bytes_uploaded_total
	for _f in 30:
		await physics_frame
	var idle_bytes := grid.bytes_uploaded_total - last_total
	print("30 idle frames: %d bytes uploaded" % idle_bytes)
	_check(idle_bytes == 0, "idle frames still uploaded %d bytes" % idle_bytes)

	# --- the tiles that were sent are the tiles that changed ---
	# A splat in one corner must not dirty a tile in another.
	grid.clear()
	grid.upload_if_dirty()
	last_total = grid.bytes_uploaded_total
	floor_node.paint_mayo(floor_node.to_global(Vector3(
		-grid.extent.x * 0.4, 0.0, -grid.extent.y * 0.4)))
	grid.upload_if_dirty()
	var corner := grid.bytes_uploaded_total - last_total
	last_total = grid.bytes_uploaded_total
	floor_node.paint_mayo(floor_node.to_global(Vector3(
		grid.extent.x * 0.4, 0.0, grid.extent.y * 0.4)))
	grid.upload_if_dirty()
	var far_corner := grid.bytes_uploaded_total - last_total
	print("splat in one corner: %.0f KB; then the opposite corner: %.0f KB" % [
		corner / 1024.0, far_corner / 1024.0])
	_check(corner > 0 and far_corner > 0, "a corner splat uploaded nothing")
	_check(corner + far_corner < whole,
		"two splats in opposite corners sent more than the whole mask")

	if failures.is_empty():
		print("MAYO_UPLOAD_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
