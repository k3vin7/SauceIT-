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
const GaitScript := preload("res://scripts/enemy_gait.gd")
const HAMBURGER_MONSTER := preload(
	"res://assets/enemies/hamburger_monster/hamburger_monster.glb")
## Evaluated mesh bounds in the authored Blender file, in metres. Scaling by
## this keeps the visible monster's soles and crown aligned with the legacy
## gameplay body's exact height.
const MODEL_SOURCE_HEIGHT := 1.7729597
## The height the proportions in `_bones` are written as fractions of.
const MODEL_HEIGHT := 4.1

@export_group("Health")
@export_range(10.0, 2000.0, 1.0) var max_health := 240.0
## What `max_health` is for one player. `max_health` itself is rewritten as
## people join and leave, so the figure the scaling multiplies has to be kept
## somewhere it is not: scaling off `max_health` would compound, and a party
## that gained and lost a player would leave a heavy permanently tougher.
var solo_health := 240.0
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
## How often the route is worked out again. Every frame is waste -- a route is
## still good while the player is in the same part of the street -- and never is
## a chase that follows you to where you used to be.
@export_range(0.05, 3.0, 0.05, "suffix:s") var repath_interval := 0.5
## How close to a waypoint counts as having reached it, **as a fraction of a
## lattice cell** rather than in metres.
##
## Metres was wrong, and wrong in a way that only showed when the map changed
## size. 1.6 m was about seven tenths of a cell when a cell was 2.3 m; the
## street was then widened and a cell became 4.6 m, leaving the same 1.6 m at
## barely a third of one. A body could then stand between two waypoints,
## be "not yet at" either, and be handed back a waypoint it had already walked
## past every time the route was redrawn -- so it orbited, at full walking
## speed, never getting closer. Tying it to the cell is what stops the next
## change of scale doing it again.
@export_range(0.2, 2.0, 0.05, "suffix:cells") var waypoint_reached_cells := 0.7

@export_group("What it notices")
## How close a player has to get before it starts coming for them.
##
## Without this every body on the map walks at you from the moment the world
## loads: `_nearest` has no notion of distance beyond picking the closest, so a
## monster three streets away sets off just the same as one in the next doorway.
@export_range(1.0, 200.0, 0.5, "suffix:m") var sight_range := 26.0
## And how far away they have to get before it gives up and settles again.
##
## **Deliberately larger than `sight_range`.** With one distance for both, a
## player standing on the line makes the body start and stop several times a
## second; the gap between the two is what stops that, and it doubles as the
## chase having some commitment to it.
@export_range(1.0, 300.0, 0.5, "suffix:m") var give_up_range := 44.0
## Whether being hit wakes it regardless of range. A body being hosed from
## outside its own sight is being told where you are.
@export var sauce_alerts := true
## Draws the two ranges on the ground as rings, the way a tutorial draws a
## tower's reach. **A development aid** -- it is off in a built game unless
## something turns it on, and `MayoPrototype` does so from one place.
@export var show_sight_rings := false:
	set(value):
		show_sight_rings = value
		_refresh_sight_rings()
@export var sight_ring_color := Color(0.95, 0.15, 0.15, 0.85)
@export var give_up_ring_color := Color(0.95, 0.45, 0.15, 0.35)

@export_group("Its charge")
## How hard a contact hit throws the player, flat and upward. **Zero on the
## bruiser**, which lands a bite rather than a charge; the rusher runs into you
## and the shove is the point of it.
@export_range(0.0, 30.0, 0.1, "suffix:m/s") var impact_push_speed := 0.0
@export_range(0.0, 15.0, 0.1, "suffix:m/s") var impact_lift_speed := 0.0

@export_group("Its attack")
## Weak on purpose. At one hit every `contact_interval` this is about 7 damage a
## second, so a player who walks into one and stays there has a good while to
## notice and get out.
@export_range(0.0, 100.0, 0.5) var contact_damage := 6.0
@export_range(0.1, 5.0, 0.05, "suffix:s") var contact_interval := 0.8
## Beyond the two capsule radii. Its arms are not modelled, so this stands in
## for them.
@export_range(0.0, 3.0, 0.05, "suffix:m") var contact_reach := 0.5

## The two kinds a body can be. Minions die to a squirt and never stagger;
## heavies soak a party's worth of sauce and flinch on the way down.
enum Grade { MINION, HEAVY }

## Which of the two bodies this is. The bruiser is the hamburger: slow, heavy,
## and built by `build`. The rusher is the moldy toast: small, quick, low on
## health, and built by `build_moldy_toast_rusher`. They share everything else
## -- the chase, the contamination, the topple and the state packet -- because
## the difference between them is proportions and numbers, not behaviour.
enum EnemyKind { BRUISER, MOLDY_TOAST_RUSHER }

@export_group("Its kind")
## What this one counts as. It changes nothing on its own -- what reads it is
## the flinch list below and the world's health scaling -- but it is the one
## place that says which of the two a body is, so neither has to guess from a
## health figure.
@export var grade: Grade = Grade.HEAVY
## Set by whichever builder ran. Read where the two genuinely differ: which
## clip to play, and whether a contact hit shoves the player.
var kind := EnemyKind.BRUISER
## The contamination fractions that make it flinch as they are crossed. **A
## minion's is empty**: small things do not stagger, they just die. A heavy's
## default is a quarter, a half and three quarters.
##
## Crossing two in one frame is still one flinch: what the player did was land
## one burst, and staggering twice for it reads as a stutter.
@export var flinch_thresholds: Array[float] = [0.25, 0.5, 0.75]

