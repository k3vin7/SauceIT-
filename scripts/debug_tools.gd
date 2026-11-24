class_name SauceDebug
extends RefCounted

## 디버그 모드: 개발하면서 쓰는 지름길을 한곳에 모은 것. 옵션 창의 "디버그" 분류로 나온다.
##
##   * 개발용 실행에서만 보인다(`available`). 출시용으로 내보낸 빌드에는 분류 자체가 없다.
##   * 게임을 켤 때마다 꺼진 상태로 시작한다(저장하지 않는다).
##   * 같이하기에서는 방장이 켠 방에서만, 그 방의 전원이 쓸 수 있다.
##   * 팀 돈 +100: 사무실에서. 파츠 바꾸기: 스테이지에서(코인·피난처와 무관하게 바로 낀다).
##
## 나중에 통째로 걷어낼 때 지울 것:
##   1. 이 파일 `scripts/debug_tools.gd`
##   2. `scripts/app_root.gd`의 `_open_options`에서 "DEBUG" 표시가 붙은 블록
##   3. `scripts/net_game.gd`에서 "# -- DEBUG" 와 "# -- /DEBUG" 사이
##   4. `scripts/mayo_prototype.gd`의 `debug_equip_part`
##   5. `tests/probe_festival_rewards.gd`, `tests/probe_tomatina.gd`의 디버그 확인 부분
## 지운 뒤에는 `MayoNet.PROTOCOL_VERSION`을 올린다(통신 함수가 줄어든다).

const MONEY_STEP := 100
# 앱 본체(`SauceApp`)나 세션(`MayoNet`)을 이름으로 가리키지 않는다: 세션이 이 파일을 쓰고 앱이
# 스테이지를 미리 읽어 두기 때문에, 이름으로 가리키면 서로를 물고 도는 로딩이 된다.
const UI := preload("res://scripts/sauce_ui.gd")


## 이 실행에서 디버그 분류를 보여 줄 것인가.
static func available() -> bool:
	return OS.is_debug_build()


## 옵션 창의 "디버그" 쪽을 채운다.
static func build_page(page: VBoxContainer, app: Node) -> void:
	var session: Node = app.get("session")
	var note := Label.new()
	note.text = "개발용 지름길입니다. 출시 빌드에는 나오지 않고, 게임을 켤 때마다 꺼져 있습니다.\n같이하기에서는 방장이 켠 방에서만 모두 쓸 수 있습니다."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", UI.MUTED)
	page.add_child(note)
	var toggle := CheckButton.new()
	toggle.name = "DebugToggle"
	toggle.text = "디버그 모드"
	page.add_child(toggle)
	var status := Label.new()
	status.name = "DebugStatus"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_color_override("font_color", UI.GOLD)
	page.add_child(status)
	page.add_child(HSeparator.new())
	var money := Button.new()
	money.name = "DebugMoney"
	money.text = "팀 돈 +%d  (사무실에서)" % MONEY_STEP
	money.custom_minimum_size.y = 40.0
	page.add_child(money)
	page.add_child(UI.eyebrow("파츠 바로 끼기  (스테이지에서)"))
	var parts := GridContainer.new()
	parts.name = "DebugParts"
	parts.columns = 3
	parts.add_theme_constant_override("h_separation", 8)
	parts.add_theme_constant_override("v_separation", 8)
	page.add_child(parts)
	var catalog: Array = preload("res://scripts/tomatina_sauce_parts.gd").CATALOG
	var part_buttons: Array[Button] = []
	for part in catalog.size():
		var choice := Button.new()
		choice.text = str(catalog[part][0])
		choice.custom_minimum_size = Vector2(170.0, 40.0)
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		parts.add_child(choice)
		part_buttons.push_back(choice)

	var refresh := func() -> void:
		var guest: bool = session.is_online() and not session.is_server()
		var active: bool = session.debug_active()
		var space: Node = app.get("current_space")
		var in_office := space is OfficeLobby
		var in_stage: bool = is_instance_valid(space) and space.has_method("debug_equip_part")
		toggle.set_pressed_no_signal(active)
		toggle.disabled = guest
		money.disabled = not (active and in_office)
		for choice in part_buttons:
			choice.disabled = not (active and in_stage)
		if guest:
			status.text = "방장이 디버그 모드를 켰습니다." if active else "방장이 켜야 쓸 수 있습니다."
		elif not active:
			status.text = "꺼져 있습니다."
		elif in_office:
			status.text = "켜짐 · 팀 돈 %d" % session.team_money
		elif in_stage:
			status.text = "켜짐 · 스테이지"
		else:
			status.text = "켜짐 · 돈은 사무실에서, 파츠는 스테이지에서 쓸 수 있습니다."
	toggle.toggled.connect(func(on: bool) -> void:
		session.set_debug_mode(on)
		refresh.call())
	money.pressed.connect(func() -> void:
		session.request_debug_money(MONEY_STEP)
		refresh.call())
	for part in part_buttons.size():
		part_buttons[part].pressed.connect(func() -> void:
			session.request_debug_part(part)
			refresh.call())
	# 방장이 켜고 끄는 것, 돈이 바뀌는 것을 따라간다. 창이 닫히면 끊는다.
	session.debug_mode_changed.connect(refresh)
	session.roster_changed.connect(refresh)
	page.tree_exiting.connect(func() -> void:
		if session.debug_mode_changed.is_connected(refresh):
			session.debug_mode_changed.disconnect(refresh)
		if session.roster_changed.is_connected(refresh):
			session.roster_changed.disconnect(refresh))
	refresh.call()
