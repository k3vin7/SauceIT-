extends SceneTree

# The two-player harness, checked from the outside: the swap keys do swap, and
# only the side being driven moves. Input routing is the part of it that is
# easy to get wrong -- Input is global, so without the hold on the idle side
# every key would drive both players at once.

var failures: Array[String] = []


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.push_back(message)


func _initialize() -> void:
	call_deferred("_run")

func _press(keycode: Key) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = keycode
	down.keycode = keycode
	down.pressed = true
	Input.parse_input_event(down)
	await process_frame
	await process_frame
	var up := InputEventKey.new()
	up.physical_keycode = keycode
	up.keycode = keycode
	up.pressed = false
	Input.parse_input_event(up)
	await process_frame

func _run() -> void:
	var harness = load("res://dev_two_player.tscn").instantiate()
	root.add_child(harness)
	for _f in 60:
		await physics_frame
	_check(harness._active == 0, "the harness did not start on the host")
	await _press(KEY_TAB)
	_check(harness._active == 1, "Tab did not move to the client")
	await _press(KEY_TAB)
	_check(harness._active == 0, "Tab did not move back to the host")
	await _press(KEY_2)
	_check(harness._active == 1, "2 did not pick the client")
	await _press(KEY_1)
	_check(harness._active == 0, "1 did not pick the host")
	print("swap keys: Tab, 1 and 2 all move the controls")
	# And does driving actually move only the active player?
	harness._set_active(1)
	var client = harness._worlds[1]
	var host = harness._worlds[0]
	var client_id: int = client._net.local_id()
	var before_b: Vector3 = host.shooter_for(client_id).player.global_position
	var before_a: Vector3 = host.shooter_for(1).player.global_position
	Input.action_press("move_forward")
	for _f in 60:
		await physics_frame
	Input.action_release("move_forward")
	await physics_frame
	var moved_b: float = before_b.distance_to(host.shooter_for(client_id).player.global_position)
	var moved_a: float = before_a.distance_to(host.shooter_for(1).player.global_position)
	print("driving B: B moved %.2f m, A moved %.2f m" % [moved_b, moved_a])
	_check(moved_b > 0.5, "the side being driven only moved %.2f m" % moved_b)
	_check(moved_a < 0.01,
		"the side that is not being driven moved %.2f m as well" % moved_a)

	if failures.is_empty():
		print("MAYO_HARNESS_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
