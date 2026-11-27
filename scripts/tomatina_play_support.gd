extends Node3D
## Tomatina-only presentation, encounter budget and mission bookkeeping.
## Authority remains in the world; this node never decides hits on a client.

## Throw preview, after PUBG's grenade line. Within ARC_NEAR_DISTANCE of the
## hand the whole arc shows, with a tomato where it lands; past it the line
## runs solid for ARC_SOLID_LENGTH, turns to fading dashes, and is gone before
## the landing.
const ARC_STEPS := 48
const ARC_NEAR_DISTANCE := 8.0
const ARC_SOLID_LENGTH := 8.0
const ARC_FADE_LENGTH := 4.5
const ARC_DASH := 0.35
const ARC_MARKER_RADIUS := 0.32
const ARC_MARKER_POINTS := 20
const TOMATO_PATH_REFRESH_MS := 100

var world: Node3D
var elapsed := 0.0
var rows := {}
var counted := {}
var special_leases := {}
var contact_leases := {}
var _scan_left := 0.0
var _hint_left := 0.0
var _duck_left := 0.0
var _floor_left := 0.0
var _was_risky := false
var _last_down := false
var _context := {}
var _context_results := {}
var diagnostics_enabled := false
var _aim_left := 0.0
var hitches: Array[Dictionary] = []
var diagnostics_frames := 0
var diagnostics_frame_ms := 0.0
var _tomato_path: Array[Vector3] = []
var _tomato_landing: Dictionary = {}
var _tomato_origin := Vector3.INF
var _tomato_velocity := Vector3.INF
var _tomato_path_until_ms := 0
var _mortar_static_path: Array[Vector3] = []
var _mortar_origin := Vector3.INF
var _mortar_velocity := Vector3.INF
var _mortar_sweep_from := Vector3.INF
var _mortar_step_seconds := 0.0
var _mortar_static_until_ms := 0

func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	get_tree().node_removed.connect(_on_node_removed)


func _on_node_added(node: Node) -> void:
	if node is StaticBody3D and world.is_ancestor_of(node):
		_mortar_static_path.clear()
		_tomato_path.clear()
	elif node is PhysicsBody3D and world.is_ancestor_of(node) and node.collision_layer != 0:
		node.set_collision_layer_value(world.SauceParts.MORTAR_PREVIEW_ACTOR_LAYER, true)


func _on_node_removed(node: Node) -> void:
	if node is StaticBody3D:
		_mortar_static_path.clear()
		_tomato_path.clear()


func _process(delta: float) -> void:
	if world._local == null:
		return
	_hint_left = maxf(0.0, _hint_left - delta)
	_duck_left = maxf(0.0, _duck_left - delta)
	if is_instance_valid(world._stage_music):
		world._stage_music.set("priority_duck", _duck_left > 0.0)
	var down: bool = world._local.player.state == MayoPlayer.State.DEAD
	if down and not _last_down:
		prioritize_sound(1.2)
	_last_down = down
	if diagnostics_enabled and delta > 0.0334:
		hitches.append({"seconds": elapsed, "frame_ms": delta * 1000.0,
			"enemies": world.enemy_count(), "splats": world._pending_splats.size(),
			"ripples": world._splash_ripples.size(), "fuses": world._overripe_bursts.size()})
		if hitches.size() > 240:
			hitches.pop_front()
	if diagnostics_enabled:
		diagnostics_frames += 1
		diagnostics_frame_ms += delta * 1000.0

func advance(delta: float) -> void:
	if world._local == null:
		return
	if world._stage_input_enabled and not world.is_cinematic_active():
		elapsed += delta
	for shooter in world._shooters.values():
		shooter.player.recovery_protection = true
		if not rows.has(shooter.peer_id):
			rows[shooter.peer_id] = {"peer": shooter.peer_id, "seat": shooter.spawn_slot,
				"character": shooter.character_index, "kills": 0, "specials": 0,
				"rescues": 0, "damage_taken": 0.0, "downs": 0, "chain_kills": 0}
		rows[shooter.peer_id].character = shooter.character_index
	_aim_left -= delta
	if _aim_left <= 0.0:
		_aim_left = 0.05
		_update_aim_feedback()
	_update_floor_warning(delta)
	_scan_left -= delta
	if _scan_left > 0.0 or not world._is_authority():
		return
	_scan_left = 0.1
	for enemy in world._enemies:
		if not is_instance_valid(enemy) or enemy.is_alive() or counted.has(enemy.get_instance_id()) \
				or enemy.kind == MayoEnemy.EnemyKind.TOMATO_BALL:
			continue
		counted[enemy.get_instance_id()] = true
		if rows.has(enemy.hurt_by):
			rows[enemy.hurt_by].kills += 1
			if enemy.kind != MayoEnemy.EnemyKind.TOMATO_GRUNT:
				rows[enemy.hurt_by].specials += 1

