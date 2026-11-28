class_name HealthHud
extends Control

const UI := preload("res://scripts/sauce_ui.gd")
const Parts := preload("res://scripts/tomatina_sauce_parts.gd")
const PressKingScript := preload("res://scripts/tomatina_press_king.gd")

## The two health bars: the player's own, pinned to the bottom of the view, and
## one floating over each living enemy.
##
## Both are drawn here rather than as 3D sprites over the enemies, because a
## sprite in the world takes sauce, gets occluded by a stall and turns edge-on
## with the body -- all of which are right for a monster and wrong for its
## health bar. Projecting the world position onto the screen keeps the bar
## legible and keeps it honest about where the enemy actually is.
##
## It draws off the view frame, not the window, so the bars sit inside the
## letterbox rather than under it.

const HUD_WIDTH := 344.0
const ENEMY_BAR := Vector2(120.0, 10.0)
## How far above the enemy's own top the bar floats, in metres.
const ENEMY_LIFT := 0.9
## Past this the bar would be a smear a few pixels wide, and a cluster of them
## reads as noise on the horizon.
const ENEMY_DRAW_RANGE := 20.0

const BACKING := Color(0.04, 0.05, 0.06, 0.78)
const EDGE := Color(0.86, 0.90, 0.94, 0.5)
const PLAYER_FULL := UI.MINT
const PLAYER_LOW := Color("d4564a")
const ENEMY_FULL := Color("e2683c")
const ENEMY_LOW := Color("7a2a20")
## Below this fraction the bar has gone fully to its low colour.
const LOW_AT := 0.35

## What a stall says when you are close enough to be served.
## Keep the usual key list visible and mark unavailable sauces for this stage.
## The arrow marks the sauce currently in the bottle.
const PROMPT_LINES: Array[String] = [
	"[E]  마요네즈",
	"[E]  머스타드",
	"[E]  케찹",
]
const PROMPT_LINE_GAP := 22.0
## What marks the line for the sauce already in the bottle.
const PROMPT_HELD := "  ◀"
const PROMPT_HELD_COLOR := Color("ffffff")
const PROMPT_SIZE := 18
const PROMPT_LIFT := 234.0
const PROMPT_COLOR := Color("fff0a8")
const PROMPT_UNAVAILABLE := Color("a5a29c")
const PROMPT_SHADOW := Color(0.0, 0.0, 0.0, 0.7)

var world: Node3D
var frame := Rect2()
var _plate := UI.box(Color(0.07, 0.11, 0.14, 0.93), UI.EDGE, 10)
var _slot_idle := UI.box(Color(0.08, 0.12, 0.15, 0.88), UI.EDGE, 7)
var _slot_active := UI.box(Color("443632"), UI.ACCENT, 7)
var _bottle_glass := UI.box(Color(0.85, 0.94, 1.0, 0.5), Color.TRANSPARENT, 5)


## 코인이 들어오는 연출. 지갑(`world._local.coins`)이 늘어난 것을 이 화면이 스스로 알아채므로
## 방장이든 팀원이든 똑같이 보이고, 따로 보내는 것이 없다. 늘어난 만큼을 `COIN_STEP`마다
## 하나씩 센다: 하나에 소리 한 번, 날아오는 동전 하나. 한 번에 `RICH_AT`개 이상 들어오면 대박 연출.
const COIN_STEP := 0.08
const COIN_FLIGHT := 0.42
const RICH_AT := 10
const RICH_TIME := 2.4
const COIN_SOUND: AudioStream = preload("res://assets/audio/slot/win_small.wav")
const RICH_SOUND: AudioStream = preload("res://assets/audio/slot/jackpot.wav")
const COIN_FACE := Color("ffd24a")
const COIN_RIM := Color("9a6410")

var _coin_known := -1
## 아직 세지 않은 코인. 화면의 숫자는 지갑에서 이만큼을 뺀 값이다.
var _coin_pending := 0
var _coin_step_left := 0.0
var _coin_combo := 0
var _coin_idle := 0.0
var _coin_pulse := 0.0
## 날아오는 동전들: {origin(월드 좌표, 없으면 INF), age, sway}.
var _coin_flights: Array[Dictionary] = []
var _coin_origin := Vector3.INF
var _coin_voices: Array[AudioStreamPlayer] = []
var _coin_voice_next := 0
var _rich_voice: AudioStreamPlayer
var _rich_left := 0.0
var _rich_gain := 0
var _rich_rain: Array[Dictionary] = []


func _ready() -> void:
	name = "HealthHud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	for index in 6:
		var voice := AudioStreamPlayer.new()
		voice.stream = COIN_SOUND
		voice.volume_db = -7.0
		add_child(voice)
		_coin_voices.push_back(voice)
	_rich_voice = AudioStreamPlayer.new()
	_rich_voice.stream = RICH_SOUND
	_rich_voice.volume_db = -4.0
	add_child(_rich_voice)


## 화면에 적는 코인 수: 아직 날아오는 중인 것은 세지 않는다.
func shown_coins() -> int:
	if world == null or world._local == null:
		return 0
	return maxi(int(world._local.coins) - _coin_pending, 0)


