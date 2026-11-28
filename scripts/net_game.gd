class_name MayoNet
extends Node

const SauceParts := preload("res://scripts/tomatina_sauce_parts.gd")

## LAN session for two players over ENet. One peer hosts, the other types an IP.
## There is no lobby and no matchmaking: pressing Host opens the port, and the
## first peer to connect is the second player.
##
## What crosses the wire, and what does not:
##
##   * Movement is the server's. Clients send keys and aim and nothing else;
##     the server runs both bodies and sends back where they ended up, along
##     with the fall state and its timer, so a fall plays out identically on
##     both screens. Tomatina predicts the local player's movement and replays
##     unacknowledged inputs after server correction. Other maps keep snapshot
##     movement. Aim is always immediate; damage and kills remain authoritative.
##   * The mid-air strand is not synchronised at all. Every peer simulates
##     every shooter from the aim it already has for them, so a burst costs a
##     boolean and a pitch per tick rather than a point cloud. The strands
##     differ by centimetres between machines, which is deliberate.
##   * The grid is the server's alone, and it is exact. When a strand lands,
##     the server paints and puts the splat's *centre cell* in the frame's
##     batch; every peer replays those cells through the same deterministic
##     paint. Two ints per splat, and byte-identical grids -- probe_determinism
##     is what holds that guarantee up.
##   * Slipping is decided by the server, off its own grid and its own bodies.
##     Clients only ever see the resulting fall state.

const DEFAULT_PORT := 24565
## What one peer may send per tick. A client sends one input a tick, but they do
## not arrive one a tick: a hitch on either end lands two in one host tick and
## none in the next. Keeping only the first of a pair threw away the newer keys
## and stepped the body on the older ones twice, which is a correction on the
## client's screen every time it happened -- the stutter moving left, right,
## forward and jumping. So up to three may land in one tick, but the allowance
## only drains by one a tick -- see `apply_client_input` -- so the sustained rate
## is still one a tick and a flood is still dropped.
const INPUT_PACKETS_PER_TICK := 3
## Floats in one player's office-range state (`MayoPrototype.EMBEDDED_STATE_SIZE`).
const RANGE_STATE_SIZE := 20
## How often one peer may be sent the office's marks, and the largest surface accepted.
const RANGE_SNAPSHOT_INTERVAL := 3.0
const RANGE_GRID_MAX_BYTES := 8 * 1024 * 1024
var _range_snapshot_sent: Dictionary = {}
## How many unplayed inputs the host holds per client. Each tick plays the oldest
## one, so every input the client predicted with is played once, in order, the
## same number of times the client played it. Past this many the oldest goes:
## a client whose clock runs a touch fast must not build up latency.
const INPUT_QUEUE_LIMIT := 3
## Wipes are rarer and travel reliably, which makes them the more expensive
## thing to flood. A wipe takes wipe_duration to finish and cannot be started
## during one, so nobody can legitimately complete more than about 1.4 a second;
## five leaves room for mashing the key and for retries without leaving the
## reliable channel open to abuse.
const WIPE_REQUESTS_PER_SECOND := 5.0
## Same idea for bottle selection: repeated number keys cost the peer bandwidth
## and the host a dictionary lookup.
const REFILL_REQUESTS_PER_SECOND := 5.0
## The same idea for view reports. A report is state, not an event: only the
## latest one matters, and it changes when a player resizes their window, which
## is the only thing that can produce a run of them. A resize drag emits an event
## a frame, so the client coalesces to the current value and sends at most this
## often; four a second leaves the mask at most a quarter of a second stale after
## a drag ends -- far below noticing -- while a peer that sends more is ignored.
const VIEW_REPORTS_PER_SECOND := 4.0
## What a peer is allowed to claim its camera is. Outside this the value is
## brought to the edge rather than dropped: an unusual window is not an attack,
## and a session that refuses to draw on it would be worse than one that draws
## on it slightly wrongly. 21:9 is the widest shipped desktop ratio; 4:3 the
## narrowest anything is still sold in.
const MIN_FOV_DEGREES := 60.0
const MAX_FOV_DEGREES := 110.0
const MIN_ASPECT := 4.0 / 3.0
const MAX_ASPECT := 21.0 / 9.0
## How long a peer has to prove it knows the code before it is dropped.
const AUTH_TIMEOUT := 3.0
const AUTH_REASON_GRACE := 0.2
## What a generated code is made of. No 0 or O, no 1, I or L: the code is read
## off one screen and typed into another, and those are the pairs that get read
## wrong. Five characters of this is about 28 million codes, which is far more
## than guessing gets through at five tries a minute.
const CODE_ALPHABET := "23456789ABCDEFGHJKMNPQRSTUVWXYZ"
const CODE_LENGTH := 5
## Wrong codes allowed from one address before it is made to wait. Five a minute
## leaves room for typing it wrong and reading it back off a chat window; it does
## not leave room for working through the alphabet.
const CODE_ATTEMPTS := 5
const CODE_ATTEMPT_WINDOW := 60.0
## How long each block lasts, in order. An address is blocked every time it gets
## another five wrong, and each block is longer than the last.
##
## The first one is short on purpose. Players behind one router share an address,
## so a friend reading the code off a chat window and mistyping it can put the
## whole house behind the same block; half a minute is an annoyance, five minutes
## is the evening. An address that comes back and does it again is not somebody
## mistyping, and the wait climbs accordingly.
##
## NOTE: when the session moves to the Steam relay, this is keyed on the Steam ID
## instead of the address. That is the right key and the reason for this one --
## an address is all ENet knows about who is knocking -- and it takes the
## shared-router problem with it.
const CODE_BLOCK_LADDER := [30.0, 120.0, 300.0]
## How long after a block runs out the address is remembered for. Come back
## inside this and the next block is the next rung; stay away and the ladder
## starts again from the bottom.
const CODE_BLOCK_MEMORY := 900.0
## How often expired records are swept, so neither dictionary grows with every
## address that ever knocked.
const CODE_SWEEP_SECONDS := 60.0
## What a blocked address is told, and how long it has left. Saying so beats
## dropping it without a word: a player who mistyped the code should find out
## that they have to wait rather than that the game is broken.
const AUTH_BLOCKED_PREFIX := "mayo1-blocked:"
const AUTH_FULL_PREFIX := "mayo1-full:"
## The wire format this build speaks, and the answer a host gives a guest
## that speaks another. **Bumped whenever an RPC is added, removed or renamed.**
## Godot numbers a node's RPCs by sorted name, so two builds that disagree on
## the list deliver each other's packets to the wrong methods: a guest on the
## older build gets into the truck -- the handshake is not an RPC -- and then
## stands there, its keys arriving at a method that throws them away. The tag
## rides in the handshake payload so the mismatch is turned away with a reason
## before it can become a player.
const PROTOCOL_VERSION := 38
const STAGE_INPUT_TIMEOUT := 0.25
const MOTION_REFRESH_SECONDS := 0.25
const ENEMY_SNAPSHOT_BATCH_SIZE := 36
const ENEMY_SNAPSHOT_NEAR_DISTANCE := 42.0
const ENEMY_SNAPSHOT_FAR_PERIOD := 5
const ENEMY_SNAPSHOT_REFRESH_PERIOD := 20
var _tomatina_snapshot_phase := 0
var _tomatina_snapshot_number := 0
var _inventory_sent := PackedInt32Array()
var _inventory_peers := PackedInt32Array()
var _motion_sent := PackedFloat64Array()
var _motion_refresh_at := 0.0
var _enemy_snapshots_by_peer := {}
var _enemy_snapshot_batches: Dictionary[int, PackedFloat32Array] = {}
var _enemy_snapshot_scratch := PackedFloat32Array()
const AUTH_VERSION_PREFIX := "mayo-version:"
## How often one address is worth answering. A blocked address can reconnect as
## fast as its machine allows, and an answer to each would be a packet out for
## every packet in -- a reflector pointed at whoever the attacker claims to be.
## One a second is plenty for a person pressing a button.
const BLOCK_REPLIES_PER_SECOND := 1.0
## Three guests and the host: four players. The droplet pool and the state
## packet are both sized against this -- see POOL_SIZE in mayo_prototype.gd.
const MAX_CLIENTS := 3
## Floats per player in a state packet: position xyz, yaw, velocity xz, firing,
## aim pitch, fall state, fall timer, fall direction, wipe timer, health, sauce
## level, nozzle state, character index. The peer ids travel alongside as ints -- a peer id is a
## full 32-bit random number and does not survive a round trip through a 32-bit
## float.
##
## The last two are why this grew. Everything else about a squirt follows from
## the trigger flag every peer already has, but an unreliable nozzle catches on
## a coin toss, and a coin tossed separately on each machine gives every player
## a different fight. The host tosses it and sends the answer; the level rides
## along rather than being derived, so nobody has to guess which band a bottle
## is in either.
const STATE_STRIDE := 29
const STATE_CHARACTER_INDEX := 17
## Where one occupant is standing in the truck: x, y, z and the yaw they are
## facing. The truck carries no bottle, no health and no aim pitch, so it needs
## none of the sixteen floats a stage body does -- four, four times a frame at
## the four-player maximum, is 80 bytes of pose a frame against the stage's 272.
const LOBBY_POSE_STRIDE := 4
const LOBBY_INPUT_TIMEOUT := 0.25
## What that costs the host. One player is 16 floats plus a 4-byte id, so 68
## bytes; a four-player session is 272 bytes of state a frame, and the host sends
## it to each of the three guests at the physics rate:
##
##     4 x 68 x 3 guests x 60 Hz = 49.0 kB/s of state
##
## The splats ride alongside on the reliable channel, 16 bytes each. Four players
## all hosing the floor land about 750 points a second between them:
##
##     750 x 16 x 3 guests      = 36.0 kB/s of splats
##
## The enemies ride along on the same tick, 5 floats each, which at one enemy is
## 20 bytes a frame per guest -- 3.6 kB/s for a full session, and a rounding
## error next to the two above until there are dozens of them.
##
## so roughly 75 kB/s of payload, near 0.6 Mbit/s up once ENet, UDP and IP
## headers are on it -- with every player firing without pause, which is the
## worst case rather than the usual one. Measured, four peers doing exactly
## that: 36.6 kB/s of state and 30.5 kB/s of splats, 67 kB/s in all.
## state_bytes_sent and splat_bytes_sent count it; probe_harness prints both.

signal status_changed(message: String)
signal lobby_joined
signal roster_changed
signal transition_requested(stage_id: String, transition_id: int)
signal play_authorized(transition_id: int)
signal transition_failed(reason: String)
signal result_ready(summary: Dictionary)
signal result_votes_changed(ready: int, total: int)
signal truck_returned
signal session_ended(reason: String)
signal late_join_waiting
## 방장 쪽에서만: 사무실에서 팀 돈이 바뀌었다(슬롯머신 등). 앱이 저장 파일에 적는다.
signal team_money_spent
## 누군가 슬롯머신을 돌린 결과. 사무실에 있는 전원에게 온다. `gain`은 팀 돈이 변한 양이고,
## 그중 `pot`은 터뜨려 받은 잭팟이다.
signal slot_result(peer_id: int, bet: int, gain: int, reels: PackedInt32Array, pot: int, request_id: int)
signal slot_spin_rejected(request_id: int)
## The host cut the arrival shot short, for everybody.
signal intro_skipped(transition_id: int)

enum SessionPhase { OFFLINE, TRUCK, LOADING, STAGE, RESULT }
const BUSY_PREFIX := "mayo1-busy:"
const LOAD_TIMEOUT := 20.0
const STAGE_LOAD_FAILED := "stage scene could not be loaded"
const STAGE_LOAD_TIMEOUT := "stage loading timed out; returned to truck"

## The lobby code both ends must agree on. Checked during the handshake, before
## a peer is a peer at all: a guest that gets it wrong is disconnected without
## ever reaching the world, so none of the RPCs above are exposed to it. Empty
## means an open session.
var lobby_code := ""
var world: Node

var _peer: ENetMultiplayerPeer
var _online := false
var _status := "offline"
## peer id -> the last input packet from that client, applied every tick until
## the next one arrives so a dropped packet coasts instead of stuttering.
var _client_input: Dictionary = {}
var _stage_input_received_at: Dictionary = {}
## peer id -> inputs received and not yet played, oldest first.
var _input_queue: Dictionary = {}
## peer id -> how many input packets it has sent this tick, and how much wipe
## budget it has left. A peer that goes over is ignored rather than answered:
## nothing is sent back, so flooding costs the flooder and not the host.
var _input_this_tick: Dictionary = {}
var _wipe_budget: Dictionary = {}
var _refill_budget: Dictionary = {}
var _view_budget: Dictionary = {}
## When the two budgets above were last topped up, on the wall clock.
var _budget_clock := 0.0
## Peer id -> the clamped Vector2(fov degrees, aspect) the host is painting that
## peer's lenses with.
var _views: Dictionary = {}
## The last view this peer sent, and the one it wants to send. Held apart so a
## resize that arrives while the budget is spent is still sent afterwards rather
## than lost.
var _view_sent := Vector2.ZERO
var _view_pending := Vector2.ZERO
var _view_cooldown := 0.0
## Whether the host has answered the last report. Until it has, the report is
## sent again: the first one goes out the moment the connection comes up, which
## is exactly when a packet is most likely to go nowhere, and a peer whose report
## was lost is painted on a camera it is not using.
var _view_acked := false
## Which spawn each peer has. The host is always slot 0. Slots are handed back
## when a peer leaves and reused by the next one, so a session someone keeps
## rejoining does not walk its spawns off into the distance -- a counter that
## only went up ran out of spawn points after four joins however few players
## were actually in.
var _slots: Dictionary = {1: 0}
var debug_state_packets := 0
## Client packets thrown away for carrying a value that is not a number.
var rejected_packets := 0
## And thrown away for arriving faster than a peer is allowed to send.
var dropped_packets := 0
## Peers turned away at the handshake for not knowing the code.
var refused_peers := 0
## And those turned away for running a different build of the game.
var version_refusals := 0
## And those turned away without being asked, because their address is waiting
## out a run of wrong ones.
var blocked_attempts := 0
## Address -> [wrong codes so far, when that run started].
var _code_failures: Dictionary = {}
## Blocked peers that were answered rather than merely dropped.
var blocked_replies := 0
## Address -> when it was last answered, so answering cannot be made into a flood.
var _block_replies: Dictionary = {}
## Peers that have been told why and are dropped on the next frame.
var _pending_drops: Array[int] = []
var _pending_drop_after: Dictionary = {}
## On a guest: when the host says it may knock again.
var _blocked_until_local := 0.0
## Address -> [when it may try again, how many times it has been blocked].
var _blocks: Dictionary = {}
var _next_sweep := 0.0
## Payload the host has put on the wire, in bytes, for the two broadcasts that
## scale with the session. Headers are not counted: this is what the game asks
## for, not what the socket ends up sending.
var state_bytes_sent := 0
var splat_bytes_sent := 0
var _refused_for_code := false
## Whether this peer got past the handshake into the session.
var _joined := false
var lobby_flow := false
var session_phase: int = SessionPhase.OFFLINE
var selected_stage := "stage_1"
## 팀 공용 돈·전리품·축제별 완료 횟수. 원본은 방장의 저장 파일이고(`SauceSaveStore`),
## 방장이 `set_team_progress`로 올리면 사무실에 있는 팀원에게 명단과 함께 간다.
var team_money := 0
var team_trophies := PackedStringArray()
var team_clears: Dictionary = {}
## 슬롯머신에 쌓인 잭팟. 팀 돈과 함께 방장의 저장 파일에 있다.
var team_jackpot := 0
var _lobby_ready: Dictionary = {}
## Which of the four characters each player picked at the truck's door, peer id
## -> index. The same index means the same character in the truck
## (`TruckLobby.CHARACTER_SCENES`) and in the stage (`PLAYER_CHARACTERS`), so
## one number carries a player's look through both. The host's copy is the one
## that counts; it rides to the guests with the roster in `_sync_lobby`. A peer
## with no entry has not picked yet and is shown as the character its seat
## would have had -- see `character_of`.
var _characters: Dictionary = {}
const CHARACTER_COUNT := 4
## Set by the app, which puts a character select between joining and the truck.
## With it set a guest no longer calls itself ready the moment it is accepted:
## it is ready when its truck is up (`report_lobby_initialized`), which is
## after it has picked. Otherwise the host could start the stage while a guest
## was still looking at four characters. Off by default, so a session driven
## without the app is ready on acceptance as it always was.
var defer_lobby_ready := false
## The truck the party is riding in, while the session sits in its lobby phase.
## It is bound by the TruckLobby itself rather than through `bind`, which is the
## combat world's: the two spaces never exist at the same time, and the truck
## shares none of the world's interface beyond the three occupant calls below.
var lobby_space: Node
## peer id -> the last [move, yaw] a client sent from the truck, applied every
## tick until the next one arrives, exactly as `_client_input` is in the stage.
var _lobby_input: Dictionary = {}
var _transition_id := 0
var _transition_roster := PackedInt32Array()
var _loaded_peers: Dictionary = {}
var _result_continue: Dictionary = {}
var _load_clock := 0.0
var _refused_busy := false
var _refused_full := false
var _refused_version := false
var hosted_port := DEFAULT_PORT
var _lobby_broadcast_at := 0.0
var _waiting_peers := {}
var _late_loading := {}
var _receiving_late_snapshot := false
var _late_syncing := {}