func request_special(enemy: MayoEnemy, target: MayoPlayer) -> bool:
	if target == null:
		return false
	var now := Time.get_ticks_msec()
	for id in special_leases.keys():
		if int(special_leases[id].until) <= now:
			special_leases.erase(id)
	var key := enemy.get_instance_id()
	if special_leases.has(key):
		return true
	var boss = world._press_king
	if is_instance_valid(boss) and boss.is_alive() and boss.act not in [0, 1, 2, 4, 5]:
		return false
	var per_target := 0
	for lease in special_leases.values():
		if int(lease.peer) == target.peer_id:
			per_target += 1
	var limit := 1 + int(world.party_size() / 2)
	if per_target >= 1 or special_leases.size() >= limit:
		return false
	special_leases[key] = {"peer": target.peer_id, "until": now + 1800}
	return true

func request_contact(_enemy: MayoEnemy, target: MayoPlayer) -> bool:
	var now := Time.get_ticks_msec()
	if now < int(contact_leases.get(target.peer_id, 0)):
		return false
	contact_leases[target.peer_id] = now + 200
	return true

func prioritize_sound(seconds := 0.9) -> void:
	_duck_left = maxf(_duck_left, seconds)

func sound_duck_db() -> float:
	return -7.0 if _duck_left > 0.0 else 0.0

func save_diagnostics(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"frames": diagnostics_frames,
			"elapsed_frame_ms": diagnostics_frame_ms, "hitches": hitches}, "\t"))

func note_damage(peer: int, amount: float, down: bool) -> void:
	if rows.has(peer):
		rows[peer].damage_taken += maxf(0.0, amount)
		if down:
			rows[peer].downs += 1

func note_rescue(peer: int) -> void:
	if rows.has(peer):
		rows[peer].rescues += 1

func note_chain(peer: int) -> void:
	if rows.has(peer):
		rows[peer].chain_kills += 1

func report() -> Dictionary:
	_scan_left = 0.0
	advance(0.0)
	var out: Array = []
	var damage: Array = world.damage_report()
	for row in rows.values():
		var copy: Dictionary = row.duplicate()
		copy.damage = 0
		for entry in damage:
			if int(entry[0]) == int(copy.peer):
				copy.damage = entry[2]
		out.append(copy)
	out.sort_custom(func(a, b): return a.seat < b.seat)
	return {"seconds": roundi(elapsed), "players": out}

func _update_aim_feedback() -> void:
	var shooter = world._local
	var reticle := world._crosshair as Crosshair
	if not is_instance_valid(shooter.muzzle):
		if reticle != null:
			reticle.effective_range = false
		return
	var origin: Vector3 = shooter.muzzle.global_position
	var direction: Vector3 = shooter.attack_direction
	if reticle != null:
		reticle.effective_range = world._input_enabled and not world.is_cinematic_active() \
			and not shooter.player.is_incapacitated() and not shooter.player.is_wiping() \
			and world._refuge_shop_room < 0 and not world.is_range_panel_open() and shooter.sauce > 0.0 \
			and world.selected_item_slot(shooter.peer_id) == 0 and world._hose_slot_of(shooter.peer_id) < 0 \
			and _aim_within_range(shooter, origin, direction)
	_update_arc(origin, direction)
	if shooter.nozzle == world.Nozzle.CAUGHT and _hint_left <= 0.0 and shooter.sauce > 0.0:
		world._health_hud.notify_action("박사: 우클릭을 누른 채 마우스를 흔들어서 풀어요!")
		_hint_left = 9.0
		prioritize_sound(0.5)