func _advance_coins(delta: float) -> void:
	_coin_pulse = maxf(_coin_pulse - delta * 5.0, 0.0)
	_rich_left = maxf(_rich_left - delta, 0.0)
	for flight in _coin_flights:
		flight.age += delta
	_coin_flights = _coin_flights.filter(func(flight): return flight.age < COIN_FLIGHT)
	if world == null or world._local == null:
		_coin_known = -1
		_coin_pending = 0
		return
	var have := int(world._local.coins)
	if _coin_known >= 0 and have > _coin_known:
		var gain := have - _coin_known
		_coin_pending += gain
		# 어디서 나온 코인인지: 방금 뒤진 시체나 쓰러진 보스. 바닥에서 주운 것은 출처가 없다.
		var parts = world.get("_sauce_parts")
		_coin_origin = Vector3.INF
		if parts != null and Time.get_ticks_msec() - int(parts.burst_msec) < 500:
			_coin_origin = parts.burst_at
		if gain >= RICH_AT:
			_start_rich(gain)
	_coin_known = have
	_coin_pending = mini(_coin_pending, have)
	if _coin_pending <= 0:
		_coin_step_left = 0.0
		_coin_idle += delta
		if _coin_idle > 0.5:
			_coin_combo = 0
		return
	_coin_idle = 0.0
	_coin_step_left -= delta
	while _coin_pending > 0 and _coin_step_left <= 0.0:
		_coin_step_left += COIN_STEP
		_coin_pending -= 1
		_coin_flights.push_back({"origin": _coin_origin, "age": 0.0,
			"sway": sin(float(_coin_combo) * 2.4) * 46.0})
		var voice := _coin_voices[_coin_voice_next]
		_coin_voice_next = (_coin_voice_next + 1) % _coin_voices.size()
		# 이어서 먹을수록 조금씩 높아진다.
		voice.pitch_scale = 1.0 + minf(float(_coin_combo), 12.0) * 0.045
		voice.play()
		_coin_combo += 1
		_coin_pulse = 1.0


func _start_rich(gain: int) -> void:
	_rich_left = RICH_TIME
	_rich_gain = gain
	_rich_voice.play()
	_rich_rain.clear()
	for index in 46:
		# 난수 없이 고르게 흩는다: 화면마다 같은 그림이고, 겹쳐 보이지 않는다.
		_rich_rain.push_back({
			"x": fposmod(float(index) * 0.618034, 1.0),
			"delay": fposmod(float(index) * 0.377, 1.0) * 0.9,
			"speed": 0.75 + fposmod(float(index) * 0.271, 1.0) * 0.6,
			"spin": float(index) * 1.7,
		})


## 코인 숫자가 적힌 자리(동전이 날아가 닿는 곳).
func _coin_counter_at() -> Vector2:
	return Vector2(frame.get_center().x + HUD_WIDTH * 0.5 - 34.0, frame.end.y - 108.0 + 14.0)


func _draw_coin(at: Vector2, radius: float, spin: float, alpha := 1.0) -> void:
	# 세로축으로 도는 동전: 가로로만 납작해진다.
	draw_set_transform(at, 0.0, Vector2(0.18 + 0.82 * absf(cos(spin)), 1.0))
	draw_circle(Vector2.ZERO, radius, Color(COIN_RIM, alpha))
	draw_circle(Vector2.ZERO, radius * 0.78, Color(COIN_FACE, alpha))
	draw_circle(Vector2(-radius * 0.22, -radius * 0.25), radius * 0.26, Color(1.0, 0.97, 0.78, alpha * 0.9))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_coin_effects() -> void:
	var counter := _coin_counter_at()
	var camera := world.get("_camera") as Camera3D
	for flight in _coin_flights:
		var from := counter + Vector2(0.0, -96.0)
		var origin: Vector3 = flight.origin
		if origin.is_finite() and camera != null and is_instance_valid(camera) \
				and not camera.is_position_behind(origin):
			var seen := camera.unproject_position(origin)
			if frame.has_point(seen):
				from = seen
		var t := clampf(float(flight.age) / COIN_FLIGHT, 0.0, 1.0)
		# 위로 튀어 올랐다가 숫자로 빨려 들어간다.
		var lift := from + Vector2(float(flight.sway), -110.0)
		var eased := t * t * (3.0 - 2.0 * t)
		var at := from.lerp(lift, eased).lerp(lift.lerp(counter, eased), eased)
		_draw_coin(at, lerpf(13.0, 8.0, t), float(flight.age) * 16.0)
	if _rich_left <= 0.0:
		return
	var age := RICH_TIME - _rich_left
	var flash := clampf(1.0 - age / 0.45, 0.0, 1.0)
	if flash > 0.0:
		draw_rect(frame, Color(1.0, 0.84, 0.3, 0.3 * flash * flash))
	for drop in _rich_rain:
		var fall := (age - float(drop.delay)) * float(drop.speed)
		if fall <= 0.0 or fall > 1.25:
			continue
		var at := Vector2(frame.position.x + frame.size.x * float(drop.x),
			frame.position.y - 30.0 + (frame.size.y + 60.0) * fall * 0.8)
		_draw_coin(at, 15.0, float(drop.spin) + age * 9.0, clampf((1.25 - fall) * 4.0, 0.0, 1.0))
	var fade := clampf(_rich_left / 0.5, 0.0, 1.0)
	var pop := 1.0 + 0.35 * clampf(1.0 - age / 0.25, 0.0, 1.0)
	var font := ThemeDB.fallback_font
	var title := "대박! +%d 코인" % _rich_gain
	var size_px := roundi(46.0 * pop)
	var width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size_px).x
	var where := Vector2(frame.get_center().x - width * 0.5, frame.position.y + frame.size.y * 0.3)
	draw_string_outline(font, where, title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size_px, 10,
		Color(0.16, 0.08, 0.0, fade))
	draw_string(font, where, title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size_px, Color(COIN_FACE, fade))


