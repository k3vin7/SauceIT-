class_name MayoTutorialDrone
extends Node3D

## The doctor's drone: a small quadcopter that flies into the monster's face and
## keeps it looking the wrong way while the party gets clear and tops up.
##
## **Placeholder art, deliberately.** It is a body, four rotor discs and a lens,
## all built from primitives, because there is no drone model in the project and
## downloading one is out of scope. Everything about how it looks is in the block
## of constants below, and the node it builds is a plain `Node3D` tree -- swapping
## in an authored model means replacing `_build` and leaving the rest alone.
##
## It has **no collider on purpose**. It is not in `mayo_contaminable`, so the
## stream passes through it and it takes no sauce: a drone that could be painted
## or shot down by the party would be a target, and it is a prop.
##
## Movement is not done here -- the tutorial places it, because where it should
## hover is a fact about the monster. What this script owns is how it looks: the
## rotor spin, the tilt it leans into as it moves, and the way it drops out of the
## air when the monster swats it.

# --- shape ------------------------------------------------------------------
## Sized against the burger it is annoying rather than against a real drone: next
## to a four-metre monster a 0.5 m quadcopter is a speck, and the whole job of
## this prop is to be the thing the party can see has the monster's attention.
const BODY_SIZE := Vector3(0.78, 0.26, 0.78)
const ARM_LENGTH := 0.68
const ARM_THICKNESS := 0.075
const ROTOR_RADIUS := 0.34
const ROTOR_THICKNESS := 0.02
const LENS_RADIUS := 0.14

# --- colour -----------------------------------------------------------------
const BODY_COLOR := Color("2b3138")
const TRIM_COLOR := Color("8fd0ff")
const ROTOR_COLOR := Color(0.72, 0.84, 0.94, 0.32)
const LENS_COLOR := Color("ff6a4d")
## How brightly the trim and the lens glow. It has to read against a pale street
## and from across it.
const TRIM_GLOW := 3.2
const LENS_GLOW := 4.5

# --- motion -----------------------------------------------------------------
## Rotor spin, in turns a second. Fast enough to blur, slow enough not to strobe.
const ROTOR_HZ := 9.0
## How far it leans into the direction it is travelling, and how quickly the lean
## follows. A quadcopter that stayed level while sliding sideways reads as a
## floating box.
const TILT_PER_SPEED := 0.055
const TILT_MAX := deg_to_rad(22.0)
const TILT_FOLLOW := 6.0
## Idle yaw drift, so a drone holding station is still alive.
const YAW_DRIFT_HZ := 0.22
const YAW_DRIFT := deg_to_rad(14.0)

# --- being swatted ----------------------------------------------------------
## Thrown this way when the monster connects, then gravity takes it.
const SMASH_SPEED := 7.0
const SMASH_LIFT := 3.4
const SMASH_SPIN := 9.0
const SMASH_GRAVITY := 18.0
## Hidden once it has been on the floor this long. It is left lying there for a
## moment first so the party sees where it went.
const WRECK_LINGER := 2.5

var _rotors: Array[Node3D] = []
var _body: Node3D
var _smashed := false
var _velocity := Vector3.ZERO
var _spin := 0.0
var _wreck_age := 0.0
var _clock := 0.0
var _tilt := Vector2.ZERO
var _previous := Vector3.INF


func _ready() -> void:
	name = "TutorialDrone"
	_build()