func _aim_within_range(shooter, origin: Vector3, direction: Vector3) -> bool:
	var eye: Vector3 = shooter.aim_pivot.global_position
	var reach: float = world.stream_range * world.squeeze_pressure(shooter)
	var part: int = shooter.sauce_part
	if world.SauceParts.PROJECTILES.has(part):
		var profile: Dictionary = world.SauceParts.PROJECTILES[part]
		reach = float(profile.reach)
	elif part == world.SauceParts.Part.FOCUS:
		reach *= 1.6
	var query := PhysicsRayQueryParameters3D.create(eye, eye + direction * maxf(40.0, reach), 1)
	query.exclude = [shooter.player.get_rid()]
	var space := world.get_world_3d().direct_space_state
	var hit := space.intersect_ray(query)
	if hit.is_empty() or not hit.collider is MayoEnemy:
		return false
	var enemy := hit.collider as MayoEnemy
	if not enemy.is_alive() or origin.distance_to(hit.position) > reach:
		return false
	query.from = origin
	query.to = hit.position
	var first := space.intersect_ray(query)
	return first.is_empty() or first.collider == enemy

func _trace_tomato_path(origin: Vector3, velocity: Vector3, gravity: float, step_seconds: float,
		space: PhysicsDirectSpaceState3D) -> void:
	var now := Time.get_ticks_msec()
	if not _tomato_path.is_empty() and now < _tomato_path_until_ms \
			and origin.is_equal_approx(_tomato_origin) and velocity.is_equal_approx(_tomato_velocity):
		return
	_tomato_origin = origin
	_tomato_velocity = velocity
	_tomato_path_until_ms = now + TOMATO_PATH_REFRESH_MS
	_tomato_path = [origin]
	_tomato_landing = {}
	var query := PhysicsRayQueryParameters3D.new()
	query.collision_mask = 1
	query.exclude = [world._local.player.get_rid()]
	for step in ARC_STEPS:
		var time := step_seconds * float(step + 1)
		query.from = _tomato_path[-1]
		query.to = world.SauceParts.ballistic_position(origin, velocity, gravity, time)
		_tomato_landing = space.intersect_ray(query)
		if not _tomato_landing.is_empty():
			_tomato_path.push_back(_tomato_landing.position)
			return
		_tomato_path.push_back(query.to)


func _update_arc(origin: Vector3, direction: Vector3) -> void:
	var reticle := world._crosshair as Crosshair
	if reticle == null:
		return
	reticle.trajectory_segments.clear()
	reticle.trajectory_alpha.clear()
	reticle.landing_marker.clear()
	reticle.landing_leaf.clear()
	reticle.queue_redraw()
	if not world._input_enabled or world._local.player.is_incapacitated() or world.is_cinematic_active() \
			or world._refuge_shop_room >= 0 or world.is_range_panel_open():
		_mortar_static_path.clear()
		_tomato_path.clear()
		return
	var velocity := Vector3.ZERO
	var gravity := 9.8
	var life := 2.0
	var step_seconds := life / float(ARC_STEPS)
	var sweep_from := Vector3.INF
	# 박격포는 멀리 던지는 토마토처럼 앞부분 곡선만 보인다: 착탄 지점은 가까워도 표시하지 않는다.
	var shows_landing := true
	if world.local_holds_tomato():
		origin = world.thrown_tomato_origin(world._local)
		var charge: float = world.tomato_charge_fraction(world._local.peer_id)
		velocity = direction * lerpf(8.0, 25.0, charge) + Vector3.UP * lerpf(1.0, 3.0, charge)
	elif world._local.sauce_part == world.SauceParts.Part.ARC \
			and world.selected_item_slot(world._local.peer_id) == 0 \
			and world._hose_slot_of(world._local.peer_id) < 0:
		var profile: Dictionary = world.SauceParts.PROJECTILES[world.SauceParts.Part.ARC]
		# Drawn from where the lob really leaves, the cap's mouth.
		origin = world.part_launch_origin(world._local, world.SauceParts.Part.ARC)
		velocity = world.SauceParts.mortar_launch_velocity(direction, world._local.bottle_charge)
		gravity = profile.gravity
		life = profile.life
		step_seconds = world.get_physics_process_delta_time()
		sweep_from = world._local.aim_pivot.global_position
		shows_landing = false
	else:
		return
	# The flight, cut at the first surface it meets.
	var points: Array[Vector3]
	var landing := {}
	var space := world.get_world_3d().direct_space_state
	if shows_landing:
		_trace_tomato_path(origin, velocity, gravity, step_seconds, space)
		points = _tomato_path
		landing = _tomato_landing
	else:
		points = _mortar_path(origin, velocity, sweep_from, gravity, life, step_seconds, space)
	# Near: the whole arc, solid, and a tomato where it lands. Far: solid out to
	# ARC_SOLID_LENGTH, then dashes that fade out before the end, so a long
	# throw shows its line but never its landing point.
	var near := shows_landing and not landing.is_empty() \
		and origin.distance_to(landing.position) <= ARC_NEAR_DISTANCE
	var camera: Camera3D = world._camera
	var travelled := 0.0
	for index in points.size() - 1:
		var from: Vector3 = points[index]
		var to: Vector3 = points[index + 1]
		var length := from.distance_to(to)
		# Cut into short pieces so the dash pattern follows distance, not time.
		var pieces := maxi(1, ceili(length / ARC_DASH))
		for piece in pieces:
			var a := from.lerp(to, float(piece) / pieces)
			var b := from.lerp(to, float(piece + 1) / pieces)
			var at := travelled + length * (float(piece) + 0.5) / pieces
			var alpha := 1.0
			if not near and at > ARC_SOLID_LENGTH:
				var into := at - ARC_SOLID_LENGTH
				if into >= ARC_FADE_LENGTH:
					break
				if int(into / ARC_DASH) % 2 == 1:
					continue
				alpha = 1.0 - into / ARC_FADE_LENGTH
			if camera.is_position_behind(a) or camera.is_position_behind(b):
				continue
			reticle.trajectory_segments.append(camera.unproject_position(a))
			reticle.trajectory_segments.append(camera.unproject_position(b))
			reticle.trajectory_alpha.append(alpha)
		travelled += length
		if not near and travelled - ARC_SOLID_LENGTH >= ARC_FADE_LENGTH:
			break
	if near:
		_mark_landing(reticle, camera, landing.position, landing.normal)


