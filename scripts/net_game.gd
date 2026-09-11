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
const MAX_CLIENTS := 1
## Floats per player in a state packet: position xyz, yaw, velocity xz, firing,
## aim pitch, fall state, fall timer, fall direction, wipe timer. The peer ids
## travel alongside as ints -- a peer id is a full 32-bit random number and does
## not survive a round trip through a 32-bit float.
const STATE_STRIDE := 12

signal status_changed(message: String)

var world: Node

var _peer: ENetMultiplayerPeer
var _online := false
var _status := "offline"
## peer id -> the last input packet from that client, applied every tick until
## the next one arrives so a dropped packet coasts instead of stuttering.
var _client_input: Dictionary = {}
## Join order, which is what decides spawn points. The host is always slot 0.
var _slots: Dictionary = {1: 0}
var _next_slot := 1
var debug_state_packets := 0
## Client packets thrown away for carrying a value that is not a number.
var rejected_packets := 0


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

func host(port := DEFAULT_PORT) -> bool:
	if _online:
		return false
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_CLIENTS)
	if error != OK:
		_set_status("could not open port %d (error %d)" % [port, error])
		return false
	_peer = peer
	multiplayer.multiplayer_peer = peer
	_online = true
	_connect_signals()
	# The host keeps the body it already had; it just stops being the only one.
	_set_status("hosting on port %d, waiting for a player" % port)
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
	_set_status("offline")


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
	var slot := _next_slot
	_next_slot += 1
	_slots[id] = slot
	world.create_avatar(id, slot, false)
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


func _on_peer_disconnected(id: int) -> void:
	_client_input.erase(id)
	_slots.erase(id)
	if multiplayer.is_server():
		world.remove_avatar(id)
		_despawn_avatar.rpc(id)
	_set_status("player %d left" % id)


func _on_connected_to_server() -> void:
	# The world is not touched here: the server's first message does that, so
	# that a spawn cannot land before the reset and be wiped by it.
	_set_status("connected as player %d" % multiplayer.get_unique_id())


func _on_connection_failed() -> void:
	leave()
	_set_status("connection failed")


func _on_server_disconnected() -> void:
	leave()
	world.reset_to_offline()
	_set_status("host closed the session")


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
	if not splats.is_empty():
		_apply_splats.rpc(splats)
	if multiplayer.get_peers().is_empty():
		return
	var ids := PackedInt32Array()
	var state := _collect_state(ids)
	_apply_state.rpc(ids, state)


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
	world.begin_wipe_for(multiplayer.get_remote_sender_id())


func send_input(move: Vector2, run: bool, firing: bool, yaw: float, pitch: float) -> void:
	if not _online or multiplayer.is_server():
		return
	# The handshake takes a few frames, and the keys sent during it have nowhere
	# to go yet.
	if _peer == null or _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_submit_input.rpc_id(1, move, run, firing, yaw, pitch)


## The server applies the last input it heard from each client before running
## the bodies, so a client that misses a tick keeps walking rather than stopping.
func apply_client_input() -> void:
	if not _online or not multiplayer.is_server():
		return
	for id in _client_input:
		var shooter = world.shooter_for(id)
		if shooter == null:
			continue
		var packet: Array = _client_input[id]
		shooter.player.input_move = packet[0]
		shooter.player.input_run = packet[1]
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
			float(state[3]), state[4], state[5], state[6]]))
	return data


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _submit_input(move: Vector2, run: bool, firing: bool, yaw: float, pitch: float) -> void:
	if not multiplayer.is_server():
		return
	if not all_finite([move, yaw, pitch]):
		rejected_packets += 1
		return
	_client_input[multiplayer.get_remote_sender_id()] = [
		clamp_direction(move), run, firing, wrap_angle(yaw),
		clamp_angle(pitch, deg_to_rad(world.pitch_limit_degrees))]


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
			data[index + 11])
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
	apply_client_input()
