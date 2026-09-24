class_name MayoNet
extends Node

## LAN session for two players over ENet. One peer hosts, the other types an IP.
## There is no lobby and no matchmaking: pressing Host opens the port, and the
## first peer to connect is the second player.
##
## What crosses the wire, and what does not:
##
##   * Movement is the server's. Clients send keys and aim and nothing else;
##     the server runs both bodies and sends back where they ended up, along
##     with the fall state and its timer, so a fall plays out identically on
##     both screens. There is no prediction: on a LAN the round trip is a frame
##     or two. The one exception is the local player's aim, which is applied
##     the moment the mouse moves, or the view would lag the hand.
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
## What one peer may send per tick. A client sends one input a tick and no more
## -- there is nothing a second one could say that the first did not -- so any
## extra is either a duplicate or someone flooding, and either way the first is
## the one to keep.
const INPUT_PACKETS_PER_TICK := 1
## Wipes are rarer and travel reliably, which makes them the more expensive
## thing to flood. A wipe takes wipe_duration to finish and cannot be started
## during one, so nobody can legitimately complete more than about 1.4 a second;
## five leaves room for mashing the key and for retries without leaving the
## reliable channel open to abuse.
const WIPE_REQUESTS_PER_SECOND := 5.0
## Same idea for the refill key: a peer leaning on E costs itself the bandwidth
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
## level, nozzle state. The peer ids travel alongside as ints -- a peer id is a
## full 32-bit random number and does not survive a round trip through a 32-bit
## float.
##
## The last two are why this grew. Everything else about a squirt follows from
## the trigger flag every peer already has, but an unreliable nozzle catches on
## a coin toss, and a coin tossed separately on each machine gives every player
## a different fight. The host tosses it and sends the answer; the level rides
## along rather than being derived, so nobody has to guess which band a bottle
## is in either.
const STATE_STRIDE := 15
## What that costs the host. One player is 15 floats plus a 4-byte id, so 64
## bytes; a four-player session is 256 bytes of state a frame, and the host sends
## it to each of the three guests at the physics rate:
##
##     4 x 64 x 3 guests x 60 Hz = 46.1 kB/s of state
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


func bind(new_world: Node) -> void:
	world = new_world


func is_online() -> bool:
	return _online


## True offline as well: a session of one is its own authority, which keeps the
## single-player path identical to what it was before any of this existed.
func is_server() -> bool:
	return not _online or multiplayer.is_server()


func status() -> String:
	return _status


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
	if lobby_code.is_empty() and not open_to_anyone:
		lobby_code = generate_code()
	# Somebody else's door, and no longer the one in front of this player.
	_blocked_until_local = 0.0
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_CLIENTS)
	if error != OK:
		_set_status("could not open port %d (error %d)" % [port, error])
		return false
	_peer = peer
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
	if not _online:
		return
	multiplayer.multiplayer_peer = null
	_peer = null
	_online = false
	_client_input.clear()
	_input_this_tick.clear()
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
	_next_sweep = 0.0
	_slots = {1: 0}
	_refused_for_code = false
	_joined = false
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
	return ("mayo1:" + lobby_code).to_utf8_buffer()


func _on_peer_authenticating(id: int) -> void:
	var scene_multiplayer := multiplayer as SceneMultiplayer
	if scene_multiplayer == null:
		return
	# A blocked address is not asked for the code at all: it is told how long it
	# has left and dropped, before either side has said anything else.
	if multiplayer.is_server():
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
				_pending_drops.push_back(id)
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