@export_group("Going down")
## Long enough to read as toppling rather than as being deleted.
@export_range(0.1, 4.0, 0.05, "suffix:s") var fall_duration := 0.9
## How far back it rocks when it bounces off the ground, as a share of the full
## topple. Zero lands it dead flat with no bounce at all.
@export_range(0.0, 0.5, 0.005) var fall_bounce := 0.06
## And how long that bounce takes to play out, once the body is down.
@export_range(0.0, 2.0, 0.01, "suffix:s") var fall_bounce_seconds := 0.22
## Where the lowest part of the body ends up once it has settled: this far above
## whatever it came to rest on.
@export_range(0.0, 0.2, 0.001, "suffix:m") var ground_clearance := 0.02

@export_group("Being hosed")
## How hard a stream landing on it shoves it back, in metres a second.
##
## **This is the continuous answer to a continuous weapon.** A flinch is an
## event, and a stream has no events -- 187 points land a second and no single
## one of them means anything. Being pushed while the sauce is on you, and
## walking again the moment it comes off, is force the player can read at any
## instant rather than at three arbitrary percentages.
## Above `move_speed` on purpose, so a body being hosed actually goes backwards
## instead of leaning in. Below it the shove is invisible exactly when it is
## wanted -- at full health, on the first engagement -- because the walk simply
## out-runs it.
##
## What keeps it from making a player unkiteable is the **bottle**, not the
## reach: a burst runs about a second and then the nozzle is shut for
## `spent_burst_cooldown`, and the body closes through every one of those gaps.
## The push and the gap are the rhythm of the fight. Worth re-checking whenever
## `stream_range` moves -- it was doubled once already, and a longer reach means
## more of the push happens before the body is out of it.
@export_range(0.0, 20.0, 0.1, "suffix:m/s") var shove_speed := 4.8
## How quickly the shove dies once the stream comes off. Short: the tell is that
## it starts walking again, and a long tail blurs the moment it does.
@export_range(0.02, 2.0, 0.01, "suffix:s") var shove_decay_seconds := 0.16
## How much of its walk it loses at full contamination. At 0.6 a nearly ruined
## body moves at 40% of its speed -- so the fight visibly winds down rather than
## ending at a threshold.
@export_range(0.0, 1.0, 0.05) var soiled_slowdown := 0.55

@export_group("Flinching")
## How far it rocks back when a threshold is crossed.
@export_range(0.0, 45.0, 0.5, "suffix:°") var flinch_degrees := 9.0
## And how long the whole rock-back-and-recover takes.
@export_range(0.05, 1.0, 0.01, "suffix:s") var flinch_seconds := 0.18

@export_group("Its walk")
## How long the gait takes to come on or go off. Faded rather than switched: cut
## at the moment a monster stops, it freezes mid-step with one elbow bent.
@export_range(0.05, 2.0, 0.05, "suffix:s") var gait_settle_seconds := 0.25

## Whether to plant the hands and solve the arms back from them. The modifier
## keeps the palm at its authored floor height and lowers the body just enough
## to give the short arms a usable, bent reach.
@export var procedural_gait := true

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

## Set by the world once the street exists. Without it the enemy walks the
## straight line, which is what it did before there was any routing at all.
var nav: StreetNav

var _contact_cooldown := 0.0
var _route := PackedVector3Array()
var _route_step := 0
var _repath_timer := 0.0
var _route_goal := Vector3.ZERO
var _body_mesh: MeshInstance3D
var _gait: Node
## How far the monster has walked, in metres. The gait's phase comes off this
## rather than off a clock, so its hands keep pace with the ground instead of
## sliding along it -- which is most of what paddling looks like.
var _ground_covered := 0.0
var _visual_root: Node3D
var _animation_player: AnimationPlayer
var _idle_animation := &""
var _walk_animation := &""
var _attack_animation := &""
var _attack_animation_active := false
## How far through the flinch it is, in seconds, counting down. The flinch is
## driven **through `fall_angle`** rather than through a field of its own, so it
## needs nothing added to the state packet: the angle already travels.
## Where the stream is currently pushing it, in metres a second, decaying.
var _shove := Vector3.ZERO
## Whether it has noticed anybody. Latched rather than recomputed from the
## distance every frame -- see `give_up_range`.
var _alerted := false
var _sight_ring: MeshInstance3D
var _give_up_ring: MeshInstance3D
var _flinch_left := 0.0
## The highest threshold already crossed, so each one fires once. Held as an
## index into `flinch_thresholds` rather than as a fraction, because the list is
## what the designer edits.
var _flinch_crossed := 0
## Seconds since the body reached the ground, for the bounce.
var _settled_for := 0.0
## World point the feet were planted on when it died -- the axis it goes over.
var _fall_pivot := Vector3.ZERO
## Half the thickness of the torso: what it comes to rest on.
var _rest_radius := 0.37


func _ready() -> void:
	_refresh_sight_rings()
	add_to_group("mayo_enemy")
	# What the strand looks for. Being in this group is what makes sauce stick.
	add_to_group("mayo_contaminable")


