class_name MayoTutorial
extends Node

## Server-owned festival opening. Movement and looking always belong to the
## player; actions, not locked cutscenes, connect the lessons.
static var disabled := false

enum Stage { IDLE, GET_SAUCE, FIRST_FIGHT, MONSTER_CUE, MONSTER_ARRIVES,
	RUN, TRAPPED, REFILL, COOP_FIGHT, OUTRO, COMPLETE }

const INTRO_DELAY := 0.6
const KIND_RUSHER := 0
const KIND_BRUISER := 1
const MONSTER_BEHIND := 16.0
const MONSTER_NEAREST := 6.0
const MONSTER_CLEAR_STEP := 0.8
const MONSTER_ARC_STEPS := [0.0, 22.0, -22.0, 45.0, -45.0, 70.0, -70.0, 90.0, -90.0]
const LINE_SECONDS := 3.4
const LINE_GAP := 0.25
const URGENT_LINE_SECONDS := 3.6
const TAG_NONE := 0
const TAG_RUN_ORDER := 1
const TAG_OPENING := 2
const TAG_SHOOT := 3
const SAY_GET_SAUCE := 0
const SAY_TOAST := 1
const SAY_SERVICE := 2
const SAY_SAUCE_FIRST := 3
const SAY_HOLD_STILL := 4
const SAY_BEHIND_YOU := 5
const SAY_RUN := 6
const SAY_TRAPPED := 7
const SAY_WALK := 8
const SAY_GO_REFILL := 9
const SAY_FINISH := 10
const SAY_RECRUIT := 11
const SAY_NOT_EATEN := 12
const SAY_LETS_GO := 13
const SAY_CROSSED := 14
const SAY_EARLY_CLEAR := 15
const SAY_INTRODUCE := 16
const LINES := [
	"먹기 전에 소스부터 챙기자.",
	"야, 토스트다.",
	"음식이 알아서 오네. 서비스 좋다.",
	"잠깐, 소스부터 뿌리고.",
	"가만있어 봐. 골고루 안 묻잖아.",
	"저기요!! 들리시나요? 뒤를 조심해요!!",
	"Shift를 누르고 포장마차 사이로 뛰세요! 저 덩치는 못 지나올 거예요!",
	"걸렸다…! 괜찮아요?",
	"마요네즈 위에서는 뛰지 말고 걸어요!",
	"저쪽 매대에도 소스가 있어요! E를 눌러 소스통을 채우세요!",
	"소스도 채웠겠다, 저것부터 치우자.",
	"다른 먹거리 구역에서도 신고가 들어왔어요. 같이 가주실 수 있나요?",
	"아, 거긴 아직 못 먹어봤는데.",
	"빨리 가서 저것들부터 치워요.",
	"잘 빠져나왔어요! 저 덩치는 걸렸네요.",
	"벌써 쓰러뜨렸네요…! 일단 소스부터 채워요.",
	"현장 조사 나온 박사예요. 음식이 움직이는 건 저도 처음 보는데… 같이 정리해보죠.",
]
const DOCTOR_LINES := [SAY_BEHIND_YOU, SAY_RUN, SAY_TRAPPED, SAY_WALK,
	SAY_GO_REFILL, SAY_RECRUIT, SAY_CROSSED, SAY_EARLY_CLEAR, SAY_INTRODUCE]

var world: Node3D
var stage: int = Stage.IDLE
var fight_enemies := PackedInt32Array()
var monster_index := -1
var acquired: Array[int] = []
var supplied: Array[int] = []
var slipped: Array[int] = []
var monster_trapped := false
var trap_position := Vector3.ZERO
var lines_shown := 0
var stomps_heard := 0
var impacts_heard := 0
var _clock := 0.0
var _stage_clock := 0.0
var _cue_step := 0
var _initial_station := -1
var _station := -1
var _station_position := Vector3.INF
var _refill_open := false
var _hit_reaction := false
var _line := -1
var _line_left := 0.0
var _line_gap := 0.0
var _line_tag := TAG_NONE
var _line_queue: Array[Array] = []

