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
#   * sauce in front of the eyes lands on the glasses, sauce behind the head
#     does not, and a wipe takes it off at the end rather than the start
#   * your own sauce can come back on you once it is clear of you -- fired
#     straight up it lands on your own face -- but never as it leaves the muzzle

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

	# --- sauce in front of the eyes lands on the glasses ---
	# The visor is a grid like any other, but measured in view units, so what is
	# painted on it is what the player cannot see through.
	var visor = target_player.visor
	_check(visor != null, "the player has no glasses")
	_check(visor.painted_cell_count() == 0, "the glasses started out dirty")
	# Straight ahead, a quarter of the way up the view.
	visor.paint_from_view(Vector3(0.0, 0.25, -1.0), scene.camera_fov)
	var ahead: int = visor.painted_cell_count()
	# And from behind: not in front of your eyes, so it does not blind you.
	visor.paint_from_view(Vector3(0.0, 0.0, 1.0), scene.camera_fov)
	print("glasses: %d cells from a hit ahead, %d after one from behind, %.0f%% blind" % [
		ahead, visor.painted_cell_count(), visor.coverage() * 100.0])
	_check(ahead > 0, "a hit in front of the eyes did not reach the glasses")
	_check(visor.painted_cell_count() == ahead,
		"a hit from behind the head put sauce on the lenses")
	_check(visor.coverage() > 0.0 and visor.coverage() < 0.5,
		"one splat left the player %.0f%% blind" % (visor.coverage() * 100.0))

	# --- and a wipe takes it off, with the firing lock that pays for it ---
	var wiper = target_player
	# Through the authority's entry point, which is what R reaches: it is also
	# what remembers to broadcast the clear when the timer runs out.
	_check(scene.begin_wipe_for(2), "the player could not start wiping dirty lenses")
	_check(wiper.is_wiping(), "the wipe did not start")
	_check(visor.painted_cell_count() > 0,
		"the lenses were cleared the instant the wipe started, not at the end of it")
	var lifted := 0.0
	var frames := 0
	while wiper.is_wiping() and frames < 300:
		await physics_frame
		frames += 1
		scene._update_visor(mark)
		lifted = maxf(lifted, absf(visor._lens.rotation.x))
	scene._finish_wipes()
	print("wipe: %d frames (expected ~%d), lenses lifted %.0f deg, %d cells left" % [
		frames, int(wiper.wipe_duration * 60.0), rad_to_deg(lifted),
		visor.painted_cell_count()])
	_check(absi(frames - int(wiper.wipe_duration * 60.0)) <= 3,
		"the wipe took %d frames, expected about %d" % [
			frames, int(wiper.wipe_duration * 60.0)])
	_check(lifted > deg_to_rad(20.0),
		"the lenses only tipped %.0f deg, so nobody can see the wipe" % rad_to_deg(lifted))
	_check(visor.painted_cell_count() == 0, "the wipe left the lenses dirty")
	_check(not scene.begin_wipe_for(2), "clean lenses can still be wiped")
	# Wiping the glasses does not wash the body.
	_check(body.painted_cell_count() > 0,
		"the wipe cleared the stain on the body as well")

	# --- and none of it touched the floor ---
	print("floor cells before %d, after %d" % [
		floor_before, scene._floor.grid.painted_cell_count()])
	_check(scene._floor.grid.painted_cell_count() == floor_before,
		"spraying a body painted the floor as well")

	# --- your own sauce can come back on you ---
	# Fired up it drifts about a metre before it lands, so the case that really
	# happens is walking into your own falling stream. Either way it must never
	# hit you on the way out: the muzzle sits inside your own capsule.
	var self_visor = scene._local.player.visor
	var self_body = scene._local.player.contamination
	self_visor.clear()
	_check(self_body.painted_cell_count() == 0,
		"the shooter was already dirty before firing at themselves")
	scene.debug_set_aim(0.0, 85.0)
	await physics_frame
	for _f in 30:
		scene._emit_point()
		scene._simulate_points(1.0 / 60.0)
		await physics_frame
	var on_the_way_out: int = self_body.painted_cell_count()
	# Now walk under it while it comes down.
	for _f in 180:
		scene._simulate_points(1.0 / 60.0)
		var centre := Vector3.ZERO
		var airborne := 0
		for point in scene._points:
			if point.phase == 0:
				centre += point.position
				airborne += 1
		if airborne > 0:
			centre /= float(airborne)
			scene._local.player.global_position = Vector3(
				centre.x, scene._local.player.global_position.y, centre.z)
		await physics_frame
	print("own sauce: %d cells on self while leaving the muzzle, %d after walking under it, %.0f%% blind" % [
		on_the_way_out, self_body.painted_cell_count(), self_visor.coverage() * 100.0])
	_check(on_the_way_out == 0,
		"%d cells were marked on the shooter as the strand left the muzzle" % on_the_way_out)
	_check(self_body.painted_cell_count() > 0,
		"walking into your own falling sauce did not mark you")
	_check(self_visor.painted_cell_count() > 0,
		"it landed on you but not on your own glasses, which were pointing at it")

	if failures.is_empty():
		print("MAYO_BODY_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
