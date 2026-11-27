extends Node3D

enum Part { STANDARD, FAN, FOCUS, BURST, ARC, CANNON, SNIPER }

## 번호는 `Part`와 같다. 이름만 바뀐 것: FAN은 3갈래 노즐, ARC는 박격포 캡이다.
## 칸은 [이름, 설명, 파는 피난처 번호, 가격]. 설명의 둘째 줄은 병을 흔들어 쏘았을 때의 효과다.
## 그 수치는 게이지를 다 채웠을 때의 값을 손으로 적은 것이다 -- 아래 상수를 바꾸면 여기도 고친다.
const CATALOG := [
	["기본 노즐", "기본 연속 분사\n흔들기: 속도 +30% · 사거리 +50%", 0, 0],
	["3갈래 노즐", "기본 줄기 세 가닥 · 가닥마다 조금 가늘고 약함 · 소스 두 배 소모\n흔들기: 가닥 사이 각도 -60%", 0, 5],
	["집중 노즐", "가늘고 멀리 뻗는 연속 분사\n흔들기: 속도 +30% · 사거리 +50%", 0, 5],
	["점사 밸브", "한 번 누를 때 짧게 세 발 분사\n흔들기: 발사 수 +1", 1, 5],
	["박격포 캡", "조준한 방향으로 날아가 착탄 시 폭발 · 아군도 맞음\n흔들기: 수평 발사 속도 24→28 m/s · 피해 +89%", 1, 6],
	["대포형 소스통", "낮고 빠르게 날아가 터짐 · 한 발에 탱크 25%\n흔들기: 폭발 범위 +50% · 주변 피해 +43%", 1, 7],
	["저격 노즐", "빠른 한 발 · 적 셋까지 관통 · 휠 클릭을 누르는 동안 조준, 좌클릭으로 발사\n흔들기: 관통 +1", 1, 6],
]
## 사무실 작업대에서 파츠를 해금하는 값(팀 돈). 번호는 `Part`와 같다. 기본 노즐은 처음부터 있다.
## 해금한 파츠만 축제의 피난처 상점에 나온다(거기서는 위의 코인 값을 낸다).
const UNLOCK_PRICES := [0, 100, 100, 100, 120, 120, 120]
## 처음부터 해금되어 있는 것: 기본 노즐뿐.
const UNLOCKED_AT_START := 1


## `mask`(비트마다 파츠 하나)에 `part`가 해금되어 있는가.
static func is_unlocked(mask: int, part: int) -> bool:
	return part >= 0 and part < UNLOCK_PRICES.size() and (mask & (1 << part)) != 0


## 덩어리를 쏘는 파츠. 각 파츠의 `gravity`를 받고 무언가에 닿을 때까지 난다 -- `life`는
## 허공으로 날아간 것을 치우는 상한일 뿐이다. `reach`는 조준점을 어디까지 찾는가(m).
## `blast`는 폭발 반경, `blast_damage`는 직접 맞지 않은 대상이 받는 피해(없으면 직격의 절반).
const GRAVITY := 9.8
const PROJECTILES := {
	# Keep the drop at 55 m close to the old drop at 45 m.
	Part.SNIPER: {"speed": 100.0, "gravity": 6.5, "life": 4.0, "reach": 55.0,
		"damage": 55.0, "blast": 0.0, "cost": 0.06, "cooldown": 1.2},
	Part.BURST: {"speed": 32.0, "gravity": GRAVITY, "life": 6.0, "reach": 20.0,
		"damage": 9.5, "blast": 0.0, "cost": 0.040, "cooldown": 0.48},
	Part.ARC: {"speed": 28.0, "gravity": GRAVITY, "life": 10.0, "reach": 40.0,
		"damage": 85.0, "blast": 3.6, "cost": 0.15, "cooldown": 1.5},
	Part.CANNON: {"speed": 28.0, "gravity": GRAVITY, "life": 6.0, "reach": 30.0,
		"damage": 100.0, "blast": 1.8, "blast_damage": 42.0, "cost": 0.25, "cooldown": 2.5},
}