func _ready() -> void:
	name = "Tutorial"

func reset_session() -> void:
	stage = Stage.IDLE
	fight_enemies.clear()
	monster_index = -1
	acquired.clear()
	supplied.clear()
	slipped.clear()
	monster_trapped = false
	trap_position = Vector3.ZERO
	_clock = 0.0
	_stage_clock = 0.0
	_cue_step = 0
	_refill_open = false
	_hit_reaction = false
	_line = -1
	_line_left = 0.0
	_line_gap = 0.0
	_line_queue.clear()
	lines_shown = 0
	stomps_heard = 0
	impacts_heard = 0
	choose_station(world.refill_stations())

func is_enabled() -> bool:
	return not disabled

func is_running() -> bool:
	return not disabled and stage != Stage.IDLE

func is_complete() -> bool:
	return stage == Stage.COMPLETE

func allows_movement() -> bool:
	return true

func allows_looking() -> bool:
	return true

func has_bottle(peer_id: int) -> bool:
	return disabled or acquired.has(peer_id)

func allows_firing(peer_id := 0) -> bool:
	if peer_id == 0 and world._local != null:
		peer_id = world._local.peer_id
	return has_bottle(peer_id)

func allows_contact_damage(enemy: MayoEnemy, _player: MayoPlayer) -> bool:
	# Escape protection belongs only to the tutorial heavy. Once it wedges,
	# enemy.advance also suppresses knockback and physical attack motion.
	return enemy != _monster() or stage == Stage.COMPLETE and not monster_trapped

func _is_authority() -> bool:
	return world != null and world.call("_is_authority")

func advance(delta: float) -> void:
	if disabled or world == null:
		return
	_clock += delta
	_stage_clock += delta
	_advance_lines(delta)
	if not _is_authority():
		return
	if _monster() != null and not _monster().is_alive():
		world.tutorial_clear_corpse(monster_index)
	match stage:
		Stage.IDLE:
			if _clock >= INTRO_DELAY:
				_enter(Stage.GET_SAUCE)
		Stage.GET_SAUCE:
			if _everyone_in(acquired):
				_begin_first_fight()
		Stage.FIRST_FIGHT:
			_watch_fight()
		Stage.MONSTER_CUE:
			if _cue_step == 0 and _stage_clock >= 0.5:
				_spawn_monster()
				_effect(0)
				_cue_step = 1
			elif _cue_step == 1 and _stage_clock >= 1.45:
				_effect(0)
				_cue_step = 2
			elif _cue_step == 2 and _stage_clock >= 2.3:
				_enter(Stage.MONSTER_ARRIVES)
		Stage.MONSTER_ARRIVES:
			# Turning is encouraged, never required. The warning gets time to
			# read even if the player already had the monster in view.
			if _stage_clock >= 3.8:
				_enter(Stage.RUN)
		Stage.RUN:
			_watch_escape()
		Stage.TRAPPED:
			if _lines_done():
				_enter(Stage.REFILL)
		Stage.REFILL:
			if _everyone_in(supplied) and _lines_done():
				_enter(Stage.COOP_FIGHT)
		Stage.COOP_FIGHT:
			if _monster() == null or not _monster().is_alive():
				_enter(Stage.OUTRO)
		Stage.OUTRO:
			if _lines_done():
				_enter(Stage.COMPLETE)

func _enter(next: int) -> void:
	if stage == next:
		return
	stage = next
	_stage_clock = 0.0
	match stage:
		Stage.GET_SAUCE:
			_say(SAY_GET_SAUCE, TAG_OPENING)
		Stage.MONSTER_CUE:
			_cancel(TAG_SHOOT)
			_cue_step = 0
		Stage.MONSTER_ARRIVES:
			_say_now(SAY_BEHIND_YOU)
		Stage.RUN:
			_say_now(SAY_RUN, TAG_RUN_ORDER)
		Stage.TRAPPED:
			_cancel(TAG_RUN_ORDER)
			_pick_refill_station()
			_say_now((SAY_TRAPPED if not slipped.is_empty() else SAY_CROSSED)
				if monster_trapped else SAY_EARLY_CLEAR)
			_say(SAY_WALK)
			_say(SAY_GO_REFILL)
		Stage.COOP_FIGHT:
			_say(SAY_INTRODUCE)
			_say(SAY_FINISH)
		Stage.OUTRO:
			_say(SAY_RECRUIT)
			_say(SAY_NOT_EATEN)
			_say(SAY_LETS_GO)
	_push_state()

