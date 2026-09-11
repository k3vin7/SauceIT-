extends Node3D

const StreamVisualScript := preload("res://scripts/stream_visual.gd")
const FloorScript := preload("res://scripts/floor_contamination.gd")
const PlayerScript := preload("res://scripts/player_controller.gd")
const WallScript := preload("res://scripts/contaminable_object.gd")
const CrosshairScript := preload("res://scripts/crosshair.gd")
const NetPanelScript := preload("res://scripts/net_panel.gd")
const BodyContaminationScript := preload("res://scripts/body_contamination.gd")
const VisorScript := preload("res://scripts/visor_contamination.gd")
const VisorOverlayScript := preload("res://scripts/visor_overlay.gd")

# Splat batch entry kinds. Four ints per splat: kind, target, cell x, cell y.
# What `target` means is the kind's business -- a wall packs its index and the
# face it was hit on, a body carries the peer id whose body it is.
const SPLAT_FLOOR := 0
const SPLAT_WALL := 1
const SPLAT_BODY := 2
## Sauce on a player's glasses, and the wipe that takes it off again. The wipe
## is a grid change like any other, so it travels the same way the splats do.
const SPLAT_VISOR := 3
const SPLAT_VISOR_CLEAR := 4
## Ints per entry in a splat batch: kind, target, cell x, cell y.
const SPLAT_STRIDE := 4
const FACES_PER_WALL := 6

enum PointPhase { AIR, WALL_FIXED, LANDING }

class MayoPoint:
	var position := Vector3.ZERO
	var last_collision_position := Vector3.ZERO
	var velocity := Vector3.ZERO
	var launch_direction := Vector3.FORWARD
	var age := 0.0
	var distance_travelled := 0.0
	var powered := true
	var phase := PointPhase.AIR
	var landing_age := 0.0
	var fixed_age := 0.0
	var collision_slot := 0
	var burst_index := 0

class RibbonPoint:
	var position := Vector3.ZERO
	var opacity := 1.0
	var width_scale := 1.0

## Everything that belongs to one player rather than to the world: their body,
## their aim, and their own strand. Offline there is exactly one, the local
## player; in a session there is one per peer, and every peer simulates all of
## them. Only the strand's landings are authoritative, and only on the server.
class Shooter:
	var peer_id := 1
	var is_local := false
	var player: MayoPlayer
	var body_mesh: MeshInstance3D
	var aim_pivot: Node3D
	var weapon: Node3D
	var muzzle: Marker3D
	var points: Array[MayoPoint] = []
	var emit_distance := 0.0
	var attack_direction := Vector3.FORWARD
	var burst_index := 0
	var was_firing := false
	var firing := false
	var next_collision_slot := 0
	var aim_yaw := 0.0
	var aim_pitch := 0.0
	var rng := RandomNumberGenerator.new()
	var air_visual: StreamVisual
	var wall_visual: StreamVisual
	var landing_visual: StreamVisual
	var shadow_visual: StreamVisual


class MayoDroplet:
	var active := false
	var position := Vector3.ZERO
	var radius := 0.014
	var expires_at := 0.0

@export_group("Mayo Stream — Reference Values")
@export_range(0.2, 6.0, 0.01, "suffix:m") var stream_range := 2.94
@export_range(0.5, 15.0, 0.1, "suffix:m/s") var extend_speed := 7.0
## How far apart the strand's points are, which is also how finely it samples
## what it hits: a sweep across someone's face only marks them where a point
## lands, so at 0.09 a quick flick left three dots rather than a line.
@export_range(0.025, 0.25, 0.005, "suffix:m") var point_spacing := 0.045
@export_range(0.02, 0.2, 0.001, "suffix:m") var strand_thickness := 0.093
@export_range(0.0, 0.5, 0.01, "suffix:m") var muzzle_forward_offset := 0.15
@export_range(0.02, 1.5, 0.01, "suffix:s") var point_time_lifetime := 0.42
@export var use_time_lifetime := true
@export var use_distance_lifetime := true
@export_range(0.0, 30.0, 0.1, "suffix:m/s²") var gravity_acceleration := 9.8

@export_group("Emission Shape")
@export_range(0.0, 0.05, 0.001, "suffix:m") var lateral_position_jitter := 0.009
@export_range(0.0, 0.08, 0.001, "suffix:rad") var yaw_angle_jitter := 0.018
@export_range(0.0, 0.5, 0.01) var speed_magnitude_jitter := 0.10
@export_range(0.0, 1.0, 0.01) var inherited_player_velocity := 0.22
## Scales with the density above: at 0.045 a strand carries twice the points,
## and a cap left at 192 would cut it short instead of letting it run its range.
@export_range(32, 768, 1) var maximum_point_count := 384
## Adjacent points further apart than this many point_spacings are treated as
## separate strands: the ribbon breaks there and no spacing correction is applied.
@export_range(1.5, 12.0, 0.1) var strand_break_spacing := 6.0

@export_group("Collision Budget")
@export_range(1, 4, 1) var raycast_frame_stride := 1
@export_range(0.0, 0.03, 0.001, "suffix:m") var raycast_min_accumulated_motion := 0.004
@export_range(0.2, 4.0, 0.1, "suffix:s") var wall_fixed_hold_time := 1.2
## How far a point has to have travelled before it can hit the player who fired
## it. The muzzle sits inside its owner's own capsule, so a point leaving it
## would hit them immediately; past this it is clear of them and fair game, and
## sauce fired straight up, or walked into, comes back on you.
@export_range(0.0, 3.0, 0.05, "suffix:m") var self_hit_distance := 0.6

@export_group("Release Pressure")
@export_range(0.0, 1.0, 0.01) var release_pressure_loss := 0.55
@export_range(0.2, 6.0, 0.1) var release_pressure_curve := 1.6

@export_group("Inertial Bend")
@export_range(0.0, 1.0, 0.01) var front_follow := 0.12
@export_range(0.2, 4.0, 0.1) var follow_curve_power := 1.8
@export_range(1, 8, 1) var spacing_constraint_passes := 3

@export_group("Landing and Grid")
@export_range(0.05, 0.5, 0.01, "suffix:m") var grid_cell_size := 0.1
## Splat radius in metres. Converted to cells internally, so changing the
## cell size does not change how big a splat is.
@export_range(0.05, 1.5, 0.01, "suffix:m") var contamination_brush_radius := 0.4
## Bodies carry their own, much finer grid: the world brush is 0.4 m and a
## player is only 2 m around, so one world-sized splat would cover a fifth of
## the way round them.
@export_range(0.005, 0.2, 0.001, "suffix:m") var body_cell_size := 0.02
@export_range(0.01, 0.5, 0.005, "suffix:m") var body_brush_radius := 0.07
@export_range(0.05, 0.5, 0.01, "suffix:s") var landing_transition_time := 0.16
## Kept at what the droplet pool can hold for two players firing at once. See
## the note on POOL_SIZE before raising it.
@export_range(0.1, 2.0, 0.05, "suffix:s") var droplet_lifetime := 0.40
## Droplets thrown by one landing. The pool they come from is one per world, not
## one per player, so this is multiplied by every strand landing at once: at
## seven, two players firing filled all 512 slots and began overwriting droplets
## that were still alive.
@export_range(1, 16, 1) var droplets_per_landing := 4

@export_group("Aim")
@export_range(0.01, 1.0, 0.01, "suffix:°/px") var mouse_sensitivity := 0.12
@export_range(60.0, 89.0, 1.0, "suffix:°") var pitch_limit_degrees := 85.0

