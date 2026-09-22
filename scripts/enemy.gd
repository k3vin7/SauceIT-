class_name MayoEnemy
extends CharacterBody3D

## The thing that walks at you.
##
## Gameplay still uses the original capsule skeleton: health, hits, chase,
## contact reach, sauce-grid coordinates and network state therefore have not
## changed. The capsules' welded render mesh is kept hidden as the stable mask
## target, while the visible body is the animated hamburger-monster GLB.
##
## Everything that decides anything runs on the authority only. A client's
## enemies are placed by the packets the server sends, the same way its players
## are, so the enemy that is about to hit you is in the same place on every
## screen.

## Fixed by the sauce refill station: twice its width and twice its height.
## Taking them from `StreetMap.VENDING_SIZE` rather than writing the metres out
## means the two cannot drift apart.
const WIDTH_MULTIPLE := 2.0
const HEIGHT_MULTIPLE := 2.0
const HAMBURGER_MONSTER := preload(
	"res://assets/enemies/hamburger_monster/hamburger_monster.glb")
## Evaluated mesh bounds in the authored Blender file, in metres. Scaling by
## this keeps the visible monster's soles and crown aligned with the legacy
## gameplay body's exact height.
const MODEL_SOURCE_HEIGHT := 1.7729597

@export_group("Health")
@export_range(10.0, 2000.0, 1.0) var max_health := 240.0
## Per strand point that lands on it. The nozzle emits `extend_speed /
## point_spacing` points a second -- about 187 at the reference values -- so a
## per-hit figure this small is still roughly 75 damage a second of accurate,
## sustained fire, and about three and a half seconds to put one down. Anything
## per-hit that reads like a normal damage number melts it instantly.
@export_range(0.01, 20.0, 0.01) var sauce_damage_per_hit := 0.4

@export_group("Movement")
## A fraction of the player's walking speed. Set from `MayoPlayer.walk_speed`
## when the world builds one, so it stays that fraction of whatever that becomes.
@export_range(0.1, 20.0, 0.1, "suffix:m/s") var move_speed := 3.64
@export_range(1.0, 60.0, 0.5, "suffix:m/s²") var fall_gravity := 20.0
## How fast it swings round to face where you have moved to. It is not a turret:
## running past one should leave it briefly pointed at where you were.
@export_range(0.5, 20.0, 0.1, "suffix:rad/s") var turn_speed := 2.4

@export_group("Its attack")
## Weak on purpose. At one hit every `contact_interval` this is about 7 damage a
## second, so a player who walks into one and stays there has a good while to
## notice and get out.
@export_range(0.0, 100.0, 0.5) var contact_damage := 6.0
@export_range(0.1, 5.0, 0.05, "suffix:s") var contact_interval := 0.8
## Beyond the two capsule radii. Its arms are not modelled, so this stands in
## for them.
@export_range(0.0, 3.0, 0.05, "suffix:m") var contact_reach := 0.5

@export_group("Going down")
## Long enough to read as toppling rather than as being deleted.
@export_range(0.1, 4.0, 0.05, "suffix:s") var fall_duration := 0.9

var health := 240.0
## Clients simulate no enemies at all, exactly as they simulate no bodies.
var authority := true
var contamination: BodyContamination
## Half the silhouette's width: the arms reach this far out, so it is also the
## capsule that the unwrap wraps around.
var radius := 1.15
var height := 4.1
## Where it is looking, kept separately from `rotation.y` because a body part
## way through falling over is turned about two axes and the yaw can no longer
## be read back off the node.
var facing_yaw := 0.0
## 0 standing, TAU/4 flat on its back.
var fall_angle := 0.0

var _contact_cooldown := 0.0
var _body_mesh: MeshInstance3D
var _visual_root: Node3D
var _animation_player: AnimationPlayer
var _idle_animation := &""
var _walk_animation := &""
var _attack_animation := &""
var _death_animation := &""
var _attack_animation_active := false
## World point the feet were planted on when it died -- the axis it goes over.
var _fall_pivot := Vector3.ZERO
## Half the thickness of the torso: what it comes to rest on.
var _rest_radius := 0.37