func _build() -> void:
	_body = Node3D.new()
	_body.name = "Frame"
	add_child(_body)

	var shell := MeshInstance3D.new()
	shell.name = "Shell"
	var box := BoxMesh.new()
	box.size = BODY_SIZE
	shell.mesh = box
	shell.material_override = _matte(BODY_COLOR)
	_body.add_child(shell)

	# A lit strip along the top, so which way is up is obvious from below.
	var strip := MeshInstance3D.new()
	strip.name = "Trim"
	var strip_box := BoxMesh.new()
	strip_box.size = Vector3(BODY_SIZE.x * 0.62, BODY_SIZE.y * 0.32, BODY_SIZE.z * 0.18)
	strip.mesh = strip_box
	strip.position = Vector3(0.0, BODY_SIZE.y * 0.55, 0.0)
	strip.material_override = _glowing(TRIM_COLOR, TRIM_GLOW)
	_body.add_child(strip)

	# The camera it is supposedly annoying the monster with, on its -z front.
	var lens := MeshInstance3D.new()
	lens.name = "Lens"
	var lens_mesh := SphereMesh.new()
	lens_mesh.radius = LENS_RADIUS
	lens_mesh.height = LENS_RADIUS * 2.0
	lens_mesh.radial_segments = 10
	lens_mesh.rings = 5
	lens.mesh = lens_mesh
	lens.position = Vector3(0.0, -BODY_SIZE.y * 0.2, -BODY_SIZE.z * 0.55)
	lens.material_override = _glowing(LENS_COLOR, LENS_GLOW)
	_body.add_child(lens)

	for corner in [Vector2(1.0, 1.0), Vector2(-1.0, 1.0), Vector2(1.0, -1.0),
			Vector2(-1.0, -1.0)]:
		var offset := Vector3(corner.x, 0.0, corner.y).normalized() * ARM_LENGTH

		var arm := MeshInstance3D.new()
		arm.name = "Arm"
		var arm_box := BoxMesh.new()
		arm_box.size = Vector3(ARM_THICKNESS, ARM_THICKNESS, ARM_LENGTH)
		arm.mesh = arm_box
		arm.position = offset * 0.5
		arm.look_at_from_position(offset * 0.5, offset, Vector3.UP)
		arm.material_override = _matte(BODY_COLOR)
		_body.add_child(arm)

		var hub := Node3D.new()
		hub.name = "Rotor"
		hub.position = offset + Vector3(0.0, BODY_SIZE.y * 0.5, 0.0)
		_body.add_child(hub)
		var disc := MeshInstance3D.new()
		var disc_mesh := CylinderMesh.new()
		disc_mesh.top_radius = ROTOR_RADIUS
		disc_mesh.bottom_radius = ROTOR_RADIUS
		disc_mesh.height = ROTOR_THICKNESS
		disc_mesh.radial_segments = 12
		disc.mesh = disc_mesh
		# Two blades' worth of mesh rather than a full disc would need a custom
		# mesh; a thin translucent cylinder is what a spinning rotor looks like
		# anyway, and it costs one primitive.
		disc.material_override = _translucent(ROTOR_COLOR)
		hub.add_child(disc)
		_rotors.push_back(hub)


func _matte(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.6
	return material


func _glowing(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _translucent(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


## Whether it is still flying. The tutorial owns the answer to "should it be up";
## this is only about the wreck having finished falling.
func is_flying() -> bool:
	return not _smashed


## Knocked out of the air. Thrown along its own -z front, which is the way it was
## facing the monster from, so it goes past the party rather than into them.
func smash() -> void:
	if _smashed:
		return
	_smashed = true
	var away := -global_transform.basis.z
	away.y = 0.0
	if away.length_squared() < 0.000001:
		away = Vector3.FORWARD
	_velocity = away.normalized() * SMASH_SPEED + Vector3.UP * SMASH_LIFT
	_spin = SMASH_SPIN


## `hover` is where the tutorial wants it; INF means "you are not flying anywhere".
func advance(delta: float, hover: Vector3) -> void:
	_clock += delta
	if _smashed:
		_fall(delta)
		return
	visible = true
	for index in _rotors.size():
		# Alternate directions, as a real quad does.
		var way: float = 1.0 if index % 2 == 0 else -1.0
		_rotors[index].rotate_y(TAU * ROTOR_HZ * delta * way)
	if hover == Vector3.INF:
		return

	# Leaned into its travel. Measured from where it actually moved rather than
	# from a velocity it does not own, because the tutorial is what moves it.
	var moved := Vector3.ZERO
	if _previous != Vector3.INF:
		moved = global_position - _previous
	_previous = global_position
	var speed := moved / maxf(delta, 0.0001)
	var wanted := Vector2(
		clampf(-speed.z * TILT_PER_SPEED, -TILT_MAX, TILT_MAX),
		clampf(speed.x * TILT_PER_SPEED, -TILT_MAX, TILT_MAX))
	_tilt = _tilt.lerp(wanted, clampf(TILT_FOLLOW * delta, 0.0, 1.0))

	# Facing the way it is going, with the idle drift on top so a drone holding
	# station is not dead still.
	var flat := Vector3(speed.x, 0.0, speed.z)
	var yaw: float = rotation.y
	if flat.length() > 0.2:
		yaw = atan2(-flat.x, -flat.z)
	yaw += sin(_clock * TAU * YAW_DRIFT_HZ) * YAW_DRIFT
	rotation = Vector3(_tilt.x, yaw, _tilt.y)


func _fall(delta: float) -> void:
	_velocity.y -= SMASH_GRAVITY * delta
	global_position += _velocity * delta
	rotate_x(_spin * delta)
	rotate_z(_spin * 0.6 * delta)
	# Stops on the road rather than falling through it. No collider, so this is
	# the floor height rather than a physics answer -- it is a prop coming to rest.
	if global_position.y <= 0.18:
		global_position.y = 0.18
		_velocity = Vector3.ZERO
		_spin = 0.0
		_wreck_age += delta
		if _wreck_age >= WRECK_LINGER:
			visible = false
