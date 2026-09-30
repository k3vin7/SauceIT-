class_name MayoTutorialHud
extends Control

## Everything the tutorial puts on screen: the doctor's subtitles, the one-line
## objective for the stage you are in, an arrow for a threat that is behind you,
## and a marker over the stall you have been sent to.
##
## Drawn here rather than as 3D signage for the same reason `HealthHud` is: a
## sprite in the world takes sauce, gets hidden behind a stall and turns edge-on
## with whatever it is attached to, all of which are wrong for a caption. It also
## draws off the view frame rather than the window, so nothing lands under the
## letterbox.
##
## **Placeholder presentation.** The captions stand in for the doctor's voice
## lines and the marker is a drawn diamond rather than authored signage; both are
## meant to be replaced, and everything about how they look lives in the block of
## constants below so that swap is a local one.

# --- subtitles --------------------------------------------------------------
const SUBTITLE_SIZE := 22
const SUBTITLE_MARGIN := 118.0
const SUBTITLE_MAX_WIDTH := 0.72
const SUBTITLE_COLOR := Color("fdf6e3")
const SUBTITLE_SHADOW := Color(0.0, 0.0, 0.0, 0.85)
const SUBTITLE_BACKING := Color(0.03, 0.04, 0.05, 0.62)
const SUBTITLE_PAD := Vector2(16.0, 9.0)
## The doctor's name tag, so a caption reads as somebody talking rather than as
## system text.
const SPEAKER_SIZE := 14
const SPEAKER_COLOR := Color("8fd0ff")
## How long a line spends fading out once its time is up.
const SUBTITLE_FADE := 0.35

# --- objective --------------------------------------------------------------
const OBJECTIVE_SIZE := 17
const OBJECTIVE_MARGIN := 24.0
const OBJECTIVE_COLOR := Color("ffd98a")
const OBJECTIVE_SHADOW := Color(0.0, 0.0, 0.0, 0.8)
const OBJECTIVE_BULLET := Color("ffd98a")

# --- the "it is behind you" arrow -------------------------------------------
const ARROW_RADIUS := 152.0
## Big on purpose. At 26 px with a thin outline it was invisible against the very
## thing it is warning you about -- a street covered in bright yellow mayo -- which
## is precisely when it has to read.
const ARROW_SIZE := 44.0
const ARROW_COLOR := Color("ff4530")
const ARROW_EDGE := Color(0.0, 0.0, 0.0, 0.85)
const ARROW_OUTLINE := 4.0
## A word under it, because an arrow alone is ambiguous about whether it means
## "turn this way" or "something is over there".
const ARROW_LABEL := "뒤!"
const ARROW_LABEL_SIZE := 20
## How fast it pulses, in cycles a second.
const ARROW_PULSE_HZ := 2.2
## Only drawn once the threat is more than this far off the centre of the screen;
## something dead ahead needs no arrow.
const ARROW_MIN_ANGLE := deg_to_rad(28.0)

# --- the stall marker -------------------------------------------------------
const MARKER_SIZE := 15.0
## The default; the tutorial picks the actual tint per errand -- see
## `MayoTutorial.marker_color`.
const MARKER_COLOR := Color("8fe38f")
const MARKER_EDGE := Color(0.0, 0.0, 0.0, 0.65)
const MARKER_LABEL_SIZE := 15
const MARKER_LIFT := 26.0
const MARKER_BOB := 5.0
const MARKER_BOB_HZ := 1.1
## Past this the diamond is a few pixels of noise on the horizon.
const MARKER_RANGE := 160.0

var world: Node3D
var tutorial: MayoTutorial
var frame := Rect2()

var _clock := 0.0


func _ready() -> void:
	name = "TutorialHud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func set_frame(new_frame: Rect2) -> void:
	frame = new_frame
	queue_redraw()


func _process(delta: float) -> void:
	_clock += delta
	# The arrow tracks the camera and the marker tracks the player, so there is
	# nothing to be gained by trying to redraw only on a change.
	queue_redraw()


func _draw() -> void:
	if world == null or tutorial == null or frame.size.x <= 0.0:
		return
	if not tutorial.is_running():
		return
	_draw_marker()
	_draw_arrow()
	_draw_objective()
	_draw_subtitle()


# ---------------------------------------------------------------------------
# Subtitles
# ---------------------------------------------------------------------------