## First-person recoil peaks. Distances are in metres, angles in degrees, and times in seconds.
const RECOIL := {
	Part.STANDARD: {"distance": 0.031, "pitch": 1.5, "attack": 0.032, "recovery": 0.12, "pressure": 0.015},
	Part.FAN: {"distance": 0.055, "pitch": 2.3, "roll": -3.6, "attack": 0.038, "recovery": 0.16, "pressure": 0.019},
	Part.FOCUS: {"distance": 0.031, "pitch": 0.7, "attack": 0.022, "recovery": 0.075, "pressure": 0.004},
	Part.BURST: {"distance": 0.034, "pitch": 1.9, "attack": 0.022, "recovery": 0.065},
	Part.ARC: {"distance": 0.075, "pitch": 19.0, "attack": 0.055, "recovery": 0.38},
	Part.CANNON: {"distance": 0.17, "pitch": 14.0, "attack": 0.048, "recovery": 0.44},
	Part.SNIPER: {"distance": 0.061, "pitch": 6.8, "attack": 0.024, "recovery": 0.13},
}

## Fine grip vibration, sustained aim lift and slight side drift. Angles are radians and frequency is in Hz.
const STREAM_AIM_RECOIL := {
	Part.STANDARD: {"amplitude": Vector2(0.36, 0.29) * (PI / 180.0), "frequency": 7.0,
		"lift": deg_to_rad(9.0), "side_drift": deg_to_rad(0.64)},
	Part.FAN: {"amplitude": Vector2(0.50, 0.40) * (PI / 180.0), "frequency": 7.6,
		"lift": deg_to_rad(11.5), "side_drift": deg_to_rad(0.96)},
	Part.FOCUS: {"amplitude": Vector2(0.23, 0.18) * (PI / 180.0), "frequency": 8.8,
		"lift": deg_to_rad(7.0), "side_drift": deg_to_rad(0.48)},
}

## Actual projectile aim lift and recovery, in degrees and seconds.
const SHOT_AIM_RECOIL := {
	Part.BURST: {"lift": 1.35, "limit": 8.0, "rise_speed": 100.0, "hold": 0.13, "return_speed": 14.0},
	Part.ARC: {"lift": 14.0, "limit": 26.0, "rise_speed": 210.0, "hold": 0.20, "return_speed": 9.3},
	Part.CANNON: {"lift": 19.0, "limit": 26.0, "rise_speed": 260.0, "hold": 0.28, "return_speed": 7.7},
	Part.SNIPER: {"lift": 6.0, "limit": 16.0, "rise_speed": 260.0, "hold": 0.13, "return_speed": 4.0},
}

## 3갈래 노즐: 기본 줄기와 똑같은 줄기 세 가닥이 이 각도씩 벌어져 나간다. 가닥마다 굵기와
## 피해가 `THREE_WAY_SCALE`배이고, 소스는 기본의 `THREE_WAY_FLOW`배로 나간다.
## 저격 노즐: 휠 클릭을 누르는 동안 화면이 `SNIPER_ZOOM`배로 당겨지고, 좌클릭으로 한 발 쏜다.
## 한 발이 적을 `SNIPER_PIERCE`마리까지 차례로 맞히고(병을 흔들어 쏘면 한 마리 더), 한 마리를
## 지날 때마다 피해가 `SNIPER_PIERCE_FALLOFF`배가 된다. 벽이나 바닥에 닿으면 거기서 끝난다.
const SNIPER_PIERCE := 3
const SNIPER_PIERCE_FALLOFF := 0.8
const SNIPER_ZOOM := 0.45
## 병을 흔들어 쏘았을 때 파츠마다 달라지는 것(게이지 0~1):
##   기본·집중  줄기가 더 빠르고 멀리 간다(스테이지의 `bottle_charge_*` 값).
##   3갈래      가닥 사이가 `THREE_WAY_ANGLE`에서 `THREE_WAY_SHAKEN_ANGLE`로 모인다.
##   점사       게이지가 `SHAKE_THRESHOLD` 이상이면 세 발 대신 `BURST_SHAKEN_SHOTS`발.
##   박격포     멀리, 세게(위의 MORTAR_* 값).
##   대포       폭발 반경과 주변 피해가 `CANNON_SHAKEN_*`까지 커진다.
##   저격       게이지가 `SHAKE_THRESHOLD` 이상이면 한 마리 더 꿰뚫는다.
## 덩어리 파츠는 더 빨라지지 않는다. 얼마나 흔들어 쏜 것인지는 발사 방향 벡터의 길이에
## `SHAKE_MARK`만큼 얹어 모든 화면에 보낸다(`shake_of`가 다시 읽는다).
const SHAKE_THRESHOLD := 0.5
const SHAKE_MARK := 0.002
const BURST_SHOTS := 3
const BURST_SHAKEN_SHOTS := 4
const THREE_WAY_SHAKEN_ANGLE := deg_to_rad(6.0)
const CANNON_SHAKEN_BLAST := 2.7
const CANNON_SHAKEN_BLAST_DAMAGE := 60.0


