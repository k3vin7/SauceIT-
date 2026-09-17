extends SceneTree

# The strand is a dynamic mesh whose vertices are written straight into the GPU
# vertex buffer, which does not recalculate the resource AABB -- so the AABB is
# set by hand, and if it does not cover the vertices the renderer culls a strand
# that is right in front of the player. Nothing else notices: the points still
# fly, still collide and still paint, so the stains keep appearing while the
# stream blinks out as the view turns and the stale box leaves the frustum.
#
# The bounds are checked against the very segments the renderer was handed, at
# both ends of the map -- the start plaza, and the arena, which is the far
# corner about 160 m from the origin the old fixed box was centred on.

var failures: Array[String] = []

const AIR := 0
const LANDING := 1


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

	for place in [["start plaza", scene.spawn_position_for(0)],
			["arena", StreetMap.arena_centre() + Vector3(0.0, scene.spawn_position_for(0).y, 0.0)]]:
		var label: String = place[0]
		var stand: Vector3 = place[1]
		scene._points.clear()
		scene._player.global_position = stand
		scene.debug_set_aim(0.0, -8.0)
		await physics_frame

		Input.action_press("fire_mayo")
		for _f in 40:
			await physics_frame
		Input.action_release("fire_mayo")
		await process_frame

		_check(scene._points.size() > 0, "%s: nothing was fired, so this case tests nothing" % label)

		# The same segments `_update_visuals` hands each ribbon, so this checks
		# the bounds against what was drawn rather than against a guess at it.
		var camera: Vector3 = scene._camera.global_position
		var drawn := {
			"_air_visual": scene._segments_for_phase(AIR, camera),
			"_landing_visual": scene._segments_for_phase(LANDING, camera),
			"_shadow_visual": scene._shadow_segments(camera),
		}
		for visual_name in drawn:
			var visual: StreamVisual = scene.get(visual_name)
			var vertices := 0
			for segment in drawn[visual_name]:
				vertices += segment.size()
			_check(visual.visible == (vertices > 0),
				"%s: %s is %s with %d points to draw" % [
					label, visual_name, "hidden" if vertices > 0 else "shown", vertices])
			if not visual.visible:
				continue

			# `custom_aabb` is what the renderer culls against once a mesh is fed
			# through its vertex buffer, so it is what has to be right.
			var world: AABB = visual.global_transform * visual.custom_aabb
			var outside := 0
			var worst := 0.0
			for segment in drawn[visual_name]:
				for point in segment:
					if not world.has_point(point.position):
						outside += 1
						worst = maxf(worst, _distance_outside(world, point.position))
			print("%-12s %-16s %4d pts, bounds at %.0v size %.0v, %d outside (worst %.2f m)" % [
				label, visual_name, vertices, world.position, world.size, outside, worst])
			_check(outside == 0,
				"%s: %s drew %d of %d points outside its bounds, by up to %.1f m -- the renderer culls that" % [
					label, visual_name, outside, vertices, worst])
			# A box that covers the map would pass the test above and defeat the
			# point of having one, so it also has to be about the strand's size.
			_check(world.size.length() < 64.0,
				"%s: %s claims a %.0f m box, far more than a strand spans" % [
					label, visual_name, world.size.length()])

		# The droplet pool is written the same way and had the same fixed box.
		# Spawned directly rather than waited for: whether a burst happens to be
		# landing on the frame the probe looks is not what is under test here,
		# and the pool empties a third of a second after it fills.
		var pool := scene.get_node("LandingDropletPool") as MultiMeshInstance3D
		scene._spawn_landing_droplets(stand + Vector3(0.0, 0.0, -3.0))
		scene._simulate_droplets(0.0)
		var pool_box: AABB = pool.global_transform * pool.custom_aabb
		var live := 0
		var stray := 0
		for i in scene._active_droplet_indices:
			var droplet = scene._droplets[i]
			live += 1
			if not pool_box.has_point(droplet.position):
				stray += 1
		print("%-12s droplets         %4d live, bounds at %.0v size %.1v, %d outside" % [
			label, live, pool_box.position, pool_box.size, stray])
		_check(live > 0, "%s: the landing droplets never spawned, so this case tests nothing" % label)
		_check(stray == 0, "%s: %d live droplets sit outside the pool's bounds" % [label, stray])
		_check(pool_box.size.length() < 8.0,
			"%s: the droplet pool claims a %.0f m box for one burst of droplets" % [
				label, pool_box.size.length()])

	if failures.is_empty():
		print("MAYO_VISIBLE_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _distance_outside(box: AABB, point: Vector3) -> float:
	var clamped := Vector3(
		clampf(point.x, box.position.x, box.end.x),
		clampf(point.y, box.position.y, box.end.y),
		clampf(point.z, box.position.z, box.end.z))
	return point.distance_to(clamped)
