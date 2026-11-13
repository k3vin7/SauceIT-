extends MayoEnemy

const MODEL := "res://assets/enemies/Stage2_PressKing/Stage2_PressKing.glb"
const CLIPS := [&"Rise", &"Idle", &"Walk", &"Slam", &"ArmorBreak", &"Collapse", &"Lob", &"Idle", &"Walk", &"Idle"]
enum Act { RISE, IDLE, WALK, SLAM, STAGGER, DEATH, LOB, CHARGE_WINDUP, CHARGE, CHARGE_RECOVER }

const SLAM_IMPACT := 38.0 / 30.0
const SLAM_LENGTH := 69.0 / 30.0
const WAVE_TIME := 0.88
const LOB_RELEASE := 29.0 / 30.0
const LOB_LENGTH := 57.0 / 30.0
const LOB_FLIGHT := 1.18
const LOB_GRAVITY := 18.0
const LOB_RADIUS := 2.6
const CHARGE_WINDUP_SECONDS := 0.8
const CHARGE_SECONDS := 0.85
const CHARGE_RECOVERY := 1.1
const CHARGE_COOLDOWN := 7.0
const CHASE_SPEED_FRACTION := 1.65
const CHARGE_BASE_SPEED_FRACTION := 0.75
const SLAM_DAMAGE := 30.0
const ENRAGED_SLAM_DAMAGE := 40.0
const CHARGE_DAMAGE := 35.0
const ENRAGED_CHARGE_DAMAGE := 45.0
const LOB_DIRECT_DAMAGE := 26.0
const LOB_SPLASH_DAMAGE := 18.0
var charge_speed := 25.74
var _boss_charge_direction := Vector3.FORWARD
var _boss_charge_cooldown := 0.0
const EXPOSED_DAMAGE_SCALE := 0.55
const WEAK_SPOT_MULTIPLIER := 1.15
const OPEN_SECONDS := 7.0
const WASH_SECONDS := 0.75
const ARENA_MARGIN := 16.0
var exposure_seconds := OPEN_SECONDS
const ARMOR_BREAK_FRACTION := 0.5

var arena := Rect2()
var act := Act.RISE
var act_time := 0.0
var armor_broken := false
var exposed_left := 0.0
var _wash := 0.0
var _cooldown := 1.7
var _shown_act := -1
var _wave_hits := {}
var _lob_at := Vector3.ZERO
var _rig_player: AnimationPlayer
var _armor: MeshInstance3D
var _weak_spot: MeshInstance3D
var _wave: MeshInstance3D
var _wave_material: StandardMaterial3D
var _death_root: Node3D
var _death_chunks: Array[MeshInstance3D] = []
var _death_rest := Transform3D.IDENTITY
var _death_clock := 0.0
var _death_landed := false
var _splinters: CPUParticles3D


static func make_visual() -> Node3D:
	var asset := load(MODEL) as PackedScene
	if asset == null:
		return null
	var visual := asset.instantiate() as Node3D
	visual.rotation.y = PI
	EnemyInk.apply(visual)
	return visual


static func rig_player(visual: Node3D) -> AnimationPlayer:
	var players := visual.find_children("*", "AnimationPlayer", true, false)
	return players.front() as AnimationPlayer if not players.is_empty() else null


func build_press_king(cell_size: float, brush_radius: float) -> void:
	kind = EnemyKind.PRESS_KING
	grade = Grade.HEAVY
	radius = 1.82
	height = 5.75
	solo_health = 840.0
	max_health = solo_health
	health = max_health
	sauce_damage_per_hit = 1.1
	move_speed = 8.58
	turn_speed = 2.6
	shove_speed = 0.0
	flinch_thresholds = []
	# Capsule is smaller than the cargo and fists so the boss can be circled.
	var collider := CollisionShape3D.new()
	collider.name = "Body"
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = height
	collider.shape = capsule
	add_child(collider)
	var mask := CapsuleMesh.new()
	mask.radius = radius
	mask.height = height
	var visual := make_visual()
	assert(visual != null, "Press King GLB is required for Tomatina")
	visual.position.y = -stand_height()
	_finish_primitive_body(cell_size, brush_radius, mask, visual, Color("ba3123"))
	_rig_player = rig_player(visual)
	assert(_rig_player != null, "Press King rig did not import")
	# The old Collapse scales the torso down to 51%; retain its joint motion,
	# but preserve the model's volume and bone lengths throughout the death.
	var collapse := _rig_player.get_animation(&"Collapse").duplicate() as Animation
	for track in range(collapse.get_track_count()-1,-1,-1):
		if collapse.track_get_type(track) == Animation.TYPE_SCALE_3D:
			collapse.remove_track(track)
	var library := _rig_player.get_animation_library(&"").duplicate() as AnimationLibrary
	library.remove_animation(&"Collapse")
	library.add_animation(&"Collapse",collapse)
	_rig_player.remove_animation_library(&"")
	_rig_player.add_animation_library(&"",library)
	_armor = visual.find_child("Armor", true, false) as MeshInstance3D
	_weak_spot = visual.find_child("WeakSpot", true, false) as MeshInstance3D
	for loop in [&"Idle", &"Walk"]:
		_rig_player.get_animation(loop).loop_mode = Animation.LOOP_LINEAR
	_build_wave()
	_build_splinters()
	_build_death_burst()
	_death_rest = _visual_root.transform
	_update_presentation()