@export_group("Camera")
@export var start_in_first_person := true
@export_range(35.0, 90.0, 1.0, "suffix:°") var camera_fov := 74.0
@export_range(0.2, 2.0, 0.01, "suffix:m") var eye_height := 0.52
@export_range(-1.5, 1.5, 0.01, "suffix:m") var shoulder_offset_right := 0.55
@export_range(-1.0, 1.5, 0.01, "suffix:m") var shoulder_offset_up := 0.34
@export_range(0.5, 5.0, 0.05, "suffix:m") var shoulder_distance := 2.40
## Points nearer than this to the camera are dropped from the ribbon so the
## strand root does not fill the screen in first person. 0 disables it.
@export_range(0.0, 1.0, 0.01, "suffix:m") var strand_near_cull_distance := 0.34
## Going down is mostly a backwards pitch; the roll is a little asymmetry on top.
@export_range(0.0, 100.0, 1.0, "suffix:°") var fall_camera_roll_degrees := 14.0
@export_range(0.0, 90.0, 1.0, "suffix:°") var fall_camera_pitch_degrees := 80.0
@export_range(-60.0, 60.0, 1.0, "suffix:°") var fall_body_roll_degrees := 12.0
## How far the capsule and the view sway while catching their balance.
@export_range(0.0, 60.0, 1.0, "suffix:°") var stumble_body_roll_degrees := 17.0
@export_range(0.0, 30.0, 0.5, "suffix:°") var stumble_camera_roll_degrees := 7.0
@export_range(0.0, 20.0, 0.5, "suffix:°") var stumble_camera_pitch_degrees := 3.0
@export_range(0.05, 1.0, 0.01, "suffix:m") var fall_camera_height := 0.28

@export_group("Weapon Hold")
@export_range(-0.6, 0.6, 0.01, "suffix:m") var weapon_offset_right := 0.155
@export_range(-0.6, 0.3, 0.01, "suffix:m") var weapon_offset_up := -0.15
@export_range(0.1, 1.0, 0.01, "suffix:m") var weapon_offset_forward := 0.28
@export_range(0.02, 0.14, 0.005, "suffix:m") var bottle_radius := 0.052
@export_range(0.08, 0.5, 0.01, "suffix:m") var bottle_length := 0.20
## The strand is launched at the point the crosshair marks, this far down the
## camera forward axis, so an off-centre nozzle still fires through the centre.
@export_range(0.5, 8.0, 0.05, "suffix:m") var aim_convergence_distance := 2.2
@export var show_crosshair := true

var _local: Shooter
## peer id -> Shooter. Offline this holds the local player alone under id 1.
var _shooters: Dictionary = {}
var _net: MayoNet
var _net_panel: Control
var _input_enabled := true
## Splat centre cells found this frame, flushed to the peers at the end of it.
## Four ints each: kind, target, cell x, cell y. See MayoNet.apply_splats.
var _pending_splats := PackedInt32Array()
## Peers whose lenses the authority is currently wiping, so the clear can be
## broadcast on the frame the timer runs out.
var _wiping: Dictionary = {}
var _crosshair: Control
var _visor_overlay: VisorOverlay
var _hud_layer: CanvasLayer
var _mayo_material: Material
var _landing_material: Material
var _shadow_material: Material
var _camera: Camera3D
var _floor: FloorContamination
var _walls: Array[ContaminableObject] = []

# The single-player fields the checks and the rest of this file grew up with,
# now views onto the local player's Shooter. Nothing assigns through them.
var _points: Array[MayoPoint]:
	get: return _local.points
var _emit_distance: float:
	get: return _local.emit_distance
var _attack_direction: Vector3:
	get: return _local.attack_direction
var _rng: RandomNumberGenerator:
	get: return _local.rng
var _player: MayoPlayer:
	get: return _local.player
var _muzzle: Marker3D:
	get: return _local.muzzle
var _aim_pivot: Node3D:
	get: return _local.aim_pivot
var _body_mesh: MeshInstance3D:
	get: return _local.body_mesh
var _weapon: Node3D:
	get: return _local.weapon
var _air_visual: StreamVisual:
	get: return _local.air_visual
var _wall_visual: StreamVisual:
	get: return _local.wall_visual
var _landing_visual: StreamVisual:
	get: return _local.landing_visual
var _shadow_visual: StreamVisual:
	get: return _local.shadow_visual
var _burst_index: int:
	get: return _local.burst_index
var _was_firing: bool:
	get: return _local.was_firing
var _aim_yaw: float:
	get: return _local.aim_yaw
var _aim_pitch: float:
	get: return _local.aim_pitch
var _droplet_multimesh: MultiMesh
var _droplets: Array[MayoDroplet] = []
var _active_droplet_indices := PackedInt32Array()
var _droplet_buffer := PackedFloat32Array()
var _droplet_buffer_dirty := false
var _droplet_cursor := 0
var _first_person := true
var debug_input_override := false
var debug_input_move := Vector2.ZERO
var debug_input_run := false
var debug_input_firing := false
var debug_profile_enabled := false
var debug_profile_frames := 0
var debug_raycast_count := 0
var debug_max_points := 0
## Splats queued this run, and landings that threw droplets. Both are per-hit
## quantities, which is what makes them worth counting against point density.
var debug_splats := 0
var debug_droplet_spawns := 0
## Droplets replaced while still alive, and how much life they had left. A pool
## that is full is only a problem if this second number is not near zero.
var debug_droplet_overwrites := 0
var debug_droplet_overwritten_life := 0.0
var debug_timings_us := {
	"emit_follow": 0,
	"point_physics": 0,
	"constraint": 0,
	"ribbon_update": 0,
	"net_send": 0,
	"total": 0,
}


func _ready() -> void:
	_ensure_input_actions()
	_build_world()
	set_first_person(start_in_first_person)
	_capture_mouse()
	_floor.configure(grid_cell_size, contamination_brush_radius)
	for wall in _walls:
		wall.configure(grid_cell_size, contamination_brush_radius)
	_update_camera()


func _physics_process(delta: float) -> void:
	if _local == null:
		return
	var frame_started := Time.get_ticks_usec() if debug_profile_enabled else 0
	var step_started := frame_started
	_read_local_input()
	# Every peer simulates every strand off the aim it has for that shooter, so
	# nothing about the strand itself goes over the wire. Only the server's copy
	# is allowed to paint, and it broadcasts the cells it painted.
	for shooter in _shooters.values():
		_update_aim(shooter)
	if _is_authority():
		for shooter in _shooters.values():
			_update_slip(shooter)
	for shooter in _shooters.values():
		_advance_strand(shooter, delta)
	if debug_profile_enabled:
		debug_timings_us.emit_follow += Time.get_ticks_usec() - step_started
		step_started = Time.get_ticks_usec()

	for shooter in _shooters.values():
		_simulate_points(delta, shooter)
	_simulate_droplets(delta)
	if debug_profile_enabled:
		debug_timings_us.point_physics += Time.get_ticks_usec() - step_started
		step_started = Time.get_ticks_usec()
	for shooter in _shooters.values():
		if shooter.firing:
			_enforce_spacing_constraint(shooter)
	if debug_profile_enabled:
		debug_timings_us.constraint += Time.get_ticks_usec() - step_started
		step_started = Time.get_ticks_usec()
	for shooter in _shooters.values():
		_trim_safety_cap(shooter)
		_update_visuals(shooter)
	if debug_profile_enabled:
		debug_timings_us.ribbon_update += Time.get_ticks_usec() - step_started
		step_started = Time.get_ticks_usec()
	if _is_authority():
		_finish_wipes()
	if debug_profile_enabled:
		debug_splats += _pending_splats.size() / SPLAT_STRIDE
	if is_instance_valid(_net):
		_net.end_of_frame(_pending_splats)
	_pending_splats.clear()
	# Sending the frame's splats and player states is part of the frame, and was
	# being left out of it: the total used to be taken before this ran.
	if debug_profile_enabled:
		debug_timings_us.net_send += Time.get_ticks_usec() - step_started
		debug_timings_us.total += Time.get_ticks_usec() - frame_started
		debug_profile_frames += 1
		debug_max_points = maxi(debug_max_points, _points.size())


## Emission and the trigger edges, for one shooter. Split out of the frame loop
## so remote shooters go through exactly the same path as the local one.
func _advance_strand(shooter: Shooter, delta: float) -> void:
	if shooter.firing:
		if not shooter.was_firing:
			shooter.burst_index += 1
		_apply_inertial_follow(shooter.player.frame_movement, shooter)
		shooter.emit_distance += extend_speed * delta
		while shooter.emit_distance >= point_spacing:
			shooter.emit_distance -= point_spacing
			_emit_point(shooter)
	else:
		shooter.emit_distance = 0.0
		if shooter.was_firing:
			_apply_release_pressure_loss(shooter)
	shooter.was_firing = shooter.firing


