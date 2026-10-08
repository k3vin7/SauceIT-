extends SceneTree

# Real ENet session: personal pickups, shared story/effects, a joining peer's
# offline roster reset, identical spill, refill requests and leaving mid-lesson.

const PORT := 24797

var failures: Array[String] = []
var _worlds: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.push_back(message)


func _make_world(index: int):
	var viewport := SubViewport.new()
	viewport.name = "Peer%d" % index
	viewport.own_world_3d = true
	viewport.size = Vector2i(64, 64)
	viewport.physics_object_picking = false
	root.add_child(viewport)
	var world = load("res://tutorial_world.tscn").instantiate()
	world.name = "World"
	viewport.add_child(world)
	world.set_process_unhandled_input(false)
	_worlds.push_back(world)
	return world


func _until(condition: Callable, frames := 2400) -> bool:
	for _f in frames:
		if condition.call():
			return true
		await process_frame
		await physics_frame
	return false


func _wait(frames: int) -> void:
	for _f in frames:
		await process_frame
		await physics_frame


## Every world's enemy list as "kind@index", so a mismatch names itself.
func _roster_signature(world) -> String:
	var parts := PackedStringArray()
	for index in world.enemy_count():
		var enemy: MayoEnemy = world.enemy_at(index)
		parts.push_back("%d:%d" % [index, enemy.kind if enemy != null else -1])
	return " ".join(parts)


## Kills a body with the damage call the stream uses.
func _hose_to_death(enemy: MayoEnemy) -> void:
	var guard := 0
	while enemy.is_alive() and guard < 4000:
		enemy.take_sauce_hit(enemy.global_position + Vector3(0.0, 0.0, 2.0))
		guard += 1