## Stage geometry is static during play. Reuse its visible curve for a steady
## aim, but sweep against the current player and enemy bodies every refresh.
func _mortar_path(origin: Vector3, velocity: Vector3, sweep_from: Vector3, gravity: float,
		life: float, step_seconds: float, space: PhysicsDirectSpaceState3D) -> Array[Vector3]:
	var now := Time.get_ticks_msec()
	if now >= _mortar_static_until_ms or _mortar_static_path.is_empty() \
			or not _mortar_origin.is_equal_approx(origin) or not _mortar_velocity.is_equal_approx(velocity) \
			or not _mortar_sweep_from.is_equal_approx(sweep_from) \
			or not is_equal_approx(_mortar_step_seconds, step_seconds):
		_mortar_origin = origin
		_mortar_velocity = velocity
		_mortar_sweep_from = sweep_from
		_mortar_step_seconds = step_seconds
		_mortar_static_until_ms = now + 250
		_mortar_static_path = [origin]
		var traced_length := 0.0
		for step in ceili(life / step_seconds):
			var time := minf(life, step_seconds * float(step + 1))
			var next: Vector3 = world.SauceParts.ballistic_position(origin, velocity, gravity, time)
			var from := sweep_from if step == 0 else _mortar_static_path[-1]
			var hit: Dictionary = world._tomatina_static_hit(from, next, 0xffffffff)
			if not hit.is_empty():
				_mortar_static_path.append(hit.position)
				break
			traced_length += _mortar_static_path[-1].distance_to(next)
			_mortar_static_path.append(next)
			if traced_length >= ARC_SOLID_LENGTH + ARC_FADE_LENGTH:
				break
	var points: Array[Vector3] = [origin]
	var query := PhysicsRayQueryParameters3D.new()
	query.collision_mask = world.SauceParts.MORTAR_PREVIEW_ACTOR_MASK
	query.exclude = [world._local.player.get_rid()]
	for index in range(1, _mortar_static_path.size()):
		query.from = sweep_from if index == 1 else points[-1]
		query.to = _mortar_static_path[index]
		var hit := space.intersect_ray(query)
		var end: Vector3 = _mortar_static_path[index] if hit.is_empty() else hit.position
		# A first sweep blocked between the eye and muzzle has no visible flight.
		if index == 1 and (end - origin).dot(velocity) <= 0.0:
			break
		points.append(end)
		if not hit.is_empty():
			break
	return points