func _ready() -> void:
	add_to_group("mayo_enemy")
	# What the strand looks for. Being in this group is what makes sauce stick.
	add_to_group("mayo_contaminable")


## The body: its bones as colliders, its bones welded into one mesh, and the
## contamination grid wrapped round the whole silhouette. `body_color` is the
## grid's clean colour, so the stain and the skin are one material.
func build(cell_size: float, brush_radius: float, body_color: Color) -> void:
	var station: Vector3 = StreetMap.VENDING_SIZE
	radius = station.x * WIDTH_MULTIPLE * 0.5
	height = station.y * HEIGHT_MULTIPLE

	var bones := _bones()
	_rest_radius = bones[BONE_TORSO][2]

	# One collider per bone rather than one capsule around the lot. A single
	# capsule wide enough to cover the outstretched arms is a fat pill that
	# nothing could walk past, and sauce aimed at an arm would land on thin air
	# a metre outside it. Per bone, the silhouette you can see is the silhouette
	# you can hit.
	for index in bones.size():
		var bone: Array = bones[index]
		var shape := CapsuleShape3D.new()
		shape.radius = bone[2]
		var span: Vector3 = bone[1] - bone[0]
		shape.height = span.length() + bone[2] * 2.0
		var collision := CollisionShape3D.new()
		collision.name = "Bone%d" % index
		collision.shape = shape
		collision.transform = Transform3D(_aligned_basis(span), (bone[0] + bone[1]) * 0.5)
		add_child(collision)

	_body_mesh = MeshInstance3D.new()
	_body_mesh.name = "EnemyBody"
	_body_mesh.mesh = _welded_mesh(bones)
	# Keep the old mesh as the deterministic contamination target without
	# drawing the capsule mockup over the authored monster.
	_body_mesh.visible = false
	add_child(_body_mesh)
	_build_visual()

	contamination = BodyContamination.new()
	contamination.name = "BodyContamination"
	contamination.cell_size = cell_size
	contamination.brush_radius = brush_radius
	add_child(contamination)
	# The unwrap is given the **torso's** radius, not the figure's. It maps a
	# surface point by its angle about the body's axis, which is an honest
	# unwrap only for a surface of revolution -- and the figure stopped being
	# one the moment it grew arms. `radius` is half the arm span, 1.15 m, while
	# the torso the sauce actually lands on is 0.37 m out: handing the unwrap
	# 1.15 stretches the torso's 2.3 m of surface over 7.2 m of grid, so a splat
	# that should be 0.40 m across renders about 0.13 m across. That is why a
	# hit on one of these looked nothing like a hit on a player.
	#
	# Using the torso instead makes the body -- the part that is nearly always
	# what gets hit -- come out at the right size. The limbs, which stick out
	# further, take a stain that is too wide for them and simply go covered;
	# they are thinner than one splat, so there was never a middle ground. The
	# fix without that compromise is a per-bone atlas, which is a much bigger
	# change than the one it would improve on.
	contamination.configure(self, _body_mesh, bones[BONE_TORSO][2], height, body_color)
	contamination.add_visual_overlay(_visual_root)

	health = max_health
	_play_animation(_idle_animation)


## Adds the authored monster as presentation only. Its transform deliberately
## derives from the legacy body height; colliders, reach and spawn placement
## remain exactly as before.
func _build_visual() -> void:
	_visual_root = HAMBURGER_MONSTER.instantiate() as Node3D
	if _visual_root == null:
		push_error("Hamburger monster GLB did not instantiate as Node3D")
		return
	_visual_root.name = "HamburgerMonsterVisual"
	var model_scale := height / MODEL_SOURCE_HEIGHT
	_visual_root.scale = Vector3.ONE * model_scale
	_visual_root.position = Vector3(0.0, -height * 0.5, 0.0)
	# The Blender asset faces -Y, which becomes +Z through glTF's Y-up export;
	# this half turn aligns its mouth with MayoEnemy's established -Z front.
	_visual_root.rotation.y = PI
	add_child(_visual_root)

	var players := _visual_root.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		push_error("Hamburger monster has no AnimationPlayer")
		return
	_animation_player = players[0] as AnimationPlayer
	_idle_animation = _find_animation("Idle")
	_walk_animation = _find_animation("Walk")
	_attack_animation = _find_animation("Attack")
	_death_animation = _find_animation("Death")
	_animation_player.animation_finished.connect(_on_animation_finished)


