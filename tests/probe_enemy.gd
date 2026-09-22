extends SceneTree

# The enemy, end to end:
#
#   * it is twice the sauce refill station's width and height
#   * it walks at the player at half the player's walking speed, and keeps
#     walking at them after they move
#   * sauce sticks to it the way it sticks to a player, and the same hit that
#     marks it is the hit that hurts it
#   * standing in it costs the player health, slowly, on a cooldown rather than
#     every frame
#   * an emptied player bar puts them back at the start, clean
#   * the splat it queues replays into the same cells on another peer

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

	_check(scene.enemy_count() > 0, "no enemies were spawned, so this tests nothing")
	var enemy: MayoEnemy = scene.enemy_at(0)
	var player: MayoPlayer = scene._player

	# --- it is solid over the shape it is drawn as ---
	# The thing that was reported: sauce went through the monster. Its colliders
	# were a humanoid stick figure left over from the mock enemy it replaced --
	# head, torso, pelvis, arms, legs -- while the burger is drawn 4.2 m across
	# and was solid over 1.9 m of it, so anything but a shot down the middle
	# met nothing. What has to hold is that the silhouette you can see is the
	# silhouette you can hit.
	var station: Vector3 = StreetMap.VENDING_SIZE
	print("refill station %.2v -> monster %.2f m wide, %.2f m tall (%.1fx tall)" % [
		station, enemy.radius * 2.0, enemy.height, enemy.height / station.y])
	_check(is_equal_approx(enemy.height, station.y * 2.0),
		"the enemy is %.2f m tall, not twice the station's %.2f m" % [enemy.height, station.y])

	# Everything below is measured in the **body's own space**. In world space
	# an axis-aligned box grows with the body's yaw, so a collider that fits
	# exactly reads as half a metre too wide -- which is how the first attempt
	# at this fix was written, and it looked wrong when it was right.
	var to_body: Transform3D = enemy.global_transform.affine_inverse()
	var drawn := AABB()
	var drawn_started := false
	for node in enemy._visual_root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		var into: Transform3D = to_body * mesh_node.global_transform
		var part: AABB = into * mesh_node.mesh.get_aabb()
		drawn = drawn.merge(part) if drawn_started else part
		drawn_started = true
	var solid := AABB()
	var solid_started := false
	var shapes: Array[Node] = enemy.find_children("*", "CollisionShape3D", true, false)
	for node in shapes:
		var shape := node as CollisionShape3D
		var part: AABB = shape.transform * shape.shape.get_debug_mesh().get_aabb()
		solid = solid.merge(part) if solid_started else part
		solid_started = true
	print("drawn %.2f x %.2f x %.2f, solid %.2f x %.2f x %.2f, in %d parts" % [
		drawn.size.x, drawn.size.y, drawn.size.z,
		solid.size.x, solid.size.y, solid.size.z, shapes.size()])
	_check(shapes.size() >= 3,
		"the monster is %d collider(s): the burger is meant to be three tiers plus its arms"
			% shapes.size())
	for axis in 3:
		_check(solid.size[axis] > drawn.size[axis] * 0.75,
			"the monster is %.2f m across axis %d but solid over only %.2f m of it"
				% [drawn.size[axis], axis, solid.size[axis]])

	# Round, not flat: the old figure was a body and much thinner front to back
	# than wide. A burger is a stack of discs, and the collider has to be too,
	# or one side of it goes back to being air.
	_check(absf(solid.size.x - solid.size.z) < solid.size.x * 0.35,
		"the monster is solid over %.2f m across and %.2f m deep, which is not a burger"
			% [solid.size.x, solid.size.z])

	# And point by point: a spot on the patty, on each bun and on an arm has to
	# be solid. The envelope above can be the right size and still be hollow
	# where it counts.
	var space := enemy.get_world_3d().direct_space_state
	var probes := {
		"the bottom bun": Vector3(0.0, -0.024 * enemy.height, -0.076 * enemy.height),
		"the patty's rim": Vector3(0.39 * enemy.height, 0.083 * enemy.height, -0.076 * enemy.height),
		"the top bun": Vector3(0.0, 0.30 * enemy.height, -0.076 * enemy.height),
		"an arm": Vector3(-0.3707 * enemy.height, -0.30 * enemy.height, -0.12 * enemy.height),
	}
	var hollow: Array[String] = []
	for where in probes.keys():
		var query := PhysicsPointQueryParameters3D.new()
		query.position = enemy.global_transform * (probes[where] as Vector3)
		query.collide_with_areas = false
		var found := false
		for hit in space.intersect_point(query, 8):
			if hit.collider == enemy:
				found = true
		if not found:
			hollow.push_back(where)
	print("solid at: %s" % ("every part sampled" if hollow.is_empty() else "hollow at " + str(hollow)))
	_check(hollow.is_empty(),
		"sauce would pass through %s" % str(hollow))

	# The mask the stains are unwrapped onto is built from the same measurements,
	# so a stain lands where the sauce hit rather than on a humanoid ghost.
	var envelope: AABB = enemy._body_mesh.mesh.get_aabb()
	print("welded mask: %d surface(s), %.2f m wide, %.2f m tall, %.2f m deep" % [
		enemy._body_mesh.mesh.get_surface_count(), envelope.size.x, envelope.size.y,
		envelope.size.z])
	_check(enemy._body_mesh.mesh.get_surface_count() == 1,
		"the body is %d surfaces; the unwrap needs one mesh in the body's space"
			% enemy._body_mesh.mesh.get_surface_count())
	_check(absf(envelope.size.y - enemy.height) < enemy.height * 0.12,
		"the mask is %.2f m tall against a %.2f m monster" % [envelope.size.y, enemy.height])
	_check(absf(envelope.size.x - solid.size.x) < 0.02,
		"the mask is %.2f m across and the colliders are %.2f m: the stain would not follow the sauce"
			% [envelope.size.x, solid.size.x])

	_check(not enemy._body_mesh.visible,
		"the old capsule mockup is still visible over the hamburger monster")
	_check(enemy._visual_root != null,
		"the hamburger monster visual was not instantiated")
	_check(enemy._animation_player != null,
		"the hamburger monster has no usable AnimationPlayer")
	_check(not enemy._idle_animation.is_empty()
			and not enemy._walk_animation.is_empty()
			and not enemy._attack_animation.is_empty()
			and not enemy._death_animation.is_empty(),
		"the hamburger monster did not import all four required animations")
	var visual_meshes := enemy._visual_root.find_children(
		"*", "MeshInstance3D", true, false)
	_check(not visual_meshes.is_empty(), "the hamburger monster imported no meshes")
	for visual_mesh in visual_meshes:
		_check((visual_mesh as MeshInstance3D).material_overlay != null,
			"a hamburger mesh is missing the sauce-contamination overlay")
	# Three discs for the burger and one capsule per arm, so what you can see
	# is what you can hit.
	var colliders := 0
	for child in enemy.get_children():
		if child is CollisionShape3D:
			colliders += 1
	print("colliders: %d (three burger tiers and two arms)" % colliders)
	_check(colliders >= 5,
		"the monster has %d colliders; it needs a tier each for the buns and the patty, and an arm each side"
			% colliders)

	# --- speed, and that it is actually chasing ---
	print("player walks %.2f m/s and runs %.2f; enemy moves %.2f m/s (%.2fx walking)" % [
		player.walk_speed, player.run_speed, enemy.move_speed,
		enemy.move_speed / player.walk_speed])
	_check(is_equal_approx(enemy.move_speed, player.walk_speed * scene.enemy_speed_fraction),
		"the enemy moves at %.2f m/s, not %.2f of the player's %.2f" % [
			enemy.move_speed, scene.enemy_speed_fraction, player.walk_speed])
	# Slower than walking, so it can always be left behind: a chase you cannot
	# leave is not a decision. Running is the wide margin on top of that.
	_check(enemy.move_speed < player.walk_speed,
		"the enemy walks at %.2f m/s against the player's %.2f: it cannot be walked away from"
			% [enemy.move_speed, player.walk_speed])

	print("enemies on the map: %d" % scene.enemy_count())
	_check(scene.enemy_count() >= 3,
		"only %d enemy on the map" % scene.enemy_count())

	# Both moved into the festival square for the walking checks. They need room
	# to close a gap and then room to dodge sideways, and a street does not have
	# it: the promenade is 18 m across, so an 18 m sidestep puts the player in a
	# wall and the enemy has nowhere to follow them to. The square is the one
	# open space on the map, which is what `arena_centre` is for.
	var square: Vector3 = StreetMap.arena_centre()
	var stand_y: float = scene.spawn_position_for(0).y
	enemy.global_position = square + Vector3(0.0, enemy.stand_height(), -16.0)
	player.global_position = square + Vector3(0.0, stand_y, 16.0)
	await physics_frame
	var opening := enemy.global_position.distance_to(player.global_position)
	var travelled := enemy.global_position
	for _f in 60:
		await physics_frame
	var closed := opening - enemy.global_position.distance_to(player.global_position)
	var moved := Vector3(enemy.global_position.x - travelled.x, 0.0,
		enemy.global_position.z - travelled.z).length()
	print("in 1 s it moved %.2f m and closed %.2f m of a %.1f m gap" % [moved, closed, opening])
	_check(closed > enemy.move_speed * 0.6,
		"it closed only %.2f m in a second at %.2f m/s" % [closed, enemy.move_speed])

	# Move the player sideways: it has to follow, not walk at where they were.
	# Twelve metres rather than eighteen, so the step stays inside the square.
	#
	# Measured as "does the gap close", over a window worked out from the gap
	# and the walking speed, rather than as "did it move on x within a second".
	# The latter assumed the enemy heads straight for the player: it routes now,
	# and a route's first second can be entirely along one axis while it gets
	# round whatever is between the two -- which on this map is the stage and
	# the tower. It also assumed a map scale, and read as a failure the day the
	# map was made bigger.
	var before_turn := enemy.global_position
	player.global_position += Vector3(12.0, 0.0, 0.0)
	var gap_before := enemy.global_position.distance_to(player.global_position)
	var window := int(gap_before / enemy.move_speed * 60.0 * 1.4)
	for _f in window:
		await physics_frame
	var gap_after := enemy.global_position.distance_to(player.global_position)
	print("player stepped 12 m sideways; over %.1f s the gap went %.0f m -> %.0f m, and it moved %.1v" % [
		window / 60.0, gap_before, gap_after, enemy.global_position - before_turn])
	_check(gap_after < gap_before * 0.4,
		"the enemy did not follow the player: %.0f m of %.0f m still between them"
			% [gap_after, gap_before])

	# It has to be looking where it is going -- compared against the direction it
	# is actually travelling, not against the player.
	#
	# It used to be checked against the player, which was the same thing back
	# when it walked straight at them. It routes now, so rounding a corner puts
	# its front ninety degrees off the player quite correctly, and the old check
	# called that going backwards. What it is really guarding is a yaw that is
	# half a turn out -- it did once walk at the player backwards, and its own
	# axes could not catch that because they were wrong in the same way. Its
	# *velocity* is not: that comes from the route, so a front that disagrees
	# with it by half a turn is exactly the bug and nothing else is.
	# Sampled during a clean walk, not while it is standing on the player. Next
	# to them its heading flips about as it shoves into them, and a body that
	# turns at a rate cannot follow that -- which says nothing about whether its
	# front is on the right end.
	player.global_position = square + Vector3(0.0, stand_y, 20.0)
	enemy.global_position = square + Vector3(0.0, enemy.stand_height(), -20.0)
	for _f in 60:
		await physics_frame
	var worst_off := 0.0
	var sampled := 0
	for _f in 90:
		await physics_frame
		var travel := Vector3(enemy.velocity.x, 0.0, enemy.velocity.z)
		if travel.length() < enemy.move_speed * 0.5:
			continue
		sampled += 1
		var front: Vector3 = -enemy.global_transform.basis.z
		worst_off = maxf(worst_off, rad_to_deg(acos(clampf(
			front.dot(travel.normalized()), -1.0, 1.0))))
	print("while walking, its front was at worst %.0f deg off its direction of travel (%d samples)" % [
		worst_off, sampled])
	_check(sampled > 10, "the enemy was not walking, so its facing tests nothing")
	# Generous: it turns at a rate, so it lags its own direction while swinging
	# round a corner. Half a turn out is the thing being ruled out.
	_check(worst_off < 60.0,
		"its front sat %.0f deg off the way it was travelling: it is going backwards"
			% worst_off)
	# And it has to have a front to look with, or none of that is visible. The
	# old figure showed its front by reaching its arms forward, and the burger
	# cannot: its colliders are discs and a disc has no front. What it has is a
	# face, so that is what is checked -- the mouth and eyes have to sit forward
	# of the body, on -Z, which is the front every other body in the game uses.
	var to_body_now: Transform3D = enemy.global_transform.affine_inverse()
	var face := AABB()
	var face_started := false
	for node in enemy._visual_root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		var part_name := String(mesh_node.name)
		if mesh_node.mesh == null:
			continue
		if not (part_name.contains("Eye") or part_name.contains("Pupil")
			or part_name.contains("Mouth") or part_name.contains("Fang")
			or part_name.contains("Gum")):
			continue
		var into_body: Transform3D = to_body_now * mesh_node.global_transform
		var part: AABB = into_body * mesh_node.mesh.get_aabb()
		face = face.merge(part) if face_started else part
		face_started = true
	var face_z := face.position.z + face.size.z * 0.5
	var face_x := face.position.x + face.size.x * 0.5
	print("its face sits at x %.2f, z %.2f in its own space (front is -Z)" % [
		face_x, face_z])
	_check(face_started, "the monster has no face meshes, so its facing tests nothing")
	_check(face_z < -enemy._body_radius() * 0.3,
		"its face sits at z %.2f: it is not looking the way the body is pointed" % face_z)
	# Square on, not over a shoulder: a face off to one side means the model is
	# turned by the wrong angle, and it would walk at you sideways.
	_check(absf(face_x) < absf(face_z) * 0.4,
		"its face sits at x %.2f against z %.2f: the model is turned off-square"
			% [face_x, face_z])

	# --- sauce marks it and hurts it, off the same hit ---
	var full: float = enemy.health
	var clean: int = enemy.contamination.painted_cell_count()
	_check(clean == 0, "the enemy started out already covered in sauce")
	scene._points.clear()
	player.global_position = enemy.global_position + Vector3(0.0, 0.0, 9.0)
	player.global_position.y = stand_y
	scene.debug_aim_at(enemy.global_position + Vector3(0.0, 0.4, 0.0))
	await physics_frame
	Input.action_press("fire_mayo")
	for _f in 90:
		scene.debug_aim_at(enemy.global_position + Vector3(0.0, 0.4, 0.0))
		await physics_frame
	Input.action_release("fire_mayo")
	await process_frame

	var marked: int = enemy.contamination.painted_cell_count()
	var lost: float = full - enemy.health
	print("90 frames of fire: %d cells of sauce on it, %.1f of %.0f health gone" % [
		marked, lost, full])
	_check(marked > 0, "sauce did not stick to the enemy")
	_check(lost > 0.0, "sauce did not hurt the enemy")
	# The stain and the damage come off the same hit, so neither can happen
	# without the other. Damage is per hit, so the ratio is fixed.
	_check(is_equal_approx(lost, enemy.sauce_damage_per_hit
			* roundf(lost / enemy.sauce_damage_per_hit)),
		"the damage taken is not a whole number of hits")

	# --- a splat is the same size on it as on a player ---
	# The world has one brush and that is the point of it: a stain is the same
	# number of metres across on the floor, a wall, a player and an enemy. The
	# unwrap converts metres of grid into metres of surface by the radius it was
	# configured with, so handing it the wrong radius silently rescales every
	# stain on that body -- no error, just a different-looking hit, which is
	# exactly what half the arm span did here.
	var body_radius: float = enemy._body_radius()
	var enemy_width := 2.0 * enemy.contamination.brush_radius \
		* body_radius / enemy.contamination.radius
	var player_width := 2.0 * player.contamination.brush_radius \
		* player.contamination.radius / player.contamination.radius
	print("one splat renders %.3f m across on a player, %.3f m on the burger (brush %.3f m)" % [
		player_width, enemy_width, 2.0 * scene.contamination_brush_radius])
	_check(absf(enemy_width - player_width) < 0.02,
		"a splat is %.3f m across on an enemy against %.3f m on a player" % [
			enemy_width, player_width])
	_check(absf(enemy_width - 2.0 * scene.contamination_brush_radius) < 0.02,
		"a splat renders %.3f m across from a %.3f m brush" % [
			enemy_width, 2.0 * scene.contamination_brush_radius])
	# And the unwrap must be built on the part that actually gets hit, not on
	# the reach of the limbs.
	print("unwrap radius %.2f m; torso %.2f m, arm span half %.2f m" % [
		enemy.contamination.radius, body_radius, enemy.radius])
	_check(is_equal_approx(enemy.contamination.radius, body_radius),
		"the unwrap is built on %.2f m rather than the torso's %.2f m" % [
			enemy.contamination.radius, body_radius])

	# --- it hurts the player, weakly and on a cooldown ---
	# The others are sent away first. This counts how often *one* enemy can land
	# a hit, and with three of them on the map the rest walk over and land their
	# own -- which looks exactly like a broken cooldown.
	for other in scene.enemy_count():
		if scene.enemy_at(other) != enemy:
			scene.enemy_at(other).global_position = square + Vector3(0.0, stand_y, 400.0)
	await physics_frame
	var health_before: float = player.health
	player.global_position = enemy.global_position \
		+ Vector3(0.0, 0.0, enemy.radius + 0.64)
	player.global_position.y = stand_y
	var ticks := 0
	var bite_animation_seen := false
	var seconds := 1.5
	for _f in int(seconds * 60.0):
		var was: float = player.health
		await physics_frame
		if player.health < was:
			ticks += 1
			bite_animation_seen = bite_animation_seen \
				or enemy._animation_player.current_animation == enemy._attack_animation
	var taken: float = health_before - player.health
	var expected := int(seconds / enemy.contact_interval)
	print("%.1f s of standing in it: %d hits for %.0f damage (one every %.2f s)" % [
		seconds, ticks, taken, enemy.contact_interval])
	_check(ticks > 0, "standing inside the enemy cost the player nothing")
	_check(bite_animation_seen,
		"a contact-damage tick did not start the biting Attack animation")
	_check(ticks <= expected + 1,
		"it hit %d times in %.1f s, more than the %.2f s cooldown allows" % [
			ticks, seconds, enemy.contact_interval])
	# "Weak" has to mean something: surviving the cooldown must take a while.
	var to_kill: float = player.max_health / maxf(enemy.contact_damage, 0.001) \
		* enemy.contact_interval
	print("standing in it the whole time would take %.1f s to empty the bar" % to_kill)
	_check(to_kill > 8.0, "the enemy empties a full bar in %.1f s, which is not weak" % to_kill)

	# --- an emptied bar sends the player back to the start ---
	player.contamination.paint_mayo(player.global_position + Vector3(0.0, 0.2, 0.6), Vector3.BACK)
	_check(player.contamination.painted_cell_count() > 0, "the player could not be dirtied")
	scene._damage_player(player, player.max_health)
	var spawn: Vector3 = scene.spawn_position_for(0)
	print("emptied: back at %.1v (spawn %.1v), health %.0f, %d cells of sauce left" % [
		player.global_position, spawn, player.health,
		player.contamination.painted_cell_count()])
	_check(player.global_position.distance_to(spawn) < 0.01,
		"an emptied bar left the player at %.1v rather than the spawn" % player.global_position)
	_check(is_equal_approx(player.health, player.max_health),
		"the player came back with %.0f health" % player.health)
	_check(player.contamination.painted_cell_count() == 0,
		"the player came back still covered in sauce")

	# --- its health bar actually lands on screen ---
	# The bar is drawn in the window's pixels and was briefly being scaled by a
	# Control size that is zero under a CanvasLayer, which collapsed every one
	# of them into the corner. Nothing looked broken -- the bar was simply not
	# where anyone was looking -- so the rect is checked rather than the drawing.
	var hud: HealthHud = scene._health_hud
	var camera: Camera3D = scene._camera
	player.global_position = enemy.global_position + Vector3(0.0, 0.0, 14.0)
	player.global_position.y = stand_y
	scene.debug_aim_at(enemy.global_position)
	await physics_frame
	await process_frame
	var bar: Rect2 = hud.enemy_bar_rect(enemy, camera)
	print("health bar at %.0v size %.0v, inside the view %s of %s" % [
		bar.position, bar.size, str(hud.frame.encloses(bar)), str(hud.frame)])
	_check(bar.size.x > 0.0, "the enemy in front of the player gets no health bar at all")
	_check(hud.frame.encloses(bar),
		"the health bar sits at %.0v, outside the %s being drawn" % [bar.position, str(hud.frame)])
	# Over the enemy rather than anywhere on screen: a bar in the corner is the
	# failure this is here to catch.
	var on_body: Vector2 = camera.unproject_position(enemy.global_position)
	_check(bar.get_center().distance_to(on_body) < hud.frame.size.y * 0.5,
		"the bar is %.0f px from the enemy it belongs to" % bar.get_center().distance_to(on_body))
	_check(bar.get_center().y < on_body.y, "the bar is under the enemy rather than over it")

	# --- killing it puts it on its back, over its own feet ---
	var standing_sole: Vector3 = enemy.global_transform * Vector3(0.0, -enemy.height * 0.5, 0.0)
	# Which way "backwards" is, taken from the player it is facing rather than
	# from its own axes: away from the player is the direction its back is in.
	var away: Vector3 = enemy.global_position - player.global_position
	away.y = 0.0
	away = away.normalized()
	enemy.health = enemy.sauce_damage_per_hit
	_check(enemy.take_sauce_hit(), "the last point of health did not kill it")
	_check(not enemy.is_alive(), "it is still alive at zero health")
	var falling_frames := 0
	for _f in int(enemy.fall_duration * 60.0) + 30:
		await physics_frame
		if enemy.fall_angle < MayoEnemy.FLAT:
			falling_frames += 1
	var sole: Vector3 = enemy.global_transform * Vector3(0.0, -enemy.height * 0.5, 0.0)
	var crown: Vector3 = enemy.global_transform * Vector3(0.0, enemy.height * 0.5, 0.0)
	var drift := Vector2(sole.x - standing_sole.x, sole.z - standing_sole.z).length()
	var backwards: float = (crown - sole).dot(away)
	print("went over in %d frames: angle %.1f deg, soles moved %.2f m, crown %.1f m %s from the player, at y=%.2f" % [
		falling_frames, rad_to_deg(enemy.fall_angle), drift, absf(backwards),
		"away" if backwards > 0.0 else "toward", crown.y])
	_check(falling_frames > 1, "it snapped flat instead of toppling over %.2f s" % enemy.fall_duration)
	_check(is_equal_approx(enemy.fall_angle, MayoEnemy.FLAT),
		"it stopped at %.1f degrees rather than flat" % rad_to_deg(enemy.fall_angle))
	# The feet are the axis: they stay put while everything above them swings.
	_check(drift < 0.05, "its feet slid %.2f m instead of staying planted" % drift)
	# And it goes over backwards, so its back takes the floor: away from what it
	# was facing, which is the player.
	_check(backwards > enemy.height * 0.8,
		"its head ended %.2f m toward the player; it fell on its face, not its back"
			% -backwards)
	# Resting on the ground rather than sunk into it or hovering over it. The
	# height to expect is measured from the feet it toppled about, not from
	# zero: the street it is standing on is not at y = 0.
	var expected_rest: float = enemy._fall_pivot.y + enemy._rest_radius
	print("at rest the body centre is %.2f m up; its feet are at %.2f and it is %.2f m thick" % [
		enemy.global_position.y, enemy._fall_pivot.y, enemy._rest_radius])
	_check(absf(enemy.global_position.y - expected_rest) < 0.02,
		"flat on its back it sits %.2f m up rather than the %.2f m its own thickness puts it at"
			% [enemy.global_position.y, expected_rest])
	_check(hud.enemy_bar_rect(enemy, camera).size.x == 0.0,
		"a dead enemy still has a health bar over it")

	# --- the splat replays into the same cells elsewhere ---
	var replay: MayoEnemy = MayoEnemy.new()
	root.add_child(replay)
	replay.build(scene.body_cell_size, scene.contamination_brush_radius, Color("4d3f6b"))
	var splats := PackedInt32Array()
	var cells: Array[Vector2i] = []
	for step in 12:
		var cell: Vector2i = enemy.contamination.grid.cell_of(
			Vector2(float(step) * 0.3 - 1.5, float(step) * 0.2))
		cells.push_back(cell)
		splats.append_array(PackedInt32Array([scene.SPLAT_ENEMY, 0, cell.x, cell.y]))
	for cell in cells:
		replay.paint_mayo_cell(cell)
	var fresh: MayoEnemy = scene.enemy_at(0)
	fresh.contamination.clear()
	scene.apply_splats(splats)
	print("replayed %d splat cells: %s vs %s" % [
		cells.size(), fresh.cells_md5().substr(0, 12), replay.cells_md5().substr(0, 12)])
	_check(fresh.cells_md5() == replay.cells_md5(),
		"a replayed enemy splat did not reproduce the server's mask")
	replay.queue_free()

	if failures.is_empty():
		print("MAYO_ENEMY_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
