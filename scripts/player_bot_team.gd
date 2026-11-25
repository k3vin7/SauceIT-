extends Node
## Offline teammates driven through the same movement/fire/action inputs.
## No direct damage, teleport recovery, free supplies or omniscient targeting.
const BOT_NAMES := ["P1", "P2", "P3", "P4"]
var world: Node3D
var autoplay := false
var brains := {}
var route: Array[Dictionary] = []
var route_index := 0
var elapsed := 0.0
var finished := false
var events: Array[Dictionary] = []
var _hud_clock := 0.0

func configure(play_world: Node3D, control_leader := false, bot_count := 3) -> void:
	world = play_world
	if world.map_kind != world.MapKind.TOMATINA or world._net.is_online():
		push_error("Player bots currently support offline Tomatina practice only")
		set_physics_process(false)
		return
	autoplay = control_leader
	process_physics_priority = -30
	var character := 0
	for slot in range(1, 1 + clampi(bot_count, 0, 3)):
		if character == world._local.character_index:
			character += 1
		var shooter = world.create_avatar(9000 + slot, slot, false)
		world.set_character_variant(shooter.peer_id, character)
		_add_brain(shooter, slot)
		character += 1
	_add_brain(world._local, 0)
	for leg in TomatinaMap.route_points().size():
		for point: Vector2 in TomatinaMap.route_points()[leg]:
			var at := TomatinaMap.at_cell(point)
			var safe := TomatinaMap.safe_room_at(Vector2i(point.floor()))
			route.append({"at": at, "safe": safe})
	world.set_meta("bot_practice", true)
	world.stage_cleared.connect(func(): finished = true; _event("stage_cleared", 0))
	_event("team_started", 0)

func _add_brain(shooter, slot: int) -> void:
	brains[shooter.peer_id] = {"slot": slot, "state": "따라가기", "think": slot * 0.035,
		"move": Vector2.ZERO, "run": false, "fire": false, "jump": false,
		"shake": 0.0, "action_left": 0.0, "target": null, "path": PackedVector3Array(),
		"path_goal": Vector3.INF, "path_left": 0.0, "path_index": 0,
		"last_at": shooter.player.global_position, "stuck": 0.0, "stuck_count": 0,
		"shots_seconds": 0.0, "distance": 0.0, "rescues_started": 0, "refills": 0,
		"was_dead": false, "downs": 0, "no_path": 0, "no_path_left": 0.0, "heals": 0, "ignored": {}}
	if slot > 0 or autoplay:
		shooter.player.use_injected_input = true

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F6:
		autoplay = not autoplay
		if not autoplay:
			world.debug_clear_input_override()
			world._local.player.use_injected_input = false
		_event("autoplay_on" if autoplay else "autoplay_off", 0)
		get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(world) or world._local == null:
		return
	if finished or not world._input_enabled or world.is_cinematic_active():
		for peer in brains:
			if brains[peer].slot > 0 or autoplay:
				_stop(peer)
		return
	elapsed += delta
	if autoplay:
		_advance_route()
	for peer in brains:
		var brain: Dictionary = brains[peer]
		var shooter = world.shooter_for(peer)
		if shooter == null:
			continue
		var at: Vector3 = shooter.player.global_position
		brain.distance += at.distance_to(brain.last_at)
		var dead: bool = shooter.player.state == MayoPlayer.State.DEAD
		if dead and not brain.was_dead:
			brain.downs += 1
			_event("downed", peer)
		brain.was_dead = dead
		if brain.slot == 0 and not autoplay:
			brain.last_at = at
			brain.state = "사람 조작"
			continue
		brain.path_left -= delta
		brain.no_path_left = maxf(0.0, brain.no_path_left - delta)
		brain.action_left = maxf(0.0, brain.action_left - delta)
		if brain.move.length_squared() > 0.1 and at.distance_to(brain.last_at) < delta * 0.4 and not dead:
			brain.stuck += delta
		else:
			brain.stuck = maxf(0.0, brain.stuck - delta * 2.0)
		brain.last_at = at
		brain.think -= delta
		if brain.think <= 0.0:
			brain.think = 0.12
			_think(shooter, brain)
		_apply(shooter, brain)
		if brain.fire:
			brain.shots_seconds += delta
	_hud_clock -= delta
	if _hud_clock <= 0.0:
		_hud_clock = 0.25
		_update_hud()

