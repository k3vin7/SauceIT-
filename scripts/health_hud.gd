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
	"[Shift+1]  마요네즈",
	"[Shift+2]  머스타드",
	"[Shift+3]  케찹",
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


func _ready() -> void:
	name = "HealthHud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func set_frame(new_frame: Rect2) -> void:
	frame = new_frame
	queue_redraw()


func _process(_delta: float) -> void:
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
	_draw_slots()
	_draw_prompt()
	_draw_pickup_hint()
	var action: String = world._tomatina_action_hint() if world.map_kind == world.MapKind.TOMATINA else ""
	if not action.is_empty():
		_draw_action_chip(action)
	var controls := "R 고글 닦기   ·   V 밀치기   ·   F4 조작표" if world.map_kind == world.MapKind.TOMATINA else "1–5 장비 선택"
	if world.local_holds_tomato():
		controls = "좌클릭 꾹: 힘 모으기 · 놓기: 던지기   /   우클릭: 먹기"
		if world._tomato_charge_started.has(world._local.peer_id):
			var charge: float = world.tomato_charge_fraction(world._local.peer_id)
			var meter := Rect2(frame.get_center() + Vector2(-60.0, 36.0), Vector2(120.0, 7.0))
			_draw_bar(meter, charge, UI.GOLD, UI.ACCENT, 1.0)
	var footer := Rect2(frame.get_center().x - 192.0, frame.end.y - 21.0, 384.0, 17.0)
	draw_style_box(_slot_idle, footer)
	draw_string(ThemeDB.fallback_font, footer.position + Vector2(0.0, 13.0), controls,
		HORIZONTAL_ALIGNMENT_CENTER, footer.size.x, 13, UI.CREAM)


func _draw_slots() -> void:
	var slots: Array = world.item_slots(world._local.peer_id)
	var selected: int = world.selected_item_slot(world._local.peer_id)
	var width := 62.0
	var gap := 8.0
	var left := frame.get_center().x - (width * 5.0 + gap * 4.0) * 0.5
	for slot in 5:
		var rect := Rect2(left + slot * (width + gap), frame.end.y - 151.0, width, 48.0)
		draw_style_box(_slot_active if selected == slot else _slot_idle, rect)
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
	var panel := Rect2(frame.get_center().x - HUD_WIDTH * 0.5, frame.end.y - 96.0, HUD_WIDTH, 73.0)
	draw_style_box(_plate, panel)
	var font := ThemeDB.fallback_font
	var at := panel.position + Vector2(12.0, 19.0)
	var part: int = world._local.sauce_part
	var level: float = world.local_sauce()
	var cannon := part == Parts.Part.CANNON
	var stage_two: bool = world.map_kind == world.MapKind.TOMATINA
	if stage_two:
		draw_string(font, at, Parts.CATALOG[part][0], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, UI.CREAM)
		draw_string(font, at + Vector2(215.0, 0.0), "%d 코인" % world._local.coins,
			HORIZONTAL_ALIGNMENT_RIGHT, HUD_WIDTH - 239.0, 14, UI.GOLD)
	else:
		draw_string(font, at, "장비 상태", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, UI.CREAM)

	var hp := Rect2(panel.position + Vector2(57.0, 28.0), Vector2(207.0, 12.0))
	var tank := Rect2(hp.position + Vector2(0.0, 22.0), hp.size)
	var sauce_color: Color = [UI.CREAM, UI.GOLD, UI.ACCENT][clampi(world.local_sauce_kind(), 0, 2)]
	_draw_bar(hp, player.health_fraction(), PLAYER_FULL, PLAYER_LOW, 1.0)
	_draw_bar(tank, level, sauce_color, sauce_color.darkened(0.35), 1.0)
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


func _draw_action_chip(text: String) -> void:
	var font := ThemeDB.fallback_font
	var message := text.trim_prefix("[E] ")
	var width := font.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 17).x
	var card := Rect2(frame.get_center().x - (width + 62.0) * 0.5, frame.end.y - 201.0, width + 62.0, 38.0)
	draw_style_box(_plate, card)
	var key := Rect2(card.position + Vector2(8.0, 7.0), Vector2(25.0, 24.0))
	draw_style_box(_slot_active, key)
	draw_string(font, key.position + Vector2(0.0, 17.0), "E", HORIZONTAL_ALIGNMENT_CENTER, key.size.x, 15, UI.CREAM)
	draw_string(font, card.position + Vector2(43.0, 25.0), message,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 17, UI.CREAM)

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
	var count: int = world.enemy_count()
	for index in count:
		var enemy := world.enemy_at(index) as MayoEnemy
		if enemy == null or not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		if world.map_kind == world.MapKind.TOMATINA:
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
				var to_enemy := enemy.global_position - camera.global_position
				if to_enemy.length_squared() > 30.0 ** 2 or to_enemy.normalized().dot(-camera.global_basis.z) < 0.997:
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
	if not world.local_at_station():
		return
	var font := ThemeDB.fallback_font
	var held: int = world.local_sauce_kind()
	# Every line is laid out against the widest of them, so the block is a block
	# rather than a ragged edge that shifts as the marker moves down it.
	var lines := PROMPT_LINES.duplicate()
	var first_sauce := 0
	if world.map_kind == world.MapKind.TOMATINA:
		lines = PackedStringArray([PROMPT_LINES[2]])
		first_sauce = 2
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
	var nearest := 2.5 * 2.5
	var chosen := Vector3.INF
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
		chosen = at
	if chosen == Vector3.INF:
		return
	var text := "[E] 토마토 줍기"
	if world.item_slots(world._local.peer_id).find(0,1) < 0:
		text = "인벤토리가 가득 찼어요"
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x
	var screen := camera.unproject_position(chosen) + Vector2(-width*0.5,-30)
	screen.x = clampf(screen.x,frame.position.x+8,frame.end.x-width-8)
	screen.y = clampf(screen.y,frame.position.y+25,frame.end.y-190)
	draw_string(font,screen+Vector2(1,2),text,HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color.BLACK)
	draw_string(font,screen,text,HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color.WHITE)
