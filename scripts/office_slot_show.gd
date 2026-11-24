class_name OfficeSlotShow
extends Node

## 사무실에 놓인 슬롯머신이 직접 보여 주는 것: 레버가 밑동을 축으로 호를 그리며 앞으로
## 넘어갔다가 돌아오고, 기계의 세 칸이 돌다가
## 하나씩 멈추고, 맞으면 전구가 번쩍인다. 소리도 여기서 낸다.
## 누가 돌리든 사무실의 모두에게 보인다(`MayoNet.slot_result`가 전원에게 온다).
## 평소에는 전구가 느리게 번갈아 깜빡인다.

const SFX := {
	"tick": preload("res://assets/audio/slot/tick.wav"),
	"stop": preload("res://assets/audio/slot/stop.wav"),
	"lever": preload("res://assets/audio/slot/lever.wav"),
	"lose": preload("res://assets/audio/slot/lose.wav"),
	"win_small": preload("res://assets/audio/slot/win_small.wav"),
	"win": preload("res://assets/audio/slot/win.wav"),
	"jackpot": preload("res://assets/audio/slot/jackpot.wav"),
}
## 등급(`OfficeSlot.tier_of`)마다 끝에 나는 소리와 전구가 번쩍이는 시간(초).
const TIER_SFX := ["lose", "win_small", "win", "win", "jackpot"]
const TIER_FLASH := [0.0, 0.7, 2.0, 2.4, 5.0]

var _machine: Node3D
var _symbols: Array[ShaderMaterial] = []
var _bulbs: Array[ShaderMaterial] = []
## 레버가 넘어가는 각도와 걸리는 시간. 내려갈 때는 톱니를 넘기듯 `LEVER_NOTCHES`번 걸린다.
const LEVER_PULL := deg_to_rad(78.0)
const LEVER_DOWN_TIME := 0.34
const LEVER_HOLD_TIME := 0.1
const LEVER_BACK_TIME := 0.55
const LEVER_NOTCHES := 6.0

var _lever: Array[Node3D] = []
var _lever_rest: Array[Transform3D] = []
## 레버 밑동(기계 좌표). 레버의 모든 조각이 이 점을 지나는 가로축을 따라 돈다.
var _lever_pivot := Vector3.ZERO
var _lever_tween: Tween
var _light: OmniLight3D
var _voice: AudioStreamPlayer3D
var _clock := 0.0
var _reels := PackedInt32Array()
var _elapsed := -1.0
var _stopped := 0
var _tier := 0
var _flash_left := 0.0
var _quiet := false
var _shown_symbols := PackedInt32Array([-1, -1, -1])
var _bulb_phase := -1
var _bulbs_winning := false


## `room`의 `SlotMachine` 노드에 붙는다. 그 노드가 없으면 아무것도 하지 않는다.
func setup(room: Node3D) -> void:
	_machine = room.get_node_or_null("SlotMachine") as Node3D
	if _machine == null:
		return
	for index in 3:
		_symbols.push_back(_own_material(_machine.get_node_or_null("Symbol%d" % (index + 1))))
	for index in 5:
		_bulbs.push_back(_own_material(_machine.get_node_or_null("Bulb%d" % (index + 1))))
	for part in ["LeverArm", "LeverKnob"]:
		var node := _machine.get_node_or_null(part) as Node3D
		if node != null:
			_lever.push_back(node)
			_lever_rest.push_back(node.transform)
			if part == "LeverArm":
				_lever_pivot = _foot_of(node)
	_light = OmniLight3D.new()
	_light.position = Vector3(0.0, 1.8, 1.4)
	_light.light_color = Color("ffd257")
	_light.omni_range = 7.0
	_light.light_energy = 0.0
	_machine.add_child(_light)
	_voice = AudioStreamPlayer3D.new()
	_voice.position = Vector3(0.0, 1.5, 0.6)
	_voice.bus = &"SFX"
	_voice.unit_size = 6.0
	_voice.max_distance = 40.0
	_machine.add_child(_voice)
	_show_symbols(PackedInt32Array([0, 1, 2]))


## 화면 전체에 들리는 소리(돌린 사람의 화면용).
func play(sound: String) -> void:
	if not SFX.has(sound):
		return
	var player := AudioStreamPlayer.new()
	player.stream = SFX[sound]
	player.bus = &"SFX"
	player.volume_db = -6.0 if sound == "tick" else -2.0
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


