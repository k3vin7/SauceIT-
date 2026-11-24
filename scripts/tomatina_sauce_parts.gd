extends Node3D

enum Part { STANDARD, FAN, FOCUS, BURST, ARC, CANNON }

## 번호는 `Part`와 같다. 이름만 바뀐 것: FAN은 이제 3갈래 노즐, ARC는 박격포 캡이다.
const CATALOG := [
	["기본 노즐", "기본 연속 분사", 0, 0],
	["3갈래 노즐", "기본 줄기 세 가닥 · 가닥마다 조금 가늘고 약함 · 소스 두 배 소모", 0, 5],
	["집중 노즐", "가늘고 멀리 뻗는 연속 분사", 0, 5],
	["점사 밸브", "한 번 누를 때 짧게 세 발 분사", 1, 5],
	["박격포 캡", "높이 쏘아 올려 떨어지며 터지는 소스 덩어리 · 흔들수록 멀리, 세게 · 아군도 맞음", 1, 6],
	["대포형 소스통", "낮고 빠르게 날아가 터짐 · 한 발에 탱크 25%", 1, 7],
]
## 덩어리를 쏘는 파츠. 전부 중력 `GRAVITY`를 받고 무언가에 닿을 때까지 난다 -- `life`는
## 허공으로 날아간 것을 치우는 상한일 뿐이다. `reach`는 조준점을 어디까지 찾는가(m).
## `blast`는 폭발 반경, `blast_damage`는 직접 맞지 않은 대상이 받는 피해(없으면 직격의 절반).
const GRAVITY := 9.8
const PROJECTILES := {
	Part.BURST: {"speed": 32.0, "gravity": GRAVITY, "life": 6.0, "reach": 20.0, "size": 0.14,
		"damage": 9.5, "blast": 0.0, "cost": 0.040, "cooldown": 0.48},
	Part.ARC: {"speed": 17.0, "gravity": GRAVITY, "life": 10.0, "reach": 30.0, "size": 0.36,
		"damage": 85.0, "blast": 3.6, "cost": 0.15, "cooldown": 1.5},
	Part.CANNON: {"speed": 28.0, "gravity": GRAVITY, "life": 6.0, "reach": 30.0, "size": 0.32,
		"damage": 100.0, "blast": 1.8, "blast_damage": 42.0, "cost": 0.25, "cooldown": 2.5},
}
## 3갈래 노즐: 기본 줄기와 똑같은 줄기 세 가닥이 이 각도씩 벌어져 나간다. 가닥마다 굵기와
## 피해가 `THREE_WAY_SCALE`배이고, 소스는 기본의 `THREE_WAY_FLOW`배로 나간다.
const THREE_WAY_ANGLE := deg_to_rad(15.0)
const THREE_WAY_SCALE := 0.8
const THREE_WAY_FLOW := 2.0
## 박격포 캡: 시점을 따라 지면에서 45°~90°로만 쏜다. 흔들어 채운 만큼 멀리(약 5m~30m),
## 세게(피해 `MORTAR_MIN_DAMAGE`~`PROJECTILES[ARC].damage`) 나간다. 폭발은 던진 토마토의
## `MORTAR_RADIUS_SHARE`배 반경이고 아군도 맞는다. 흔들기 게이지는 이 파츠를 낀 동안
## `MORTAR_CHARGE_HOLD`초 동안 빠지지 않는다.
const MORTAR_MIN_ELEVATION := deg_to_rad(45.0)
const MORTAR_MIN_SPEED := 6.3
const MORTAR_MIN_DAMAGE := 45.0
const MORTAR_RADIUS_SHARE := 0.8
const MORTAR_CHARGE_HOLD := 5.0


## 박격포가 `speed`(m/s)로 나갔을 때 얼마나 채워 쏜 것인가, 0~1.
static func mortar_charge(speed: float) -> float:
	return clampf(inverse_lerp(MORTAR_MIN_SPEED, float(PROJECTILES[Part.ARC].speed), speed), 0.0, 1.0)


static func mortar_damage(charge: float) -> float:
	return lerpf(MORTAR_MIN_DAMAGE, float(PROJECTILES[Part.ARC].damage), clampf(charge, 0.0, 1.0))
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
var _sauce_materials: Array[StandardMaterial3D] = []

## How long a shot is drawn bending from where it visibly left (the part on the
## character's bottle) onto the line it really flies, as the stream does with
## `MUZZLE_DRAW_BLEND`.
const DRAW_BLEND := 0.22