func _advance_route() -> void:
	if route_index >= route.size() or world._horde_spawned:
		return
	var at: Vector3 = world._local.player.global_position
	for step in 4:
		if route_index >= route.size():
			return
		var point: Dictionary = route[route_index]
		if int(point.safe) >= 0 and world._tomatina_checkpoint < int(point.safe):
			return # Never bypass a regroup checkpoint just by fighting past it.
		var reached := _flat_distance(at, point.at) <= 3.5
		var passed := false
		if route_index + 1 < route.size():
			passed = _passed_waypoint(at, point.at, route[route_index + 1].at)
		if not reached and not passed:
			return
		_event("route_point", world._local.peer_id)
		route_index += 1

static func _passed_waypoint(at: Vector3, point: Vector3, next: Vector3) -> bool:
	var along := Vector2(next.x - point.x, next.z - point.z)
	if along.length_squared() < 0.01:
		return false
	var offset := Vector2(at.x - point.x, at.z - point.z)
	var direction := along.normalized()
	var progress := offset.dot(direction)
	var lateral := (offset - direction * progress).length()
	return progress > 1.0 and lateral < 22.0 and _flat_distance(at, next) + 2.0 < _flat_distance(at, point)

func _think(shooter, brain: Dictionary) -> void:
	brain.move = Vector2.ZERO
	brain.run = false
	brain.fire = false
	brain.jump = false
	brain.shake = 0.0
	var player: MayoPlayer = shooter.player
	if player.state == MayoPlayer.State.DEAD:
		brain.state = "구조 대기"
		return
	if player.is_incapacitated():
		brain.state = "일어서기"
		return
	if _evade_blast(shooter, brain):
		return
	if world._rescue_attempts.has(shooter.peer_id):
		brain.state = "구조 중"
		return
	if player.visor != null and player.visor.coverage() > 0.12 and not player.is_wiping():
		world.begin_wipe_for(shooter.peer_id)
	if player.is_wiping():
		brain.state = "고글 닦기"
		return
	if _heal(shooter, brain):
		return
	var teammate = _downed_teammate(shooter)
	if teammate != null:
		brain.state = "동료 구조"
		if world._can_rescue_teammate(player, teammate.player):
			if brain.action_left <= 0.0:
				world.perform_context_action(shooter.peer_id, "rescue", teammate.peer_id)
				brain.action_left = 1.2
				brain.rescues_started += 1
		else:
			_steer(shooter, brain, teammate.player.global_position, 1.8)
		return
	if shooter.sauce < 0.24 and world._hose_slot_of(shooter.peer_id) < 0:
		var station := _supply_target(shooter)
		if not station.is_empty():
			brain.state = "소스 보급"
			if world.station_in_reach(player) >= 0 and brain.action_left <= 0.0:
				if world.refill_for(shooter.peer_id, world.STATION_SAUCE_HERE):
					brain.refills += 1
					_event("refill", shooter.peer_id)
				brain.action_left = 0.8
			else:
				_steer(shooter, brain, station.at, 0.8)
			return
	var boss = world._press_king
	if autoplay and world._horde_spawned and int(brain.slot) < 2 and is_instance_valid(boss) \
			and boss.is_alive() and not boss.armor_broken and boss.exposed_left <= 0.0:
		_finale(shooter, brain)
		return
	var target := _visible_enemy(shooter, brain)
	brain.target = target
	if target != null:
		brain.state = "전투"
		var aim: Vector3 = target.global_position
		_aim(shooter, aim, brain.slot)
		var gap := _flat_distance(player.global_position, target.global_position)
		if world._hose_slot_of(shooter.peer_id) >= 0:
			brain.fire = true
			return
		if shooter.sauce > 0.0 and shooter.sauce < world.steady_level and shooter.bottle_charge < 1.0 and not shooter.bottle_boosting:
			brain.state = "소스통 흔들기"
			brain.shake = 1.0
		elif gap < (5.2 if world._is_overripe(target) else 4.6) and absf(wrapf(shooter.aim_yaw - _yaw_to(player.global_position, aim), -PI, PI)) < 0.15:
			brain.fire = _clear_shot(shooter, target)
			if gap < 2.6 + target.radius:
				_move_direction(shooter, brain, player.global_position - aim, false)
			elif not brain.fire:
				_move_direction(shooter, brain, (aim - player.global_position).cross(Vector3.UP), false)
		else:
			_steer(shooter, brain, aim, 3.8, false)
		if gap < 3.0 and brain.action_left <= 0.0:
			world.tomato_action(shooter.peer_id, world.ESCAPE_SHOVE_ACTION)
			brain.action_left = 1.5
		return
	if autoplay and world._horde_spawned:
		_finale(shooter, brain)
		return
	var goal := _formation_goal(shooter, brain)
	if autoplay and brain.slot == 0:
		goal = route[route_index].at if route_index < route.size() else TomatinaMap.at_cell(TomatinaMap.siren_cell())
		var lag := _party_lag()
		if lag > 22.0:
			brain.state = "팀원 기다리기"
			return
	brain.state = "진행" if brain.slot == 0 else "대형 유지"
	_steer(shooter, brain, goal, 2.0 if brain.slot == 0 else 2.8)
	if autoplay and route_index >= route.size() and brain.slot == 0 \
			and TomatinaMap.in_rect(world._siren_zone, player.global_position) and brain.action_left <= 0.0:
		world.tomato_action(shooter.peer_id, 0)
		brain.action_left = 1.0

