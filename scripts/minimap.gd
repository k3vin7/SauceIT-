class_name Minimap
extends Control

## The street map in the top-right corner, scrolling under the player.
##
## The streets are baked into a texture once, one pixel per lattice cell, and
## every frame draws a window of it centred on where the player is standing.
## Drawing the cells themselves would be a couple of thousand `draw_rect` calls
## a frame for a picture that never changes; the only things that actually move
## are the handful of markers on top.
##
## North is up rather than the map turning with the player. This is a street map
## of a real place with named streets running north-south and east-west, and a
## map that spins loses that -- which way the promenade runs stops being a fact
## you can learn. The wedge on the player's dot carries which way they are
## facing instead.

const SIZE := 190.0
const MARGIN := 16.0
## How much street to show around the player, in lattice cells. Eighteen is
## about 41 m: far enough to see the next junction and the stalls on the way to
## it, close enough that a single stall is still a distinct mark.
const VIEW_CELLS := 18.0

const BACKING := Color(0.04, 0.05, 0.06, 0.82)
const EDGE := Color(0.86, 0.90, 0.94, 0.45)
const STREET := Color(0.34, 0.38, 0.43, 1.0)
const STALL := Color("3fc3d4")
const ENEMY := Color("b06be0")
const LANDMARK := Color("f0a500")
const PLAYER := Color("e8382c")

var world: Node3D
var frame := Rect2()

var _texture: ImageTexture
## Lattice cell that image pixel (0, 0) holds.
var _image_origin := Vector2i.ZERO
var _stall_cells := PackedVector2Array()
var _landmark_cells := PackedVector2Array()


func _ready() -> void:
	name = "Minimap"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Cells, not a smear: the streets are a pixel each and the window is drawn
	# at about five pixels to the cell, so anything but nearest is mush.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## Bakes the street picture and the marker positions. Called once, after the
## world is built, because it reads the map's own cell set.
func build() -> void:
	var bounds := StreetMap.bounds()
	# Padded by a full window so the region drawn each frame is always inside
	# the image, whatever corner of the map the player walks into. Without it
	# the edges of the map would sample outside the texture.
	var pad := int(ceil(VIEW_CELLS)) + 2
	_image_origin = bounds.position - Vector2i(pad, pad)
	var width := bounds.size.x + pad * 2
	var height := bounds.size.y + pad * 2

	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	for cell in StreetMap.floor_cells():
		var at: Vector2i = cell - _image_origin
		if at.x >= 0 and at.y >= 0 and at.x < width and at.y < height:
			image.set_pixel(at.x, at.y, STREET)
	_texture = ImageTexture.create_from_image(image)

	# The markers never move, so their cells are worked out here rather than by
	# rebuilding the stall list -- which walks the whole map -- every frame.
	_stall_cells = PackedVector2Array()
	for stall in StreetMap.stall_boxes():
		_stall_cells.push_back(_cell_of(stall["position"]))
	_landmark_cells = PackedVector2Array([
		_cell_of(StreetMap.stage_position()),
		_cell_of(StreetMap.tower_position()),
	])


func set_frame(new_frame: Rect2) -> void:
	frame = new_frame
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if world == null or _texture == null or frame.size.x <= 0.0:
		return
	var player := world.get("_player") as MayoPlayer
	if player == null or not is_instance_valid(player):
		return

	var box := Rect2(
		Vector2(frame.position.x + frame.size.x - SIZE - MARGIN, frame.position.y + MARGIN),
		Vector2(SIZE, SIZE))
	draw_rect(box, BACKING, true)

	var per_cell := box.size.x / (VIEW_CELLS * 2.0)
	var centre := _cell_of(player.global_position)
	var region := Rect2(
		centre - Vector2(VIEW_CELLS, VIEW_CELLS) - Vector2(_image_origin),
		Vector2(VIEW_CELLS, VIEW_CELLS) * 2.0)
	draw_texture_rect_region(_texture, box, region)

	# Stalls, which are also where the sauce comes from, so they are the thing
	# most worth finding on it.
	var mark := maxf(per_cell * 0.9, 2.0)
	for cell in _stall_cells:
		_draw_mark(box, centre, per_cell, cell, mark, STALL)
	for cell in _landmark_cells:
		_draw_mark(box, centre, per_cell, cell, mark * 1.4, LANDMARK)

	var count: int = world.enemy_count()
	for index in count:
		var enemy := world.enemy_at(index) as MayoEnemy
		if enemy == null or not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		_draw_mark(box, centre, per_cell, _cell_of(enemy.global_position), mark * 1.2, ENEMY)

	# The player, always dead centre -- the map moves, they do not.
	var middle := box.get_center()
	# A wedge for where they are looking, since the map itself does not turn.
	var facing := -player.global_transform.basis.z
	var heading := Vector2(facing.x, facing.z).normalized()
	if heading.length_squared() > 0.001:
		var side := Vector2(-heading.y, heading.x)
		draw_colored_polygon(PackedVector2Array([
			middle + heading * (mark * 3.4),
			middle + side * (mark * 1.5),
			middle - side * (mark * 1.5),
		]), Color(PLAYER.r, PLAYER.g, PLAYER.b, 0.45))
	draw_circle(middle, maxf(mark * 1.3, 3.0), PLAYER)

	draw_rect(box, EDGE, false, 2.0)


func _draw_mark(box: Rect2, centre: Vector2, per_cell: float, cell: Vector2,
		size: float, color: Color) -> void:
	var offset := (cell - centre) * per_cell
	# Off the window: nothing is drawn rather than clamped to the rim, because a
	# mark pinned to the edge reads as a stall that is actually there.
	if absf(offset.x) > box.size.x * 0.5 or absf(offset.y) > box.size.y * 0.5:
		return
	var at := box.get_center() + offset
	draw_rect(Rect2(at - Vector2(size, size) * 0.5, Vector2(size, size)), color, true)


## World position to lattice cell, keeping the fraction: the map has to slide
## under the player rather than jump a cell at a time.
func _cell_of(world_position: Vector3) -> Vector2:
	return Vector2(
		world_position.x / StreetMap.CELL + float(StreetMap.ORIGIN_CELL.x),
		world_position.z / StreetMap.CELL + float(StreetMap.ORIGIN_CELL.y))
