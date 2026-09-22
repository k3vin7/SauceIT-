class_name ScaleTestBase
extends Node3D

const PLAYER_HEIGHT_M := 2.56
const KARJA_LENGTH_1X_M := 164.67033188026195
const KARJA_NARROW_STATION_1X_M := 30.0
const KARJA_NARROW_WIDTH_1X_M := 11.84980790875818
const KARJA_NARROW_POINT_1X := Vector2(-4.963386662605342, -28.95932728106288)
const KARJA_NARROW_NORMAL := Vector2(0.9869162129028283, 0.16123395644075472)
const ROOTSITURG_ENTRY_1X := Vector2(27.95902511838358, -159.30707296729088)
const SPAWN_POSITION := Vector3(0.0, 1.30, 1.55)
const DUMMY_OFFSETS_M := [-3.75, -1.25, 1.25, 3.75]

enum StopwatchState { WAITING, RUNNING, FINISHED }

var map_scale := 1.0
var game: Node
var player: MayoPlayer
var stopwatch_state := StopwatchState.WAITING
var stopwatch_seconds := 0.0
var rootsiturg_entry_world := Vector3.ZERO
var _initialized := false


func initialize_scale(scale_factor: float) -> void:
	map_scale = scale_factor
	$ScaledMap.scale = Vector3.ONE * map_scale
	game = $Game
	player = _find_local_player(game)
	if player == null:
		push_error("The main.tscn instance did not create its offline MayoPlayer")
		return
	_prepare_main_instance()
	rootsiturg_entry_world = Vector3(
		ROOTSITURG_ENTRY_1X.x * map_scale, 0.0,
		ROOTSITURG_ENTRY_1X.y * map_scale)
	_update_info_labels()
	await get_tree().physics_frame
	_build_enemy_dummies()
	reset_to_spawn()
	_initialized = true
	_capture_if_requested()


func _find_local_player(root: Node) -> MayoPlayer:
	for child in root.get_children():
		if child is MayoPlayer:
			return child as MayoPlayer
		var nested := _find_local_player(child)
		if nested != null:
			return nested
	return null


func _prepare_main_instance() -> void:
	# main.tscn owns the real input, player construction and camera.  Its street,
	# enemies and HUD remain part of the untouched instance but are hidden and
	# collision-disabled so only the corridor graybox participates in this test.
	for node in _descendants(game):
		if node is MayoEnemy:
			(node as MayoEnemy).authority = false
		if node is CollisionObject3D and node != player \
				and not player.is_ancestor_of(node):
			var collision_object := node as CollisionObject3D
			collision_object.collision_layer = 0
			collision_object.collision_mask = 0

	for child in game.get_children():
		if child == player or child is Camera3D:
			continue
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false
		elif child is WorldEnvironment:
			(child as WorldEnvironment).environment = null
		elif child is Light3D:
			(child as Light3D).visible = false
		elif child is Node3D:
			(child as Node3D).visible = false

	# These belong to the hidden prototype street.  Clearing them only on this
	# instance keeps its chase/contact loop out of the scale walk; the four
	# measurement dummies below are separate, inert bodies with collision only.
	game.debug_clear_enemies()
	game.debug_clear_input_override()
	game.set_first_person(true)