func _everyone_in(peers: Array[int]) -> bool:
	var ids: Array = world.shooter_ids()
	if ids.is_empty():
		return false
	for peer_id in ids:
		if not peers.has(peer_id):
			return false
	return true

func _begin_first_fight() -> void:
	_cancel(TAG_OPENING)
	stage = Stage.FIRST_FIGHT
	_stage_clock = 0.0
	for index in world.party_size() + 1:
		# Single file beyond the wreck: the party first sees the route being
		# used by food walking towards them, before needing it to escape.
		var at := Vector3(0.0, 0.0, TutorialWreck.SPILL_BACK - 5.0 - float(index) * 3.2)
		var enemy_id: int = world.tutorial_spawn_enemy(KIND_RUSHER, at)
		if enemy_id >= 0:
			fight_enemies.push_back(enemy_id)
	_say(SAY_TOAST, TAG_SHOOT)
	_say(SAY_SERVICE, TAG_SHOOT)
	_say(SAY_SAUCE_FIRST, TAG_SHOOT)
	_push_state()

func _watch_fight() -> void:
	var alive := 0
	for index in fight_enemies:
		var enemy: MayoEnemy = world.enemy_at(index)
		if enemy != null and enemy.is_alive():
			alive += 1
			if not _hit_reaction and enemy.health < enemy.max_health:
				_hit_reaction = true
				_say_now(SAY_HOLD_STILL, TAG_SHOOT)
		elif enemy != null:
			world.tutorial_clear_corpse(index)
	if alive == 0 and not fight_enemies.is_empty():
		_enter(Stage.MONSTER_CUE)

func _watch_escape() -> void:
	var monster := _monster()
	# A party that kills it early still gets the refill lesson and the outro.
	if monster == null or not monster.is_alive():
		_enter(Stage.TRAPPED)
		return
	var crossed := false
	for peer_id in world.shooter_ids():
		var player: MayoPlayer = world.shooter_for(peer_id).player
		if player.global_position.z < TutorialWreck.CENTRE_Z - TutorialWreck.DEPTH * 0.5:
			crossed = true
	var mouth := TutorialWreck.CENTRE_Z + TutorialWreck.DEPTH * 0.5
	# Trigger only on the actual body arriving at the narrow mouth. Waiting
	# for a player to slip would strand somebody who crossed on foot.
	if crossed and absf(monster.global_position.x) < monster.radius + 0.5 \
			and monster.global_position.z <= mouth + monster.radius + 0.6:
		monster_trapped = true
		trap_position = monster.global_position
		monster.set_tutorial_trapped(true, trap_position)
		_effect(1)
		_enter(Stage.TRAPPED)
	elif _stage_clock >= 12.0 and _lines_done():
		_stage_clock = 0.0
		_say(SAY_RUN, TAG_RUN_ORDER)

func note_slip(peer_id: int) -> void:
	if not _is_authority() or stage not in [Stage.RUN, Stage.TRAPPED, Stage.REFILL]:
		return
	var shooter = world.shooter_for(peer_id)
	if shooter != null and TutorialWreck.in_spill(shooter.player.global_position) \
			and not slipped.has(peer_id):
		slipped.push_back(peer_id)
		if stage == Stage.RUN:
			_say_now(SAY_WALK, TAG_RUN_ORDER)
		_push_state()

func targets_for(enemy: MayoEnemy, targets: Array) -> Array:
	if enemy == _monster():
		if stage == Stage.MONSTER_CUE or monster_trapped:
			return []
		# Follow the escaping player rather than an idle teammate left behind.
		var leading: MayoPlayer
		for candidate in targets:
			if leading == null or candidate.global_position.z < leading.global_position.z:
				leading = candidate
		return [leading] if leading != null else []
	return targets