## The body: its bones as colliders, its bones welded into one mesh, and the
## contamination grid wrapped round the whole silhouette. `body_color` is the
## grid's clean colour, so the stain and the skin are one material.
func build(cell_size: float, brush_radius: float, body_color: Color) -> void:
	# Whatever the scene or the inspector set is the one-player figure; the party
	# scaling multiplies up from here and never from the scaled value.
	solo_health = max_health
	health = max_health
	var station: Vector3 = StreetMap.VENDING_SIZE
	height = station.y * HEIGHT_MULTIPLE
	# The burger is very nearly as wide as it is tall, so its width comes
	# from the model rather than from the refill station it is sized against.
	radius = _body_radius()

	var bones := _bones()
	_rest_radius = _body_radius()

	# One collider per bone rather than one capsule around the lot. A single
	# capsule wide enough to cover the outstretched arms is a fat pill that
	# nothing could walk past, and sauce aimed at an arm would land on thin air
	# a metre outside it. Per bone, the silhouette you can see is the silhouette
	# you can hit.
	for index in bones.size():
		var bone: Dictionary = bones[index]
		var collision := CollisionShape3D.new()
		collision.name = BONE_NAMES[index] if index < BONE_NAMES.size() else "Part%d" % index
		if bone["kind"] == "disc":
			var disc := CylinderShape3D.new()
			disc.radius = bone["radius"]
			disc.height = bone["height"]
			collision.shape = disc
			collision.transform = Transform3D(Basis(), bone["centre"])
		else:
			var span: Vector3 = bone["b"] - bone["a"]
			var capsule := CapsuleShape3D.new()
			capsule.radius = bone["radius"]
			capsule.height = span.length() + bone["radius"] * 2.0
			collision.shape = capsule
			collision.transform = Transform3D(_aligned_basis(span), (bone["a"] + bone["b"]) * 0.5)
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
	# The burger sits back of its own node, and the unwrap turns about an
	# axis. Turning about the node instead skews a stain by up to ten degrees
	# around the flanks -- which is exactly where anyone aims.
	contamination.axis_offset = Vector3(0.0, 0.0, -0.0756 * height)
	# A burger has a flat top and a flat bottom, and the side chart cannot
	# draw either: it keeps a point's angle and its height and throws the
	# radius away, so a stain on the crown comes out as a streak from the
	# middle to the rim. The caps are polar charts stacked above and below
	# the side band in the same mask, which is why this costs nothing on the
	# wire. A player leaves this at zero: their ends are hemispheres.
	contamination.cap_depth = _body_radius()
	add_child(contamination)
	# The unwrap maps a surface point by its angle about the body's axis, which
	# is an honest unwrap only for a surface of revolution. A burger very nearly
	# is one -- three stacked discs -- which is the one thing that got easier
	# when the humanoid figure it replaced went away: that one grew arms and
	# stopped being a solid of revolution the moment it did.
	#
	# The radius handed over is the widest the burger gets, the patty. It sets
	# how much grid a metre of surface is worth, so handing over the wrong one
	# silently rescales every stain on the body -- half an arm span instead of
	# a torso once rendered a 0.40 m splat at 0.13 m, which is why a hit on one
	# of these looked nothing like a hit on a player. `probe_enemy` measures
	# the rendered width against a player's rather than trusting the number.
	#
	# What the unwrap still cannot do is a top or a bottom: every point on the
	# crown of the bun at the same angle shares one texel whatever its radius,
	# so a stain up there draws as a radial streak rather than a blob. It does
	# not show while the monster is upright and you are looking at its side. It
	# shows when it topples and the crown turns to face you.
	contamination.configure(self, _body_mesh, _body_radius(), height, body_color)
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
	_animation_player.animation_finished.connect(_on_animation_finished)

	# `EnemyGait` plants the hands and solves the arms back from them. The rig's
	# arms are too short to move fore and aft while the body stays at its authored
	# height, so the modifier adds a small support crouch to the body instead of
	# lifting the plant point into the air. That preserves the floor contact and
	# gives the elbows room to bend under load.
	if procedural_gait:
		for node in _visual_root.find_children("*", "Skeleton3D", true, false):
			_gait = GaitScript.new()
			_gait.name = "Gait"
			node.add_child(_gait)
			break