func set_frame(new_frame: Rect2) -> void:
	frame = new_frame
	queue_redraw()


var _pickup_refresh_left := 0.0
var _pickup_target: Node3D
var _nearby_pickups: Array[Node3D] = []
var pickup_scan_count := 0
var feedback_rows: Array[Dictionary] = []
var _occlusion_cache := {}
var _occlusion_frame := -1
var _occlusion_budget := 0

func notify_action(text: String, accent := Color("ffd46a")) -> void:
	if not feedback_rows.is_empty() and feedback_rows.back().text == text and feedback_rows.back().left > 2.3:
		feedback_rows.back().count += 1
		feedback_rows.back().left = 2.8
		return
	feedback_rows.append({"text": text, "color": accent, "left": 2.8, "count": 1})
	while feedback_rows.size() > 3:
		feedback_rows.pop_front()

func _process(_delta: float) -> void:
	_pickup_refresh_left -= _delta
	if _pickup_refresh_left <= 0.0:
		_pickup_refresh_left = 0.1
		_refresh_pickups()
	_advance_coins(_delta)
	for row in feedback_rows:
		row.left -= _delta
	feedback_rows = feedback_rows.filter(func(row): return row.left > 0.0)

	# Both bars move every frame -- one with the damage, one with the enemy --
	# so there is nothing to be gained by trying to redraw only on a change.
	queue_redraw()


func _draw() -> void:
	if world == null or frame.size.x <= 0.0:
		return
	_draw_enemies()
	if world._local == null:
		return
	_draw_player()
	_draw_team()
	_draw_context_extras()
	_draw_slots()
	_draw_prompt()
	_draw_pickup_hint()
	var action: String = world._tomatina_action_hint() if world.map_kind == world.MapKind.TOMATINA else ""
	if not action.is_empty():
		_draw_action_chip(action)
	var controls := "R 고글 닦기   ·   V 밀치기   ·   F4 조작표" if world.map_kind == world.MapKind.TOMATINA else "1–5 장비 선택 · F4 조작표"
	if world.map_kind == world.MapKind.TOMATINA:
		var options := preload("res://scripts/game_options.gd")
		controls = "%s 고글 닦기 · %s 밀치기 · F4 조작표" % [options.key_label("wipe_screen", "R"), options.key_label("shove", "V")]
	if world.local_holds_tomato():
		controls = "좌클릭 꾹: 힘 모으기 · 놓기: 던지기   /   우클릭: 먹기"
		if world._tomato_charge_started.has(world._local.peer_id):
			var charge: float = world.tomato_charge_fraction(world._local.peer_id)
			var meter := Rect2(frame.get_center() + Vector2(-60.0, 36.0), Vector2(120.0, 7.0))
			_draw_bar(meter, charge, UI.GOLD, UI.ACCENT, 1.0)
	if world.map_kind == world.MapKind.TOMATINA:
		_draw_coin_effects()
	var footer := Rect2(frame.get_center().x - 210.0, frame.end.y - 30.0, 420.0, 22.0)
	draw_style_box(_slot_idle, footer)
	draw_string(ThemeDB.fallback_font, footer.position + Vector2(0.0, 16.0), controls,
		HORIZONTAL_ALIGNMENT_CENTER, footer.size.x, 14, UI.CREAM)