func _run() -> void:
	var host = _make_world(0)
	var guest = _make_world(1)
	await physics_frame
	for world in _worlds:
		set_multiplayer(SceneMultiplayer.new(), world.get_path())
		world.debug_set_input(Vector2.ZERO, false, false)
	host._net.host(PORT, true)
	guest._net.join("127.0.0.1", PORT)
	if not await _until(func(): return host.party_size() == 2 and guest.party_size() == 2 \
		and guest._net.debug_state_packets > 0):
		_check(false, "session did not connect")
		_finish()
		return
	var ht: MayoTutorial = host.tutorial()
	var gt: MayoTutorial = guest.tutorial()
	var guest_id: int = guest._net.local_id()
	await _until(func(): return ht.stage == MayoTutorial.Stage.GET_SAUCE)
	_check(host.enemy_count() == 0 and guest.enemy_count() == 0, "premature toast roster")
	_check(not gt.has_bottle(guest_id), "guest started with bottle")
	# Both need their own bottle. The guest uses the number-key selection RPC.
	_place_at_station(host, 1, ht.station_index())
	_check(host.refill_for(1, 0), "host initial pickup failed")
	await _wait(60)
	_check(ht.stage == MayoTutorial.Stage.GET_SAUCE, "host pickup skipped guest")
	_check("동료" in ht.objective_text(), "supplied host still gets pickup instruction")
	_check(ht.marker_position() == Vector3.INF, "host's completed pickup marker remains")
	_check("1 마요네즈" in gt.objective_text(), "guest's unfinished pickup was hidden")
	host.shooter_for(1).player.position = Vector3(-3, 1.28, -4)
	await _wait(3)
	_place_at_station(host, guest_id, gt.station_index())
	await _wait(10)
	guest._request_refill(1)
	_check(await _until(func(): return ht.stage == MayoTutorial.Stage.FIRST_FIGHT), "guest bottle selection did not start fight")
	_check(await _until(func(): return gt.has_bottle(guest_id)), "guest bottle was not replicated")
	_check(await _until(func(): return guest.local_sauce_kind() == 1 \
		and host.shooter_for(guest_id).sauce_kind == ContaminationGrid.KIND_MUSTARD),
		"guest's mustard bottle choice was not replicated")
	host.shooter_for(guest_id).player.position = Vector3(4, 1.28, -8)
	host.shooter_for(1).player.position = Vector3(0, 1.28, -4)
	host.debug_aim_at(Vector3(0, 1.28, -50))
	await _wait(30)
	_check(host.enemy_count() == 3 and guest.enemy_count() == 3, "wrong two-player roster")
	for index in ht.fight_enemies:
		_hose_to_death(host.enemy_at(index))
	_check(await _until(func(): return ht.stage == MayoTutorial.Stage.MONSTER_ARRIVES), "host never warned about monster")
	host.debug_aim_at(host.enemy_at(ht.monster_index).global_position)
	_check(await _until(func(): return ht.stage == MayoTutorial.Stage.RUN), "host never reached escape")
	await _wait(30)
	_check(gt.stomps_heard == 2, "guest did not hear both footsteps")
	_check(_roster_signature(host) == _roster_signature(guest), "enemy indices differ")
	for frame in 2000:
		if host._player.position.z < TutorialCourse.SPILL_BACK - 2:
			break
		host.debug_aim_at(Vector3(0, host._player.position.y, TutorialCourse.EXIT.z))
		host.debug_set_input(Vector2(0, -1), ht.slipped.is_empty(), false)
		await _wait(1)
	host.debug_set_input(Vector2.ZERO, false, false)
	if not await _until(func(): return ht.monster_trapped):
		_check(false, "network heavy never trapped")
		_finish()
		return
	_check(await _until(func(): return gt.monster_trapped), "guest never saw trap")
	_check(guest.enemy_at(gt.monster_index).tutorial_trapped, "guest heavy has no pinned state")
	_check(gt.impacts_heard == 1, "guest missed collision cue")
	_check(await _until(func(): return ht.stage == MayoTutorial.Stage.REFILL), "refill did not begin")
	_check(await _until(func(): return gt.station_index() == ht.station_index()), "refill markers differ")
	# A late joiner has already played offline: those bodies and lines must
	# disappear before the host's ordered roster arrives.
	var late = _make_world(2)
	await _wait(2)
	set_multiplayer(SceneMultiplayer.new(), late.get_path())
	late.tutorial_spawn_enemy(MayoTutorial.KIND_RUSHER, Vector3(0, 0, -12))
	late.tutorial().show_line(MayoTutorial.SAY_TOAST)
	late._net.join("127.0.0.1", PORT)
	_check(await _until(func(): return host.party_size() == 3 and late.party_size() == 3 \
		and late.tutorial().monster_trapped), "late join never received trapped state")
	await _wait(30)
	var lt: MayoTutorial = late.tutorial()
	_check(_roster_signature(host) == _roster_signature(late), "late join duplicated offline enemies")
	_check(late.enemy_at(lt.monster_index).tutorial_trapped, "late join heavy is free")
	_check(late._floor.cells_md5() == host._floor.cells_md5(), "late join spill differs")
	_check(lt.current_line_id() == -1, "offline dialogue survived joining")
	var said := gt.lines_shown
	await _wait(180)
	_check(gt.lines_shown == said, "state packet replayed a caption")
	_place_at_station(host, 1, ht.station_index())
	_check(host.refill_for(1, 0), "host top-up failed")
	await _wait(2)
	_check("교체 완료" in ht.objective_text(), "host's completed bottle selection still asks for another")
	_check(ht.current_line_id() != MayoTutorial.SAY_GO_REFILL, "host still hears completed refill instruction")
	_check("새 소스통 선택" in gt.objective_text(), "guest's unfinished refill was hidden")
	host.shooter_for(1).player.position = Vector3(0, 1.28, -50)
	await _wait(3)
	_place_at_station(host, guest_id, gt.station_index())
	await _wait(10)
	guest._request_refill(2)
	_check(await _until(func(): return ht.supplied.has(guest_id)), "guest bottle selection lost")
	_check(await _until(func(): return guest.local_sauce_kind() == 2 \
		and host.shooter_for(guest_id).sauce_kind == ContaminationGrid.KIND_KETCHUP),
		"guest's ketchup bottle choice was not replicated")
	await _wait(60)
	_check(ht.stage == MayoTutorial.Stage.REFILL, "late joiner not waited for")
	late._net.leave()
	_check(await _until(func(): return ht.stage == MayoTutorial.Stage.COOP_FIGHT), "departed peer stalls progress")
	_hose_to_death(host.enemy_at(ht.monster_index))
	_check(await _until(func(): return ht.is_complete() and gt.is_complete(), 3600), "ending not replicated")
	_finish()

func _place_at_station(world, peer_id: int, index: int) -> void:
	var station: Dictionary = world.refill_stations()[index]
	var player: MayoPlayer = world.shooter_for(peer_id).player
	player.global_position = station.position + station.facing * 1.5
	player.global_position.y = 1.28
	player.velocity = Vector3.ZERO


func _finish() -> void:
	for world in _worlds:
		world._net.leave()
	if failures.is_empty():
		print("MAYO_TUTORIAL_NET_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
