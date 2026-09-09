extends SceneTree

# Confirms each wall face has its own grid and that a world impact lands in the
# cell its position implies, on the face its normal implies.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var wall: ContaminableObject = scene.get_node("ImpactWall")
	print("cell_size=%.2f m  brush_radius=%.2f m  faces=%d" % [
		wall.cell_size, wall.brush_radius, wall.grids.size()])
	for i in wall.grids.size():
		var grid: ContaminationGrid = wall.grids[i]
		print("  face %d: extent %.2v m -> grid %dx%d" % [i, grid.extent, grid.width, grid.height])

	# ImpactWall: centre (2.35, 1.1, -0.72), size (1.65, 2.2, 0.18).
	# Its +Z face is the one the player sees, at z = -0.72 + 0.09 = -0.63.
	var tests := [
		["+Z centre", Vector3(2.35, 1.10, -0.63), Vector3(0, 0, 1)],
		["+Z left-low", Vector3(1.65, 0.25, -0.63), Vector3(0, 0, 1)],
		["+Z right-high", Vector3(3.05, 1.95, -0.63), Vector3(0, 0, 1)],
		["-X side", Vector3(1.525, 1.10, -0.72), Vector3(-1, 0, 0)],
		["+Y top", Vector3(2.35, 2.20, -0.72), Vector3(0, 1, 0)],
	]
	for t in tests:
		var before := wall.painted_cell_count()
		wall.paint_mayo(t[1], t[2])
		var face: int = wall._face_for_normal(t[2])
		var grid: ContaminationGrid = wall.grids[face]
		var u_axis: Vector3 = ContaminableObject.FACE_BASIS[face][1]
		var v_axis: Vector3 = ContaminableObject.FACE_BASIS[face][2]
		var local: Vector3 = wall.to_local(t[1])
		var cell := grid.cell_of(Vector2(local.dot(u_axis), local.dot(v_axis)))
		print("%-14s face=%d grid=%dx%d cell=%v in_range=%s new_cells=%d" % [
			t[0], face, grid.width, grid.height, cell, str(grid.has_cell(cell)),
			wall.painted_cell_count() - before])
	quit(0)
