extends SceneTree

# The minimap in the top-right corner.
#
# Checked by arithmetic rather than by looking at it: a HUD element that lands
# in the wrong place is invisible rather than visibly wrong, which is how the
# enemy health bars spent a while not appearing at all.
#
#   * it sits inside the view frame, in the top-right corner
#   * the street picture is baked and covers the whole map, padded enough that
#     the window drawn never samples outside it
#   * the player is dead centre wherever they stand, and the map slides under
#     them rather than jumping a cell at a time
#   * what it shows is the street the player is actually on

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
	var map: Minimap = scene._minimap
	var player: MayoPlayer = scene._player
	_check(map != null, "there is no minimap")

	# --- where it sits ---
	var frame: Rect2 = map.frame
	var box := Rect2(
		Vector2(frame.position.x + frame.size.x - Minimap.SIZE - Minimap.MARGIN,
			frame.position.y + Minimap.MARGIN),
		Vector2(Minimap.SIZE, Minimap.SIZE))
	print("view %s -> minimap %s (%.0f px square)" % [str(frame), str(box), Minimap.SIZE])
	_check(frame.encloses(box), "the minimap hangs outside the view frame")
	# Top-right: nearer the frame's right edge and top than its left and bottom.
	_check(box.get_center().x > frame.get_center().x,
		"the minimap is on the left of the screen")
	_check(box.get_center().y < frame.get_center().y,
		"the minimap is on the bottom of the screen")

	# --- the baked picture ---
	var texture: ImageTexture = map._texture
	_check(texture != null, "the street picture was never baked")
	var bounds := StreetMap.bounds()
	var size := texture.get_size()
	print("street picture %dx%d for a %dx%d map, origin cell %s" % [
		size.x, size.y, bounds.size.x, bounds.size.y, str(map._image_origin)])
	# Padded by at least a full window on every side, or the corners of the map
	# would sample off the edge of the texture.
	var pad_low := bounds.position - map._image_origin
	var pad_high := Vector2i(size) - (bounds.end - map._image_origin)
	_check(mini(pad_low.x, pad_low.y) >= int(Minimap.VIEW_CELLS)
			and mini(pad_high.x, pad_high.y) >= int(Minimap.VIEW_CELLS),
		"the picture is padded by %s / %s, under the %d-cell window" % [
			str(pad_low), str(pad_high), int(Minimap.VIEW_CELLS)])

	# Every street cell is drawn, and nothing that is not street is.
	var image := texture.get_image()
	var street := StreetMap.floor_cells()
	var missing := 0
	for cell in street:
		var at: Vector2i = cell - map._image_origin
		if image.get_pixel(at.x, at.y).a < 0.5:
			missing += 1
	var painted := 0
	for y in size.y:
		for x in size.x:
			if image.get_pixel(x, y).a >= 0.5:
				painted += 1
	print("picture: %d pixels drawn for %d street cells, %d cells missing" % [
		painted, street.size(), missing])
	_check(missing == 0, "%d street cells are missing from the picture" % missing)
	_check(painted == street.size(),
		"the picture draws %d pixels for %d street cells" % [painted, street.size()])

	# --- the player is centred, and the window follows them ---
	var stand: float = scene.spawn_position_for(0).y
	var places := [
		["the start zone", scene.spawn_position_for(0)],
		["the festival square", StreetMap.arena_centre() + Vector3(0.0, stand, 0.0)],
		["the round place", StreetMap.circle_centre() + Vector3(0.0, stand, 0.0)],
	]
	for place in places:
		var label: String = place[0]
		var at: Vector3 = place[1]
		player.global_position = at
		await physics_frame
		var centre: Vector2 = map._cell_of(player.global_position)
		# The window the texture is drawn from, in image pixels.
		var region := Rect2(
			centre - Vector2(Minimap.VIEW_CELLS, Minimap.VIEW_CELLS) - Vector2(map._image_origin),
			Vector2(Minimap.VIEW_CELLS, Minimap.VIEW_CELLS) * 2.0)
		print("%-20s player cell %.1v -> window %s" % [label, centre, str(region)])
		_check(region.position.x >= 0.0 and region.position.y >= 0.0
				and region.end.x <= float(size.x) and region.end.y <= float(size.y),
			"at %s the window %s falls outside the %dx%d picture" % [
				label, str(region), size.x, size.y])
		# The cell under the middle of the window is the one the player is on,
		# which is what "centred on me" means.
		var middle := Vector2i(floor(centre.x), floor(centre.y))
		_check(street.has(middle),
			"at %s the player's own cell %s is not street" % [label, str(middle)])
		_check(image.get_pixel(middle.x - map._image_origin.x,
				middle.y - map._image_origin.y).a >= 0.5,
			"at %s the cell under the player is blank on the map" % label)

	# The window has to slide, not step: half a cell of movement has to move it.
	player.global_position = scene.spawn_position_for(0)
	await physics_frame
	var before: Vector2 = map._cell_of(player.global_position)
	player.global_position += Vector3(StreetMap.CELL * 0.5, 0.0, 0.0)
	await physics_frame
	var after: Vector2 = map._cell_of(player.global_position)
	print("half a cell of walking moved the window by %.3f cells" % (after.x - before.x))
	_check(absf((after.x - before.x) - 0.5) < 0.01,
		"half a cell of walking moved the map by %.3f cells: it is stepping, not sliding"
			% (after.x - before.x))

	# --- what it marks ---
	print("marks: %d stalls, %d landmarks, %d enemies" % [
		map._stall_cells.size(), map._landmark_cells.size(), scene.enemy_count()])
	_check(map._stall_cells.size() == StreetMap.stall_boxes().size(),
		"the map marks %d of %d stalls" % [
			map._stall_cells.size(), StreetMap.stall_boxes().size()])
	_check(map._landmark_cells.size() == 2, "the stage and the tower are not both marked")

	if failures.is_empty():
		print("MAYO_MINIMAP_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
