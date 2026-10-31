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

const FryStalkerVisualScript := preload("res://scripts/fry_stalker_visual.gd")
const TomatoVisualsScript := preload("res://scripts/tomato_visuals.gd")
const HAMBURGER_MONSTER := preload(
	"res://assets/enemies/hamburger_monster/hamburger_monster.glb")
## The authored crawler, measured off its meshes at scale 1: fingertip to
## fingertip, ground to crown, front to back. It is a wide, low thing -- nearly
## four times as wide as it is tall -- and every figure below is derived from
## these three so a re-export only has to update this line.
const MODEL_SOURCE_SIZE := Vector3(5.0, 1.35, 2.27)
## How wide the burger stands on the street, which is the one knob. 4.1 m is
## the footprint the festival street was built around: it walks under a 4.54 m
## stall canopy, wedges in the tutorial's escape gap, and a toast pair stands
## beside it inside five metres. Grown to 10 m for a while, and nothing on the
## street fitted it; and for a while the body was declared 10 m *tall* over a
## mesh a quarter of that, so three quarters of it was air that sauce flew
## through. The body is now exactly the mesh.
const BURGER_WIDTH := 4.1
const MODEL_SCALE_FACTOR := BURGER_WIDTH / MODEL_SOURCE_SIZE.x
const MODEL_TARGET_SIZE := MODEL_SOURCE_SIZE * MODEL_SCALE_FACTOR
const MODEL_SCALE := Vector3.ONE * MODEL_SCALE_FACTOR
## The burger stack itself, hands not counted: half its depth, since the stack
## is round and the depth is all stack. The unwrap turns about this, and the
## hands are what `contact_reach` adds beyond it.
const MODEL_BODY_RADIUS := MODEL_SOURCE_SIZE.z * 0.5 * MODEL_SCALE_FACTOR
## Nominal only: the death measures the real thickness off the mesh, see
## `_measure_rest_thickness`. Kept for the body before it has a visual.
const MODEL_REST_RADIUS := MODEL_BODY_RADIUS
## Attack_GroundSlam reaches the ground on frame 16 at 24 fps.
const MODEL_ATTACK_IMPACT_SECONDS := 15.0 / 24.0
const FRY_STALKER_SOURCE_HEIGHT := 4.2
const FRY_STALKER_PLAYER_HEIGHT_MULTIPLE := 2.5

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
## bruiser**, which slams with both hands rather than charging; the rusher runs
## into you and the shove is the point of it.
@export_range(0.0, 30.0, 0.1, "suffix:m/s") var impact_push_speed := 0.0
@export_range(0.0, 15.0, 0.1, "suffix:m/s") var impact_lift_speed := 0.0

@export_group("Its attack")
## Weak on purpose. At one hit every `contact_interval` this is about 7 damage a
## second, so a player who walks into one and stays there has a good while to
## notice and get out.
@export_range(0.0, 100.0, 0.5) var contact_damage := 6.0
@export_range(0.1, 5.0, 0.05, "suffix:s") var contact_interval := 0.8
## Beyond the two body radii. The crawler's authored hands already extend the
## attack, so its build leaves this at zero.
@export_range(0.0, 3.0, 0.05, "suffix:m") var contact_reach := 0.5
## A Fry Stalker leaves its front claws buried after a slam. During this
## window it cannot chase or be pushed, giving the player a deliberate opening.
@export_range(0.0, 4.0, 0.05, "suffix:s") var attack_lock_seconds := 0.0
## Time from the start of an attack to its visible contact frame.
@export_range(0.0, 2.0, 0.01, "suffix:s") var attack_impact_delay_seconds := 0.0

## The two kinds a body can be. Minions die to a squirt and never stagger;
## heavies soak a party's worth of sauce and flinch on the way down.
enum Grade { MINION, HEAVY }

## Which of the two bodies this is. The bruiser is the hamburger: slow, heavy,
## and built by `build`. The rusher is the moldy toast: small, quick, low on
## health, and built by `build_moldy_toast_rusher`. They share everything else
## -- the chase, the contamination, the topple and the state packet -- because
## the difference between them is proportions and numbers, not behaviour.
enum EnemyKind {
	BRUISER, MOLDY_TOAST_RUSHER, FRY_STALKER,
	## Stage 2, La Tomatina. Primitive bodies -- see `TomatoVisuals` -- that
	## share the chase, the stain, the topple and the packet with the three
	## above, and add one trick each in `_advance_special`.
	TOMATO_GRUNT, TOMATO_BRUTE, BOWLING_TOMATO, TOMATO_BALL, KETCHUP_SPITTER,
	CAPRESE_CRAWLER,
}

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
## Whether the shove is shared out between however many players are hosing it.
##
## **On for a heavy, off for a minion.** A heavy hosed by one player is barely
## slowed and walks through it; hosed by the whole party it is held off. That is
## the co-op the fight has -- there are no roles here, everyone carries the same
## bottle, so what a team does that one player cannot is *arrive together*.
## A minion dies to one squirt and never needed the rule.
@export var shove_needs_party := true
## How quickly the shove dies once the stream comes off. Short: the tell is that
## it starts walking again, and a long tail blurs the moment it does.
@export_range(0.02, 2.0, 0.01, "suffix:s") var shove_decay_seconds := 0.16
## How much of its walk it loses at full contamination. At 0.6 a nearly ruined
## body moves at 40% of its speed -- so the fight visibly winds down rather than
## ending at a threshold.
@export_range(0.0, 1.0, 0.05) var soiled_slowdown := 0.55
## And what mustard does to it, as a fraction of the pace it would have had.
##
## Multiplied into the pace rather than added to `soiled_slowdown`, which is a
## share of how beaten the body is: a fresh monster has no soiling for mustard to
## add to, so adding would have made the sauce do nothing to the one body the
## player most wants slowed. The same two numbers a player gets, so a monster
## wading through a puddle is slowed by what slowed them.
@export_range(0.05, 1.0, 0.01) var mustard_slow_scale := 0.55
@export_range(0.0, 10.0, 0.1, "suffix:s") var mustard_slow_seconds := 2.5

@export_group("Ketchup")
## How long this body has to be under a ketchup stream to take on one more stack.
##
## **A quarter second, because a full bottle's longest squirt is one second.** One
## press is therefore worth four stacks at the very most, and three in practice --
## the stream takes a moment to reach anything, and that moment is a stack. Against
## the six it takes to go off, that means no single press ever sets a body off.
##
## It does not mean one player cannot. Holding the trigger starts the next squirt
## by itself once the pause is up, so a solo player reaches six in about two and a
## half seconds and two presses, on a tank still five-sixths full -- measured. That
## is the intent: several shots rather than one, and a second player hosing the
## same body halves the wait rather than being required for it.
@export_range(0.05, 2.0, 0.01, "suffix:s") var ketchup_stack_seconds := 0.25
## Stacks that make it go off.
@export_range(2, 12, 1) var ketchup_burst_stacks := 6

## How much ketchup is on this body, and when the last stack landed. Stacks do not
## drain: a body that has been half-sauced stays half-sauced, so walking away and
## coming back with a full bottle is a plan rather than a reset.
var ketchup_stacks := 0
var _ketchup_at := -1000.0