## A tomato lying flat on the surface the throw lands on: its outline traced
## round the landing point in that surface's plane and projected, so it sits
## on the floor or wall in perspective instead of floating as a screen icon.
func _mark_landing(reticle: Crosshair, camera: Camera3D, at: Vector3, normal: Vector3) -> void:
	var up := normal.normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.y) > 0.9 else Vector3.UP).normalized()
	var ahead := side.cross(up)
	# Face the leaves away from the thrower, so the tomato reads upright.
	var toward := camera.global_position - at
	if ahead.dot(toward) > 0.0:
		ahead = -ahead
		side = -side
	var lift := at + up * 0.03
	var ring := PackedVector2Array()
	for index in ARC_MARKER_POINTS:
		var angle := TAU * float(index) / ARC_MARKER_POINTS
		# A little wider than tall, like a tomato.
		var point := lift + side * cos(angle) * ARC_MARKER_RADIUS * 1.1 + ahead * sin(angle) * ARC_MARKER_RADIUS * 0.9
		if camera.is_position_behind(point):
			return
		ring.append(camera.unproject_position(point))
	var leaf := PackedVector2Array()
	var crown := lift + ahead * ARC_MARKER_RADIUS * 0.72
	for index in 10:
		var angle := TAU * float(index) / 10.0
		var reach := ARC_MARKER_RADIUS * (0.34 if index % 2 == 0 else 0.13)
		var point := crown + side * cos(angle) * reach + ahead * sin(angle) * reach
		if camera.is_position_behind(point):
			return
		leaf.append(camera.unproject_position(point))
	reticle.landing_marker = ring
	reticle.landing_leaf = leaf

func _update_floor_warning(delta: float) -> void:
	_floor_left -= delta
	if _floor_left > 0.0 or world._floor == null:
		return
	_floor_left = 0.15
	var player: MayoPlayer = world._local.player
	var ahead := player.global_position - player.global_basis.z * 1.3
	var risky: bool = world.floor_is_slippery_at(ahead) or world._floor.is_slowing_at(ahead)
	if risky and not _was_risky and player.is_running():
		world._health_hud.notify_action("미끄러운 바닥 · 달리기를 멈춰요")
	_was_risky = risky

func context_candidates(shooter) -> Array:
	var out: Array = []
	var player: MayoPlayer = shooter.player
	if player.state != MayoPlayer.State.NORMAL:
		return out
	# Each prompt is pinned beside the thing it acts on -- the `anchor`, drawn
	# by the HUD -- while `at`, what the choice between prompts is scored on,
	# stays what it always was.
	for teammate in world._shooters.values():
		if world._can_rescue_teammate(player, teammate.player):
			var down: Vector3 = teammate.player.global_position
			_candidate(out, shooter, "rescue", teammate.peer_id, down, "동료 구조 · 1초간 움직이지 않기", -4.0,
				down + Vector3.UP * 0.7)
	var at := player.global_position
	if is_instance_valid(world._truck_arrival) and is_instance_valid(world._press_king) \
			and not world._press_king.is_alive() and world._truck_arrival.in_reach(player) \
			and TomatinaMap.in_rect(world._fire_truck_zone, at):
		_candidate(out, shooter, "truck", 0, at, "트럭 탑승 · 생존 팀원 집결", -3.0,
			world._truck_arrival.final_at + Vector3.UP * 2.2)
	if not world._horde_spawned and TomatinaMap.in_rect(world._siren_zone, at):
		var generator: Vector3 = world._pump_generator.global_position if is_instance_valid(world._pump_generator) \
			else TomatinaMap.at_cell(TomatinaMap.siren_cell())
		_candidate(out, shooter, "generator", 0, at, "발전기 켜기", -2.0, generator + Vector3.UP * 1.3)
	var hose: int = world._hose_slot_of(shooter.peer_id)
	if hose < 0:
		hose = world._hose_slot(at)
	if world._horde_spawned and hose >= 0:
		_candidate(out, shooter, "hose", 0, at, "소방 호스 잡기 / 놓기", -1.0,
			TomatinaMap.at_cell(world.TOMATINA_HOSES[hose]) + Vector3.UP * 1.2)
	var room: int = world._refuge_shower_in_reach(at)
	if room >= 0:
		_candidate(out, shooter, "shower", room, TomatinaMap.refuge_shower_at(room), "샤워로 소스 씻기", 0.0,
			TomatinaMap.refuge_shower_marker_at(room))
	room = world._refuge_shop_in_reach(at)
	if room >= 0:
		var shop := TomatinaMap.refuge_shop_at(room)
		_candidate(out, shooter, "shop", room, shop, "장비 개조", 0.0, TomatinaMap.refuge_tent_at(room))
	var station: int = world.station_in_reach(player)
	if station >= 0:
		var stall: Vector3 = world._refill_stations[station]["position"]
		if world.practice_range:
			_candidate(out, shooter, "range_supply", station, at, "소스 충전·교체", 0.5, stall + Vector3.UP * 0.80)
		elif shooter.sauce < 0.999 or world.station_sauce_for(player) != shooter.sauce_kind:
			_candidate(out, shooter, "refill", station, at, "케첩 보충", 0.5, stall + Vector3.UP * 1.4)
	if world.item_slots(shooter.peer_id).find(0, 1) >= 0:
		for id in world._healing_tomatoes:
			if int(id) < 0 or int(id) >= 1000000:
				continue
			var node: Node3D = world._healing_tomatoes[id].node
			if is_instance_valid(node) and at.distance_squared_to(node.global_position) < 6.25:
				_candidate(out, shooter, "pickup", int(id), node.global_position, "토마토 줍기", 0.0,
					node.global_position + Vector3.UP * 0.35)
	if is_instance_valid(world._victims):
		var body: int = world._victims.in_reach(at)
		if body >= 0:
			_add_loot_candidate(out, shooter, body)
	return out


