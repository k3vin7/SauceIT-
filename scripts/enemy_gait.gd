class_name EnemyGait
extends SkeletonModifier3D

## Makes the burger monster walk on its hands rather than hang above them.
##
## The imported `Walk` clip swings the arms, and that is all it does: the body
## rides level while the arms paddle underneath it, which reads as a burger
## suspended in the air being rowed along. Two things are missing from it, and
## both are the same thing a walk cycle is made of.
##
## **The arms have to take weight.** A leg bends when it is under load and
## straightens as it pushes off; a straight limb swinging from the shoulder is a
## pendulum, not a step. So each arm gets extra flexion at the elbow, out of
## phase with the other, deepest as that arm passes under the body.
##
## **The body has to fall and be caught.** Nothing carries the weight between
## one hand landing and the next, so the body dips in the middle of each step
## and rises as a hand plants. That is the bob, and it is what makes the steps
## look like they touch the ground -- at twice the stride frequency, because
## there are two of them in a cycle.
##
## This runs as a `SkeletonModifier3D` rather than out of `_process`, which is
## the difference between adding to the clip and fighting it: a modifier is
## called after the animation has written its pose and before the skeleton is
## used, so what it writes is the clip's pose plus this rather than whichever of
## the two ran last.
##
## Everything here is **cosmetic**. It is driven by `phase`, which the enemy
## sets from the ground it has actually covered, so the gait cannot drift from
## the walking -- and nothing reads it back. No collider, no mask cell and no
## packet is touched by any of it.

## How far the monster travels in one full cycle -- two steps. The phase comes
## from distance rather than from time so the hands keep pace with the ground
## instead of sliding along it, which is most of what "paddling" looks like.
@export_range(0.5, 12.0, 0.1, "suffix:m") var stride_metres := 4.6

## How far the elbow bends beyond whatever the clip is already doing, at the
## deepest part of a step.
@export_range(0.0, 90.0, 1.0, "suffix:deg") var elbow_bend_degrees := 26.0

## And how much the shoulder gathers with it. Less than the elbow: a limb that
## folds at both joints equally reads as boneless.
@export_range(0.0, 60.0, 1.0, "suffix:deg") var shoulder_gather_degrees := 9.0

## How far the body drops between steps. It is the whole of the weight cue, so
## it is small on purpose -- a burger bouncing is a different animal.
@export_range(0.0, 0.6, 0.01, "suffix:m") var bob_metres := 0.11

## How much the body leans into each step, rocking side to side as the weight
## passes from one hand to the other.
@export_range(0.0, 20.0, 0.5, "suffix:deg") var body_roll_degrees := 3.5

## 0 standing still, 1 walking. Faded rather than switched, so coming to a stop
## settles instead of snapping upright.
var strength := 0.0

## Cycles, not radians: the whole number part is how many strides have been
## taken and the fraction is where in the current one the monster is.
var phase := 0.0

var _body := -1
var _upper := [-1, -1]
var _lower := [-1, -1]


func _ready() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	_body = skeleton.find_bone("Body")
	_upper = [skeleton.find_bone("Arm.L.Upper"), skeleton.find_bone("Arm.R.Upper")]
	_lower = [skeleton.find_bone("Arm.L.Lower"), skeleton.find_bone("Arm.R.Lower")]


## True when every bone this needs was found. A rig without them is not an
## error worth stopping for -- the monster simply walks the way it used to --
## but it is worth a check being able to say so.
func has_rig() -> bool:
	if _body < 0:
		return false
	for index in 2:
		if _upper[index] < 0 or _lower[index] < 0:
			return false
	return true


## How many times the skeleton has called this. Godot has had two names for the
## hook, and a modifier whose hook is never called is silent rather than loud --
## it just quietly does nothing -- so the checks count the calls.
var calls := 0


func _process_modification() -> void:
	_apply()


func _process_modification_with_delta(_delta: float) -> void:
	_apply()


func _apply() -> void:
	calls += 1
	var skeleton := get_skeleton()
	if skeleton == null or not has_rig() or strength <= 0.0:
		return
	var turn := phase * TAU
	for side in 2:
		# The two arms are half a cycle apart: one is under the body while the
		# other is reaching.
		var swing := turn + PI * float(side)
		# Deepest as the arm passes under, and never negative -- an elbow that
		# bends backwards is worse than one that does not bend at all.
		var load := maxf(sin(swing), 0.0)
		var bend := deg_to_rad(elbow_bend_degrees) * load * strength
		var gather := deg_to_rad(shoulder_gather_degrees) * load * strength
		# Added to the clip's pose rather than replacing it, which is the whole
		# point of doing this here.
		skeleton.set_bone_pose_rotation(_lower[side],
			skeleton.get_bone_pose_rotation(_lower[side])
				* Quaternion(Vector3.RIGHT, bend))
		skeleton.set_bone_pose_rotation(_upper[side],
			skeleton.get_bone_pose_rotation(_upper[side])
				* Quaternion(Vector3.RIGHT, -gather))

	# Twice a cycle, because both steps carry weight. Lowest between the two,
	# highest as a hand plants.
	var drop := (1.0 - cos(turn * 2.0)) * 0.5 * bob_metres * strength
	skeleton.set_bone_pose_position(_body,
		skeleton.get_bone_pose_position(_body) - Vector3.UP * drop)
	var roll := deg_to_rad(body_roll_degrees) * sin(turn) * strength
	skeleton.set_bone_pose_rotation(_body,
		skeleton.get_bone_pose_rotation(_body) * Quaternion(Vector3.FORWARD, roll))