## 발사 방향 벡터의 길이(`reach`, 평소 1)에서 얼마나 흔들어 쏜 것인지 읽는다, 0~1.
static func shake_of(reach: float) -> float:
	return clampf((reach - 1.0) / SHAKE_MARK, 0.0, 1.0)


static func cannon_blast(shake: float) -> float:
	return lerpf(float(PROJECTILES[Part.CANNON].blast), CANNON_SHAKEN_BLAST, clampf(shake, 0.0, 1.0))


static func cannon_blast_damage(shake: float) -> float:
	return lerpf(float(PROJECTILES[Part.CANNON].blast_damage), CANNON_SHAKEN_BLAST_DAMAGE, clampf(shake, 0.0, 1.0))
const THREE_WAY_ANGLE := deg_to_rad(15.0)
const THREE_WAY_SCALE := 0.8
const THREE_WAY_FLOW := 2.0
## 박격포 캡은 시점 그대로 쏘며, 가파르게 올려 쏠 때는 발사 속도를 낮춰 상승 높이를 제한한다.
const MORTAR_MAX_RISE := 3.2
const MORTAR_PREVIEW_ACTOR_LAYER := 31
const MORTAR_PREVIEW_ACTOR_MASK := 1 << (MORTAR_PREVIEW_ACTOR_LAYER - 1)
const MORTAR_MIN_SPEED := 24.0
const MORTAR_MIN_DAMAGE := 45.0
const MORTAR_RADIUS_SHARE := 0.8
const MORTAR_CHARGE_HOLD := 5.0


static func mortar_launch_velocity(aim: Vector3, charge: float) -> Vector3:
	var direction := aim.normalized()
	var speed := lerpf(MORTAR_MIN_SPEED, float(PROJECTILES[Part.ARC].speed), clampf(charge, 0.0, 1.0))
	return direction * speed * _mortar_speed_scale(direction)


## Apply the same scale to the whole charge range to preserve the shot direction.
static func _mortar_speed_scale(direction: Vector3) -> float:
	var max_upward_speed := sqrt(2.0 * GRAVITY * MORTAR_MAX_RISE)
	var full_upward_speed := direction.y * float(PROJECTILES[Part.ARC].speed)
	return max_upward_speed / maxf(max_upward_speed, full_upward_speed)


static func mortar_charge(launch_velocity: Vector3) -> float:
	var speed := launch_velocity.length() / _mortar_speed_scale(launch_velocity.normalized())
	return clampf(inverse_lerp(MORTAR_MIN_SPEED, float(PROJECTILES[Part.ARC].speed), speed), 0.0, 1.0)


static func mortar_damage(charge: float) -> float:
	return lerpf(MORTAR_MIN_DAMAGE, float(PROJECTILES[Part.ARC].damage), clampf(charge, 0.0, 1.0))


static func ballistic_position(origin: Vector3, velocity: Vector3, gravity: float, seconds: float) -> Vector3:
	return origin + velocity * seconds + Vector3.DOWN * (0.5 * gravity * seconds * seconds)
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
	Color("c589d9"), Color("dfab60"), Color("b85e41"), Color("3f4a5c")]

