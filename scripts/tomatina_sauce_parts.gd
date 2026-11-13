extends Node3D

enum Part { STANDARD, FAN, FOCUS, BURST, ARC, CANNON }

const CATALOG := [
	["기본 노즐", "기본 연속 분사", 0, 0],
	["부채꼴 노즐", "정면 부채꼴로 다섯 갈래 짧은 소스 줄기 · 가까울수록 강함", 0, 5],
	["집중 노즐", "가늘고 멀리 뻗는 연속 분사", 0, 5],
	["점사 밸브", "한 번 누를 때 짧게 세 발 분사", 1, 5],
	["곡사 캡", "조준한 곳에 포물선으로 떨어져 터지는 소스 덩어리", 1, 6],
	["대포형 소스통", "직선으로 날아가 크게 폭발 · 한 발에 탱크 25%", 1, 7],
]
const PROJECTILES := {
	Part.FAN: {"speed": 22.0, "gravity": 0.0, "life": 0.19, "size": 0.09, "damage": 1.7, "blast": 0.0,
		"cost": 0.010, "cooldown": 0.14},
	Part.BURST: {"speed": 32.0, "gravity": 0.0, "life": 0.29, "size": 0.14, "damage": 9.5, "blast": 0.0,
		"cost": 0.040, "cooldown": 0.48},
	Part.ARC: {"speed": 13.0, "gravity": 15.0, "life": 2.3, "size": 0.36, "damage": 22.0, "blast": 1.8,
		"cost": 0.045, "cooldown": 0.72},
	Part.CANNON: {"speed": 34.0, "gravity": 0.0, "life": 0.60, "size": 0.32, "damage": 120.0, "blast": 2.7,
		"cost": 0.25, "cooldown": 3.6},
}
## Tuned against the plain stream on a 0.4-per-point body: about 35 damage a
## second held, about 700 a tank. `damage` is for that body; `scaled_damage`
## carries it to softer ones, the way the stream's own per-point damage does.
const REFERENCE_HIT_DAMAGE := 0.4
## What a blast deals to everything but the body it landed on.
const BLAST_DAMAGE_SHARE := 0.5


static func scaled_damage(base: float, enemy: MayoEnemy) -> float:
	return base * enemy.sauce_damage_per_hit / REFERENCE_HIT_DAMAGE
const COIN_PICKUP_RADIUS := 1.45
const GRUNT_DROP_CHANCE := 0.15
const SPECIAL_DROP_CHANCE := 0.50
const TIP_COLORS := [Color.WHITE, Color("6bb9ac"), Color("78a3cf"),
	Color("c589d9"), Color("dfab60"), Color("b85e41")]

var world: Node3D
var dirty := false
var _rng := RandomNumberGenerator.new()
var _rolled_deaths := {}
var _coins := {}
var _coin_serial := 0
var _projectiles: Array[Dictionary] = []
var _coin_mesh: CylinderMesh
var _sauce_mesh := SphereMesh.new()
## The fan's five are drawn as streams, not lumps: each shot drags a tapered
## streak behind it as long as the gap to the shot after it, so a held trigger
## reads as five short unbroken streams. One unit tall along +Y, head at the top.
var _streak_mesh := CylinderMesh.new()
var _sauce_materials: Array[StandardMaterial3D] = []


