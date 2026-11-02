class_name HealthHud
extends Control

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

const PLAYER_BAR := Vector2(320.0, 20.0)
const PLAYER_MARGIN := 28.0
## The tank, under the health bar. Slimmer, because it is the second thing you
## look at rather than the first.
const SAUCE_BAR := Vector2(320.0, 12.0)
const SAUCE_GAP := 6.0
const ENEMY_BAR := Vector2(120.0, 10.0)
## How far above the enemy's own top the bar floats, in metres.
const ENEMY_LIFT := 0.9
## Past this the bar would be a smear a few pixels wide, and a cluster of them
## reads as noise on the horizon.
const ENEMY_DRAW_RANGE := 20.0

const BACKING := Color(0.04, 0.05, 0.06, 0.78)
const EDGE := Color(0.86, 0.90, 0.94, 0.5)
const PLAYER_FULL := Color("6fd38a")
const PLAYER_LOW := Color("d4564a")
## Mayo, and mayo with nothing behind it.
const SAUCE_FULL := Color("fff0a8")
const SAUCE_LOW := Color("8a7a3c")
const ENEMY_FULL := Color("e2683c")
const ENEMY_LOW := Color("7a2a20")
## Below this fraction the bar has gone fully to its low colour.
const LOW_AT := 0.35

## What a stall says when you are close enough to be served.
## **Every stall offers the same three fresh bottles.** The list is
## the prompt now rather than one line, because a key that does nothing visible
## until you press it is how the stalls read before they said anything at all --
## and a player who never learns 2 exists never finds out mustard is in the game.
## The sauce in the bottle is marked, so the prompt also answers "what am I
## carrying", which nothing else on the HUD does.
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
const PROMPT_LIFT := 220.0
const PROMPT_COLOR := Color("fff0a8")
const PROMPT_SHADOW := Color(0.0, 0.0, 0.0, 0.7)

var world: Node3D
var frame := Rect2()


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
	_draw_player()
	_draw_enemies()
	_draw_prompt()
	if world._local != null:
		var slots: Array = world.item_slots(world._local.peer_id)
		var selected: int = world.selected_item_slot(world._local.peer_id)
		for slot in 5:
			var rect := Rect2(Vector2(frame.get_center().x - 160 + slot*65,frame.end.y-145),Vector2(60,48))
			draw_rect(rect, Color(1,1,1,1.0 if selected == slot else 0.45), false, 3 if selected == slot else 1)
			if slot == 0:
				_draw_bottle_icon(rect.get_center())
			elif slots[slot] == 1:
				_draw_tomato_icon(rect.get_center())
	_draw_pickup_hint()
	var tomato_hint := "1~5 장비 선택"
	if world.local_holds_tomato():
		tomato_hint = "좌클릭 꾹: 힘 모으기 · 놓기: 던지기 / 우클릭: 먹기"
		if world._tomato_charge_started.has(world._local.peer_id):
			var charge: float = world.tomato_charge_fraction(world._local.peer_id)
			var meter := Rect2(frame.get_center() + Vector2(-60,36),Vector2(120,7))
			draw_rect(meter, Color(1,1,1,0.2))
			draw_rect(Rect2(meter.position,Vector2(meter.size.x * charge,meter.size.y)),Color("fff0a8"))
	draw_string(ThemeDB.fallback_font, Vector2(frame.get_center().x - 180, frame.end.y - 160),
		tomato_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("fff0a8"))