func _find_animation(suffix: String) -> StringName:
	if _animation_player == null:
		return &""
	for animation in _animation_player.get_animation_list():
		if String(animation).to_lower().ends_with(suffix.to_lower()):
			return animation
	push_error("Hamburger monster is missing the %s animation" % suffix)
	return &""


func _play_animation(animation: StringName) -> void:
	if _animation_player == null or animation.is_empty():
		return
	if _animation_player.current_animation != animation \
			or not _animation_player.is_playing():
		_animation_player.play(animation)


func _set_locomotion_animation(moving: bool) -> void:
	if not is_alive() or _attack_animation_active:
		return
	_play_animation(_walk_animation if moving else _idle_animation)


func _play_attack_animation() -> void:
	if _animation_player == null or _attack_animation.is_empty():
		return
	_attack_animation_active = true
	# A new damage tick is a new bite, even if the previous clip had not quite
	# reached its final frame yet.
	_animation_player.stop()
	_animation_player.play(_attack_animation)


func _play_death_animation() -> void:
	_attack_animation_active = false
	_play_animation(_death_animation)


func _on_animation_finished(animation: StringName) -> void:
	if animation == _idle_animation or animation == _walk_animation:
		_animation_player.play(animation)
		return
	if animation != _attack_animation:
		return
	_attack_animation_active = false
	var moving := Vector2(velocity.x, velocity.z).length_squared() > 0.000001
	_set_locomotion_animation(moving)


## Index of the torso in `_bones()`. It is what the body comes to rest on, so
## its radius is the one measurement the fall needs back out of the skeleton.
const BONE_TORSO := 1
## Flat on its back: a quarter turn from standing.
const FLAT := TAU * 0.25

## The skeleton, in the body's own space: y runs from -height/2 at the soles to
## +height/2 at the crown, and x is its right. Each bone is a capsule given as
## two end points and a radius, so the proportions are all fractions of the one
## height and the whole figure scales with the size it was told to be.
##
## The arms set the width: their hands reach exactly `radius` out, so the
## silhouette really is as wide as the size it claims rather than that wide plus
## whatever a cuff happened to add.
func _bones() -> Array:
	var h := height
	var half := h * 0.5
	var arm_radius := h * 0.035
	var hand_x := radius - arm_radius
	var head_radius := h * 0.075
	var leg_radius := h * 0.045
	# How far the hands come forward. Enough to read as reaching for you from
	# down the street, short of turning the figure into a slab.
	var reach := h * 0.13
	return [
		# Head: a capsule with no barrel is a sphere, and its crown is the top
		# of the whole figure.
		[Vector3(0.0, half - head_radius, 0.0), Vector3(0.0, half - head_radius, 0.0), head_radius],
		[Vector3(0.0, h * 0.30, 0.0), Vector3(0.0, 0.0, 0.0), h * 0.09],
		[Vector3(-h * 0.055, 0.0, 0.0), Vector3(h * 0.055, 0.0, 0.0), h * 0.07],
		# Arms, shoulder to hand, out and down and reaching forward. The reach
		# is what gives the figure a front at all: every other bone is on the
		# x-y plane, so without it the body is symmetric back to front and there
		# is no way to tell which way it is facing until it falls over.
		[Vector3(-h * 0.10, h * 0.27, 0.0), Vector3(-hand_x, h * 0.02, -reach), arm_radius],
		[Vector3(h * 0.10, h * 0.27, 0.0), Vector3(hand_x, h * 0.02, -reach), arm_radius],
		# Legs, hip to sole. Their feet are the bottom of the figure, and are
		# set a little forward of the hips for the same reason.
		[Vector3(-h * 0.05, 0.0, 0.0), Vector3(-h * 0.06, -half + leg_radius, -h * 0.02), leg_radius],
		[Vector3(h * 0.05, 0.0, 0.0), Vector3(h * 0.06, -half + leg_radius, -h * 0.02), leg_radius],
	]


