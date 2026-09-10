extends SceneTree

# A player's body is contaminable too, and the grid on it is the same grid the
# floor and the walls use -- the body unwrapped about its own axis, u the angle
# and v the height. What that has to get right:
#   * spraying a body marks it, and marks the side that was actually hit
#   * the u axis is a loop: a splat at the seam carries on round the far side
#     instead of being clipped in half
#   * the mask follows the body when it walks and turns, because it is stored in
#     the body's own space
#   * a splat replayed from its centre cell reproduces the same mask, so a body
#     travels over the network the way the floor does
#   * the floor is untouched by any of it: bodies are cosmetic, and slipping
#     still reads the floor alone
#   * a splat on your own body puts sauce on your camera, on the side it came
#     from, and R wipes the lot
#   * being hit again does not push off what is already on the glass: a burst is
#     ~78 splats a second and the cap is 18, so sauce on the lens is throttled

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.push_back(message)


## Fires at `target` from wherever the shooter is until the strand has had time
## to get there and land, and returns how many new cells appeared on the body.
func _spray_at(scene, body, target: Vector3, frames: int) -> int:
	var before: int = body.painted_cell_count()
	scene.debug_aim_at(target)
	for _f in frames:
		scene._emit_point()
		scene._simulate_points(1.0 / 60.0)
		await physics_frame
	return body.painted_cell_count() - before