@export_group("Flinching")
## How far it rocks back when a threshold is crossed.
@export_range(0.0, 45.0, 0.5, "suffix:°") var flinch_degrees := 12.0
## And how long the whole rock-back-and-recover takes.
@export_range(0.05, 1.0, 0.01, "suffix:s") var flinch_seconds := 0.18

@export_group("Its walk")
## How long the gait takes to come on or go off. Faded rather than switched: cut
## at the moment a monster stops, it freezes mid-step with one elbow bent.
@export_range(0.05, 2.0, 0.05, "suffix:s") var gait_settle_seconds := 0.25

## Legacy inspector flag retained for scene compatibility. The Tripo crawler's
## supplied Crawl action owns its hand plants, so no modifier is attached.
@export var procedural_gait := false

var health := 240.0
## Clients simulate no enemies at all, exactly as they simulate no bodies.
var authority := true
var contamination: BodyContamination
## Half the silhouette's width: the arms reach this far out, so it is also the
## capsule that the unwrap wraps around.
var radius := 1.15
var height := MODEL_TARGET_SIZE.y
## Where it is looking, kept separately from `rotation.y` because a body part
## way through falling over is turned about two axes and the yaw can no longer
## be read back off the node.
var facing_yaw := 0.0
## 0 standing, TAU/4 flat on its back.
var fall_angle := 0.0

## Set by the world once the street exists. Without it the enemy walks the
## straight line, which is what it did before there was any routing at all.
var nav: StreetNav

## Something that is not a player and that this body would rather go for.
##
## Set while the doctor's drone is pulling it off the party, and cleared when the
## drone is gone. A baited body walks, routes, turns and animates through exactly
## the same code it always did -- the only two differences are what it is walking
## *at* and that it cannot land a contact hit on a player while it is doing so.
## It is emphatically not a pause: an enemy that simply stopped would read as the
## AI switching off, which is the thing this is meant to avoid.
var bait: Node3D = null
## Tutorial heavy pinned between the wrecks. The tutorial snapshot replicates
## this latch; the ordinary enemy packet continues to carry its struggling pose.
var tutorial_trapped := false
var _trap_position := Vector3.ZERO
var _trap_clock := 0.0

func set_tutorial_trapped(value: bool, at: Vector3) -> void:
	tutorial_trapped = value
	_trap_position = at


## Counts down while a mustard hit is still dragging this body.
var mustard_slow := 0.0
## True while it is standing in mustard thick enough to drag. Set from outside,
## by whoever is already asking the floor about this body.
var in_mustard := false
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
var _attack_target: MayoPlayer
var _attack_impact_left := 0.0
var _fry_visual: Node
var _attack_lock_left := 0.0
## How far through the flinch it is, in seconds, counting down. The flinch is
## driven **through `fall_angle`** rather than through a field of its own, so it
## needs nothing added to the state packet: the angle already travels.
## Where the stream is currently pushing it, in metres a second, decaying.
var _shove := Vector3.ZERO
var _pressure_left := 0.0
var _pressure_pose := 0.0
var _contact_kick_left := 0.0
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
## How far the body reaches behind its node: what it comes to rest on. The
## build writes a nominal figure; the death measures the real one off the
## visual, see `_measure_rest_thickness`.
var _rest_radius := 0.37
## True once the corpse has been dropped onto the ground and found to rest
## there, so `_settle_onto_ground` stops casting rays for it every tick.
var _rested := false

# --- La Tomatina ---------------------------------------------------------------

## How far the juice flies when this body bursts, in metres; zero for a body
## that does not burst. **Assigned by the world at build, deterministically**
## -- from the body's index and the map's seed -- so every peer holds the same
## figure and a client can throw the fragments itself when the packet says the
## body died, without the radius travelling.
var burst_radius := 0.0
## 0 small, 1 medium, 2 large: which of the three a grunt was dealt. The large
## one is drawn bigger and darker so it can be told apart before it goes.
var burst_tier := 0
## A bowled tomato that met a wall asks the world to burst it here; INF when
## nothing is pending. See `take_burst_request`.
var _burst_request := Vector3.INF

## The brute's charge: how long is left of it, which way it is going, and how
## long until it may charge again.
const BRUTE_CHARGE_RANGE := 14.0
const BRUTE_CHARGE_SECONDS := 1.2
const BRUTE_CHARGE_SPEED_SCALE := 2.2
const BRUTE_CHARGE_COOLDOWN := 4.0
## How long it is stuck for after running into a wall.
const BRUTE_WALL_STUN := 0.8
var _charge_left := 0.0
var _charge_cooldown := 0.0
var _charge_direction := Vector3.ZERO

## The bowler's lane. It stands still and rolls a ball from its pool every
## `BOWLING_INTERVAL` at whoever it can see down a straight street; the balls
## are bodies of their own (`TOMATO_BALL`), built with it so the enemy list
## stays append-only, parked under the floor between throws.
const BOWLING_INTERVAL := 4.0
const BOWLING_RANGE := 30.0
const BALL_SPEED := 14.0
const BALL_LIFETIME := 6.0
const BALL_PARK := Vector3(0.0, -50.0, 0.0)
const BALLS_PER_BOWLER := 3
var ball_pool: Array = []
var ball_owner: MayoEnemy = null
var _launch_cooldown := 2.0
var _ball_velocity := Vector3.ZERO
var _ball_live := false
var _ball_left := 0.0
## Player instance id -> seconds until the ball may knock them down again.
var _ball_hit_cooldown: Dictionary = {}

## The spitter: holds its distance and spits a hitscan stream of ketchup at
## whoever it can see. The spit is a request the world fulfils -- it paints
## the visor, the body and a puddle, and none of that is this body's to do.
const SPIT_RANGE := 18.0
const SPIT_HOLD_RANGE := 11.0
const SPIT_INTERVAL := 3.0
var _spit_cooldown := 1.5
var _spit_request: MayoPlayer = null

## The crawler's thread: within range and in sight it reels one player in,
## and a hit on it lets go for a while -- which is what a teammate is for.
const TETHER_RANGE := 8.0
const TETHER_REEL_SPEED := 6.5
const TETHER_BREAK_SECONDS := 2.0
var tether_target: MayoPlayer = null
var _tether_break_left := 0.0


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
	height = MODEL_TARGET_SIZE.y
	radius = MODEL_BODY_RADIUS
	contact_interval = 1.5
	# The hands reach the rest of the way to the fingertips.
	contact_reach = MODEL_TARGET_SIZE.x * 0.5 - MODEL_BODY_RADIUS
	attack_lock_seconds = 1.5
	attack_impact_delay_seconds = MODEL_ATTACK_IMPACT_SECONDS

	var bones := _bones()
	_rest_radius = MODEL_REST_RADIUS

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
	contamination.axis_offset = Vector3.ZERO
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
	_set_locomotion_animation(false)