## Every bone's capsule baked into one mesh, in the body's space. Baked rather
## than parented: the shader reads `VERTEX`, which is the mesh's own space, so a
## part left sitting on its own node transform would unwrap about its own centre
## and slide its share of the stain.
func _welded_mesh(bones: Array) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for bone in bones:
		var span: Vector3 = bone[1] - bone[0]
		var bone_radius: float = bone[2]
		var capsule := CapsuleMesh.new()
		capsule.radius = bone_radius
		capsule.height = span.length() + bone_radius * 2.0
		capsule.radial_segments = 12
		capsule.rings = 6
		var arrays: Array = capsule.get_mesh_arrays()
		var placement := Transform3D(_aligned_basis(span), (bone[0] + bone[1]) * 0.5)
		var offset := vertices.size()
		for vertex in arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array:
			vertices.push_back(placement * vertex)
		for normal in arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array:
			normals.push_back(placement.basis * normal)
		for index in arrays[Mesh.ARRAY_INDEX] as PackedInt32Array:
			indices.push_back(index + offset)

	var surface := []
	surface.resize(Mesh.ARRAY_MAX)
	surface[Mesh.ARRAY_VERTEX] = vertices
	surface[Mesh.ARRAY_NORMAL] = normals
	surface[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)
	return mesh


## Orthonormal basis whose +y runs along `span`, which is the axis a capsule is
## built on. Right-handed, so the baked normals and winding stay the way the
## capsule generated them.
func _aligned_basis(span: Vector3) -> Basis:
	if span.length_squared() < 0.0000001:
		return Basis()
	var y_axis := span.normalized()
	var reference := Vector3.FORWARD if absf(y_axis.z) < 0.9 else Vector3.RIGHT
	var x_axis := reference.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, x_axis.cross(y_axis))


## A fraction of whatever the players walk at, rather than a speed of its own:
## the interesting number is how it compares to the player, and that stays true
## if the player's speed is retuned.
func match_player_speed(walk_speed: float, fraction: float) -> void:
	move_speed = walk_speed * fraction


## Standing height off the floor, for dropping one in without burying it.
func stand_height() -> float:
	return height * 0.5


func is_alive() -> bool:
	return health > 0.0


func health_fraction() -> float:
	return clampf(health / maxf(max_health, 0.001), 0.0, 1.0)


## A strand point landed on it. Returns true if that was the hit that killed it,
## so the world can take it out of the fight in one place rather than polling.
func take_sauce_hit() -> bool:
	if not is_alive():
		return false
	health = maxf(health - sauce_damage_per_hit, 0.0)
	if is_alive():
		return false
	# The soles it is standing on, on the ground: the line it goes over.
	_fall_pivot = global_position - Vector3.UP * (height * 0.5)
	_play_death_animation()
	return true


## Goes over backwards about its own feet. The feet stay where they were planted
## and the body swings up and back over them, so it lands on its back with its
## soles still on the spot it died on -- rather than rotating about its middle,
## which drives its head through the floor and slides its feet out behind it.
##
## The extra lift is what keeps it resting on the ground rather than sunk into
## it: standing, the body's centre is half its height above the soles; flat, it
## is the torso's own thickness above them, and the sine carries it between the
## two in step with the rotation.
func _advance_fall(delta: float) -> void:
	if fall_angle >= FLAT:
		return
	fall_angle = minf(fall_angle + FLAT / maxf(fall_duration, 0.01) * delta, FLAT)
	_apply_pose()


## Writes `facing_yaw` and `fall_angle` onto the node. The yaw is applied first
## and the topple second, so the topple is about the body's own right axis --
## it falls onto its own back whichever way it happened to be looking.
func _apply_pose() -> void:
	var pose := Basis(Vector3.UP, facing_yaw) * Basis(Vector3.RIGHT, fall_angle)
	if fall_angle <= 0.0:
		global_transform = Transform3D(pose, global_position)
		return
	global_transform = Transform3D(pose, _fall_pivot
		+ pose.y * (height * 0.5)
		+ Vector3.UP * (_rest_radius * sin(fall_angle)))


func paint_mayo(world_position: Vector3, world_normal: Vector3) -> Vector2i:
	if contamination == null:
		return Vector2i(-1, -1)
	return contamination.paint_mayo(world_position, world_normal)


