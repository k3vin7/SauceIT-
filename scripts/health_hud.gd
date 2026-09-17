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
const ENEMY_BAR := Vector2(120.0, 10.0)
## How far above the enemy's own top the bar floats, in metres.
const ENEMY_LIFT := 0.9
## Past this the bar would be a smear a few pixels wide, and a cluster of them
## reads as noise on the horizon.
const ENEMY_DRAW_RANGE := 120.0

const BACKING := Color(0.04, 0.05, 0.06, 0.78)
const EDGE := Color(0.86, 0.90, 0.94, 0.5)
const PLAYER_FULL := Color("6fd38a")
const PLAYER_LOW := Color("d4564a")
const ENEMY_FULL := Color("e2683c")
const ENEMY_LOW := Color("7a2a20")
## Below this fraction the bar has gone fully to its low colour.
const LOW_AT := 0.35

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


func _draw_player() -> void:
	# `world` is the prototype, which has no class_name to type it by, so the
	# nodes come back as Variants and are cast here -- an untyped camera makes
	# `unproject_position` untyped too, and the file will not compile.
	var player := world.get("_player") as MayoPlayer
	if player == null or not is_instance_valid(player):
		return
	var origin := Vector2(
		frame.position.x + (frame.size.x - PLAYER_BAR.x) * 0.5,
		frame.position.y + frame.size.y - PLAYER_MARGIN - PLAYER_BAR.y)
	_draw_bar(Rect2(origin, PLAYER_BAR), player.health_fraction(), PLAYER_FULL, PLAYER_LOW, 2.0)


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
	if camera.global_position.distance_to(enemy.global_position) > ENEMY_DRAW_RANGE:
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