## The host decides; a guest accepts whatever the host says, since the host has
## already checked the guest by the time it answers.
func _check_code(id: int, data: PackedByteArray) -> void:
	var scene_multiplayer := multiplayer as SceneMultiplayer
	if scene_multiplayer == null:
		return
	if not multiplayer.is_server():
		var message := data.get_string_from_utf8()
		if message.begins_with(AUTH_BLOCKED_PREFIX):
			# Not completed: there is nothing to join. The host is about to drop
			# this peer, and the wait is what there is to report.
			_blocked_until_local = _now() + float(
				message.trim_prefix(AUTH_BLOCKED_PREFIX).to_int())
			return
		scene_multiplayer.complete_auth(id)
		return
	# Already told why it is not coming in, and waiting on the drop. Whatever it
	# sent after that is not a guess at the code.
	if _pending_drops.has(id):
		return
	var address := _address_of(id)
	if data == _auth_payload():
		# Getting it right clears the slate: a player who mistyped it twice and
		# then got in is not working towards a block.
		_code_failures.erase(address)
		scene_multiplayer.complete_auth(id)
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
	if not multiplayer.is_server():
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
	var slot := _free_slot()
	_slots[id] = slot
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
	var snapshot: Array = world.grid_snapshot()
	for index in snapshot.size():
		_load_grid.rpc_id(id, index, snapshot[index])
	# Bodies too: whoever is already in the session may already be covered.
	for existing_id in world.shooter_ids():
		var body: PackedByteArray = world.body_snapshot(existing_id)
		if not body.is_empty():
			_load_body_grid.rpc_id(id, existing_id, body)
		var visor: PackedByteArray = world.visor_snapshot(existing_id)
		if not visor.is_empty():
			_load_visor_grid.rpc_id(id, existing_id, visor)
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
	_client_input.erase(id)
	_input_this_tick.erase(id)
	_wipe_budget.erase(id)
	_refill_budget.erase(id)
	_view_budget.erase(id)
	_views.erase(id)
	_slots.erase(id)
	if multiplayer.is_server():
		world.remove_avatar(id)
		_despawn_avatar.rpc(id)
	_set_status("player %d left" % id)


func _on_connected_to_server() -> void:
	_joined = true
	_blocked_until_local = 0.0
	# The world is not touched here: the server's first message does that, so
	# that a spawn cannot land before the reset and be wiped by it.
	_set_status("connected as player %d" % multiplayer.get_unique_id())


func _on_connection_failed() -> void:
	var refused := _refused_for_code
	var waiting := blocked_seconds()
	leave()
	if waiting > 0:
		_set_status("blocked, %d s left" % waiting)
		return
	_set_status("wrong lobby code" if refused else "connection failed")


func _on_server_disconnected() -> void:
	# A guest that never got as far as being in the session was refused at the
	# handshake, which is the only thing the host drops a peer over before it has
	# a body. Once it is in, the same signal means what it always did.
	var refused := _refused_for_code or not _joined
	var waiting := blocked_seconds()
	leave()
	world.reset_to_offline()
	if waiting > 0:
		_set_status("blocked, %d s left" % waiting)
		return
	_set_status("wrong lobby code" if refused else "host closed the session")


func _set_status(message: String) -> void:
	_status = message
	status_changed.emit(message)


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
	if not _online or not multiplayer.is_server():
		return
	var guests := multiplayer.get_peers().size()
	if not splats.is_empty():
		_apply_splats.rpc(splats)
		splat_bytes_sent += splats.size() * 4 * guests
	if guests == 0:
		return
	var ids := PackedInt32Array()
	var state := _collect_state(ids)
	_apply_state.rpc(ids, state)
	state_bytes_sent += (ids.size() + state.size()) * 4 * guests
	# Enemies are the server's outright -- clients simulate none of them -- so
	# they are sent, never asked for. Unreliable like the player state: a
	# dropped frame is corrected by the next one.
	var enemies: PackedFloat32Array = world.enemy_state()
	if not enemies.is_empty():
		_apply_enemy_state.rpc(enemies)
		state_bytes_sent += enemies.size() * 4 * guests


## R, on a client. The wipe is a change everyone sees, so the client asks and
## the server decides -- the server owns whether the lenses are dirty enough to
## be worth wiping and whether the player is in a state to do it.
func request_wipe() -> void:
	if not _online or multiplayer.is_server():
		return
	if _peer == null or _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_request_wipe.rpc_id(1)