## The local player's own keyboard and mouse. Their aim is applied immediately,
## never round-tripped, or the view would lag the mouse by the latency; the
## server still owns where the body ends up.
func _read_local_input() -> void:
	if _local == null:
		return
	var live := _input_enabled and not _local.player.is_incapacitated() \
		and not _local.player.is_wiping()
	_local.firing = live and _fire_held()
	if debug_input_override:
		# The checks have no keyboard, so the same keys reach the body and the
		# packet through here rather than through Input.
		_local.player.use_injected_input = true
		_local.player.input_move = debug_input_move
		_local.player.input_run = debug_input_run
	if not is_instance_valid(_net) or not _net.is_online():
		return
	if _net.is_server():
		return
	var move := Vector2.ZERO
	var run := false
	if debug_input_override:
		move = debug_input_move
		run = debug_input_run
	elif _input_enabled:
		move = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
		run = Input.is_action_pressed("run")
	_net.send_input(move, run, _local.firing, _local.aim_yaw, _local.aim_pitch)


func _fire_held() -> bool:
	if debug_input_override:
		return debug_input_firing
	return Input.is_action_pressed("fire_mayo")


## Stands in for the keyboard in the headless checks, the way debug_set_aim
## stands in for the mouse. The two-player harness uses it to hold whichever
## player is not being driven still.
func debug_set_input(move: Vector2, run: bool, firing: bool) -> void:
	debug_input_override = true
	debug_input_move = move
	debug_input_run = run
	debug_input_firing = firing


## Hands the body back to the real keyboard.
func debug_clear_input_override() -> void:
	debug_input_override = false
	debug_input_move = Vector2.ZERO
	debug_input_run = false
	debug_input_firing = false


## True when this peer decides slips and grid paint: the server, or offline,
## where a session of one is its own authority.
func _is_authority() -> bool:
	return not is_instance_valid(_net) or _net.is_server()


func _process(_delta: float) -> void:
	if _local == null:
		return
	_update_camera()
	for shooter in _shooters.values():
		_update_fallen_body(shooter)
		_update_visor(shooter)


## The capsule lies on its side while the player is down. A capsule is all the
## character model this step needs, so this is a single rotation.
## The lenses tipping up and back down, which is the part of a wipe that
## everyone else can see. Driven off the replicated timer, so it plays at the
## same moment on every screen.
func _update_visor(shooter: Shooter) -> void:
	if shooter.player.visor == null:
		return
	shooter.player.visor.set_wipe_progress(shooter.player.wipe_progress())


func _update_fallen_body(shooter: Shooter) -> void:
	if not is_instance_valid(shooter.body_mesh):
		return
	# Going over backwards, the feet skid forward and the capsule tips about its
	# local X: +90 degrees takes its top to +Z, behind the player. Pitching
	# forward is the same rotation mirrored, which puts the top out in front.
	var tilt := shooter.player.fall_tilt()
	shooter.body_mesh.rotation.x = deg_to_rad(90.0) * tilt * shooter.player.fall_direction
	# The stumble sways the capsule side to side before it goes over; the two
	# never overlap, since fall_tilt is 0 while stumbling.
	shooter.body_mesh.rotation.z = deg_to_rad(fall_body_roll_degrees) * tilt * shooter.player.fall_direction \
		+ deg_to_rad(stumble_body_roll_degrees) * shooter.player.stumble_wobble()


func _unhandled_input(event: InputEvent) -> void:
	if _local == null:
		return
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
		return
	if event.is_action_pressed("toggle_camera_mode"):
		set_first_person(not _first_person)
		return
	if event.is_action_pressed("toggle_network_panel"):
		set_network_panel_open(not _net_panel.visible)
		return
	if not _input_enabled:
		return
	if event.is_action_pressed("wipe_screen"):
		_request_wipe()
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		apply_look((event as InputEventMouseMotion).relative)


## Mouse-look. Both camera modes feed the same yaw/pitch, so aiming is
## identical in first and third person; only the camera placement differs.
func apply_look(relative: Vector2) -> void:
	var radians_per_pixel := deg_to_rad(mouse_sensitivity)
	_local.aim_yaw = wrapf(_local.aim_yaw - relative.x * radians_per_pixel, -PI, PI)
	var limit := deg_to_rad(pitch_limit_degrees)
	_local.aim_pitch = clampf(_local.aim_pitch - relative.y * radians_per_pixel, -limit, limit)


## Only the local player's own capsule is hidden in first person. Everyone
## else's stays visible in both modes -- that is the whole point of them.
func set_first_person(enabled: bool) -> void:
	_first_person = enabled
	if _local != null and is_instance_valid(_local.body_mesh):
		_local.body_mesh.visible = not enabled
	# You look through your own lenses, not at them: the mask reaches you as the
	# screen overlay instead. Everyone else's stay visible in both modes.
	if _local != null and _local.player.visor != null:
		_local.player.visor.visible = not enabled
	# The bottle is a first-person viewmodel held at eye height; in third person
	# it would sit inside the capsule, so it is hidden rather than mispositioned.
	if _local != null and is_instance_valid(_local.weapon):
		_local.weapon.visible = enabled
	_update_camera()


func _ensure_input_actions() -> void:
	# Registered in code so the toggle works without editing the input map.
	if InputMap.has_action("toggle_camera_mode"):
		return
	InputMap.add_action("toggle_camera_mode")
	var toggle := InputEventKey.new()
	toggle.physical_keycode = KEY_F1
	InputMap.action_add_event("toggle_camera_mode", toggle)
	if not InputMap.has_action("run"):
		InputMap.add_action("run")
		var run := InputEventKey.new()
		run.physical_keycode = KEY_SHIFT
		InputMap.action_add_event("run", run)
	if not InputMap.has_action("wipe_screen"):
		InputMap.add_action("wipe_screen")
		var wipe := InputEventKey.new()
		wipe.physical_keycode = KEY_R
		InputMap.action_add_event("wipe_screen", wipe)
	if not InputMap.has_action("toggle_network_panel"):
		InputMap.add_action("toggle_network_panel")
		var network := InputEventKey.new()
		network.physical_keycode = KEY_F2
		InputMap.action_add_event("toggle_network_panel", network)


func _capture_mouse() -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_world() -> void:
	_build_environment()

	_floor = FloorScript.new()
	_floor.name = "FloorContamination"
	_floor.floor_size = Vector2(12.0, 12.0)
	_floor.cell_size = grid_cell_size
	_floor.brush_radius = contamination_brush_radius
	add_child(_floor)

	# The default centre aim is left open for the ballistic-to-floor test. Aim to
	# the right-hand slab to validate wall attachment and trailing-point pressure.
	_create_wall("ImpactWall", Vector3(2.35, 1.1, -0.72), Vector3(1.65, 2.2, 0.18), Color("886b61"))
	_create_wall("LeftGuide", Vector3(-3.6, 0.75, 0.8), Vector3(0.16, 1.5, 4.0), Color("6b7b84"))
	_create_wall("RightBlock", Vector3(3.0, 0.7, 2.1), Vector3(0.9, 1.4, 0.9), Color("6b7b84"))

	_net = MayoNet.new()
	_net.name = "Net"
	add_child(_net)
	_net.bind(self)

	_local = _create_shooter(1, true)

	_camera = Camera3D.new()
	_camera.name = "ThirdPersonCamera"
	_camera.current = true
	_camera.fov = camera_fov
	_camera.near = 0.05
	add_child(_camera)

	var mayo_material := StandardMaterial3D.new()
	mayo_material.albedo_color = Color("fff0a8")
	mayo_material.roughness = 0.28
	mayo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mayo_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var landing_material := mayo_material.duplicate() as StandardMaterial3D
	landing_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	landing_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var shadow_material := StandardMaterial3D.new()
	shadow_material.albedo_color = Color(0.08, 0.07, 0.055, 0.18)
	shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	shadow_material.no_depth_test = false
	shadow_material.render_priority = -1

	_mayo_material = mayo_material
	_landing_material = landing_material
	_shadow_material = shadow_material
	_build_shooter_visuals(_local)
	_build_droplet_pool(mayo_material)
	_build_crosshair()
	_build_network_panel()


## The other player is a different colour, so it is obvious which capsule on
## screen is being watched fall over -- and, now, which one is covered in mayo.
func _body_color(is_local: bool) -> Color:
	return Color("33495b") if is_local else Color("7a4b3a")