## 보스(프레스 킹)를 쓰러뜨리면 전원이 받는 코인.
const BOSS_BOUNTY := 20

var world: Node3D
var dirty := false
var burst_at := Vector3.INF
var burst_msec := 0
var _rng := RandomNumberGenerator.new()
var _rolled_deaths := {}
var _coins := {}
var _coin_serial := 0
var _projectiles: Array[Dictionary] = []
var _projectile_ray := PhysicsRayQueryParameters3D.new()
var _close_impact_ribbons: Array[Dictionary] = []
var _coin_mesh: CylinderMesh
var _free_projectile_ribbons: Array[StreamVisual] = []
var _projectile_segments: Array = [[]]

const BURST_SIZE_SCALE := 1.5
const BURST_DRAW_LENGTH := 1.45 * BURST_SIZE_SCALE
const BURST_WIDTH_SCALE := 1.7 * BURST_SIZE_SCALE
const BURST_WIDTHS := [0.68, 1.0, 0.83, 0.91, 0.62, 0.43, 0.16]
const PROJECTILE_RIBBON_POOL_LIMIT := 24
const PROJECTILE_RIBBON_POINTS := 7
const CLOSE_IMPACT_FLIGHT_TIME := 0.07
const CLOSE_IMPACT_DRAW_TIME := 0.085
## Cross-sections start at the leading edge and taper along the flight path.
const PROJECTILE_RIBBONS := {
	Part.BURST: {"length": BURST_DRAW_LENGTH, "width": BURST_WIDTH_SCALE, "bend": 0.30, "sections": BURST_WIDTHS},
	Part.ARC: {"length": 2.75, "width": 5.5, "bend": 0.32, "sections": [0.55, 1.0, 0.96, 0.77, 0.57, 0.28, 0.08]},
	Part.CANNON: {"length": 2.4, "width": 6.2, "bend": 0.25, "sections": [0.65, 1.0, 0.82, 0.91, 0.52, 0.34, 0.11]},
	Part.SNIPER: {"length": 4.1, "width": 1.55, "bend": 0.23, "sections": [0.48, 1.0, 0.76, 0.59, 0.43, 0.20, 0.06]},
}

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
		Part.SNIPER:
			return 0.26
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
		if part == Part.SNIPER:
			# 길고 가는 총열.
			barrel.height = 0.52
			barrel.bottom_radius = 0.05
			barrel.top_radius = 0.03
		body.mesh = barrel
		body.rotation.x = -PI * 0.5
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

	for i in PROJECTILE_RIBBON_POINTS:
		_projectile_segments[0].append({"position": Vector3.ZERO, "width_scale": 0.0})


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


## Authority only: `count` coins straight into every purse, with no coin on the
## ground -- a searched body, the boss. `at` is where they came out of, which the
## HUD flies them in from (see `note_burst`).
func grant_coins(count: int, at := Vector3.INF) -> void:
	if count <= 0:
		return
	for shooter in world._shooters.values():
		shooter.coins += count
	note_burst(at)
	dirty = true
	world._refresh_refuge_shop()


## Where the coins about to land in the purse came from. Every peer notes it for
## itself -- the host on granting, a guest on hearing a body was searched.
func note_burst(at: Vector3) -> void:
	burst_at = at
	burst_msec = Time.get_ticks_msec()


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
		_release_projectile(shot.node)
	_projectiles.clear()
	for trace in _close_impact_ribbons:
		_release_projectile(trace.node)
	_close_impact_ribbons.clear()
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
	var material: ShaderMaterial = world.SAUCE_STREAM_MATERIALS[sauce]
	var ribbon: StreamVisual
	if _free_projectile_ribbons.is_empty():
		ribbon = StreamVisual.new()
		ribbon.setup(material, PROJECTILE_RIBBON_POINTS)
		add_child(ribbon)
	else:
		ribbon = _free_projectile_ribbons.pop_back()
		ribbon.set_ribbon_material(material)
	# `head` is the simulated tip. The ribbon follows behind it for display.
	# The mortar carries real speed in the direction vector. Cannon and sniper
	# carry a small shake marker instead, so their launch speeds stay constant.
	var shake := shake_of(forward.length()) if part == Part.CANNON or part == Part.SNIPER else 0.0
	var launch_vector := forward if part == Part.ARC else forward.normalized()
	var launch_velocity := launch_vector * float(profile.speed)
	var shot := {"node": ribbon, "peer": peer, "part": part, "sauce": sauce,
		"velocity": launch_velocity, "left": profile.life,
		"launch_velocity": launch_velocity,
		"shake": shake,
		"pierce_limit": SNIPER_PIERCE + (1 if part == Part.SNIPER and shake >= SHAKE_THRESHOLD - 0.001 else 0),
		"head": origin, "origin": origin, "age": 0.0, "draw_offset": draw_offset}
	if sweep_from.is_finite():
		shot["sweep_from"] = sweep_from
	_projectiles.append(shot)