## Adds the authored monster as presentation only. Its transform deliberately
## derives from the legacy body height; colliders, reach and spawn placement
## remain exactly as before.
func _build_visual() -> void:
	_visual_root = HAMBURGER_MONSTER.instantiate() as Node3D
	if _visual_root == null:
		push_error("Hamburger monster GLB did not instantiate as Node3D")
		return
	_visual_root.name = "HamburgerMonsterVisual"
	_visual_root.scale = MODEL_SCALE
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
	_walk_animation = _find_animation("Crawl")
	_idle_animation = _walk_animation
	_attack_animation = _find_animation("Attack_GroundSlam")
	_animation_player.animation_finished.connect(_on_animation_finished)


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
	# It weighs nothing, so the hose throws it further than it throws a burger --
	# and one player is enough to do it. Sharing the shove out is a rule for
	# bodies a team has to gang up on.
	shove_speed = 9.0
	shove_needs_party = false

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


## The Fry Stalker: the supplied 4.2 m carton creature, with eight articulated
## fry legs and a front-pair ground slam. It is a heavy like the hamburger, but
## moves between the hamburger and toast speeds and shares the hamburger's
## sight distance and health budget.
func build_fry_stalker(cell_size: float, brush_radius: float) -> void:
	kind = EnemyKind.FRY_STALKER
	grade = Grade.HEAVY
	flinch_thresholds = [0.25, 0.5, 0.75]
	height = MayoPlayer.CAPSULE_HEIGHT * FRY_STALKER_PLAYER_HEIGHT_MULTIPLE
	var model_scale := height / FRY_STALKER_SOURCE_HEIGHT
	radius = 1.0 * model_scale
	_rest_radius = 0.55 * model_scale
	max_health = 240.0
	solo_health = max_health
	health = max_health
	sauce_damage_per_hit = 0.4
	turn_speed = 4.2
	contact_damage = 10.0
	contact_interval = 1.4
	contact_reach = 0.72 * model_scale
	attack_lock_seconds = 1.4
	# The damage waits for the claws. Without this it landed the instant the
	# slam began, 0.56 s before the visual had lifted a leg -- the one attack
	# built to be read had no telegraph at all.
	attack_impact_delay_seconds = FryStalkerVisualScript.PLANT_AT * attack_lock_seconds
	sight_range = 26.0
	give_up_range = 44.0
	impact_push_speed = 0.0
	impact_lift_speed = 0.0
	shove_speed = 4.8

	# A solid carton and four long lower-body capsules cover the authored
	# silhouette without turning the open spaces between eight legs into a wall.
	var carton_shape := BoxShape3D.new()
	carton_shape.size = Vector3(1.7, 2.15, 1.15) * model_scale
	var carton_collision := CollisionShape3D.new()
	carton_collision.name = "Carton"
	carton_collision.shape = carton_shape
	carton_collision.position = Vector3(0.0, 0.58, 0.0) * model_scale
	add_child(carton_collision)
	for spec in [
		[Vector3(-0.35, 0.10, -0.35), Vector3(-0.83, -1.75, -0.82)],
		[Vector3(0.35, 0.10, -0.35), Vector3(0.83, -1.75, -0.82)],
		[Vector3(-0.35, 0.10, 0.35), Vector3(-0.83, -1.75, 0.82)],
		[Vector3(0.35, 0.10, 0.35), Vector3(0.83, -1.75, 0.82)],
	]:
		var a: Vector3 = spec[0] * model_scale
		var b: Vector3 = spec[1] * model_scale
		var span: Vector3 = b - a
		var shape := CapsuleShape3D.new()
		shape.radius = 0.12 * model_scale
		shape.height = span.length() + shape.radius * 2.0
		var collision := CollisionShape3D.new()
		collision.name = "Leg"
		collision.shape = shape
		collision.transform = Transform3D(_aligned_basis(span), (a + b) * 0.5)
		add_child(collision)

	_body_mesh = MeshInstance3D.new()
	_body_mesh.name = "EnemyBody"
	var mask_box := BoxMesh.new()
	mask_box.size = Vector3(1.7, 2.15, 1.15) * model_scale
	_body_mesh.mesh = mask_box
	_body_mesh.position = Vector3(0.0, 0.58, 0.0) * model_scale
	_body_mesh.visible = false
	add_child(_body_mesh)

	_fry_visual = FryStalkerVisualScript.new()
	_fry_visual.name = "FryStalkerVisual"
	_fry_visual.scale = Vector3.ONE * model_scale
	_fry_visual.position.y = -stand_height()
	_visual_root = _fry_visual
	add_child(_visual_root)

	contamination = BodyContamination.new()
	contamination.name = "BodyContamination"
	contamination.cell_size = cell_size
	contamination.brush_radius = brush_radius
	add_child(contamination)
	contamination.configure(self, _body_mesh, radius, height, Color("9e0b06"))
	contamination.add_visual_overlay(_visual_root)


# --- La Tomatina builders ------------------------------------------------------

## The common tail of every primitive build: the hidden mask mesh, the
## primitive visual at the body's origin, and the contamination grid wrapped
## round the whole thing. Colliders are the builder's own, added before this.
func _finish_primitive_body(cell_size: float, brush_radius: float, mask: Mesh,
		visual: Node3D, skin: Color) -> void:
	_body_mesh = MeshInstance3D.new()
	_body_mesh.name = "EnemyBody"
	_body_mesh.mesh = mask
	_body_mesh.visible = false
	add_child(_body_mesh)
	_visual_root = visual
	add_child(_visual_root)
	contamination = BodyContamination.new()
	contamination.name = "BodyContamination"
	contamination.cell_size = cell_size
	contamination.brush_radius = brush_radius
	add_child(contamination)
	contamination.configure(self, _body_mesh, radius, height, skin)
	contamination.add_visual_overlay(_visual_root)


func _add_sphere_collider(sphere_radius: float, at := Vector3.ZERO) -> void:
	var shape := SphereShape3D.new()
	shape.radius = sphere_radius
	var collision := CollisionShape3D.new()
	collision.name = "Body"
	collision.shape = shape
	collision.position = at
	add_child(collision)


func _add_cylinder_collider(cylinder_radius: float, cylinder_height: float,
		at := Vector3.ZERO) -> void:
	var shape := CylinderShape3D.new()
	shape.radius = cylinder_radius
	shape.height = cylinder_height
	var collision := CollisionShape3D.new()
	collision.name = "Body"
	collision.shape = shape
	collision.position = at
	add_child(collision)