func bind(new_world: Node) -> void:
	if world != new_world:
		_enemy_snapshots_by_peer.clear()
		_enemy_snapshot_batches.clear()
		_tomatina_snapshot_number = 0
		_tomatina_snapshot_phase = 0
		_clear_stage_input()
		_reset_inventory_and_motion()
	world = new_world


func _world_ready() -> bool:
	return world != null and (not lobby_flow or session_phase == SessionPhase.STAGE or _receiving_late_snapshot)


## The truck tells the session it exists, and takes it back on the way out. A
## stale pointer here would have the host walking bodies in a freed scene one
## frame into the stage load.
func bind_lobby(space: Node) -> void:
	lobby_space = space
	_lobby_input.clear()


func unbind_lobby(space: Node) -> void:
	if lobby_space == space:
		lobby_space = null
		_lobby_input.clear()


func _lobby_space_ready() -> bool:
	return is_instance_valid(lobby_space) and not lobby_space.is_queued_for_deletion() \
		and (not lobby_flow or session_phase == SessionPhase.TRUCK)


func begin_host_room(port := DEFAULT_PORT, code := "", open_to_anyone := false,
		stage_id := "stage_1") -> bool:
	if _online:
		return false
	var from_solo := lobby_flow and session_phase == SessionPhase.TRUCK
	var previous_code := lobby_code
	lobby_flow = true
	lobby_code = code.strip_edges()
	if not host(port, open_to_anyone):
		lobby_flow = from_solo
		lobby_code = previous_code
		return false
	selected_stage = stage_id
	if not from_solo:
		session_phase = SessionPhase.TRUCK
		_joined = true
		_slots = {1: 0}
		_lobby_ready = {1: true}
		_characters.clear()
		lobby_joined.emit()
	roster_changed.emit()
	return true


## 혼자하기: a room of one that opens no port. Everything the app asks of a
## room -- the office, the pick, the festival, the start, the result vote --
## runs the same way, with this peer as the only seat and the only authority.
func begin_solo_room(stage_id := "stage_1") -> bool:
	if _online or lobby_flow:
		return false
	lobby_flow = true
	selected_stage = stage_id
	lobby_code = ""
	session_phase = SessionPhase.TRUCK
	_joined = true
	_slots = {1: 0}
	_lobby_ready = {1: true}
	_characters.clear()
	_set_status("solo")
	lobby_joined.emit()
	roster_changed.emit()
	return true


func begin_join_room(address: String, port := DEFAULT_PORT, code := "") -> bool:
	lobby_flow = true
	lobby_code = code.strip_edges()
	_characters.clear()
	_debug_host = false  # DEBUG
	_refused_busy = false
	_refused_full = false
	_refused_version = false
	var connected := join(address, port)
	if not connected:
		lobby_flow = false
	return connected


func cancel_join() -> void:
	if _online and not _joined:
		leave()
		_set_status("connection cancelled")


func phase() -> int:
	return session_phase


func seat_assignments() -> Dictionary:
	return _slots.duplicate()


## The character a player is wearing: the one they picked, or -- until they
## have -- the one their seat used to decide, so a body that has to be drawn
## before its owner has chosen is still drawn as somebody.
func character_of(peer_id: int) -> int:
	if _characters.has(peer_id):
		return clampi(int(_characters[peer_id]), 0, CHARACTER_COUNT - 1)
	return posmod(int(_slots.get(peer_id, 0)), CHARACTER_COUNT)


func has_character(peer_id: int) -> bool:
	return _characters.has(peer_id)


## Only the players who have actually picked, peer id -> index.
func character_assignments() -> Dictionary:
	return _characters.duplicate()


## This peer's pick. No two players wear the same character, and the host is
## the one who says who got there first: the host (and a solo room) takes a
## free one at once, a guest asks and hears back in the next `_sync_lobby`.
## Until then a guest's own entry does not change -- a pick that lost the race
## is simply never applied. Returns false when it is known here to be taken.
func choose_character(index: int) -> bool:
	var mine := local_id()
	if not _can_choose_character(mine, index):
		return false
	if int(_characters.get(mine, -1)) == index:
		return true
	if is_server():
		_commit_character(mine, index)
		_broadcast_lobby()
	else:
		_choose_character.rpc_id(1, index)
	return true


func _can_choose_character(peer_id: int, index: int) -> bool:
	return lobby_flow and _joined and _slots.has(peer_id) \
		and session_phase in [SessionPhase.TRUCK, SessionPhase.STAGE] \
		and index >= 0 and index < CHARACTER_COUNT and not character_taken(index, peer_id)


func _commit_character(peer_id: int, index: int) -> void:
	_characters[peer_id] = index
	_apply_world_character(peer_id)


func _apply_world_character(peer_id: int) -> void:
	if world == null or session_phase != SessionPhase.STAGE:
		return
	var index := character_of(peer_id)
	if peer_id == local_id():
		world.set_local_character(index)
	else:
		world.set_character_variant(peer_id, index)


## Whether somebody other than `except` is wearing character `index`.
func character_taken(index: int, except := 0) -> bool:
	for id in _characters:
		if int(id) != except and _slots.has(id) and int(_characters[id]) == index:
			return true
	if not _online and _world_ready() and world.has_meta("bot_practice"):
		for id in world.shooter_ids():
			if not _slots.has(id) and world.shooter_for(id).character_index == index:
				return true
	return false


## Every seated player has picked. The host's start waits on this and on
## nothing else a player can dawdle over.
func all_characters_chosen() -> bool:
	for id in _slots:
		if not _characters.has(id):
			return false
	return not _slots.is_empty()


func can_start_stage() -> bool:
	return lobby_flow and is_server() and all_lobby_ready() and all_characters_chosen()


## 검사용: 0 이상이면 슬롯머신이 난수 대신 이 값으로 배당을 뽑는다(`OfficeSlot.multiplier_for`).
var slot_pick_override := -1.0
var _slot_rng := RandomNumberGenerator.new()


## 해금한 파츠가 바뀌었다(`team_parts`).
signal team_parts_changed
## 사무실 소품의 상태가 바뀌었다(`office_props`).
signal office_props_changed
## 팀이 사무실 작업대에서 해금한 파츠, 비트마다 하나(`TomatinaSauceParts.UNLOCK_PRICES`).
## 원본은 방장의 저장 파일이고 팀원에게는 명단과 함께 간다.
var team_parts := 1
## 사무실 소품의 켜고 끈 상태, 비트마다 하나(`OfficeLobby.PROP_*`). 누구나 바꾸고 모두에게 보인다.
var office_props := 0


## 작업대에서 `part`를 해금한다: 팀 돈에서 값을 치른다. 사무실에 있는 누구나 할 수 있고
## 셈은 방장이 한다. 팀원이 부르면 요청만 보낸다(답은 `team_parts_changed`).
func request_part_unlock(part: int) -> bool:
	if not lobby_flow or session_phase != SessionPhase.TRUCK or not _can_unlock(part):
		return false
	if is_server():
		return _resolve_part_unlock(local_id(), part)
	_request_part_unlock.rpc_id(1, part)
	return true


func _can_unlock(part: int) -> bool:
	return part > 0 and part < SauceParts.UNLOCK_PRICES.size() \
		and not SauceParts.is_unlocked(team_parts, part) \
		and team_money >= int(SauceParts.UNLOCK_PRICES[part])


@rpc("any_peer", "call_remote", "reliable")
func _request_part_unlock(part: int) -> void:
	if multiplayer.is_server():
		_resolve_part_unlock(multiplayer.get_remote_sender_id(), part)


func _resolve_part_unlock(peer_id: int, part: int) -> bool:
	if not is_server() or session_phase != SessionPhase.TRUCK or not _slots.has(peer_id) \
			or not _can_unlock(part):
		return false
	team_money -= int(SauceParts.UNLOCK_PRICES[part])
	team_parts |= 1 << part
	team_money_spent.emit()
	_broadcast_lobby()
	team_parts_changed.emit()
	return true


## 사무실 소품 하나(`bit`)를 켜거나 끈다. 사무실에 있는 누구나.
func request_office_prop(bit: int, on: bool) -> bool:
	if not lobby_flow or session_phase != SessionPhase.TRUCK or bit <= 0 or bit > 0xffff:
		return false
	if is_server():
		_set_office_prop(bit, on)
	else:
		_request_office_prop.rpc_id(1, bit, on)
	return true


@rpc("any_peer", "call_remote", "reliable")
func _request_office_prop(bit: int, on: bool) -> void:
	if multiplayer.is_server() and _slots.has(multiplayer.get_remote_sender_id()) \
			and session_phase == SessionPhase.TRUCK and bit > 0 and bit <= 0xffff:
		_set_office_prop(bit, on)


func _set_office_prop(bit: int, on: bool) -> void:
	var next := (office_props | bit) if on else (office_props & ~bit)
	if next == office_props:
		return
	office_props = next
	for id in _slots.keys():
		if int(id) != 1 and _peer_can_receive(int(id)):
			_sync_office_props.rpc_id(int(id), office_props)
	office_props_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _sync_office_props(props: int) -> void:
	if not multiplayer.is_server():
		office_props = props
		office_props_changed.emit()


## 슬롯머신 앞에 앉은 사람이 바뀌었다(`slot_user`).
signal slot_user_changed
signal slot_seat_answered(request_id: int, granted: bool)
## 지금 슬롯머신을 쓰고 있는 사람의 peer id. 아무도 없으면 0. 기계는 하나라 한 번에 한 명만
## 쓴다: 자리는 방장이 내주고, 화면을 닫거나 방을 나가면 비운다.
var slot_user := 0


## 방장은 바로 앉고, 팀원은 `slot_seat_answered`로 요청의 결과를 받는다.
func request_slot_seat(request_id := 0) -> bool:
	if not lobby_flow or session_phase != SessionPhase.TRUCK \
			or (slot_user != 0 and slot_user != local_id()):
		return false
	if is_server():
		return _take_slot_seat(local_id())
	_request_slot_seat.rpc_id(1, request_id)
	return true


