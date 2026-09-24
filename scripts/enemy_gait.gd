class_name EnemyGait
extends SkeletonModifier3D

## Makes the burger monster walk on its hands rather than paddle above them.
##
## The imported `Walk` clip swings the arms from the shoulder and holds the body
## level. Swinging is not walking: a hand that keeps moving while it is meant to
## be carrying the body reads as treading water, and no amount of extra bend at
## the elbow fixes it, because the problem is not the shape of the limb. It is
## that **the hand does not stay where it was put**.
##
## So the hands are placed rather than posed. Each one is given a plant point on
## the ground, and while it is the hand taking weight it **does not move**: the
## body travels over it, which in the body's own space means the hand slides
## backwards at exactly the speed the monster is going forwards. Then it lifts,
## swings ahead, and plants again. The arm is solved backwards from wherever the
## hand is -- two-bone inverse kinematics, shoulder and elbow -- so the bend
## comes out of the reach instead of being dialled in.
##
## The body crouches just far enough for the arms to carry it, then falls and is
## caught between plants and rolls as the weight passes from one hand to the
## other. The crouch is the important difference from raising an unreachable
## plant target: the palm stays on the floor and the burger comes down to meet
## it, instead of the hand being held still in mid-air.
##
## It runs as a `SkeletonModifier3D` rather than out of `_process`, which is the
## difference between adding to the clip and fighting it: a modifier is called
## after the animation has written its pose and before the skeleton is used.
##
## Everything here is **cosmetic**, and driven by `phase`, which the enemy sets
## from the ground it has actually covered. No collider, no mask cell and no
## packet is touched by any of it.

## How far the monster travels in one full cycle -- two plants, one per hand.
## The phase comes from distance rather than from time, which is what lets a
## planted hand hold still: the body advances exactly one step while the hand it
## is standing on slides one step backwards through the body's own space.
## **Clamped to what the arms can actually span after the allowed crouch.** Ask
## for a longer stride than that and the cycle is shortened rather than letting
## the solver miss the hand target. `stride_in_use` is what the monster is
## really taking.
@export_range(0.5, 12.0, 0.1, "suffix:m") var stride_metres := 1.8

## The share of a step a hand spends on the ground. Above 0.5 both hands are
## down together for part of the cycle, which is what a heavy thing does.
@export_range(0.3, 0.9, 0.01) var stance_share := 0.62

## Nudges the wrist height at contact. Zero keeps the asset's authored contact
## height: in the rest pose its palm is already flat and its underside is at
## the model floor. The target is never raised just to make an impossible reach
## solvable; the body crouches instead.
@export_range(-0.5, 0.5, 0.01, "suffix:m") var plant_height_offset := 0.0

## How much of the airborne stroke is used to release and prepare the wrist.
## The palm stays locked for the whole support stroke, then eases back to the
## authored clip instead of snapping as it leaves or approaches the floor.
@export_range(0.02, 0.25, 0.01) var wrist_transition_share := 0.10

## The largest permanent crouch the walk may add. This is not the bounce: it is
## the small lowering that gives a bent arm enough spare reach to move fore and
## aft while the palm remains on the floor. If a requested stride needs more,
## the stride is shortened.
@export_range(0.0, 1.0, 0.01, "suffix:m") var support_crouch_limit_metres := 0.32

## Safety limit for a restrained cartoon stretch if a tuned stride still needs
## more reach after the support crouch. The current contact pose fits at 1.0;
## one is rigid and 1.30 would permit at most 30%.
@export_range(1.0, 1.35, 0.01) var arm_stretch_limit := 1.30

## How high a hand lifts as it swings through.
@export_range(0.0, 1.5, 0.05, "suffix:m") var step_lift_metres := 0.45

## How far out to the side the hands are planted, as a share of the shoulders'
## own width. Under 1 walks them in towards the middle, which reads as weight.
@export_range(0.5, 1.6, 0.05) var track_width := 0.86

## How far the body drops between plants. The whole of the weight cue, so it is
## small on purpose -- a bouncing burger is a different animal.
@export_range(0.0, 0.6, 0.01, "suffix:m") var bob_metres := 0.13

