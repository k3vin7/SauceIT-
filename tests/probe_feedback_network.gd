extends "res://tests/probe_network.gd"

class ConfirmationProbe:
	extends Crosshair
	var flinches := 0
	var defeats := 0

	func confirm_impact(killed: bool, weak_spot := false) -> void:
		if killed:
			defeats += 1
		else:
			flinches += 1
		super.confirm_impact(killed, weak_spot)

# Reliable impact accents must reach the contributing client exactly once,
# even before the enemy's unreliable health snapshot arrives.
func _run() -> void:
	server_world = _make_world("ServerView", "World")
	client_world = _make_world("ClientView", "World")
	await physics_frame
	set_multiplayer(SceneMultiplayer.new(), ^"/root/ServerView/World")
	set_multiplayer(SceneMultiplayer.new(), ^"/root/ClientView/World")
	_check(server_world._net.host(24779, true), "feedback host could not open port")
	_check(client_world._net.join("127.0.0.1", 24779), "feedback client could not join")
	await _settled(server_world, client_world)
	_check(client_world._net.debug_state_packets > 0, "feedback client did not connect")
	if not failures.is_empty():
		_finish()
		return
	for world in [server_world, client_world]:
		for enemy in world._enemies:
			enemy.move_speed = 0.0
			enemy.contact_damage = 0.0
	# Count delivered events rather than polling a 120 ms visual pulse: heavy
	# headless frames can render and expire that pulse between physics polls.
	var client_probe := ConfirmationProbe.new()
	var server_probe := ConfirmationProbe.new()
	client_world.add_child(client_probe)
	server_world.add_child(server_probe)
	client_world._crosshair = client_probe
	server_world._crosshair = server_probe
	var client_id: int = client_world._net.local_id()
	var peers := PackedInt32Array([client_id])
	client_world._crosshair.impact_left = 0.0
	server_world._net.send_enemy_shake(0, peers, 0.0, 0.12, 1)
	_check(await _until(func(): return client_probe.flinches == 1, 900),
		"flinch accent never arrived on contributing client")
	_check(client_probe.defeats == 0, "flinch was decoded as defeat")
	_check(server_probe.flinches == 0 and server_probe.defeats == 0, "non-contributor received the accent")
	await _wait(20)
	client_world._crosshair.impact_left = 0.0
	server_world._net.send_enemy_shake(0, peers, 0.0, 0.3, 2)
	_check(await _until(func(): return client_probe.defeats == 1, 900),
		"defeat accent never arrived independently of health state")
	await _wait(25)
	_check(client_probe.defeats == 1 and client_probe.flinches == 1, "defeat accent repeated without another event")
	server_world._net.send_enemy_shake(0, PackedInt32Array([1]), 0.0, 0.3, 2)
	await _wait(8)
	_check(client_probe.defeats == 1, "client received another player's kill confirmation")

	client_world._prepare_tomatina_blast_effects()
	var blast := client_world._blast_effects.back() as Node3D
	var flash := blast.get_child(0) as MeshInstance3D
	var hit := client_world._blast_hits.back() as MeshInstance3D
	var blast_tint := flash.material_override as StandardMaterial3D
	var hit_tint := hit.material_override as StandardMaterial3D
	var mustard := ContaminationGrid.KIND_MUSTARD
	var mayo := ContaminationGrid.KIND_MAYO
	server_world._net.broadcast_tomato_blast(Vector3(0.0, 3.0, -10.0), 2.0, mustard)
	server_world._net.send_enemy_shake(0, PackedInt32Array(), 0.0, 0.0, 4, mayo)
	_check(await _until(func():
		return Color(blast_tint.albedo_color, 1.0) == client_world.SAUCE_TINTS[mustard] \
			and Color(hit_tint.albedo_color, 1.0) == client_world.SAUCE_TINTS[mayo], 180),
		"the client did not receive the blast and splash hit colors")

	if failures.is_empty():
		print("MAYO_FEEDBACK_NETWORK_OK")
	_finish()