## Spawn point for the nth player to join. Fixed by join order so both peers
## place everyone the same way.
func spawn_position_for(slot: int) -> Vector3:
	const SPAWNS := [Vector3(0.0, 0.64, 1.55), Vector3(1.35, 0.64, 2.6)]
	return SPAWNS[slot % SPAWNS.size()]


## Builds one player: capsule, aim pivot, bottle, and their own strand. Called
## for the local player at startup and for each peer as they join.
func create_avatar(peer_id: int, slot: int, is_local: bool) -> Shooter:
	if _shooters.has(peer_id):
		return _shooters[peer_id]
	var shooter := _create_shooter(peer_id, is_local, slot)
	if _mayo_material != null:
		_build_shooter_visuals(shooter)
	# Anyone but the player at this keyboard is driven by the packets they send.
	shooter.player.use_injected_input = not is_local
	# A client simulates no bodies at all, its own included: every one of them
	# is placed by the server. Set here rather than at each call site so no
	# ordering of the join messages can leave a body simulating itself.
	shooter.player.authority = _is_authority()
	if is_local:
		_adopt_local(shooter)
	return shooter


func remove_avatar(peer_id: int) -> void:
	if not _shooters.has(peer_id) or (_local != null and peer_id == _local.peer_id):
		return
	_free_shooter(_shooters[peer_id])
	_shooters.erase(peer_id)


## Joining a session throws away the offline body: the server decides who is in
## the world, this peer included, and says so in the messages that follow.
func reset_for_join() -> void:
	for peer_id in _shooters.keys():
		_free_shooter(_shooters[peer_id])
	_shooters.clear()
	_local = null


## Back to a session of one after the host goes away, so the game is still
## playable rather than left with an empty world.
func reset_to_offline() -> void:
	reset_for_join()
	var shooter := _create_shooter(1, true)
	_build_shooter_visuals(shooter)
	_adopt_local(shooter)


## Marks which of the spawned bodies this peer is looking out of.
func claim_avatar(peer_id: int, slot := 0) -> void:
	var shooter: Shooter = _shooters.get(peer_id)
	if shooter == null:
		shooter = create_avatar(peer_id, slot, true)
	shooter.is_local = true
	shooter.player.use_injected_input = false
	var material := shooter.body_mesh.material_override as ShaderMaterial
	if material != null:
		material.set_shader_parameter("clean_color", _body_color(true))
	_adopt_local(shooter)


## The one place the local player changes hands. Everything bound to the body
## the player is looking out of is rebound here.
func _adopt_local(shooter: Shooter) -> void:
	_local = shooter
	_rebind_visor_overlay()
	set_first_person(_first_person)


func set_avatar_authority(peer_id: int, authority: bool) -> void:
	var shooter: Shooter = _shooters.get(peer_id)
	if shooter != null:
		shooter.player.authority = authority


func _free_shooter(shooter: Shooter) -> void:
	for node in [shooter.player, shooter.air_visual, shooter.wall_visual,
			shooter.landing_visual, shooter.shadow_visual]:
		if is_instance_valid(node):
			# Detached before freeing so the node name is free again this frame:
			# the same peer id has to be able to respawn under the same name.
			remove_child(node)
			node.queue_free()


func shooter_for(peer_id: int) -> Shooter:
	return _shooters.get(peer_id)


func shooter_ids() -> Array:
	return _shooters.keys()


func _create_shooter(peer_id: int, is_local: bool, slot := 0) -> Shooter:
	var shooter := Shooter.new()
	shooter.peer_id = peer_id
	shooter.is_local = is_local
	# Seeded per peer so two players firing at once do not share a jitter
	# sequence. Peer 1 keeps the original seed, so the single-player game and
	# the checks built on it emit exactly the strand they always did.
	shooter.rng.seed = 0x4d41594f + peer_id - 1
	shooter.player = PlayerScript.new()
	shooter.player.peer_id = peer_id
	# The name is the address the network state is applied through, so it must
	# be derived from the peer id and nothing else.
	shooter.player.name = "Player_%d" % peer_id
	shooter.player.position = spawn_position_for(slot)
	add_child(shooter.player)
	_build_player_body(shooter)
	_shooters[peer_id] = shooter
	return shooter


func _build_shooter_visuals(shooter: Shooter) -> void:
	var suffix := str(shooter.peer_id)
	shooter.air_visual = _make_stream_visual("AirRibbon" + suffix, _mayo_material)
	shooter.wall_visual = _make_stream_visual("WallFixedRibbon" + suffix, _mayo_material)
	shooter.landing_visual = _make_stream_visual("LandingRibbon" + suffix, _landing_material)
	shooter.shadow_visual = _make_stream_visual("ProjectedShadow" + suffix, _shadow_material)


func _build_crosshair() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)
	_visor_overlay = VisorOverlayScript.new() as VisorOverlay
	_visor_overlay.name = "VisorOverlay"
	layer.add_child(_visor_overlay)
	_rebind_visor_overlay()
	# Above the sauce, so there is always something to aim with.
	_crosshair = CrosshairScript.new()
	_crosshair.visible = show_crosshair
	layer.add_child(_crosshair)
	_hud_layer = layer


## Host / join panel, opened with F2 and closed again once a session is up.
## Hidden by default, so the offline game starts exactly as it always has.
func _build_network_panel() -> void:
	_net_panel = NetPanelScript.new()
	_net_panel.bind(_net)
	_net_panel.visible = false
	_hud_layer.add_child(_net_panel)


## The overlay draws whichever lenses the local player is currently wearing.
## Joining a session replaces their body, and with it the visor and the texture
## the overlay samples, so this has to be redone every time the local player
## changes -- otherwise the screen keeps showing the mask of a body that no
## longer exists, which is to say nothing at all.
func _rebind_visor_overlay() -> void:
	if _visor_overlay == null or _local == null or _local.player.visor == null:
		return
	_visor_overlay.bind(_local.player.visor)


func set_network_panel_open(open: bool) -> void:
	if not is_instance_valid(_net_panel):
		return
	_net_panel.visible = open
	_input_enabled = not open
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED


func _build_environment() -> void:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("18212a")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b5c5d4")
	environment.ambient_light_energy = 0.72
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.name = "KeyLight"
	sun.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	sun.light_color = Color("fff1d1")
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)


func _build_player_body(shooter: Shooter) -> void:
	var collision := CollisionShape3D.new()
	var capsule_shape := CapsuleShape3D.new()
	capsule_shape.radius = 0.32
	capsule_shape.height = 1.28
	collision.shape = capsule_shape
	shooter.player.add_child(collision)

	var body_mesh := MeshInstance3D.new()
	body_mesh.name = "CapsuleBody"
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.radius = 0.32
	capsule_mesh.height = 1.28
	body_mesh.mesh = capsule_mesh
	shooter.player.add_child(body_mesh)
	shooter.body_mesh = body_mesh

	# The capsule carries a contamination grid of its own, wrapped around it,
	# and the shader that draws it is also what colours the body -- so the
	# player's colour is the grid's clean colour.
	var contamination := BodyContaminationScript.new() as BodyContamination
	contamination.name = "BodyContamination"
	contamination.cell_size = body_cell_size
	contamination.brush_radius = body_brush_radius
	shooter.player.add_child(contamination)
	shooter.player.contamination = contamination
	contamination.configure(shooter.player, body_mesh, capsule_shape.radius,
		capsule_shape.height, _body_color(shooter.is_local))

	# The pivot carries the pitch so the nozzle and muzzle follow vertical aim.
	# The player body itself only yaws.
	var aim_pivot := Node3D.new()
	aim_pivot.name = "AimPivot"
	aim_pivot.position = Vector3(0.0, eye_height, 0.0)
	shooter.player.add_child(aim_pivot)
	shooter.aim_pivot = aim_pivot

	# The glasses hang off the aim pivot, which already carries the aim pitch,
	# so they move with the camera rather than with the body.
	var visor := VisorScript.new() as VisorContamination
	visor.name = "Visor"
	aim_pivot.add_child(visor)
	shooter.player.visor = visor

	_build_weapon(shooter)