func can_search_body(shooter, body: int) -> bool:
	if not is_instance_valid(world._victims) or not world._victims.can_loot(body, shooter.player.global_position):
		return false
	var candidates: Array = []
	_add_loot_candidate(candidates, shooter, body)
	return not candidates.is_empty()


func _add_loot_candidate(out: Array, shooter, body: int) -> void:
	var lying: Vector3 = world._victims.positions[body] + Vector3.UP * 0.35
	_candidate(out, shooter, "loot", body, lying, "시체 수색 · %d초간 누르기" % TomatinaVictims.LOOT_TIME,
		0.2, lying + Vector3.UP * 0.3)

func _candidate(out: Array, shooter, kind: String, id: int, at: Vector3, text: String, priority: float,
		anchor := Vector3.INF) -> void:
	var eye: Vector3 = world.player_eye_position(shooter)
	var offset := at - eye
	var distance := offset.length()
	var facing: Vector3 = -world._aim_basis(shooter).z
	var alignment := facing.dot(offset.normalized()) if distance > 0.01 else 1.0
	if kind in ["pickup", "shop", "shower", "loot"]:
		if alignment < -0.1:
			return
		var query := PhysicsRayQueryParameters3D.create(eye, at, 1)
		query.exclude = [shooter.player.get_rid()]
		var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.position.distance_to(at) > 0.65:
			return
	out.append({"kind": kind, "id": id, "text": text, "anchor": anchor,
		"score": priority + distance * 0.15 + (1.0 - alignment)})

func context_target(shooter) -> Dictionary:
	var frame := Engine.get_physics_frames()
	var cached: Dictionary = _context_results.get(shooter.peer_id, {})
	if not cached.is_empty() and int(cached.frame) == frame:
		return cached.target
	var candidates := context_candidates(shooter)
	if candidates.is_empty():
		_context.erase(shooter.peer_id)
		_context_results[shooter.peer_id] = {"frame": frame, "target": {}}
		return {}
	candidates.sort_custom(func(a, b): return a.score < b.score)
	var previous: Dictionary = _context.get(shooter.peer_id, {})
	var now := Time.get_ticks_msec()
	if not previous.is_empty() and now < int(previous.until):
		for candidate in candidates:
			if candidate.kind == previous.kind and candidate.id == previous.id and candidate.score <= candidates[0].score + 0.7:
				_context_results[shooter.peer_id] = {"frame": frame, "target": candidate}
				return candidate
	var chosen: Dictionary = candidates[0]
	_context[shooter.peer_id] = {"kind": chosen.kind, "id": chosen.id, "until": now + 300}
	_context_results[shooter.peer_id] = {"frame": frame, "target": chosen}
	return chosen

func interaction_hint() -> String:
	var target := context_target(world._local)
	if target.is_empty():
		return ""
	# Same label as the key legend and the tutorial; InputEvent.as_text() reads
	# "E - Physical" for a physical binding.
	var key := preload("res://scripts/game_options.gd").key_label("interact", "E")
	return "[%s] %s" % [key, target.text]