static func build_tip(part: int, mount: Node3D, at: Vector3) -> Node3D:
	var tip := Node3D.new()
	tip.name = "EquippedSaucePart"
	mount.add_child(tip)
	tip.position = at
	var body := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = TIP_COLORS[part]
	material.roughness = 0.62
	body.material_override = material
	if part == Part.FAN:
		var head := BoxMesh.new()
		head.size = Vector3(0.23, 0.075, 0.18)
		body.mesh = head
	else:
		var barrel := CylinderMesh.new()
		barrel.radial_segments = 10
		barrel.height = 0.23 if part != Part.CANNON else 0.41
		barrel.bottom_radius = 0.085 if part != Part.CANNON else 0.16
		barrel.top_radius = 0.04 if part == Part.FOCUS else barrel.bottom_radius * 0.87
		body.mesh = barrel
		body.rotation.x = -PI * 0.5 + (0.32 if part == Part.ARC else 0.0)
	tip.add_child(body)
	if part == Part.BURST or part == Part.CANNON:
		var ring := MeshInstance3D.new()
		var collar := CylinderMesh.new()
		collar.radial_segments = 10
		collar.height = 0.065
		collar.top_radius = 0.098 if part == Part.BURST else 0.173
		collar.bottom_radius = collar.top_radius
		ring.mesh = collar
		var dark := StandardMaterial3D.new()
		dark.albedo_color = Color("363d49")
		ring.material_override = dark
		ring.rotation.x = -PI * 0.5
		ring.position.z = -0.08 if part == Part.BURST else -0.16
		tip.add_child(ring)
	return tip


func _ready() -> void:
	_rng.randomize()
	_coin_mesh = CylinderMesh.new()
	_coin_mesh.top_radius = 0.21
	_coin_mesh.bottom_radius = 0.21
	_coin_mesh.height = 0.085
	_coin_mesh.radial_segments = 12
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color("ffca49")
	gold.emission_enabled = true
	gold.emission = Color("b7761e")
	gold.emission_energy_multiplier = 0.38
	_coin_mesh.material = gold
	_sauce_mesh.radial_segments = 10
	_sauce_mesh.rings = 5
	_streak_mesh.height = 1.0
	_streak_mesh.top_radius = 0.5
	_streak_mesh.bottom_radius = 0.32
	_streak_mesh.radial_segments = 8
	_streak_mesh.rings = 1
	for color: Color in world.SAUCE_TINTS:
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		_sauce_materials.append(material)


func drop_for(enemy: MayoEnemy) -> void:
	var id := enemy.get_instance_id()
	if _rolled_deaths.has(id) or enemy.is_alive() or enemy.kind == MayoEnemy.EnemyKind.TOMATO_BALL:
		return
	_rolled_deaths[id] = true
	var chance := GRUNT_DROP_CHANCE if enemy.kind == MayoEnemy.EnemyKind.TOMATO_GRUNT else SPECIAL_DROP_CHANCE
	if _rng.randf() >= chance:
		return
	var at := enemy.global_position
	var ground: Dictionary = world._tomatina_static_hit(at + Vector3.UP, at - Vector3.UP * 30.0)
	if not ground.is_empty():
		at = ground.position
	_coin_serial += 1
	_place_coin(_coin_serial, at + Vector3.UP * 0.37)
	dirty = true


func _place_coin(id: int, at: Vector3) -> void:
	var coin := MeshInstance3D.new()
	coin.name = "SauceCoin%d" % id
	coin.mesh = _coin_mesh
	coin.rotation.x = PI * 0.5
	coin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(coin)
	coin.global_position = at
	_coins[id] = coin


func advance_coins(delta: float, authority: bool) -> void:
	for id in _coins.keys():
		var coin: MeshInstance3D = _coins[id]
		coin.rotation.y += delta * 2.5
		if not authority:
			continue
		for shooter in world._shooters.values():
			var player: MayoPlayer = shooter.player
			var offset := player.global_position - coin.global_position
			if player.state != MayoPlayer.State.NORMAL or absf(offset.y) > 1.9 \
					or Vector2(offset.x, offset.z).length_squared() > COIN_PICKUP_RADIUS ** 2:
				continue
			for teammate in world._shooters.values():
				teammate.coins += 1
			_remove_coin(id)
			dirty = true
			world._refresh_refuge_shop()
			break


func _remove_coin(id: int) -> void:
	_coins[id].queue_free()
	_coins.erase(id)