func _build_wave() -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = 0.92
	ring.outer_radius = 1.0
	ring.rings = 40
	ring.ring_segments = 6
	_wave_material = StandardMaterial3D.new()
	_wave_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_wave_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_wave = MeshInstance3D.new()
	_wave.mesh = ring
	_wave.material_override = _wave_material
	_wave.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wave.position.y = -stand_height() + 0.08
	add_child(_wave)


func _build_splinters() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("94613a")
	wood.roughness = 1.0
	var chunk := BoxMesh.new()
	chunk.size = Vector3(0.34, 0.15, 0.12)
	chunk.material = wood
	_splinters = CPUParticles3D.new()
	_splinters.emitting = false
	_splinters.one_shot = true
	_splinters.explosiveness = 1.0
	_splinters.amount = 18
	_splinters.lifetime = 0.86
	_splinters.mesh = chunk
	_splinters.direction = Vector3.UP
	_splinters.spread = 145.0
	_splinters.initial_velocity_min = 3.0
	_splinters.initial_velocity_max = 6.0
	_splinters.angular_velocity_min = -270.0
	_splinters.angular_velocity_max = 360.0
	_splinters.position = Vector3(0.0, -0.4, -1.1)
	add_child(_splinters)


func _set_act(next: Act) -> void:
	if act == next:
		return
	act = next
	act_time = 0.0


func _update_presentation() -> void:
	if _rig_player == null:
		return
	if _shown_act != act:
		_shown_act = act
		var clip: StringName = CLIPS[act]
		_rig_player.speed_scale = 2.2 if act == Act.CHARGE else 1.0
		_rig_player.play(clip, 0.09)
		_rig_player.seek(minf(act_time, _rig_player.get_animation(clip).length), true)
		if act == Act.DEATH:
			_death_clock = act_time
			_death_landed = act_time >= 0.95
			_death_root.show()
			if act_time < 0.4:
				_splinters.restart()
		if act == Act.STAGGER and act_time < 0.4:
			_splinters.restart()
	if _armor != null:
		_armor.visible = not armor_broken and exposed_left <= 0.0
	if _weak_spot != null:
		_weak_spot.visible = armor_broken or exposed_left > 0.0
	var wave_t := (act_time - SLAM_IMPACT) / WAVE_TIME
	_wave.visible = act == Act.SLAM and wave_t < 1.0
	if _wave.visible:
		var spreading := wave_t >= 0.0
		var width := _wave_range()
		if spreading:
			width = lerpf(1.8, width, clampf(wave_t, 0.0, 1.0))
		_wave.scale = Vector3(width, 0.7, width)
		_wave_material.albedo_color = (Color(0.92, 0.85, 1.0, 0.85 - wave_t * 0.52)
			if spreading else Color(0.71, 0.47, 1.0, 0.40 + 0.17 * sin(act_time * 18.0)))


func _process(delta: float) -> void:
	super._process(delta)
	if act == Act.DEATH:
		_death_clock = maxf(act_time, _death_clock + delta)
		_update_death_burst(_death_clock)
	if not authority:
		act_time += delta
		exposed_left = maxf(exposed_left - delta, 0.0)
		_update_presentation()


func wash_armor(delta: float) -> void:
	if not is_alive() or act == Act.RISE or armor_broken:
		return
	if exposed_left > 0.0:
		return
	_wash += delta
	if _wash >= WASH_SECONDS:
		_wash = 0.0
		exposed_left = exposure_seconds
		_set_act(Act.STAGGER)


func wash_progress() -> float:
	return clampf(_wash / WASH_SECONDS, 0.0, 1.0)


func apply_wash_progress(fraction: float) -> void:
	_wash = clampf(fraction, 0.0, 1.0) * WASH_SECONDS


