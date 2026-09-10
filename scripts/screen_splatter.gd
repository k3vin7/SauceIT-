class_name ScreenSplatter
extends Control

## Sauce on the camera itself: what you see when someone hits you.
##
## One blob per splat the server marks on this player's body, so the screen and
## the stain on the capsule are the same event -- there is no second hit test,
## and no extra traffic. It is drawn, never simulated: blobs sit where they
## landed until they are wiped.
##
## Deliberately not on a timer. The whole point of the wipe key is that being
## covered is a state you have to do something about, and a blob that faded on
## its own would make pressing R pointless.

class Blob:
	var position := Vector2.ZERO
	var radius := 60.0
	## Satellite offsets and sizes, as fractions of the radius, so a blob reads
	## as a splat rather than a circle.
	var satellites: Array[Vector3] = []

## Past this many the screen is a wall of mayo and more adds nothing but cost;
## the oldest goes instead.
const MAX_BLOBS := 18
## How far off centre a hit from the side is allowed to sit, as a fraction of
## the screen. Kept inside the edge so a blob always reads as being on the
## glass rather than half-missing.
const EDGE_MARGIN := 0.12

@export var mayo_color := Color("fff0a8")

var _blobs: Array[Blob] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The sauce is on the glass, not on anything the player can click.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.seed = 0x53504c54


## `view_direction` is where the hit came from in the camera's own space: -Z is
## straight ahead. A hit from behind lands at the edge on the side it came from
## rather than being dropped, so you can tell which way to turn.
func add_splat(view_direction: Vector3) -> void:
	var blob := Blob.new()
	blob.position = _to_screen(view_direction)
	blob.radius = _rng.randf_range(0.045, 0.10) * minf(size.x, size.y)
	var count := _rng.randi_range(3, 6)
	for _i in count:
		var angle := _rng.randf_range(0.0, TAU)
		var distance := _rng.randf_range(0.35, 0.95)
		blob.satellites.push_back(Vector3(
			cos(angle) * distance, sin(angle) * distance,
			_rng.randf_range(0.28, 0.62)))
	_blobs.push_back(blob)
	while _blobs.size() > MAX_BLOBS:
		_blobs.pop_front()
	queue_redraw()


func wipe() -> void:
	if _blobs.is_empty():
		return
	_blobs.clear()
	queue_redraw()


func blob_count() -> int:
	return _blobs.size()


## Roughly how much of the screen is covered, for the checks. Overlap is
## counted twice, so it is an upper bound rather than a measurement.
func coverage() -> float:
	var covered := 0.0
	for blob in _blobs:
		covered += PI * blob.radius * blob.radius
		for satellite in blob.satellites:
			var radius: float = blob.radius * satellite.z
			covered += PI * radius * radius
	return covered / maxf(size.x * size.y, 1.0)


func _draw() -> void:
	for blob in _blobs:
		draw_circle(blob.position, blob.radius, mayo_color)
		for satellite in blob.satellites:
			draw_circle(
				blob.position + Vector2(satellite.x, satellite.y) * blob.radius,
				blob.radius * satellite.z, mayo_color)


## Camera-space direction -> a point on the screen. This is a hand-rolled
## projection rather than Camera3D.unproject_position because the hit is on the
## player's own body, a hand's width from the lens: unprojecting a point that
## close throws it far off screen for any hit that is not dead ahead.
func _to_screen(view_direction: Vector3) -> Vector2:
	var centre := size * 0.5
	var margin := minf(size.x, size.y) * EDGE_MARGIN
	var direction := view_direction.normalized()
	if direction.length_squared() < 0.5:
		return centre
	if direction.z < -0.1:
		# In front: a plain perspective divide, then held inside the frame.
		var scale := centre.y / -direction.z
		var point := centre + Vector2(direction.x, -direction.y) * scale
		return Vector2(
			clampf(point.x, margin, size.x - margin),
			clampf(point.y, margin, size.y - margin))
	# Level with the lens or behind it: pin it to the side it came from.
	var sideways := Vector2(direction.x, -direction.y)
	if sideways.length_squared() < 0.0001:
		return centre
	sideways = sideways.normalized()
	return centre + sideways * Vector2(centre.x - margin, centre.y - margin)
