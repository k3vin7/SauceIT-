extends RefCounted
const DEFAULTS := {"window_mode": 2, "resolution": 0, "quality": 1,
	"fov": 74.0, "motion": 1.0, "ui_scale": 1.0, "viewmodel": 0.88}
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const ACTIONS := {"move_forward": "앞으로", "move_backward": "뒤로", "move_left": "왼쪽",
	"move_right": "오른쪽", "run": "달리기", "jump": "점프", "wipe_screen": "고글 닦기",
	"interact": "상호작용", "shove": "밀치기"}
const KEYS := {"move_forward": KEY_W, "move_backward": KEY_S, "move_left": KEY_A,
	"move_right": KEY_D, "run": KEY_SHIFT, "jump": KEY_SPACE, "wipe_screen": KEY_R,
	"interact": KEY_E, "shove": KEY_V}
var settings := DEFAULTS.duplicate()
var bindings := {}
var _pending := ""
var _button: Button
var _controls := {}
var _binding_draft := {}

static func key_label(action: String, fallback := "E") -> String:
	if not InputMap.has_action(action):
		return fallback
	var events := InputMap.action_get_events(action)
	if events.is_empty() or events[0] is not InputEventKey:
		return fallback
	return OS.get_keycode_string(events[0].physical_keycode)

func load_config(config: ConfigFile) -> void:
	for key in DEFAULTS:
		settings[key] = config.get_value("display", key, DEFAULTS[key])
	for action in ACTIONS:
		bindings[action] = int(config.get_value("keys", action, KEYS[action]))
	settings.fov = clampf(float(settings.fov), 60.0, 90.0)
	settings.motion = clampf(float(settings.motion), 0.0, 1.0)
	settings.ui_scale = clampf(float(settings.ui_scale), 0.85, 1.25)
	settings.viewmodel = clampf(float(settings.viewmodel), 0.75, 1.0)
	settings.quality = clampi(int(settings.quality), 0, 2)
	settings.resolution = clampi(int(settings.resolution), 0, RESOLUTIONS.size() - 1)
	settings.window_mode = clampi(int(settings.window_mode), 0, 2)

func write_config(config: ConfigFile) -> void:
	for key in settings:
		config.set_value("display", key, settings[key])
	for key in bindings:
		config.set_value("keys", key, bindings[key])

func apply_window(window: Window) -> void:
	window.mode = [Window.MODE_WINDOWED, Window.MODE_EXCLUSIVE_FULLSCREEN, Window.MODE_MAXIMIZED][int(settings.window_mode)]
	if int(settings.window_mode) == 0:
		window.size = RESOLUTIONS[int(settings.resolution)]
	window.content_scale_factor = float(settings.ui_scale)
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var event := InputEventKey.new()
		event.physical_keycode = int(bindings.get(action, KEYS[action]))
		InputMap.action_add_event(action, event)

func apply_world(world: Node) -> void:
	if world == null or not world.has_method("apply_view"):
		return
	var size: Vector2 = world.get_viewport().get_visible_rect().size
	world.apply_view(float(settings.fov), size.x / maxf(size.y, 1.0))
	world.set("camera_motion_scale", float(settings.motion))
	world.set("viewmodel_scale", float(settings.viewmodel))
	var light := world.get_node_or_null("KeyLight") as DirectionalLight3D
	if light != null:
		light.shadow_enabled = int(settings.quality) > 0
		light.directional_shadow_max_distance = 65.0 if int(settings.quality) == 1 else 95.0
	world.get_viewport().scaling_3d_scale = [0.7, 0.85, 1.0][int(settings.quality)]

func build(column: VBoxContainer) -> void:
	_pending = ""
	_controls.clear()
	_binding_draft = bindings.duplicate()
	_choice(column, "화면 모드", "window_mode", ["창", "전체 화면", "최대화"])
	_choice(column, "해상도 (창 모드)", "resolution", ["1280 × 720", "1600 × 900", "1920 × 1080"])
	_choice(column, "그래픽 품질", "quality", ["낮음", "중간", "높음"])
	_slider(column, "시야각", "fov", 60.0, 90.0, 1.0)
	_slider(column, "화면 흔들림", "motion", 0.0, 1.0, 0.05)
	_slider(column, "UI 크기", "ui_scale", 0.85, 1.25, 0.05)
	_slider(column, "1인칭 소스통 크기", "viewmodel", 0.75, 1.0, 0.05)
	for action in ACTIONS:
		var button := Button.new()
		button.text = "%s · %s" % [ACTIONS[action], OS.get_keycode_string(int(_binding_draft.get(action, KEYS[action])))]
		button.pressed.connect(func():
			_pending = action
			_button = button
			button.text = "키를 누르세요 · Esc 취소")
		column.add_child(button)

func capture_key(event: InputEvent) -> bool:
	if _pending.is_empty() or event is not InputEventKey or not event.pressed or event.echo:
		return false
	var key: int = event.physical_keycode
	if key != KEY_ESCAPE:
		if key in [KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F6, KEY_C, KEY_M] or (key >= KEY_1 and key <= KEY_5):
			_button.text = "예약된 키입니다 · 다른 키를 누르세요"
			return true
		for action in ACTIONS:
			if action != _pending and int(_binding_draft.get(action, KEYS[action])) == key:
				_button.text = "이미 사용 중인 키입니다 · 다른 키를 누르세요"
				return true
		_binding_draft[_pending] = key
	_button.text = "%s · %s" % [ACTIONS[_pending], OS.get_keycode_string(int(_binding_draft.get(_pending, KEYS[_pending])))]
	_pending = ""
	return true

func commit() -> void:
	for key in _controls:
		var control: Control = _controls[key]
		settings[key] = control.selected if control is OptionButton else control.value
	bindings = _binding_draft.duplicate()

func _choice(parent: VBoxContainer, title: String, key: String, choices: Array) -> void:
	var label := Label.new()
	label.text = title
	parent.add_child(label)
	var field := OptionButton.new()
	for choice in choices:
		field.add_item(choice)
	field.select(int(settings[key]))
	parent.add_child(field)
	_controls[key] = field

func _slider(parent: VBoxContainer, title: String, key: String, low: float, high: float, step: float) -> void:
	var label := Label.new()
	label.text = "%s · %.2f" % [title, float(settings[key])]
	parent.add_child(label)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = settings[key]
	slider.value_changed.connect(func(value): label.text = "%s · %.2f" % [title, value])
	parent.add_child(slider)
	_controls[key] = slider