## The moldy toast rusher: small, quick, and it charges rather than bites.
##
## Built beside `build` rather than inside it. The two share every system that
## matters -- the chase, the contamination unwrap, the topple, the state packet
## -- and differ only in proportions, numbers and which clips exist, so the
## fork is kept to the one function that sets those.
##
## It is a **minion**: `flinch_thresholds` is empty. Small things do not
## stagger, they die, and at 52 health a squirt puts one down.
func build_moldy_toast_rusher(cell_size: float, brush_radius: float,
		visual_scene: PackedScene) -> void:
	kind = EnemyKind.MOLDY_TOAST_RUSHER
	grade = Grade.MINION
	flinch_thresholds = []
	radius = 0.675
	height = 1.10
	_rest_radius = 0.15
	max_health = 52.0
	solo_health = max_health
	health = max_health
	sauce_damage_per_hit = 0.65
	turn_speed = 9.0
	contact_damage = 9.0
	contact_interval = 0.9
	contact_reach = 0.18
	fall_duration = 0.55
	# It spots you from further than a bruiser does and it closes at 8.6 m/s,
	# which is what makes it a rusher rather than a small bruiser. The bruiser's
	# 26 m at 3.6 m/s is a long slow walk; this is a charge.
	sight_range = 34.0
	give_up_range = 55.0
	impact_push_speed = 7.5
	impact_lift_speed = 2.0
	# It weighs nothing, so the hose throws it further than it throws a burger.
	shove_speed = 9.0

	# The toast is a thin slab. Two compact capsules cover its body and feet
	# without turning its collision into the much wider original humanoid.
	for spec in [
		[Vector3(0.0, -0.30, 0.0), Vector3(0.0, 0.30, 0.0), 0.32],
		[Vector3(-0.22, -0.47, -0.04), Vector3(-0.22, -0.47, -0.04), 0.18],
		[Vector3(0.22, -0.47, -0.04), Vector3(0.22, -0.47, -0.04), 0.18],
	]:
		var shape := CapsuleShape3D.new()
		var span: Vector3 = spec[1] - spec[0]
		shape.radius = spec[2]
		shape.height = span.length() + spec[2] * 2.0
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.transform = Transform3D(_aligned_basis(span), (spec[0] + spec[1]) * 0.5)
		add_child(collision)

	# The mask target, hidden, exactly as the bruiser keeps its capsule mock-up:
	# the sauce grid is unwrapped from a shape that does not animate.
	_body_mesh = MeshInstance3D.new()
	_body_mesh.name = "EnemyBody"
	var slab := BoxMesh.new()
	slab.size = Vector3(radius * 2.0, height, radius * 0.6)
	_body_mesh.mesh = slab
	_body_mesh.visible = false
	add_child(_body_mesh)

	_visual_root = visual_scene.instantiate() as Node3D
	if _visual_root == null:
		push_error("Moldy toast rusher scene did not instantiate as Node3D")
		return
	_visual_root.name = "MoldyToastVisual"
	# Blender assets are ground-origin; MayoEnemy is centre-origin so its fall
	# pivot and contact math stay compatible with the bruiser. The GLB's face
	# points along +Z after Blender's axis conversion, while gameplay moves
	# enemies along their -Z front, so turn only the visual half a revolution.
	_visual_root.position.y = -stand_height()
	_visual_root.rotation.y = PI
	add_child(_visual_root)

	var players := _visual_root.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		_animation_player = players[0] as AnimationPlayer
		_idle_animation = _find_animation("Idle", false)
		_walk_animation = _find_animation("Run", false)
		if _walk_animation.is_empty():
			_walk_animation = _find_animation("Walk", false)
		_attack_animation = _find_animation("Ram", false)
		if _attack_animation.is_empty():
			_attack_animation = _find_animation("Attack", false)
		if _idle_animation.is_empty():
			_idle_animation = _walk_animation
		_animation_player.animation_finished.connect(_on_animation_finished)

	contamination = BodyContamination.new()
	contamination.name = "BodyContamination"
	contamination.cell_size = cell_size
	contamination.brush_radius = brush_radius
	# A slab, not a burger: no flat crown worth its own polar chart, and the
	# body sits on its own axis, so both corrections the bruiser needs are off.
	add_child(contamination)
	contamination.configure(self, _body_mesh, radius, height, Color("56651b"))
	# The same per-mesh rest matrix the bruiser uses, captured once at build --
	# not a live world-to-body inverse pushed every frame, which slides the
	# stain off anything that animates.
	contamination.add_visual_overlay(_visual_root)
	_play_animation(_idle_animation)


## `required` is false for the rusher, whose rig has a different set of clips:
## a missing one there is a fallback, not a fault.
func _find_animation(suffix: String, required := true) -> StringName:
	if _animation_player == null:
		return &""
	for animation in _animation_player.get_animation_list():
		if String(animation).to_lower().ends_with(suffix.to_lower()):
			return animation
	if required:
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
	# `fall_angle` turns the gameplay body, its colliders and the visual together.
	# The imported Death clip also translates, rotates and scales the Body bone
	# and throws both arms elsewhere. Playing both made the visible corpse fall a
	# second time inside its already-fallen collision body, so a new hit was
	# recorded at the collider and drawn metres away on the animated mesh.
	#
	# The gait is a walk, and this is not one. Stop every animation write and put
	# the rig back in the same rest pose its fixed colliders and contamination
	# projection were authored from; the procedural node fall supplies the whole
	# death motion and travels over the network as `fall_angle`.
	if _gait != null:
		_gait.strength = 0.0
	if _animation_player != null:
		_animation_player.speed_scale = 1.0
		_animation_player.stop()
	# There is deliberately **no Death clip lookup**. The imported one rocks the
	# body 40 degrees to its own left and stops there, never reaching the floor,
	# while translating and scaling the Body bone -- so played over the node
	# fall it toppled the corpse a second time inside its already-toppled
	# collider, and a hit recorded at the collider was drawn metres away on the
	# mesh. The node fall is the whole death motion.
	if _visual_root != null:
		for node in _visual_root.find_children("*", "Skeleton3D", true, false):
			(node as Skeleton3D).reset_bone_poses()


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
const BONE_NAMES := ["BottomBun", "Fillings", "TopBun", "ArmLeft", "ArmRight",
	"HandLeft", "HandRight"]
## Flat on its back: a quarter turn from standing.
const FLAT := TAU * 0.25