## Sauce bottle viewmodel, held to the lower right and angled so its nozzle
## points at the crosshair rather than straight down the view axis.
func _build_weapon(shooter: Shooter) -> void:
	var hold := Vector3(weapon_offset_right, weapon_offset_up, -weapon_offset_forward)
	var weapon := Node3D.new()
	weapon.name = "SauceBottle"
	# The convergence point sits on the view axis, so pointing the bottle at it
	# in pivot space is what visually lines the nozzle up with the crosshair.
	var to_crosshair := Vector3(0.0, 0.0, -aim_convergence_distance) - hold
	weapon.transform = Transform3D(Basis.looking_at(to_crosshair, Vector3.UP), hold)
	shooter.aim_pivot.add_child(weapon)
	shooter.weapon = weapon

	var body_color := Color("cdc4b4")
	var cap_color := Color("2f3a47")
	var label_color := Color("c25b3f")
	var cursor := 0.0
	# Squeeze-bottle silhouette: tapering body, a label band, then a dark cap and
	# tip that clear the body so the nozzle reads against the scene.
	cursor = _add_bottle_part(weapon, "Body", bottle_radius, bottle_radius * 0.72,
		bottle_length, cursor, body_color, 0.45, 16)
	_add_bottle_part(weapon, "Label", bottle_radius * 1.04, bottle_radius * 0.95,
		bottle_length * 0.3, bottle_length * 0.22, label_color, 0.6, 16)
	cursor = _add_bottle_part(weapon, "Shoulder", bottle_radius * 0.72, bottle_radius * 0.4,
		bottle_length * 0.26, cursor, body_color, 0.45, 14)
	cursor = _add_bottle_part(weapon, "Cap", bottle_radius * 0.46, bottle_radius * 0.42,
		bottle_length * 0.26, cursor, cap_color, 0.55, 14)
	cursor = _add_bottle_part(weapon, "Tip", bottle_radius * 0.42, bottle_radius * 0.16,
		bottle_length * 0.22, cursor, cap_color, 0.5, 12)

	var muzzle := Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0.0, 0.0, -cursor)
	weapon.add_child(muzzle)
	shooter.muzzle = muzzle


## Adds one cylinder section along the bottle axis starting at `offset`, and
## returns the offset of its far end.
func _add_bottle_part(weapon: Node3D, part_name: String, back_radius: float, front_radius: float,
		length: float, offset: float, color: Color, roughness: float, segments: int) -> float:
	var part := MeshInstance3D.new()
	part.name = part_name
	var mesh := CylinderMesh.new()
	# The mesh is built along +Y then rotated onto -Z, so its "top" faces forward.
	mesh.top_radius = front_radius
	mesh.bottom_radius = back_radius
	mesh.height = length
	mesh.radial_segments = segments
	part.mesh = mesh
	part.rotation_degrees.x = -90.0
	part.position = Vector3(0.0, 0.0, -(offset + length * 0.5))
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	part.material_override = material
	weapon.add_child(part)
	return offset + length


func _create_wall(wall_name: String, wall_position: Vector3, wall_size: Vector3, color: Color) -> void:
	var wall := WallScript.new()
	wall.name = wall_name
	wall.position = wall_position
	wall.size = wall_size
	wall.body_color = color
	wall.cell_size = grid_cell_size
	wall.brush_radius = contamination_brush_radius
	add_child(wall)
	_walls.push_back(wall)


func _make_stream_visual(visual_name: String, material: Material) -> StreamVisual:
	var visual := StreamVisualScript.new() as StreamVisual
	visual.name = visual_name
	visual.setup(material, maximum_point_count)
	add_child(visual)
	return visual


## Running over a painted cell trips the player. The test is a plain cell
## lookup on the same grid the floor draws, so it is exact and repeatable:
## there is no probability anywhere in it.
func _update_slip(shooter: Shooter) -> void:
	var player := shooter.player
	if not player.can_slip() or not player.is_running():
		return
	if _floor.is_mayo_at(player.global_position):
		player.begin_slip()


## Orientation of the aim, shared by the camera and the strand direction.
func _aim_basis(shooter: Shooter = null) -> Basis:
	if shooter == null:
		shooter = _local
	return Basis.from_euler(Vector3(shooter.aim_pitch, shooter.aim_yaw, 0.0))


func _update_camera() -> void:
	if _local == null or not is_instance_valid(_camera) or not is_instance_valid(_player):
		return
	_camera.fov = camera_fov
	var aim_basis := _aim_basis()
	var eye := _player.global_position + Vector3.UP * eye_height
	var tilt := _player.fall_tilt()
	# The stumble shakes the view in both camera modes; it is small enough that
	# the shoulder camera keeps the capsule in frame.
	var wobble := _player.stumble_wobble()
	if wobble != 0.0:
		aim_basis = aim_basis.rotated(aim_basis.z, deg_to_rad(stumble_camera_roll_degrees) * wobble)
		aim_basis = aim_basis.rotated(aim_basis.x, deg_to_rad(stumble_camera_pitch_degrees) * wobble)
	if _first_person:
		if tilt > 0.0:
			# Landing on your back means you end up looking up, so the view
			# pitches back rather than down; going over forwards mirrors it and
			# ends up staring at the floor. Crude on purpose; timing matters more.
			var fall_sign := _player.fall_direction
			aim_basis = aim_basis.rotated(aim_basis.z, deg_to_rad(fall_camera_roll_degrees) * tilt * fall_sign)
			aim_basis = aim_basis.rotated(aim_basis.x, deg_to_rad(fall_camera_pitch_degrees) * tilt * fall_sign)
			eye.y = lerpf(eye.y, fall_camera_height, tilt)
		_camera.global_transform = Transform3D(aim_basis, eye)
		return
	# The shoulder camera does not go down with the player: tilting it there
	# would swing it to the floor and lose the capsule it exists to show.
	# Over-the-shoulder: the camera keeps the aim orientation and is offset
	# behind and to the side, so the strand leaves toward the screen centre
	# rather than converging on a fixed point.
	var offset := aim_basis.x * shoulder_offset_right \
		+ aim_basis.y * shoulder_offset_up \
		+ aim_basis.z * shoulder_distance
	_camera.global_transform = Transform3D(aim_basis, eye + offset)


func _update_aim(shooter: Shooter = null) -> void:
	if shooter == null:
		shooter = _local
	if shooter == null or not is_instance_valid(shooter.player):
		return
	# The body yaws, the weapon pivot pitches, and the strand always leaves
	# along the camera forward axis.
	shooter.player.rotation.y = shooter.aim_yaw
	shooter.aim_pivot.rotation.x = shooter.aim_pitch
	shooter.attack_direction = -_aim_basis(shooter).z


## Aims at an explicit yaw/pitch in degrees. Used by the headless checks, which
## have no mouse to move.
func debug_set_aim(yaw_degrees: float, pitch_degrees: float) -> void:
	var limit := deg_to_rad(pitch_limit_degrees)
	_local.aim_yaw = deg_to_rad(yaw_degrees)
	_local.aim_pitch = clampf(deg_to_rad(pitch_degrees), -limit, limit)
	_update_aim()
	_update_camera()


## Aims from the weapon pivot at a world position.
func debug_aim_at(target: Vector3) -> void:
	var to_target := target - _local.aim_pivot.global_position
	if to_target.length_squared() < 0.000001:
		return
	to_target = to_target.normalized()
	debug_set_aim(rad_to_deg(atan2(-to_target.x, -to_target.z)), rad_to_deg(asin(to_target.y)))