func _draw_subtitle() -> void:
	var line: String = tutorial.current_line()
	if line.is_empty():
		return
	var font := ThemeDB.fallback_font
	var alpha: float = tutorial.current_line_alpha()
	if alpha <= 0.01:
		return

	# Wrapped by hand into the view's own width, because the caption is drawn
	# rather than laid out: a long line would otherwise run off the letterbox.
	var limit: float = frame.size.x * SUBTITLE_MAX_WIDTH
	var rows := _wrap(font, line, SUBTITLE_SIZE, limit)
	var row_height: float = font.get_height(SUBTITLE_SIZE) + 4.0
	var widest := 0.0
	for row in rows:
		widest = maxf(widest,
			font.get_string_size(row, HORIZONTAL_ALIGNMENT_LEFT, -1.0, SUBTITLE_SIZE).x)

	var block_height: float = row_height * float(rows.size())
	var centre_x: float = frame.position.x + frame.size.x * 0.5
	var bottom: float = frame.position.y + frame.size.y - SUBTITLE_MARGIN
	var top: float = bottom - block_height

	# A panel behind the text: the street is pale mayo and cream captions vanish
	# into it without one.
	var backing := Rect2(
		Vector2(centre_x - widest * 0.5 - SUBTITLE_PAD.x,
			top - SUBTITLE_PAD.y - float(SPEAKER_SIZE) - 2.0),
		Vector2(widest + SUBTITLE_PAD.x * 2.0,
			block_height + SUBTITLE_PAD.y * 2.0 + float(SPEAKER_SIZE) + 2.0))
	draw_rect(backing, Color(SUBTITLE_BACKING.r, SUBTITLE_BACKING.g,
		SUBTITLE_BACKING.b, SUBTITLE_BACKING.a * alpha), true)

	var speaker_at := Vector2(backing.position.x + SUBTITLE_PAD.x,
		backing.position.y + SUBTITLE_PAD.y + float(SPEAKER_SIZE) - 2.0)
	draw_string(font, speaker_at, tutorial.current_speaker(), HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		SPEAKER_SIZE, Color(SPEAKER_COLOR.r, SPEAKER_COLOR.g, SPEAKER_COLOR.b, alpha))

	var y: float = top + font.get_ascent(SUBTITLE_SIZE)
	for row in rows:
		var width: float = font.get_string_size(row, HORIZONTAL_ALIGNMENT_LEFT,
			-1.0, SUBTITLE_SIZE).x
		var at := Vector2(centre_x - width * 0.5, y)
		draw_string(font, at + Vector2(1.0, 1.0), row, HORIZONTAL_ALIGNMENT_LEFT,
			-1.0, SUBTITLE_SIZE,
			Color(SUBTITLE_SHADOW.r, SUBTITLE_SHADOW.g, SUBTITLE_SHADOW.b,
				SUBTITLE_SHADOW.a * alpha))
		draw_string(font, at, row, HORIZONTAL_ALIGNMENT_LEFT, -1.0, SUBTITLE_SIZE,
			Color(SUBTITLE_COLOR.r, SUBTITLE_COLOR.g, SUBTITLE_COLOR.b, alpha))
		y += row_height


## Greedy wrap on spaces, falling back to the whole line when a single word is
## longer than the limit -- Korean captions often have very few spaces in them,
## and a character-level wrap would break words mid-syllable-cluster.
func _wrap(font: Font, line: String, size: int, limit: float) -> PackedStringArray:
	var rows := PackedStringArray()
	if font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x <= limit:
		rows.push_back(line)
		return rows
	var current := ""
	for word in line.split(" ", false):
		var candidate: String = word if current.is_empty() else current + " " + word
		if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x > limit \
				and not current.is_empty():
			rows.push_back(current)
			current = word
		else:
			current = candidate
	if not current.is_empty():
		rows.push_back(current)
	return rows


# ---------------------------------------------------------------------------
# Objective
# ---------------------------------------------------------------------------

## One line saying what this stage wants, taken from the stage itself rather than
## from a message. That is what lets somebody who joined halfway through know
## what they are supposed to be doing: they are sent the stage, and the stage is
## the objective.
func _draw_objective() -> void:
	var text: String = tutorial.objective_text()
	if text.is_empty():
		return
	var font := ThemeDB.fallback_font
	var at := Vector2(frame.position.x + OBJECTIVE_MARGIN + 14.0,
		frame.position.y + OBJECTIVE_MARGIN + float(OBJECTIVE_SIZE))
	draw_circle(Vector2(at.x - 10.0, at.y - float(OBJECTIVE_SIZE) * 0.35), 3.5,
		OBJECTIVE_BULLET)
	draw_string(font, at + Vector2(1.0, 1.0), text, HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, OBJECTIVE_SIZE, OBJECTIVE_SHADOW)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, OBJECTIVE_SIZE,
		OBJECTIVE_COLOR)


# ---------------------------------------------------------------------------
# The threat behind you
# ---------------------------------------------------------------------------