## No numbers to range-check here: the packet carries nothing but the fact that
## a key was pressed, and the sender is taken from the connection rather than
## from the message. Anything added to it goes through `all_finite` and the
## clamps above, like every other client input.
@rpc("any_peer", "call_remote", "reliable")
func _request_wipe() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if _wipe_budget.get(sender, WIPE_REQUESTS_PER_SECOND) < 1.0:
		dropped_packets += 1
		return
	_wipe_budget[sender] = _wipe_budget.get(sender, WIPE_REQUESTS_PER_SECOND) - 1.0
	world.begin_wipe_for(sender)


## E, on a client. Carries nothing but the fact that a key went down: where the
## player is standing is the server's own copy of them, not something the packet
## gets to claim.
func request_refill() -> void:
	if not _online or multiplayer.is_server():
		return
	if _peer == null or _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_request_refill.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_refill() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if _refill_budget.get(sender, REFILL_REQUESTS_PER_SECOND) < 1.0:
		dropped_packets += 1
		return
	_refill_budget[sender] = _refill_budget.get(sender, REFILL_REQUESTS_PER_SECOND) - 1.0
	world.refill_for(sender)


## The host telling everyone a bottle was filled. An event, not a value in the
## state packet: refills are rare and the drain is already derived everywhere.
func broadcast_refill(peer_id: int) -> void:
	if not _online or not multiplayer.is_server():
		return
	_apply_refill.rpc(peer_id)


@rpc("authority", "call_remote", "reliable")
func _apply_refill(peer_id: int) -> void:
	world.apply_refill(peer_id)


## Called every frame with whatever the local camera currently is. Sends only
## when it has changed, and no more often than the host will listen, so the host
## never has to drop a report an honest client sent.
func report_view(fov_degrees: float, aspect: float, delta: float) -> void:
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
	if _peer == null or _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
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
	if not multiplayer.is_server():
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
	if multiplayer.is_server():
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


func send_input(move: Vector2, run: bool, jump: bool, firing: bool,
		yaw: float, pitch: float) -> void:
	if not _online or multiplayer.is_server():
		return
	# The handshake takes a few frames, and the keys sent during it have nowhere
	# to go yet.
	if _peer == null or _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_submit_input.rpc_id(1, move, run, jump, firing, yaw, pitch)


## The server applies the last input it heard from each client before running
## the bodies, so a client that misses a tick keeps walking rather than stopping.
func apply_client_input() -> void:
	if not _online or not multiplayer.is_server():
		return
	# A fresh allowance every tick. Anything a peer sent past last tick's was
	# dropped as it arrived, so there is nothing here to catch up on.
	_input_this_tick.clear()
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
	for id in _client_input:
		var shooter = world.shooter_for(id)
		if shooter == null:
			continue
		var packet: Array = _client_input[id]
		shooter.player.input_move = packet[0]
		shooter.player.input_run = packet[1]
		shooter.player.input_jump = packet[5]
		shooter.firing = packet[2] and not shooter.player.is_incapacitated() \
			and not shooter.player.is_wiping()
		shooter.aim_yaw = packet[3]
		shooter.aim_pitch = packet[4]


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
			1.0 if shooter.firing else 0.0, shooter.aim_pitch,
			float(state[3]), state[4], state[5], state[6], state[7],
			shooter.sauce, float(shooter.nozzle)]))
	return data


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _submit_input(move: Vector2, run: bool, jump: bool, firing: bool,
		yaw: float, pitch: float) -> void:
	if not multiplayer.is_server():
		return
	if not _within_budget(multiplayer.get_remote_sender_id()):
		return
	# The bools need no range check -- there is no wrong value for a key being
	# down -- but the floats do, and they go through the same helpers as before.
	if not all_finite([move, yaw, pitch]):
		rejected_packets += 1
		return
	_client_input[multiplayer.get_remote_sender_id()] = [
		clamp_direction(move), run, firing, wrap_angle(yaw),
		clamp_angle(pitch, deg_to_rad(world.pitch_limit_degrees)), jump]