## How far the fitted part reaches past the bottle's muzzle -- the front of the
## mesh `build_tip` centres on it -- so a shot leaves from the part's mouth.
static func tip_reach(part: int) -> float:
	match part:
		Part.STANDARD:
			return 0.0
		Part.FAN:
			return 0.09
		Part.CANNON:
			return 0.205
		_:
			return 0.115


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


## Authority only: a coin lying at `at`, on the ground -- what a searched body
## drops. Picked up and sent like any other.
func drop_coin(at: Vector3) -> void:
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


## The coins lying about, four floats each. The searched bodies ride along as
## entries with a negative id (-1 - body), so a body searched on the host stops
## offering itself on every screen without a message of its own.
func coin_state() -> PackedFloat32Array:
	var data := PackedFloat32Array()
	for id in _coins:
		var at: Vector3 = _coins[id].global_position
		data.append_array(PackedFloat32Array([id, at.x, at.y, at.z]))
	var victims = world.get("_victims")
	if victims != null:
		for index in victims.looted_indices():
			data.append_array(PackedFloat32Array([-1 - int(index), 0.0, 0.0, 0.0]))
	return data


func apply_coin_state(data: PackedFloat32Array) -> void:
	var present := {}
	var looted := []
	for i in range(0, data.size() - 3, 4):
		var id := int(data[i])
		if id < 0:
			looted.push_back(-1 - id)
			continue
		present[id] = true
		if not _coins.has(id):
			_place_coin(id, Vector3(data[i + 1], data[i + 2], data[i + 3]))
	for id in _coins.keys():
		if not present.has(id):
			_remove_coin(id)
	var victims = world.get("_victims")
	if victims != null:
		victims.set_looted(looted)


func reset() -> void:
	for id in _coins.keys():
		_remove_coin(id)
	for shot in _projectiles:
		shot.node.queue_free()
	_projectiles.clear()
	_rolled_deaths.clear()
	var victims = world.get("_victims")
	if victims != null:
		victims.reset()
	dirty = true


## `origin` is where the shot really flies from -- the same on every peer, so
## it lands the same everywhere. `draw_from`, when given, is where this screen
## sees it leave (the part on the shooter's character); the gap is drawn
## closing over `DRAW_BLEND`. `sweep_from`, when given, is where the first hit
## check starts, so a body pressed against the shooter, nearer than the part's
## mouth, is still struck.
func show_volley(peer: int, part: int, sauce: int, origin: Vector3, forward: Vector3,
		draw_from := Vector3.INF, sweep_from := Vector3.INF) -> void:
	var profile: Dictionary = PROJECTILES[part]
	var draw_offset := draw_from - origin if draw_from.is_finite() else Vector3.ZERO
	for direction: Vector3 in [forward]:
		var glob := MeshInstance3D.new()
		glob.mesh = _sauce_mesh
		glob.material_override = _sauce_materials[sauce]
		glob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glob.scale = Vector3.ONE * (2.0 * float(profile.size))
		add_child(glob)
		# `head` is where the shot really is; the node is only drawn from it.
		var shot := {"node": glob, "peer": peer, "part": part, "sauce": sauce,
			"velocity": direction * float(profile.speed), "left": profile.life,
			"launch_speed": direction.length() * float(profile.speed),
			"head": origin, "origin": origin, "age": 0.0, "draw_offset": draw_offset}
		if sweep_from.is_finite():
			shot["sweep_from"] = sweep_from
		_place_shot(shot, profile)
		_projectiles.append(shot)


func _place_shot(shot: Dictionary, _profile: Dictionary) -> void:
	var offset: Vector3 = shot.draw_offset * (1.0 - smoothstep(0.0, DRAW_BLEND, float(shot.age)))
	(shot.node as MeshInstance3D).global_position = shot.head + offset


func advance_projectiles(delta: float, authority: bool) -> void:
	for i in range(_projectiles.size() - 1, -1, -1):
		var shot: Dictionary = _projectiles[i]
		var profile: Dictionary = PROJECTILES[shot.part]
		var node: MeshInstance3D = shot.node
		var from: Vector3 = shot.head
		shot.velocity += Vector3.DOWN * float(profile.gravity) * delta
		var to: Vector3 = from + shot.velocity * delta
		var sweep: Vector3 = shot.get("sweep_from", from)
		shot.erase("sweep_from")
		var query := PhysicsRayQueryParameters3D.create(sweep, to)
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
			shot.head = to
			shot.age = float(shot.age) + delta
			_place_shot(shot, profile)
			continue
		node.queue_free()
		_projectiles.remove_at(i)
