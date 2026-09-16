extends Control

## The whole of the connection UI: host, or type an address and join. No lobby,
## no player list, no matchmaking. Opened and closed with F2; hidden at startup,
## so a player who never presses it is in the same single-player game as before.

const PORT_HINT := "24565"

var _net: MayoNet
var _address_field: LineEdit
var _code_field: LineEdit
var _open_box: CheckBox
var _port_field: LineEdit
var _status_label: Label
var _host_button: Button
var _join_button: Button
var _leave_button: Button


func bind(net: MayoNet) -> void:
	_net = net
	if not _net.status_changed.is_connected(_on_status_changed):
		_net.status_changed.connect(_on_status_changed)


func _ready() -> void:
	# The offsets have to be zeroed along with the anchors: a Control built in
	# code has no rect yet, and a preset that only moves the anchors leaves the
	# node its old zero size. This one covers the screen, so the dim behind the
	# panel covers it too and clicks cannot fall through to the game.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.04, 0.72)
	add_child(dim)

	# Centred by a container rather than by anchors, so the panel is placed
	# after its contents have decided how big it is.
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380.0, 0.0)
	centre.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 18)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var title := Label.new()
	title.text = "LAN 플레이 (최대 4인)"
	column.add_child(title)

	# The same code on both ends. It is checked during the handshake, so a guest
	# that types it wrong is dropped before it is a player at all. Left empty on
	# the host, the session is open to anyone who can reach the port.
	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 8)
	column.add_child(code_row)

	var code_label := Label.new()
	code_label.text = "로비 코드"
	code_row.add_child(code_label)

	_code_field = LineEdit.new()
	_code_field.placeholder_text = "비우면 자동 생성"
	_code_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_row.add_child(_code_field)

	# Opening without a code is a choice, not what happens when the field is
	# left alone: the port is reachable by anything that can find it.
	_open_box = CheckBox.new()
	_open_box.text = "코드 없이 열기"
	column.add_child(_open_box)

	_host_button = Button.new()
	_host_button.text = "호스트 시작"
	_host_button.pressed.connect(_on_host_pressed)
	column.add_child(_host_button)

	var separator := HSeparator.new()
	column.add_child(separator)

	var address_row := HBoxContainer.new()
	address_row.add_theme_constant_override("separation", 8)
	column.add_child(address_row)

	var address_label := Label.new()
	address_label.text = "호스트 IP"
	address_row.add_child(address_label)

	_address_field = LineEdit.new()
	_address_field.text = "127.0.0.1"
	_address_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	address_row.add_child(_address_field)

	_port_field = LineEdit.new()
	_port_field.text = PORT_HINT
	_port_field.custom_minimum_size = Vector2(70.0, 0.0)
	address_row.add_child(_port_field)

	_join_button = Button.new()
	_join_button.text = "접속"
	_join_button.pressed.connect(_on_join_pressed)
	column.add_child(_join_button)

	_leave_button = Button.new()
	_leave_button.text = "세션 종료"
	_leave_button.pressed.connect(_on_leave_pressed)
	column.add_child(_leave_button)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(340.0, 0.0)
	column.add_child(_status_label)

	var hint := Label.new()
	hint.text = "F2로 이 창을 열고 닫습니다."
	column.add_child(hint)

	_refresh()
	# The wait counts down in front of the player rather than sitting at the
	# number it was when they were turned away.
	set_process(true)


func _process(_delta: float) -> void:
	if _net != null and _net.blocked_seconds() > 0:
		_refresh()


func _on_host_pressed() -> void:
	_net.lobby_code = _code_field.text.strip_edges()
	if _net.host(_port(), _open_box.button_pressed):
		# A generated code has to be readable back off the panel, so it is put in
		# the field rather than only in the status line.
		_code_field.text = _net.lobby_code
		_close_on_success()
	_refresh()


func _on_join_pressed() -> void:
	_net.lobby_code = _code_field.text.strip_edges()
	if _net.join(_address_field.text.strip_edges(), _port()):
		_close_on_success()
	_refresh()


func _on_leave_pressed() -> void:
	_net.leave()
	_net.world.reset_to_offline()
	_refresh()


## Hosting and joining both drop straight back into the game; the status shows
## up again next time the panel is opened.
func _close_on_success() -> void:
	_net.world.set_network_panel_open(false)


func _port() -> int:
	var value := _port_field.text.strip_edges().to_int()
	return value if value > 0 else MayoNet.DEFAULT_PORT


func _on_status_changed(_message: String) -> void:
	_refresh()


func _refresh() -> void:
	if _status_label == null:
		return
	_status_label.text = _net.status() if _net != null else "offline"
	# Being made to wait is the one thing the panel says in its own words: it is
	# an instruction to the player, not a report of what the session is doing.
	var waiting: int = 0 if _net == null else _net.blocked_seconds()
	if waiting > 0:
		_status_label.text = "잠시 후 다시 시도하세요 (%d초)" % waiting
	var online: bool = _net != null and _net.is_online()
	_host_button.disabled = online
	_join_button.disabled = online
	_address_field.editable = not online
	_code_field.editable = not online
	_open_box.disabled = online
	_port_field.editable = not online
	_leave_button.disabled = not online
