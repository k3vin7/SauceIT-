extends "res://tests/probe_network.gd"
func _run() -> void:
	server_world = _make_world("ServerView", "World")
	client_world = _make_world("ClientView", "World")
	await physics_frame
	set_multiplayer(SceneMultiplayer.new(), ^"/root/ServerView/World")
	set_multiplayer(SceneMultiplayer.new(), ^"/root/ClientView/World")
	_check(server_world._net.host(24781, true), "context host failed")
	_check(client_world._net.join("127.0.0.1", 24781), "context client failed")
	await _settled(server_world, client_world)
	if not failures.is_empty():
		_finish()
		return
	var peer: int = client_world._local.peer_id
	client_world._health_hud.feedback_rows.clear()
	server_world._health_hud.feedback_rows.clear()
	server_world._net.send_enemy_shake(0, PackedInt32Array([peer]), 0.0, 0.0, 2)
	for i in 12:
		await physics_frame
	_check(not client_world._health_hud.feedback_rows.is_empty(), "confirmed kill feedback did not reach contributing client")
	_check(server_world._health_hud.feedback_rows.is_empty(), "client kill feedback leaked to host")
	if failures.is_empty():
		print("CONTEXT_NETWORK_OK")
	_finish()