func _draw_player() -> void:
	# `world` is the prototype, which has no class_name to type it by, so the
	# nodes come back as Variants and are cast here -- an untyped camera makes
	# `unproject_position` untyped too, and the file will not compile.
	var player := world.get("_player") as MayoPlayer
	if player == null or not is_instance_valid(player):
		return
	var origin := Vector2(
		frame.position.x + (frame.size.x - PLAYER_BAR.x) * 0.5,
		frame.position.y + frame.size.y - PLAYER_MARGIN - PLAYER_BAR.y - SAUCE_GAP - SAUCE_BAR.y)
	_draw_bar(Rect2(origin, PLAYER_BAR), player.health_fraction(), PLAYER_FULL, PLAYER_LOW, 2.0)

	# The tank, and a notch at the half mark the squirt-length curve bends on.
	# Without the bar the limit is invisible: a press cuts and there is nothing
	# on screen saying why, or how much shorter the next one will be.
	var tank := Rect2(Vector2(origin.x, origin.y + PLAYER_BAR.y + SAUCE_GAP), SAUCE_BAR)
	_draw_bar(tank, world.local_sauce(), SAUCE_FULL, SAUCE_LOW, 2.0)
	var midpoint: float = world.get("burst_midpoint")
	var notch_x := tank.position.x + tank.size.x * midpoint
	draw_line(Vector2(notch_x, tank.position.y - 2.0),
		Vector2(notch_x, tank.end.y + 2.0), EDGE, 1.0)

	# The two reliability thresholds, so the bar says where the bottle stops
	# being dependable rather than leaving it to be discovered mid-fight.
	for level in [world.get("steady_level"), world.get("spluttering_level")]:
		var at := tank.position.x + tank.size.x * float(level)
		draw_line(Vector2(at, tank.position.y), Vector2(at, tank.end.y),
			Color(0.0, 0.0, 0.0, 0.55), 1.0)

	# How much of the mayo on the floor is deep enough to put someone down. A
	# debug readout rather than a game one -- it walks the whole grid, so it is
	# asked a few times a second, not every frame -- and it is here because
	# "how slippery is this street getting" is otherwise invisible while tuning.
	var deep: float = world.get("debug_deep_fraction")
	if deep >= 0.0:
		var font_deep := ThemeDB.fallback_font
		var deep_text := "deep %.0f%%" % (deep * 100.0)
		var deep_at := Vector2(tank.position.x - 8.0
			- font_deep.get_string_size(deep_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13).x,
			tank.end.y - 1.0)
		draw_string(font_deep, deep_at + Vector2(1.0, 1.0), deep_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color(0.0, 0.0, 0.0, 0.7))
		draw_string(font_deep, deep_at, deep_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13,
			Color("e8cf4a"))

	# The band, and how many seconds of delivery are left in it. Secondary to
	# the bottle in the player's hand, which is what everyone else reads.
	var level: float = world.local_sauce()
	var stage: int = world.sauce_stage_of(level)
	var label: String = ["", "불안정", "바닥"][clampi(stage, 0, 2)]
	if label != "":
		var font := ThemeDB.fallback_font
		var text := "%s  %.1fs" % [label, world.sauce_seconds_left(level)]
		var at := Vector2(tank.end.x + 8.0, tank.end.y - 1.0)
		draw_string(font, at + Vector2(1.0, 1.0), text, HORIZONTAL_ALIGNMENT_LEFT,
			-1.0, 13, Color(0.0, 0.0, 0.0, 0.7))
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13,
			SAUCE_LOW if stage == 2 else SAUCE_FULL)


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
	var widest := 0.0
	for line in lines:
		widest = maxf(widest,
			font.get_string_size(line + PROMPT_HELD, HORIZONTAL_ALIGNMENT_LEFT,
				-1.0, PROMPT_SIZE).x)
	var top := frame.position.y + frame.size.y - PROMPT_LIFT \
		- PROMPT_LINE_GAP * float(lines.size() - 1)
	for index in lines.size():
		var line: String = lines[index]
		var colour := PROMPT_COLOR
		if index < PROMPT_LINES.size() and index == held:
			line += PROMPT_HELD
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
	draw_style_box(_icon_box(Color(0.85,0.94,1,0.5)),body)
	draw_style_box(_icon_box(fill),Rect2(at+Vector2(-7,0),Vector2(14,15)))
	draw_rect(Rect2(at+Vector2(-7,-14),Vector2(14,6)), Color("f3d052"))
	draw_colored_polygon(PackedVector2Array([at+Vector2(-3,-14),at+Vector2(3,-14),at+Vector2(1,-22)]),Color("fff3bf"))
	draw_line(at+Vector2(-6,-6),at+Vector2(-6,12),Color(1,1,1,0.8),2,true)


func _icon_box(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(5)
	return style


func _draw_pickup_hint() -> void:
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