func _emit_point(shooter: Shooter = null) -> void:
	if shooter == null:
		shooter = _local
	var point := MayoPoint.new()
	# Both jitters use the aim's own axes rather than the world up axis, which
	# degenerates to a zero vector when aiming straight up or down.
	var aim_basis := _aim_basis(shooter)
	var jitter := shooter.rng.randf_range(-lateral_position_jitter, lateral_position_jitter)
	point.position = shooter.muzzle.global_position + shooter.attack_direction * muzzle_forward_offset \
		+ aim_basis.x * jitter
	# The nozzle is held off to the side, so the strand is launched at the point
	# the crosshair marks rather than parallel to the view axis.
	var convergence := shooter.aim_pivot.global_position + shooter.attack_direction * aim_convergence_distance
	var angle := shooter.rng.randf_range(-yaw_angle_jitter, yaw_angle_jitter)
	var direction := (convergence - point.position).normalized().rotated(aim_basis.y, angle).normalized()
	point.last_collision_position = point.position
	# Speed jitter is independent of the yaw jitter above: it spreads where a
	# point runs out of pressure, and so spreads the landing point along the
	# strand axis rather than across it.
	var speed := extend_speed * (1.0 + shooter.rng.randf_range(-speed_magnitude_jitter, speed_magnitude_jitter))
	var player_velocity := shooter.player.velocity
	point.velocity = direction * speed + Vector3(player_velocity.x, 0.0, player_velocity.z) * inherited_player_velocity
	point.launch_direction = direction
	point.collision_slot = shooter.next_collision_slot
	point.burst_index = shooter.burst_index
	shooter.next_collision_slot = (shooter.next_collision_slot + 1) % maxi(raycast_frame_stride, 1)
	shooter.points.push_back(point)


## Two array-adjacent points are one continuous strand only if they came from
## the same trigger press and have not been pulled apart into separate blobs.
func _points_connected(front: MayoPoint, back: MayoPoint) -> bool:
	return front.burst_index == back.burst_index \
		and front.position.distance_squared_to(back.position) <= _break_distance_squared()


func _break_distance_squared() -> float:
	var break_distance := point_spacing * strand_break_spacing
	return break_distance * break_distance


## Index range [start, end] of the burst the point at `start` belongs to.
func _burst_end(start: int, shooter: Shooter = null) -> int:
	if shooter == null:
		shooter = _local
	var points := shooter.points
	var burst: int = points[start].burst_index
	var last := start
	while last + 1 < points.size() and points[last + 1].burst_index == burst:
		last += 1
	return last


func _apply_inertial_follow(player_movement: Vector3, shooter: Shooter = null) -> void:
	if shooter == null:
		shooter = _local
	var points := shooter.points
	if player_movement.length_squared() <= 0.00000001 or points.is_empty():
		return
	# t is the point's position inside its own burst. Measuring it against the
	# whole array skews the bend of the strand being extended whenever an
	# earlier burst is still falling. Only the burst still attached to the
	# muzzle follows the player; detached ones are on their own.
	var index := 0
	while index < points.size():
		var last := _burst_end(index, shooter)
		if points[index].burst_index == shooter.burst_index:
			var denominator := maxf(float(last - index), 1.0)
			for i in range(index, last + 1):
				var point := points[i]
				if point.phase != PointPhase.AIR:
					continue
				var t := float(i - index) / denominator
				point.position += player_movement * lerpf(front_follow, 1.0, pow(t, follow_curve_power))
		index = last + 1


## Releasing the trigger drops the line pressure. The front of the strand is
## already coasting on its own momentum and keeps its speed, while the points
## still at the muzzle lose the most, so the trail that lands afterwards starts
## at full range and is drawn back toward the player.
func _apply_release_pressure_loss(shooter: Shooter = null) -> void:
	if shooter == null:
		shooter = _local
	var points := shooter.points
	if release_pressure_loss <= 0.0 or points.is_empty():
		return
	# Only the burst that was being fired loses pressure, and t is measured
	# inside it: an earlier burst is already coasting and must not be decayed
	# a second time.
	var start := 0
	while start < points.size():
		var last := _burst_end(start, shooter)
		if points[start].burst_index == shooter.burst_index:
			var denominator := maxf(float(last - start), 1.0)
			for i in range(start, last + 1):
				var point := points[i]
				if point.phase != PointPhase.AIR:
					continue
				# The burst's index 0 is its front tip; its last index is the muzzle.
				var t := float(i - start) / denominator
				point.velocity *= 1.0 - release_pressure_loss * pow(t, release_pressure_curve)
				# Nothing is being pushed any more, so gravity takes over immediately.
				point.powered = false
		start = last + 1


func _simulate_points(delta: float, shooter: Shooter = null) -> void:
	if shooter == null:
		shooter = _local
	var points := shooter.points
	var space_state := get_world_3d().direct_space_state
	var physics_frame := int(Engine.get_physics_frames())
	var stride := maxi(raycast_frame_stride, 1)
	for point in points:
		if point.phase == PointPhase.WALL_FIXED:
			point.fixed_age += delta
			continue
		if point.phase == PointPhase.LANDING:
			point.landing_age += delta
			continue

		point.age += delta
		if point.powered:
			var time_expired := use_time_lifetime and point.age >= point_time_lifetime
			var distance_expired := use_distance_lifetime and point.distance_travelled >= stream_range
			if time_expired or distance_expired:
				point.powered = false
		if not point.powered:
			point.velocity.y -= gravity_acceleration * delta

		var previous := point.position
		var next := previous + point.velocity * delta
		point.distance_travelled += previous.distance_to(next)
		var accumulated_motion := point.last_collision_position.distance_to(next)
		var scheduled := physics_frame % stride == point.collision_slot % stride
		var near_floor := next.y <= strand_thickness * 1.25
		var must_catch_up := accumulated_motion >= point_spacing * float(stride + 1)
		var should_cast := accumulated_motion >= raycast_min_accumulated_motion \
			and (scheduled or near_floor or must_catch_up)
		if should_cast:
			var query := PhysicsRayQueryParameters3D.create(point.last_collision_position, next)
			if point.distance_travelled < self_hit_distance:
				query.exclude = [shooter.player.get_rid()]
			query.collide_with_areas = false
			if debug_profile_enabled:
				debug_raycast_count += 1
			var hit := space_state.intersect_ray(query)
			if not hit.is_empty():
				var collider := hit.collider as Node
				if collider != null and collider.is_in_group("mayo_floor"):
					_begin_landing(point, hit.position)
				else:
					# Only the server's copy of the strand marks anything. Every
					# peer runs this same code for every shooter, but a client's
					# splats would be its own guess; it waits for the broadcast.
					if _is_authority() and collider != null \
							and collider.is_in_group("mayo_contaminable"):
						_record_splat(collider, hit.position, hit.normal)
					point.position = hit.position + hit.normal * (strand_thickness * 0.5)
					point.last_collision_position = point.position
					point.velocity = Vector3.ZERO
					point.phase = PointPhase.WALL_FIXED
			else:
				point.position = next
				point.last_collision_position = next
		else:
			point.position = next

	for i in range(points.size() - 1, -1, -1):
		var point := points[i]
		if point.phase == PointPhase.LANDING and point.landing_age >= landing_transition_time:
			_spawn_landing_droplets(point.position)
			points.remove_at(i)
		elif point.phase == PointPhase.WALL_FIXED and point.fixed_age >= wall_fixed_hold_time:
			points.remove_at(i)
		elif point.position.y < -1.0:
			points.remove_at(i)


func _begin_landing(point: MayoPoint, hit_position: Vector3) -> void:
	point.position = hit_position + Vector3.UP * 0.008
	point.last_collision_position = point.position
	point.velocity = Vector3.ZERO
	point.powered = false
	point.phase = PointPhase.LANDING
	point.landing_age = 0.0
	if not _is_authority():
		return
	var cell := _floor.paint_mayo(hit_position)
	if cell.x >= 0:
		_pending_splats.append_array(PackedInt32Array([SPLAT_FLOOR, 0, cell.x, cell.y]))


## The server paints whatever was hit and queues the same splat for the peers.
## Walls and bodies differ only in how the surface is addressed; the strand and
## the batch do not care which one it was.
func _record_splat(surface: Node, hit_position: Vector3, hit_normal: Vector3) -> void:
	if surface is ContaminableObject:
		var wall := surface as ContaminableObject
		var splat := wall.paint_mayo(hit_position, hit_normal)
		var index := _walls.find(wall)
		if splat.x < 0 or index < 0:
			return
		_pending_splats.append_array(PackedInt32Array([
			SPLAT_WALL, index * FACES_PER_WALL + splat.x, splat.y, splat.z]))
		return
	if surface is MayoPlayer:
		var player := surface as MayoPlayer
		var cell := player.paint_mayo(hit_position, hit_normal)
		if cell.x < 0:
			return
		_pending_splats.append_array(PackedInt32Array([
			SPLAT_BODY, player.peer_id, cell.x, cell.y]))
		_record_visor_splat(player, hit_position)