func _release_projectile(ribbon: StreamVisual) -> void:
	if _free_projectile_ribbons.size() < PROJECTILE_RIBBON_POOL_LIMIT:
		ribbon.hide()
		_free_projectile_ribbons.append(ribbon)
	else:
		ribbon.queue_free()


func _draw_projectile(shot: Dictionary, gravity: float) -> void:
	var age: float = shot.age
	if age <= 0.0:
		return
	var ribbon: StreamVisual = shot.node
	var camera: Camera3D = world._camera
	var head: Vector3 = shot.head
	var velocity: Vector3 = shot.velocity
	var profile: Dictionary = PROJECTILE_RIBBONS[shot.part]
	var trail_seconds := minf(age, float(profile.length) / maxf(velocity.length(), 0.01))
	var strand_width: float = world.strand_thickness * float(profile.width)
	var bend := strand_width * float(profile.bend)
	var sections: Array = profile.sections
	var side := velocity.normalized().cross(Vector3.UP)
	var segment: Array = _projectile_segments[0]
	for i in PROJECTILE_RIBBON_POINTS:
		var progress := float(i) / float(PROJECTILE_RIBBON_POINTS - 1)
		var back_time := trail_seconds * progress
		# Draw only the part of the trail that has already left the muzzle.
		var point_age := age - back_time
		var offset: Vector3 = shot.draw_offset * (1.0 - smoothstep(0.0, DRAW_BLEND, point_age))
		var position := head - velocity * back_time + Vector3.DOWN * (0.5 * gravity * back_time ** 2)
		position += offset + side * (sin(progress * TAU) * bend)
		segment[i].position = position
		segment[i].width_scale = sections[i]
	ribbon.update_ribbon(_projectile_segments, camera.global_position, -camera.global_basis.z, strand_width)


## The first physics sweep can land a shot before an in-flight ribbon is drawn.
## Retain its render buffer briefly, using the visible mouth and confirmed impact.
func _hold_close_impact(shot: Dictionary, at: Vector3, normal: Vector3) -> bool:
	if float(shot.age) >= CLOSE_IMPACT_FLIGHT_TIME:
		return false
	var muzzle: Vector3 = shot.origin + shot.draw_offset
	var touch := at + normal * 0.012
	if muzzle.distance_squared_to(touch) <= 0.0001:
		return false
	var trace := {
		"node": shot.node, "part": shot.part, "muzzle": muzzle, "contact": touch,
		"remaining": CLOSE_IMPACT_DRAW_TIME,
	}
	_close_impact_ribbons.append(trace)
	_draw_close_impact(trace)
	return true


func _draw_close_impact(trace: Dictionary) -> void:
	var profile: Dictionary = PROJECTILE_RIBBONS[trace.part]
	var sections: Array = profile.sections
	var segment: Array = _projectile_segments[0]
	var contact: Vector3 = trace.contact
	var muzzle: Vector3 = trace.muzzle
	var fade := smoothstep(0.0, 0.65, float(trace.remaining) / CLOSE_IMPACT_DRAW_TIME)
	for index in PROJECTILE_RIBBON_POINTS:
		var progress := float(index) / float(PROJECTILE_RIBBON_POINTS - 1)
		segment[index].position = contact.lerp(muzzle, progress)
		segment[index].width_scale = float(sections[index]) * fade
	var ribbon: StreamVisual = trace.node
	var camera: Camera3D = world._camera
	var width: float = world.strand_thickness * float(profile.width) * 0.62
	ribbon.update_ribbon(_projectile_segments, camera.global_position, -camera.global_basis.z, width)