## How far it rocks as the weight crosses from one hand to the other.
@export_range(0.0, 20.0, 0.5, "suffix:deg") var body_roll_degrees := 4.0

## A small fore/aft weight shift. The actual forward travel comes from the
## enemy node moving over a planted hand; this only stops the torso reading as
## a perfectly level puck while that happens.
@export_range(0.0, 12.0, 0.5, "suffix:deg") var body_pitch_degrees := 2.5

## Which way the elbow folds. A hand-walker's elbows point back, away from the
## direction of travel; flipping this points them forward, like a mantis.
@export var elbows_point_back := true

## 0 standing still, 1 walking. Faded rather than switched: cut at the moment a
## monster stops, it freezes mid-step with one arm in the air.
var strength := 0.0

## Cycles. The whole number is strides taken, the fraction is where in the
## current one the monster is.
var phase := 0.0

## How many times the skeleton has called this. Godot has had two names for the
## hook, and a modifier whose hook is never called is silent rather than loud --
## it just quietly does nothing -- so the checks count the calls.
var calls := 0

var _body := -1
var _upper := [-1, -1]
var _lower := [-1, -1]
var _hand := [-1, -1]
## The hand bones have a deliberately twisted local basis. Their +Y axis is
## not the finger direction and their +Z axis is not the palm normal. At rest,
## however, the mesh is authored exactly as a useful support hand: palm plane
## horizontal, fingers forward. Preserve that global rest basis at contact
## rather than inventing an axis frame from the bone names.
var _hand_contact_basis := [Basis(), Basis()]
## Bone lengths, in the skeleton's own units, read off the rest pose.
var _upper_length := 0.0
var _lower_length := 0.0
## The height the hands rest at, in the skeleton's own units. Read off the rest
## pose rather than assumed to be the floor -- see `plant_height_offset`.
var _plant_height := 0.0
## How high the shoulders sit in the skeleton's own units, and the scale in
## force when the rig was last posed. Both read off the rig rather than guessed.
var _shoulder_height := 0.0
## Where each shoulder sits across the body, at rest. The plant is measured from
## here rather than from the shoulder's live pose: the body bobs and rolls, so a
## target hung off the moving shoulder moves with it, and the hand it is meant
## to be holding still wanders by exactly that much.
var _shoulder_across := [0.0, 0.0]
var _scale := 1.0


func _ready() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	_body = skeleton.find_bone("Body")
	_upper = [skeleton.find_bone("Arm.L.Upper"), skeleton.find_bone("Arm.R.Upper")]
	_lower = [skeleton.find_bone("Arm.L.Lower"), skeleton.find_bone("Arm.R.Lower")]
	_hand = [skeleton.find_bone("Hand.L"), skeleton.find_bone("Hand.R")]
	if not has_rig():
		return
	# A bone sits at its parent's +Y by the length of that parent, so the rest
	# origin of a child is the length of the bone above it.
	_upper_length = skeleton.get_bone_rest(_lower[0]).origin.length()
	_lower_length = skeleton.get_bone_rest(_hand[0]).origin.length()
	# Where the hand sits with the rig at rest: chain the rest transforms up to
	# the root, because nothing has been posed yet at this point.
	var at_rest := Transform3D()
	var bone: int = _hand[0]
	while bone >= 0:
		at_rest = skeleton.get_bone_rest(bone) * at_rest
		bone = skeleton.get_bone_parent(bone)
	_plant_height = at_rest.origin.y
	var shoulder_rest := Transform3D()
	bone = _upper[0]
	while bone >= 0:
		shoulder_rest = skeleton.get_bone_rest(bone) * shoulder_rest
		bone = skeleton.get_bone_parent(bone)
	_shoulder_height = shoulder_rest.origin.y
	for side in 2:
		var chain := Transform3D()
		bone = _upper[side]
		while bone >= 0:
			chain = skeleton.get_bone_rest(bone) * chain
			bone = skeleton.get_bone_parent(bone)
		_shoulder_across[side] = chain.origin.x
		_hand_contact_basis[side] = skeleton.get_bone_global_rest(
			_hand[side]).basis.orthonormalized()