func _monster() -> MayoEnemy:
	return world.enemy_at(monster_index) if monster_index >= 0 else null

func _effect(kind: int) -> void:
	var at := _monster().global_position if _monster() != null else Vector3.ZERO
	world.tutorial_effect(kind, at)

func apply_effect(kind: int) -> void:
	if kind == 0:
		stomps_heard += 1
	else:
		impacts_heard += 1

func choose_station(stations: Array) -> void:
	_initial_station = world._tutorial_start_station
	_station = _initial_station
	if _station >= 0 and _station < stations.size():
		_station_position = stations[_station]["position"]

func _pick_refill_station() -> void:
	var best := INF
	var stations: Array = world.refill_stations()
	for index in stations.size():
		var at: Vector3 = stations[index]["position"]
		if at.z >= TutorialWreck.SPILL_BACK - 1.0:
			continue
		var distance := at.distance_squared_to(TutorialWreck.EXIT)
		if distance < best:
			best = distance
			_station = index
			_station_position = at

func station_index() -> int:
	return _station

func refill_is_open() -> bool:
	return stage == Stage.GET_SAUCE or _refill_open and stage in [Stage.TRAPPED, Stage.REFILL]

func note_refill(peer_id: int, station: int) -> void:
	if not _is_authority():
		return
	# Picking up a bottle is personal, including a late joiner. Replenishing
	# at another normal stall must still work even when it is not the objective.
	if not acquired.has(peer_id):
		acquired.push_back(peer_id)
	if _refill_open and refill_is_open() and station == _station and not supplied.has(peer_id):
		supplied.push_back(peer_id)
	_push_state()

func peer_joined(peer_id: int) -> void:
	if not _is_authority():
		return
	var shooter = world.shooter_for(peer_id)
	if stage in [Stage.IDLE, Stage.GET_SAUCE]:
		shooter.sauce = 0.0
	elif not acquired.has(peer_id):
		acquired.push_back(peer_id)
	_push_state()

func peer_left(peer_id: int) -> void:
	acquired.erase(peer_id)
	supplied.erase(peer_id)
	slipped.erase(peer_id)
	if _is_authority():
		_push_state()

func marker_position() -> Vector3:
	if stage in [Stage.IDLE, Stage.GET_SAUCE]:
		return _station_position
	if stage in [Stage.MONSTER_ARRIVES, Stage.RUN]:
		return TutorialWreck.EXIT + Vector3.UP * 1.2
	if refill_is_open():
		return _station_position
	return Vector3.INF

func marker_label() -> String:
	if stage in [Stage.IDLE, Stage.GET_SAUCE]:
		return "소스 챙기기 · E"
	if stage in [Stage.MONSTER_ARRIVES, Stage.RUN]:
		return "포장마차 사이로 · Shift"
	return "소스 보충 · E"

func marker_color() -> Color:
	return Color("4fc3ff") if stage in [Stage.IDLE, Stage.GET_SAUCE] else Color("8fe38f")

func threat_position() -> Vector3:
	if stage in [Stage.MONSTER_CUE, Stage.MONSTER_ARRIVES, Stage.RUN] and _monster() != null:
		return _monster().global_position
	return Vector3.INF

func objective_text() -> String:
	match stage:
		Stage.IDLE, Stage.GET_SAUCE:
			return "WASD로 앞 포장마차에 이동 → E로 소스 챙기기"
		Stage.FIRST_FIGHT:
			return "마우스 왼쪽 버튼을 눌러 토스트에 소스를 뿌리세요"
		Stage.MONSTER_CUE, Stage.MONSTER_ARRIVES:
			return "뒤에서 큰 발소리가 들립니다 · 마우스로 뒤를 확인하세요"
		Stage.RUN:
			if world._local != null and slipped.has(world._local.peer_id):
				return "Shift를 놓고 마요네즈 위를 걸어서 빠져나가세요"
			return "Shift를 누른 채 포장마차 사이로 달리세요"
		Stage.TRAPPED:
			if _refill_open:
				return "E로 소스통 채우기"
			return "괴물이 끼었습니다 · 마요네즈 위에서는 걷기" if monster_trapped else "마요네즈 위에서는 걷기"
		Stage.REFILL:
			return "표시된 매대에서 E로 소스통 채우기 (%d/%d)" % [supplied.size(), world.party_size()]
		Stage.COOP_FIGHT:
			return "소스를 뿌려 포장마차에 낀 괴물을 처치하세요"
		Stage.OUTRO, Stage.COMPLETE:
			return "박사와 함께 다음 먹거리 구역으로"
	return ""

