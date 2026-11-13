extends SceneTree

# Stage 2, La Tomatina, as a greybox:
#
#   * the stage scene builds on the Tomatina layout, with the start on the
#     street and a walkable route from the start to the fire truck bay
#   * every stage 2 kind builds, and the bowler brings its balls
#   * the juice is on the floor where it should be and nowhere else, and it is
#     never slippery
#   * a grunt dying bursts: ketchup on the floor, none of it slippery, and the
#     splats queued for the peers
#   * the burst a grunt is dealt is reproducible from its index alone, and the
#     deal is mostly small with a few large
#   * a bowled tomato bursts on the first wall and parks itself
#   * the siren schedules separate, capped waves and opens the truck after 30 seconds
#   * clearing the waves summons the Press King and its defeat opens extraction
#   * stage 1 gets its own street back afterwards

var failures: Array[String] = []


func _initialize() -> void:
	MayoTutorial.disabled = true
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.push_back(message)


func _frames(count: int) -> void:
	for _index in count:
		await process_frame
		await physics_frame


func _run() -> void:
	if OS.get_cmdline_user_args().has("--network"):
		await _run_network()
		return
	if OS.get_cmdline_user_args().has("--profile"):
		await _run_profile()
		return
	StreetMap.layout_override = null
	var festival_cells := StreetMap.floor_cells().size()

	var scene = load("res://stage_2_tomatina.tscn").instantiate()
	root.add_child(scene)
	await _frames(2)
	scene.set_process_unhandled_input(false)

	var village: Node3D = scene.get_node_or_null("TomatinaVillageArt")
	_check(village != null and village.get_child_count() > 30, "the Blender village kit was not placed")
	if village != null:
		var placed := {}
		for batch: MultiMeshInstance3D in village.get_children():
			var model := str(batch.name).get_slice("_", 0)
			if TomatinaVillageArt.STREET_ACCENTS.has(model):
				_check(batch.material_override is StandardMaterial3D, "%s is missing its street accent" % batch.name)
			else:
				_check(batch.multimesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] != null,
					"%s lost the Blender vertex colors" % batch.name)
			placed[model] = int(placed.get(model, 0)) + batch.multimesh.instance_count
		_check(int(placed.get("TomatoTruck", 0)) == 6, "loaded tomato trucks are missing")
		_check(int(placed.get("SauceVan", 0)) == 24, "decorative vans are missing")
		_check(int(placed.get("OverturnedTomatoTruck", 0)) == 2, "overturned tomato trucks are missing")
		_check(int(placed.get("TomatoCrateStack", 0)) == 18, "tomato crate stacks are missing")
		_check(int(placed.get("RefugeShower", 0)) == TomatinaMap.SAFE_ROOMS.size(),
			"each refuge should have a shower model")
		for prop in TomatinaMap.AFTERMATH_MODELS:
			_check(int(placed.get(prop[0], 0)) >= 6,
				"festival aftermath is missing %s obstacles" % prop[0])
		_check(int(placed.get("CrushedTomatoes", 0)) > 40, "crushed tomatoes are missing from the streets")
		_check(int(placed.get("BrokenBoards", 0)) > 25, "broken boards are missing from the streets")
		var boundary_edges := 0
		var cells := TomatinaMap.floor_cells()
		for cell: Vector2i in cells:
			for step: Vector2i in TomatinaVillageArt.CARDINAL:
				if not cells.has(cell + step):
					boundary_edges += 1
		_check(int(placed.get("BoundaryWall", 0)) == boundary_edges,
			"the visible exterior does not cover every boundary edge")
		for accent in TomatinaVillageArt.STREET_ACCENTS:
			_check(int(placed.get(accent, 0)) > 0, "%s is missing from the street" % accent)
		_check(int(placed.get("Brazier", 0)) == TomatinaMap.SAFE_ROOMS.size(),
			"a refuge is missing its central campfire")
		_check(not placed.has("RefugeFireplace"), "a refuge still has a wall fireplace")

	var bunting := scene.get_node_or_null("FestivalBunting") as MeshInstance3D
	_check(bunting != null and bunting.mesh.get_aabb().size.z > 700.0,
		"festival decorations are missing from the length of the village")

	var fires := get_nodes_in_group("tomatina_fire")
	_check(fires.size() == TomatinaMap.SAFE_ROOMS.size(),
		"the fires are missing from the refuges")
	for fire: Node3D in fires:
		var index := TomatinaMap.safe_room_at(StreetMap.cell_at(fire.position))
		_check(index >= 0, "a campfire is outside a refuge")
		if index >= 0:
			var room: Rect2i = TomatinaMap.SAFE_ROOMS[index]
			var centre := TomatinaMap.at_cell(Vector2(room.position) + Vector2(room.size) * 0.5)
			_check(centre.is_equal_approx(Vector3(fire.position.x, 0.0, fire.position.z)),
				"a campfire is not centred in its refuge")
		_check(fire.get_node_or_null("FlameVolume") is MeshInstance3D,
			"a fire is missing its flame volume")
		_check(fire.get_node_or_null("Embers") is GPUParticles3D,
			"a fire is missing its ember emitter")

	# --- the map ---
	_check(scene.map_kind == scene.MapKind.TOMATINA, "stage 2 scene did not select the Tomatina map")
	_check(StreetMap.layout_override is TomatinaMap, "the lattice is not carrying the Tomatina design")
	var floor_set := StreetMap.floor_cells()
	_check(floor_set.size() != festival_cells, "the Tomatina floor is the festival floor")
	var exterior := scene._walls[0] as ContaminableObject
	var exterior_face := exterior.get_node("Face0") as MeshInstance3D
	_check(is_equal_approx(exterior.size.y, TomatinaMap.BOUNDARY_HEIGHT) and not exterior_face.visible,
		"the exterior collider or its clean paint layer is incorrect")
	var clean_face := exterior.snapshot_cells(0)
	exterior.paint_mayo_cell(0, Vector2i(1, 1), ContaminationGrid.KIND_KETCHUP)
	await _frames(2)
	_check(exterior_face.visible and exterior.debug_texture_uploads() > 0,
		"a painted exterior face did not become visible")
	exterior.restore_cells(0, clean_face)
	_check(not exterior_face.visible, "a restored clean face still draws")
	for enemy: MayoEnemy in scene._enemies:
		if enemy.kind != MayoEnemy.EnemyKind.TOMATO_GRUNT:
			continue
		var parts := enemy._visual_meshes()
		_check(parts.size() == 1, "a grunt has multiple render meshes")
		var mesh := parts[0] as MeshInstance3D
		_check(mesh.material_overlay == null, "an unpainted grunt draws a paint overlay")
		enemy.contamination.paint_mayo_cell(Vector2i(1, 1), ContaminationGrid.KIND_KETCHUP)
		await _frames(2)
		_check(mesh.material_overlay != null, "a grunt lost its paint overlay")
		enemy.contamination.clear()
		await _frames(2)
		_check(mesh.material_overlay == null, "a cleaned grunt still draws its paint overlay")
		break
	for slot in 4:
		var spawn: Vector3 = scene.spawn_position_for(slot)
		_check(floor_set.has(StreetMap.cell_at(spawn)), "spawn %d is not on the street" % slot)
	var truck_zone: Rect2 = TomatinaMap.fire_truck_zone()
	var truck_centre := Vector3(truck_zone.get_center().x, 0.0, truck_zone.get_center().y)
	_check(scene._nav != null, "stage 2 built no router")
	var route: PackedVector3Array = scene._nav.route(scene.spawn_position_for(0), truck_centre)
	print("route from the start to the fire truck: %d waypoints" % route.size())
	_check(not route.is_empty() and route.size() < 375, "the market shortcut did not shorten the stage")
	for cell: Vector2i in TomatinaMap.market_gate_cells():
		if scene._nav.is_walkable(cell):
			scene._nav.grid.set_point_solid(cell, true)
	var detour: PackedVector3Array = scene._nav.route(scene.spawn_position_for(0), truck_centre)
	print("market routes: %d waypoints open, %d closed" % [route.size(), detour.size()])
	_check(detour.size() >= route.size() + 12, "closing the shortcut does not leave a longer main route")
	scene._nav.build()
	for room in TomatinaMap.SAFE_ROOMS:
		for y in range(room.position.y, room.end.y):
			for x in range(room.position.x, room.end.x):
				var cell := Vector2i(x, y)
				if scene._nav.is_walkable(cell):
					scene._nav.grid.set_point_solid(cell, true)
		_check(scene._nav.route(scene.spawn_position_for(0), truck_centre).is_empty(),
			"the main route can bypass a refuge")
		scene._nav.build()
	# And nothing on the lattice is cut off: a truck a cell and a half deep
	# parked opposite another in a three-cell alley closes it, and the router
	# would quietly route round the whole fork.
	var open := {}
	for cell in StreetMap.floor_cells().keys():
		if not StreetMap.blocked_cells().has(cell):
			open[cell] = true
	var start := StreetMap.cell_at(scene.spawn_position_for(0))
	var reached := {start: true}
	var frontier := [start]
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_front()
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + step
			if open.has(next) and not reached.has(next):
				reached[next] = true
				frontier.push_back(next)
	print("lattice: %d of %d open cells reachable from the start" % [reached.size(), open.size()])
	if reached.size() != open.size():
		print("isolated cells: ", open.keys().filter(func(cell: Vector2i) -> bool: return not reached.has(cell)))
	_check(reached.size() == open.size(), "%d open cells are cut off from the start" % (open.size() - reached.size()))
	# And nobody is built inside a prop: the grunts are dealt round them, the
	# elites are placed by hand, and the wreckage is placed by hand too.
	var buried := 0
	for index in scene.enemy_count():
		var body: MayoEnemy = scene.enemy_at(index)
		if body.kind == MayoEnemy.EnemyKind.TOMATO_BALL:
			continue
		if StreetMap.blocked_cells().has(StreetMap.cell_at(body.global_position)):
			buried += 1
			push_error("%s stands in a prop's cell" % body.name)
	_check(buried == 0, "%d bodies are built inside props" % buried)
	# The wreck narrows the approach without cutting off the plaza.
	var cid_blocked := 0
	for i in range(28, 32):
		if StreetMap.blocked_cells().has(Vector2i(i, int(TomatinaMap.TRUCK_ROW))):
			cid_blocked += 1
	_check(cid_blocked > 0 and cid_blocked < 4, "truck gap blocks %d of 4 cells" % cid_blocked)
	var stations: Array = scene.refill_stations()
	var props := TomatinaMap.debris_boxes() + TomatinaMap.parked_trucks()
	props.push_back(TomatinaMap.fire_truck_box())
	for box: Dictionary in props:
		var registered := stations.any(func(station: Dictionary) -> bool:
			return station["position"] == box["position"])
		_check(registered == TomatinaMap.is_supply_prop(box),
			"incorrect supply station registration for %s" % box["name"])
		if box["name"] == "OverturnedTomatoTruck":
			_check(registered, "a truck with tomatoes in its overturned cargo bed cannot refill")
	_check(stations.size() == 62, "stage 2 is missing tomato crates or loaded trucks")
	var refill_player: MayoPlayer = scene._local.player
	var original_position := refill_player.global_position
	var interact := InputEventKey.new()
	interact.physical_keycode = KEY_E
	interact.pressed = true
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	scene._unhandled_input(interact)
	_check(not scene._refuge_shop.visible, "a distant shop opened")
	for room in TomatinaMap.SAFE_ROOMS.size():
		refill_player.global_position = TomatinaMap.refuge_shop_at(room) + Vector3.UP * 1.28
		_check(scene._tomatina_action_hint() == "[E] 상점 열기", "a refuge shop lacks its prompt")
		scene._unhandled_input(interact)
		_check(scene._refuge_shop.visible and scene._refuge_shop_room == room
			and refill_player.frozen and scene.is_physics_processing(),
			"the shop did not open locally while keeping the world active")
		scene._unhandled_input(cancel if room % 2 == 0 else interact)
		_check(not scene._refuge_shop.visible and not refill_player.frozen, "the shop did not close")
	_probe_sauce_parts(scene, refill_player)
	refill_player.global_position = original_position
	var stain := refill_player.contamination
	var clean_body := stain.snapshot_cells()
	var stained_body := clean_body.duplicate()
	stained_body[0] = (1 << ContaminationGrid.KIND_BITS) | ContaminationGrid.KIND_KETCHUP
	stained_body[1] = (1 << ContaminationGrid.KIND_BITS) | ContaminationGrid.KIND_MAYO
	stain.restore_cells(stained_body)
	scene.tomato_action(refill_player.peer_id, 0)
	_check(stain.snapshot_cells() == stained_body, "a distant shower washed the player")
	for room in TomatinaMap.SAFE_ROOMS.size():
		refill_player.global_position = TomatinaMap.refuge_shower_at(room) + Vector3.UP * 1.28
		_check(scene._refuge_shower_in_reach(refill_player.global_position) == room
			and scene._tomatina_action_hint().begins_with("[E]"), "shower is missing its interaction prompt")
		stain.restore_cells(stained_body.duplicate())
		scene.tomato_action(refill_player.peer_id, 0)
		var washed := stain.snapshot_cells()
		_check(washed[0] == 0 and washed[1] == stained_body[1],
			"shower should remove ketchup from the body and retain other sauces")
	stain.restore_cells(clean_body)
	var trucks := TomatinaMap.parked_trucks()
	var truck: Dictionary = trucks[0]
	refill_player.global_position = truck["position"] + Vector3.LEFT * 2.5
	scene._local.sauce = 0.1
	_check(scene.local_at_station(), "the loaded truck did not show the proximity prompt")
	_check(not scene.can_select_refill_sauce(0) and not scene.can_select_refill_sauce(1)
		and scene.can_select_refill_sauce(2), "the proximity prompt offers the wrong sauces")
	_check(not scene.refill_for(refill_player.peer_id, 0)
		and not scene.refill_for(refill_player.peer_id, 1) and scene._local.sauce == 0.1,
		"a sauce truck accepted mayo or mustard")
	_check(scene.refill_for(refill_player.peer_id, 2) and scene._local.sauce == 1.0
		and scene.local_sauce_kind() == 2, "a sauce truck did not refill with ketchup")
	refill_player.global_position = trucks[1]["position"] + Vector3.BACK * 2.6
	scene._local.sauce = 0.1
	_check(not scene.local_at_station() and not scene.refill_for(refill_player.peer_id, 2)
		and scene._local.sauce == 0.1, "a decorative van offered or accepted a refill")
	var crate_centre := TomatinaMap.at_cell(Vector2(28.0, 227.8))
	for side in [-1.0, 1.0]:
		refill_player.global_position = crate_centre + Vector3(1.95 * side, 1.28, 0.0)
		var station: int = scene.station_in_reach(refill_player)
		_check(station >= 0 and stations[station].has("half_footprint"),
			"the tomato crate cannot be reached from both sides")
		scene._local.sauce = 0.1
		_check(not scene.refill_for(refill_player.peer_id, 0) and scene._local.sauce == 0.1,
			"the tomato crate accepted mayo")
		_check(scene.refill_for(refill_player.peer_id, 2) and scene._local.sauce == 1.0
			and scene.local_sauce_kind() == 2, "the tomato crate did not refill with ketchup")
	refill_player.global_position = original_position
	_check(not scene.local_at_station(), "the supply prompt is visible away from a station")
	_check(scene.find_children("SauceSupply*", "Label3D", true, false).is_empty(),
		"a world-space supply label was left in the map")
	for enemy in scene._enemies:
		if enemy.kind != MayoEnemy.EnemyKind.TOMATO_BALL:
			_check(TomatinaMap.safe_room_at(StreetMap.cell_at(enemy.global_position)) < 0,
				"an enemy spawned inside a refuge")
	# --- the roster ---
	var counts := {}
	var groups := {}
	var plaza_guards := {}
	var reinforced_legs := [0, 0, 0, 0]
	var reinforcement_grunts := 0
	var occupied := {}
	for index in scene.enemy_count():
		var enemy: MayoEnemy = scene.enemy_at(index)
		counts[enemy.kind] = int(counts.get(enemy.kind, 0)) + 1
		if enemy.kind == MayoEnemy.EnemyKind.TOMATO_BALL:
			continue
		var cell := StreetMap.cell_at(enemy.global_position)
		if enemy.has_meta(TomatinaMap.ALLEY_REINFORCEMENT):
			var leg: int = enemy.get_meta("encounter")
			_check(leg >= 0 and not occupied.has(cell) and not enemy.has_meta("finale_guard"),
				"a reinforcement shares a spawn or is outside its alley")
			if leg >= 0:
				reinforced_legs[leg] += 1
			reinforcement_grunts += int(enemy.kind == MayoEnemy.EnemyKind.TOMATO_GRUNT)
		occupied[cell] = true
		if enemy.has_meta("finale_guard"):
			plaza_guards[enemy.kind] = int(plaza_guards.get(enemy.kind, 0)) + 1
		if enemy.has_meta("alley_ambush"):
			var group := int(enemy.get_meta("alley_ambush"))
			groups[group] = int(groups.get(group, 0)) + 1
			var plan: Array = TomatinaMap.ALLEY_AMBUSHES[group]
			_check(enemy.get_meta("encounter") == plan[0] and not enemy.has_meta("finale_guard"),
				"an ambusher spawned outside its alley")
	print("roster: %s" % str(counts))
	_check(int(counts.get(MayoEnemy.EnemyKind.TOMATO_GRUNT, 0)) == TomatinaMap.grunt_cells().size(), "encounter pack grunt count differs from plan")
	_check(int(counts.get(MayoEnemy.EnemyKind.TOMATO_GRUNT, 0)) - reinforcement_grunts <= 140,
		"the original grunt packs grew")
	_check(reinforced_legs == [5, 10, 10, 10] and reinforcement_grunts == 28,
		"the alley reinforcement packs are incomplete")
	for group in TomatinaMap.ALLEY_AMBUSHES.size():
		_check(groups.get(group, 0) == 3, "alley ambush %d is missing an attacker" % group)
	_check(plaza_guards == {MayoEnemy.EnemyKind.TOMATO_BRUTE: 2,
		MayoEnemy.EnemyKind.CAPRESE_CRAWLER: 1, MayoEnemy.EnemyKind.KETCHUP_SPITTER: 2,
		MayoEnemy.EnemyKind.TOMATO_GRUNT: 20}, "the alley ambushes changed the plaza guard")
	var bowlers := int(counts.get(MayoEnemy.EnemyKind.BOWLING_TOMATO, 0))
	_check(int(counts.get(MayoEnemy.EnemyKind.TOMATO_BALL, 0)) == bowlers * MayoEnemy.BALLS_PER_BOWLER,
		"the bowler did not bring its balls")
	for index in scene.enemy_count():
		var enemy: MayoEnemy = scene.enemy_at(index)
		if enemy.kind == MayoEnemy.EnemyKind.TOMATO_BALL:
			_check(enemy.global_position.y < -40.0, "a ball is not parked under the floor")
			continue
		_check(scene._nav.is_walkable(StreetMap.cell_at(enemy.global_position)),
			"%s stands on a cell nothing can walk" % enemy.name)
		_check(enemy.contamination != null and enemy._visual_root != null,
			"%s has no stain grid or no visual" % enemy.name)
		_check(enemy._visual_root.find_children("*", "MeshInstance3D", true, false).size() > 0,
			"%s has no meshes to look at" % enemy.name)

	# --- the deal ---
	var tiers := [0, 0, 0]
	for index in 400:
		var deal: Dictionary = scene._deal_grunt_burst(index)
		var again: Dictionary = scene._deal_grunt_burst(index)
		_check(deal == again, "the burst dealt to body %d changed between two asks" % index)
		tiers[int(deal["tier"])] += 1
		var radius: float = deal["radius"]
		match int(deal["tier"]):
			0: _check(radius >= 1.2 and radius <= 2.0, "a small burst of %.2f m" % radius)
			1: _check(radius >= 2.5 and radius <= 3.5, "a medium burst of %.2f m" % radius)
			2: _check(radius >= 5.0 and radius <= 6.5, "a large burst of %.2f m" % radius)
	print("400 grunts dealt: %d small, %d medium, %d large" % tiers)
	_check(tiers[0] > 220, "fewer than 55%% of grunts burst small")
	_check(tiers[2] >= 4 and tiers[2] <= 60, "the large burst is dealt %d times in 400" % tiers[2])

	# --- the floor ---
	var floor_body: FloorContamination = scene._floor
	var juicy := TomatinaMap.at_cell(Vector2(4.2, 174.2))
	var clean := TomatinaMap.at_cell(Vector2(29.2, 222.2))
	var juicy_hits := 0
	for dx in 6:
		for dz in 6:
			var at := juicy + Vector3(float(dx) * 0.3, 0.0, float(dz) * 0.3)
			if floor_body.thickness_at(at) > 0:
				juicy_hits += 1
				_check(floor_body.sauce_kind_at(at) == ContaminationGrid.KIND_KETCHUP,
					"the juice in the first juice alley is not ketchup")
				_check(not floor_body.is_slippery_at(at), "the juice in the first juice alley is slippery")
	print("juice under 36 samples in the first juice alley: %d painted" % juicy_hits)
	_check(juicy_hits > 10, "the juice alley is not awash")
	var clean_hits := 0
	for dx in 6:
		for dz in 6:
			if floor_body.thickness_at(clean + Vector3(float(dx) * 0.3, 0.0, float(dz) * 0.3)) > 0:
				clean_hits += 1
	_check(clean_hits == 0, "the dry entry has juice on it")

	# --- a grunt bursts ---
	scene.set_physics_process(false)
	var grunt: MayoEnemy = null
	for index in scene.enemy_count():
		var enemy: MayoEnemy = scene.enemy_at(index)
		if enemy.kind == MayoEnemy.EnemyKind.TOMATO_GRUNT and enemy.burst_tier == 0:
			grunt = enemy
			break
	_check(grunt != null, "no small grunt to burst")
	if grunt != null:
		# Two more grunts: one stood inside the splash, one well outside it.
		# The splash is the burst's damage, so the first is hurt by exactly
		# the notional hits `tomato_burst_damage` is worth and the second is
		# not touched. Neither is low enough to die of it, so the burst stays
		# one burst and the splat count below is still the one grunt's.
		var neighbour: MayoEnemy = null
		var bystander: MayoEnemy = null
		for index in scene.enemy_count():
			var candidate: MayoEnemy = scene.enemy_at(index)
			if candidate == grunt or candidate.kind != MayoEnemy.EnemyKind.TOMATO_GRUNT \
					or not candidate.is_alive():
				continue
			if neighbour == null:
				neighbour = candidate
			elif bystander == null:
				bystander = candidate
		_check(neighbour != null and bystander != null, "not enough grunts to stand in the splash")
		if neighbour != null:
			neighbour.global_position = grunt.global_position + Vector3(grunt.burst_radius * 0.5, 0.0, 0.0)
		if bystander != null:
			bystander.global_position = grunt.global_position + Vector3(grunt.burst_radius + 4.0, 0.0, 0.0)
		var neighbour_health := neighbour.health if neighbour != null else 0.0
		var bystander_health := bystander.health if bystander != null else 0.0
		var before := floor_body.grid.painted_cell_count()
		scene._pending_splats.clear()
		grunt.health = grunt.sauce_damage_per_hit * 0.5
		var hit_at := grunt.global_position + Vector3(0.0, 0.0, grunt.radius)
		scene._record_splat(grunt, hit_at, Vector3.BACK, scene._local)
		_check(not grunt.is_alive(), "the last hit did not kill the grunt")
		if neighbour != null:
			# The juice travels: nothing lands in the frame of the burst, and all
			# of it has landed once `chain_burst_delay` has run.
			_check(is_equal_approx(neighbour.health, neighbour_health),
				"the splash landed before its juice could travel")
			scene._advance_splash_ripples(scene.chain_burst_delay + 0.01)
			var hits := maxi(1, int(round(scene.tomato_burst_damage / neighbour.sauce_damage_per_hit)))
			var splash := neighbour_health - neighbour.health
			print("splash: the neighbour lost %.2f of %.2f health" % [splash, neighbour_health])
			_check(is_equal_approx(splash, hits * neighbour.sauce_damage_per_hit),
				"the splash took %.2f off the neighbour, not %.2f" % [splash, hits * neighbour.sauce_damage_per_hit])
			_check(neighbour.is_alive(), "the splash killed a full-health grunt")
		if bystander != null:
			_check(is_equal_approx(bystander.health, bystander_health),
				"the splash reached a grunt outside its radius")
		var after := floor_body.grid.painted_cell_count()
		print("burst of %.2f m: %d floor cells painted, %d ints queued" % [
			grunt.burst_radius, after - before, scene._pending_splats.size()])
		_check(after > before, "the burst painted nothing on the floor")
		var floor_splats := 0
		var ketchup_code: int = scene._splat_code(scene.SPLAT_FLOOR, ContaminationGrid.KIND_KETCHUP)
		var i := 0
		while i + 3 < scene._pending_splats.size():
			if scene._pending_splats[i] == ketchup_code:
				floor_splats += 1
			i += 4
		_check(floor_splats > 5, "the burst queued %d floor splats for the peers" % floor_splats)
		var expected := int(round(scene.TOMATO_SPLATS_PER_M2 * PI * grunt.burst_radius * grunt.burst_radius))
		_check(floor_splats == mini(expected, scene.TOMATO_BURST_SPLAT_CAP),
			"the burst laid %d splats, not the %d its radius is worth" % [floor_splats, expected])
		# And the body is gone: nothing to walk into, nothing drawn, pieces on
		# the road instead.
		_check(grunt.vanished, "the burst grunt did not vanish")
		_check(grunt.collision_layer == 0, "the burst grunt is still on a collision layer")
		_check(not grunt._visual_root.visible, "the burst grunt is still drawn")
		var debris: TomatoDebris = null
		for child in scene.get_children():
			if child is TomatoDebris:
				debris = child
		_check(debris != null, "the burst left no pieces")
		if debris != null:
			print("debris: %d pieces" % debris.piece_count())
			_check(debris.piece_count() >= 5, "the burst left only %d pieces" % debris.piece_count())
			scene.set_physics_process(true)
			await _frames(240)
			scene.set_physics_process(false)
			_check(debris.settled(), "the pieces never came to rest")
			for piece in debris.get_children():
				_check((piece as Node3D).position.y >= 0.0, "a piece ended below the road")
		var slippery := 0
		for dx in range(-4, 5):
			for dz in range(-4, 5):
				var at := grunt.global_position + Vector3(float(dx) * 0.3, 0.0, float(dz) * 0.3)
				if floor_body.is_slippery_at(at):
					slippery += 1
		_check(slippery == 0, "the burst left %d slippery cells" % slippery)

	# --- a bowled tomato ---
	var bowler: MayoEnemy = null
	for index in scene.enemy_count():
		if scene.enemy_at(index).kind == MayoEnemy.EnemyKind.BOWLING_TOMATO:
			bowler = scene.enemy_at(index)
	_check(bowler != null and bowler.ball_pool.size() == MayoEnemy.BALLS_PER_BOWLER,
		"the bowler has no pool")
	if bowler != null and not bowler.ball_pool.is_empty():
		var ball: MayoEnemy = bowler.ball_pool[0]
		# Rolled north from inside the lane into its side wall
		# a cell and a half away. Clear of it, as the bowler itself throws:
		# a ball started inside another body is pushed out of it first, and
		# the way out is as likely to be down through the floor as anywhere.
		var launch := TomatinaMap.at_cell(Vector2(23.4, 22.8))
		launch.y = bowler.global_position.y
		ball.launch(launch, Vector3.FORWARD)
		var launched_at := ball.global_position
		_check(ball.is_ball_live(), "the ball did not go live")
		# A grunt stood in the lane: the ball rolls through it to the wall.
		var blocker: MayoEnemy = null
		for index in scene.enemy_count():
			var candidate: MayoEnemy = scene.enemy_at(index)
			if candidate.kind == MayoEnemy.EnemyKind.TOMATO_GRUNT and candidate.is_alive():
				blocker = candidate
				break
		_check(blocker != null, "no live grunt to stand in the lane")
		if blocker != null:
			blocker.global_position = launched_at + Vector3.FORWARD * 2.5
		var burst_at := Vector3.INF
		for _tick in 240:
			ball.advance(1.0 / 60.0, [])
			await physics_frame
			burst_at = ball.take_burst_request()
			if burst_at != Vector3.INF:
				break
		print("ball met its wall at %s, launched from %s" % [str(burst_at), str(launched_at)])
		_check(burst_at != Vector3.INF, "the bowled tomato never met a wall")
		_check(burst_at != Vector3.INF and absf(burst_at.y - launched_at.y) < 0.2,
			"the ball left the ground on its way to the wall")
		_check(burst_at != Vector3.INF and burst_at.z < launched_at.z - 2.0,
			"the ball burst before it had rolled anywhere")
		if blocker != null:
			_check(burst_at != Vector3.INF and burst_at.z < blocker.global_position.z,
				"the ball stopped at the grunt in the lane instead of rolling through it")
			_check(blocker.global_position.distance_to(launched_at + Vector3.FORWARD * 2.5) < 0.1,
				"the ball shoved the grunt in the lane")
		_check(not ball.is_ball_live() and ball.global_position.y < -40.0,
			"the ball did not park after bursting")
		_check(ball.burst_radius > 0.0, "the ball has nothing to burst with")

	var flank := TomatinaMap.at_cell(Vector2(28.5, 70.5))
	var ambush := TomatinaMap.at_cell(TomatinaMap.CAPRESE_AMBUSH_CELL)
	var teammate_lane := TomatinaMap.at_cell(Vector2(31.5, 69.5))
	_check(scene._nav.is_walkable(StreetMap.cell_at(flank))
		and scene._nav.line_is_walkable(flank, ambush)
		and scene._nav.line_is_walkable(flank, teammate_lane),
		"the rescue bay cannot see both the crawler and its target lane")

	# A lethal hit primes an overripe body, then releases exactly one explosion.
	var ripe_at := TomatinaMap.at_cell(Vector2(30.5, 224.5))
	var ripe: MayoEnemy = scene.enemy_at(scene.tutorial_add_enemy(MayoTutorial.KIND_TOMATO_GRUNT, ripe_at))
	ripe.burst_tier = 2
	ripe.burst_radius = 5.5
	ripe.take_sauce_hit(Vector3.INF, ripe.max_health)
	scene._pending_splats.clear()
	scene._finish_tomato_kill(ripe, scene._local)
	_check(scene.get_node_or_null("OverripeWarning") != null and ripe.vanished,
		"the overripe tomato did not show its warning")
	scene._advance_overripe_bursts(0.5)
	_check(scene._overripe_bursts.has(ripe) and scene._pending_splats.is_empty(),
		"the overripe tomato exploded before its warning ended")
	scene._burst_ground_budget = scene.TOMATO_BURST_TICK_CAP
	scene._advance_overripe_bursts(0.16)
	_check(not scene._overripe_bursts.has(ripe) and not scene._pending_splats.is_empty(),
		"the overripe tomato did not explode after its warning")

	_probe_cheese_thread(scene)

	# --- shove, the timed horde and extraction ---
	var player: MayoPlayer = scene._player
	var plaza: Rect2 = TomatinaMap.plaza_rect()
	var siren := TomatinaMap.at_cell(TomatinaMap.SIREN_CELL) + Vector3.UP * 1.28
	player.global_position = siren
	scene._check_stage_clear()
	_check(not scene.horde_spawned(), "entering the plaza armed the siren")
	var before_horde: int = scene.enemy_count()
	var peer: int = scene._local.peer_id
	scene.tomato_action(peer, 0)
	_check(scene.horde_spawned(), "using the siren did not start the finale")
	var previous: int = scene.enemy_count()
	scene._advance_horde_spawn(0.016)
	_check(scene.enemy_count() - previous <= scene.HORDE_SPAWN_PER_TICK, "spawn burst exceeded its per-step budget")
	for _step in 160:
		scene._advance_horde_spawn(0.2)
	_check(scene._finale_wave == 2, "the finale did not schedule all three approaches")
	_check(scene.enemy_count() > before_horde, "no reinforcements spawned")
	var wave_kinds: Array = scene.tutorial_spawned().map(func(entry: Array) -> int: return int(entry[0]))
	for kind in scene.FINALE_SPECIALS:
		_check(wave_kinds.has(kind), "a scheduled special enemy did not enter the finale")
	_check(scene.tutorial_spawned().size() == scene.enemy_count() - before_horde,
		"reinforcements are not recorded for a late joiner")
	var active_grunts := 0
	for enemy in scene._enemies:
		if enemy.kind == MayoEnemy.EnemyKind.TOMATO_GRUNT and enemy.is_alive() \
				and (enemy.has_meta("horde") or TomatinaMap.in_rect(plaza, enemy.global_position)):
			active_grunts += 1
	_check(active_grunts <= scene.tomatina_active_grunt_cap, "the finale exceeded the active grunt cap")

	var nearby := TomatinaMap.at_cell(Vector2(26.5, 30.5)) + Vector3.UP * 1.28
	player.global_position = nearby
	var shoved: MayoEnemy = null
	for enemy in scene._enemies:
		if enemy.kind == MayoEnemy.EnemyKind.TOMATO_GRUNT and enemy.is_alive():
			shoved = enemy
			break
	shoved.global_position = nearby + Vector3(0.0, 0.0, -1.6)
	scene._local.aim_yaw = 0.0
	scene._local.sauce = 0.0
	var health := shoved.health
	var shove_key := InputEventKey.new()
	shove_key.pressed = true
	shove_key.physical_keycode = KEY_Q
	scene._unhandled_input(shove_key)
	_check(scene._escape_shove_times.is_empty(), "the old Q binding still triggers shove")
	shove_key.physical_keycode = KEY_V
	scene._unhandled_input(shove_key)
	_check(shoved._escape_left > 0.0 and shoved.health == health, "empty-tank shove did not open a non-damaging escape")
	_check(shoved.get_collision_exceptions().has(player), "shove did not open player clearance")
	for _frame in 30:
		shoved._update_escape_clearance(1.0 / 60.0)
	_check(not shoved.get_collision_exceptions().has(player), "shove left a permanent collision exception")

	var teammate: MayoPlayer = scene.create_avatar(2, 1, false).player
	var refuge := TomatinaMap.at_cell(Vector2(TomatinaMap.SAFE_ROOMS[0].get_center())) \
		+ Vector3.UP * 1.28
	player.global_position = refuge
	teammate.global_position = scene.spawn_position_for(1)
	player.health = 30.0
	scene._update_tomatina_checkpoint([player, teammate])
	_check(scene._tomatina_checkpoint == -1 and player.health == 30.0,
		"the refuge activated before the party regrouped")
	teammate.global_position = refuge + Vector3.RIGHT * 2.0
	teammate.health = 45.0
	scene._update_tomatina_checkpoint([player, teammate])
	_check(scene._tomatina_checkpoint == 0 and player.health == player.max_health \
		and teammate.health == teammate.max_health and scene._local.sauce == 0.0,
		"the refuge failed to heal the party or granted sauce without a supply prop")
	scene._damage_player(player, player.max_health * 2.0)
	_check(player.state == MayoPlayer.State.NORMAL, "the refuge did not protect the player")
	shoved.global_position = nearby
	player.global_position = nearby + Vector3.RIGHT * 3.0
	teammate.global_position = nearby + Vector3.BACK * 4.0
	var blocker_wall := StaticBody3D.new()
	var blocker_shape := CollisionShape3D.new()
	var blocker_box := BoxShape3D.new()
	blocker_box.size = Vector3(0.3, 4.0, 1.8)
	blocker_shape.shape = blocker_box
	blocker_wall.add_child(blocker_shape)
	scene.add_child(blocker_wall)
	blocker_wall.global_position = nearby + Vector3.RIGHT * 1.5
	await _frames(2)
	shoved.horde_alert = false
	_check(shoved._choose_pursuit_target([player, teammate], 30.0, {}) == teammate,
		"the nearest player behind a wall hid a visible teammate from the enemy")
	blocker_wall.free()
	shoved.horde_alert = true
	_check(shoved._choose_pursuit_target([player, teammate], 30.0, {peer: 6}) == teammate,
		"a horde grunt ignored a nearby teammate when its first target was crowded")
	shoved.horde_alert = false
	shoved.global_position = nearby + Vector3.LEFT * 8.0
	player.finish_respawn(nearby + Vector3.UP * 0.08)
	teammate.global_position = nearby + Vector3.RIGHT * 1.6
	# --- down: the body crawls at 40% of a walk, and is then picked up ---
	scene._damage_player(teammate, teammate.max_health * 2.0)
	_check(teammate.state == MayoPlayer.State.DEAD, "a lethal hit did not put the teammate down")
	_check(teammate.crawl_allowed, "a Tomatina death did not allow crawling")
	teammate.use_injected_input = true
	teammate.input_move = Vector2.ZERO
	_check(not teammate.is_crawling(), "the body crawled before the death clip had played")
	teammate._advance_fall(teammate.death_duration)
	_check(teammate.is_crawling(), "the body could not crawl after the death clip")
	var crawl_from := teammate.global_position
	teammate.input_move = Vector2(0.0, -1.0)
	await _frames(30)
	teammate.input_move = Vector2.ZERO
	var crawled := Vector2(teammate.global_position.x - crawl_from.x,
		teammate.global_position.z - crawl_from.z).length()
	_check(crawled > 0.5 and crawled < teammate.walk_speed * 0.5 * 0.6,
		"the downed teammate crawled %.2f m in half a second (walk would be %.2f)" % [
			crawled, teammate.walk_speed * 0.5])
	_check(teammate.state == MayoPlayer.State.DEAD, "crawling stood the teammate up")
	await _frames(5)
	player.finish_respawn(teammate.global_position + Vector3.LEFT * 1.6)
	_check(scene._rescue_in_reach(player, teammate), "the rescuer is outside interaction range")
	var hud: Dictionary = scene.rescue_hud_state()
	_check(not hud.get("downed", true) and hud.get("downed_teammates", []).size() == 1
		and hud.get("in_reach", false),
		"the standing player's HUD does not offer the downed teammate in reach: %s" % str(hud))
	scene.tomato_action(peer, 0)
	scene._advance_tomatina_rescues(0.5)
	_check(teammate.state == MayoPlayer.State.DEAD, "rescue completed before its channel time")
	hud = scene.rescue_hud_state()
	_check(absf(float(hud.get("rescue_progress", -1.0)) - 0.5) < 0.05,
		"the rescuer's HUD reads %.2f of the hold halfway through" % float(hud.get("rescue_progress", -1.0)))
	var status: PackedFloat64Array = scene.tomatina_status()
	var carried := false
	for at in range(1, status.size() - 1, 2):
		if status[at] <= -1000.0 and int(floor(status[at + 1] / 1000.0)) == teammate.peer_id:
			carried = true
	_check(carried, "the rescue under way is not in the status packet")
	scene._advance_tomatina_rescues(0.6)
	_check(teammate.state == MayoPlayer.State.NORMAL and is_equal_approx(teammate.health, 40.0),
		"a teammate was not rescued in place with partial health")

	# --- the fire hose: a toggle, a long wide jet, and a sweep ---
	_check(scene.TOMATINA_RESCUE_WINDOW >= 20.0, "a downed player waits less than 20 s for a rescue")
	var hose := TomatinaMap.at_cell(scene.TOMATINA_HOSES[0]) + Vector3.UP * 1.28
	player.global_position = hose
	scene._local.aim_yaw = PI
	var wet := hose + Vector3.BACK * 2.0
	var wet_far := hose + Vector3.BACK * 16.0 + Vector3.RIGHT * 1.0
	floor_body.paint_mayo(wet)
	floor_body.paint_mayo(wet_far)
	var swept: MayoEnemy = null
	var bystander: MayoEnemy = null
	for enemy in scene._enemies:
		if enemy.kind == MayoEnemy.EnemyKind.TOMATO_GRUNT and enemy.is_alive():
			if swept == null:
				swept = enemy
			elif bystander == null:
				bystander = enemy
				break
	_check(swept != null and bystander != null, "no two grunts left to hose")
	if swept != null and bystander != null:
		swept.global_position = hose + Vector3.BACK * 15.0 + Vector3.DOWN * 1.0
		bystander.global_position = hose + Vector3.BACK * 8.0 + Vector3.RIGHT * 2.0 + Vector3.DOWN * 0.58
	scene.tomato_action(peer, 0)
	_check(scene._hose_slot_of(peer) == 0, "[E] at the hose stand did not open the hose")
	scene._advance_fire_hoses(0.016)
	var wet_after_first := floor_body.thickness_at(wet)
	var wet_kind := floor_body.sauce_kind_at(wet)
	# The first tick kills whatever was standing in the jet, and a grunt bursts
	# ketchup onto the floor as it goes -- onto the path the same tick washed.
	# The next tick washes that too; what the check wants is the floor once the
	# water has been on it a moment.
	scene._advance_fire_hoses(0.016)
	_check(floor_body.thickness_at(wet) == 0, "the hose did not clear the aimed path (after first tick: thickness %d kind %d)" % [wet_after_first, wet_kind])
	_check(floor_body.thickness_at(wet_far) == 0, "the hose did not reach 16 m down the aimed path")
	if swept != null and bystander != null:
		_check(not swept.is_alive(), "a grunt 15 m down the jet survived the water")
		_check(bystander.is_alive() and bystander._shove.length_squared() > 0.0,
			"a grunt in the water spray was not pushed safely out of the jet")
	scene.tomato_action(peer, 0)
	_check(scene._hose_slot_of(peer) < 0, "[E] again did not close the hose")
	var queued: int = scene._hose_wave_pending
	scene.tomato_action(peer, 0)
	_check(queued == scene.HOSE_WAVE_COUNT and scene._hose_wave_pending == queued,
		"reopening the hose queued a second counterattack")
	player.global_position = hose + Vector3.RIGHT * 6.0
	scene._advance_fire_hoses(0.016)
	_check(scene._hose_slot_of(peer) < 0, "the hose stayed open after the player left the stand")

	scene._advance_press_king_spawn(0.0)
	_check(scene._press_king == null and scene._finale_remaining > 0,
		"the Press King spawned while the plaza fight was still active")
	for enemy: MayoEnemy in scene._enemies:
		if enemy.has_meta("horde") or enemy.has_meta("finale_guard"):
			enemy.health = 0.0
	# The earlier hose check called its optional wave without running the
	# spawn tick. Clear that test fixture before checking the boss gate.
	scene._hose_wave_pending = 0
	player.global_position = TomatinaMap.at_cell(TomatinaMap.PRESS_KING_CELL) + Vector3.UP * 1.28
	scene._advance_press_king_spawn(0.0)
	_check(scene._press_king == null and scene._boss_entrance.active,
		"the boss appeared before its entrance warning")
	scene._advance_press_king_spawn(scene.PRESS_KING_RISE_WARNING + 0.01)
	var boss := scene._press_king as MayoEnemy
	_check(boss != null and boss.kind == MayoEnemy.EnemyKind.PRESS_KING, "the Press King did not spawn")
	if boss != null:
		_check(boss.global_position.distance_to(player.global_position) > 3.0, "the occupied boss entrance did not use a fallback")
	player.global_position = nearby
	var before_count: int = scene.enemy_count()
	scene._advance_press_king_spawn(0.0)
	_check(scene.enemy_count() == before_count, "the boss spawn was repeated")

	var cleared := [false]
	scene.stage_cleared.connect(func() -> void: cleared[0] = true)
	scene._check_stage_clear()
	_check(not cleared[0], "the stage cleared while the player was still outside the truck bay")
	player.global_position = Vector3(truck_centre.x, 1.28, truck_centre.z)
	scene._check_stage_clear()
	_check(not cleared[0], "one player cleared while a living teammate was outside the truck bay")
	teammate.global_position = player.global_position + Vector3.RIGHT * 1.5
	scene._check_stage_clear()
	_check(not cleared[0], "the party escaped with the Press King alive")
	if boss != null:
		boss.advance(2.21, [])
		scene._press_king.wash_armor(1.0)
		_check(scene._press_king.exposed_left > 0.0 and boss.is_alive(), "the hose did not open the boss armor")
		boss.advance(0.8, [])
		var exposed: float = scene._press_king.exposed_left
		scene._press_king.wash_armor(1.0)
		_check(is_equal_approx(exposed, scene._press_king.exposed_left), "continuous water refreshed the exposure")
		boss.health = 0.1
		boss.take_sauce_hit()
		boss.advance(1.91, [])
		scene._check_stage_clear()
		_check(cleared[0], "the party could not escape after defeating the Press King")

	scene.free()
	await process_frame

	# --- stage 1 is unharmed ---
	var festival = load("res://stage_1_festival.tscn").instantiate()
	root.add_child(festival)
	await _frames(2)
	_check(StreetMap.layout_override == null, "stage 1 is still carrying the Tomatina design")
	_check(StreetMap.floor_cells().size() == festival_cells,
		"stage 1's street changed after stage 2 was built")
	_check(festival.enemy_count() > 0 and festival.enemy_at(0).kind == MayoEnemy.EnemyKind.BRUISER,
		"stage 1's roster is not its own")
	festival.tomato_action(festival._local.peer_id, festival.ESCAPE_SHOVE_ACTION)
	_check(festival._escape_shove_times.is_empty(), "stage 1 accepted a shove request")
	festival.free()
	await process_frame

	if failures.is_empty():
		print("TOMATINA_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _probe_sauce_parts(scene, player: MayoPlayer) -> void:
	var parts := preload("res://scripts/tomatina_sauce_parts.gd")
	var shooter = scene._local
	var system = scene._sauce_parts
	shooter.coins = 40
	_check(not scene.buy_or_equip_sauce_part(player.peer_id, -1), "shop accepted an invalid part")
	player.global_position = TomatinaMap.refuge_shop_at(0) + Vector3.UP * 1.28
	_check(not scene.buy_or_equip_sauce_part(player.peer_id, parts.Part.CANNON),
		"first shop sold a later part")
	_check(scene.buy_or_equip_sauce_part(player.peer_id, parts.Part.FAN) and shooter.coins == 35,
		"fan purchase did not debit the wallet")
	shooter.firing = true
	scene._advance_strand(shooter, 0.01)
	_check(system._projectiles.size() == 5, "fan did not emit five streams")
	shooter.firing = false
	_check(scene.buy_or_equip_sauce_part(player.peer_id, parts.Part.FOCUS), "focus purchase failed")
	scene._emit_point(shooter)
	_check(shooter.points.back().range_scale > 1.0, "focus did not extend the jet")
	shooter.points.clear()
	system.reset()

	player.global_position = TomatinaMap.refuge_shop_at(1) + Vector3.UP * 1.28
	_check(scene.buy_or_equip_sauce_part(player.peer_id, parts.Part.BURST), "burst purchase failed")
	shooter.firing = true
	scene._advance_strand(shooter, 0.01)
	shooter.firing = false
	for i in 4:
		scene._advance_strand(shooter, 0.11)
	_check(system._projectiles.size() == 3, "one burst press did not fire exactly three shots")
	system.reset()
	_check(scene.buy_or_equip_sauce_part(player.peer_id, parts.Part.ARC), "arc purchase failed")
	shooter.firing = true
	scene._advance_strand(shooter, 0.01)
	_check(system._projectiles.size() == 1 and system._projectiles[0].velocity.y > 0.0,
		"arc did not launch upward")
	shooter.firing = false
	system.reset()

	_check(scene.buy_or_equip_sauce_part(player.peer_id, parts.Part.CANNON), "cannon purchase failed")
	shooter.sauce = 1.0
	for shot in 5:
		shooter.firing = true
		scene._advance_strand(shooter, 0.01)
		shooter.firing = false
		scene._advance_strand(shooter, 3.7)
	_check(system._projectiles.size() == 4 and shooter.sauce == 0.0, "a full cannon did not fire exactly four shots")
	var balance: int = shooter.coins
	_check(scene.buy_or_equip_sauce_part(player.peer_id, parts.Part.STANDARD)
		and scene.buy_or_equip_sauce_part(player.peer_id, parts.Part.CANNON)
		and shooter.coins == balance, "switching an owned part charged again")
	scene.buy_or_equip_sauce_part(player.peer_id, parts.Part.STANDARD)
	shooter.coins = 0
	shooter.owned_parts = 1
	shooter.sauce = 1.0
	system.reset()


func _probe_cheese_thread(scene) -> void:
	var index := -1
	for i in scene.enemy_count():
		if scene.enemy_at(i).kind == MayoEnemy.EnemyKind.CAPRESE_CRAWLER:
			index = i
			break
	if index < 0:
		_check(false, "there is no crawler for the mozzarella check")
		return
	var caster: MayoEnemy = scene.enemy_at(index)
	var player: MayoPlayer = scene._local.player
	var previous_position := player.global_position
	var previous_caster := caster.global_position
	player.global_position = TomatinaMap.at_cell(Vector2(29.5, 226.0)) + Vector3.UP * 1.28
	caster.global_position = TomatinaMap.at_cell(Vector2(29.5, 224.5)) + Vector3.UP * caster.stand_height()
	caster._visible_target = player
	scene._try_cast_cheese_thread(index, caster, 1.0)
	if not scene._cheese_threads.has(index):
		_check(false, "the crawler did not place a thread across a clear retreat path")
		player.global_position = previous_position
		caster.global_position = previous_caster
		return
	var thread = scene._cheese_threads[index]
	var centre: Vector3 = (thread.from + thread.to) * 0.5
	var across := (thread.to as Vector3) - (thread.from as Vector3)
	var approach := across.normalized().cross(Vector3.UP)
	var grounded := Vector3(centre.x, MayoPlayer.CAPSULE_HEIGHT * 0.5, centre.z) + approach * 0.4
	player.global_position = grounded
	player.frame_movement = approach * 1.0
	_check(not thread.armed(), "the crawler did not telegraph its thread")
	scene._advance_cheese_threads(thread.WINDUP + 0.01)
	_check(thread.armed() and player.cheese_snag_left == 0.0, "arming caught movement from the warning phase")
	player.global_position = grounded + Vector3.UP
	scene._advance_cheese_threads(0.01)
	_check(player.cheese_snag_left == 0.0, "jumping over the thread caught the player")
	player.global_position = grounded
	scene._advance_cheese_threads(0.01)
	_check(player.cheese_snag_left > 0.0, "crossing the armed thread on foot did not slow the player")
	scene._try_cast_cheese_thread(index, caster, 1.0)
	_check(scene._cheese_threads.size() == 1, "the crawler replaced an active thread")
	var snapshot: PackedFloat32Array = scene.cheese_thread_state()
	scene._cut_cheese_by_stream(centre - approach, centre + approach)
	_check(scene._cheese_threads.is_empty(), "a stream crossing the armed thread did not cut it")
	scene.apply_cheese_thread_state(snapshot)
	_check(scene._cheese_threads.has(index) and scene._cheese_threads[index].armed(),
		"the thread snapshot did not restore the armed segment")
	scene._cut_cheese_by_blast(centre + Vector3.UP, 0.4)
	_check(scene._cheese_threads.has(index), "a blast outside its radius cut the thread")
	scene._cut_cheese_by_blast(centre + Vector3.UP, 2.0)
	_check(scene._cheese_threads.is_empty(), "a tomato blast within reach did not cut the thread")
	player.global_position = previous_position
	player.cheese_snag_left = 0.0
	player.frame_movement = Vector3.ZERO
	caster.global_position = previous_caster
	caster._visible_target = null


func _make_network_world(view_name: String) -> Node3D:
	var viewport := SubViewport.new()
	viewport.name = view_name
	viewport.own_world_3d = true
	viewport.size = Vector2i(64, 64)
	root.add_child(viewport)
	var world := (load("res://stage_2_tomatina.tscn") as PackedScene).instantiate() as Node3D
	world.name = "World"
	viewport.add_child(world)
	set_multiplayer(SceneMultiplayer.new(), world.get_path())
	return world


func _run_network() -> void:
	var host = _make_network_world("HostView")
	var guest = _make_network_world("GuestView")
	_check(host._net.host(24818, true), "Tomatina host could not open the port")
	_check(guest._net.join("127.0.0.1", 24818), "Tomatina guest could not connect")
	for _frame in 600:
		if guest.shooter_ids().size() == 2 and guest._net.debug_state_packets > 0:
			break
		await _frames(1)
	if guest.shooter_ids().size() != 2 or host.shooter_ids().size() != 2:
		push_error("Tomatina peers failed to join")
		quit(1)
		return
	var peer: int = guest._net.local_id()
	var avatar: MayoPlayer = host.shooter_for(peer).player
	avatar.global_position = TomatinaMap.at_cell(TomatinaMap.SIREN_CELL) + Vector3.UP * 1.28
	var starting_roster: int = host.enemy_count()
	_check(guest.enemy_count() == starting_roster, "the starting roster differs between peers")
	guest._net.request_tomato_action(0)
	for _frame in 180:
		if guest.horde_spawned() and guest.enemy_count() > starting_roster:
			break
		await _frames(1)
	_check(host.horde_spawned() and guest.horde_spawned(), "guest siren did not replicate")
	_check(guest.enemy_count() > starting_roster,
		"no reinforcement spawns (host %d, guest %d, start %d, pending %d, timer %.1f)" %
			[host.enemy_count(), guest.enemy_count(), starting_roster, host._horde_pending, host._finale_elapsed])
	_check(guest._finale_elapsed > 0.0 and guest._finale_elapsed <= host._finale_elapsed,
		"guest did not receive the server finale timer")
	var reinforcement_synced := false
	for _frame in 90:
		var remote: MayoEnemy = guest.enemy_at(starting_roster)
		var original: MayoEnemy = host.enemy_at(starting_roster)
		if remote != null and original != null and remote.global_position.distance_to(original.global_position) < 2.5:
			reinforcement_synced = true
			break
		await _frames(1)
	_check(reinforcement_synced,
		"a reinforcement in the last snapshot batch did not follow the host position")

	# --- going down replicates: the guest's HUD sees the clock and the hold ---
	host.debug_clear_enemies()
	var bay := TomatinaMap.at_cell(Vector2(29.5, 19.5)) + Vector3.UP * 1.28
	host._local.player.global_position = bay
	avatar.global_position = bay + Vector3.RIGHT * 1.5
	host._damage_player(avatar, avatar.max_health * 2.0)
	var guest_hud := {}
	for _frame in 120:
		guest_hud = guest.rescue_hud_state()
		if guest_hud.get("downed", false):
			break
		await _frames(1)
	_check(guest_hud.get("downed", false) and guest_hud.get("standing_teammate", false)
		and float(guest_hud.get("left", 0.0)) > 15.0,
		"the guest was not told it is down with a teammate standing: %s" % str(guest_hud))
	var host_hud: Dictionary = host.rescue_hud_state()
	_check(host_hud.get("in_reach", false), "the host is not offered the downed guest in reach")
	host.tomato_action(host._local.peer_id, 0)
	var progress_seen := -1.0
	for _frame in 90:
		guest_hud = guest.rescue_hud_state()
		progress_seen = maxf(progress_seen, float(guest_hud.get("rescue_progress", -1.0)))
		if not guest_hud.get("downed", false):
			break
		await _frames(1)
	_check(progress_seen >= 0.0, "the guest never saw the rescue hold's progress")
	_check(not guest_hud.get("downed", false) and avatar.state == MayoPlayer.State.NORMAL,
		"the guest was not stood back up by the host's rescue")

	avatar.global_position = TomatinaMap.refuge_shower_at(0) + Vector3.UP * 1.28
	var previous_sauce: int = host._local.sauce_kind
	host._local.sauce_kind = ContaminationGrid.KIND_KETCHUP
	var hit: Vector3 = avatar.global_position + Vector3.BACK * 0.4
	host._record_splat(avatar, hit, Vector3.BACK, host._local)
	host._local.sauce_kind = previous_sauce
	var before_wash: PackedByteArray = host.body_snapshot(peer)
	for _frame in 120:
		if guest.body_snapshot(peer) == before_wash:
			break
		await _frames(1)
	_check(avatar.contamination.painted_cell_count() > 0 and guest.body_snapshot(peer) == before_wash,
		"body stain did not replicate before the shower")
	guest._net.request_tomato_action(0)
	for _frame in 120:
		if avatar.contamination.painted_cell_count() == 0 and guest.body_snapshot(peer) == host.body_snapshot(peer):
			break
		await _frames(1)
	_check(avatar.contamination.painted_cell_count() == 0
		and guest.body_snapshot(peer) == host.body_snapshot(peer), "guest shower did not replicate")

	avatar.global_position = TomatinaMap.refuge_shop_at(0) + Vector3.UP * 1.28
	for _frame in 120:
		if guest._tomatina_action_hint() == "[E] 상점 열기":
			break
		await _frames(1)
	var interact := InputEventKey.new()
	interact.physical_keycode = KEY_E
	interact.pressed = true
	guest._unhandled_input(interact)
	_check(guest._refuge_shop.visible and not host._refuge_shop.visible
		and host.is_physics_processing(), "the guest shop interrupted the host or failed to open")
	for index in 5:
		host._sauce_parts._place_coin(10000 + index, avatar.global_position - Vector3.UP)
	for _frame in 120:
		if guest._local.coins >= 5:
			break
		await _frames(1)
	_check(guest._local.coins == 5 and host._local.coins == 5,
		"the guest's coin pickup was not shared with the host")
	var parts := preload("res://scripts/tomatina_sauce_parts.gd")
	guest._request_sauce_part(parts.Part.FAN)
	for _frame in 120:
		if guest._local.sauce_part == parts.Part.FAN:
			break
		await _frames(1)
	_check(guest._local.sauce_part == parts.Part.FAN and guest._local.coins == 0
		and host.shooter_for(peer).sauce_part == parts.Part.FAN and host._local.coins == 5,
		"the guest's purchase did not equip and debit only the guest")
	avatar.global_position = TomatinaMap.refuge_shower_at(0) + Vector3.UP * 1.28
	for _frame in 120:
		if not guest._refuge_shop.visible:
			break
		await _frames(1)
	_check(not guest._refuge_shop.visible, "the guest shop stayed open after leaving its counter")
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("TOMATINA_NETWORK_OK")
	quit(0 if failures.is_empty() else 1)


func _run_profile() -> void:
	for cap in [32, 48, 64]:
		var world = load("res://stage_2_tomatina.tscn").instantiate()
		root.add_child(world)
		world.set_physics_process(false)
		world.debug_clear_enemies()
		await _frames(2)
		var plaza := TomatinaMap.at_cell(Vector2(30.0, 29.5))
		world._player.global_position = plaza + Vector3.UP * 1.28
		world._player.health = 100000.0
		for index in cap:
			var at := plaza + Vector3(float(index % 8) - 3.5, 0.0,
				float(index / 8) + 3.0) * 2.3
			world.tutorial_add_enemy(MayoTutorial.KIND_TOMATO_GRUNT, at)
		await _frames(3)
		var samples := PackedInt64Array()
		for frame in 120:
			await physics_frame
			world._player.global_position = plaza + Vector3.UP * 1.28
			var start := Time.get_ticks_usec()
			world._advance_enemies(1.0 / 60.0)
			if frame >= 30:
				samples.append(Time.get_ticks_usec() - start)
		samples.sort()
		print("TOMATINA_PROFILE cap=%d enemy_tick_p95_ms=%.2f snapshot_bytes=%d" %
			[cap, float(samples[int(samples.size() * 0.95)]) / 1000.0,
				world.enemy_state().size() * 4])
		world.free()
		await process_frame
	quit()