func _run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await physics_frame
	scene.set_process_unhandled_input(false)
	scene.set_physics_process(false)

	# A second body to shoot at: the strand never hits the shooter's own, which
	# is excluded from the cast so the muzzle is not firing into their chest.
	var mark = scene.create_avatar(2, 1, false)
	var target_player = mark.player
	var body = target_player.contamination
	target_player.global_position = Vector3(0.0, 0.64, -1.6)
	await physics_frame
	print("body grid: %dx%d cells of %.3f m, brush %.3f m" % [
		body.grid.width, body.grid.height, body.cell_size, body.brush_radius])
	_check(body.grid.wrap_x, "the body grid does not wrap, so its seam will clip splats")
	_check(body.painted_cell_count() == 0, "the body started out already dirty")

	var floor_before: int = scene._floor.grid.painted_cell_count()

	# --- spraying a body marks it, on the side that was hit ---
	var chest: Vector3 = target_player.global_position + Vector3(0.0, 0.2, 0.32)
	var marked: int = await _spray_at(scene, body, chest, 60)
	print("sprayed the near side: %d cells marked, %.1f%% of the body" % [
		marked, body.coverage() * 100.0])
	_check(marked > 0, "spraying a body did not mark it at all")
	_check(body.coverage() < 0.5,
		"one burst covered %.0f%% of the body, so the brush is far too big"
			% (body.coverage() * 100.0))

	# The hit came from +Z, so the mark belongs in the +Z half of the unwrap:
	# u is the angle about Y, and atan2(0, +1) is 0, the middle column.
	var near_column: int = body.grid.width / 2
	var near := 0
	var far := 0
	for y in body.grid.height:
		for x in body.grid.width:
			if body.grid.cells[y * body.grid.width + x] != 1:
				continue
			# Distance round the loop, not across it.
			var gap: int = absi(x - near_column)
			gap = mini(gap, body.grid.width - gap)
			if gap <= body.grid.width / 4:
				near += 1
			else:
				far += 1
	print("marks on the side facing the shooter: %d, on the far side: %d" % [near, far])
	_check(near > 0, "nothing was marked on the side the strand came from")
	_check(far == 0, "%d cells were marked on the side away from the strand" % far)

	# --- the seam is a loop, not an edge ---
	# Painted straight at the back of the body, whose unwrap sits at the seam:
	# the splat has to appear on both ends of the grid, not be cut in half.
	var fresh = scene.create_avatar(3, 1, false)
	var seam_body = fresh.player.contamination
	fresh.player.global_position = Vector3(4.0, 0.64, 0.0)
	await physics_frame
	# Local -Z is the far side of the unwrap, where column 0 and the last column
	# meet, so this is the splat that would be clipped without the wrap.
	seam_body.paint_mayo(fresh.player.to_global(Vector3(0.0, 0.0, -0.32)), Vector3.BACK)
	var left_edge := 0
	var right_edge := 0
	for y in seam_body.grid.height:
		if seam_body.grid.cells[y * seam_body.grid.width] == 1:
			left_edge += 1
		if seam_body.grid.cells[y * seam_body.grid.width + seam_body.grid.width - 1] == 1:
			right_edge += 1
	print("seam splat: %d cells in the first column, %d in the last" % [left_edge, right_edge])
	_check(left_edge > 0 and right_edge > 0,
		"a splat on the seam only reached one side of it (%d / %d)" % [left_edge, right_edge])

	# --- the mask is in the body's own space, so it travels with the body ---
	var before_move: String = body.cells_md5()
	target_player.global_position += Vector3(3.0, 0.0, 2.0)
	target_player.rotation.y += 1.1
	await physics_frame
	print("after walking and turning: mask unchanged=%s" % str(body.cells_md5() == before_move))
	_check(body.cells_md5() == before_move,
		"the stain changed when the body moved, so it is not stored on the body")

	# --- a body replays from centre cells like every other surface ---
	var replay = scene.create_avatar(4, 1, false)
	var replay_body = replay.player.contamination
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x424f4459
	var source = scene.create_avatar(5, 1, false)
	var source_body = source.player.contamination
	for _i in 40:
		var cell := Vector2i(rng.randi_range(-4, source_body.grid.width + 4),
			rng.randi_range(0, source_body.grid.height - 1))
		source_body.paint_mayo_cell(cell)
		replay_body.paint_mayo_cell(cell)
	print("replayed body: %s vs %s" % [source_body.cells_md5(), replay_body.cells_md5()])
	_check(source_body.cells_md5() == replay_body.cells_md5(),
		"two bodies given the same centre cells came out different")
	_check(source_body.painted_cell_count() > 100,
		"the replay test only marked %d cells" % source_body.painted_cell_count())

	# --- sauce on your own body is sauce on your camera ---
	var splatter = scene._splatter
	# Off for the placement checks below, which want one blob per call.
	var throttle: float = splatter.blob_interval
	splatter.blob_interval = 0.0
	_check(splatter.size.x > 0.0 and splatter.size.y > 0.0,
		"the splatter overlay has no rect, so every blob would land at the corner")
	_check(splatter.blob_count() == 0, "the screen started out dirty")
	# Level and facing down -Z, so the view is not pitched when the blobs land.
	scene.debug_set_aim(0.0, 0.0)
	await physics_frame
	# Forward is -Z, so the front of the body is where the unwrap starts and the
	# middle column is the player's back. A hit on the chest belongs in the
	# middle of the view; one in the back has nowhere to be but the edge.
	var eye_row: int = int((scene.eye_height + 0.64) / 0.02)
	scene._note_body_splat(1, Vector2i(0, eye_row))
	_check(splatter.blob_count() == 1, "a splat on your own body did not reach the camera")
	var ahead: Vector2 = splatter._blobs[0].position
	scene._note_body_splat(1, Vector2i(body.grid.width / 2, eye_row))
	var behind: Vector2 = splatter._blobs[1].position
	print("blob from the front at %.0v, from behind at %.0v, screen %.0v" % [
		ahead, behind, splatter.size])
	_check(ahead.distance_to(splatter.size * 0.5) < splatter.size.y * 0.25,
		"a hit from straight ahead landed at %.0v, not near the middle" % ahead)
	_check(behind.distance_to(splatter.size * 0.5) > splatter.size.y * 0.25,
		"a hit from behind landed at %.0v, in the middle of the view" % behind)
	for blob in splatter._blobs:
		_check(blob.position.x >= 0.0 and blob.position.y >= 0.0
				and blob.position.x <= splatter.size.x and blob.position.y <= splatter.size.y,
			"a blob landed at %.0v, off the screen" % blob.position)

	# Blobs pile up, and they stay: nothing here is on a timer, or the wipe key
	# would have nothing to do.
	for i in 40:
		scene._note_body_splat(1, Vector2i(i * 2, eye_row))
	await physics_frame
	await physics_frame
	print("after 42 splats: %d blobs held, roughly %.0f%% of the screen" % [
		splatter.blob_count(), splatter.coverage() * 100.0])
	_check(splatter.blob_count() == ScreenSplatter.MAX_BLOBS,
		"%d blobs are being held, past the %d cap" % [
			splatter.blob_count(), ScreenSplatter.MAX_BLOBS])
	_check(splatter.coverage() > 0.1,
		"a screenful of splats covers only %.0f%% of it" % (splatter.coverage() * 100.0))

	# --- a second hit does not wipe out the first ---
	# The failure this guards against: one burst is far more splats than the cap
	# holds, so without the throttle being hit again left only the new marks.
	splatter.wipe()
	splatter.blob_interval = throttle
	scene._note_body_splat(1, Vector2i(0, eye_row))
	var first: Vector2 = splatter._blobs[0].position
	# A full second of being sprayed, spread over the frames it really arrives
	# on rather than in one instant, which the throttle would swallow whole.
	var burst := 0
	for _frame in 60:
		await physics_frame
		# The strand lands about 78 splats a second at the reference fire rate.
		for _i in 2:
			scene._note_body_splat(1, Vector2i(body.grid.width / 2, eye_row))
			burst += 1
	var added: int = splatter.blob_count() - 1
	print("a second of being sprayed (%d splats) added %d blobs, first mark still there=%s" % [
		burst, added, str(splatter.blob_count() > 0 and splatter._blobs[0].position == first)])
	_check(added >= 3 and added <= 12,
		"a second of spray added %d blobs, which is not a second's worth" % added)
	_check(splatter.blob_count() < ScreenSplatter.MAX_BLOBS,
		"a single burst filled the screen to the %d cap" % ScreenSplatter.MAX_BLOBS)
	_check(splatter.blob_count() > 0 and splatter._blobs[0].position == first,
		"the burst pushed the earlier mark off the glass")
	splatter.blob_interval = 0.0

	# --- and R wipes it ---
	var wipe := InputEventAction.new()
	wipe.action = "wipe_screen"
	wipe.pressed = true
	scene._unhandled_input(wipe)
	print("after R: %d blobs" % splatter.blob_count())
	_check(InputMap.has_action("wipe_screen"), "the wipe key is not bound")
	_check(splatter.blob_count() == 0, "R left %d blobs on the screen" % splatter.blob_count())
	# The body underneath is untouched: wiping the lens does not wash the player.
	_check(body.painted_cell_count() > 0,
		"wiping the screen cleared the stain on the body as well")

	# --- and none of it touched the floor ---
	print("floor cells before %d, after %d" % [
		floor_before, scene._floor.grid.painted_cell_count()])
	_check(scene._floor.grid.painted_cell_count() == floor_before,
		"spraying a body painted the floor as well")

	if failures.is_empty():
		print("MAYO_BODY_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