func current_speaker() -> String:
	if _line in [SAY_BEHIND_YOU, SAY_RUN, SAY_TRAPPED, SAY_WALK, SAY_GO_REFILL, SAY_CROSSED, SAY_EARLY_CLEAR]:
		return "낯선 목소리"
	return "박사" if _line in DOCTOR_LINES else "뚱보"

func current_line_id() -> int:
	return _line

func current_line() -> String:
	return LINES[_line] if _line >= 0 and _line < LINES.size() else ""

func current_line_alpha() -> float:
	return clampf(_line_left / 0.35, 0.0, 1.0)

func _line_began(line_id: int) -> void:
	if line_id == SAY_GO_REFILL:
		_refill_open = true
		if _is_authority():
			_push_state()

func _lines_done() -> bool:
	return _line_queue.is_empty() and _line_left <= 0.0

## Versioned, bounded state. Parse completely before changing the replica so a
## truncated snapshot cannot partially mutate progression or player ownership.
func state() -> PackedInt32Array:
	var data := PackedInt32Array([2, stage, monster_index, int(monster_trapped),
		_station, int(_refill_open), roundi(trap_position.x * 100),
		roundi(trap_position.y * 100), roundi(trap_position.z * 100)])
	for values in [fight_enemies, acquired, supplied, slipped]:
		data.push_back(values.size())
		data.append_array(PackedInt32Array(values))
	return data

func apply_state(data: PackedInt32Array) -> void:
	if data.size() < 13 or data[0] != 2 or data[1] < Stage.IDLE or data[1] > Stage.COMPLETE:
		return
	var groups: Array[Array] = []
	var cursor := 9
	for group in 4:
		if cursor >= data.size():
			return
		var count := data[cursor]
		cursor += 1
		if count < 0 or count > 128 or cursor + count > data.size():
			return
		var values: Array = []
		for index in count:
			values.push_back(data[cursor + index])
		groups.push_back(values)
		cursor += count
	var stations: Array = world.refill_stations()
	if data[4] < 0 or data[4] >= stations.size():
		return
	if stage != data[1]:
		stage = data[1]
		_stage_clock = 0.0
	monster_index = data[2]
	monster_trapped = data[3] == 1
	_station = data[4]
	_station_position = stations[_station]["position"]
	_refill_open = data[5] == 1
	trap_position = Vector3(data[6], data[7], data[8]) / 100.0
	fight_enemies = PackedInt32Array(groups[0])
	acquired.assign(groups[1])
	supplied.assign(groups[2])
	slipped.assign(groups[3])
	if _monster() != null:
		_monster().set_tutorial_trapped(monster_trapped, trap_position)

func _push_state() -> void:
	world.tutorial_broadcast_state()


func _spawn_monster() -> void:
	if monster_index >= 0:
		return
	var centre := Vector3.ZERO
	var backs := Vector3.ZERO
	var counted := 0
	for peer_id in world.shooter_ids():
		var shooter = world.call("shooter_for", peer_id)
		if shooter == null:
			continue
		var player: MayoPlayer = shooter.player
		if player == null or not is_instance_valid(player):
			continue
		centre += player.global_position
		# A body's front is its -z, so its back is +z in its own basis.
		var back: Vector3 = player.global_basis.z
		back.y = 0.0
		if back.length_squared() > 0.000001:
			backs += back.normalized()
		counted += 1
	if counted == 0:
		return
	centre /= float(counted)
	if backs.length_squared() < 0.000001:
		# Everyone facing exactly opposite ways: fall back to down the street,
		# which is the way they came in.
		backs = Vector3.BACK
	backs = backs.normalized()

	monster_index = world.call("tutorial_spawn_enemy", KIND_BRUISER,
		_behind_the_party(centre, backs))
	_push_state()