## The body, in its own space: y runs from -height/2 at the soles to +height/2
## at the crown, and x is its right.
##
## **Measured off the monster, not invented.** These were a humanoid stick
## figure left over from the mock enemy the burger replaced -- head, torso,
## pelvis, two arms, two legs -- and a burger is nothing like that shape, so it
## was drawn 4.2 m across and solid over 1.9 m of it. Sauce aimed anywhere but
## its middle went straight through it.
##
## Every number below is the real extent of the parts it stands for, read out
## of the GLB **in the body's own space**. That last part matters: measured in
## world space an axis-aligned box grows with the body's yaw, and a collider
## that fits perfectly reads as half a metre too wide.
##
##     bottom bun            y -0.82 ..  0.63   radius 1.49
##     patty, cheese, salad  y -0.18 ..  0.86   radius 1.71
##     top bun and face      y  0.42 ..  2.04   radius 1.56
##     arms, shoulder-hand   y -2.08 ..  0.65   radius 0.46, at x +/-1.52
##     hands                 y -2.07 .. -1.11   radius 0.50, reaching forward
##
## The burger sits a third of a metre back of its own origin, which is why
## every disc is offset in z rather than centred.
##
## Three discs for the burger, because that is what a burger is and because the
## tiers are what a player aims at -- sauce should land on the bun or the patty
## and be seen to have. The arms are not decoration: the monster has no legs,
## it walks on its hands, so they carry every low shot.
##
## `kind` is "disc" (a cylinder: centre, radius, height) or "limb" (a capsule:
## two ends and a radius). A burger tier needs the cylinder -- a capsule wide
## enough to be a bun is also that tall.
func _bones() -> Array:
	var h := height
	var cz := -0.0756 * h
	return [
		{"kind": "disc", "centre": Vector3(0.0, -0.0244 * h, cz),
			"radius": 0.3634 * h, "height": 0.3561 * h},
		{"kind": "disc", "centre": Vector3(0.0, 0.0829 * h, cz),
			"radius": 0.4171 * h, "height": 0.2537 * h},
		{"kind": "disc", "centre": Vector3(0.0, 0.3000 * h, cz),
			"radius": 0.3805 * h, "height": 0.3951 * h},
		# The end points are pulled in by one radius each, because a capsule's
		# caps reach that far past them -- given the shoulder and the knuckle
		# as they measure, the shape overhangs both by half a metre.
		{"kind": "limb", "a": Vector3(-0.3707 * h, 0.0463 * h, -0.0366 * h),
			"b": Vector3(-0.3707 * h, -0.3951 * h, -0.1732 * h), "radius": 0.1122 * h},
		{"kind": "limb", "a": Vector3(0.3707 * h, 0.0463 * h, -0.0366 * h),
			"b": Vector3(0.3707 * h, -0.3951 * h, -0.1732 * h), "radius": 0.1122 * h},
		# The hands, which the arms' own capsules stop short of: the fingers
		# reach forward past them, and a shot at the knuckles met nothing.
		# Given per side rather than mirrored, because the model's hands are
		# posed differently and mirroring one onto the other misses by 0.2 m.
		{"kind": "limb", "a": Vector3(0.4357 * h, -0.3884 * h, -0.0316 * h),
			"b": Vector3(0.4357 * h, -0.3884 * h, -0.2268 * h), "radius": 0.1220 * h},
		{"kind": "limb", "a": Vector3(-0.3904 * h, -0.3886 * h, -0.0869 * h),
			"b": Vector3(-0.3904 * h, -0.3886 * h, -0.2821 * h), "radius": 0.1220 * h},
	]


## The half-width the unwrap wraps the body around, and what `contact_reach` is
## measured beyond: the widest the burger gets, which is the patty, not a
## shoulder and not the arms.
func _body_radius() -> float:
	return 0.4171 * height


## Every bone's capsule baked into one mesh, in the body's space. Baked rather
## than parented: the shader reads `VERTEX`, which is the mesh's own space, so a
## part left sitting on its own node transform would unwrap about its own centre
## and slide its share of the stain.
func _welded_mesh(bones: Array) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for bone in bones:
		var arrays: Array
		var placement: Transform3D
		if bone["kind"] == "disc":
			var disc := CylinderMesh.new()
			disc.top_radius = bone["radius"]
			disc.bottom_radius = bone["radius"]
			disc.height = bone["height"]
			disc.radial_segments = 16
			disc.rings = 1
			arrays = disc.get_mesh_arrays()
			placement = Transform3D(Basis(), bone["centre"])
		else:
			var span: Vector3 = bone["b"] - bone["a"]
			var capsule := CapsuleMesh.new()
			capsule.radius = bone["radius"]
			capsule.height = span.length() + bone["radius"] * 2.0
			capsule.radial_segments = 12
			capsule.rings = 6
			arrays = capsule.get_mesh_arrays()
			placement = Transform3D(_aligned_basis(span), (bone["a"] + bone["b"]) * 0.5)
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
## `from` is where the hit came from, so a killing one can turn the body to face
## it. `Vector3.INF` means "not stated", which is what the checks that call this
## without a shooter pass.
func take_sauce_hit(from := Vector3.INF) -> bool:
	if not is_alive():
		return false
	health = maxf(health - sauce_damage_per_hit, 0.0)
	# Being hit is being told where you are, whatever the range says.
	if sauce_alerts:
		_alerted = true
	if is_alive():
		_note_flinch()
		return false
	# Turned to face whoever landed the last hit, so the topple -- which is
	# always onto its own back -- takes it away from them rather than in
	# whatever direction it happened to be walking. Done before the pivot is
	# taken, since the pivot is read off the pose.
	if from != Vector3.INF:
		var away := Vector3(from.x - global_position.x, 0.0, from.z - global_position.z)
		if away.length_squared() > 0.000001:
			facing_yaw = atan2(-away.x, -away.z)
	# The soles it is standing on, on the ground: the line it goes over.
	_fall_pivot = global_position - Vector3.UP * (height * 0.5)
	# A flinch under way is abandoned rather than finished: it is going over now.
	_flinch_left = 0.0
	_settled_for = 0.0
	_play_death_animation()
	return true


