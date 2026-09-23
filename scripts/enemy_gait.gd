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
## The body falls and is caught between plants, and rolls as the weight passes
## from one hand to the other. That part is added on top of the clip.
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
## **Clamped to what the arms can actually span.** The shoulders are higher off
## the ground than the arms are long, so the hands work in a narrow window fore
## and aft of the shoulder; ask for a longer stride than that and the solver
## quietly clamps the target, the hand stops holding still, and the walk goes
## back to paddling. `stride_in_use` is what the monster is really taking.
@export_range(0.5, 12.0, 0.1, "suffix:m") var stride_metres := 1.8

## The share of a step a hand spends on the ground. Above 0.5 both hands are
## down together for part of the cycle, which is what a heavy thing does.
@export_range(0.3, 0.9, 0.01) var stance_share := 0.62

## Nudges the plant height. The ground itself is not the target: the arms are
## shorter than the shoulders are high, so a hand aimed at the floor is a hand
## the arm cannot reach and the solver quietly clamps it, which puts the hand
## somewhere between the plant and the shoulder and lets it drift. The height
## the model was authored to stand at is taken off its own rest pose instead,
## and this moves it from there.
@export_range(-0.5, 0.5, 0.01, "suffix:m") var plant_height_offset := 0.0

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
	var span := _span()
	if span <= 0.0:
		return stride_metres
	# The hand can be at most a span from the shoulder, so half a stride's
	# reach out has to fit inside that with something left over to stand on.
	return minf(stride_metres, 2.0 * span * 0.9 * _scale / maxf(stance_share, 0.01))


## How far a hand can be from the shoulder, in the skeleton's own units.
func _span() -> float:
	return (_upper_length + _lower_length) * 0.94


## The height the hands plant at.
##
## **Worked back from the stride, not taken from the floor.** The arms are
## barely longer than the shoulders are high, so at the height the model rests
## its hands the arm is already at full stretch and has no room to swing fore or
## aft at all -- ask it to and the solver clamps, and the hand stops holding
## still. Planting a little higher buys that room: the monster crouches into its
## stride rather than reaching past what it has.
func plant_height() -> float:
	var span := _span()
	var half := (stride_in_use() * stance_share * 0.5) / maxf(_scale, 0.0001)
	half = minf(half, span * 0.9)
	var drop := sqrt(maxf(span * span - half * half, 0.0))
	var height := maxf(_shoulder_height - drop, _plant_height)
	return height + plant_height_offset / maxf(_scale, 0.0001)


## True while this hand is the one taking weight.
func is_planted(side: int, at_phase: float) -> bool:
	return fposmod(at_phase + 0.5 * float(side), 1.0) < stance_share


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
	# Twice a cycle, because both plants carry weight. Lowest between them.
	var drop := (1.0 - cos(turn * 2.0)) * 0.5 * (bob_metres / scale) * strength
	skeleton.set_bone_pose_position(_body,
		skeleton.get_bone_pose_position(_body) - Vector3.UP * drop)
	var roll := deg_to_rad(body_roll_degrees) * sin(turn) * strength
	skeleton.set_bone_pose_rotation(_body,
		skeleton.get_bone_pose_rotation(_body) * Quaternion(Vector3.FORWARD, roll))

	for side in 2:
		var shoulder_pose := skeleton.get_bone_global_pose(_upper[side])
		var shoulder := shoulder_pose.origin
		var target := hand_target(side, phase, scale)
		_reach(skeleton, side, shoulder_pose, target)


## Two-bone inverse kinematics: turns the shoulder and the elbow so the hand
## lands on `target`, and blends that against whatever the clip was doing by
## `strength`.
##
## The chain runs along each bone's +Y, which is why a child's rest origin is
## the length of its parent. The elbow's fold is the law of cosines; which way
## it folds is the one thing the arithmetic cannot decide, so it is given.
func _reach(skeleton: Skeleton3D, side: int, shoulder_pose: Transform3D,
		target: Vector3) -> void:
	var to_target := target - shoulder_pose.origin
	var reach := to_target.length()
	var longest := (_upper_length + _lower_length) * 0.999
	var shortest := absf(_upper_length - _lower_length) * 1.001 + 0.0001
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
		(_upper_length * _upper_length + reach * reach - _lower_length * _lower_length)
			/ (2.0 * _upper_length * reach), -1.0, 1.0))
	var upper_dir := along.rotated(hinge, shoulder_open)
	var elbow := shoulder_pose.origin + upper_dir * _upper_length
	var lower_dir := (target - elbow)
	if lower_dir.length_squared() < 0.000001:
		return
	lower_dir = lower_dir.normalized()

	_point(skeleton, _upper[side], upper_dir, hinge)
	_point(skeleton, _lower[side], lower_dir, hinge)
	# And the wrist. A hand pressed to the ground does not pivot on it: leave
	# the hand bone to the arm and the palm swings about the joint even though
	# the joint is planted, which is the same wander again one bone further
	# down. Fingers along the way it walks, palm to the floor.
	_point(skeleton, _hand[side], Vector3.BACK, hinge)


## Turns one bone so its +Y runs along `direction`, keeping `hinge` as its +X so
## the joint does not spin about its own length. Blended in by `strength`.
func _point(skeleton: Skeleton3D, bone: int, direction: Vector3, hinge: Vector3) -> void:
	var across := hinge - direction * hinge.dot(direction)
	if across.length_squared() < 0.000001:
		return
	across = across.normalized()
	var wanted := Basis(across, direction, across.cross(direction))
	var parent := skeleton.get_bone_parent(bone)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 \
		else Basis()
	var local := parent_basis.inverse() * wanted
	skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone).slerp(
		local.get_rotation_quaternion(), strength))