## True when every bone this needs was found. A rig without them is not an error
## worth stopping for -- the monster walks the way it used to -- but it is worth
## a check being able to say so.
func has_rig() -> bool:
	if _body < 0:
		return false
	for index in 2:
		if _upper[index] < 0 or _lower[index] < 0 or _hand[index] < 0:
			return false
	return true


## Where a hand should be, in the skeleton's own space, for a phase and a side.
##
## Measured forward of the shoulder, so the whole of a hand's stance is a
## straight slide backwards: the body covers one step while the hand it is
## standing on holds still, and that is the same motion seen from the body.
func hand_target(side: int, at_phase: float, scale: float) -> Vector3:
	var turn := fposmod(at_phase + 0.5 * float(side), 1.0)
	# How far the body travels while this hand is down. That, and not half a
	# stride, is how far the hand has to slide back through the body's space --
	# they are the same distance seen from two places, and if they differ the
	# hand skates by the difference.
	var slide := (stride_in_use() * stance_share) / maxf(scale, 0.0001)
	var forward := 0.0
	var lift := plant_height()
	if turn < stance_share:
		# On the ground: not moving. In the body's space that is a slide back.
		var through := turn / stance_share
		forward = slide * (0.5 - through)
	else:
		# In the air: back to the front, lifting on the way.
		var through := (turn - stance_share) / maxf(1.0 - stance_share, 0.001)
		forward = slide * (-0.5 + through)
		lift += sin(through * PI) * (step_lift_metres / maxf(scale, 0.0001))
	# **Forward is +Z here.** The visual root is turned a half turn so the
	# model's face lines up with the body's -Z, which leaves the skeleton's own
	# +Z pointing the way the monster walks. Getting this backwards slides a
	# planted hand along with the body instead of against it, and the hand ends
	# up covering twice the ground rather than none of it.
	return Vector3(float(_shoulder_across[side]) * track_width, lift, forward)


## The stride the monster is really taking: what was asked for, or what the
## arms can span, whichever is shorter. The enemy turns the gait by this, so a
## clamped stride shortens the steps rather than making the hands skate.
func stride_in_use() -> float:
	var span := _span() * arm_stretch_limit
	if span <= 0.0:
		return stride_metres
	# Work out how much fore/aft reach remains after the shoulder has used the
	# allowed crouch to come down toward the planted wrist. This keeps an
	# over-ambitious stride from being silently clamped inside the IK solve.
	var scale := maxf(_scale, 0.0001)
	var vertical := maxf(_shoulder_height - plant_height()
		- support_crouch_limit_metres / scale, 0.0)
	if vertical >= span:
		return 0.5
	var half_reach := sqrt(maxf(span * span - vertical * vertical, 0.0))
	var reachable_stride := 2.0 * half_reach * scale / maxf(stance_share, 0.01)
	return minf(stride_metres, maxf(reachable_stride, 0.5))


## How far a hand can be from the shoulder, in the skeleton's own units.
func _span() -> float:
	return (_upper_length + _lower_length) * 0.94


## The authored wrist height already puts the palm on the model floor. Keeping
## it is important: subtracting a guessed palm thickness here sinks the hand
## and forces the arm into the broken, folded-under pose this gait replaces.
func plant_height() -> float:
	return _plant_height + plant_height_offset / maxf(_scale, 0.0001)


## How far the body has to come down so the requested fore/aft hand position is
## inside the arm's comfortable span. Returned in metres for diagnostics and
## tuning; the bone pose converts it back into skeleton units.
func support_crouch_metres() -> float:
	var span := _span()
	if span <= 0.0:
		return 0.0
	var scale := maxf(_scale, 0.0001)
	var half := (stride_in_use() * stance_share * 0.5) / scale
	half = minf(half, span * 0.999)
	var vertical_reach := sqrt(maxf(span * span - half * half, 0.0))
	var standing_vertical := _shoulder_height - plant_height()
	var needed := maxf(standing_vertical - vertical_reach, 0.0) * scale
	return minf(needed, support_crouch_limit_metres)