func _downed_teammate(shooter):
	var best = null
	var distance := 26.0
	for other in world._shooters.values():
		if other == shooter or other.player.state != MayoPlayer.State.DEAD:
			continue
		var gap := _flat_distance(shooter.player.global_position, other.player.global_position)
		if gap < distance:
			distance = gap
			best = other
	return best

func _supply_target(shooter) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for station: Dictionary in world.refill_stations():
		if not world.can_select_refill_sauce(int(station.get("sauce", 0))):
			continue
		var point: Vector3 = station.position + station.get("facing", Vector3.FORWARD) * 1.5
		var gap := _flat_distance(shooter.player.global_position, point)
		candidates.append({"at": point, "distance": gap})
	candidates.sort_custom(func(a, b): return a.distance < b.distance)
	for candidate in candidates:
		if world._nav.line_is_walkable(shooter.player.global_position, candidate.at):
			return candidate
		var path: PackedVector3Array = world._nav.route(shooter.player.global_position, candidate.at)
		if not path.is_empty():
			return candidate
	return {}

func _evade_blast(shooter, brain: Dictionary) -> bool:
	for enemy in world._overripe_bursts:
		if not is_instance_valid(enemy):
			continue
		var fuse: Dictionary = world._overripe_bursts[enemy]
		var at: Vector3 = fuse.at
		var away: Vector3 = shooter.player.global_position - at
		if _flat_distance(shooter.player.global_position, at) > enemy.burst_radius + 1.0:
			continue
		if not world._tomato_blast_reaches(at, shooter.player):
			continue
		brain.state = "폭발 회피"
		_move_direction(shooter, brain, away if away.length_squared() > 0.1 else Vector3.BACK, true)
		return true
	return false