## Somewhere behind `centre`, facing `backs`, that a body can actually stand.
##
## Swung around the back arc before being brought closer, so a party with a wall
## straight behind them gets the burger over their shoulder rather than on top of
## them. Distance is given up last and never below `MONSTER_NEAREST`: a burger
## spawned inside the party is worse than one at a slight angle.
func _behind_the_party(centre: Vector3, backs: Vector3) -> Vector3:
	var reach := MONSTER_BEHIND
	while reach >= MONSTER_NEAREST:
		for degrees in MONSTER_ARC_STEPS:
			var way: Vector3 = backs.rotated(Vector3.UP, deg_to_rad(degrees))
			var at: Vector3 = centre + way * reach
			at.y = 0.0
			if world.call("tutorial_can_stand_at", at):
				return at
		reach -= MONSTER_CLEAR_STEP
	# Nothing in the whole arc: straight back at the shortest allowed distance,
	# which at least keeps it off them.
	var last: Vector3 = centre + backs * MONSTER_NEAREST
	last.y = 0.0
	return last


func _say(line_id: int, tag := TAG_NONE) -> void:
	if not _is_authority():
		return
	_line_queue.push_back([line_id, tag])
	lines_shown += 1
	world.call("tutorial_broadcast_line", line_id, false, tag)


## A line that cannot wait its turn.
##
## Warnings replace queued banter so the player hears them while the danger is
## relevant. This changes only captions; movement and aiming stay live.
func _say_now(line_id: int, tag := TAG_NONE) -> void:
	if not _is_authority():
		return
	_line_queue.clear()
	_line = line_id
	_line_tag = tag
	_line_left = URGENT_LINE_SECONDS
	_line_gap = 0.0
	lines_shown += 1
	_line_began(line_id)
	world.call("tutorial_broadcast_line", line_id, true, tag)


## Withdraws everything queued under `tag`, and takes it off the screen if it is
## up. Explanations are untagged, so nothing that still needs saying is lost.
func _cancel(tag: int) -> void:
	_drop_tag(tag)
	if _is_authority():
		world.call("tutorial_broadcast_cancel", tag)


## Everyone's side of that, the server's own included.
func _drop_tag(tag: int) -> void:
	if tag == TAG_NONE:
		return
	var kept: Array[Array] = []
	for entry in _line_queue:
		if int(entry[1]) != tag:
			kept.push_back(entry)
	_line_queue = kept
	if _line >= 0 and _line_tag == tag:
		_line = -1
		_line_tag = TAG_NONE
		_line_left = 0.0
		_line_gap = LINE_GAP


func cancel_lines(tag: int) -> void:
	_drop_tag(tag)


## The client's side, and the server's own: a line to put on screen.
func show_line(line_id: int, urgent := false, tag := TAG_NONE) -> void:
	if line_id < 0 or line_id >= LINES.size():
		return
	if _is_authority():
		# Already queued by `_say`; the broadcast is for everyone else.
		return
	lines_shown += 1
	if urgent:
		_line_queue.clear()
		_line = line_id
		_line_tag = tag
		_line_left = URGENT_LINE_SECONDS
		_line_gap = 0.0
		_line_began(line_id)
		return
	_line_queue.push_back([line_id, tag])


func _advance_lines(delta: float) -> void:
	if _line_left > 0.0:
		_line_left = maxf(_line_left - delta, 0.0)
		if _line_left <= 0.0:
			_line_gap = LINE_GAP
		return
	if _line_gap > 0.0:
		_line_gap = maxf(_line_gap - delta, 0.0)
		return
	if _line_queue.is_empty():
		_line = -1
		_line_tag = TAG_NONE
		return
	var entry: Array = _line_queue.pop_front()
	_line = int(entry[0])
	_line_tag = int(entry[1])
	_line_left = LINE_SECONDS
	_line_began(_line)