func _draw_team() -> void:
	if world.map_kind != world.MapKind.TOMATINA or world._shooters.size() < 2:
		return
	var players: Array = world._shooters.values()
	players.sort_custom(func(a, b): return a.spawn_slot < b.spawn_slot)
	var top := frame.position.y + 104.0
	if is_instance_valid(world._objective_card):
		top = maxf(top, world._objective_card.position.y + world._objective_card.size.y + 12.0)
	var practice: bool = world.get_meta("bot_practice", false)
	var panel := Rect2(frame.position.x + 20, top, 270, 34 + players.size() * 40 + (24 if practice else 0))
	draw_style_box(_plate, panel)
	var font := ThemeDB.fallback_font
	draw_string(font, panel.position + Vector2(12, 21), "팀 상태", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.MUTED)
	for index in players.size():
		var shooter = players[index]
		var at := panel.position + Vector2(12, 34 + index * 40)
		var own: bool = shooter == world._local
		var hp: float = shooter.player.health_fraction()
		var down: bool = shooter.player.state == MayoPlayer.State.DEAD
		draw_string(font, at + Vector2(0, 14), "P%d" % (shooter.spawn_slot + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UI.MINT if own else UI.CREAM)
		var status := "구조 필요" if down else "체력 %d" % ceili(shooter.player.health)
		draw_string(font, at + Vector2(40, 12), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, PLAYER_LOW if down or hp < LOW_AT else UI.CREAM)
		draw_string(font, at + Vector2(158, 12), "소스 %d%%" % roundi(shooter.sauce * 100), HORIZONTAL_ALIGNMENT_RIGHT, 88, 13, UI.GOLD if shooter.sauce < 0.25 else UI.MUTED)
		_draw_bar(Rect2(at + Vector2(40, 20), Vector2(206, 7)), hp, PLAYER_FULL, PLAYER_LOW, 1.0)
	if practice:
		draw_string(font, Vector2(panel.position.x + 12, panel.end.y - 10), "F6 내 자동조작 %s" % ("ON" if world.get_meta("bot_autoplay", false) else "OFF"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UI.MUTED)


func _draw_slots() -> void:
	var slots: Array = world.item_slots(world._local.peer_id)
	var selected: int = world.selected_item_slot(world._local.peer_id)
	var width := 62.0
	var gap := 8.0
	var left := frame.get_center().x - (width * 5.0 + gap * 4.0) * 0.5
	for slot in 5:
		var rect := Rect2(left + slot * (width + gap), frame.end.y - 163.0, width, 48.0)
		draw_style_box(_slot_active if selected == slot else _slot_idle, rect)
		if selected == slot:
			draw_style_box(UI.box(Color.TRANSPARENT, UI.MINT, 7), rect.grow(1.0))
			draw_line(rect.position + Vector2(10, 44), rect.position + Vector2(width - 10, 44), UI.MINT, 3.0, true)
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(6.0, 14.0), str(slot + 1),
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, UI.ACCENT if selected == slot else UI.MUTED)
		if slot == 0:
			_draw_bottle_icon(rect.get_center() + Vector2(5.0, 0.0))
		elif slots[slot] == 1:
			_draw_tomato_icon(rect.get_center() + Vector2(5.0, 2.0))
		else:
			draw_line(rect.get_center() + Vector2(-3.0, 1.0), rect.get_center() + Vector2(7.0, 1.0),
				UI.EDGE, 1.0, true)


func _draw_player() -> void:
	var player: MayoPlayer = world._local.player
	var panel := Rect2(frame.get_center().x - HUD_WIDTH * 0.5, frame.end.y - 108.0, HUD_WIDTH, 73.0)
	draw_style_box(_plate, panel)
	var font := ThemeDB.fallback_font
	var at := panel.position + Vector2(12.0, 19.0)
	var part: int = world._local.sauce_part
	var level: float = world.local_sauce()
	var cannon := part == Parts.Part.CANNON
	var stage_two: bool = world.map_kind == world.MapKind.TOMATINA
	if stage_two:
		draw_string(font, at, Parts.CATALOG[part][0], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, UI.CREAM)
		# 코인을 하나 셀 때마다 숫자가 잠깐 커지고 밝아진다.
		draw_string(font, at + Vector2(215.0, 0.0), "%d 코인" % shown_coins(),
			HORIZONTAL_ALIGNMENT_RIGHT, HUD_WIDTH - 239.0, 14 + roundi(4.0 * _coin_pulse),
			UI.GOLD.lerp(Color.WHITE, _coin_pulse * 0.7))
	else:
		draw_string(font, at, "장비 상태", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, UI.CREAM)

	var hp := Rect2(panel.position + Vector2(57.0, 27.0), Vector2(207.0, 15.0))
	var tank := Rect2(hp.position + Vector2(0.0, 22.0), hp.size)
	var sauce_color: Color = [UI.CREAM, UI.GOLD, UI.ACCENT][clampi(world.local_sauce_kind(), 0, 2)]
	_draw_bar(hp, player.health_fraction(), PLAYER_FULL, PLAYER_LOW, 1.0)
	_draw_bar(tank, level, UI.GOLD if level < 0.25 else sauce_color, sauce_color.darkened(0.35), 1.0)
	var markers: Array = [0.25, 0.5, 0.75] if cannon else [world.get("burst_midpoint")]
	for fraction: float in markers:
		var notch := tank.position.x + tank.size.x * fraction
		draw_line(Vector2(notch, tank.position.y + 1.0), Vector2(notch, tank.end.y - 1.0), UI.INK, 1.0)
	draw_string(font, at + Vector2(0.0, 19.0), "체력", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, UI.MUTED)
	draw_string(font, at + Vector2(0.0, 41.0), "소스", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, UI.MUTED)
	var health := "%d / %d" % [ceili(player.health), ceili(player.max_health)]
	var sauce := "%d / 4발" % floori(level * 4.0) if cannon else "%d%%" % roundi(level * 100.0)
	draw_string(font, at + Vector2(256.0, 19.0), health, HORIZONTAL_ALIGNMENT_RIGHT, 64.0, 13, UI.CREAM)
	draw_string(font, at + Vector2(256.0, 41.0), sauce, HORIZONTAL_ALIGNMENT_RIGHT, 64.0, 13, sauce_color)
	var status := _bottle_status()
	if not status.is_empty():
		var notice := Rect2(panel.position + Vector2(0.0, -86.0), Vector2(HUD_WIDTH, 25.0))
		draw_style_box(_plate, notice)
		var color := UI.ACCENT if status.begins_with("소스 부족") else UI.GOLD
		draw_string(font, notice.position + Vector2(0.0, 17.0), status,
			HORIZONTAL_ALIGNMENT_CENTER, notice.size.x, 14, color)
	# The shake gauge: a strip under the tank, filling while the bottle is
	# shaken, holding, then running down; and what it is doing, beside it.
	# (x the gauge, y seconds of hold left, z the strength of a boost under way.)
	var charge: Vector3 = world.local_bottle_charge()
	if charge.x > 0.0 or charge.z > 0.0:
		var strip := Rect2(tank.position + Vector2(0.0, tank.size.y + 3.0), Vector2(tank.size.x, 4.0))
		var fill := charge.x
		var tint := UI.MINT
		var note := "강화 게이지 %d%%" % roundi(charge.x * 100.0)
		if charge.z > 0.0:
			# The boosted shot is going out now, at the strength it was spent at.
			fill = charge.z
			tint = UI.GOLD
			note = "강화 분사 %d%%" % roundi(charge.z * 100.0)
		elif world._local.bottle_shake_input > 0.0:
			note = "흔드는 중 %d%%" % roundi(charge.x * 100.0)
		elif charge.y > 0.0:
			note = "강화 유지 %.1f초" % charge.y
		else:
			tint = UI.MUTED
			note = "강화 감소 중 %d%%" % roundi(charge.x * 100.0)
		draw_rect(strip, BACKING, true)
		draw_rect(Rect2(strip.position, Vector2(strip.size.x * clampf(fill, 0.0, 1.0), strip.size.y)), tint, true)
		draw_string(font, at + Vector2(104.0, 0.0), note,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, tint)


func _bottle_status() -> String:
	var shooter = world._local
	if world.map_kind != world.MapKind.TOMATINA or not world._input_enabled \
			or shooter.player.is_incapacitated() or world.selected_item_slot(shooter.peer_id) != 0 \
			or world._hose_slot_of(shooter.peer_id) >= 0 or world._refuge_shop_room >= 0:
		return ""
	if shooter.nozzle == world.Nozzle.CAUGHT:
		return "노즐 막힘 · 우클릭을 누른 채 마우스 흔들기"
	var part: int = shooter.sauce_part
	if Parts.PROJECTILES.has(part):
		if shooter.sauce < Parts.PROJECTILES[part].cost and shooter.part_shots_left == 0:
			return "소스 부족 · 보급 지점에서 충전"
		return ""
	var stage: int = world.sauce_stage_of(shooter.sauce)
	if stage == world.SauceStage.EMPTY and shooter.nozzle != world.Nozzle.STREAM:
		return "소스 부족 · 보급 지점에서 충전"
	if shooter.firing and shooter.fire_cooldown > 0.0 and world._burst_spent(shooter):
		return "압력 회복 중"
	if stage == world.SauceStage.SPLUTTERING:
		return "소스 잔량 낮음 · 보급 지점에서 충전"
	return ""


## The current prompt's target, as the play support chose it: its kind and
## where in the world it is pinned (`anchor`, INF for none).
func _action_target() -> Dictionary:
	var support = world.get("play_support")
	if support == null or not is_instance_valid(support) or world._local == null:
		return {}
	return support.context_target(world._local)


## Every prompt is drawn beside the thing it acts on, at twice the old size.
## Off screen it is not drawn -- the thing is not in view, so neither is what
## to do with it -- except the hose being held, whose stand the holder walks
## away from: that one falls back to the bottom of the screen.
func _draw_action_chip(text: String) -> void:
	var target := _action_target()
	var anchor: Vector3 = target.get("anchor", Vector3.INF)
	var zoom := 2.0
	var at := Vector2.INF
	var camera := world.get("_camera") as Camera3D
	if anchor.is_finite():
		if camera != null and is_instance_valid(camera) and not camera.is_position_behind(anchor):
			at = camera.unproject_position(anchor)
		if not at.is_finite() or not frame.has_point(at):
			if target.get("kind", "") != "hose":
				return
			at = Vector2.INF
	var font := ThemeDB.fallback_font
	var key_label := preload("res://scripts/game_options.gd").key_label("interact", "E")
	var message := text.trim_prefix("[%s] " % key_label)
	var width := font.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1.0, roundi(17 * zoom)).x
	var chip_size := Vector2(width + 62.0 * zoom, 38.0 * zoom)
	var card := Rect2(frame.get_center().x - chip_size.x * 0.5, frame.end.y - 240.0, chip_size.x, chip_size.y)
	if at.is_finite():
		# To the right of the anchor, centred on it, clear of the 0.2 m around
		# it (the shower's cross) however near the camera stands.
		var clear := camera.unproject_position(anchor + camera.global_basis.x * 0.2).x - at.x
		card.position = at + Vector2(maxf(clear, 0.0) + 12.0, -chip_size.y * 0.5)
		if target.get("kind", "") == "shop":
			# The tent is the thing itself, and big: the prompt sits on it.
			card.position = at - chip_size * 0.5
		card.position = card.position.clamp(frame.position, frame.end - chip_size)
	draw_style_box(_plate, card)
	var key := Rect2(card.position + Vector2(8.0, 7.0) * zoom, Vector2(25.0, 24.0) * zoom)
	draw_style_box(_slot_active, key)
	draw_string(font, key.position + Vector2(0.0, 17.0 * zoom), key_label, HORIZONTAL_ALIGNMENT_CENTER,
		key.size.x, roundi(15 * zoom), UI.CREAM)
	draw_string(font, card.position + Vector2(43.0, 25.0) * zoom, message,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, roundi(17 * zoom), UI.CREAM)

