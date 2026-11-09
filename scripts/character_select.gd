extends CanvasLayer

## The door of the truck: four characters, pick one.
##
## Shown once per session, between being let into a room and the truck itself,
## for the host and for every guest. What is picked here goes to the session
## (`MayoNet.choose_character`), which is what the truck and the stage both ask
## when they dress a body -- so this screen is the only place the choice is
## made, and it holds from the truck through every stage after it.
##
## Two players may pick the same character. The cards say who has already taken
## what, so a party that wants four different ones can see how to get there, but
## nothing is locked: a lock would need a rule for two picks arriving at once,
## and "you both get it" is a better answer than any tiebreak.

signal character_chosen(index: int)
signal leave_requested

const NAMES := ["캐릭터 1", "캐릭터 2", "캐릭터 3", "캐릭터 4"]
## Every model is stood at the stage's 2.56 m and then given the stage's own
## size multiplier for that character (`PLAYER_CHARACTER_SIZE_MULTIPLIERS`), so
## the line-up here is the line-up in the street: the fourth is wide for its
## height and is played smaller.
const PREVIEW_HEIGHT := 2.56
const PREVIEW_SCALE := [1.0, 1.0, 1.0, 0.72]
const CARD_SIZE := Vector2(214.0, 372.0)
const TURN_SPEED := 0.9

var session: MayoNet
var selected := 0

var _cards: Array[Button] = []
var _models: Array[Node3D] = []
var _walks: Array = []
var _taken: Array[Label] = []
var _confirm: Button


func _ready() -> void:
	name = "CharacterSelectUI"
	layer = 5
	if session != null:
		# Opens on the character the seat would have given, so a player who just
		# presses the button gets what they would have got before this screen.
		selected = session.character_of(session.local_id())
		if not session.roster_changed.is_connected(_refresh_taken):
			session.roster_changed.connect(_refresh_taken)
	_build()
	_select(selected)
	_refresh_taken()


func _exit_tree() -> void:
	if session != null and session.roster_changed.is_connected(_refresh_taken):
		session.roster_changed.disconnect(_refresh_taken)


func _process(delta: float) -> void:
	# The picked one turns on the spot; the others stand facing out.
	for index in _models.size():
		var model := _models[index]
		if not is_instance_valid(model):
			continue
		if index == selected:
			model.rotation.y = wrapf(model.rotation.y + TURN_SPEED * delta, -PI, PI)
		else:
			model.rotation.y = lerp_angle(model.rotation.y, 0.0, minf(delta * 6.0, 1.0))


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	var code: int = key.physical_keycode if key.physical_keycode != 0 else key.keycode
	if code >= KEY_1 and code < KEY_1 + NAMES.size():
		_select(code - KEY_1)
		get_viewport().set_input_as_handled()
	elif code == KEY_LEFT or code == KEY_A:
		_select(posmod(selected - 1, NAMES.size()))
		get_viewport().set_input_as_handled()
	elif code == KEY_RIGHT or code == KEY_D:
		_select(posmod(selected + 1, NAMES.size()))
		get_viewport().set_input_as_handled()
	elif code == KEY_ENTER or code == KEY_KP_ENTER:
		_confirm_pick()
		get_viewport().set_input_as_handled()


func _build() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.04, 0.94)
	add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	centre.add_child(column)
	var title := Label.new()
	title.text = "캐릭터 선택"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color("fff0a8"))
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "트럭에 타기 전에 함께할 캐릭터를 고르세요.  (1~4 · ←/→ 선택, Enter 탑승)"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(0.72, 0.8, 0.84)
	column.add_child(subtitle)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	column.add_child(row)
	var group := ButtonGroup.new()
	for index in NAMES.size():
		row.add_child(_build_card(index, group))
	_confirm = Button.new()
	_confirm.custom_minimum_size = Vector2(0.0, 48.0)
	_confirm.add_theme_font_size_override("font_size", 20)
	_confirm.pressed.connect(_confirm_pick)
	column.add_child(_confirm)
	var leave := Button.new()
	leave.text = "세션 나가기"
	leave.custom_minimum_size = Vector2(0.0, 38.0)
	leave.pressed.connect(func(): leave_requested.emit())
	column.add_child(leave)