## Replays a batch of splat centre cells from the server. `paint_cell` depends
## on nothing but the centre cell, so this reproduces the server's grid exactly
## rather than approximately -- see probe_determinism.
func apply_splats(data: PackedInt32Array) -> void:
	var index := 0
	while index + 3 < data.size():
		var kind := data[index]
		var target := data[index + 1]
		var cell := Vector2i(data[index + 2], data[index + 3])
		index += 4
		if kind == SPLAT_FLOOR:
			_floor.paint_mayo_cell(cell)
			continue
		if kind == SPLAT_BODY:
			var body_shooter: Shooter = _shooters.get(target)
			if body_shooter != null:
				body_shooter.player.paint_mayo_cell(cell)
			continue
		if kind == SPLAT_VISOR or kind == SPLAT_VISOR_CLEAR:
			var visor_shooter: Shooter = _shooters.get(target)
			if visor_shooter != null and visor_shooter.player.visor != null:
				if kind == SPLAT_VISOR_CLEAR:
					visor_shooter.player.visor.clear()
				else:
					visor_shooter.player.visor.paint_cell(cell)
			continue
		var wall_index := target / FACES_PER_WALL
		var face := target % FACES_PER_WALL
		if wall_index >= 0 and wall_index < _walls.size():
			_walls[wall_index].paint_mayo_cell(face, cell)


## A hit that lands in front of a player's eyes goes on their glasses as well
## as on their body. Decided by the server off the same hit, so the mask that
## blinds them and the mask everyone else sees on their face are one thing.
func _record_visor_splat(player: MayoPlayer, hit_position: Vector3) -> void:
	if player.visor == null:
		return
	var direction := player.visor.to_local(hit_position)
	var cell := player.visor.paint_from_view(direction, camera_fov)
	if cell.x < 0:
		return
	_pending_splats.append_array(PackedInt32Array([
		SPLAT_VISOR, player.peer_id, cell.x, cell.y]))


## R. The wipe is a shared state change -- everyone watches the lenses come up
## and the mask disappear -- so a client asks and the server decides.
func _request_wipe() -> void:
	if _local == null:
		return
	if _is_authority():
		begin_wipe_for(_local.peer_id)
		return
	_net.request_wipe()


## The authority's side of a wipe request, wherever it came from.
func begin_wipe_for(peer_id: int) -> bool:
	var shooter: Shooter = _shooters.get(peer_id)
	if shooter == null or not shooter.player.begin_wipe():
		return false
	_wiping[peer_id] = true
	return true


## Ends the wipes that ran out this frame, on the authority, and queues the
## clear for everyone else.
func _finish_wipes() -> void:
	for shooter in _shooters.values():
		var player: MayoPlayer = shooter.player
		if not _wiping.has(player.peer_id):
			continue
		if player.is_wiping():
			continue
		_wiping.erase(player.peer_id)
		if player.visor != null:
			player.visor.clear()
		_pending_splats.append_array(PackedInt32Array([
			SPLAT_VISOR_CLEAR, player.peer_id, 0, 0]))


## Whole-grid state for a peer that has just joined, so it starts from what is
## already on the floor rather than from clean.
func grid_snapshot() -> Array:
	var snapshot := [_floor.snapshot_cells()]
	for wall in _walls:
		for face in wall.face_count():
			snapshot.push_back(wall.snapshot_cells(face))
	return snapshot


## The pieces arrive one message each, in the order `grid_snapshot` produced
## them: the floor, then every wall face.
func apply_grid_snapshot_part(index: int, cells: PackedByteArray) -> bool:
	if index == 0:
		return _floor.restore_cells(cells)
	var cursor := 1
	for wall in _walls:
		for face in wall.face_count():
			if cursor == index:
				return wall.restore_cells(face, cells)
			cursor += 1
	return false


## A body's stain, for a peer joining a session that is already messy. Bodies
## are not part of `grid_snapshot`: which ones exist depends on who is in the
## session, so they are sent per player as the players themselves are spawned.
func body_snapshot(peer_id: int) -> PackedByteArray:
	var shooter: Shooter = _shooters.get(peer_id)
	if shooter == null or shooter.player.contamination == null:
		return PackedByteArray()
	return shooter.player.contamination.snapshot_cells()


func apply_body_snapshot(peer_id: int, cells: PackedByteArray) -> bool:
	var shooter: Shooter = _shooters.get(peer_id)
	if shooter == null or shooter.player.contamination == null:
		return false
	return shooter.player.contamination.restore_cells(cells)


## The glasses go over with the body: someone joining a messy session should see
## who is already blinded, not a room of clean lenses.
func visor_snapshot(peer_id: int) -> PackedByteArray:
	var shooter: Shooter = _shooters.get(peer_id)
	if shooter == null or shooter.player.visor == null:
		return PackedByteArray()
	return shooter.player.visor.snapshot_cells()


func apply_visor_snapshot(peer_id: int, cells: PackedByteArray) -> bool:
	var shooter: Shooter = _shooters.get(peer_id)
	if shooter == null or shooter.player.visor == null:
		return false
	return shooter.player.visor.restore_cells(cells)


func visor_md5(peer_id: int) -> String:
	var shooter: Shooter = _shooters.get(peer_id)
	if shooter == null or shooter.player.visor == null:
		return ""
	return shooter.player.visor.cells_md5()


func body_md5(peer_id: int) -> String:
	var shooter: Shooter = _shooters.get(peer_id)
	if shooter == null or shooter.player.contamination == null:
		return ""
	return shooter.player.contamination.cells_md5()


func grid_md5() -> String:
	var parts := PackedStringArray([_floor.cells_md5()])
	for wall in _walls:
		parts.push_back(wall.cells_md5())
	return "|".join(parts)


func _enforce_spacing_constraint(shooter: Shooter = null) -> void:
	if shooter == null:
		shooter = _local
	var points := shooter.points
	if points.size() < 2:
		return
	var break_distance_squared := _break_distance_squared()
	for _pass in spacing_constraint_passes:
		for i in points.size() - 1:
			var front := points[i]
			var back := points[i + 1]
			# Inlined _points_connected: this runs once per pair per pass.
			if front.burst_index != shooter.burst_index \
					or front.burst_index != back.burst_index \
					or front.position.distance_squared_to(back.position) > break_distance_squared:
				continue
			var direction := (front.launch_direction + back.launch_direction).normalized()
			if direction.length_squared() < 0.000001:
				direction = shooter.attack_direction
			var projected_gap := (front.position - back.position).dot(direction)
			if projected_gap <= point_spacing:
				continue
			var correction := direction * (projected_gap - point_spacing)
			var front_free := front.phase == PointPhase.AIR
			var back_free := back.phase == PointPhase.AIR
			if front_free and back_free:
				front.position -= correction * 0.5
				back.position += correction * 0.5
			elif front_free:
				front.position -= correction
			elif back_free:
				back.position += correction


func _trim_safety_cap(shooter: Shooter = null) -> void:
	if shooter == null:
		shooter = _local
	while shooter.points.size() > maximum_point_count:
		shooter.points.pop_front()


func _update_visuals(shooter: Shooter = null) -> void:
	if shooter == null:
		shooter = _local
	if shooter.air_visual == null:
		return
	var camera_position := _camera.global_position
	var camera_forward := -_camera.global_basis.z
	var air_segments := _segments_for_phase(PointPhase.AIR, camera_position, shooter)
	var wall_segments := _segments_for_phase(PointPhase.WALL_FIXED, camera_position, shooter)
	var landing_segments := _segments_for_phase(PointPhase.LANDING, camera_position, shooter)
	var shadow_segments := _shadow_segments(camera_position, shooter)
	var mayo_tint := Color("fff0a8")
	shooter.air_visual.update_ribbon(air_segments, camera_position, camera_forward, strand_thickness, mayo_tint)
	shooter.wall_visual.update_ribbon(wall_segments, camera_position, camera_forward, strand_thickness, mayo_tint)
	shooter.landing_visual.update_ribbon(landing_segments, camera_position, camera_forward, strand_thickness, mayo_tint, 0.004)
	shooter.shadow_visual.update_ribbon(shadow_segments, camera_position, camera_forward, strand_thickness * 0.72,
		Color(0.08, 0.07, 0.055, 0.18), 0.012)