func _draw_enemies() -> void:
	var camera := world.get("_camera") as Camera3D
	if camera == null or not is_instance_valid(camera):
		return
	# `unproject_position` gives window pixels, `frame` is in window pixels, and
	# this Control sits at the window origin -- so a projected point is already
	# in the space being drawn in. It used to be scaled by `size / window`
	# first, which looks like it belongs but does not: a Control under a
	# CanvasLayer reports `size` as zero, so every bar was multiplied to (0, 0)
	# and drawn in the screen corner. The player's bar is laid out from `frame`
	# and never went through it, which is why it was the only one showing.
	# Asked of the world rather than of the tree: groups are tree-wide, and the
	# harness runs several worlds in one tree, so a group lookup would hang
	# every world's enemies over every screen.
	var camera_pose := camera.global_transform
	var tomatina: bool = world.map_kind == world.MapKind.TOMATINA
	var count: int = world.enemy_count()
	for index in count:
		var enemy := world.enemy_at(index) as MayoEnemy
		if enemy == null or not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		# A bowled ball cannot be hurt, so a bar over it would never move.
		if enemy.kind == MayoEnemy.EnemyKind.TOMATO_BALL:
			continue
		if tomatina:
			if enemy.kind == MayoEnemy.EnemyKind.PRESS_KING:
				var boss := enemy as PressKingScript
				var card := Rect2(frame.get_center().x - 158.0, frame.position.y + 18.0, 316.0, 52.0)
				draw_style_box(_plate, card)
				draw_string(ThemeDB.fallback_font, card.position + Vector2(12.0, 21.0),
					"토마토 압착왕", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, UI.CREAM)
				var meter := Rect2(card.position + Vector2(12.0, 32.0), Vector2(292.0, 9.0))
				var phase := UI.MINT if boss.exposed_left > 0.0 else UI.ACCENT
				_draw_bar(meter, boss.health_fraction(), phase, ENEMY_LOW, 1.0)
				continue
			if enemy.kind == MayoEnemy.EnemyKind.TOMATO_GRUNT:
				var to_enemy := enemy.global_position - camera_pose.origin
				var distance_squared := to_enemy.length_squared()
				if distance_squared > 30.0 ** 2:
					continue
				var facing := to_enemy.dot(-camera_pose.basis.z)
				if facing <= 0.0 or facing * facing < distance_squared * 0.997 ** 2:
					continue
		var bar := enemy_bar_rect(enemy, camera)
		if bar.size.x <= 0.0:
			continue
		_draw_bar(bar, enemy.health_fraction(), ENEMY_FULL, ENEMY_LOW, 1.0)


