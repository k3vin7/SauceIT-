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
	# The outline is still a hard cut on a filtered sample -- that is what makes
	# it marching squares -- but it is cut at half a *deposit* now rather than at
	# a fixed 0.5, because a cell with one splat on it is nowhere near the top of
	# a byte any more.
	_check(code.contains("step(paint_threshold, coverage)"),
		"the shader does not cut the outline at the paint threshold")
	# And the deep band is read unfiltered, so the cells drawn as slippery are
	# exactly the cells the slip test calls slippery.
	_check(code.contains("texelFetch(mask_texture"),
		"the deep band is filtered, so what is drawn can disagree with what trips you")
	_check(code.contains("step(slip_threshold, thickness)"),
		"the deep band is not cut at the slip threshold")
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

	# --- the texture the shader samples actually carries the mask ---
	# Everything else here reads `cells`, which is why an upload that wrote 1
	# into an R8 texture -- read back as 1/255, far under the 0.5 cut -- left
	# every surface in the game blank without a single check noticing.
	# Grid coordinates are the floor's own, and the floor no longer sits at the
	# world origin now that it carries the whole street, so every world point
	# here is built from the local one rather than assumed equal to it.
	# Painted several times: one splat now leaves a thickness, not a flag.
	for _splat in 8:
		floor_node.paint_mayo(floor_node.to_global(Vector3(2.0, 0.0, 2.0)))
	grid.upload_if_dirty()
	# grid.image is what is handed to texture.update. Reading the texture back
	# would be closer to what the shader sees, but headless has no GPU to read
	# it back from -- it returns the blank image it was created with.
	# Read back out of `cells`, which *is* the texture's bytes now: a thickness
	# is already exactly what an R8 texture wants, so the parallel 0/255 array
	# that used to be kept beside it is gone.
	var marked := grid.cell_of(Vector2(2.0, 2.0))
	var painted_texel: int = grid.cells[marked.y * grid.width + marked.x]
	var clean_texel: int = grid.cells[0]
	var cut := maxf(float(floor_node.thickness_per_pass) * 0.5, 0.5)
	print("uploaded texel: painted cell reads %d, clean cell reads %d (the outline cuts at %.1f)" % [
		painted_texel, clean_texel, cut])
	_check(painted_texel > 0, "the test splat did not mark the cell it was aimed at")
	_check(float(painted_texel) > cut,
		"a painted cell holds %d, under the outline's cut of %.1f: it would not be drawn"
			% [painted_texel, cut])
	_check(clean_texel == 0, "a clean cell holds %d rather than 0" % clean_texel)
	# And wiping has to take the texture with it, not just the mask.
	grid.clear()
	grid.upload_if_dirty()
	_check(grid.cells[marked.y * grid.width + marked.x] == 0,
		"clearing the grid left the stain behind")

	# --- the 0.5 crossing sits on the cell boundary ---
	# A block of cells filled directly, then walked across in fine steps. Built
	# from the cells rather than from splats because this is a claim about the
	# shader's maths, not about the brush: a block of overlapping splats has a
	# roughened outer edge, and how rough depends on the brush radius.
	var centre := Vector3(0.0, 0.0, 0.0)
	var block := grid.cell_of(Vector2(centre.x, centre.z))
	for offset_x in range(-6, 7):
		for offset_y in range(-6, 7):
			var cell := block + Vector2i(offset_x, offset_y)
			if grid.has_cell(cell):
				grid.cells[cell.y * grid.width + cell.x] = 1
	grid.dirty = true
	# Filled to one deposit and cut at half of one, which is the case the
	# outline's marching-squares property is actually claimed for: the outermost
	# cells of a real stain are the ones a single splat only just reached.
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
			if rendered != floor_node.is_mayo_at(floor_node.to_global(probe)):
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
