extends Node3D
## Tomatina-only presentation, encounter budget and mission bookkeeping.
## Authority remains in the world; this node never decides hits on a client.

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
	if world._input_enabled and not world.is_cinematic_active():
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
	var camera: Camera3D = world._camera
	if camera == null or not is_instance_valid(shooter.muzzle):
		return
	var origin: Vector3 = shooter.muzzle.global_position
	var direction: Vector3 = shooter.attack_direction
	var query := PhysicsRayQueryParameters3D.create(camera.global_position,
		camera.global_position - camera.global_basis.z * 40.0, 1)
	query.exclude = [shooter.player.get_rid()]
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	var reach: float = world.stream_range * world.squeeze_pressure(shooter)
	var part: int = shooter.sauce_part
	if world.SauceParts.PROJECTILES.has(part):
		var profile: Dictionary = world.SauceParts.PROJECTILES[part]
		reach = float(profile.speed) * float(profile.life)
	elif part == world.SauceParts.Part.FOCUS:
		reach *= 1.6
	var valid := false
	if not hit.is_empty() and hit.collider is MayoEnemy:
		var enemy := hit.collider as MayoEnemy
		valid = enemy.is_alive() and origin.distance_to(hit.position) <= reach and shooter.sauce > 0.0
		if valid:
			var obstruction := PhysicsRayQueryParameters3D.create(origin, hit.position, 1)
			obstruction.exclude = [shooter.player.get_rid()]
			var first := world.get_world_3d().direct_space_state.intersect_ray(obstruction)
			valid = first.is_empty() or first.collider == enemy
	if world._crosshair is Crosshair:
		world._crosshair.effective_range = valid and world._input_enabled and not shooter.player.is_incapacitated()
	_update_arc(origin, direction)
	if shooter.nozzle == world.Nozzle.CAUGHT and _hint_left <= 0.0 and shooter.sauce > 0.0:
		world._health_hud.notify_action("박사: 막힌 소스통은 흔들어서 풀어요!")
		world._health_hud.notify_action("우클릭을 누른 채 마우스 흔들기")
		_hint_left = 9.0
		prioritize_sound(0.5)

func _update_arc(origin: Vector3, direction: Vector3) -> void:
	var reticle := world._crosshair as Crosshair
	if reticle == null:
		return
	reticle.trajectory_segments.clear()
	reticle.queue_redraw()
	if not world._input_enabled or world._local.player.is_incapacitated() or world.is_cinematic_active():
		return
	var velocity := Vector3.ZERO
	var gravity := 9.8
	var life := 2.0
	if world.local_holds_tomato():
		origin = world._local.player.global_position + Vector3.UP * 0.65
		var charge: float = world.tomato_charge_fraction(world._local.peer_id)
		velocity = direction * lerpf(8.0, 25.0, charge) + Vector3.UP * lerpf(1.0, 3.0, charge)
	elif world._local.sauce_part == world.SauceParts.Part.ARC:
		var profile: Dictionary = world.SauceParts.PROJECTILES[world.SauceParts.Part.ARC]
		velocity = world._arc_launch_direction(world._local, origin) * float(profile.speed)
		gravity = profile.gravity
		life = profile.life
	else:
		return
	var camera: Camera3D = world._camera
	var previous := origin
	for step in 32:
		var time := life * float(step + 1) / 32.0
		var next := origin + velocity * time + Vector3.DOWN * gravity * time * time * 0.5
		# Stop at the first surface; no landing circle or endpoint marker.
		var query := PhysicsRayQueryParameters3D.create(previous, next, 1)
		query.exclude = [world._local.player.get_rid()]
		if not world.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			break
		if step % 2 == 0:
			if not camera.is_position_behind(previous) and not camera.is_position_behind(next):
				reticle.trajectory_segments.append(camera.unproject_position(previous))
				reticle.trajectory_segments.append(camera.unproject_position(next))
		previous = next

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
	for teammate in world._shooters.values():
		if world._can_rescue_teammate(player, teammate.player):
			_candidate(out, shooter, "rescue", teammate.peer_id, teammate.player.global_position, "동료 구조 · 1초간 움직이지 않기", -4.0)
	var at := player.global_position
	if is_instance_valid(world._truck_arrival) and is_instance_valid(world._press_king) \
			and not world._press_king.is_alive() and world._truck_arrival.in_reach(player) \
			and TomatinaMap.in_rect(world._fire_truck_zone, at):
		_candidate(out, shooter, "truck", 0, at, "트럭 탑승 · 생존 팀원 집결", -3.0)
	if not world._horde_spawned and TomatinaMap.in_rect(world._siren_zone, at):
		_candidate(out, shooter, "generator", 0, at, "발전기 켜기", -2.0)
	if world._horde_spawned and (world._hose_slot_of(shooter.peer_id) >= 0 or world._hose_slot(at) >= 0):
		_candidate(out, shooter, "hose", 0, at, "소방 호스 잡기 / 놓기", -1.0)
	var room: int = world._refuge_shower_in_reach(at)
	if room >= 0:
		_candidate(out, shooter, "shower", room, TomatinaMap.refuge_shower_at(room), "샤워로 소스 씻기", 0.0)
	room = world._refuge_shop_in_reach(at)
	if room >= 0:
		_candidate(out, shooter, "shop", room, TomatinaMap.refuge_shop_at(room), "장비 개조", 0.0)
	var station: int = world.station_in_reach(player)
	if station >= 0 and (shooter.sauce < 0.999 or world.station_sauce_for(player) != shooter.sauce_kind):
		_candidate(out, shooter, "refill", station, at, "케첩 보충", 0.5)
	if world.item_slots(shooter.peer_id).find(0, 1) >= 0:
		for id in world._healing_tomatoes:
			if int(id) < 0 or int(id) >= 1000000:
				continue
			var node: Node3D = world._healing_tomatoes[id].node
			if is_instance_valid(node) and at.distance_squared_to(node.global_position) < 6.25:
				_candidate(out, shooter, "pickup", int(id), node.global_position, "토마토 줍기", 0.0)
	return out

func _candidate(out: Array, shooter, kind: String, id: int, at: Vector3, text: String, priority: float) -> void:
	var eye: Vector3 = shooter.player.global_position + Vector3.UP * world.eye_height
	var offset := at - eye
	var distance := offset.length()
	var facing: Vector3 = -Basis.from_euler(Vector3(shooter.aim_pitch, shooter.aim_yaw, 0)).z
	var alignment := facing.dot(offset.normalized()) if distance > 0.01 else 1.0
	if kind in ["pickup", "shop", "shower"]:
		if alignment < -0.1:
			return
		var query := PhysicsRayQueryParameters3D.create(eye, at, 1)
		query.exclude = [shooter.player.get_rid()]
		var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.position.distance_to(at) > 0.65:
			return
	out.append({"kind": kind, "id": id, "text": text, "score": priority + distance * 0.15 + (1.0 - alignment)})

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
	var events := InputMap.action_get_events("interact")
	var key := events[0].as_text() if not events.is_empty() else "E"
	return "[%s] %s" % [key.replace(" (Physical)", ""), target.text]