## The refill prompt, over the tank. Drawn only while a stall is in reach, so it
## doubles as the feedback that says you are close enough -- without it a stall
## is a blue box that silently does nothing until you happen to be in the right
## spot with the right key down.
func _draw_prompt() -> void:
	if is_instance_valid(world.play_support):
		return # Tomatina uses the same selected target for prompt and action.
	if not world.local_at_station():
		return
	var font := ThemeDB.fallback_font
	var held: int = world.local_sauce_kind()
	# Every line is laid out against the widest of them, so the block is a block
	# rather than a ragged edge that shifts as the marker moves down it.
	# One line: a station hands out one sauce, and E takes it.
	var first_sauce: int = clampi(world.local_station_sauce(), 0, PROMPT_LINES.size() - 1)
	var lines := PackedStringArray([PROMPT_LINES[first_sauce]])
	for index in lines.size():
		if not world.can_select_refill_sauce(first_sauce + index):
			lines[index] += "  ·  보급 불가"
	var widest := 0.0
	for line in lines:
		widest = maxf(widest,
			font.get_string_size(line + PROMPT_HELD, HORIZONTAL_ALIGNMENT_LEFT,
				-1.0, PROMPT_SIZE).x)
	var top := frame.position.y + frame.size.y - PROMPT_LIFT \
		- PROMPT_LINE_GAP * float(lines.size() - 1)
	draw_style_box(_plate, Rect2(frame.get_center().x - widest * 0.5 - 12.0,
		top - 21.0, widest + 24.0, 32.0 + PROMPT_LINE_GAP * float(lines.size() - 1)))
	for index in lines.size():
		var line: String = lines[index]
		var available: bool = world.can_select_refill_sauce(first_sauce + index)
		var colour := PROMPT_COLOR if available else PROMPT_UNAVAILABLE
		if first_sauce + index == held:
			line += PROMPT_HELD
			if available:
				colour = PROMPT_HELD_COLOR
		var at := Vector2(
			frame.position.x + (frame.size.x - widest) * 0.5,
			top + PROMPT_LINE_GAP * float(index))
		# Drawn twice, offset: the street is dark but a wall behind it may not be.
		draw_string(font, at + Vector2(1.0, 1.0), line, HORIZONTAL_ALIGNMENT_LEFT,
			-1.0, PROMPT_SIZE, PROMPT_SHADOW)
		draw_string(font, at, line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, PROMPT_SIZE, colour)