static func _sphere_mask(sphere_radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = sphere_radius
	mesh.height = sphere_radius * 2.0
	return mesh


## The grunt: the horde. A tomato the size of a person that runs at you and
## bumps you. `tier` is which burst it was dealt, which also sizes it.
## Every tomato body is drawn at this fraction of its designed size: the
## street reads better with more, smaller tomatoes than fewer big ones.
const TOMATO_SCALE := 0.7


func build_tomato_grunt(cell_size: float, brush_radius: float, tier := 0) -> void:
	kind = EnemyKind.TOMATO_GRUNT
	grade = Grade.MINION
	flinch_thresholds = []
	burst_tier = tier
	var size := 1.3 if tier >= 2 else 1.0
	radius = 1.0 * size * TOMATO_SCALE
	height = radius * 2.0
	_rest_radius = radius
	max_health = 40.0
	solo_health = max_health
	health = max_health
	sauce_damage_per_hit = 0.65
	turn_speed = 8.0
	contact_damage = 6.0
	contact_interval = 0.9
	contact_reach = 0.15
	fall_duration = 0.5
	sight_range = 30.0
	give_up_range = 50.0
	impact_push_speed = 6.0
	impact_lift_speed = 1.5
	shove_speed = 8.0
	shove_needs_party = false
	_add_sphere_collider(radius)
	_finish_primitive_body(cell_size, brush_radius, _sphere_mask(radius),
		TomatoVisualsScript.grunt(radius, tier), TomatoVisualsScript.TOMATO)


## The brute: the tank. Twice the grunt, three hundred health, and a charge
## that knocks a player flat -- see `_advance_special`.
func build_tomato_brute(cell_size: float, brush_radius: float) -> void:
	kind = EnemyKind.TOMATO_BRUTE
	grade = Grade.HEAVY
	flinch_thresholds = [0.25, 0.5, 0.75]
	burst_tier = 2
	radius = 1.8 * TOMATO_SCALE
	height = radius * 2.0
	_rest_radius = radius
	max_health = 300.0
	solo_health = max_health
	health = max_health
	sauce_damage_per_hit = 0.4
	turn_speed = 3.0
	contact_damage = 14.0
	contact_interval = 1.6
	contact_reach = 0.4
	fall_duration = 1.1
	sight_range = 28.0
	give_up_range = 46.0
	impact_push_speed = 12.0
	impact_lift_speed = 4.0
	shove_speed = 4.8
	shove_needs_party = true
	_add_sphere_collider(radius)
	_finish_primitive_body(cell_size, brush_radius, _sphere_mask(radius),
		TomatoVisualsScript.brute(radius), TomatoVisualsScript.OVERRIPE)


## The bowler: stands at the end of a straight and rolls giant tomatoes down
## it. Its balls are built by the world right after it -- `BALLS_PER_BOWLER`
## of them -- and handed over through `ball_pool`.
func build_bowling_tomato(cell_size: float, brush_radius: float) -> void:
	kind = EnemyKind.BOWLING_TOMATO
	grade = Grade.HEAVY
	flinch_thresholds = [0.25, 0.5, 0.75]
	radius = 1.2 * TOMATO_SCALE
	height = 3.0 * TOMATO_SCALE
	_rest_radius = radius
	max_health = 160.0
	solo_health = max_health
	health = max_health
	sauce_damage_per_hit = 0.4
	turn_speed = 2.5
	contact_damage = 8.0
	contact_interval = 1.2
	contact_reach = 0.3
	sight_range = 36.0
	give_up_range = 60.0
	shove_speed = 2.0
	shove_needs_party = true
	_add_cylinder_collider(radius, height)
	var mask := CylinderMesh.new()
	mask.top_radius = radius
	mask.bottom_radius = radius
	mask.height = height
	_finish_primitive_body(cell_size, brush_radius, mask,
		TomatoVisualsScript.bowler(radius, height), TomatoVisualsScript.CRATE)


## The ball: what the bowler rolls. A body so the packet carries it, but not a
## fighter -- it never chases, cannot be killed, and counts for nothing.
func build_tomato_ball(cell_size: float, brush_radius: float, owner: MayoEnemy) -> void:
	kind = EnemyKind.TOMATO_BALL
	grade = Grade.MINION
	flinch_thresholds = []
	ball_owner = owner
	radius = 1.3 * TOMATO_SCALE
	height = radius * 2.0
	_rest_radius = radius
	max_health = 1000.0
	solo_health = max_health
	health = max_health
	sauce_alerts = false
	sight_range = 0.0
	give_up_range = 0.0
	contact_damage = 0.0
	shove_speed = 0.0
	_add_sphere_collider(radius)
	_finish_primitive_body(cell_size, brush_radius, _sphere_mask(radius),
		TomatoVisualsScript.ball(radius), Color("c0281a"))


## The spitter: the one that blinds you from range and leaves a puddle under
## you. Slow, and it keeps its distance.
func build_ketchup_spitter(cell_size: float, brush_radius: float) -> void:
	kind = EnemyKind.KETCHUP_SPITTER
	grade = Grade.HEAVY
	flinch_thresholds = [0.25, 0.5, 0.75]
	radius = 0.9
	height = 3.2
	_rest_radius = radius
	max_health = 120.0
	solo_health = max_health
	health = max_health
	sauce_damage_per_hit = 0.4
	turn_speed = 4.0
	contact_damage = 6.0
	contact_interval = 1.2
	contact_reach = 0.2
	sight_range = 30.0
	give_up_range = 50.0
	shove_speed = 5.0
	shove_needs_party = false
	_add_cylinder_collider(radius, height)
	var mask := CylinderMesh.new()
	mask.top_radius = radius
	mask.bottom_radius = radius
	mask.height = height
	_finish_primitive_body(cell_size, brush_radius, mask,
		TomatoVisualsScript.spitter(radius, height), TomatoVisualsScript.BOTTLE)


## The crawler: a caprese skewer that reels one player in on a thread of
## mozzarella until somebody hits it.
func build_caprese_crawler(cell_size: float, brush_radius: float) -> void:
	kind = EnemyKind.CAPRESE_CRAWLER
	grade = Grade.HEAVY
	flinch_thresholds = [0.25, 0.5, 0.75]
	radius = 0.6
	height = 1.2
	_rest_radius = radius
	max_health = 140.0
	solo_health = max_health
	health = max_health
	sauce_damage_per_hit = 0.4
	turn_speed = 5.0
	contact_damage = 7.0
	contact_interval = 1.0
	contact_reach = 0.3
	fall_duration = 0.6
	sight_range = 26.0
	give_up_range = 44.0
	shove_speed = 6.0
	shove_needs_party = false
	const SEGMENTS := 5
	const SPACING := 0.95
	var shape := CapsuleShape3D.new()
	shape.radius = radius * 0.95
	shape.height = SPACING * float(SEGMENTS - 1) + radius * 2.0
	var collision := CollisionShape3D.new()
	collision.name = "Body"
	collision.shape = shape
	# A capsule stands on y; the chain lies along z, so it is turned down flat.
	collision.rotation.x = deg_to_rad(90.0)
	add_child(collision)
	var mask := CapsuleMesh.new()
	mask.radius = radius
	mask.height = height
	_finish_primitive_body(cell_size, brush_radius, mask,
		TomatoVisualsScript.caprese(radius, SEGMENTS, SPACING), TomatoVisualsScript.MOZZARELLA)


# --- La Tomatina behaviour -----------------------------------------------------

## The one trick each stage 2 body has, run once a tick on the authority after
## the target is chosen and before the body moves. Returns overrides for the
## walk: "flat", a direction to walk instead of the chase, and "pace", a factor
## on the walking speed. Empty for the bodies that have no trick.
func _advance_special(delta: float, target: MayoPlayer) -> Dictionary:
	match kind:
		EnemyKind.TOMATO_BRUTE:
			return _advance_brute(delta, target)
		EnemyKind.BOWLING_TOMATO:
			return _advance_bowler(delta, target)
		EnemyKind.KETCHUP_SPITTER:
			return _advance_spitter(delta, target)
		EnemyKind.CAPRESE_CRAWLER:
			return _advance_crawler(delta, target)
	return {}


func _can_see_straight(target: MayoPlayer) -> bool:
	return nav == null or nav.line_is_walkable(global_position, target.global_position)


func is_charging() -> bool:
	return _charge_left > 0.0


func _advance_brute(delta: float, target: MayoPlayer) -> Dictionary:
	_charge_cooldown = maxf(_charge_cooldown - delta, 0.0)
	if _charge_left > 0.0:
		_charge_left = maxf(_charge_left - delta, 0.0)
		return {"flat": _charge_direction, "pace": BRUTE_CHARGE_SPEED_SCALE}
	if target == null or _charge_cooldown > 0.0 or _attack_lock_left > 0.0:
		return {}
	var gap := Vector3(target.global_position.x - global_position.x, 0.0,
		target.global_position.z - global_position.z)
	if gap.length() > BRUTE_CHARGE_RANGE or gap.length() < 0.5 or not _can_see_straight(target):
		return {}
	_charge_direction = gap.normalized()
	_charge_left = BRUTE_CHARGE_SECONDS
	_charge_cooldown = BRUTE_CHARGE_COOLDOWN + BRUTE_CHARGE_SECONDS
	return {"flat": _charge_direction, "pace": BRUTE_CHARGE_SPEED_SCALE}


func _advance_bowler(delta: float, target: MayoPlayer) -> Dictionary:
	_launch_cooldown = maxf(_launch_cooldown - delta, 0.0)
	# It never walks: pace zero keeps it turning to face whoever it is bowling
	# at without stepping towards them.
	var hold := {"pace": 0.0}
	if target == null or _launch_cooldown > 0.0:
		return hold
	var gap := Vector3(target.global_position.x - global_position.x, 0.0,
		target.global_position.z - global_position.z)
	if gap.length() > BOWLING_RANGE or gap.length() < radius * 2.0 or not _can_see_straight(target):
		return hold
	var ball := _free_ball()
	if ball == null:
		return hold
	var direction := gap.normalized()
	ball.launch(global_position + direction * (radius + ball.radius + 0.3), direction)
	_launch_cooldown = BOWLING_INTERVAL
	return hold


func _free_ball() -> MayoEnemy:
	for ball in ball_pool:
		if is_instance_valid(ball) and not ball._ball_live:
			return ball
	return null


func _advance_spitter(delta: float, target: MayoPlayer) -> Dictionary:
	_spit_cooldown = maxf(_spit_cooldown - delta, 0.0)
	if target == null:
		return {}
	var gap := Vector3(target.global_position.x - global_position.x, 0.0,
		target.global_position.z - global_position.z).length()
	var sees := _can_see_straight(target)
	if _spit_cooldown <= 0.0 and gap <= SPIT_RANGE and sees:
		_spit_request = target
		_spit_cooldown = SPIT_INTERVAL
	# Close enough and in sight: stand and spit rather than walk into reach.
	if gap <= SPIT_HOLD_RANGE and sees:
		return {"pace": 0.0}
	return {}


func _advance_crawler(delta: float, target: MayoPlayer) -> Dictionary:
	_tether_break_left = maxf(_tether_break_left - delta, 0.0)
	tether_target = null
	if target == null or _tether_break_left > 0.0:
		return {}
	var gap := Vector3(target.global_position.x - global_position.x, 0.0,
		target.global_position.z - global_position.z)
	var reach := radius + _target_radius(target) + contact_reach
	if gap.length() > TETHER_RANGE or gap.length() <= reach + 0.2 or not _can_see_straight(target):
		return {}
	if not _reaches_height(target) or target.is_incapacitated():
		return {}
	tether_target = target
	# Reeled in by position, not by impulse: an impulse every tick outruns the
	# player's own acceleration and sends them flying, while a steady pull is
	# a thing to be dragged by. The mustard slow is the "tied up" half -- the
	# same slow the floor uses, so nothing new is on the player.
	target.splash_mustard()
	var pull := -gap.normalized() * minf(TETHER_REEL_SPEED * delta, gap.length() - reach)
	target.move_and_collide(pull)
	return {"pace": 0.0}


## The ball's own tick: it rolls where it was sent, knocks over whoever it
## meets, and bursts on the first wall. Nothing of the chase applies to it.
func _advance_ball(delta: float, _targets: Array) -> void:
	if not _ball_live:
		velocity = Vector3.ZERO
		return
	_ball_left -= delta
	if _ball_left <= 0.0:
		_retire_ball()
		return
	for id in _ball_hit_cooldown.keys():
		_ball_hit_cooldown[id] = float(_ball_hit_cooldown[id]) - delta
		if _ball_hit_cooldown[id] <= 0.0:
			_ball_hit_cooldown.erase(id)
	velocity.x = _ball_velocity.x
	velocity.z = _ball_velocity.z
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= fall_gravity * delta
	var before := global_position
	move_and_slide()
	# Rolled rather than slid: the visual turns about the axis across its travel
	# by the ground it covered, which is what makes it read as a ball.
	var step := global_position - before
	var covered := Vector2(step.x, step.z).length()
	if covered > 0.0001 and _visual_root != null:
		var axis := Vector3.UP.cross(Vector3(step.x, 0.0, step.z).normalized())
		_visual_root.rotate(axis.normalized(), covered / maxf(radius, 0.01))
	facing_yaw = atan2(-_ball_velocity.x, -_ball_velocity.z)
	for index in get_slide_collision_count():
		var collision := get_slide_collision(index)
		var collider := collision.get_collider()
		if collider is MayoPlayer:
			var player := collider as MayoPlayer
			var id := player.get_instance_id()
			if _ball_hit_cooldown.has(id):
				continue
			_ball_hit_cooldown[id] = 1.0
			player.apply_enemy_impact(_ball_velocity, 9.0, 3.0)
			if player.can_slip():
				player.begin_slip()
		elif collider is StaticBody3D and collision.get_normal().y < 0.5:
			# A wall, a crate, a truck: not the floor. It bursts here.
			_burst_request = global_position
			_retire_ball()
			return


func _retire_ball() -> void:
	_ball_live = false
	_ball_velocity = Vector3.ZERO
	velocity = Vector3.ZERO
	global_position = BALL_PARK


## Rolled from `from` along `direction`, on the ground. Authority only.
func launch(from: Vector3, direction: Vector3) -> void:
	if not authority:
		return
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.000001:
		return
	global_position = Vector3(from.x, stand_height(), from.z)
	_ball_velocity = flat.normalized() * BALL_SPEED
	_ball_live = true
	_ball_left = BALL_LIFETIME
	_ball_hit_cooldown.clear()
	fall_angle = 0.0
	_apply_pose()


func is_ball_live() -> bool:
	return _ball_live


## Where a ball asked to burst, or INF; cleared on being asked.
func take_burst_request() -> Vector3:
	var at := _burst_request
	_burst_request = Vector3.INF
	return at


## Whom the spitter wants spat at, or null; cleared on being asked.
func take_spit_request() -> MayoPlayer:
	var target := _spit_request
	_spit_request = null
	return target if target != null and is_instance_valid(target) else null


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
	if moving:
		_play_animation(_walk_animation)
		return
	if _animation_player == null or _idle_animation.is_empty():
		return
	if _animation_player.current_animation != _idle_animation:
		_animation_player.play(_idle_animation)
	_animation_player.seek(0.0, true)
	_animation_player.pause()


func _play_attack_animation() -> void:
	if _fry_visual != null:
		_fry_visual.play_slam(attack_lock_seconds)
	if _animation_player == null or _attack_animation.is_empty():
		return
	_attack_animation_active = true
	# A new attack restarts the hand-slam wind-up from its readable first pose.
	_animation_player.stop()
	_animation_player.play(_attack_animation)


## Returns the victim only on the hand-slam contact frame. Leaving the authored
## reach during the wind-up makes the clearly telegraphed attack miss.
func _advance_pending_attack(delta: float) -> MayoPlayer:
	if _attack_target == null:
		return null
	_attack_impact_left = maxf(_attack_impact_left - delta, 0.0)
	if _attack_impact_left > 0.0:
		return null
	var victim := _attack_target
	_attack_target = null
	if not is_instance_valid(victim):
		return null
	var reach := radius + _target_radius(victim) + contact_reach
	var gap := Vector2(victim.global_position.x - global_position.x,
		victim.global_position.z - global_position.z).length()
	return victim if gap <= reach else null


func _play_death_animation() -> void:
	_attack_animation_active = false
	_attack_lock_left = 0.0
	_attack_target = null
	_attack_impact_left = 0.0
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
		var moving := Vector2(velocity.x, velocity.z).length_squared() > 0.000001
		_set_locomotion_animation(moving)
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
## Measured off the crawler's rest rig in body space, in source units -- see
## `MODEL_SOURCE_SIZE` -- with y running up from the soles. Three stacked discs
## are the bun, the fillings and the bun; a capsule per side is the arm from the
## shoulder to the forearm, and another the hand out to the fingertips, which
## is where the model is widest.
##
## `kind` is "disc" (a cylinder: centre, radius, height) or "limb" (a capsule:
## two ends and a radius). A burger tier needs the cylinder -- a capsule wide
## enough to be a bun is also that tall.
##
## Nothing here reaches below the soles: a hand capsule's radius extends past
## its endpoint, so each hand lies at its own radius above the floor and its
## underside rests exactly on it. Lower, and CharacterBody3D is pushed up off
## the street by its own collider and the whole monster hovers. The hands run
## straight out along x rather than following the slight slant of the forearm,
## so that their boxes are exact: a tilted capsule's bounding box reaches
## below the capsule and past its fingertips, and both the floor check and the
## mask-matches-colliders check read the box.
func _bones() -> Array:
	var s := MODEL_SCALE_FACTOR
	var floor_y := -height * 0.5
	var stack := MODEL_BODY_RADIUS
	var arm_radius := 0.20 * s
	var hand_radius := 0.28 * s
	var up := func(y: float) -> float: return floor_y + y * s
	return [
		{"kind": "disc", "centre": Vector3(0.0, up.call(0.22), 0.0),
			"radius": stack * 0.97, "height": 0.44 * s},
		{"kind": "disc", "centre": Vector3(0.0, up.call(0.62), 0.0),
			"radius": stack, "height": 0.36 * s},
		{"kind": "disc", "centre": Vector3(0.0, up.call(1.05), 0.0),
			"radius": stack * 0.93, "height": 0.50 * s},
		{"kind": "limb", "a": Vector3(-0.72 * s, up.call(0.55), 0.43 * s),
			"b": Vector3(-1.48 * s, up.call(0.43), 0.17 * s), "radius": arm_radius},
		{"kind": "limb", "a": Vector3(0.72 * s, up.call(0.55), 0.43 * s),
			"b": Vector3(1.48 * s, up.call(0.43), 0.17 * s), "radius": arm_radius},
		{"kind": "limb", "a": Vector3(-1.48 * s, floor_y + hand_radius, -0.14 * s),
			"b": Vector3(-(MODEL_SOURCE_SIZE.x * 0.5 - 0.28) * s, floor_y + hand_radius, -0.14 * s),
			"radius": hand_radius},
		{"kind": "limb", "a": Vector3(1.48 * s, floor_y + hand_radius, -0.14 * s),
			"b": Vector3((MODEL_SOURCE_SIZE.x * 0.5 - 0.28) * s, floor_y + hand_radius, -0.14 * s),
			"radius": hand_radius},
	]


## The half-width the unwrap wraps the body around, and what `contact_reach` is
## measured beyond: the widest the burger gets, which is the patty, not a
## shoulder and not the arms.
func _body_radius() -> float:
	return MODEL_BODY_RADIUS


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
	# A bowled tomato wears the sauce and is not hurt by it: it is a thing
	# thrown at you, not a thing to fight.
	if kind == EnemyKind.TOMATO_BALL:
		return false
	# A hit is what cuts the crawler's thread: the reeled-in player is pulled
	# off whoever it had, for long enough to get clear.
	if kind == EnemyKind.CAPRESE_CRAWLER:
		_tether_break_left = TETHER_BREAK_SECONDS
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
	_rested = false
	_play_death_animation()
	# Measured after the rig is back in its rest pose, which is what it falls in.
	var thickness := _measure_rest_thickness()
	if thickness > 0.0:
		_rest_radius = thickness
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
## `strength` is how much of the full shove this hit is worth, 0 to 1. The world
## works it out from how many players are on this body at once -- see
## `shove_needs_party`.
##
## Authority only -- the position it moves is what travels.
func take_shove(from: Vector3, strength := 1.0) -> void:
	if not authority or not is_alive():
		return
	var away := Vector3(global_position.x - from.x, 0.0, global_position.z - from.z)
	if away.length_squared() < 0.000001:
		return
	# Set from whoever landed the hit, so a body being hosed from two sides is
	# pushed by whichever stream reached it last. At 187 landings a second that
	# alternates fast enough to average out into the middle of them.
	if _pressure_left <= 0.0:
		_contact_kick_left = 0.14
	_pressure_left = 0.14
	_shove = away.normalized() * shove_speed * clampf(strength, 0.0, 1.0)


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


func is_attack_locked() -> bool:
	return _attack_lock_left > 0.0


## Rocks back and recovers, writing `fall_angle` -- which is why nothing is
## added to the state packet for it. A half-sine: away from upright and back,
## reaching the full angle in the middle rather than at the end.
func _advance_flinch(delta: float) -> void:
	if _flinch_left <= 0.0 and _pressure_left <= 0.0 and _pressure_pose < 0.0001 \
			and _contact_kick_left <= 0.0 and absf(fall_angle) < 0.0001:
		return
	_pressure_left = maxf(_pressure_left - delta, 0.0)
	_pressure_pose = lerpf(_pressure_pose, 1.0 if _pressure_left > 0.0 else 0.0,
		1.0 - exp(-delta / 0.07))
	_contact_kick_left = maxf(_contact_kick_left - delta, 0.0)
	var contact := sin((1.0 - _contact_kick_left / 0.14) * PI) if _contact_kick_left > 0.0 else 0.0
	_flinch_left = maxf(_flinch_left - delta, 0.0)
	var through := 1.0 - _flinch_left / maxf(flinch_seconds, 0.001)
	var flinch := deg_to_rad(flinch_degrees) * sin(through * PI)
	# A brief first-contact recoil, then a restrained lean under sustained pressure.
	# This shares the replicated pose and never stops chasing or contact attacks.
	fall_angle = maxf(flinch, deg_to_rad(5.0) * contact) + deg_to_rad(2.5) * _pressure_pose
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
	if _fry_visual != null:
		_fry_visual.set_motion(_ground_covered, walking and _attack_lock_left <= 0.0)
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


## Drops the settled body onto the ground: lifts it until nothing of it is
## through the floor, lowers it until something of it touches.
##
## The topple is an arc about the feet with an allowance for the body's
## thickness, which is right on flat ground and wrong everywhere else -- a body
## that dies on a kerb, on a ramp or half under a stall counter arrives with
## part of itself inside the geometry. So once it is down, every mesh of the
## visual is dropped onto whatever is under its lowest point and the **whole
## node** is moved by the worst of them.
##
## Off the visual, not off a bone table. This used to read the hamburger's
## `_bones()` -- for every kind of enemy, at the hamburger's scale -- and so
## held every corpse with its centre 4.5 m up: a toast slice floated four
## metres over the street, and the burger itself, two metres thicker in the
## table than in the mesh, hung above its own shadow. The meshes are what the
## player sees resting on the ground, so they are what is measured.
##
## The node, not the mesh. Lifting the mesh alone is what put the visible body
## somewhere the collider was not, which is the fault the death animation was
## taken out for; the colliders and the contamination unwrap are authored
## against this node's own transform and have to move with it.
##
## Authority only, and it changes `global_position`, which is already in the
## state packet -- so every peer gets the corrected pose without anything new
## being sent. Runs until the body is found at rest, then not again.
func _settle_onto_ground() -> void:
	if not authority or _rested or not is_inside_tree():
		return
	var world_3d := get_world_3d()
	if world_3d == null:
		return
	var space := world_3d.direct_space_state
	var worst := -INF
	for mesh_instance in _visual_meshes():
		var aabb: AABB = mesh_instance.get_aabb()
		var lowest := Vector3.INF
		for corner in 8:
			var point: Vector3 = mesh_instance.global_transform * aabb.get_endpoint(corner)
			if point.y < lowest.y:
				lowest = point
		# Cast from inside the body, level with the mesh's centre, so a point
		# already through the floor still finds the surface it is through.
		var centre: Vector3 = mesh_instance.global_transform * aabb.get_center()
		var query := PhysicsRayQueryParameters3D.create(
			Vector3(lowest.x, maxf(centre.y, lowest.y), lowest.z),
			lowest - Vector3.UP * height)
		query.collide_with_areas = false
		# The ground is the street, not whoever is standing in it. A body dies
		# next to the player who killed it as often as not, and a ray that
		# stopped at their shoulder would lay the corpse across their head.
		var exclude: Array[RID] = [get_rid()]
		var hit := {}
		for _attempt in 6:
			query.exclude = exclude
			hit = space.intersect_ray(query)
			if hit.is_empty() or not (hit.collider is CharacterBody3D):
				break
			exclude.append((hit.collider as CollisionObject3D).get_rid())
		if hit.is_empty():
			continue
		# Positive when the mesh's underside is through the surface.
		worst = maxf(worst, (hit.position.y as float) - lowest.y)
	if worst == -INF:
		return
	var lift := worst + ground_clearance
	if absf(lift) < 0.0005:
		_rested = true
		return
	global_position += Vector3.UP * lift
	_fall_pivot += Vector3.UP * lift


## Every mesh of the visual, whatever built it -- an imported GLB or the Fry
## Stalker's primitives.
func _visual_meshes() -> Array:
	if _visual_root == null or not is_instance_valid(_visual_root):
		return []
	return _visual_root.find_children("*", "MeshInstance3D", true, false)


## How far the visual reaches behind the node, along its local +Z: the body goes
## over onto its back, so this is the thickness it lands on, and what
## `_apply_pose` lifts the centre by as it goes. Measured rather than written
## down, because written down it was wrong: the hamburger's nominal 4.5 m was
## its old bone table at 5x, and the mesh is 2.3 m -- so the centre *rose* 1.6 m
## in the middle of the fall and came to rest in the air. Returns 0 when there
## is nothing to measure, and the nominal figure stands.
func _measure_rest_thickness() -> float:
	if not is_inside_tree():
		return 0.0
	var into_body := global_transform.affine_inverse()
	var deepest := 0.0
	for mesh_instance in _visual_meshes():
		var to_body: Transform3D = into_body * mesh_instance.global_transform
		var aabb: AABB = mesh_instance.get_aabb()
		for corner in 8:
			deepest = maxf(deepest, (to_body * aabb.get_endpoint(corner)).z)
	return deepest


## **One more layer of ketchup, if enough time has passed for one.** Returns true
## on the stack that makes it go off; the caller owns what that means, because an
## explosion is a thing that happens to the world rather than to this body.
##
## Rate-limited by time rather than counted per hit, for the reason the floor's
## coats are: a stream lands a hundred points a second on whatever it is pointed
## at, so per hit would set a body off in a tenth of a second and the number six
## would mean nothing.
func soak_ketchup(now: float) -> bool:
	if not is_alive():
		return false
	if now - _ketchup_at < ketchup_stack_seconds:
		return false
	_ketchup_at = now
	ketchup_stacks += 1
	return ketchup_stacks >= ketchup_burst_stacks


## The body went off: the sauce on it is spent.
func clear_ketchup() -> void:
	ketchup_stacks = 0
	_ketchup_at = -1000.0


## **Mustard drags a monster the way it drags a player**, and for the same
## reason it is one drag rather than two: hit and standing in it do not multiply.
func mustard_factor() -> float:
	if mustard_slow > 0.0 or in_mustard:
		return mustard_slow_scale
	return 1.0


## A mustard hit landed on this body.
func splash_mustard() -> void:
	mustard_slow = mustard_slow_seconds


func paint_mayo(world_position: Vector3, world_normal: Vector3,
		kind := ContaminationGrid.KIND_MAYO) -> Vector2i:
	if contamination == null:
		return Vector2i(-1, -1)
	return contamination.paint_mayo(world_position, world_normal, kind)


func paint_mayo_cell(cell: Vector2i, kind := ContaminationGrid.KIND_MAYO) -> void:
	if contamination != null:
		contamination.paint_mayo_cell(cell, kind)


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
##
## `max_health` travels alongside `health` because a health bar is a fraction,
## and the ceiling is decided by the size of the party -- which the server scales
## and a client has no reliable count of. Sending the numerator without the
## denominator gave the two screens the same hit points and two different bars:
## a heavy on 192 read half gone on the host and four fifths gone on the guest.
## It rides in the packet rather than in a join message because it changes
## whenever somebody joins or leaves, and the cost is one float per body.
func network_state() -> Array:
	return [global_position, facing_yaw, health, fall_angle, max_health]


func apply_network_state(new_position: Vector3, yaw: float, new_health: float,
		new_fall_angle: float, new_max_health := 0.0) -> void:
	# Guarded rather than assigned outright: a zero would make every fraction a
	# division by nothing, and `health_fraction` clamping it away would hide
	# that the ceiling never arrived.
	if new_max_health > 0.0:
		max_health = new_max_health
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
	if kind == EnemyKind.TOMATO_BALL:
		_advance_ball(delta, targets)
		return null
	if tutorial_trapped:
		_trap_clock += delta
		global_position = _trap_position
		velocity = Vector3.ZERO
		_shove = Vector3.ZERO
		facing_yaw = 0.0
		fall_angle = sin(_trap_clock * 7.0) * 0.045
		_apply_pose()
		_advance_gait(Vector3.ZERO, true, delta)
		return null
	_contact_cooldown = maxf(_contact_cooldown - delta, 0.0)
	mustard_slow = maxf(mustard_slow - delta, 0.0)
	_attack_lock_left = maxf(_attack_lock_left - delta, 0.0)
	var pending_hit := _advance_pending_attack(delta)
	# Rocking back from a threshold. It keeps walking through it: the flinch is
	# a stagger, not a stun, and stopping the chase would make a steady stream
	# of hits into a hold.
	_advance_flinch(delta)

	# Something in its face outranks the party. It still walks, routes and turns
	# through everything below; it is simply walking at the drone instead.
	var baited := bait != null and is_instance_valid(bait)

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

	# The stage 2 tricks: a charge, a throw, a spit, a pull. Run here, with the
	# target decided and the body not yet moved, so a trick can redirect the
	# walk below without a second movement pass.
	var special := _advance_special(delta, target)

	var flat := Vector3.ZERO
	if baited:
		# The bait is walked to the same way a player is -- same router, same
		# waypoints -- so it rounds the same corners rather than sliding at it.
		flat = _step_toward(bait.global_position, delta) - global_position
		flat.y = 0.0
	elif target != null and _attack_lock_left <= 0.0:
		flat = _step_toward(target.global_position, delta) - global_position
		flat.y = 0.0
	if special.has("flat"):
		flat = special["flat"]
		flat.y = 0.0

	# A body that is more sauce than burger walks like it. Continuous, like the
	# shove: what it reads as is the fight winding down rather than a state
	# change at a percentage.
	var soiled := 1.0 - health_fraction()
	var pace := move_speed * (1.0 - soiled_slowdown * soiled) * mustard_factor() \
		* float(special.get("pace", 1.0))
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
	if _attack_lock_left <= 0.0:
		velocity.x += _shove.x
		velocity.z += _shove.z
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	_shove = _shove.move_toward(Vector3.ZERO,
		shove_speed / maxf(shove_decay_seconds, 0.01) * delta)

	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= fall_gravity * delta
	var stood_at := global_position
	move_and_slide()
	# A charge that meets a wall ends in it: the brute is stuck for a moment,
	# which is the opening the charge pays for.
	if _charge_left > 0.0 and is_on_wall():
		_charge_left = 0.0
		_charge_cooldown = BRUTE_CHARGE_COOLDOWN
		_attack_lock_left = BRUTE_WALL_STUN
		_contact_cooldown = maxf(_contact_cooldown, BRUTE_WALL_STUN)
	var walking := Vector2(velocity.x, velocity.z).length_squared() > 0.000001
	_set_locomotion_animation(walking)
	_advance_gait(global_position - stood_at, walking, delta)
	if pending_hit != null:
		return pending_hit

	# Baited: it is swiping at the drone, not at the party. Returning null before
	# the reach tests is what makes that true of the damage *and* of the contact
	# knockback -- neither can happen through a body that is busy elsewhere.
	if baited or target == null or _contact_cooldown > 0.0:
		return null
	# Measured between the capsule axes, flat: both bodies are capsules, so the
	# gap between their surfaces is the axis distance less the two radii.
	var reach := radius + _target_radius(target) + contact_reach
	var gap := Vector3(target.global_position.x - global_position.x, 0.0,
		target.global_position.z - global_position.z)
	if gap.length() > reach:
		return null
	# And it has to be able to reach that high. The chase above is deliberately
	# flat -- a player on a stall roof is still worth walking towards -- but the
	# hit is not the chase, and a body cannot touch what is over its head.
	#
	# What decides it is whether the two bodies' vertical spans meet, not how
	# far apart their two origins are: a burger is 4.1 m of body and a toast
	# slab is 1.1 m, so the same y difference is well inside one's reach and far
	# outside the other's, and any single constant would be wrong for one of
	# them. `contact_reach` stands in for the unmodelled arms here exactly as it
	# does flat.
	if not _reaches_height(target):
		return null
	_contact_cooldown = maxf(contact_interval, attack_lock_seconds)
	_attack_lock_left = attack_lock_seconds
	_play_attack_animation()
	if attack_impact_delay_seconds > 0.0:
		_attack_target = target
		_attack_impact_left = attack_impact_delay_seconds
		return null
	# A rusher does not bite, it runs into you: the shove is what it is for, and
	# it is what stops a swarm of them being a stationary damage tick.
	if impact_push_speed > 0.0 or impact_lift_speed > 0.0:
		target.apply_enemy_impact(gap, impact_push_speed, impact_lift_speed)
	# A charging brute does not bump you, it flattens you: the shove above and
	# then the floor. The charge is spent on whoever it reached.
	if _charge_left > 0.0:
		_charge_left = 0.0
		if target.can_slip():
			target.begin_slip()
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
##
## Takes the `goal` rather than the player standing on it: the only thing this
## ever read off a target was its position, and the drone is not a player.
func _step_toward(goal: Vector3, delta: float) -> Vector3:
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


## How tall the player's body is, from the same place the width comes from: the
## grid is unwrapped around the capsule, so it carries the capsule's figures.
## The fallback is the capsule the world actually builds.
func _target_height(player: MayoPlayer) -> float:
	if player.contamination != null:
		return player.contamination.height
	return 2.56


## Whether this body and the player overlap vertically closely enough to touch.
##
## Both are treated as their own full height centred on their origin, which is
## what the contamination unwrap already assumes and what puts a standing
## burger's span at roughly floor to 4.1 m and a toast slab's at floor to 1.1 m.
## The span is widened by `contact_reach` at both ends for the same reason it is
## added flat -- the arms are not modelled -- so a burger still swats somebody on
## a low kerb and a rusher still rams somebody stepping off one.
##
## Deliberately *not* "off the ground means safe": half of an ordinary jump is
## still inside both bodies' spans. Only genuinely out of reach is out of reach.
func _reaches_height(player: MayoPlayer) -> bool:
	var low := global_position.y - height * 0.5 - contact_reach
	var high := global_position.y + height * 0.5 + contact_reach
	var player_half := _target_height(player) * 0.5
	return player.global_position.y - player_half <= high \
		and player.global_position.y + player_half >= low