## Stretch needed after the support crouch has done its share. This is computed
## from the furthest point of the planted stroke, so both hands keep one stable
## length through the cycle instead of visibly breathing in and out.
func arm_stretch_in_use() -> float:
	var span := _span()
	if span <= 0.0:
		return 1.0
	var scale := maxf(_scale, 0.0001)
	var half := (stride_in_use() * stance_share * 0.5) / scale
	var vertical := maxf(_shoulder_height - plant_height()
		- support_crouch_metres() / scale, 0.0)
	var needed := sqrt(half * half + vertical * vertical) / span
	return clampf(needed, 1.0, arm_stretch_limit)


## True while this hand is the one taking weight.
func is_planted(side: int, at_phase: float) -> bool:
	return fposmod(at_phase + 0.5 * float(side), 1.0) < stance_share


## One through the complete load-bearing stroke, zero through the middle of the
## swing. The short eased shoulders of the swing prevent a wrist snap without
## ever letting a planted palm tilt away from the ground.
func hand_contact_weight(side: int, at_phase: float) -> float:
	var turn := fposmod(at_phase + 0.5 * float(side), 1.0)
	if turn < stance_share:
		return 1.0
	var swing_share := maxf(1.0 - stance_share, 0.001)
	var through := (turn - stance_share) / swing_share
	var edge := minf(wrist_transition_share / swing_share, 0.49)
	if through < edge:
		var released := through / maxf(edge, 0.001)
		return 1.0 - released * released * (3.0 - 2.0 * released)
	if through > 1.0 - edge:
		var prepared := (through - (1.0 - edge)) / maxf(edge, 0.001)
		return prepared * prepared * (3.0 - 2.0 * prepared)
	return 0.0


func _process_modification() -> void:
	_apply()


func _process_modification_with_delta(_delta: float) -> void:
	_apply()


func _apply() -> void:
	calls += 1
	var skeleton := get_skeleton()
	if skeleton == null or not has_rig() or strength <= 0.0:
		return
	# The rig is built at the model's own scale and everything below is in that
	# space, so the stride has to come back out of metres.
	var scale := maxf(skeleton.global_transform.basis.get_scale().x, 0.0001)
	_scale = scale
	var turn := phase * TAU
	# Come down far enough to keep the palm on the floor with a visibly bent arm,
	# then dip a little between catches. Twice a cycle because there are two
	# plants. Raising the target instead is the old mid-air paddling failure.
	var crouch := support_crouch_metres() / scale
	var bob := (1.0 - cos(turn * 2.0)) * 0.5 * (bob_metres / scale)
	var drop := (crouch + bob) * strength
	skeleton.set_bone_pose_position(_body,
		skeleton.get_bone_pose_position(_body) - Vector3.UP * drop)
	var roll := deg_to_rad(body_roll_degrees) * sin(turn) * strength
	skeleton.set_bone_pose_rotation(_body,
		skeleton.get_bone_pose_rotation(_body) * Quaternion(Vector3.FORWARD, roll))
	var pitch := deg_to_rad(body_pitch_degrees) * sin(turn * 2.0) * strength
	skeleton.set_bone_pose_rotation(_body,
		skeleton.get_bone_pose_rotation(_body) * Quaternion(Vector3.RIGHT, pitch))

	var stretch := lerpf(1.0, arm_stretch_in_use(), strength)
	for side in 2:
		_stretch_bone(skeleton, _upper[side], stretch)
		_stretch_bone(skeleton, _lower[side], stretch)
		var shoulder_pose := skeleton.get_bone_global_pose(_upper[side])
		var target := hand_target(side, phase, scale)
		_reach(skeleton, side, shoulder_pose, target, stretch)


## Lengthens along the bone's local +Y axis, which is the chain axis in this
## rig. Preserve any scale authored by the clip on the other axes.
func _stretch_bone(skeleton: Skeleton3D, bone: int, stretch: float) -> void:
	var pose_scale := skeleton.get_bone_pose_scale(bone)
	pose_scale.y *= stretch
	skeleton.set_bone_pose_scale(bone, pose_scale)