## 한 번 돌린 것을 기계가 보여 준다. `quiet`이면 기계는 소리를 내지 않는다(돌린 사람은
## 자기 화면에서 이미 듣는다).
func spin(reels: PackedInt32Array, quiet: bool) -> void:
	if _machine == null or reels.size() != 3:
		return
	_reels = reels
	_tier = OfficeSlot.tier_of(reels)
	_elapsed = 0.0
	_stopped = 0
	_flash_left = 0.0
	_quiet = quiet
	_say("lever")
	if _lever_tween != null:
		_lever_tween.kill()
	_lever_tween = create_tween()
	# 내려갈 때: 호를 따라가되 톱니 하나를 넘을 때마다 잠깐씩 걸린다.
	_lever_tween.tween_method(func(t: float):
		var eased := t * t * (3.0 - 2.0 * t)
		var notch := floorf(eased * LEVER_NOTCHES) / LEVER_NOTCHES
		_set_lever(LEVER_PULL * lerpf(eased, notch, 0.45) if t < 1.0 else LEVER_PULL),
		0.0, 1.0, LEVER_DOWN_TIME)
	_lever_tween.tween_interval(LEVER_HOLD_TIME)
	# 놓으면 용수철로 되돌아가며 한 번 출렁인다.
	_lever_tween.tween_method(_set_lever, LEVER_PULL, 0.0, LEVER_BACK_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 레버를 선 자리에서 앞으로 `angle`만큼 넘긴다: 밑동을 지나는 가로축(기계의 x) 둘레로 돈다.
func _set_lever(angle: float) -> void:
	var turn := Transform3D(Basis(Vector3.RIGHT, angle), _lever_pivot) \
		* Transform3D(Basis.IDENTITY, -_lever_pivot)
	for index in _lever.size():
		if is_instance_valid(_lever[index]):
			_lever[index].transform = turn * _lever_rest[index]


## 레버 막대의 맨 아래 가운데(기계 좌표).
func _foot_of(arm: Node3D) -> Vector3:
	var box := AABB()
	if arm is MeshInstance3D and (arm as MeshInstance3D).mesh != null:
		box = (arm as MeshInstance3D).mesh.get_aabb()
	elif arm is CSGBox3D:
		box = AABB(-(arm as CSGBox3D).size * 0.5, (arm as CSGBox3D).size)
	var centre := box.get_center()
	return arm.transform * Vector3(centre.x, box.position.y, centre.z)


func _process(delta: float) -> void:
	if _machine == null:
		return
	_clock += delta
	if _elapsed >= 0.0:
		_elapsed += delta
		var stops := OfficeSlot.stop_times(_reels)
		var shown := PackedInt32Array([0, 0, 0])
		var stopped := 0
		for index in 3:
			if _elapsed >= stops[index]:
				shown[index] = _reels[index]
				stopped += 1
			else:
				shown[index] = (index + OfficeSlot.spin_ticks(index, _reels, _elapsed)) % OfficeSlot.SYMBOLS.size()
		_show_symbols(shown)
		if stopped > _stopped:
			_stopped = stopped
			_say("stop")
		if stopped == 3:
			_elapsed = -1.0
			_flash_left = TIER_FLASH[_tier]
			_say(TIER_SFX[_tier])
	# 전구: 맞았으면 빠르게 전부 번쩍, 평소에는 느리게 번갈아.
	var winning := _flash_left > 0.0
	if winning:
		_flash_left -= delta
	var phase := int(_clock * (12.0 if winning else 1.5))
	if phase != _bulb_phase or winning != _bulbs_winning:
		_bulb_phase = phase
		_bulbs_winning = winning
		for index in _bulbs.size():
			var lit := (phase + index) % (2 if winning else 3) == 0
			if _bulbs[index] != null:
				_bulbs[index].set_shader_parameter("glow", 1.6 if lit else 0.1)
	if _light != null:
		_light.light_energy = (2.5 + 2.0 * sin(_clock * 24.0)) if winning and _tier >= 2 else 0.0


func _say(sound: String) -> void:
	if _quiet or _voice == null or not SFX.has(sound):
		return
	_voice.stream = SFX[sound]
	_voice.play()


func _show_symbols(symbols: PackedInt32Array) -> void:
	for index in mini(_symbols.size(), symbols.size()):
		if _symbols[index] != null and symbols[index] != _shown_symbols[index]:
			_symbols[index].set_shader_parameter("albedo", OfficeSlot.SYMBOL_COLORS[symbols[index]])
			_shown_symbols[index] = symbols[index]


## 이 조각만의 재질: 씬에서는 여러 조각이 한 재질을 같이 쓰므로, 색을 따로 바꾸려면 복제한다.
func _own_material(node: Node) -> ShaderMaterial:
	var instance := node as MeshInstance3D
	if instance == null or instance.mesh == null:
		return null
	var source := instance.get_active_material(0) as ShaderMaterial
	if source == null:
		return null
	var own := source.duplicate() as ShaderMaterial
	instance.set_surface_override_material(0, own)
	return own