## Where this enemy's bar goes, or a zero rect if it does not get one. Split out
## of `_draw_enemies` so it can be asked the question directly: a bar that ends
## up in the wrong place is invisible rather than wrong-looking, and a drawing
## call answers nothing about where it went.
func enemy_bar_rect(enemy: MayoEnemy, camera: Camera3D) -> Rect2:
	if enemy == null or camera == null or not enemy.is_alive():
		return Rect2()
	var head := enemy.global_position + Vector3.UP * (enemy.stand_height() + ENEMY_LIFT)
	if camera.is_position_behind(head):
		return Rect2()
	var player := world.get("_player") as MayoPlayer if is_instance_valid(world) else null
	if not is_instance_valid(player):
		return Rect2()
	if player.global_position.distance_squared_to(enemy.global_position) > ENEMY_DRAW_RANGE * ENEMY_DRAW_RANGE:
		return Rect2()
	var at: Vector2 = camera.unproject_position(head)
	if not frame.has_point(at):
		return Rect2()
	if world.map_kind == world.MapKind.TOMATINA:
		var tick := Engine.get_physics_frames()
		if _occlusion_frame != tick:
			_occlusion_frame = tick
			_occlusion_budget = 4
		var key := enemy.get_instance_id()
		var cached: Dictionary = _occlusion_cache.get(key, {})
		if _occlusion_budget > 0 and (cached.is_empty() or tick - int(cached.tick) >= 8):
			_occlusion_budget -= 1
			var query := PhysicsRayQueryParameters3D.create(camera.global_position,
				enemy.global_position, 1)
			query.exclude = [player.get_rid()]
			var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
			cached = {"tick": tick, "visible": hit.is_empty() or hit.collider == enemy}
			_occlusion_cache[key] = cached
		if cached.is_empty() or not cached.visible:
			return Rect2()
	return Rect2(at - Vector2(ENEMY_BAR.x * 0.5, ENEMY_BAR.y), ENEMY_BAR)


## Backing, fill, then outline. The fill is inset by the border so a full bar
## reads as full rather than as one pixel short of it.
func _draw_bar(rect: Rect2, fraction: float, full: Color, low: Color, border: float) -> void:
	draw_rect(rect, BACKING, true)
	var inner := Rect2(rect.position + Vector2(border, border),
		rect.size - Vector2(border, border) * 2.0)
	if fraction > 0.0 and inner.size.x > 0.0:
		var fill := Rect2(inner.position, Vector2(inner.size.x * fraction, inner.size.y))
		draw_rect(fill, low.lerp(full, clampf(fraction / LOW_AT, 0.0, 1.0)), true)
	draw_rect(rect, EDGE, false, border)


func _draw_tomato_icon(at: Vector2) -> void:
	draw_circle(at + Vector2(0,3), 15, Color("8d271d"))
	draw_circle(at, 14, Color("ec4931"))
	draw_circle(at + Vector2(-5,-5), 4, Color("ff8762"))
	for i in 5:
		var angle := TAU * float(i) / 5.0
		draw_line(at + Vector2(0,-10), at + Vector2(cos(angle)*8, -10+sin(angle)*5), Color("69bc43"), 3, true)
	draw_line(at + Vector2(0,-10), at + Vector2(2,-19), Color("75cf4a"), 3, true)


func _draw_bottle_icon(at: Vector2) -> void:
	var fill := Color("fff0a8")
	var kind: int = world.local_sauce_kind()
	if kind == 1:
		fill = Color("e5b939")
	elif kind == 2:
		fill = Color("e84b32")
	var body := Rect2(at + Vector2(-10,-9),Vector2(20,27))
	draw_style_box(_bottle_glass, body)
	draw_rect(Rect2(at + Vector2(-7, 0), Vector2(14, 15)), fill)
	draw_rect(Rect2(at+Vector2(-7,-14),Vector2(14,6)), Color("f3d052"))
	draw_colored_polygon(PackedVector2Array([at+Vector2(-3,-14),at+Vector2(3,-14),at+Vector2(1,-22)]),Color("fff3bf"))
	draw_line(at+Vector2(-6,-6),at+Vector2(-6,12),Color(1,1,1,0.8),2,true)


