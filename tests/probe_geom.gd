extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var wall: ContaminableObject = scene.get_node("ImpactWall")
	print("atlas=%dx%d regions=%s" % [wall._atlas_width, wall._atlas_height, str(wall._face_regions)])

	# ImpactWall: centre (2.35, 1.1, -0.72), size (1.65, 2.2, 0.18).
	# +Z face is the one the player sees, at z = -0.72 + 0.09 = -0.63.
	var tests := [
		["+Z centre",      Vector3(2.35, 1.10, -0.63), Vector3(0, 0, 1)],
		["+Z left-low",    Vector3(1.65, 0.25, -0.63), Vector3(0, 0, 1)],
		["+Z right-high",  Vector3(3.05, 1.95, -0.63), Vector3(0, 0, 1)],
		["-X side",        Vector3(1.525, 1.10, -0.72), Vector3(-1, 0, 0)],
		["+Y top",         Vector3(2.35, 2.20, -0.72), Vector3(0, 1, 0)],
	]
	for t in tests:
		var before := wall.painted_cell_count()
		wall.paint_mayo(t[1], t[2])
		var face: int = wall._face_for_normal(t[2])
		var region: Vector4i = wall._face_regions[face]
		# Recover the cell the hit centre mapped to.
		var u_axis: Vector3 = ContaminableObject.FACE_BASIS[face][1]
		var v_axis: Vector3 = ContaminableObject.FACE_BASIS[face][2]
		var lp: Vector3 = wall.to_local(t[1])
		var cx := floori((lp.dot(u_axis) + wall._extent_along(u_axis) * 0.5) / wall.cell_size)
		var cy := floori((lp.dot(v_axis) + wall._extent_along(v_axis) * 0.5) / wall.cell_size)
		print("%-14s face=%d grid=%dx%d cell=(%d,%d) in_range=%s new_cells=%d" % [
			t[0], face, region.z, region.w, cx, cy,
			str(cx >= 0 and cy >= 0 and cx < region.z and cy < region.w),
			wall.painted_cell_count() - before])
	quit(0)