func take_sauce_hit(_from := Vector3.INF, damage := -1.0) -> bool:
	return _take_sauce_damage(damage if damage >= 0.0 else sauce_damage_per_hit)


func is_weak_spot_hit(hit_position: Vector3) -> bool:
	var at := to_local(hit_position)
	return (armor_broken or exposed_left > 0.0) and at.z < -0.65 and absf(at.x) < 1.1 and absf(at.y + 0.68) < 1.05


func take_aimed_sauce_hit(hit_position: Vector3, damage := -1.0) -> bool:
	var multiplier := WEAK_SPOT_MULTIPLIER if is_weak_spot_hit(hit_position) else 1.0
	return _take_sauce_damage((sauce_damage_per_hit if damage < 0.0 else damage) * multiplier)


func _take_sauce_damage(damage: float) -> bool:
	if not is_alive() or act == Act.RISE:
		return false
	var exposed := armor_broken or exposed_left > 0.0
	health = maxf(health - damage * (EXPOSED_DAMAGE_SCALE if exposed else 0.16), 0.0)
	if not is_alive():
		collision_layer = 0
		collision_mask = 0
		_set_act(Act.DEATH)
		_update_presentation()
		return true
	if not armor_broken and health_fraction() <= ARMOR_BREAK_FRACTION:
		armor_broken = true
		_set_act(Act.STAGGER)
	return false


func _wave_range() -> float:
	return 13.0 if armor_broken else 10.5


func _slam(targets: Array, old_time: float) -> void:
	if old_time < SLAM_IMPACT and act_time >= SLAM_IMPACT:
		_burst_request = global_position
	var progress := (act_time - SLAM_IMPACT) / WAVE_TIME
	if progress < 0.0 or old_time > SLAM_IMPACT + WAVE_TIME:
		return
	var outer := lerpf(1.8, _wave_range(), clampf(progress, 0.0, 1.0))
	var inner := lerpf(1.8, _wave_range(), clampf((old_time - SLAM_IMPACT) / WAVE_TIME, 0.0, 1.0))
	for target: MayoPlayer in targets:
		if target.state == MayoPlayer.State.DEAD or _wave_hits.has(target.peer_id):
			continue
		if not arena.grow(ARENA_MARGIN).has_point(Vector2(target.global_position.x, target.global_position.z)):
			continue
		var gap := target.global_position - global_position
		gap.y = 0.0
		var distance := gap.length()
		if distance <= outer + 0.65 and (old_time < SLAM_IMPACT or distance >= inner - 0.65):
			_wave_hits[target.peer_id] = true
			if target.global_position.y > MayoPlayer.CAPSULE_HEIGHT * 0.5 + 0.55:
				continue
			var direction := gap.normalized() if distance > 0.1 else Vector3.FORWARD
			target.apply_enemy_impact(direction, 8.5, 2.4)
			if target.can_slip():
				target.begin_slip()
			slam_hit.emit(target, ENRAGED_SLAM_DAMAGE if armor_broken else SLAM_DAMAGE)


signal slam_hit(player: MayoPlayer, damage: float)
signal lob_warning(at: Vector3, duration: float)
signal lob_release(origin: Vector3, velocity: Vector3, seconds: float)


func advance(delta: float, targets: Array, _target_load: Dictionary = {}) -> MayoPlayer:
	if not authority:
		return null
	var old_time := act_time
	act_time += delta
	exposed_left = maxf(exposed_left - delta, 0.0)
	_wash = maxf(_wash - delta * 0.16, 0.0)
	_cooldown = maxf(_cooldown - delta, 0.0)
	_boss_charge_cooldown = maxf(_boss_charge_cooldown - delta, 0.0)
	match act:
		Act.RISE:
			if act_time >= 2.2:
				_set_act(Act.IDLE)
		Act.STAGGER:
			if act_time >= 1.3:
				_cooldown = maxf(_cooldown, 0.8)
				_set_act(Act.IDLE)
		Act.CHARGE_WINDUP:
			if act_time >= CHARGE_WINDUP_SECONDS:
				_set_act(Act.CHARGE)
		Act.CHARGE:
			_advance_boss_charge(delta, targets)
		Act.CHARGE_RECOVER:
			if act_time >= CHARGE_RECOVERY:
				_set_act(Act.IDLE)
		Act.SLAM:
			_slam(targets, old_time)
			if act_time >= SLAM_LENGTH:
				_set_act(Act.IDLE)
		Act.LOB:
			if old_time < LOB_RELEASE and act_time >= LOB_RELEASE:
				var origin := global_position - basis.z * 2.3 + basis.x * 0.85 + Vector3.UP * 1.05
				var velocity := (_lob_at - origin) / LOB_FLIGHT + Vector3.UP * LOB_GRAVITY * LOB_FLIGHT * 0.5
				lob_release.emit(origin, velocity, LOB_FLIGHT + 0.15)
			if act_time >= LOB_LENGTH:
				_set_act(Act.IDLE)
		Act.IDLE, Act.WALK:
			_chase(delta, targets)
	_update_presentation()
	return null