## True if this hit crossed a threshold, having started the flinch if it did.
##
## Contamination is counted **up** -- 0 clean, 1 ruined -- so the list reads the
## way the designer wrote it. `health` runs the other way, which is why this is
## one minus the health fraction rather than the fraction itself.
##
## Several thresholds crossed by one hit still start one flinch: `_flinch_crossed`
## walks to the last one passed rather than firing per step.
func _note_flinch() -> bool:
	if flinch_thresholds.is_empty():
		return false
	var soiled := 1.0 - health_fraction()
	var crossed := _flinch_crossed
	while crossed < flinch_thresholds.size() and soiled >= flinch_thresholds[crossed]:
		crossed += 1
	if crossed == _flinch_crossed:
		return false
	_flinch_crossed = crossed
	_flinch_left = flinch_seconds
	return true


## Sauce is landing on it from `from`, so it is pushed away from there.
##
## Set rather than accumulated: every one of the stream's points would otherwise
## pile onto the last, and the shove would depend on the frame rate and the
## point density rather than on whether the stream is on the body. Refreshed
## while it is being hit and decaying the moment it is not is the whole effect.
##
## Authority only -- the position it moves is what travels.
func take_shove(from: Vector3) -> void:
	if not authority or not is_alive():
		return
	var away := Vector3(global_position.x - from.x, 0.0, global_position.z - from.z)
	if away.length_squared() < 0.000001:
		return
	_shove = away.normalized() * shove_speed


## Whether it has noticed a player and is coming for them.
func is_alerted() -> bool:
	return _alerted


## A flat annulus on the XZ plane: the ring itself, not a filled disc, so what
## is inside it stays readable.
static func _ring_mesh(ring_radius: float, thickness: float) -> ArrayMesh:
	const SEGMENTS := 72
	var vertices := PackedVector3Array()
	var inner := maxf(ring_radius - thickness * 0.5, 0.01)
	var outer := ring_radius + thickness * 0.5
	for step in SEGMENTS:
		var a := TAU * float(step) / float(SEGMENTS)
		var b := TAU * float(step + 1) / float(SEGMENTS)
		var a_in := Vector3(cos(a) * inner, 0.0, sin(a) * inner)
		var a_out := Vector3(cos(a) * outer, 0.0, sin(a) * outer)
		var b_in := Vector3(cos(b) * inner, 0.0, sin(b) * inner)
		var b_out := Vector3(cos(b) * outer, 0.0, sin(b) * outer)
		vertices.append_array([a_in, a_out, b_out, a_in, b_out, b_in])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _make_ring(ring_name: String, ring_radius: float, thickness: float,
		color: Color) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	ring.name = ring_name
	ring.mesh = _ring_mesh(ring_radius, thickness)
	# **Independent of this node's own transform.** `_apply_pose` turns the
	# whole body -- flinching and toppling included -- and a ring parented
	# normally would roll over with it. `top_level` cuts it loose, and
	# `_process` puts it back on the ground under the body every frame.
	ring.top_level = true
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = material
	add_child(ring)
	return ring


func _refresh_sight_rings() -> void:
	if not is_inside_tree():
		return
	if not show_sight_rings:
		if _sight_ring != null:
			_sight_ring.queue_free()
			_sight_ring = null
		if _give_up_ring != null:
			_give_up_ring.queue_free()
			_give_up_ring = null
		return
	if _sight_ring == null:
		_sight_ring = _make_ring("SightRing", sight_range, 0.35, sight_ring_color)
	if _give_up_ring == null:
		_give_up_ring = _make_ring("GiveUpRing", give_up_range, 0.2, give_up_ring_color)


func _process(_delta: float) -> void:
	if _sight_ring == null:
		return
	# Flat on the ground under the body, whatever the body is doing. A little
	# clear of it so it does not fight the street for the same pixels.
	var under := Vector3(global_position.x, global_position.y - stand_height() + 0.06,
		global_position.z)
	_sight_ring.global_transform = Transform3D(Basis(), under)
	_give_up_ring.global_transform = Transform3D(Basis(), under)
	# Lit up while it is actually coming for someone, so the two states can be
	# told apart at a glance.
	var tint := sight_ring_color
	tint.a = sight_ring_color.a if _alerted else sight_ring_color.a * 0.45
	(_sight_ring.material_override as StandardMaterial3D).albedo_color = tint


