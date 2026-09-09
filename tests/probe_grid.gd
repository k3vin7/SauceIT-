extends SceneTree

# Confirms the rendered boundary and the slip test cannot drift apart:
#   * the shader cuts at exactly 0.5, with linear filtering, no mipmaps, clamped
#   * the 0.5 crossing lands exactly on a cell boundary
#   * is_mayo_at agrees with the rendered coverage everywhere except the corner
#     cells that marching squares deliberately bevels

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
	var floor_node: FloorContamination = scene._floor
	var grid: ContaminationGrid = floor_node.grid
	print("floor grid %dx%d at %.2f m/cell, brush radius %.2f m" % [
		grid.width, grid.height, grid.cell_size, floor_node.brush_radius])

	# --- sampler settings ---
	var code: String = grid.material.shader.code
	_check(code.contains("step(THRESHOLD, coverage)") and code.contains("THRESHOLD = 0.5"),
		"the shader does not cut at exactly 0.5")
	var sampler := ""
	for line in code.split("\n"):
		if line.begins_with("uniform sampler2D mask_texture"):
			sampler = line
	print("sampler declaration: %s" % sampler)
	_check(sampler.contains("filter_linear") and not sampler.contains("mipmap"),
		"mask sampler is not plain bilinear without mipmaps: %s" % sampler)
	_check(sampler.contains("repeat_disable"), "mask sampler does not clamp at the texture edge: %s" % sampler)
	_check(not grid.image.has_mipmaps(), "mask image was generated with mipmaps")
	_check(grid.texture.get_image().get_format() == Image.FORMAT_R8,
		"mask texture is not a single-channel mask")
	print("shader: step at 0.5, filter_linear, repeat_disable; image mipmaps=%s format=%s" % [
		str(grid.image.has_mipmaps()), str(grid.texture.get_image().get_format())])

	# --- the 0.5 crossing sits on the cell boundary ---
	# Paint a block, then walk across one of its straight edges in fine steps.
	var centre := Vector3(0.0, 0.0, 0.0)
	for offset_x in range(-6, 7):
		for offset_z in range(-6, 7):
			floor_node.paint_mayo(centre + Vector3(offset_x, 0.0, offset_z) * grid.cell_size)
	var crossing := _find_crossing(floor_node, grid, centre)
	var boundary := _nearest_cell_boundary(grid, crossing)
	print("bilinear 0.5 crossing at x=%.5f m, nearest cell boundary x=%.5f m, error %.6f m" % [
		crossing, boundary, absf(crossing - boundary)])
	_check(absf(crossing - boundary) < 0.0005,
		"the rendered boundary is %.4f m off the cell boundary" % absf(crossing - boundary))

	# --- rendered coverage vs the slip test over a real splat ---
	var mismatch := 0
	var total := 0
	var worst := 0.0
	for step_x in 400:
		for step_z in 400:
			var probe := Vector3(-2.0 + float(step_x) * 0.01, 0.0, -2.0 + float(step_z) * 0.01)
			var local := Vector2(probe.x, probe.z)
			if not grid.has_cell(grid.cell_of(local)):
				continue
			total += 1
			var rendered := grid.sample_bilinear(local) >= 0.5
			if rendered != floor_node.is_mayo_at(probe):
				mismatch += 1
				worst = maxf(worst, _distance_to_cell_edge(grid, local))
	print("rendered vs slip test over %d samples: %d disagree (%.3f%%), all within %.4f m of a cell edge" % [
		total, mismatch, 100.0 * float(mismatch) / float(total), worst])
	_check(float(mismatch) / float(total) < 0.02,
		"rendered coverage and the slip test disagree on %.2f%% of the floor" % (100.0 * float(mismatch) / float(total)))
	_check(worst <= grid.cell_size * 0.75,
		"a disagreement sat %.4f m from a cell edge, further than one cell allows" % worst)

	if failures.is_empty():
		print("MAYO_GRID_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


## Scans +x from a painted centre for where the bilinear mask crosses 0.5.
func _find_crossing(floor_node: FloorContamination, grid: ContaminationGrid, centre: Vector3) -> float:
	var x := centre.x
	while x < centre.x + 2.0:
		if grid.sample_bilinear(Vector2(x, centre.z)) < 0.5:
			# Bisect the last step for the exact crossing.
			var low := x - 0.0005
			var high := x
			for _i in 40:
				var mid := (low + high) * 0.5
				if grid.sample_bilinear(Vector2(mid, centre.z)) >= 0.5:
					low = mid
				else:
					high = mid
			return (low + high) * 0.5
		x += 0.0005
	return NAN


func _nearest_cell_boundary(grid: ContaminationGrid, x: float) -> float:
	var shifted := (x + grid.extent.x * 0.5) / grid.cell_size
	return roundf(shifted) * grid.cell_size - grid.extent.x * 0.5


func _distance_to_cell_edge(grid: ContaminationGrid, local: Vector2) -> float:
	var in_cell_x := fposmod((local.x + grid.extent.x * 0.5) / grid.cell_size, 1.0)
	var in_cell_y := fposmod((local.y + grid.extent.y * 0.5) / grid.cell_size, 1.0)
	return minf(minf(in_cell_x, 1.0 - in_cell_x), minf(in_cell_y, 1.0 - in_cell_y)) * grid.cell_size