func advance_projectiles(delta: float, authority: bool) -> void:
	for i in range(_close_impact_ribbons.size() - 1, -1, -1):
		var trace: Dictionary = _close_impact_ribbons[i]
		trace.remaining = float(trace.remaining) - delta
		if trace.remaining <= 0.0:
			_release_projectile(trace.node)
			_close_impact_ribbons.remove_at(i)
		else:
			_draw_close_impact(trace)
	if _projectiles.is_empty():
		return
	var space := get_world_3d().direct_space_state
	var query := _projectile_ray
	query.collide_with_areas = true
	var self_exclusions: Dictionary[int, Array] = {}
	var last_peer := -1
	var last_had_pierces := false
	for i in range(_projectiles.size() - 1, -1, -1):
		var shot: Dictionary = _projectiles[i]
		var profile: Dictionary = PROJECTILES[shot.part]
		var ribbon: StreamVisual = shot.node
		var from: Vector3 = shot.head
		var gravity: float = profile.gravity
		shot.velocity += Vector3.DOWN * gravity * delta
		var to: Vector3 = from + shot.velocity * delta
		if shot.part == Part.ARC:
			to = ballistic_position(shot.origin, shot.launch_velocity, gravity, float(shot.age) + delta)
		var sweep: Vector3 = shot.get("sweep_from", from)
		shot.erase("sweep_from")
		query.from = sweep
		query.to = to
		var peer: int = shot.peer
		var shooter = world.shooter_for(peer)
		var has_pierces := shot.has("passed")
		if peer != last_peer or has_pierces or last_had_pierces:
			if not self_exclusions.has(peer):
				var own_body: Array[RID] = []
				if shooter != null:
					own_body = world.sauce_self_exclusions(shooter)
				self_exclusions[peer] = own_body
			var skipped: Array[RID] = self_exclusions[peer]
			if has_pierces:
				skipped = skipped.duplicate()
				skipped.append_array(shot.passed)
			query.exclude = skipped
		last_peer = peer
		last_had_pierces = has_pierces
		query.hit_from_inside = float(shot.age) == 0.0
		var hit: Dictionary = world.cast_sauce_ray(space, query)
		if not hit.is_empty():
			shot.impact_direction = to - sweep
			if (hit.normal as Vector3).is_zero_approx():
				hit.normal = (sweep - to).normalized()
		shot.left -= delta
		if authority:
			world._cut_cheese_by_stream(from, to if hit.is_empty() else hit.position)
		if not hit.is_empty():
			world._part_projectile_impact(hit, shot, profile, shooter, authority)
			# 저격 노즐: 적을 맞히고도 계속 난다, 정해진 수만큼. 맞힌 적은 다시 맞히지 않는다.
			if shot.part == Part.SNIPER and hit.collider is MayoEnemy and shot.left > 0.0:
				shot.pierced = int(shot.get("pierced", 0)) + 1
				if int(shot.pierced) < int(shot.get("pierce_limit", SNIPER_PIERCE)):
					var passed: Array = shot.get("passed", [])
					passed.push_back((hit.collider as CollisionObject3D).get_rid())
					shot.passed = passed
					shot.damage_scale = float(shot.get("damage_scale", 1.0)) * SNIPER_PIERCE_FALLOFF
					shot.head = hit.position
					shot.age = float(shot.age) + delta
					_draw_projectile(shot, gravity)
					continue
		elif shot.left > 0.0:
			shot.head = to
			shot.age = float(shot.age) + delta
			_draw_projectile(shot, gravity)
			continue
		if hit.is_empty() or not _hold_close_impact(shot, hit.position, hit.normal):
			_release_projectile(ribbon)
		_projectiles.remove_at(i)