## One card: a button the size of the card, with the character standing in its
## own little world inside it. Everything on top of the button ignores the
## mouse, so the whole card is the click target.
func _build_card(index: int, group: ButtonGroup) -> Button:
	var card := Button.new()
	card.custom_minimum_size = CARD_SIZE
	card.toggle_mode = true
	card.button_group = group
	card.focus_mode = Control.FOCUS_NONE
	card.add_theme_stylebox_override("normal", _card_style(Color("1b2226"), Color("3a464c"), 2))
	card.add_theme_stylebox_override("hover", _card_style(Color("232c31"), Color("8b9aa1"), 2))
	card.add_theme_stylebox_override("pressed", _card_style(Color("2c2a1a"), Color("ffd84a"), 4))
	card.add_theme_stylebox_override("hover_pressed", _card_style(Color("2c2a1a"), Color("ffd84a"), 4))
	card.pressed.connect(_select.bind(index))
	_cards.push_back(card)

	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.offset_left = 8.0
	holder.offset_top = 8.0
	holder.offset_right = -8.0
	holder.offset_bottom = -70.0
	card.add_child(holder)
	var view := SubViewport.new()
	view.own_world_3d = true
	view.transparent_bg = true
	view.msaa_3d = Viewport.MSAA_4X
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	holder.add_child(view)
	_build_stage(view, index)

	var label := Label.new()
	label.text = NAMES[index]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 22)
	label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	label.offset_top = -66.0
	label.offset_bottom = -36.0
	card.add_child(label)
	var taken := Label.new()
	taken.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	taken.mouse_filter = Control.MOUSE_FILTER_IGNORE
	taken.add_theme_font_size_override("font_size", 14)
	taken.modulate = Color(0.95, 0.72, 0.42)
	taken.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	taken.offset_top = -34.0
	taken.offset_bottom = -10.0
	card.add_child(taken)
	_taken.push_back(taken)
	return card


func _card_style(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(10)
	return style


## The little world a card looks into: the character on a turntable, a key
## light, a fill, and a camera far enough back to hold the tallest of them.
func _build_stage(view: SubViewport, index: int) -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.0, 0.0, 0.0, 0.0)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("d8dccb")
	settings.ambient_light_energy = 0.75
	environment.environment = settings
	view.add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38.0, 28.0, 0.0)
	key.light_energy = 1.25
	view.add_child(key)
	var camera := Camera3D.new()
	camera.fov = 34.0
	camera.near = 0.05
	camera.position = Vector3(0.0, 1.45, 5.3)
	view.add_child(camera)
	camera.look_at_from_position(camera.position, Vector3(0.0, 1.22, 0.0), Vector3.UP)
	camera.current = true

	var turntable := Node3D.new()
	turntable.name = "Turntable"
	view.add_child(turntable)
	var model := TruckLobby.CHARACTER_SCENES[index].instantiate() as Node3D
	var walk := StringName()
	var animator: AnimationPlayer
	if model != null:
		model.scale = Vector3.ONE * (PREVIEW_HEIGHT / float(TruckLobby.CHARACTER_HEIGHTS[index])
			* float(PREVIEW_SCALE[index]))
		turntable.add_child(model)
		# Out of the bind pose and into the first frame of its walk, which is
		# what the truck stands an idle occupant in as well: the files carry no
		# idle clip, and a row of four T-poses is not a line-up.
		var players := model.find_children("*", "AnimationPlayer", true, false)
		if not players.is_empty():
			animator = players[0] as AnimationPlayer
			var suffix: String = TruckLobby.CHARACTER_WALKS[index]
			for candidate in animator.get_animation_list():
				# By suffix, as the stage finds them: two of the files prefix their
				# clips with the character's name (`Character_2_Walk_WeaponHold`).
				if String(candidate).ends_with(suffix):
					walk = StringName(candidate)
					break
			if not walk.is_empty():
				animator.get_animation(walk).loop_mode = Animation.LOOP_LINEAR
				animator.play(walk)
				animator.seek(0.0, true)
				animator.pause()
	_models.push_back(turntable)
	_walks.push_back([animator, walk])


func _select(index: int) -> void:
	selected = clampi(index, 0, NAMES.size() - 1)
	for card_index in _cards.size():
		_cards[card_index].set_pressed_no_signal(card_index == selected)
	# The picked one walks on the spot as it turns; the rest hold still.
	for walk_index in _walks.size():
		var animator: AnimationPlayer = _walks[walk_index][0]
		var clip: StringName = _walks[walk_index][1]
		if not is_instance_valid(animator) or clip.is_empty():
			continue
		animator.play(clip)
		if walk_index != selected:
			animator.seek(0.0, true)
			animator.pause()
	if _confirm != null:
		_confirm.text = "%s 선택하고 탑승" % NAMES[selected]


func _confirm_pick() -> void:
	character_chosen.emit(selected)


## Who else is already wearing each one. This peer's own entry is left out: the
## highlighted card says that already.
func _refresh_taken() -> void:
	if _taken.is_empty():
		return
	var holders := []
	for _index in NAMES.size():
		holders.push_back(PackedStringArray())
	if session != null:
		var mine := session.local_id()
		var picks := session.character_assignments()
		var ids: Array = picks.keys()
		ids.sort()
		for id in ids:
			if int(id) == mine:
				continue
			var pick := int(picks[id])
			if pick >= 0 and pick < holders.size():
				holders[pick].push_back("P%d" % int(id))
	for index in _taken.size():
		var names: PackedStringArray = holders[index]
		_taken[index].text = "" if names.is_empty() else "%s 선택함" % ", ".join(names)