func _heal(shooter, brain: Dictionary) -> bool:
	if shooter.player.health >= 65.0:
		if world.selected_item_slot(shooter.peer_id) > 0:
			world.tomato_action(shooter.peer_id, 10)
		return false
	var slots: Array = world.item_slots(shooter.peer_id)
	var tomato := slots.find(1, 1)
	if tomato >= 0:
		brain.state = "토마토로 회복"
		if world.selected_item_slot(shooter.peer_id) != tomato:
			world.tomato_action(shooter.peer_id, 10 + tomato)
		else:
			world.tomato_action(shooter.peer_id, 2)
			brain.heals += 1
		return true
	for candidate in world.play_support.context_candidates(shooter):
		if candidate.kind == "pickup":
			brain.state = "회복 토마토 줍기"
			world.perform_context_action(shooter.peer_id, "pickup", candidate.id)
			return true
	if world.selected_item_slot(shooter.peer_id) > 0:
		world.tomato_action(shooter.peer_id, 10)
	return false

func _visible_enemy(shooter, brain: Dictionary) -> MayoEnemy:
	var best: MayoEnemy
	var score := INF
	var forward: Vector3 = -Basis(Vector3.UP, shooter.aim_yaw).z
	for enemy: MayoEnemy in world._enemies:
		if not enemy.is_alive() or enemy.kind == MayoEnemy.EnemyKind.TOMATO_BALL:
			continue
		if elapsed < float(brain.ignored.get(enemy.get_instance_id(), 0.0)):
			continue
		var offset: Vector3 = enemy.global_position - shooter.player.global_position
		var distance := offset.length()
		if distance > 25.0 or (distance > 5.0 and forward.dot(offset.normalized()) < 0.05):
			continue
		var query := PhysicsRayQueryParameters3D.create(shooter.player.global_position + Vector3.UP * world.eye_height, enemy.global_position, 1)
		query.exclude = [shooter.player.get_rid()]
		var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.collider != enemy:
			continue
		var weight := distance - (3.0 if world._is_overripe(enemy) and distance > 5.5 else 0.0)
		if brain.target == enemy:
			weight -= 2.0
		if weight < score:
			score = weight
			best = enemy
	return best

func _clear_shot(shooter, target: MayoEnemy) -> bool:
	var query := PhysicsRayQueryParameters3D.create(shooter.muzzle.global_position, target.global_position, 1)
	query.exclude = [shooter.player.get_rid()]
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.collider == target

func _aim(shooter, at: Vector3, slot: int) -> void:
	var offset: Vector3 = at - (shooter.player.global_position + Vector3.UP * world.eye_height)
	var yaw := atan2(-offset.x, -offset.z) - float(shooter.stream_recoil_yaw)
	var pitch := atan2(offset.y, Vector2(offset.x, offset.z).length()) - float(world.aim_pitch_offset(shooter))
	# Reaction/turn limits and a small deterministic error, never instant auto-headshots.
	shooter.aim_yaw = rotate_toward(shooter.aim_yaw, yaw, 0.48)
	shooter.aim_pitch = move_toward(shooter.aim_pitch, pitch + sin(elapsed * 1.7 + slot) * 0.018, 0.32)