func _chase(delta: float, targets: Array) -> void:
	var target: MayoPlayer
	var nearest := INF
	for player: MayoPlayer in targets:
		var at := player.global_position
		if player.state == MayoPlayer.State.DEAD or not arena.grow(ARENA_MARGIN).has_point(Vector2(at.x, at.z)):
			continue
		var distance := global_position.distance_squared_to(at)
		if distance < nearest:
			nearest = distance
			target = player
	if target == null:
		_set_act(Act.IDLE)
		return
	var aim := Vector2(target.global_position.x, target.global_position.z)
	var gap := Vector3(aim.x - global_position.x, 0.0, aim.y - global_position.z)
	if gap.length_squared() > 0.01:
		facing_yaw = rotate_toward(facing_yaw, atan2(-gap.x, -gap.z), turn_speed * delta)
		rotation.y = facing_yaw
	var distance := gap.length()
	if distance >= 6.0 and distance <= 30.0 and _cooldown <= 0.0 and _boss_charge_cooldown <= 0.0:
		_boss_charge_direction = gap.normalized()
		facing_yaw = atan2(-gap.x, -gap.z)
		rotation.y = facing_yaw
		_wave_hits.clear()
		_boss_charge_cooldown = CHARGE_COOLDOWN
		_cooldown = CHARGE_WINDUP_SECONDS + CHARGE_SECONDS + CHARGE_RECOVERY + 0.8
		_set_act(Act.CHARGE_WINDUP)
		special_warning.emit(self, _boss_charge_direction, CHARGE_WINDUP_SECONDS)
		return
	if distance <= _wave_range() - 1.1 and _cooldown <= 0.0:
		_wave_hits.clear()
		_cooldown = 3.3 if armor_broken else 4.65
		_set_act(Act.SLAM)
		special_warning.emit(self, Vector3.ZERO, SLAM_IMPACT)
		return
	if distance >= 12.0 and distance <= 34.0 and _cooldown <= 0.0:
		facing_yaw = atan2(-gap.x, -gap.z)
		rotation.y = facing_yaw
		_lob_at = Vector3(aim.x, 0.04, aim.y)
		_cooldown = 3.8 if armor_broken else 4.8
		_set_act(Act.LOB)
		lob_warning.emit(_lob_at, LOB_RELEASE + LOB_FLIGHT)
		return
	if distance < 3.0:
		_set_act(Act.IDLE)
		return
	var inset := arena.grow(-radius)
	var chase_at := aim.clamp(inset.position, inset.end)
	var point := Vector3(chase_at.x, global_position.y, chase_at.y)
	var step := _step_toward(point, delta) - global_position
	step.y = 0.0
	var pace := move_speed
	velocity = step.normalized() * pace + Vector3.DOWN * 0.8
	move_and_slide()
	_set_act(Act.WALK if get_real_velocity().length_squared() > 0.1 else Act.IDLE)


## The boss replaces the unused topple angle with its action, phase and timer
## within the existing enemy packet. Quantized hundredths survive float32.
func network_state() -> Array:
	var flags := int(act) + (10 if armor_broken else 0)
	var packed := (flags * 100000 + mini(999, roundi(act_time * 100.0)) * 100
		+ clampi(ceili(exposed_left * 8.0), 0, 99))
	return [global_position, facing_yaw, health, packed, max_health]


func apply_network_state(new_position: Vector3, yaw: float, new_health: float,
		packed_pose: float, new_max_health := 0.0, interpolate := false) -> void:
	super.apply_network_state(new_position, yaw, new_health, 0.0, new_max_health, interpolate)
	var packed := int(packed_pose)
	var flags := packed / 100000
	act = (flags % 10) as Act
	armor_broken = flags >= 10
	act_time = float((packed % 100000) / 100) * 0.01
	exposed_left = float(packed % 100) / 8.0
	_update_presentation()


func configure_combat_speed(player_walk_speed: float, rusher_fraction: float) -> void:
	move_speed = player_walk_speed * rusher_fraction
	charge_speed = player_walk_speed * CHARGE_BASE_SPEED_FRACTION * MayoEnemy.BRUTE_CHARGE_SPEED_SCALE