func coin_state() -> PackedFloat32Array:
	var data := PackedFloat32Array()
	for id in _coins:
		var at: Vector3 = _coins[id].global_position
		data.append_array(PackedFloat32Array([id, at.x, at.y, at.z]))
	return data


func apply_coin_state(data: PackedFloat32Array) -> void:
	var present := {}
	for i in range(0, data.size() - 3, 4):
		var id := int(data[i])
		present[id] = true
		if not _coins.has(id):
			_place_coin(id, Vector3(data[i + 1], data[i + 2], data[i + 3]))
	for id in _coins.keys():
		if not present.has(id):
			_remove_coin(id)


func reset() -> void:
	for id in _coins.keys():
		_remove_coin(id)
	for shot in _projectiles:
		shot.node.queue_free()
	_projectiles.clear()
	_rolled_deaths.clear()
	dirty = true


func show_volley(peer: int, part: int, sauce: int, origin: Vector3, forward: Vector3) -> void:
	var profile: Dictionary = PROJECTILES[part]
	var angles := [-18.0, -9.0, 0.0, 9.0, 18.0] if part == Part.FAN else [0.0]
	for angle: float in angles:
		var direction := forward.rotated(Vector3.UP, deg_to_rad(angle))
		var glob := MeshInstance3D.new()
		glob.mesh = _streak_mesh if part == Part.FAN else _sauce_mesh
		glob.material_override = _sauce_materials[sauce]
		glob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glob.scale = Vector3.ONE * (2.0 * float(profile.size))
		add_child(glob)
		glob.global_position = origin
		var shot := {"node": glob, "peer": peer, "part": part, "sauce": sauce,
			"velocity": direction * float(profile.speed), "left": profile.life}
		if part == Part.FAN:
			# Where the shot really is travels apart from the node, which is
			# now the streak behind it. See `_draw_streak`.
			shot["head"] = origin
			shot["origin"] = origin
			shot["trail"] = float(profile.speed) * float(profile.cooldown)
			_draw_streak(shot, profile)
		_projectiles.append(shot)


## Lays a fan shot's streak from its head back towards the nozzle, no longer
## than the distance the shot after it has yet to cover.
func _draw_streak(shot: Dictionary, profile: Dictionary) -> void:
	var node: MeshInstance3D = shot.node
	var head: Vector3 = shot.head
	var velocity: Vector3 = shot.velocity
	if velocity.length_squared() < 0.000001:
		return
	var along := velocity.normalized()
	var length := clampf(head.distance_to(shot.origin), 0.02, float(shot.trail))
	var width := float(profile.size) * 1.5
	var basis := Basis(Quaternion(Vector3.UP, along)).scaled_local(Vector3(width, length, width))
	node.global_transform = Transform3D(basis, head - along * length * 0.5)


func advance_projectiles(delta: float, authority: bool) -> void:
	for i in range(_projectiles.size() - 1, -1, -1):
		var shot: Dictionary = _projectiles[i]
		var profile: Dictionary = PROJECTILES[shot.part]
		var node: MeshInstance3D = shot.node
		var from: Vector3 = shot.get("head", node.global_position)
		shot.velocity += Vector3.DOWN * float(profile.gravity) * delta
		var to: Vector3 = from + shot.velocity * delta
		var query := PhysicsRayQueryParameters3D.create(from, to)
		var shooter = world.shooter_for(shot.peer)
		if shooter != null:
			query.exclude = [shooter.player.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		shot.left -= delta
		if authority:
			world._cut_cheese_by_stream(from, to if hit.is_empty() else hit.position)
		if not hit.is_empty():
			world._part_projectile_impact(hit, shot, profile, shooter, authority)
		elif shot.left > 0.0:
			if shot.has("head"):
				shot.head = to
				_draw_streak(shot, profile)
			else:
				node.global_position = to
			continue
		node.queue_free()
		_projectiles.remove_at(i)