func _steer(shooter, brain: Dictionary, goal: Vector3, stop: float, allow_run := true) -> void:
	var at: Vector3 = shooter.player.global_position
	if _flat_distance(at, goal) <= stop:
		return
	var aim := goal
	if not world._nav.line_is_walkable(at, goal):
		if brain.path_left <= 0.0 or _flat_distance(brain.path_goal, goal) > 4.5:
			brain.path = world._nav.route(at, goal, (float(brain.slot) - 1.5) * 0.35)
			if brain.path.is_empty() and is_instance_valid(brain.target):
				# An enemy's centre may occupy a blocked prop cell. Route to a
				# reachable firing position around it, never into the collider.
				var best_size := 100000
				for sample in 8:
					var angle := TAU * float(sample) / 8.0
					var firing_at := goal + Vector3(cos(angle), 0, sin(angle)) * 3.8
					var candidate: PackedVector3Array = world._nav.route(at, firing_at)
					if not candidate.is_empty() and candidate.size() < best_size:
						brain.path = candidate
						best_size = candidate.size()
			brain.path_index = 0
			brain.path_left = 0.8
			brain.path_goal = goal
		var path: PackedVector3Array = brain.path
		while brain.path_index < path.size() and _flat_distance(at, path[brain.path_index]) < 1.4:
			brain.path_index += 1
		if brain.path_index >= path.size():
			brain.state = "경로 확인"
			if is_instance_valid(brain.target):
				brain.ignored[brain.target.get_instance_id()] = elapsed + 3.0
			elif autoplay and int(brain.slot) == 0 and route_index + 1 < route.size() and int(route[route_index].safe) < 0:
				var next: Vector3 = route[route_index + 1].at
				if not world._nav.route(at, next).is_empty():
					route_index += 1
					_event("route_detour", shooter.peer_id)
			if brain.no_path_left <= 0.0:
				brain.no_path += 1
				brain.no_path_left = 4.0
				_event("no_route", shooter.peer_id)
			return
		aim = path[brain.path_index]
	if brain.target == null:
		_aim(shooter, aim + Vector3.UP * world.eye_height, brain.slot)
	_move_direction(shooter, brain, aim - at, allow_run and _flat_distance(at, goal) > 9.0)
	if brain.stuck > 1.2:
		brain.jump = true
		brain.move.x += 0.7 if int(brain.slot) % 2 == 0 else -0.7
		brain.move = brain.move.limit_length()
		brain.path_left = 0.0
	if brain.stuck > 4.0:
		brain.stuck = 1.3
		brain.stuck_count += 1
		_event("navigation_stuck", shooter.peer_id)

func _move_direction(shooter, brain: Dictionary, direction: Vector3, running: bool) -> void:
	direction.y = 0.0
	if direction.length_squared() < 0.001:
		return
	var desired := direction.normalized()
	for other in world._shooters.values():
		if other == shooter:
			continue
		var away: Vector3 = shooter.player.global_position - other.player.global_position
		away.y = 0.0
		var distance := away.length()
		if distance > 0.01 and distance < 2.2:
			desired += away.normalized() * (1.0 - distance / 2.2) * 1.5
	desired = desired.normalized()
	var chosen := Vector3.ZERO
	var best_score := -INF
	for angle in [0.0, 0.55, -0.55, 1.1, -1.1, 2.1, -2.1, PI]:
		var candidate := desired.rotated(Vector3.UP, angle)
		if shooter.player.test_move(shooter.player.global_transform, candidate * 1.2):
			continue
		var score := candidate.dot(desired)
		if score > best_score:
			best_score = score
			chosen = candidate
	if chosen == Vector3.ZERO:
		chosen = desired
		brain.jump = true
	var local: Vector3 = Basis(Vector3.UP, shooter.aim_yaw).inverse() * chosen
	brain.move = Vector2(local.x, local.z).limit_length()
	var ahead: Vector3 = shooter.player.global_position + direction.normalized() * 1.7
	brain.run = running and not world.floor_is_slippery_at(ahead) and not world._floor.is_slowing_at(ahead)
	if brain.stuck > 4.0:
		brain.stuck = 1.3
		brain.stuck_count += 1
		brain.jump = true
		_event("navigation_stuck", shooter.peer_id)

func _formation_goal(shooter, brain: Dictionary) -> Vector3:
	var leader = world._local
	var basis := Basis(Vector3.UP, leader.aim_yaw)
	var offsets := [Vector3.ZERO, Vector3(-2.2, 0, 3.3), Vector3(2.2, 0, 4.3), Vector3(0, 0, 6.5)]
	return leader.player.global_position + basis * offsets[int(brain.slot)]

func _party_lag() -> float:
	var lag := 0.0
	for shooter in world._shooters.values():
		if shooter.player.state != MayoPlayer.State.DEAD:
			lag = maxf(lag, _flat_distance(shooter.player.global_position, world._local.player.global_position))
	return lag