func _draw_pickup_hint() -> void:
	if world.map_kind == world.MapKind.TOMATINA:
		if not world._tomatina_action_hint().is_empty() or world.rescue_hud_state().get("in_reach", false):
			return
	var player := world.get("_player") as MayoPlayer
	var camera := world.get("_camera") as Camera3D
	if not is_instance_valid(player) or not is_instance_valid(camera):
		return
	if player.state != MayoPlayer.State.NORMAL or not is_instance_valid(_pickup_target) or not _pickup_target.visible:
		return
	var chosen := _pickup_target.global_position
	if player.global_position.distance_squared_to(chosen) > 6.25 or camera.is_position_behind(chosen):
		return
	if chosen == Vector3.INF:
		return
	var text := "[E] 토마토 줍기 · 회복 +%d" % int(world.healing_tomato_amount)
	if world.item_slots(world._local.peer_id).find(0,1) < 0:
		text = "인벤토리가 가득 찼어요"
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x
	var point := camera.unproject_position(chosen)
	if not frame.has_point(point):
		return
	draw_arc(point, 11.0, 0.0, TAU, 24, UI.MINT, 2.0, true)
	var screen := point + Vector2(-width*0.5,-30)
	screen.x = clampf(screen.x,frame.position.x+8,frame.end.x-width-8)
	screen.y = clampf(screen.y,frame.position.y+25,frame.end.y-190)
	draw_string(font,screen+Vector2(1,2),text,HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color.BLACK)
	draw_string(font,screen,text,HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color.WHITE)


func _refresh_pickups() -> void:
	_pickup_target = null
	if not is_instance_valid(world) or world._local == null:
		return
	var player := world.get("_player") as MayoPlayer
	var camera := world.get("_camera") as Camera3D
	if not is_instance_valid(player) or not is_instance_valid(camera):
		return
	if player.state != MayoPlayer.State.NORMAL:
		_nearby_pickups.clear()
		return
	var nearest := 2.5 * 2.5
	_pickup_target = null
	_nearby_pickups.clear()
	pickup_scan_count += 1
	for id in world._healing_tomatoes:
		# Negative IDs are held items, large IDs are airborne tomatoes.
		if id < 0 or id >= 1000000:
			continue
		var node = world._healing_tomatoes[id].node
		var at: Vector3 = node.global_position
		var distance := player.global_position.distance_squared_to(at)
		if distance >= nearest or camera.is_position_behind(at):
			continue
		var screen := camera.unproject_position(at)
		if not frame.has_point(screen):
			continue
		var query := PhysicsRayQueryParameters3D.create(camera.global_position,at,1)
		query.exclude = [player.get_rid()]
		var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.position.distance_to(at) > 0.5:
			continue
		nearest = distance
		_pickup_target = node

	# At most three visible nearby markers; projection follows the camera each frame.
	var candidates: Array = []
	for id in world._healing_tomatoes:
		if id < 0 or id >= 1000000:
			continue
		var node = world._healing_tomatoes[id].node
		var distance := player.global_position.distance_squared_to(node.global_position)
		if distance <= 144.0:
			candidates.append({"node": node, "distance": distance})
			candidates.sort_custom(func(a, b): return a.distance < b.distance)
			if candidates.size() > 3:
				candidates.pop_back()
	for entry in candidates:
		var node: Node3D = entry.node
		var query := PhysicsRayQueryParameters3D.create(camera.global_position, node.global_position, 1)
		query.exclude = [player.get_rid()]
		var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or hit.position.distance_to(node.global_position) <= 0.5:
			_nearby_pickups.append(node)

func _draw_context_extras() -> void:
	if world._local == null or world._local.player.is_incapacitated():
		return
	var camera := world.get("_camera") as Camera3D
	if is_instance_valid(camera):
		for node in _nearby_pickups:
			if not is_instance_valid(node) or node == _pickup_target or not node.visible:
				continue
			var at := node.global_position + Vector3.UP * 0.2
			if camera.is_position_behind(at):
				continue
			var screen := camera.unproject_position(at)
			if frame.grow(-24).has_point(screen):
				draw_circle(screen, 5.0, Color(0.04, 0.08, 0.1, 0.85))
				draw_circle(screen, 2.5, UI.MINT)
	var y := frame.get_center().y + 80.0
	for row in feedback_rows:
		var alpha := minf(row.left * 2.5, 1.0)
		var text: String = row.text
		if row.count > 1:
			text += " ×%d" % row.count
		var width := minf(520.0, ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + 28.0)
		var rect := Rect2(frame.get_center().x - width * 0.5, y, width, 30.0)
		draw_style_box(_plate, rect)
		var tint: Color = row.color
		tint.a = alpha
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(0, 21), text, HORIZONTAL_ALIGNMENT_CENTER, width, 17, tint)
		y += 35.0