## True while it is rocking back from a threshold. The world asks so it can send
## the camera shake to whoever is hitting it.
func is_flinching() -> bool:
	return _flinch_left > 0.0


## Rocks back and recovers, writing `fall_angle` -- which is why nothing is
## added to the state packet for it. A half-sine: away from upright and back,
## reaching the full angle in the middle rather than at the end.
func _advance_flinch(delta: float) -> void:
	if _flinch_left <= 0.0:
		return
	_flinch_left = maxf(_flinch_left - delta, 0.0)
	var through := 1.0 - _flinch_left / maxf(flinch_seconds, 0.001)
	fall_angle = deg_to_rad(flinch_degrees) * sin(through * PI)
	_apply_pose()


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
	# Past the ground: the one small bounce, and then still.
	if _settled_for > 0.0 or fall_angle >= FLAT:
		_settled_for += delta
		if _settled_for >= fall_bounce_seconds or fall_bounce <= 0.0:
			fall_angle = FLAT
			_apply_pose()
			_settle_onto_ground()
			return
		# Back off the floor and settle again, once. A half sine, so it leaves
		# the ground and returns to it rather than stopping partway.
		var through := _settled_for / maxf(fall_bounce_seconds, 0.001)
		fall_angle = FLAT - FLAT * fall_bounce * sin(through * PI)
		_apply_pose()
		return
	# Fast off the mark and slowing into the floor, rather than the constant
	# rate this turned at before: a body going over accelerates under its own
	# weight at first, and what sells the landing is that it arrives quickly.
	var rate := FLAT / maxf(fall_duration, 0.01)
	var through_fall := fall_angle / FLAT
	fall_angle = minf(fall_angle + rate * (1.6 - 0.9 * through_fall) * delta, FLAT)
	if fall_angle >= FLAT:
		_settled_for = 0.0001
	_apply_pose()


## Writes `facing_yaw` and `fall_angle` onto the node. The yaw is applied first
## and the topple second, so the topple is about the body's own right axis --
## it falls onto its own back whichever way it happened to be looking.
## Walks the clip -- and the gait, when there is one -- forward by the ground
## actually covered rather than by the clock.
##
## The phase is a distance, so a monster slowed down or shoved takes shorter
## steps rather than the same steps faster -- the hands stay with the floor
## instead of skating over it. The clip is scaled by the same measure, for the
## same reason.
##
## `strength` is faded rather than switched. Snapping it off at the moment a
## monster stops leaves it mid-step with one elbow bent, which reads as a flinch.
func _advance_gait(step: Vector3, walking: bool, delta: float) -> void:
	var covered := Vector2(step.x, step.z).length()
	_ground_covered += covered
	if _gait != null:
		_gait.phase = _ground_covered / maxf(_gait.stride_in_use(), 0.01)
		_gait.strength = move_toward(_gait.strength, 1.0 if walking else 0.0,
			delta / maxf(gait_settle_seconds, 0.01))
	if _animation_player != null and not _attack_animation_active and is_alive():
		# The clip keeps pace with the ground too: at a standstill it idles at
		# its own rate, and walking it runs at the share of full speed the
		# monster is actually managing.
		var pace := 1.0
		if walking and move_speed > 0.01:
			pace = clampf(covered / maxf(delta, 0.0001) / move_speed, 0.25, 2.0)
		_animation_player.speed_scale = pace


func _apply_pose() -> void:
	var pose := Basis(Vector3.UP, facing_yaw) * Basis(Vector3.RIGHT, fall_angle)
	# **Alive, not `fall_angle <= 0`.** A flinch turns `fall_angle` too, and the
	# pivot below is the spot the feet were planted on when it *died* -- unset
	# while it is still up. Branching on the angle sent a flinching body to the
	# world origin, because that is where an unset pivot is.
	if is_alive():
		global_transform = Transform3D(pose, global_position)
		return
	global_transform = Transform3D(pose, _fall_pivot
		+ pose.y * (height * 0.5)
		+ Vector3.UP * (_rest_radius * sin(fall_angle)))