func _finale(shooter, brain: Dictionary) -> void:
	var boss = world._press_king
	if is_instance_valid(boss) and not boss.is_alive():
		brain.state = "탈출 집결"
		if world._hose_slot_of(shooter.peer_id) >= 0:
			world.tomato_action(shooter.peer_id, 0)
			return
		_steer(shooter, brain, Vector3(world._fire_truck_zone.get_center().x, 1.28, world._fire_truck_zone.get_center().y), 2.0)
		if brain.action_left <= 0.0:
			world.tomato_action(shooter.peer_id, 0)
			brain.action_left = 1.0
		return
	if int(brain.slot) < 2:
		var hose: int = world._hose_slot_of(shooter.peer_id)
		if hose >= 0:
			brain.state = "호스로 지원"
			brain.fire = true
			if is_instance_valid(boss) and boss.is_alive():
				_aim(shooter, boss.global_position, brain.slot)
			return
		var at := TomatinaMap.at_cell(world.TOMATINA_HOSES[int(brain.slot)])
		brain.state = "호스 확보"
		_steer(shooter, brain, at, 1.5)
		if _flat_distance(shooter.player.global_position, at) < 2.5 and brain.action_left <= 0.0:
			world.tomato_action(shooter.peer_id, 0)
			brain.action_left = 1.0
	else:
		brain.state = "광장 방어"
		_steer(shooter, brain, TomatinaMap.at_cell(Vector2(30.0 + (brain.slot - 2) * 2.0, 29.0)), 2.0)

func _apply(shooter, brain: Dictionary) -> void:
	shooter.player.use_injected_input = true
	shooter.player.input_move = brain.move
	shooter.player.input_run = brain.run
	shooter.player.input_jump = brain.jump
	shooter.firing = brain.fire
	shooter.bottle_shake_input = brain.shake
	if int(brain.slot) == 0:
		world.debug_set_input(brain.move, brain.run, brain.fire, brain.jump)
		world.debug_input_shake = brain.shake

func _stop(peer: int) -> void:
	var shooter = world.shooter_for(peer)
	if shooter == null:
		return
	var brain: Dictionary = brains[peer]
	brain.move = Vector2.ZERO
	brain.run = false
	brain.fire = false
	brain.jump = false
	brain.shake = 0.0
	_apply(shooter, brain)

func _update_hud() -> void:
	world.set_meta("bot_autoplay", autoplay)

func _event(kind: String, peer: int) -> void:
	events.append({"seconds": snappedf(elapsed, 0.1), "kind": kind, "peer": peer, "route_index": route_index})
	if events.size() > 500:
		events.pop_front()

func report() -> Dictionary:
	var players: Array = []
	for peer in brains:
		var brain: Dictionary = brains[peer]
		players.append({"peer": peer, "name": BOT_NAMES[brain.slot], "state": brain.state,
			"position": [world.shooter_for(peer).player.global_position.x, world.shooter_for(peer).player.global_position.z],
			"path_goal": [brain.path_goal.x, brain.path_goal.z] if is_finite(brain.path_goal.x) else [], "no_path": brain.no_path, "heals": brain.heals,
			"distance_m": snappedf(brain.distance, 0.1), "fire_seconds": snappedf(brain.shots_seconds, 0.1),
			"refills": brain.refills, "rescues_started": brain.rescues_started,
			"downs": brain.downs, "navigation_stuck": brain.stuck_count})
	return {"scope": "offline input-driven bots; not four network clients or human playtest",
		"seconds": elapsed, "autoplay": autoplay, "cleared": finished,
		"route_index": route_index, "route_points": route.size(), "players": players,
		"mission": world.mission_report(), "events": events}

static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

static func _yaw_to(from: Vector3, to: Vector3) -> float:
	return atan2(from.x - to.x, from.z - to.z)