## Two-bone inverse kinematics: turns the shoulder and the elbow so the hand
## lands on `target`, and blends that against whatever the clip was doing by
## `strength`.
##
## The chain runs along each bone's +Y, which is why a child's rest origin is
## the length of its parent. The elbow's fold is the law of cosines; which way
## it folds is the one thing the arithmetic cannot decide, so it is given.
func _reach(skeleton: Skeleton3D, side: int, shoulder_pose: Transform3D,
		target: Vector3, stretch: float) -> void:
	var to_target := target - shoulder_pose.origin
	var reach := to_target.length()
	var upper_length := _upper_length * stretch
	var lower_length := _lower_length * stretch
	var longest := (upper_length + lower_length) * 0.999
	var shortest := absf(upper_length - lower_length) * 1.001 + 0.0001
	if reach < 0.0001:
		return
	reach = clampf(reach, shortest, longest)
	var along := to_target.normalized()

	# The plane the arm folds in. Its hinge is the body's own right, made
	# square to the reach so the fold stays in one plane whatever the reach.
	var parent := skeleton.get_bone_parent(_upper[side])
	var body_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 \
		else Basis()
	var hinge := body_basis.x.normalized()
	hinge = (hinge - along * hinge.dot(along))
	if hinge.length_squared() < 0.000001:
		hinge = body_basis.z.normalized()
		hinge = (hinge - along * hinge.dot(along))
		if hinge.length_squared() < 0.000001:
			return
	hinge = hinge.normalized()
	if not elbows_point_back:
		hinge = -hinge

	# The shoulder opens off the straight line by this much, and the elbow
	# closes by the rest of it.
	var shoulder_open := acos(clampf(
		(upper_length * upper_length + reach * reach - lower_length * lower_length)
			/ (2.0 * upper_length * reach), -1.0, 1.0))
	var upper_dir := along.rotated(hinge, shoulder_open)
	var elbow := shoulder_pose.origin + upper_dir * upper_length
	var lower_dir := (target - elbow)
	if lower_dir.length_squared() < 0.000001:
		return
	lower_dir = lower_dir.normalized()

	_point(skeleton, _upper[side], upper_dir, hinge)
	_point(skeleton, _lower[side], lower_dir, hinge)
	# A planted wrist uses the asset's actual support orientation. The hand bone
	# is twisted about all three local axes, so treating +Y as the fingers and +Z
	# as the palm normal produces the folded-under hand seen in game. The global
	# rest basis is the calibration supplied by the rig itself: it leaves the
	# palm mesh horizontal and its fingers pointing along the monster's +Z walk.
	_orient_hand(skeleton, side,
		strength * hand_contact_weight(side, phase))


func _orient_hand(skeleton: Skeleton3D, side: int, blend: float) -> void:
	if blend <= 0.0:
		return
	var parent := skeleton.get_bone_parent(_hand[side])
	var parent_basis := skeleton.get_bone_global_pose(parent).basis.orthonormalized() \
		if parent >= 0 else Basis()
	var local := parent_basis.inverse() * (_hand_contact_basis[side] as Basis)
	skeleton.set_bone_pose_rotation(_hand[side],
		skeleton.get_bone_pose_rotation(_hand[side]).slerp(
			local.get_rotation_quaternion(), clampf(blend, 0.0, 1.0)))


## Turns one bone so its +Y runs along `direction`, keeping `hinge` as its +X so
## the joint does not spin about its own length. Blended in by `strength`.
func _point(skeleton: Skeleton3D, bone: int, direction: Vector3, hinge: Vector3) -> void:
	var across := hinge - direction * hinge.dot(direction)
	if across.length_squared() < 0.000001:
		return
	across = across.normalized()
	var wanted := Basis(across, direction, across.cross(direction))
	var parent := skeleton.get_bone_parent(bone)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 \
		else Basis()
	var local := parent_basis.inverse() * wanted
	skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone).slerp(
		local.get_rotation_quaternion(), strength))