## True for points sitting on top of the camera, which in first person would
## otherwise fill the screen with the strand root.
func _is_near_camera(point: MayoPoint, camera_position: Vector3) -> bool:
	if strand_near_cull_distance <= 0.0:
		return false
	return point.position.distance_squared_to(camera_position) \
		< strand_near_cull_distance * strand_near_cull_distance


func _segments_for_phase(phase: PointPhase, camera_position: Vector3, shooter: Shooter = null) -> Array:
	if shooter == null:
		shooter = _local
	var result: Array = []
	var current: Array = []
	# Points skipped here are not array-adjacent to the next kept one, so the
	# run breaks and `previous` is cleared; within a run adjacency holds.
	var previous: MayoPoint = null
	var break_distance_squared := _break_distance_squared()
	for point in shooter.points:
		if point.phase != phase or _is_near_camera(point, camera_position):
			if not current.is_empty():
				result.push_back(current)
				current = []
			previous = null
			continue
		if previous != null and (previous.burst_index != point.burst_index \
				or previous.position.distance_squared_to(point.position) > break_distance_squared):
			if not current.is_empty():
				result.push_back(current)
				current = []
		var visual_point := RibbonPoint.new()
		visual_point.position = point.position
		if phase == PointPhase.LANDING:
			var progress := clampf(point.landing_age / landing_transition_time, 0.0, 1.0)
			visual_point.opacity = 1.0 - progress
			visual_point.width_scale = 1.0 - progress
		current.push_back(visual_point)
		previous = point
	if not current.is_empty():
		result.push_back(current)
	return result


func _shadow_segments(camera_position: Vector3, shooter: Shooter = null) -> Array:
	if shooter == null:
		shooter = _local
	var result: Array = []
	var current: Array = []
	var previous: MayoPoint = null
	var break_distance_squared := _break_distance_squared()
	for point in shooter.points:
		if point.phase == PointPhase.WALL_FIXED or _is_near_camera(point, camera_position):
			if not current.is_empty():
				result.push_back(current)
				current = []
			previous = null
			continue
		if previous != null and (previous.burst_index != point.burst_index \
				or previous.position.distance_squared_to(point.position) > break_distance_squared):
			if not current.is_empty():
				result.push_back(current)
				current = []
		previous = point
		var visual_point := RibbonPoint.new()
		visual_point.position = Vector3(point.position.x, 0.0, point.position.z)
		if point.phase == PointPhase.LANDING:
			var progress := clampf(point.landing_age / landing_transition_time, 0.0, 1.0)
			visual_point.opacity = 1.0 - progress
			visual_point.width_scale = 1.0 - progress
		current.push_back(visual_point)
	if not current.is_empty():
		result.push_back(current)
	return result


func _build_droplet_pool(mayo_material: Material) -> void:
	# One pool per world, shared by every player in it, and a landing takes its
	# droplets whether or not there is room: a full pool replaces the droplet
	# taken longest ago, which is fine only while that one was about to expire
	# anyway. What it has to hold is
	#
	#     needed = landings per second x droplets_per_landing x droplet_lifetime
	#
	# A landing is one point reaching the floor, so the rate follows
	# extend_speed / point_spacing: 156 a second per player at the current
	# density. Two players firing: 311 x 4 x 0.40 = 498, inside 512.
	#
	# MAX_CLIENTS caps a session at two players, which is what this is sized
	# for. Raise it and this needs recomputing -- at four players the same
	# settings need 1369, and droplets start being thrown away with two thirds
	# of their life left. debug_droplet_overwrites and
	# debug_droplet_overwritten_life measure exactly that.
	const POOL_SIZE := 512
	var droplet_mesh := SphereMesh.new()
	droplet_mesh.radius = 0.5
	droplet_mesh.height = 1.0
	droplet_mesh.radial_segments = 8
	droplet_mesh.rings = 4
	droplet_mesh.material = mayo_material

	_droplet_multimesh = MultiMesh.new()
	_droplet_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_droplet_multimesh.mesh = droplet_mesh
	_droplet_multimesh.instance_count = POOL_SIZE
	_droplet_buffer.resize(POOL_SIZE * 12)
	_droplet_buffer.fill(0.0)
	_droplet_multimesh.buffer = _droplet_buffer
	var instance := MultiMeshInstance3D.new()
	instance.name = "LandingDropletPool"
	instance.add_to_group("mayo_droplets")
	instance.multimesh = _droplet_multimesh
	instance.custom_aabb = AABB(Vector3(-12.0, -1.0, -12.0), Vector3(24.0, 5.0, 24.0))
	add_child(instance)

	_droplets.resize(POOL_SIZE)
	for i in POOL_SIZE:
		_droplets[i] = MayoDroplet.new()


func _spawn_landing_droplets(position: Vector3) -> void:
	if _droplet_multimesh == null:
		return
	debug_droplet_spawns += 1
	var now := Time.get_ticks_msec() * 0.001
	var expires_at := now + droplet_lifetime
	for _i in droplets_per_landing:
		var droplet := _droplets[_droplet_cursor]
		if not droplet.active:
			_active_droplet_indices.push_back(_droplet_cursor)
		else:
			# The cursor walks the pool in order and every droplet is given the
			# same lifetime, so the slot it arrives at is always the one taken
			# longest ago. Recorded so that can be checked rather than assumed:
			# if it holds, what is overwritten was about to expire anyway.
			debug_droplet_overwrites += 1
			debug_droplet_overwritten_life += maxf(droplet.expires_at - now, 0.0)
		_droplet_cursor = (_droplet_cursor + 1) % _droplets.size()
		var angle := _rng.randf_range(0.0, TAU)
		var spread_radius := sqrt(_rng.randf()) * 0.12
		droplet.active = true
		droplet.expires_at = expires_at
		droplet.radius = _rng.randf_range(0.014, 0.03)
		droplet.position = position + Vector3(cos(angle) * spread_radius, droplet.radius, sin(angle) * spread_radius)
		_write_droplet_buffer((_droplet_cursor - 1 + _droplets.size()) % _droplets.size(),
			droplet.position, droplet.radius * 2.0)
	_droplet_buffer_dirty = true


func _simulate_droplets(_delta: float) -> void:
	if _droplet_multimesh == null or _active_droplet_indices.is_empty():
		return
	var current_time := Time.get_ticks_msec() * 0.001
	for active_index in range(_active_droplet_indices.size() - 1, -1, -1):
		var i := _active_droplet_indices[active_index]
		var droplet := _droplets[i]
		if current_time >= droplet.expires_at:
			droplet.active = false
			_write_droplet_buffer(i, Vector3.ZERO, 0.0)
			_active_droplet_indices.remove_at(active_index)
			_droplet_buffer_dirty = true
	if _droplet_buffer_dirty:
		_droplet_multimesh.buffer = _droplet_buffer
		_droplet_buffer_dirty = false


func _write_droplet_buffer(index: int, position: Vector3, uniform_scale: float) -> void:
	var offset := index * 12
	# MultiMesh 3D transform buffer: three rows of (basis xyz, origin).
	_droplet_buffer[offset] = uniform_scale
	_droplet_buffer[offset + 1] = 0.0
	_droplet_buffer[offset + 2] = 0.0
	_droplet_buffer[offset + 3] = position.x
	_droplet_buffer[offset + 4] = 0.0
	_droplet_buffer[offset + 5] = uniform_scale
	_droplet_buffer[offset + 6] = 0.0
	_droplet_buffer[offset + 7] = position.y
	_droplet_buffer[offset + 8] = 0.0
	_droplet_buffer[offset + 9] = 0.0
	_droplet_buffer[offset + 10] = uniform_scale
	_droplet_buffer[offset + 11] = position.z


func debug_reset_profile() -> void:
	debug_profile_frames = 0
	debug_raycast_count = 0
	debug_max_points = 0
	debug_splats = 0
	debug_droplet_spawns = 0
	debug_droplet_overwrites = 0
	debug_droplet_overwritten_life = 0.0
	for key in debug_timings_us:
		debug_timings_us[key] = 0
	if is_instance_valid(_floor):
		_floor.reset_debug_counters()
	for wall in _walls:
		wall.reset_debug_counters()