func _descendants(root: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in root.get_children():
		result.push_back(child)
		result.append_array(_descendants(child))
	return result


func _build_enemy_dummies() -> void:
	var centre := Vector3(
		KARJA_NARROW_POINT_1X.x * map_scale,
		0.0,
		KARJA_NARROW_POINT_1X.y * map_scale)
	var across := Vector3(KARJA_NARROW_NORMAL.x, 0.0, KARJA_NARROW_NORMAL.y)
	for index in DUMMY_OFFSETS_M.size():
		var enemy := MayoEnemy.new()
		enemy.name = "NarrowSectionDummy%02d" % index
		enemy.authority = false
		enemy.add_to_group("scale_test_dummy")
		$EnemyDummies.add_child(enemy)
		enemy.build(0.1, 0.2, Color("6957a5"))
		enemy.set_physics_process(false)
		var horizontal := centre + across * float(DUMMY_OFFSETS_M[index])
		var ground_y := _ground_height(horizontal)
		enemy.global_position = Vector3(horizontal.x,
			ground_y + enemy.stand_height(), horizontal.z)


func _ground_height(horizontal: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(horizontal.x, 100.0, horizontal.z),
		Vector3(horizontal.x, -100.0, horizontal.z))
	if player != null:
		query.exclude = [player.get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	var hit_position: Vector3 = hit.get("position", Vector3.ZERO)
	return hit_position.y


func _process(delta: float) -> void:
	if not _initialized or player == null:
		return
	var horizontal_from_spawn := Vector2(
		player.global_position.x - SPAWN_POSITION.x,
		player.global_position.z - SPAWN_POSITION.z).length()
	if stopwatch_state == StopwatchState.WAITING and horizontal_from_spawn > 0.45:
		stopwatch_state = StopwatchState.RUNNING
	if stopwatch_state == StopwatchState.RUNNING:
		stopwatch_seconds += delta
		var to_entry := Vector2(
			player.global_position.x - rootsiturg_entry_world.x,
			player.global_position.z - rootsiturg_entry_world.z).length()
		if to_entry <= 5.0 * map_scale:
			stopwatch_state = StopwatchState.FINISHED
	_update_stopwatch_label()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_R:
		reset_to_spawn()
		get_viewport().set_input_as_handled()


func reset_to_spawn() -> void:
	if player == null:
		return
	player.global_transform = Transform3D(Basis.IDENTITY, SPAWN_POSITION)
	player.velocity = Vector3.ZERO
	player.state = MayoPlayer.State.NORMAL
	player.fall_direction = 1.0
	player.heal_to_full()
	game.debug_clear_input_override()
	game.debug_set_aim(0.0, 0.0)
	stopwatch_state = StopwatchState.WAITING
	stopwatch_seconds = 0.0
	_update_stopwatch_label()


func _update_info_labels() -> void:
	var expected_walk := (KARJA_LENGTH_1X_M * map_scale + SPAWN_POSITION.z) \
		/ player.walk_speed
	$HUD/Info.text = "Map %.2fx | Actual MayoPlayer %.2f m | Walk %.1f m/s" % [
		map_scale, PLAYER_HEIGHT_M, player.walk_speed]
	$HUD/Help.text = "WASD move  |  Shift run  |  Space jump  |  Mouse look  |  F1 camera  |  R reset"
	$HUD/Target.text = "Rotary ETA %.1f s | Narrow section %.2f m at station %.0f m" % [
		expected_walk, KARJA_NARROW_WIDTH_1X_M * map_scale,
		KARJA_NARROW_STATION_1X_M * map_scale]


func _update_stopwatch_label() -> void:
	var status := "READY"
	if stopwatch_state == StopwatchState.RUNNING:
		status = "RUNNING"
	elif stopwatch_state == StopwatchState.FINISHED:
		status = "FINISHED"
	var minutes := floori(stopwatch_seconds / 60.0)
	var seconds := fmod(stopwatch_seconds, 60.0)
	$HUD/Stopwatch.text = "STOPWATCH  %02d:%06.3f  %s" % [minutes, seconds, status]


func _capture_if_requested() -> void:
	var requested_path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-scale-test="):
			requested_path = argument.trim_prefix("--capture-scale-test=")
	if requested_path.is_empty():
		return
	# The playable scenes start in the game's normal first-person mode.  Pull
	# back only for the requested report image so the real 2.56 m player body is
	# visible at the Kalda spawn.
	game.set_first_person(false)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var absolute_path := ProjectSettings.globalize_path(requested_path)
	var error := image.save_png(absolute_path)
	if error != OK:
		push_error("Could not save scale-test screenshot: %s" % absolute_path)
	else:
		print("SCALE_TEST_SCREENSHOT %s" % absolute_path)
	get_tree().quit(error)