## An arrow swung round the middle of the screen, pointing the way you have to
## turn to see the thing that is coming. This is the whole of "look behind you":
## the camera is never taken off the player, because having the view yanked round
## is worse than being told to turn it.
func _draw_arrow() -> void:
	var at: Vector3 = tutorial.threat_position()
	if at == Vector3.INF:
		return
	var camera := world.get("_camera") as Camera3D
	var player := world.get("_player") as MayoPlayer
	if camera == null or not is_instance_valid(camera):
		return
	if player == null or not is_instance_valid(player):
		return

	# Worked out in the camera's own space: +z is behind it, so a threat with a
	# positive local z is one the player cannot see, and the x/z angle is exactly
	# how far they have to turn.
	var local: Vector3 = camera.global_transform.affine_inverse() * at
	var angle := atan2(local.x, -local.z)
	if absf(angle) < ARROW_MIN_ANGLE:
		return

	var centre := frame.position + frame.size * 0.5
	# Screen space: x right, y down, and the arrow sits on a circle round the
	# crosshair at the bearing the player has to turn through.
	var direction := Vector2(sin(angle), -cos(angle))
	var tip := centre + direction * ARROW_RADIUS
	var side := Vector2(-direction.y, direction.x)
	var pulse: float = 0.78 + 0.22 * sin(_clock * TAU * ARROW_PULSE_HZ)
	var points := PackedVector2Array([
		tip + direction * ARROW_SIZE * 0.6,
		tip - direction * ARROW_SIZE * 0.4 + side * ARROW_SIZE * 0.5,
		tip - direction * ARROW_SIZE * 0.4 - side * ARROW_SIZE * 0.5,
	])
	var outline := PackedVector2Array([points[0], points[1], points[2], points[0]])
	# Dark first and wide, so the shape survives being drawn over bright mayo.
	draw_polyline(outline, ARROW_EDGE, ARROW_OUTLINE)
	draw_colored_polygon(points,
		Color(ARROW_COLOR.r, ARROW_COLOR.g, ARROW_COLOR.b, pulse))
	draw_polyline(outline, ARROW_EDGE, 1.5)

	# And a word, so it cannot be read as "go this way".
	var font := ThemeDB.fallback_font
	var width: float = font.get_string_size(ARROW_LABEL, HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, ARROW_LABEL_SIZE).x
	var label_at := tip + direction * (ARROW_SIZE * 0.6 + float(ARROW_LABEL_SIZE))
	label_at -= Vector2(width * 0.5, 0.0)
	draw_string(font, label_at + Vector2(2.0, 2.0), ARROW_LABEL,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, ARROW_LABEL_SIZE, ARROW_EDGE)
	draw_string(font, label_at, ARROW_LABEL, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		ARROW_LABEL_SIZE, Color(ARROW_COLOR.r, ARROW_COLOR.g, ARROW_COLOR.b, pulse))


# ---------------------------------------------------------------------------
# The stall you were sent to
# ---------------------------------------------------------------------------

func _draw_marker() -> void:
	var at: Vector3 = tutorial.marker_position()
	if at == Vector3.INF:
		return
	var camera := world.get("_camera") as Camera3D
	if camera == null or not is_instance_valid(camera):
		return
	var distance: float = camera.global_position.distance_to(at)
	if distance > MARKER_RANGE:
		return

	var local: Vector3 = camera.global_transform.affine_inverse() * at
	var behind := local.z >= -0.001
	var screen := frame.get_center() if behind else camera.unproject_position(at)
	var margin := minf(95.0, minf(frame.size.x, frame.size.y) * 0.2)
	var outside := behind or not frame.grow(-margin).has_point(screen)
	if outside:
		# Keep an objective discoverable when the player is looking away from
		# the counter. This points without taking control of their camera.
		var direction := Vector2(local.x, -local.y)
		if behind:
			direction = Vector2(1.0 if local.x >= 0 else -1.0, 0.0)
		if direction.length_squared() < 0.01:
			direction = Vector2.RIGHT
		var half := (frame.size * 0.5 - Vector2(110.0, 115.0)).max(frame.size * 0.2)
		var reach := minf(half.x / maxf(absf(direction.x), 0.001),
			half.y / maxf(absf(direction.y), 0.001))
		screen = frame.get_center() + direction * reach
	var tint: Color = tutorial.marker_color()
	var bob: float = sin(_clock * TAU * MARKER_BOB_HZ) * MARKER_BOB
	var centre := screen - Vector2(0.0, MARKER_LIFT + bob)
	var diamond := PackedVector2Array([
		centre + Vector2(0.0, -MARKER_SIZE),
		centre + Vector2(MARKER_SIZE * 0.72, 0.0),
		centre + Vector2(0.0, MARKER_SIZE),
		centre + Vector2(-MARKER_SIZE * 0.72, 0.0),
	])
	draw_colored_polygon(diamond, tint)
	draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2],
		diamond[3], diamond[0]]), MARKER_EDGE, 2.0)

	var label: String = tutorial.marker_label()
	if outside:
		label += " →" if screen.x > frame.get_center().x else " ←"
	if label.is_empty():
		return
	var font := ThemeDB.fallback_font
	var width: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, MARKER_LABEL_SIZE).x
	var label_at := centre + Vector2(-width * 0.5, -MARKER_SIZE - 6.0)
	# On a plate: the stalls carry painted signs of their own, and a green caption
	# laid straight over a pink awning is not readable from across the street.
	draw_rect(Rect2(label_at - Vector2(6.0, float(MARKER_LABEL_SIZE)),
		Vector2(width + 12.0, float(MARKER_LABEL_SIZE) + 8.0)),
		Color(0.03, 0.04, 0.05, 0.7), true)
	draw_string(font, label_at + Vector2(1.0, 1.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, MARKER_LABEL_SIZE, MARKER_EDGE)
	draw_string(font, label_at, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		MARKER_LABEL_SIZE, tint)