## 게스트가 승인 전에 닫아도 요청 뒤에 자리 반납이 도착한다. 방장은 현재 사용자만 비운다.
func release_slot_seat() -> void:
	if not lobby_flow:
		return
	if is_server():
		_leave_slot_seat(local_id())
	elif _online:
		_release_slot_seat.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_slot_seat(request_id: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if _slots.has(sender) and _peer_can_receive(sender):
		_slot_seat_answered.rpc_id(sender, request_id, _take_slot_seat(sender))


@rpc("authority", "call_remote", "reliable")
func _slot_seat_answered(request_id: int, granted: bool) -> void:
	if not multiplayer.is_server():
		slot_seat_answered.emit(request_id, granted)


@rpc("any_peer", "call_remote", "reliable")
func _release_slot_seat() -> void:
	if multiplayer.is_server():
		_leave_slot_seat(multiplayer.get_remote_sender_id())


func _take_slot_seat(peer_id: int) -> bool:
	if not is_server() or session_phase != SessionPhase.TRUCK or not _slots.has(peer_id):
		return false
	if slot_user != 0 and slot_user != peer_id and _slots.has(slot_user):
		return false
	_set_slot_user(peer_id)
	return true


func _leave_slot_seat(peer_id: int) -> void:
	if is_server() and slot_user == peer_id and peer_id != 0:
		_set_slot_user(0)


func _set_slot_user(peer_id: int) -> void:
	if slot_user == peer_id:
		return
	slot_user = peer_id
	for id in _slots.keys():
		if int(id) != 1 and _peer_can_receive(int(id)):
			_sync_slot_user.rpc_id(int(id), slot_user)
	slot_user_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _sync_slot_user(peer_id: int) -> void:
	if not multiplayer.is_server():
		slot_user = peer_id
		slot_user_changed.emit()


## 팀 돈 `bet`을 걸고 슬롯머신을 돌린다. 자리에 앉은 사람만 할 수 있고(`request_slot_seat`),
## 굴리는 것은 방장이다.
func request_slot_spin(bet: int, request_id := 0) -> bool:
	if not lobby_flow or session_phase != SessionPhase.TRUCK or bet < 1 or bet > team_money \
			or slot_user != local_id():
		return false
	if is_server():
		return _resolve_slot_spin(local_id(), bet, request_id)
	_request_slot_spin.rpc_id(1, bet, request_id)
	return true


@rpc("any_peer", "call_remote", "reliable")
func _request_slot_spin(bet: int, request_id: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not _resolve_slot_spin(sender, bet, request_id) and _peer_can_receive(sender):
		_slot_spin_rejected.rpc_id(sender, request_id)


@rpc("authority", "call_remote", "reliable")
func _slot_spin_rejected(request_id: int) -> void:
	if not multiplayer.is_server():
		slot_spin_rejected.emit(request_id)


func _resolve_slot_spin(peer_id: int, bet: int, request_id: int) -> bool:
	if not is_server() or session_phase != SessionPhase.TRUCK or not _slots.has(peer_id) \
			or bet < 1 or bet > team_money or slot_user != peer_id:
		return false
	var outcome := OfficeSlot.roll(_slot_rng, slot_pick_override)
	var gain := OfficeSlot.gain_for(bet, outcome.multiplier)
	var pot := 0
	if OfficeSlot.tier_of(outcome.reels) == 4:
		pot = team_jackpot
		team_jackpot = 0
		gain += pot
	elif gain < 0:
		team_jackpot += OfficeSlot.jackpot_share(bet)
	team_money += gain
	team_money_spent.emit()
	_broadcast_lobby()
	for id in _slots.keys():
		if int(id) != 1 and _peer_can_receive(int(id)):
			_slot_result.rpc_id(int(id), peer_id, bet, gain, outcome.reels, pot, request_id)
	slot_result.emit(peer_id, bet, gain, outcome.reels, pot, request_id)
	return true


@rpc("authority", "call_remote", "reliable")
func _slot_result(peer_id: int, bet: int, gain: int, reels: PackedInt32Array, pot: int,
		request_id: int) -> void:
	if not multiplayer.is_server() and reels.size() == 3:
		slot_result.emit(peer_id, bet, gain, reels, pot, request_id)


# -- DEBUG -------------------------------------------------------------------
# 디버그 모드(`scripts/debug_tools.gd`)가 쓰는 것. 걷어낼 때는 "# -- /DEBUG"까지 지운다.

## 디버그 모드가 켜지거나 꺼졌다(이 화면에서 보기에).
signal debug_mode_changed
## 이 플레이어가 켠 디버그 모드. 저장하지 않으므로 게임을 켤 때마다 꺼져 있다.
var _debug_here := false
## 들어가 있는 방의 방장이 켰는가(참가자일 때만 본다).
var _debug_host := false


## 지금 디버그 기능을 쓸 수 있는가: 참가자는 방장이 켰을 때, 그 밖에는 자기가 켰을 때.
func debug_active() -> bool:
	if not SauceDebug.available():
		return false
	return _debug_host if _online and not is_server() else _debug_here


## 디버그 모드를 켜고 끈다. 남의 방에 들어가 있는 참가자는 바꿀 수 없다.
func set_debug_mode(on: bool) -> bool:
	if not SauceDebug.available() or (_online and not is_server()):
		return false
	_debug_here = on
	if _online:
		for id in _slots.keys():
			if int(id) != 1 and _peer_can_receive(int(id)):
				_sync_debug_mode.rpc_id(int(id), on)
	debug_mode_changed.emit()
	return true


@rpc("authority", "call_remote", "reliable")
func _sync_debug_mode(on: bool) -> void:
	if not multiplayer.is_server():
		_debug_host = on
		debug_mode_changed.emit()


## 팀 돈을 그냥 더한다. 디버그 모드가 켜진 방의 사무실에서, 누구나.
func request_debug_money(amount: int) -> bool:
	if not debug_active() or amount <= 0:
		return false
	if is_server():
		return add_team_money(amount)
	_debug_money.rpc_id(1, amount)
	return true


@rpc("any_peer", "call_remote", "reliable")
func _debug_money(amount: int) -> void:
	if multiplayer.is_server() and debug_active() and _slots.has(multiplayer.get_remote_sender_id()):
		add_team_money(clampi(amount, 1, 100000))


## 파츠를 코인·피난처와 무관하게 바로 낀다. 디버그 모드가 켜진 방의 스테이지에서, 누구나.
func request_debug_part(part: int) -> bool:
	if not debug_active() or not _world_ready() or not world.has_method("debug_equip_part"):
		return false
	if is_server():
		return world.debug_equip_part(local_id(), part)
	_debug_part.rpc_id(1, part)
	return true


@rpc("any_peer", "call_remote", "reliable")
func _debug_part(part: int) -> void:
	if multiplayer.is_server() and debug_active() and _world_ready() \
			and world.has_method("debug_equip_part"):
		world.debug_equip_part(multiplayer.get_remote_sender_id(), part)

# -- /DEBUG ------------------------------------------------------------------


## 팀 돈을 그냥 더한다(방장만, 사무실에 있는 동안).
func add_team_money(amount: int) -> bool:
	if not lobby_flow or not is_server() or session_phase != SessionPhase.TRUCK or amount <= 0:
		return false
	team_money += amount
	team_money_spent.emit()
	_broadcast_lobby()
	return true


## 방장이 자기 저장 파일의 돈·전리품을 방에 올린다. 팀원이 부르면 아무 일도 없다.
## `parts`를 주지 않으면(-1) 해금한 파츠는 그대로 둔다.
func set_team_progress(money: int, trophies: PackedStringArray, clears: Dictionary,
		jackpot := 0, parts := -1) -> void:
	if not is_server():
		return
	if parts >= 0:
		team_parts = parts | 1
		team_parts_changed.emit()
	team_money = money
	team_jackpot = maxi(jackpot, 0)
	team_trophies = trophies.duplicate()
	team_clears = clears.duplicate()
	_broadcast_lobby()
	if not lobby_flow:
		roster_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _sync_team_progress(money: int, trophies: PackedStringArray, clears: Dictionary,
		jackpot: int, parts: int) -> void:
	if multiplayer.is_server():
		return
	if (parts | 1) != team_parts:
		team_parts = parts | 1
		team_parts_changed.emit()
	team_money = maxi(money, 0)
	team_jackpot = maxi(jackpot, 0)
	team_trophies = trophies
	team_clears = clears
	roster_changed.emit()


## The festival on the office map. The host's to choose, while the party is
## still in the office; it rides to the guests with the roster.
func set_selected_stage(stage_id: String) -> bool:
	if not lobby_flow or not is_server() or session_phase != SessionPhase.TRUCK \
			or not StageRegistry.has_stage(stage_id):
		return false
	if selected_stage != stage_id:
		selected_stage = stage_id
		_broadcast_lobby()
	return true


func lobby_ready_count() -> int:
	return _lobby_ready.size()


func all_lobby_ready() -> bool:
	return session_phase == SessionPhase.TRUCK and _lobby_ready.size() == _slots.size()


func attach_play_world(new_world: Node) -> void:
	bind(new_world)
	if not lobby_flow or new_world == null:
		return
	new_world.reset_for_join()
	var ids: Array = _slots.keys()
	ids.sort()
	var mine := local_id()
	for id in ids:
		new_world.create_avatar(int(id), int(_slots[id]), int(id) == mine)
	new_world.claim_avatar(mine, int(_slots.get(mine, 0)))
	# Everybody walks out of the truck as who they walked into it as. Dressed
	# here, before the first state packet, so nobody is seen as the default
	# character for the frames it would take the index to arrive.
	for id in ids:
		new_world.set_character_variant(int(id), character_of(int(id)))
	new_world.set_local_character(character_of(mine))
	# The fight is sized for the party that set out, and stays that size: a
	# player who drops mid-stage does not make it easier for the rest.
	new_world.fixed_party_size = ids.size()
	new_world.rescale_enemies()
	new_world.set_gameplay_input_enabled(false)


func report_world_loaded(transition: int) -> void:
	if session_phase != SessionPhase.LOADING or transition != _transition_id:
		return
	if is_server():
		_mark_loaded(local_id(), transition)
	else:
		_report_world_loaded.rpc_id(1, transition)


func report_world_load_failed(transition: int) -> void:
	if session_phase != SessionPhase.LOADING or transition != _transition_id:
		return
	if is_server():
		_fail_loading(STAGE_LOAD_FAILED)
	else:
		_report_world_load_failed.rpc_id(1, transition)


func request_stage_start() -> bool:
	if not lobby_flow or not is_server():
		_set_status("only the host can start")
		return false
	if session_phase != SessionPhase.TRUCK or not all_lobby_ready():
		_set_status("waiting for every player to initialize the lobby")
		return false
	if not all_characters_chosen():
		_set_status("waiting for every player to pick a character")
		return false
	_transition_id += 1
	_transition_roster = PackedInt32Array(_slots.keys())
	_transition_roster.sort()
	_loaded_peers.clear()
	_load_clock = 0.0
	session_phase = SessionPhase.LOADING
	if _online:
		_begin_stage_transition.rpc(selected_stage, _transition_id, _transition_roster)
	transition_requested.emit(selected_stage, _transition_id)
	_set_status("loading %s" % selected_stage)
	return true


## The host cuts the arrival shot short and everybody lands together. A guest
## asking is not answered: the shot is short, and one hand on it is enough.
func request_intro_skip() -> bool:
	if not lobby_flow or not is_server() or session_phase != SessionPhase.STAGE:
		return false
	if _online:
		_skip_intro.rpc(_transition_id)
	intro_skipped.emit(_transition_id)
	return true


@rpc("authority", "call_remote", "reliable")
func _skip_intro(transition: int) -> void:
	if is_server() or transition != _transition_id:
		return
	intro_skipped.emit(transition)


func finish_stage(summary := {}) -> void:
	if not lobby_flow or not is_server() or session_phase != SessionPhase.STAGE:
		return
	session_phase = SessionPhase.RESULT
	_result_continue.clear()
	_waiting_peers.clear()
	_late_loading.clear()
	_late_syncing.clear()
	if _online:
		_show_result.rpc(summary)
	result_ready.emit(summary)
	result_votes_changed.emit(0, _slots.size())


## Every result screen owns one vote.  The host no longer drags guests away
## from statistics they are still reading; the server advances only after the
## current roster has all pressed the same continue button.
func request_result_continue() -> bool:
	if not lobby_flow or session_phase != SessionPhase.RESULT:
		return false
	if is_server():
		return _accept_result_continue(local_id())
	_request_result_continue.rpc_id(1)
	return true


func result_continue_status() -> Vector2i:
	return Vector2i(_result_continue.size(), _slots.size())


func _accept_result_continue(peer_id: int) -> bool:
	if not is_server() or session_phase != SessionPhase.RESULT \
			or not _slots.has(peer_id) or _result_continue.has(peer_id):
		return false
	_result_continue[peer_id] = true
	var packet := PackedInt32Array(_result_continue.keys())
	packet.sort()
	if _online:
		_sync_result_continue.rpc(packet)
	result_votes_changed.emit(packet.size(), _slots.size())
	if packet.size() >= _slots.size() and not _slots.is_empty():
		call_deferred("return_to_truck")
	return true


@rpc("any_peer", "call_remote", "reliable")
func _request_result_continue() -> void:
	if multiplayer.is_server():
		_accept_result_continue(multiplayer.get_remote_sender_id())


@rpc("authority", "call_remote", "reliable")
func _sync_result_continue(peers: PackedInt32Array) -> void:
	if multiplayer.is_server() or session_phase != SessionPhase.RESULT:
		return
	_result_continue.clear()
	for peer_id in peers:
		if _slots.has(peer_id):
			_result_continue[peer_id] = true
	result_votes_changed.emit(_result_continue.size(), _slots.size())


func return_to_truck() -> bool:
	if not lobby_flow or not is_server() or session_phase != SessionPhase.RESULT:
		return false
	if _slots.is_empty() or _result_continue.size() < _slots.size():
		return false
	session_phase = SessionPhase.TRUCK
	_result_continue.clear()
	_lobby_ready = {1: true}
	_loaded_peers.clear()
	_transition_roster.clear()
	if _online:
		_return_to_truck.rpc()
	truck_returned.emit()
	_set_status("truck lobby")
	return true


func replay_stage() -> bool:
	if not lobby_flow or not is_server() or session_phase != SessionPhase.RESULT:
		return false
	_transition_id += 1
	_transition_roster = PackedInt32Array(_slots.keys())
	_transition_roster.sort()
	_loaded_peers.clear()
	_load_clock = 0.0
	session_phase = SessionPhase.LOADING
	if _online:
		_begin_stage_transition.rpc(selected_stage, _transition_id, _transition_roster)
	transition_requested.emit(selected_stage, _transition_id)
	return true


func report_lobby_initialized() -> void:
	if not lobby_flow or session_phase != SessionPhase.TRUCK:
		return
	if is_server():
		_lobby_ready[local_id()] = true
		_broadcast_lobby()
	else:
		_report_lobby_ready.rpc_id(1)


@rpc("authority", "call_remote", "reliable")
func _accept_waiting(stage_id: String, roster: PackedInt32Array) -> void:
	if is_server() or not lobby_flow or not _apply_roster_packet(roster):
		return
	_joined = true
	_refused_for_code = false
	selected_stage = stage_id
	session_phase = SessionPhase.STAGE
	late_join_waiting.emit()


func _admit_waiting_peers() -> void:
	if not lobby_flow or session_phase != SessionPhase.STAGE or world == null:
		return
	for id in _late_loading.keys():
		if _now() - float(_late_loading[id]) > LOAD_TIMEOUT:
			_late_loading.erase(id)
			_late_syncing.erase(id)
			if _peer_can_receive(id):
				multiplayer.multiplayer_peer.disconnect_peer(id)
	if _waiting_peers.is_empty() or not world.can_admit_waiting_player():
		return
	# One snapshot at a time; other waiting players stay out of the active roster.
	if not _late_loading.is_empty():
		return
	var id: int = _waiting_peers.keys()[0]
	_waiting_peers.erase(id)
	_late_loading[id] = _now()
	var active := PackedInt32Array(world.shooter_ids())
	active.append(id)
	_load_late_stage.rpc_id(id, selected_stage, _transition_id, active, _character_packet())


@rpc("authority", "call_remote", "reliable")
func _load_late_stage(stage_id: String, transition: int, active: PackedInt32Array,
		characters: PackedInt32Array) -> void:
	if is_server() or not _joined or session_phase != SessionPhase.STAGE:
		return
	_apply_character_packet(characters)
	var filtered := {}
	for id in active:
		if _slots.has(id):
			filtered[id] = _slots[id]
	_slots = filtered
	_transition_id = transition
	session_phase = SessionPhase.LOADING
	transition_requested.emit(stage_id, transition)


func _finish_late_join(id: int) -> void:
	if world == null or not _peer_can_receive(id):
		return
	_late_syncing[id] = true
	var shooter = world.create_avatar(id, int(_slots[id]), false)
	shooter.player.finish_respawn(world.waiting_player_spawn(int(_slots[id])))
	shooter.sauce = 1.0
	_spawn_avatar.rpc(id, int(_slots[id]))
	_begin_late_snapshot.rpc_id(id)
	var ids := PackedInt32Array()
	var state := _collect_state(ids)
	_apply_state.rpc_id(id, ids, state)
	for spawn in world.tutorial_spawned():
		_add_tutorial_enemy.rpc_id(id, spawn[0], spawn[1])
	var snapshot: Array = world.grid_snapshot()
	for index in snapshot.size():
		var cells: PackedByteArray = snapshot[index]
		var packed := cells.compress(FileAccess.COMPRESSION_ZSTD)
		_load_grid.rpc_id(id, index, packed, cells.size())
	for peer_id in world.shooter_ids():
		_load_body_grid.rpc_id(id, peer_id, world.body_snapshot(peer_id))
		_load_visor_grid.rpc_id(id, peer_id, world.visor_snapshot(peer_id))
	_apply_sauce_shop_state.rpc_id(id, world.sauce_shop_state(), world._sauce_parts.coin_state())
	for start in range(0, world.enemy_count(), ENEMY_SNAPSHOT_BATCH_SIZE):
		_apply_enemy_state.rpc_id(id, world.enemy_state(start, ENEMY_SNAPSHOT_BATCH_SIZE), start, false)
	_apply_tomatina_status.rpc_id(id, world.tomatina_status(), world.cheese_thread_state())
	_complete_late_snapshot.rpc_id(id, _transition_id)
	_broadcast_lobby()


@rpc("authority", "call_remote", "reliable")
func _begin_late_snapshot() -> void:
	if not is_server() and session_phase == SessionPhase.LOADING:
		_receiving_late_snapshot = true


@rpc("authority", "call_remote", "reliable")
func _complete_late_snapshot(transition: int) -> void:
	if is_server() or not _receiving_late_snapshot or transition != _transition_id:
		return
	_receiving_late_snapshot = false
	session_phase = SessionPhase.STAGE
	play_authorized.emit(transition)
	_set_status("joined stage at safe point")
	_late_snapshot_ack.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _late_snapshot_ack() -> void:
	if not is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if _late_syncing.has(sender):
		_late_syncing.erase(sender)
		_late_loading.erase(sender)


func is_online() -> bool:
	return _online


## True offline as well: a session of one is its own authority, which keeps the
## single-player path identical to what it was before any of this existed.
func is_server() -> bool:
	return not _online or multiplayer.is_server()


func status() -> String:
	return _status


func connection_summary() -> String:
	var addresses: Array[String] = []
	for address in IP.get_local_addresses():
		# IPv4 is the least ambiguous value to type into the current join form.
		# Loopback remains documented as the same-machine fallback, not advertised
		# as the address another computer should use.
		if not address.contains(":") and not address.begins_with("127.") \
				and address != "0.0.0.0":
			addresses.push_back(address)
	if addresses.is_empty():
		addresses.push_back("127.0.0.1")
	return "IP %s · UDP %d · 코드 %s" % [
		", ".join(addresses), hosted_port,
		"없음" if lobby_code.is_empty() else lobby_code]


func local_id() -> int:
	return multiplayer.get_unique_id() if _online else 1


# --------------------------------------------------------------------------
# Session setup
# --------------------------------------------------------------------------

## `open_to_anyone` is the deliberate choice to run without a code. Left alone, a
## session that was given no code makes one rather than opening the port to
## whoever finds it.
func host(port := DEFAULT_PORT, open_to_anyone := false) -> bool:
	if _online:
		return false
	# Somebody else's door, and no longer the one in front of this player.
	_blocked_until_local = 0.0
	var peer := ENetMultiplayerPeer.new()
	# Keep one authentication slot beyond the three admitted guests so a fourth
	# can receive an explicit "room full" reason instead of a generic timeout.
	var error := peer.create_server(port, MAX_CLIENTS + 1)
	if error != OK:
		_set_status("could not open port %d (error %d)" % [port, error])
		return false
	if open_to_anyone:
		lobby_code = ""
	elif lobby_code.is_empty():
		lobby_code = generate_code()
	_peer = peer
	hosted_port = port
	multiplayer.multiplayer_peer = peer
	_online = true
	_arm_authentication()
	_connect_signals()
	# The host keeps the body it already had; it just stops being the only one.
	_set_status("hosting on port %d%s, waiting for a player" % [
		port, "" if lobby_code.is_empty() else ", code '%s'" % lobby_code])
	return true


func join(address: String, port := DEFAULT_PORT) -> bool:
	if _online:
		return false
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)
	if error != OK:
		_set_status("could not reach %s:%d (error %d)" % [address, port, error])
		return false
	_peer = peer
	multiplayer.multiplayer_peer = peer
	_online = true
	_arm_authentication()
	_connect_signals()
	_set_status("connecting to %s:%d" % [address, port])
	return true


func leave() -> void:
	slot_user = 0
	office_props = 0
	if not _online:
		# A solo room has no peer to close, only the room itself to put away.
		if lobby_flow:
			_slots = {1: 0}
			_characters.clear()
			_joined = false
			session_phase = SessionPhase.OFFLINE
			_lobby_ready.clear()
			_loaded_peers.clear()
			_result_continue.clear()
			_transition_roster.clear()
			_load_clock = 0.0
			lobby_flow = false
			_set_status("offline")
		return
	# Mark the teardown before detaching the peer. Some backends deliver the
	# disconnect signal synchronously from this assignment; a handler calling
	# leave() again must see an already-closed session instead of sending a
	# second disconnect packet on a zero-channel ENet peer.
	_online = false
	_receiving_late_snapshot = false
	_late_syncing.clear()
	_waiting_peers.clear()
	_late_loading.clear()
	_peer = null
	multiplayer.multiplayer_peer = null
	_clear_stage_input()
	_reset_inventory_and_motion()
	_wipe_budget.clear()
	_refill_budget.clear()
	_view_budget.clear()
	_budget_clock = _now()
	_views.clear()
	_view_sent = Vector2.ZERO
	_view_pending = Vector2.ZERO
	_view_acked = false
	# The block list belongs to the session that was running, not to the process:
	# opening a new room starts everyone even.
	_code_failures.clear()
	_blocks.clear()
	_block_replies.clear()
	_pending_drops.clear()
	_pending_drop_after.clear()
	_next_sweep = 0.0
	_slots = {1: 0}
	_characters.clear()
	_refused_for_code = false
	_joined = false
	session_phase = SessionPhase.OFFLINE
	_lobby_ready.clear()
	_loaded_peers.clear()
	_transition_roster.clear()
	_load_clock = 0.0
	_refused_busy = false
	_refused_full = false
	_refused_version = false
	_lobby_broadcast_at = 0.0
	lobby_flow = false
	_set_status("offline")


## Both ends send their code the moment the other is seen, and the host is the
## one that judges. Godot holds the peer in authenticating until it is let
## through, so a wrong code never becomes a player.
func _arm_authentication() -> void:
	var scene_multiplayer := multiplayer as SceneMultiplayer
	if scene_multiplayer == null:
		return
	scene_multiplayer.auth_timeout = AUTH_TIMEOUT
	scene_multiplayer.auth_callback = _check_code
	if not scene_multiplayer.peer_authenticating.is_connected(_on_peer_authenticating):
		scene_multiplayer.peer_authenticating.connect(_on_peer_authenticating)
		scene_multiplayer.peer_authentication_failed.connect(_on_authentication_failed)


## Tagged rather than sent bare, so an open session still has something to send:
## an empty payload is not a message, and the handshake would sit there.
func _auth_payload() -> PackedByteArray:
	return ("mayo%d:%s" % [PROTOCOL_VERSION, lobby_code]).to_utf8_buffer()


## True of a handshake message from a build that does not speak this version:
## the explicit answer, or a code tagged with another version number. The
## dashed tags (`mayo1-full:` and friends) are answers, not codes, and are
## read before this is asked.
func _other_version(message: String) -> bool:
	if message.begins_with(AUTH_VERSION_PREFIX):
		return true
	var tag := message.get_slice(":", 0)
	return tag.begins_with("mayo") and not tag.contains("-") \
		and tag != "mayo%d" % PROTOCOL_VERSION


func _on_peer_authenticating(id: int) -> void:
	var scene_multiplayer := multiplayer as SceneMultiplayer
	if scene_multiplayer == null:
		return
	# A blocked address is not asked for the code at all: it is told how long it
	# has left and dropped, before either side has said anything else.
	if multiplayer.is_server():
		# The door is open while the party is in the office and at no other
		# time: once they have set out, nobody joins until they are back.
		if lobby_flow and session_phase != SessionPhase.TRUCK:
			scene_multiplayer.send_auth(id,
				(BUSY_PREFIX + "session already started").to_utf8_buffer())
			_queue_drop(id)
			return
		if lobby_flow and _slots.size() >= MAX_CLIENTS + 1:
			scene_multiplayer.send_auth(id, AUTH_FULL_PREFIX.to_utf8_buffer())
			_queue_drop(id)
			return
		var address := _address_of(id)
		var remaining := block_remaining(address)
		if remaining > 0.0:
			blocked_attempts += 1
			_set_status("a player was turned away: blocked for %d s" % ceili(remaining))
			if _may_answer_block(address):
				blocked_replies += 1
				scene_multiplayer.send_auth(id,
					(AUTH_BLOCKED_PREFIX + str(ceili(remaining))).to_utf8_buffer())
				# Dropped next frame rather than now: disconnecting inside this
				# call takes the answer with it and the guest is left with a
				# silent failure, which is the thing being fixed.
				_queue_drop(id)
				return
			multiplayer.multiplayer_peer.disconnect_peer(id)
			return
	scene_multiplayer.send_auth(id, _auth_payload())


## One answer an address a second. Past that a blocked address is dropped without
## one, which is what it was before there were any.
func _may_answer_block(address: String, now := _now()) -> bool:
	if now - float(_block_replies.get(address, -INF)) < 1.0 / BLOCK_REPLIES_PER_SECOND:
		return false
	_block_replies[address] = now
	return true


func _queue_drop(id: int) -> void:
	if not _pending_drops.has(id):
		_pending_drops.push_back(id)
	_pending_drop_after[id] = _now() + AUTH_REASON_GRACE


## The host decides; a guest accepts whatever the host says, since the host has
## already checked the guest by the time it answers.
func _check_code(id: int, data: PackedByteArray) -> void:
	var scene_multiplayer := multiplayer as SceneMultiplayer
	if scene_multiplayer == null:
		return
	if not multiplayer.is_server():
		var message := data.get_string_from_utf8()
		if message.begins_with(BUSY_PREFIX):
			_refused_busy = true
			return
		if message.begins_with(AUTH_FULL_PREFIX):
			_refused_full = true
			return
		if message.begins_with(AUTH_BLOCKED_PREFIX):
			# Not completed: there is nothing to join. The host is about to drop
			# this peer, and the wait is what there is to report.
			_blocked_until_local = _now() + float(
				message.trim_prefix(AUTH_BLOCKED_PREFIX).to_int())
			return
		if _other_version(message):
			# Not completed either way: a host on another build is about to
			# drop this peer, or would admit it to a session whose packets it
			# cannot read.
			_refused_version = true
			return
		scene_multiplayer.complete_auth(id)
		return
	# Already told why it is not coming in, and waiting on the drop. Whatever it
	# sent after that is not a guess at the code.
	if _pending_drops.has(id):
		return
	var address := _address_of(id)
	var message := data.get_string_from_utf8()
	if data == _auth_payload() or (lobby_code.is_empty() and message.begins_with("mayo%d:" % PROTOCOL_VERSION)):
		# Getting it right clears the slate: a player who mistyped it twice and
		# then got in is not working towards a block.
		_code_failures.erase(address)
		scene_multiplayer.complete_auth(id)
		return
	if _other_version(message):
		# Told which build this is and dropped, like a full room: it is not a
		# guess at the code, so it does not count towards a block.
		version_refusals += 1
		_set_status("a player was turned away: different game version")
		scene_multiplayer.send_auth(id,
			(AUTH_VERSION_PREFIX + str(PROTOCOL_VERSION)).to_utf8_buffer())
		_queue_drop(id)
		return
	refused_peers += 1
	_record_failure(address)
	_set_status("a player was turned away: wrong code")
	multiplayer.multiplayer_peer.disconnect_peer(id)


## A code worth reading aloud.
static func generate_code() -> String:
	var code := ""
	for _i in CODE_LENGTH:
		code += CODE_ALPHABET[randi() % CODE_ALPHABET.length()]
	return code


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Which machine a peer is on. Peers are blocked by address rather than by id:
## an id is new on every attempt, so counting those would count nothing.
func _address_of(id: int) -> String:
	var enet := _peer as ENetMultiplayerPeer
	if enet == null:
		return ""
	var packet_peer := enet.get_peer(id)
	return "" if packet_peer == null else packet_peer.get_remote_address()


## `now` is a parameter rather than a reading so the ladder can be walked in a
## check without waiting out the blocks it hands down.
func _record_failure(address: String, now := _now()) -> void:
	var record: Array = _code_failures.get(address, [0, now])
	# A run that has gone quiet for the window is over; this is the start of a
	# new one rather than the sixth of an old one.
	if now - float(record[1]) > CODE_ATTEMPT_WINDOW:
		record = [0, now]
	record[0] = int(record[0]) + 1
	_code_failures[address] = record
	if int(record[0]) < CODE_ATTEMPTS:
		return
	var rung: int = int(_blocks.get(address, [0.0, 0])[1])
	var seconds: float = CODE_BLOCK_LADDER[mini(rung, CODE_BLOCK_LADDER.size() - 1)]
	_blocks[address] = [now + seconds, rung + 1]
	_code_failures.erase(address)


## How long this address still has to wait, in seconds. For the checks and for
## anything that wants to say so.
func block_remaining(address: String, now := _now()) -> float:
	return maxf(float(_blocks.get(address, [0.0, 0])[0]) - now, 0.0)


## How long this peer was told to wait, in whole seconds, counting down as it
## does. Zero when it was not turned away for knocking too often. What the panel
## puts in front of the player.
func blocked_seconds() -> int:
	return maxi(ceili(_blocked_until_local - _now()), 0)


## Which rung of the ladder this address is on: 0 before its first block, 1 after
## it, and so on. For the checks.
func block_count(address: String) -> int:
	return int(_blocks.get(address, [0.0, 0])[1])


## Drops records nothing is waiting on any more: runs of wrong codes that went
## quiet, and blocks that ran out long enough ago that the ladder has reset. Both
## dictionaries are keyed by address, so without this a host left running would
## keep a row for every address that ever got the code wrong.
func _sweep_blocks(now := _now()) -> void:
	if now < _next_sweep:
		return
	_next_sweep = now + CODE_SWEEP_SECONDS
	for address in _code_failures.keys():
		if now - float(_code_failures[address][1]) > CODE_ATTEMPT_WINDOW:
			_code_failures.erase(address)
	for address in _blocks.keys():
		if now - float(_blocks[address][0]) > CODE_BLOCK_MEMORY:
			_blocks.erase(address)
	for address in _block_replies.keys():
		if now - float(_block_replies[address]) > CODE_SWEEP_SECONDS:
			_block_replies.erase(address)


func _on_authentication_failed(_id: int) -> void:
	# The guest is told nothing but that it was refused, so the failure has to be
	# remembered here: the connection_failed that follows would otherwise report
	# it as an unreachable host.
	if not multiplayer.is_server() and not _refused_busy and not _refused_full \
			and not _refused_version:
		_refused_for_code = true


func _connect_signals() -> void:
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		multiplayer.connected_to_server.connect(_on_connected_to_server)
		multiplayer.connection_failed.connect(_on_connection_failed)
		multiplayer.server_disconnected.connect(_on_server_disconnected)


func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	if lobby_flow and session_phase != SessionPhase.TRUCK:
		# Knocked while the party was in the office, got through the handshake
		# as it left. Told so, and dropped once that has had time to leave.
		_refuse_started.rpc_id(id)
		_queue_drop(id)
		return
	var slot := _free_slot()
	_slots[id] = slot
	if lobby_flow:
		_accept_lobby.rpc_id(id, id, slot, selected_stage, _roster_packet())
		_broadcast_lobby()
		_set_status("player %d joined the truck" % id)
		return
	if world == null:
		return
	world.create_avatar(id, slot, false)
	# The lenses exist as of now; whatever camera this peer has already claimed
	# has to be put on them, or it waits for the peer to change its window.
	var view := view_for(id)
	world.set_view_for(id, view.x, view.y)
	# The newcomer is told first, and that message is what ends their offline
	# game: everything after it describes the session they are now in. Doing it
	# in this order means no join message can arrive before the reset that would
	# have thrown it away.
	_join_session.rpc_id(id, id, slot)
	for existing_id in world.shooter_ids():
		if existing_id != id:
			_spawn_avatar.rpc_id(id, existing_id, _slots.get(existing_id, 0))
	_spawn_avatar.rpc(id, slot)
	if world._sauce_parts != null:
		_apply_sauce_shop_state.rpc_id(id, world.sauce_shop_state(), world._sauce_parts.coin_state())
	var snapshot: Array = world.grid_snapshot()
	for index in snapshot.size():
		var cells: PackedByteArray = snapshot[index]
		var packed := cells.compress(FileAccess.COMPRESSION_ZSTD)
		if not packed.is_empty() and packed.size() < cells.size():
			_load_grid.rpc_id(id, index, packed, cells.size())
		else:
			_load_grid.rpc_id(id, index, cells, 0)
	# Bodies too: whoever is already in the session may already be covered.
	for existing_id in world.shooter_ids():
		var body: PackedByteArray = world.body_snapshot(existing_id)
		if not body.is_empty():
			_load_body_grid.rpc_id(id, existing_id, body)
		var visor: PackedByteArray = world.visor_snapshot(existing_id)
		if not visor.is_empty():
			_load_visor_grid.rpc_id(id, existing_id, visor)
	# The tutorial, if one is running: every body it has placed, in the order it
	# placed them, and then where the sequence has got to. Bodies before stage,
	# because the stage names them by index.
	for spawn in world.tutorial_spawned():
		_add_tutorial_enemy.rpc_id(id, spawn[0], spawn[1])
	var tutorial = world.tutorial()
	if tutorial != null:
		send_tutorial_state(id, tutorial.state())
	_set_status("player %d connected" % id)


## The lowest spawn nobody is standing on.
func _free_slot() -> int:
	var taken := {}
	for id in _slots:
		taken[_slots[id]] = true
	var slot := 0
	while taken.has(slot):
		slot += 1
	return slot


func _on_peer_disconnected(id: int) -> void:
	_late_syncing.erase(id)
	_waiting_peers.erase(id)
	_late_loading.erase(id)
	_client_input.erase(id)
	_input_queue.erase(id)
	_stage_input_received_at.erase(id)
	_lobby_input.erase(id)
	_input_this_tick.erase(id)
	_wipe_budget.erase(id)
	_refill_budget.erase(id)
	_view_budget.erase(id)
	_views.erase(id)
	_slots.erase(id)
	_leave_slot_seat(id)
	_characters.erase(id)
	_lobby_ready.erase(id)
	_loaded_peers.erase(id)
	_result_continue.erase(id)
	if multiplayer.is_server() and world != null:
		world.remove_avatar(id)
		if not lobby_flow:
			_despawn_avatar.rpc(id)
	if lobby_flow:
		roster_changed.emit()
		# ENet reports the disconnect before the channel is fully retired. Sending
		# an RPC from inside that callback can target a zero-channel peer when two
		# players leave together, so debounce the compact roster publication until
		# ENet has retired every disconnect from this burst.
		if multiplayer.is_server():
			_lobby_broadcast_at = _now() + 0.1
		if multiplayer.is_server() and session_phase == SessionPhase.RESULT:
			var result_packet := PackedInt32Array(_result_continue.keys())
			result_packet.sort()
			_sync_result_continue.rpc(result_packet)
			result_votes_changed.emit(result_packet.size(), _slots.size())
			if result_packet.size() >= _slots.size() and not _slots.is_empty():
				call_deferred("return_to_truck")
	_set_status("player %d left" % id)


func _on_connected_to_server() -> void:
	if not lobby_flow:
		_joined = true
	_blocked_until_local = 0.0
	# The world is not touched here: the server's first message does that, so
	# that a spawn cannot land before the reset and be wiped by it.
	_set_status("connected as player %d" % multiplayer.get_unique_id())


func _on_connection_failed() -> void:
	var refused := _refused_for_code
	var busy := _refused_busy
	var full := _refused_full
	var mismatched := _refused_version
	var waiting := blocked_seconds()
	leave()
	if waiting > 0:
		_set_status("blocked, %d s left" % waiting)
		return
	_set_status("game version differs from the host" if mismatched else (
		"room is full" if full else (
		"session is already in progress" if busy else (
		"wrong lobby code" if refused else "connection failed"))))


func _on_server_disconnected() -> void:
	# A guest that never got as far as being in the session was refused at the
	# handshake, which is the only thing the host drops a peer over before it has
	# a body. Once it is in, the same signal means what it always did.
	var refused := _refused_for_code or not _joined
	var busy := _refused_busy
	var full := _refused_full
	var mismatched := _refused_version
	var waiting := blocked_seconds()
	var was_lobby_flow := lobby_flow
	leave()
	if world != null and not was_lobby_flow:
		world.reset_to_offline()
	if waiting > 0:
		_set_status("blocked, %d s left" % waiting)
		return
	var reason := "game version differs from the host" if mismatched else (
		"room is full" if full else (
		"session is already in progress" if busy else (
		"wrong lobby code" if refused else "host closed the session")))
	_set_status(reason)
	session_ended.emit(reason)


func _set_status(message: String) -> void:
	_status = message
	status_changed.emit(message)


# --------------------------------------------------------------------------
# Persistent truck / stage session flow
# --------------------------------------------------------------------------

func _roster_packet() -> PackedInt32Array:
	var packet := PackedInt32Array()
	var ids: Array = _slots.keys()
	ids.sort()
	for id in ids:
		packet.push_back(int(id))
		packet.push_back(int(_slots[id]))
	return packet


func _apply_roster_packet(packet: PackedInt32Array) -> bool:
	if packet.size() % 2 != 0 or packet.size() > (MAX_CLIENTS + 1) * 2:
		return false
	var parsed := {}
	var used := {}
	for index in range(0, packet.size(), 2):
		var id := int(packet[index])
		var seat := int(packet[index + 1])
		if id <= 0 or seat < 0 or seat > MAX_CLIENTS or parsed.has(id) or used.has(seat):
			return false
		parsed[id] = seat
		used[seat] = true
	_slots = parsed
	return true


## Every pick, as [peer id, index] pairs in peer order.
func _character_packet() -> PackedInt32Array:
	var packet := PackedInt32Array()
	var ids: Array = _characters.keys()
	ids.sort()
	for id in ids:
		if _slots.has(id):
			packet.push_back(int(id))
			packet.push_back(int(_characters[id]))
	return packet


## The host's picks, on a guest. Anything that is not a seated player with an
## index in range is skipped rather than failing the packet: the roster it
## arrived with is already applied and is still right. The host's copy is the
## whole truth, this peer's own pick included -- see `choose_character`.
func _apply_character_packet(packet: PackedInt32Array) -> void:
	var parsed := {}
	for index in range(0, packet.size() - 1, 2):
		var id := int(packet[index])
		var character := int(packet[index + 1])
		if _slots.has(id) and character >= 0 and character < CHARACTER_COUNT:
			parsed[id] = character
	_characters = parsed


func _broadcast_lobby() -> void:
	if not lobby_flow or not is_server():
		return
	var ready := PackedInt32Array(_lobby_ready.keys())
	ready.sort()
	var packet := _roster_packet()
	var characters := _character_packet()
	for peer_id in _slots.keys():
		if int(peer_id) != 1 and _peer_can_receive(int(peer_id)):
			_sync_team_progress.rpc_id(int(peer_id), team_money, team_trophies, team_clears, team_jackpot,
				team_parts)
			_sync_office_props.rpc_id(int(peer_id), office_props)
			_sync_debug_mode.rpc_id(int(peer_id), _debug_here)  # DEBUG
			_sync_slot_user.rpc_id(int(peer_id), slot_user)
			_sync_lobby.rpc_id(int(peer_id), packet, ready, selected_stage, session_phase,
				characters)
	roster_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _accept_lobby(id: int, seat: int, stage_id: String,
		packet: PackedInt32Array) -> void:
	if multiplayer.is_server() or not lobby_flow or not _apply_roster_packet(packet):
		return
	if not _slots.has(id) or int(_slots[id]) != seat:
		return
	_joined = true
	_refused_for_code = false
	_refused_busy = false
	_refused_full = false
	_refused_version = false
	session_phase = SessionPhase.TRUCK
	selected_stage = stage_id
	_set_status("joined truck lobby as player %d" % id)
	lobby_joined.emit()
	roster_changed.emit()
	if not defer_lobby_ready:
		_report_lobby_ready.rpc_id(1)


@rpc("authority", "call_remote", "reliable")
func _sync_lobby(packet: PackedInt32Array, ready: PackedInt32Array,
		stage_id: String, remote_phase: int,
		characters := PackedInt32Array()) -> void:
	if multiplayer.is_server() or not lobby_flow or not _apply_roster_packet(packet):
		return
	_apply_character_packet(characters)
	selected_stage = stage_id
	if remote_phase >= SessionPhase.OFFLINE and remote_phase <= SessionPhase.RESULT:
		session_phase = remote_phase
	if world != null and session_phase in [SessionPhase.LOADING, SessionPhase.STAGE, SessionPhase.RESULT]:
		for id in world.shooter_ids():
			if not _slots.has(id):
				world.remove_avatar(id)
		for id in _characters:
			_apply_world_character(int(id))
	_lobby_ready.clear()
	for id in ready:
		if _slots.has(id):
			_lobby_ready[id] = true
	roster_changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _report_lobby_ready() -> void:
	if not lobby_flow or not multiplayer.is_server() or session_phase != SessionPhase.TRUCK:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not _slots.has(sender):
		return
	_lobby_ready[sender] = true
	_broadcast_lobby()


## A guest's pick, at the host. Clamped like every other number a client sends;
## there is no wrong character, only an index outside the four.
@rpc("any_peer", "call_remote", "reliable")
func _choose_character(index: int) -> void:
	if not lobby_flow or not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not _slots.has(sender):
		return
	# Send the roster even if another player took the character first.
	if _can_choose_character(sender, index):
		_commit_character(sender, index)
	_broadcast_lobby()


@rpc("authority", "call_remote", "reliable")
func _refuse_started() -> void:
	if not is_server() and not _joined:
		_refused_busy = true


@rpc("authority", "call_remote", "reliable")
func _begin_stage_transition(stage_id: String, transition: int,
		participants: PackedInt32Array) -> void:
	if multiplayer.is_server() or not lobby_flow or session_phase not in [SessionPhase.TRUCK, SessionPhase.RESULT]:
		return
	if not participants.has(local_id()) or transition <= _transition_id:
		return
	selected_stage = stage_id
	_transition_id = transition
	_transition_roster = participants
	_loaded_peers.clear()
	_load_clock = 0.0
	session_phase = SessionPhase.LOADING
	_set_status("loading %s" % stage_id)
	transition_requested.emit(stage_id, transition)


@rpc("any_peer", "call_remote", "reliable")
func _report_world_loaded(transition: int) -> void:
	if not lobby_flow or not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if _late_loading.has(sender) and not _late_syncing.has(sender) and transition == _transition_id:
		_finish_late_join(sender)
		return
	_mark_loaded(sender, transition)


func _mark_loaded(peer_id: int, transition: int) -> void:
	if session_phase != SessionPhase.LOADING or transition != _transition_id:
		return
	if not _transition_roster.has(peer_id) or not _slots.has(peer_id):
		return
	_loaded_peers[peer_id] = true
	_try_authorize_play()


func _try_authorize_play() -> void:
	# Send the updated roster before authorizing a load with a departing peer.
	if not is_server() or session_phase != SessionPhase.LOADING or _lobby_broadcast_at > 0.0:
		return
	for id in _transition_roster:
		if _slots.has(id) and not _loaded_peers.has(id):
			return
	session_phase = SessionPhase.STAGE
	if _online:
		_authorize_play.rpc(_transition_id)
	play_authorized.emit(_transition_id)
	_set_status("stage started")


@rpc("authority", "call_remote", "reliable")
func _authorize_play(transition: int) -> void:
	if multiplayer.is_server() or session_phase != SessionPhase.LOADING \
			or transition != _transition_id:
		return
	session_phase = SessionPhase.STAGE
	play_authorized.emit(transition)
	_set_status("stage started")


@rpc("any_peer", "call_remote", "reliable")
func _report_world_load_failed(transition: int) -> void:
	if not is_server() or transition != _transition_id:
		return
	var sender := multiplayer.get_remote_sender_id()
	if _transition_roster.has(sender) and _slots.has(sender) and not _loaded_peers.has(sender):
		_fail_loading(STAGE_LOAD_FAILED)


func _fail_loading(reason: String) -> void:
	if not is_server() or session_phase != SessionPhase.LOADING:
		return
	if _online:
		_loading_failed.rpc(_transition_id, selected_stage, reason)
	_return_after_failed_load(selected_stage, reason)


@rpc("authority", "call_remote", "reliable")
func _loading_failed(transition: int, stage_id: String, reason: String) -> void:
	if is_server() or session_phase != SessionPhase.LOADING or transition != _transition_id:
		return
	_return_after_failed_load(stage_id, reason)


func _return_after_failed_load(stage_id: String, reason: String) -> void:
	selected_stage = stage_id
	session_phase = SessionPhase.TRUCK
	_lobby_ready = {1: true} if is_server() else {}
	_loaded_peers.clear()
	_transition_roster.clear()
	_load_clock = 0.0
	_receiving_late_snapshot = false
	transition_failed.emit(reason)
	_set_status(reason)


@rpc("authority", "call_remote", "reliable")
func _show_result(summary: Dictionary) -> void:
	if multiplayer.is_server() or session_phase not in [SessionPhase.STAGE, SessionPhase.LOADING]:
		return
	session_phase = SessionPhase.RESULT
	_result_continue.clear()
	_receiving_late_snapshot = false
	result_ready.emit(summary)
	result_votes_changed.emit(0, _slots.size())


@rpc("authority", "call_remote", "reliable")
func _return_to_truck() -> void:
	if multiplayer.is_server() or session_phase != SessionPhase.RESULT:
		return
	session_phase = SessionPhase.TRUCK
	_result_continue.clear()
	_lobby_ready.clear()
	_loaded_peers.clear()
	_transition_roster.clear()
	truck_returned.emit()
	_set_status("truck lobby")


# --------------------------------------------------------------------------
# Client input validation
#
# Nothing a client sends is trusted. The keyboard path bounds itself on the way
# in -- Input.get_vector never returns a vector longer than the stick, and the
# aim is clamped to the pitch limit as the mouse moves it -- but a packet
# carries no such guarantee, and the values in one go straight into the body the
# server simulates. Unbounded, a move vector is a speed hack; a single NaN in a
# position is worse than that, because the server writes it into the next state
# packet and both screens follow it.
#
# So: every RPC a client can call runs its floats through `all_finite` and drops
# the whole packet if any of them is not, then clamps each value to the range
# the keyboard could have produced. Any client input added later belongs here
# too -- these are the only doors into the simulation from outside.
# --------------------------------------------------------------------------

## True when every float in `values` is a real number. Vector2s are checked
## component-wise; anything that is not a number is ignored.
static func all_finite(values: Array) -> bool:
	for value in values:
		if value is Vector2:
			if not is_finite(value.x) or not is_finite(value.y):
				return false
		elif value is float or value is int:
			if not is_finite(value):
				return false
	return true


## A direction, never a magnitude: anything longer than a full stick deflection
## is cut back to it, so a packet cannot ask for a speed the keys could not.
static func clamp_direction(value: Vector2) -> Vector2:
	return value if value.length_squared() <= 1.0 else value.normalized()


## The plain range check, for a number that has a floor and a ceiling and no
## angle wrapping to think about. Out of range is brought to the edge; the caller
## decides whether that is the right answer or whether the packet should go.
static func clamp_range(value: float, low: float, high: float) -> float:
	return clampf(value, low, high)


## For an angle with a stop at each end, like the aim pitch.
static func clamp_angle(value: float, limit: float) -> float:
	return clampf(value, -limit, limit)


## For an angle that wraps instead, like yaw: out of range is not hostile, it
## just needs bringing back into the turn the body understands.
static func wrap_angle(value: float) -> float:
	return wrapf(value, -PI, PI)


# --------------------------------------------------------------------------
# Per-frame traffic
# --------------------------------------------------------------------------

## Called at the end of the world's physics frame: the server pushes the frame's
## splats and the state of every body, the client has already sent its input.
func end_of_frame(splats: PackedInt32Array) -> void:
	if not _online or not multiplayer.is_server() or not _world_ready():
		return
	_admit_waiting_peers()
	var peer_ids := multiplayer.get_peers()
	var guests := peer_ids.size()
	if not splats.is_empty():
		_apply_splats.rpc(splats)
		splat_bytes_sent += splats.size() * 4 * guests
	if guests == 0:
		_reset_inventory_and_motion()
		return
	var ids := PackedInt32Array()
	var state := _collect_state(ids)
	_apply_state.rpc(ids, state)
	state_bytes_sent += (ids.size() + state.size()) * 4 * guests
	# Enemies are the server's outright -- clients simulate none of them -- so
	# they are sent, never asked for. Unreliable like the player state: a
	# dropped frame is corrected by the next one.
	var healing: PackedFloat64Array = world.healing_tomato_state()
	_apply_healing_tomato_state.rpc(healing)
	state_bytes_sent += healing.size() * 8 * guests
	var peers_changed := _inventory_peers != peer_ids
	var inventory: PackedInt32Array = world.inventory_state()
	if peers_changed or _inventory_sent != inventory:
		if rpc(&"_apply_inventory_state", inventory) == OK:
			state_bytes_sent += inventory.size() * 4 * guests
			_inventory_sent = inventory
			_inventory_peers = peer_ids
	var stage_two: bool = world.map_kind == world.MapKind.TOMATINA
	if stage_two:
		if world._sauce_parts.dirty:
			world._sauce_parts.dirty = false
			var shop: PackedInt32Array = world.sauce_shop_state()
			var coins: PackedFloat32Array = world._sauce_parts.coin_state()
			_apply_sauce_shop_state.rpc(shop, coins)
			state_bytes_sent += (shop.size() + coins.size()) * 4 * guests
		_tomatina_snapshot_phase = (_tomatina_snapshot_phase + 1) % 3
		if _tomatina_snapshot_phase != 0:
			return
	var motion: PackedFloat64Array = world.player_motion_state()
	var now := _now()
	if not stage_two or peers_changed or motion != _motion_sent or now >= _motion_refresh_at:
		_apply_player_motion_state.rpc(motion)
		state_bytes_sent += motion.size() * 8 * guests
		_motion_sent = motion
		_motion_refresh_at = now + MOTION_REFRESH_SECONDS
	# Keep each unreliable datagram under the ENet MTU even during a horde.
	if stage_two and world.is_inside_tree():
		_send_tomatina_enemy_snapshots(peer_ids)
	else:
		for start in range(0, world.enemy_count(), ENEMY_SNAPSHOT_BATCH_SIZE):
			var enemies: PackedFloat32Array = world.enemy_state(start, ENEMY_SNAPSHOT_BATCH_SIZE)
			_apply_enemy_state.rpc(enemies, start, stage_two)
			state_bytes_sent += (enemies.size() * 4 + 8) * guests
	if stage_two:
		var status: PackedFloat64Array = world.tomatina_status()
		var threads: PackedFloat32Array = world.cheese_thread_state()
		_apply_tomatina_status.rpc(status, threads)
		state_bytes_sent += (status.size() * 8 + threads.size() * 4) * guests


func _reset_inventory_and_motion() -> void:
	_inventory_sent.clear()
	_inventory_peers.clear()
	_motion_sent.clear()
	_motion_refresh_at = 0.0


func _send_tomatina_enemy_snapshots(peer_ids: PackedInt32Array) -> void:
	_tomatina_snapshot_number += 1
	for id in _enemy_snapshots_by_peer.keys():
		if not peer_ids.has(id):
			_enemy_snapshots_by_peer.erase(id)
	var positions := {}
	for id in peer_ids:
		var shooter = world.shooter_for(id)
		if shooter != null:
			positions[id] = shooter.player.global_position
			_enemy_snapshots_by_peer.get_or_add(id, {})
	for start in range(0, world.enemy_count(), ENEMY_SNAPSHOT_BATCH_SIZE):
		var batch_number := start / ENEMY_SNAPSHOT_BATCH_SIZE
		var staggered := _tomatina_snapshot_number + batch_number
		var refresh := staggered % ENEMY_SNAPSHOT_REFRESH_PERIOD == 0
		var far_turn := staggered % ENEMY_SNAPSHOT_FAR_PERIOD == 0
		world.fill_enemy_state(_enemy_snapshot_scratch, start, ENEMY_SNAPSHOT_BATCH_SIZE)
		# Most batches hold idle enemies. Keep their last encoded payload for
		# refreshes, and allocate a new immutable payload only when it differs.
		var state: PackedFloat32Array = _enemy_snapshot_batches.get(start, PackedFloat32Array())
		if state != _enemy_snapshot_scratch:
			state = _enemy_snapshot_scratch.duplicate()
			_enemy_snapshot_batches[start] = state
		var recipients := PackedInt32Array()
		for id in positions:
			var previous: PackedFloat32Array = _enemy_snapshots_by_peer[id].get(start, PackedFloat32Array())
			if previous.size() != state.size() or refresh:
				recipients.append(id)
			elif previous != state and (far_turn or _enemy_snapshot_important(state, previous, positions[id])):
				recipients.append(id)
		if recipients.size() == peer_ids.size():
			_apply_enemy_state.rpc(state, start, true)
		else:
			for id in recipients:
				_apply_enemy_state.rpc_id(id, state, start, true)
		for id in recipients:
			_enemy_snapshots_by_peer[id][start] = state
		state_bytes_sent += (state.size() * 4 + 8) * recipients.size()


func _enemy_snapshot_important(state: PackedFloat32Array, previous: PackedFloat32Array,
		peer_position: Vector3) -> bool:
	for offset in range(0, state.size(), world.ENEMY_STATE_STRIDE):
		# Health transitions stay visible even when the team is split across the map.
		if (state[offset + 4] <= 0.0) != (previous[offset + 4] <= 0.0):
			return true
		var at := Vector3(state[offset], state[offset + 1], state[offset + 2])
		if at.distance_squared_to(peer_position) <= ENEMY_SNAPSHOT_NEAR_DISTANCE ** 2:
			return true
	return false


## R, on a client. The wipe is a change everyone sees, so the client asks and
## the server decides -- the server owns whether the lenses are dirty enough to
## be worth wiping and whether the player is in a state to do it.
func request_wipe() -> void:
	if not _online or multiplayer.is_server():
		return
	if not _joined or _peer == null or _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_request_wipe.rpc_id(1)


## No numbers to range-check here: the packet carries nothing but the fact that
## a key was pressed, and the sender is taken from the connection rather than
## from the message. Anything added to it goes through `all_finite` and the
## clamps above, like every other client input.
@rpc("any_peer", "call_remote", "reliable")
func _request_wipe() -> void:
	if not multiplayer.is_server() or not _world_ready():
		return
	var sender := multiplayer.get_remote_sender_id()
	if _wipe_budget.get(sender, WIPE_REQUESTS_PER_SECOND) < 1.0:
		dropped_packets += 1
		return
	_wipe_budget[sender] = _wipe_budget.get(sender, WIPE_REQUESTS_PER_SECOND) - 1.0
	world.begin_wipe_for(sender)


## The client selects a sauce; the server checks its own player position.
func request_refill(sauce: int) -> void:
	if not _online or multiplayer.is_server():
		return
	if not _joined or _peer == null or _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_request_refill.rpc_id(1, sauce)


@rpc("any_peer", "call_remote", "reliable")
func _request_refill(sauce: int) -> void:
	if not multiplayer.is_server() or not _world_ready():
		return
	var sender := multiplayer.get_remote_sender_id()
	if _refill_budget.get(sender, REFILL_REQUESTS_PER_SECOND) < 1.0:
		dropped_packets += 1
		return
	_refill_budget[sender] = _refill_budget.get(sender, REFILL_REQUESTS_PER_SECOND) - 1.0
	# Which sauce is the station's to say, not the client's: every station
	# hands out one, and the host knows which it is standing the body at.
	world.refill_for(sender, world.STATION_SAUCE_HERE)


## The host telling everyone a fresh bottle was selected. An event, not a value in the
## state packet: refills are rare and the drain is already derived everywhere.
func broadcast_refill(peer_id: int, sauce: int) -> void:
	if not _online or not multiplayer.is_server():
		return
	_apply_refill.rpc(peer_id, sauce)


@rpc("authority", "call_remote", "reliable")
func _apply_refill(peer_id: int, sauce: int) -> void:
	if not _world_ready():
		return
	world.apply_refill(peer_id, sauce)


## Called every frame with whatever the local camera currently is. Sends only
## when it has changed, and no more often than the host will listen, so the host
## never has to drop a report an honest client sent.
func report_view(fov_degrees: float, aspect: float, delta: float) -> void:
	if not _world_ready():
		return
	_view_cooldown = maxf(_view_cooldown - delta, 0.0)
	# The host has nobody to ask, so it clamps its own camera the same way and
	# paints its own lenses with the answer. Offline is the same case.
	if not _online or multiplayer.is_server():
		var mine := _clamp_view(fov_degrees, aspect)
		var id := local_id()
		if _views.get(id, Vector2.ZERO) != mine:
			_views[id] = mine
			world.set_view_for(id, mine.x, mine.y)
			world.apply_view(mine.x, mine.y)
		return
	if not _joined or _peer == null or _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_view_pending = Vector2(fov_degrees, aspect)
	var unchanged := _view_pending.is_equal_approx(_view_sent)
	if (unchanged and _view_acked) or _view_cooldown > 0.0:
		return
	_view_sent = _view_pending
	_view_acked = false
	_view_cooldown = 1.0 / VIEW_REPORTS_PER_SECOND
	_submit_view.rpc_id(1, fov_degrees, aspect)


## A client saying what its camera is. Two floats, so they go through the same
## finite check every other client input does; then to the edges of what a camera
## may be, and back to the sender as the values it has to render with.
@rpc("any_peer", "call_remote", "reliable")
func _submit_view(fov_degrees: float, aspect: float) -> void:
	if not multiplayer.is_server() or not _world_ready():
		return
	var sender := multiplayer.get_remote_sender_id()
	if _view_budget.get(sender, VIEW_REPORTS_PER_SECOND) < 1.0:
		dropped_packets += 1
		return
	_view_budget[sender] = _view_budget.get(sender, VIEW_REPORTS_PER_SECOND) - 1.0
	if not all_finite([fov_degrees, aspect]):
		rejected_packets += 1
		return
	var view := _clamp_view(fov_degrees, aspect)
	_views[sender] = view
	world.set_view_for(sender, view.x, view.y)
	_accept_view.rpc_id(sender, view.x, view.y)


## The host's answer, which is not advice. A client that renders something else
## is drawing its blindness in the wrong place on its own screen, and the mask
## everyone sees is the host's either way.
@rpc("authority", "call_remote", "reliable")
func _accept_view(fov_degrees: float, aspect: float) -> void:
	if multiplayer.is_server() or not _world_ready():
		return
	_view_acked = true
	world.apply_view(fov_degrees, aspect)


func _clamp_view(fov_degrees: float, aspect: float) -> Vector2:
	return Vector2(
		clamp_range(fov_degrees, MIN_FOV_DEGREES, MAX_FOV_DEGREES),
		clamp_range(aspect, MIN_ASPECT, MAX_ASPECT))


## What the host is painting a peer's lenses with, for the checks.
func view_for(peer_id: int) -> Vector2:
	return _views.get(peer_id, Vector2(
		VisorContamination.DEFAULT_FOV_DEGREES, VisorContamination.DEFAULT_ASPECT))


## One input a tick per peer. The rest are dropped where they arrive, so a
## flood costs the flooder its bandwidth and the host a dictionary lookup.
func _within_budget(sender: int) -> bool:
	var sent: int = _input_this_tick.get(sender, 0)
	if sent >= INPUT_PACKETS_PER_TICK:
		dropped_packets += 1
		return false
	_input_this_tick[sender] = sent + 1
	return true


## The truck runs on the same split as the stage: clients send their keys, the
## host walks every body and sends back where they ended up. Nothing in a lobby
## is competitive, but a player who sees themselves standing somewhere the seat
## next to them does not is the same bug in either space, and the stage already
## has the helpers for not having it.
##
## It is also what runs the truck when there is no session at all -- the scene
## opened on its own with `F6` -- because then this peer is the only authority
## there is.
func run_lobby(delta: float) -> void:
	if not _lobby_space_ready():
		return
	if not _online:
		lobby_space.step_occupants({}, delta)
		return
	if not multiplayer.is_server():
		return
	# `apply_client_input` hands out a fresh allowance every tick, but it
	# returns early outside the stage, so the truck has to clear its own:
	# without this every guest spends its one packet on the first truck frame
	# and is never heard from again -- it stands still on the host's screen
	# while walking on its own.
	_input_this_tick.clear()
	var now := _now()
	for id in _lobby_input.keys():
		if now - float(_lobby_input[id][3]) >= LOBBY_INPUT_TIMEOUT:
			_lobby_input.erase(id)
	lobby_space.step_occupants(_lobby_input, delta)
	if multiplayer.get_peers().is_empty():
		return
	var ids := PackedInt32Array()
	var data := PackedFloat32Array()
	for peer_id in lobby_space.occupant_ids():
		var pose: Array = lobby_space.occupant_pose(int(peer_id))
		var at: Vector3 = pose[0]
		ids.push_back(int(peer_id))
		data.append_array(PackedFloat32Array([at.x, at.y, at.z, pose[1]]))
	_apply_lobby_poses.rpc(ids, data)


## A guest's keys on their way to the host. Unreliable like the stage's: the
## host reuses recent input through short gaps, then lets the occupant stop.
func send_lobby_input(move: Vector2, yaw: float, jump := false, run := false) -> void:
	if not _online or multiplayer.is_server() or not _lobby_space_ready():
		return
	if not _joined or _peer == null \
			or _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_submit_lobby_input.rpc_id(1, move, yaw, jump, run)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _submit_lobby_input(move: Vector2, yaw: float, jump := false, run := false) -> void:
	if not multiplayer.is_server() or not _lobby_space_ready():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not _within_budget(sender):
		return
	# The same two doors as every other client packet. A truck is a smaller
	# place to cheat in, but a NaN written into a pose is still broadcast to
	# everyone and still takes all four screens with it.
	if not all_finite([move, yaw]):
		rejected_packets += 1
		return
	# The jump and the run are bools, and there is no wrong value for a key being down.
	_lobby_input[sender] = [clamp_direction(move), wrap_angle(yaw), jump, _now(), run]


## A guest standing in the office's firing range. There its body is walked by
## the range on its own screen, so instead of keys it sends where that body is
## and the host shows it there (`TruckLobby.pin_occupant`). Sent in place of
## the keys, on the same budget. The lobby decides whether the spot is one a
## body in the range could be standing on.
func send_lobby_pin(at: Vector3, yaw: float) -> void:
	if not _online or multiplayer.is_server() or not _lobby_space_ready():
		return
	if not _joined or _peer == null \
			or _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_submit_lobby_pin.rpc_id(1, at, yaw)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _submit_lobby_pin(at: Vector3, yaw: float) -> void:
	if not multiplayer.is_server() or not _lobby_space_ready():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not _within_budget(sender):
		return
	if not all_finite([at.x, at.y, at.z, yaw]):
		rejected_packets += 1
		return
	if lobby_space.has_method("accept_pin"):
		lobby_space.accept_pin(sender, at, wrap_angle(yaw))


## The office's firing range runs on every screen separately, so what a player
## is doing with their bottle travels as that player's own state -- where they
## stand, where they aim, whether they are firing, what they hold -- and each
## screen stands a body for them in its own range (`OfficeLobby.accept_range_state`).
## Through the host, like everything else: a guest's goes up and is passed on.
func send_range_state(data: PackedFloat32Array) -> void:
	if not _online or not _lobby_space_ready() or data.is_empty():
		return
	if multiplayer.is_server():
		_apply_range_state.rpc(1, data)
		return
	if not _joined or _peer == null \
			or _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_submit_range_state.rpc_id(1, data)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _submit_range_state(data: PackedFloat32Array) -> void:
	if not multiplayer.is_server() or not _lobby_space_ready():
		return
	var sender := multiplayer.get_remote_sender_id()
	if data.size() != RANGE_STATE_SIZE or not all_finite(Array(data)):
		rejected_packets += 1
		return
	_apply_range_state.rpc(sender, data)
	if lobby_space.has_method("accept_range_state"):
		lobby_space.accept_range_state(sender, data)


## Whoever walks into an office that has already been sprayed asks the host for
## the marks that are there: every screen works its own out from then on, but
## nothing replays what happened before it arrived. One message per marked
## surface, as the stage's late join does.
func request_range_snapshot() -> void:
	if not _online or multiplayer.is_server() or not _lobby_space_ready():
		return
	if not _joined or _peer == null \
			or _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_request_range_snapshot.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_range_snapshot() -> void:
	if not multiplayer.is_server() or not _lobby_space_ready() \
			or not lobby_space.has_method("range_snapshot"):
		return
	var sender := multiplayer.get_remote_sender_id()
	# A snapshot is the whole building's worth of cells: not something to hand
	# out as fast as it can be asked for.
	var now := _now()
	if now - float(_range_snapshot_sent.get(sender, -INF)) < RANGE_SNAPSHOT_INTERVAL:
		return
	_range_snapshot_sent[sender] = now
	for entry: Array in lobby_space.range_snapshot():
		var cells: PackedByteArray = entry[1]
		var packed := cells.compress(FileAccess.COMPRESSION_ZSTD)
		if not packed.is_empty() and packed.size() < cells.size():
			_load_range_grid.rpc_id(sender, int(entry[0]), packed, cells.size())
		else:
			_load_range_grid.rpc_id(sender, int(entry[0]), cells, 0)


@rpc("authority", "call_remote", "reliable")
func _load_range_grid(index: int, cells: PackedByteArray, raw_size: int) -> void:
	if not _lobby_space_ready() or not lobby_space.has_method("accept_range_grid"):
		return
	if raw_size > 0:
		if raw_size > RANGE_GRID_MAX_BYTES:
			return
		cells = cells.decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	lobby_space.accept_range_grid(index, cells)


@rpc("authority", "call_remote", "unreliable_ordered")
func _apply_range_state(peer_id: int, data: PackedFloat32Array) -> void:
	if peer_id == local_id() or not _lobby_space_ready() or data.size() != RANGE_STATE_SIZE:
		return
	if lobby_space.has_method("accept_range_state"):
		lobby_space.accept_range_state(peer_id, data)


@rpc("authority", "call_remote", "unreliable_ordered")
func _apply_lobby_poses(ids: PackedInt32Array, data: PackedFloat32Array) -> void:
	if not _lobby_space_ready():
		return
	for slot in ids.size():
		var index := slot * LOBBY_POSE_STRIDE
		if index + LOBBY_POSE_STRIDE > data.size():
			return
		lobby_space.apply_occupant_pose(ids[slot],
			Vector3(data[index], data[index + 1], data[index + 2]), data[index + 3])


func send_input(move: Vector2, run: bool, jump: bool, firing: bool,
		yaw: float, pitch: float, character_index := 0, shake := 0.0) -> void:
	if not _online or multiplayer.is_server() or not _world_ready():
		return
	# The handshake takes a few frames, and the keys sent during it have nowhere
	# to go yet.
	if not _joined or _peer == null or _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	var sequence: int = world._local.player.prediction_sequence
	_submit_input.rpc_id(1, move, run, jump, firing, yaw, pitch, character_index, shake, sequence)


func _clear_stage_input() -> void:
	_client_input.clear()
	_input_queue.clear()
	_stage_input_received_at.clear()
	_input_this_tick.clear()


## Apply connected guests' input before the bodies take their physics step.
func apply_client_input() -> void:
	if not _online or not multiplayer.is_server() or not _world_ready():
		return
	# The allowance leaks one packet a tick: a peer may run up to
	# INPUT_PACKETS_PER_TICK in a bunch after a quiet tick, but not keep it up.
	# What a flooder sent past that was dropped as it arrived.
	for id in _input_this_tick.keys():
		var left: int = _input_this_tick[id] - 1
		if left <= 0:
			_input_this_tick.erase(id)
		else:
			_input_this_tick[id] = left
	# The two rate limits below refill on the wall clock rather than by a fixed
	# 1/60th per tick. What they are limiting is measured in real seconds at the
	# other end -- a client's cooldown between view reports is decremented with
	# the frame delta, from `_process` -- and the two only agree while the game
	# is running at exactly 60 fps. Below that the client asks faster than a
	# per-tick allowance grows, so every report it sends is dropped for being
	# over budget, and the host never learns what camera that peer is using:
	# their lenses get painted against the wrong frustum for the whole session.
	# A heavier level was all it took to fall off 60 and expose it.
	var now := _now()
	# Clamped so a long hitch or a paused window does not hand out a burst.
	var elapsed := clampf(now - _budget_clock, 0.0, 1.0)
	_budget_clock = now
	for id in _wipe_budget:
		_wipe_budget[id] = minf(_wipe_budget[id] + WIPE_REQUESTS_PER_SECOND * elapsed,
			WIPE_REQUESTS_PER_SECOND)
	for id in _refill_budget:
		_refill_budget[id] = minf(_refill_budget[id] + REFILL_REQUESTS_PER_SECOND * elapsed,
			REFILL_REQUESTS_PER_SECOND)
	for id in _view_budget:
		_view_budget[id] = minf(_view_budget[id] + VIEW_REPORTS_PER_SECOND * elapsed,
			VIEW_REPORTS_PER_SECOND)
	_sweep_blocks()
	# Coast across brief packet loss, then release every held control.
	for id in _stage_input_received_at.keys():
		if now - float(_stage_input_received_at[id]) < STAGE_INPUT_TIMEOUT:
			continue
		_stage_input_received_at.erase(id)
		_client_input.erase(id)
		_input_queue.erase(id)
		var shooter = world.shooter_for(id)
		if shooter == null:
			continue
		shooter.player.input_move = Vector2.ZERO
		shooter.player.input_run = false
		shooter.player.input_jump = false
		shooter.firing = false
		shooter.bottle_shake_input = 0.0
		world.tomato_action(id, world.CANCEL_TOMATO_CHARGE_ACTION)
	# Drain one packet per client each tick, oldest first.
	for id in _input_queue:
		var queue: Array = _input_queue[id]
		if not queue.is_empty():
			_client_input[id] = queue.pop_front()
	for id in _client_input:
		var shooter = world.shooter_for(id)
		if shooter == null:
			continue
		var packet: Array = _client_input[id]
		shooter.player.input_move = packet[0]
		shooter.player.input_run = packet[1]
		shooter.player.input_jump = packet[5]
		shooter.player.server_input_sequence = int(packet[8]) if packet.size() > 8 else 0
		shooter.firing = packet[2] and not shooter.player.is_incapacitated() \
			and not shooter.player.is_wiping()
		shooter.aim_yaw = packet[3]
		shooter.aim_pitch = packet[4]
		if not lobby_flow:
			world.set_character_variant(id, packet[6])
		shooter.bottle_shake_input = packet[7] if not shooter.player.is_incapacitated() else 0.0


func _collect_state(ids: PackedInt32Array) -> PackedFloat32Array:
	var data := PackedFloat32Array()
	for id in world.shooter_ids():
		var shooter = world.shooter_for(id)
		var state: Array = shooter.player.network_state()
		var position: Vector3 = state[0]
		var velocity: Vector3 = state[2]
		ids.push_back(id)
		data.append_array(PackedFloat32Array([
			position.x, position.y, position.z, state[1],
			velocity.x, velocity.z,
			1.0 if shooter.firing else 0.0, world.effective_aim_pitch(shooter),
			float(state[3]), state[4], state[5], state[6], state[7],
			shooter.sauce, float(shooter.nozzle), world.bottle_state_code(shooter),
			shooter.bottle_shake_input, float(shooter.character_index),
			float(shooter.player.server_input_sequence), velocity.y,
			shooter.player.mustard_slow, shooter.player.cheese_snag_left,
			1.0 if shooter.player.in_mustard else 0.0, shooter.player.charge_effect_state(),
			shooter.stream_recoil_pitch, shooter.stream_recoil_yaw, shooter.hose_flow_age,
			shooter.player.external_drift.x, shooter.player.external_drift.z]))
	return data


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _submit_input(move: Vector2, run: bool, jump: bool, firing: bool,
		yaw: float, pitch: float, character_index := 0, shake := 0.0, sequence := 0) -> void:
	if not multiplayer.is_server() or not _world_ready():
		return
	if not _within_budget(multiplayer.get_remote_sender_id()):
		return
	# The bools need no range check -- there is no wrong value for a key being
	# down -- but the floats do, and they go through the same helpers as before.
	if not all_finite([move, yaw, pitch, shake]):
		rejected_packets += 1
		return
	var sender := multiplayer.get_remote_sender_id()
	var queue: Array = _input_queue.get(sender, [])
	queue.push_back([
		clamp_direction(move), run, firing, wrap_angle(yaw),
		clamp_angle(pitch, deg_to_rad(world.pitch_limit_degrees)), jump,
		clampi(character_index, 0, world.PLAYER_CHARACTERS.size() - 1),
		clamp_range(shake, 0.0, 1.0), clampi(sequence, 0, 16000000)])
	while queue.size() > INPUT_QUEUE_LIMIT:
		queue.pop_front()
	_input_queue[sender] = queue
	_stage_input_received_at[sender] = _now()


@rpc("authority", "call_remote", "unreliable_ordered")
func _apply_state(ids: PackedInt32Array, data: PackedFloat32Array) -> void:
	if not _world_ready():
		return
	debug_state_packets += 1
	for slot in ids.size():
		var index := slot * STATE_STRIDE
		if index + STATE_STRIDE > data.size():
			return
		var shooter = world.shooter_for(ids[slot])
		if shooter == null:
			continue
		shooter.player.apply_network_state(
			Vector3(data[index], data[index + 1], data[index + 2]),
			data[index + 3],
			Vector3(data[index + 4], data[index + 19], data[index + 5]),
			int(data[index + 8]), data[index + 9], data[index + 10],
			data[index + 11], data[index + 12], int(data[index + 18]),
			data[index + 20], data[index + 21], data[index + 22] > 0.5, data[index + 23],
			Vector3(data[index + 27], 0.0, data[index + 28]))
		# The bottle and what its nozzle is doing are the host's, for everyone
		# including the peer holding it: a client that decided its own would
		# catch at different moments from the screen next to it.
		shooter.sauce = clampf(data[index + 13], 0.0, 1.0)
		shooter.nozzle = clampi(int(round(data[index + 14])), 0, 3)
		world.apply_bottle_state_code(shooter, clampf(data[index + 15], 0.0, 3.0))
		shooter.stream_recoil_pitch = data[index + 24]
		shooter.stream_recoil_yaw = data[index + 25]
		shooter.hose_flow_age = data[index + 26]
		# Lobby characters arrive through the reliable roster.
		if not shooter.is_local:
			if not lobby_flow:
				world.set_character_variant(ids[slot],
					clampi(int(round(data[index + STATE_CHARACTER_INDEX])), 0,
						world.PLAYER_CHARACTERS.size() - 1))
			shooter.firing = data[index + 6] > 0.5
			# How hard they are shaking the bottle: theirs to say, and the
			# local player already knows their own.
			shooter.bottle_shake_input = clampf(data[index + 16], 0.0, 1.0)
			# The effective pitch already contains the lift applied by the host.
			shooter.aim_pitch = data[index + 7] - shooter.stream_recoil_pitch
			# The yaw has to land on the aim, not only on the body: _update_aim
			# rewrites the body from the aim every frame, and the strand leaves
			# along the aim too. Setting the body alone points a remote player's
			# spray back down whatever yaw this peer last had for them.
			shooter.aim_yaw = data[index + 3]
		else:
			shooter.player.rotation.y = shooter.aim_yaw


@rpc("authority", "call_remote", "unreliable_ordered")
func _apply_enemy_state(data: PackedFloat32Array, start: int, smooth: bool) -> void:
	if _world_ready():
		world.apply_enemy_state(data, smooth, start)


@rpc("authority", "call_remote", "unreliable_ordered")
func _apply_tomatina_status(status: PackedFloat64Array, threads: PackedFloat32Array) -> void:
	if _world_ready():
		world.apply_tomatina_status(status)
		world.apply_cheese_thread_state(threads)


## An enemy flinched or went down, and these players should feel it.
##
## **Reliable, and separate from the enemy state.** That state is
## `unreliable_ordered` and describes where a body *is*; this describes
## something that *happened*, once. A dropped state packet is corrected by the
## next one, but a dropped event is simply never seen -- and a flinch is over in
## a fifth of a second, so there is no next one to correct it.
func send_enemy_shake(enemy_index: int, peers: PackedInt32Array,
		degrees: float, seconds: float, accent := 0, sauce := -1) -> void:
	if not _online or not multiplayer.is_server():
		return
	if multiplayer.get_peers().is_empty():
		return
	_apply_enemy_shake.rpc(enemy_index, peers, degrees, seconds, accent, sauce)


@rpc("authority", "call_remote", "reliable")
func _apply_enemy_shake(enemy_index: int, peers: PackedInt32Array,
		degrees: float, seconds: float, accent := 0, sauce := -1) -> void:
	if not _world_ready():
		return
	# From the server, so the range checks are about surviving a corrupt packet
	# rather than about a hostile client -- but they are free and the rule in
	# this file is that nothing off the wire is trusted unchecked.
	if not all_finite([degrees, seconds]) or sauce < -1 or sauce > ContaminationGrid.KIND_KETCHUP:
		rejected_packets += 1
		return
	world.apply_enemy_shake(enemy_index, peers,
		clamp_range(degrees, 0.0, 90.0), clamp_range(seconds, 0.0, 5.0), clampi(accent, 0, 4), sauce)


# ---------------------------------------------------------------------------
# The tutorial
#
# Three messages, all from the server and all reliable, because all three are
# *events*: a body was added, a caption was said, the stage moved on. None of
# them is sent per frame -- which is what stops a caption from being replayed
# every time an ordinary state packet lands.
# ---------------------------------------------------------------------------

## One body the tutorial asked for. Every peer appends it, so the list stays the
## same list in the same order, which is what the state packet and the splat batch
## address a body by.
func broadcast_tutorial_enemy(kind: int, at: Vector3) -> void:
	if not _online or not multiplayer.is_server():
		return
	if multiplayer.get_peers().is_empty():
		return
	_add_tutorial_enemy.rpc(kind, at)


@rpc("authority", "call_remote", "reliable")
func _add_tutorial_enemy(kind: int, at: Vector3) -> void:
	if not _world_ready():
		return
	if not all_finite([at.x, at.y, at.z]):
		rejected_packets += 1
		return
	world.tutorial_add_enemy(kind, at)


func broadcast_tutorial_effect(kind: int, at: Vector3) -> void:
	if _online and multiplayer.is_server() and not multiplayer.get_peers().is_empty():
		_apply_tutorial_effect.rpc(kind, at)


@rpc("authority", "call_remote", "reliable")
func _apply_tutorial_effect(kind: int, at: Vector3) -> void:
	if not _world_ready():
		return
	if kind not in [0, 1] or not all_finite([at.x, at.y, at.z]):
		return
	world.apply_tutorial_effect(kind, at)


## A spitter's lump leaving its mouth: from where, how fast, and for how long
## at most. Everyone flies the same lump; what it does when it lands is the
## server's, and arrives as stains and health exactly as it always did.
func broadcast_spit(origin: Vector3, velocity: Vector3, seconds: float, lob := false) -> void:
	if _online and multiplayer.is_server() and not multiplayer.get_peers().is_empty():
		_show_spit.rpc(origin, velocity, seconds, lob)


@rpc("authority", "call_remote", "reliable")
func _show_spit(origin: Vector3, velocity: Vector3, seconds: float, lob: bool) -> void:
	if not _world_ready():
		return
	var sane := all_finite([origin.x, origin.y, origin.z, velocity.x, velocity.y, velocity.z, seconds])
	if not sane or seconds < 0.0 or seconds > 5.0 or velocity.length() > 60.0:
		rejected_packets += 1
		return
	world.show_spit(origin, velocity, seconds, lob)


func broadcast_overripe_burst(at: Vector3, radius: float, priming: bool) -> void:
	if is_online() and is_server():
		_show_overripe_burst.rpc(at, radius, priming)


@rpc("authority", "call_remote", "reliable")
func _show_overripe_burst(at: Vector3, radius: float, priming: bool) -> void:
	if world != null:
		world.show_overripe_burst(at, radius, priming)


func broadcast_tomato_fuse(at: Vector3) -> void:
	if is_online() and is_server():
		_show_tomato_fuse.rpc(at)


@rpc("authority", "call_remote", "reliable")
func _show_tomato_fuse(at: Vector3) -> void:
	if world != null:
		world._show_tomato_fuse(at)


func broadcast_tomato_blast(at: Vector3, radius: float, sauce := -1) -> void:
	if _online and multiplayer.is_server() and not multiplayer.get_peers().is_empty():
		_show_tomato_blast.rpc(at, radius, sauce)


@rpc("authority", "call_remote", "reliable")
func _show_tomato_blast(at: Vector3, radius: float, sauce := -1) -> void:
	if _world_ready() and all_finite([at.x, at.y, at.z, radius]) and radius >= 0.5 and radius <= 12.0 \
			and sauce >= -1 and sauce <= ContaminationGrid.KIND_KETCHUP:
		world.show_tomato_blast(at, radius, sauce)


## One caption. The index of the line, not the line: both ends hold the same
## table, so the text cannot drift and a caption costs four bytes.
func broadcast_tutorial_line(line_id: int, urgent := false, tag := 0) -> void:
	if not _online or not multiplayer.is_server():
		return
	if multiplayer.get_peers().is_empty():
		return
	_apply_tutorial_line.rpc(line_id, urgent, tag)


## A caption that has stopped applying. An event like the line itself, so the
## withdrawal lands on every screen the same way the caption did.
func broadcast_tutorial_cancel(tag: int) -> void:
	if not _online or not multiplayer.is_server():
		return
	if multiplayer.get_peers().is_empty():
		return
	_apply_tutorial_cancel.rpc(tag)


@rpc("authority", "call_remote", "reliable")
func _apply_tutorial_cancel(tag: int) -> void:
	if not _world_ready():
		return
	world.apply_tutorial_cancel(tag)


## The same, to one peer: what somebody arriving mid-stage is told.
func send_tutorial_line(peer_id: int, line_id: int) -> void:
	if not _online or not multiplayer.is_server():
		return
	_apply_tutorial_line.rpc_id(peer_id, line_id, false, 0)


@rpc("authority", "call_remote", "reliable")
func _apply_tutorial_line(line_id: int, urgent: bool, tag: int) -> void:
	if not _world_ready():
		return
	world.apply_tutorial_line(line_id, urgent, tag)


## Stage, roster and who has topped up. Sent when one of them changes, and to a
## peer as it joins so a late arrival is on the same stage as everyone else.
func broadcast_tutorial_state(data: PackedInt32Array) -> void:
	if not _online or not multiplayer.is_server():
		return
	if multiplayer.get_peers().is_empty():
		return
	_apply_tutorial_state.rpc(data)


func send_tutorial_state(peer_id: int, data: PackedInt32Array) -> void:
	if not _online or not multiplayer.is_server():
		return
	_apply_tutorial_state.rpc_id(peer_id, data)


@rpc("authority", "call_remote", "reliable")
func _apply_tutorial_state(data: PackedInt32Array) -> void:
	if not _world_ready():
		return
	world.apply_tutorial_state(data)


@rpc("authority", "call_remote", "reliable")
func _apply_splats(data: PackedInt32Array) -> void:
	if not _world_ready():
		return
	world.apply_splats(data)


@rpc("authority", "call_remote", "reliable")
func _spawn_avatar(id: int, slot: int) -> void:
	if not _world_ready():
		return
	_slots[id] = slot
	world.create_avatar(id, slot, false)


@rpc("authority", "call_remote", "reliable")
func _despawn_avatar(id: int) -> void:
	if not _world_ready():
		return
	world.remove_avatar(id)


## First message a joining client gets: the offline body it has been walking
## around in is not part of the session, and this is the body it now owns.
@rpc("authority", "call_remote", "reliable")
func _join_session(id: int, slot: int) -> void:
	_slots[id] = slot
	world.reset_for_join()
	world.claim_avatar(id, slot)


@rpc("authority", "call_remote", "reliable")
func _load_grid(index: int, cells: PackedByteArray, raw_size: int) -> void:
	if raw_size > 0:
		cells = cells.decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	world.apply_grid_snapshot_part(index, cells)


@rpc("authority", "call_remote", "reliable")
func _load_body_grid(peer_id: int, cells: PackedByteArray) -> void:
	world.apply_body_snapshot(peer_id, cells)


@rpc("authority", "call_remote", "reliable")
func _load_visor_grid(peer_id: int, cells: PackedByteArray) -> void:
	world.apply_visor_snapshot(peer_id, cells)


func _ready() -> void:
	# Ahead of the bodies, which run at -10: a client's keys have to be in place
	# before the server steps the body they drive.
	process_physics_priority = -20


func _physics_process(delta: float) -> void:
	_drop_pending()
	if _lobby_broadcast_at > 0.0 and _now() >= _lobby_broadcast_at:
		_lobby_broadcast_at = 0.0
		_broadcast_lobby()
		_try_authorize_play()
	apply_client_input()
	run_lobby(delta)
	if lobby_flow and is_server() and session_phase == SessionPhase.LOADING:
		_load_clock += delta
		if _load_clock >= LOAD_TIMEOUT:
			_fail_loading(STAGE_LOAD_TIMEOUT)


## Peers that were answered last frame. Whatever was said to them has had a frame
## to leave the host by now.
func _drop_pending() -> void:
	if _pending_drops.is_empty() or not _online:
		return
	var now := _now()
	for index in range(_pending_drops.size() - 1, -1, -1):
		var id := _pending_drops[index]
		if now < float(_pending_drop_after.get(id, now)):
			continue
		if _peer_can_receive(id):
			multiplayer.multiplayer_peer.disconnect_peer(id)
		_pending_drops.remove_at(index)
		_pending_drop_after.erase(id)


func _peer_can_receive(id: int) -> bool:
	var enet := _peer as ENetMultiplayerPeer
	if enet == null:
		return false
	var packet_peer := enet.get_peer(id)
	return packet_peer != null and packet_peer.get_state() == ENetPacketPeer.STATE_CONNECTED


@rpc("authority", "call_remote", "unreliable_ordered")
func _apply_healing_tomato_state(data: PackedFloat64Array) -> void:
	if _world_ready():
		world.apply_healing_tomato_state(data)


func broadcast_shove_clearance(peer: int, indices: PackedInt32Array) -> void:
	if _online and multiplayer.is_server():
		_apply_shove_clearance.rpc(peer, indices)


@rpc("authority", "call_remote", "reliable")
func _apply_shove_clearance(peer: int, indices: PackedInt32Array) -> void:
	if _world_ready():
		world.apply_shove_clearance(peer, indices)


func broadcast_combat_warning(at: Vector3, direction: Vector3, duration: float, cue: int) -> void:
	if _online and multiplayer.is_server():
		_show_combat_warning.rpc(at, direction, duration, cue)


@rpc("authority", "call_remote", "reliable")
func _show_combat_warning(at: Vector3, direction: Vector3, duration: float, cue: int) -> void:
	if _world_ready():
		world.show_combat_warning(at, direction, duration, cue)


func send_contact_confirmation(peer: int) -> void:
	if _online and is_server() and _peer_can_receive(peer):
		_confirm_contact.rpc_id(peer)


@rpc("authority", "call_remote", "reliable")
func _confirm_contact() -> void:
	if _world_ready() and world._crosshair is Crosshair:
		world._confirmed_contact_until = Time.get_ticks_msec() + 180
		world._crosshair.confirm_impact(false)


func request_context_action(kind: String, target: int) -> void:
	if _online and _joined:
		_context_action.rpc_id(1, kind, target)


@rpc("any_peer", "call_remote", "reliable")
func _context_action(kind: String, target: int) -> void:
	if not is_server() or not _world_ready() or kind.length() > 16:
		return
	var sender := multiplayer.get_remote_sender_id()
	# A release or completed hold belongs to the already rate-limited start.
	if kind == "loot_cancel" or kind == "loot_finish":
		world.perform_context_action(sender, kind, target)
		return
	if float(_refill_budget.get(sender, REFILL_REQUESTS_PER_SECOND)) < 1.0:
		return
	_refill_budget[sender] = float(_refill_budget.get(sender, REFILL_REQUESTS_PER_SECOND)) - 1.0
	world.perform_context_action(sender, kind, target)


func request_tomato_action(action: int) -> void:
	if _online and _joined:
		_request_tomato_action.rpc_id(1, action)


@rpc("any_peer", "call_remote", "reliable")
func _request_tomato_action(action: int) -> void:
	if multiplayer.is_server() and _world_ready() and action >= 0 and action <= 14:
		world.tomato_action(multiplayer.get_remote_sender_id(), action)


@rpc("authority", "call_remote", "reliable")
func _apply_inventory_state(data: PackedInt32Array) -> void:
	if _world_ready():
		world.apply_inventory_state(data)


func request_sauce_part(part: int) -> void:
	if _online and _joined:
		_buy_sauce_part.rpc_id(1, part)


@rpc("any_peer", "call_remote", "reliable")
func _buy_sauce_part(part: int) -> void:
	if multiplayer.is_server() and _world_ready() and _within_budget(multiplayer.get_remote_sender_id()):
		world.buy_or_equip_sauce_part(multiplayer.get_remote_sender_id(), part)


@rpc("authority", "call_remote", "reliable")
func _apply_sauce_shop_state(data: PackedInt32Array, coins: PackedFloat32Array) -> void:
	if _world_ready():
		world.apply_sauce_shop_state(data, coins)


func broadcast_part_volley(peer: int, part: int, sauce: int, origin: Vector3, forward: Vector3) -> void:
	if _online and multiplayer.is_server() and _world_ready():
		_show_part_volley.rpc(peer, part, sauce, origin, forward)


@rpc("authority", "call_remote", "reliable")
func _show_part_volley(peer: int, part: int, sauce: int, origin: Vector3, forward: Vector3) -> void:
	if _world_ready():
		world.show_part_volley(peer, part, sauce, origin, forward)


@rpc("authority", "call_remote", "unreliable_ordered")
func _apply_player_motion_state(data: PackedFloat64Array) -> void:
	if _world_ready():
		world.apply_player_motion_state(data)
