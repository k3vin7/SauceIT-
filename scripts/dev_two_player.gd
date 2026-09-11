extends Node

## Both ends of a LAN session, side by side, driven by one person.
##
## A real session needs two machines, which makes the things that actually go
## wrong -- a player's aim looking right on their own screen and wrong on the
## other -- awkward to see and awkward to reproduce. This runs the host and the
## client in one process, each in its own SubViewport so they get separate 3D
## worlds, talking to each other over the loopback exactly as two machines
## would. Both screens are on screen at once; `Tab` moves the keyboard and mouse
## between them.
##
## It is a development harness, not a game mode: it runs from its own scene and
## the shipped one is untouched.

const WorldScene := preload("res://main.tscn")
const PORT := 24700
## Which side is being driven is shown on the label and nowhere else. Dimming
## the idle view would be clearer at a glance and useless in practice: the
## reason for having both on screen is to compare what they are drawing.
const ACTIVE_LABEL := Color("fff0a8")
const IDLE_LABEL := Color(0.62, 0.66, 0.70, 1.0)

var _worlds: Array = []
var _containers: Array[SubViewportContainer] = []
var _labels: Array[Label] = []
var _active := 0
var _status: Label


func _ready() -> void:
	_ensure_actions()
	_build_ui()
	# The host opens first; the client is given a moment so its connection
	# attempt does not race the socket being bound.
	_worlds[0]._net.host(PORT)
	await get_tree().process_frame
	_worlds[1]._net.join("127.0.0.1", PORT)
	_set_active(0)


func _process(_delta: float) -> void:
	if _status == null:
		return
	_status.text = "Tab / 1 / 2: 조종 전환   |   호스트: %s   |   손님: %s" % [
		_worlds[0]._net.status(), _worlds[1]._net.status()]


## Only the side being driven hears anything. The other has its keys held at
## zero rather than being left to read the same keyboard, which both worlds can
## see -- Input is global, and without this every key would move both players.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("dev_swap_player"):
		_set_active(1 - _active)
		get_viewport().set_input_as_handled()
		return
	# 1 and 2 pick a side outright. Tab is the handy key but it is also the
	# engine's focus key, so there is a way through that nothing else wants.
	if event.is_action_pressed("dev_pick_host"):
		_set_active(0)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("dev_pick_client"):
		_set_active(1)
		get_viewport().set_input_as_handled()
		return
	# Forwarded by hand rather than left to the viewport tree: whether a
	# SubViewport sees an event depends on container settings that are easy to
	# get subtly wrong, and this is unambiguous.
	_worlds[_active]._unhandled_input(event)


func _set_active(index: int) -> void:
	_active = index
	for i in _worlds.size():
		var world = _worlds[i]
		if i == index:
			world.debug_clear_input_override()
		else:
			world.debug_set_input(Vector2.ZERO, false, false)
		_labels[i].add_theme_color_override("font_color",
			ACTIVE_LABEL if i == index else IDLE_LABEL)
		_labels[i].text = "%s%s" % [
			"호스트 (A)" if i == 0 else "손님 (B)",
			"  ◀ 조종 중" if i == index else ""]


func _ensure_actions() -> void:
	_bind("dev_swap_player", KEY_TAB)
	_bind("dev_pick_host", KEY_1)
	_bind("dev_pick_client", KEY_2)


func _bind(action: String, keycode: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var key := InputEventKey.new()
	key.physical_keycode = keycode
	InputMap.action_add_event(action, key)


func _build_ui() -> void:
	var root_box := VBoxContainer.new()
	root_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root_box)

	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 4)
	root_box.add_child(row)

	for i in 2:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(column)

		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(label)
		_labels.push_back(label)

		var container := SubViewportContainer.new()
		container.stretch = true
		container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		column.add_child(container)
		_containers.push_back(container)

		var viewport := SubViewport.new()
		# Its own 3D world: sharing one would put both floors, both sets of
		# walls and all four capsules in the same physics space.
		viewport.own_world_3d = true
		# The harness routes input itself; letting the viewport pick events up
		# as well would drive both players at once.
		viewport.gui_disable_input = true
		viewport.handle_input_locally = false
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		container.add_child(viewport)

		var world = WorldScene.instantiate()
		world.name = "World"
		# Events reach it through _unhandled_input above, for the active side
		# only.
		world.set_process_unhandled_input(false)
		viewport.add_child(world)
		_worlds.push_back(world)

		# One MultiplayerAPI per side, rooted at the world, so RPC paths resolve
		# against it: "Net" means "Net" on both, as it would across machines.
		get_tree().set_multiplayer(SceneMultiplayer.new(), world.get_path())

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_box.add_child(_status)