@rpc("authority", "call_remote", "unreliable_ordered")
func _apply_state(ids: PackedInt32Array, data: PackedFloat32Array) -> void:
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
			Vector3(data[index + 4], 0.0, data[index + 5]),
			int(data[index + 8]), data[index + 9], data[index + 10],
			data[index + 11], data[index + 12])
		# The bottle and what its nozzle is doing are the host's, for everyone
		# including the peer holding it: a client that decided its own would
		# catch at different moments from the screen next to it.
		shooter.sauce = clampf(data[index + 13], 0.0, 1.0)
		shooter.nozzle = clampi(int(round(data[index + 14])), 0, 3)
		# The local player's own aim is never taken back from the server: it is
		# already ahead of this packet.
		if not shooter.is_local:
			shooter.firing = data[index + 6] > 0.5
			shooter.aim_pitch = data[index + 7]
			# The yaw has to land on the aim, not only on the body: _update_aim
			# rewrites the body from the aim every frame, and the strand leaves
			# along the aim too. Setting the body alone points a remote player's
			# spray back down whatever yaw this peer last had for them.
			shooter.aim_yaw = data[index + 3]
		else:
			shooter.player.rotation.y = shooter.aim_yaw


@rpc("authority", "call_remote", "unreliable_ordered")
func _apply_enemy_state(data: PackedFloat32Array) -> void:
	world.apply_enemy_state(data)


## An enemy flinched or went down, and these players should feel it.
##
## **Reliable, and separate from the enemy state.** That state is
## `unreliable_ordered` and describes where a body *is*; this describes
## something that *happened*, once. A dropped state packet is corrected by the
## next one, but a dropped event is simply never seen -- and a flinch is over in
## a fifth of a second, so there is no next one to correct it.
func send_enemy_shake(enemy_index: int, peers: PackedInt32Array,
		degrees: float, seconds: float) -> void:
	if not _online or not multiplayer.is_server():
		return
	if multiplayer.get_peers().is_empty():
		return
	_apply_enemy_shake.rpc(enemy_index, peers, degrees, seconds)


@rpc("authority", "call_remote", "reliable")
func _apply_enemy_shake(enemy_index: int, peers: PackedInt32Array,
		degrees: float, seconds: float) -> void:
	# From the server, so the range checks are about surviving a corrupt packet
	# rather than about a hostile client -- but they are free and the rule in
	# this file is that nothing off the wire is trusted unchecked.
	if not all_finite([degrees, seconds]):
		rejected_packets += 1
		return
	world.apply_enemy_shake(enemy_index, peers,
		clamp_range(degrees, 0.0, 90.0), clamp_range(seconds, 0.0, 5.0))


@rpc("authority", "call_remote", "reliable")
func _apply_splats(data: PackedInt32Array) -> void:
	world.apply_splats(data)


@rpc("authority", "call_remote", "reliable")
func _spawn_avatar(id: int, slot: int) -> void:
	_slots[id] = slot
	world.create_avatar(id, slot, false)


@rpc("authority", "call_remote", "reliable")
func _despawn_avatar(id: int) -> void:
	world.remove_avatar(id)


## First message a joining client gets: the offline body it has been walking
## around in is not part of the session, and this is the body it now owns.
@rpc("authority", "call_remote", "reliable")
func _join_session(id: int, slot: int) -> void:
	_slots[id] = slot
	world.reset_for_join()
	world.claim_avatar(id, slot)


@rpc("authority", "call_remote", "reliable")
func _load_grid(index: int, cells: PackedByteArray) -> void:
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


func _physics_process(_delta: float) -> void:
	_drop_pending()
	apply_client_input()


## Peers that were answered last frame. Whatever was said to them has had a frame
## to leave the host by now.
func _drop_pending() -> void:
	if _pending_drops.is_empty() or not _online:
		return
	for id in _pending_drops:
		multiplayer.multiplayer_peer.disconnect_peer(id)
	_pending_drops.clear()