func paint_mayo_cell(cell: Vector2i) -> void:
	if contamination != null:
		contamination.paint_mayo_cell(cell)


func cells_md5() -> String:
	return contamination.cells_md5() if contamination != null else ""


func snapshot_cells() -> PackedByteArray:
	return contamination.snapshot_cells() if contamination != null else PackedByteArray()


func restore_cells(cells: PackedByteArray) -> bool:
	return contamination != null and contamination.restore_cells(cells)


## Where the server puts it, which way it is looking, how hurt it is, and how
## far over it has gone. The same shape as the player's state packet and for the
## same reason: enough to place the body, plus what the other screens have to
## agree about. The topple travels as its angle rather than as a "it died" flag,
## so a peer that joins or drops a packet mid-fall picks it up where it is
## instead of snapping it upright or flat.
func network_state() -> Array:
	return [global_position, facing_yaw, health, fall_angle]


func apply_network_state(new_position: Vector3, yaw: float, new_health: float,
		new_fall_angle: float) -> void:
	var was_alive := is_alive()
	var travelled := Vector2(new_position.x - global_position.x,
		new_position.z - global_position.z).length_squared()
	facing_yaw = yaw
	fall_angle = new_fall_angle
	health = new_health
	# The position is the server's outright, so the pose is written around it
	# rather than derived from a pivot this peer never saw.
	global_transform = Transform3D(
		Basis(Vector3.UP, facing_yaw) * Basis(Vector3.RIGHT, fall_angle), new_position)
	if was_alive and not is_alive():
		_play_death_animation()
	elif is_alive():
		_set_locomotion_animation(travelled > 0.000001)


## Walks at `targets`' nearest member and hits it when it gets there. Returns
## the player it damaged this frame, or null -- the world owns what damage does,
## because on a client the answer is "nothing, wait for the packet".
func advance(delta: float, targets: Array) -> MayoPlayer:
	if not authority:
		return null
	if not is_alive():
		# Dead ones are not skipped -- they are still going over.
		_advance_fall(delta)
		return null
	_contact_cooldown = maxf(_contact_cooldown - delta, 0.0)

	var target := _nearest(targets)
	var flat := Vector3.ZERO
	if target != null:
		flat = target.global_position - global_position
		flat.y = 0.0

	if flat.length_squared() > 0.000001:
		var direction := flat.normalized()
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
		# Turned toward the player rather than snapped: a snap makes it read as
		# a camera-facing sprite, and the stain on its back is worth seeing.
		# A body's front is its -z, so facing a direction is atan2 of its
		# negation -- the same form `debug_aim_at` uses to point the player at
		# something. Facing `atan2(direction.x, direction.z)` instead turns its
		# *back* to the target: it walks at you backwards, and then topples onto
		# that back, which looks for all the world like falling forwards.
		facing_yaw = rotate_toward(facing_yaw,
			atan2(-direction.x, -direction.z), turn_speed * delta)
		_apply_pose()
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= fall_gravity * delta
	move_and_slide()
	_set_locomotion_animation(Vector2(velocity.x, velocity.z).length_squared() > 0.000001)

	if target == null or _contact_cooldown > 0.0:
		return null
	# Measured between the capsule axes, flat: both bodies are capsules, so the
	# gap between their surfaces is the axis distance less the two radii.
	var reach := radius + _target_radius(target) + contact_reach
	var gap := Vector3(target.global_position.x - global_position.x, 0.0,
		target.global_position.z - global_position.z)
	if gap.length() > reach:
		return null
	_contact_cooldown = contact_interval
	_play_attack_animation()
	return target


func _nearest(targets: Array) -> MayoPlayer:
	var best: MayoPlayer = null
	var best_distance := INF
	for candidate in targets:
		var player := candidate as MayoPlayer
		if player == null or not is_instance_valid(player):
			continue
		var distance := global_position.distance_squared_to(player.global_position)
		if distance < best_distance:
			best_distance = distance
			best = player
	return best


func _target_radius(player: MayoPlayer) -> float:
	if player.contamination != null:
		return player.contamination.radius
	return 0.64