## Lifts the settled body until nothing of it is through the floor.
##
## The topple is an arc about the feet with a fixed allowance for the torso's
## thickness, which is right on flat ground and wrong everywhere else -- a body
## that dies on a kerb, on a ramp or half under a stall counter arrives with
## part of itself inside the geometry. So once it is down, the three bones that
## decide the silhouette -- **head, middle and feet**, indices 2, 1 and 0 of
## `_bones()` -- are dropped onto whatever is under them and the **whole node**
## is raised by the worst of them.
##
## The node, not the mesh. Lifting the mesh alone is what put the visible body
## somewhere the collider was not, which is the fault the death animation was
## taken out for; the colliders and the contamination unwrap are authored
## against this node's own transform and have to move with it.
##
## Authority only, and it changes `global_position`, which is already in the
## state packet -- so every peer gets the corrected pose without anything new
## being sent.
func _settle_onto_ground() -> void:
	if not authority:
		return
	var space := get_world_3d().direct_space_state
	var bones := _bones()
	var worst := -INF
	for index in [2, 1, 0]:
		var bone: Dictionary = bones[index]
		var centre: Vector3 = global_transform * (bone["centre"] as Vector3)
		# Flat on its back, a disc rests on its side, so what hangs below its
		# centre is its radius rather than half its height.
		var reach: float = bone["radius"]
		var query := PhysicsRayQueryParameters3D.create(
			centre, centre - Vector3.UP * (reach + height))
		query.exclude = [get_rid()]
		query.collide_with_areas = false
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		# Positive when the bone's underside is through the surface.
		worst = maxf(worst, (hit.position.y as float) - (centre.y - reach))
	if worst == -INF:
		return
	var lift := worst + ground_clearance
	if absf(lift) < 0.0005:
		return
	global_position += Vector3.UP * lift
	_fall_pivot += Vector3.UP * lift


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
	var step := new_position - global_position
	var walking := Vector2(step.x, step.z).length_squared() > 0.000001
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
		_set_locomotion_animation(walking)
		# Clients do not simulate enemies; this packet is the only ground distance
		# they see. Feed it through the same odometer as the authority so planted
		# hands walk on every peer instead of freezing in the idle pose remotely.
		#
		# TODO: the delta here is a physics tick, but this runs on packet arrival
		# and the enemy state packet is `unreliable_ordered`. `phase` is a
		# distance and so stays right when one is dropped; `strength`, which is
		# a time fade, is under-advanced by exactly the packets that went
		# missing. Wants the real interval between packets.
		_advance_gait(step, walking, 1.0 / float(Engine.physics_ticks_per_second))


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
	# Rocking back from a threshold. It keeps walking through it: the flinch is
	# a stagger, not a stun, and stopping the chase would make a steady stream
	# of hits into a hold.
	_advance_flinch(delta)

	var target := _nearest(targets)
	# Noticed, or given up on. Measured flat: a player on a stall roof is as
	# close as one standing under it, and height should not decide a chase.
	if target != null:
		var gap_to_target := Vector2(target.global_position.x - global_position.x,
			target.global_position.z - global_position.z).length()
		if _alerted:
			if gap_to_target > give_up_range:
				_alerted = false
		elif gap_to_target <= sight_range:
			_alerted = true
	else:
		_alerted = false
	if not _alerted:
		target = null

	var flat := Vector3.ZERO
	if target != null:
		flat = _step_toward(target, delta) - global_position
		flat.y = 0.0

	# A body that is more sauce than burger walks like it. Continuous, like the
	# shove: what it reads as is the fight winding down rather than a state
	# change at a percentage.
	var soiled := 1.0 - health_fraction()
	var pace := move_speed * (1.0 - soiled_slowdown * soiled)
	if flat.length_squared() > 0.000001:
		var direction := flat.normalized()
		velocity.x = direction.x * pace
		velocity.z = direction.z * pace
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

	# The shove rides on top of the walk rather than replacing it, so a body
	# being hosed head-on is pushed backwards while still trying to come at you
	# -- which is what leaning into a hose looks like.
	velocity.x += _shove.x
	velocity.z += _shove.z
	_shove = _shove.move_toward(Vector3.ZERO,
		shove_speed / maxf(shove_decay_seconds, 0.01) * delta)

	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= fall_gravity * delta
	var stood_at := global_position
	move_and_slide()
	var walking := Vector2(velocity.x, velocity.z).length_squared() > 0.000001
	_set_locomotion_animation(walking)
	_advance_gait(global_position - stood_at, walking, delta)

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
	# A rusher does not bite, it runs into you: the shove is what it is for, and
	# it is what stops a swarm of them being a stationary damage tick.
	if impact_push_speed > 0.0 or impact_lift_speed > 0.0:
		target.apply_enemy_impact(gap, impact_push_speed, impact_lift_speed)
	return target


## Where to walk this frame to end up at `target`.
##
## Straight at them while the way is clear, which is most of the time on an open
## street and is what keeps a chase from reading as a body pacing out the middle
## of every cell it crosses. Once something is in the way, a route round it,
## recomputed on a timer rather than every frame.
##
## Falling back to the straight line when there is no router at all is
## deliberate: an enemy that stops chasing because nobody handed it a map is a
## worse failure than one that leans on a wall.
func _step_toward(target: MayoPlayer, delta: float) -> Vector3:
	var goal := target.global_position
	if nav == null:
		return goal
	if nav.line_is_walkable(global_position, goal):
		_route.clear()
		return goal

	_repath_timer -= delta
	# Redone when the timer runs out, or at once if the player has left the part
	# of the street the current route was drawn to.
	if _repath_timer <= 0.0 or _route.is_empty() \
			or StreetMap.cell_at(goal) != StreetMap.cell_at(_route_goal):
		_repath_timer = repath_interval
		_route_goal = goal
		_route = nav.route(global_position, goal)
		_route_step = 0

	# Waypoints already passed are dropped rather than walked back to.
	while _route_step < _route.size():
		var flat := _route[_route_step] - global_position
		flat.y = 0.0
		if flat.length() > StreetMap.CELL * waypoint_reached_cells:
			return _route[_route_step]
		_route_step += 1
	return goal


## Whether the straight line to that point is walkable, which the router is
## asked rather than a ray.
##
## This was a chest-high raycast, and it was wrong in a way that only showed up
## on the street: a ray at that height passes **under every canopy and over
## every counter**, so it reported a clear road through a stall, the route was
## dropped, and the body walked into something it was never going to fit
## through. Seeing a thing and being able to walk to it are different questions.
func _can_walk_straight_to(point: Vector3) -> bool:
	return nav == null or nav.line_is_walkable(global_position, point)


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