func _advance_boss_charge(delta: float, targets: Array) -> void:
	var before := global_position
	var inset := arena.grow(-radius)
	var wanted := before + _boss_charge_direction * charge_speed * delta
	var boundary := not inset.has_point(Vector2(wanted.x, wanted.z))
	velocity = _boss_charge_direction * charge_speed + Vector3.DOWN * 0.8
	move_and_slide()
	var after := global_position
	# Sweep the whole travelled segment so fast charges cannot skip a player.
	for target: MayoPlayer in targets:
		if target.state == MayoPlayer.State.DEAD or _wave_hits.has(target.peer_id):
			continue
		var flat_target := Vector3(target.global_position.x, before.y, target.global_position.z)
		var closest := Geometry3D.get_closest_point_to_segment(flat_target, before, Vector3(after.x, before.y, after.z))
		if closest.distance_to(flat_target) > radius + MayoPlayer.CAPSULE_RADIUS:
			continue
		if absf(target.global_position.y - global_position.y) > height * 0.5 + 0.5:
			continue
		if nav != null and not nav.line_is_walkable(global_position, target.global_position):
			continue
		_wave_hits[target.peer_id] = true
		target.apply_charge_impact(_boss_charge_direction, MayoEnemy.BRUTE_CHARGE_PUSH_SPEED, MayoEnemy.BRUTE_CHARGE_LIFT_SPEED)
		slam_hit.emit(target, ENRAGED_CHARGE_DAMAGE if armor_broken else CHARGE_DAMAGE)
	var flat_move := Vector2(after.x - before.x, after.z - before.z).length()
	if boundary or flat_move < charge_speed * delta * 0.35 or act_time >= CHARGE_SECONDS:
		if boundary:
			var safe := Vector2(after.x, after.z).clamp(inset.position, inset.end)
			global_position.x = safe.x
			global_position.z = safe.y
		velocity = Vector3.ZERO
		_set_act(Act.CHARGE_RECOVER)


func _build_death_burst() -> void:
	_death_root = Node3D.new()
	_death_root.name = "BossDeathBurst"
	_death_root.hide()
	add_child(_death_root)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("b9864d")
	wood.roughness = 0.95
	var sauce := StandardMaterial3D.new()
	sauce.albedo_color = Color("df4329")
	sauce.roughness = 0.65
	for i in 8:
		var chunk := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.22 + (i % 3) * 0.11, 0.15, 0.45 + (i % 4) * 0.13)
		chunk.mesh = box
		chunk.material_override = wood if i % 3 != 0 else sauce
		chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_death_root.add_child(chunk)
		_death_chunks.append(chunk)

func _update_death_burst(time: float) -> void:
	var t := clampf(time, 0.0, 2.2)
	# One authored collapse, with no second hop, spin or squash layered on top.
	_visual_root.transform = _death_rest
	# Sample the existing rigged collapse against the same replicated death clock.
	_rig_player.pause()
	_rig_player.seek(clampf(t, 0.0, _rig_player.get_animation(&"Collapse").length), true)
	if t >= 0.95 and not _death_landed:
		_death_landed = true
		_splinters.position = Vector3(0.0, -stand_height() + 0.2, 0.8)
		_splinters.restart()
	if _armor != null:
		_armor.hide()
	var burst_time := maxf(t - 0.12, 0.0)
	for i in _death_chunks.size():
		var angle := i * 2.399963
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var speed := 1.2 + float(i % 5) * 0.2
		var start := direction * 0.9 + Vector3.UP * (0.1 + (i % 4) * 0.38)
		var point := start + direction * speed * burst_time + Vector3.UP * (2.0 * burst_time - 8.5 * burst_time * burst_time)
		point.y = maxf(point.y, -stand_height() + 0.12)
		_death_chunks[i].position = point
		_death_chunks[i].rotation = Vector3(angle, angle * 0.7, angle * 0.3) * burst_time * 3.0
		_death_chunks[i].scale = Vector3.ONE * (1.0 - clampf((t - 1.25) / 0.6, 0.0, 1.0))
	var impact := (t - 0.95) / 0.6
	_wave.visible = impact >= 0.0 and impact <= 1.0
	if _wave.visible:
		_wave.scale = Vector3.ONE * lerpf(1.0, 3.5, impact)
		_wave.scale.y = 0.3
		_wave_material.albedo_color = Color(0.86, 0.65, 0.39, (1.0 - impact) * 0.3)
