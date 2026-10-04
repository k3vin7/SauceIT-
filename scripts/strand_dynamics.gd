class_name StrandDynamics
extends RefCounted

## **The shape of a strand between its points, and nothing else.**
##
## Which pairs are still joined, how far they may drift before they are not, how
## an attached burst follows the player, how pressure leaves it when the trigger
## does, and how the gaps are pulled back. No raycasts, no collision, no damage,
## no contamination, no wire, no ribbons.
##
## **Every call is static and every call is told everything.** There is no state
## here to go stale and no reference back to the world, so a number changed in the
## inspector is in effect on the next call without this knowing a number exists.
##
## **A point is read by duck typing, not by type.** `MayoPoint` is an inner class
## of the world, so naming it here would make the two scripts refer to each other.
## The fields read are `position`, `velocity`, `launch_direction`, `phase`,
## `powered`, `severed` and `burst_index`; `phase` is compared against an `air`
## value handed in, for the same reason.
##
## **Invariants these rely on.** `points` is ordered front-to-back -- index 0 is
## the tip furthest from the muzzle, the last index is at the muzzle -- and a
## burst occupies one contiguous run of it. Points are updated in place: nothing
## here copies the array or a point, because the caller holds the same objects.
## `severed` latches, and only `update_connections` sets it, so the answer cannot
## change between the constraint, the ribbon and the shadow, or change back.


## True while a pair is still one piece of sauce.
##
## Unused: `enforce_spacing` inlines the same test because it runs once per pair
## per pass. Kept with the rest of the module rather than dropped, since deleting
## it is a change of its own.
static func points_connected(front, back) -> bool:
	return front.burst_index == back.burst_index and not back.severed


## Index of the last point of the burst that the point at `start` belongs to.
static func burst_end(points: Array, start: int) -> int:
	var burst: int = points[start].burst_index
	var last := start
	while last + 1 < points.size() and points[last + 1].burst_index == burst:
		last += 1
	return last


## Which threshold a pair is held to: the taut one while either end is still
## under pressure, the slack one once both are falling.
static func break_distance_squared(front, back, taut: float, slack: float,
		extend_speed: float, emission_speed: float) -> float:
	var break_distance := taut
	if front != null and back != null and not front.powered and not back.powered:
		break_distance = slack
	break_distance *= extend_speed / maxf(emission_speed, 0.001)
	return break_distance * break_distance


## Walks the strand once and latches the pairs that have come apart. Called once
## a frame, before anything asks whether a pair is joined.
static func update_connections(points: Array, taut: float, slack: float,
		extend_speed: float, emission_speed: float) -> void:
	for i in range(1, points.size()):
		var back = points[i]
		if back.severed:
			continue
		var front = points[i - 1]
		if front.burst_index != back.burst_index:
			back.severed = true
			continue
		if front.position.distance_squared_to(back.position) \
				> break_distance_squared(front, back, taut, slack,
					extend_speed, emission_speed):
			back.severed = true


## The strand drags behind a moving player.
##
## `t` is a point's place inside its own burst, not inside the array: measured
## against the whole array it would skew the bend of the burst being extended
## whenever an earlier one is still falling. Only the burst still at the muzzle
## follows; detached ones are on their own.
static func apply_inertial_follow(points: Array, burst_index: int,
		player_movement: Vector3, air: int, front_follow: float,
		follow_curve_power: float) -> void:
	if player_movement.length_squared() <= 0.00000001 or points.is_empty():
		return
	var index := 0
	while index < points.size():
		var last := burst_end(points, index)
		if points[index].burst_index == burst_index:
			var denominator := maxf(float(last - index), 1.0)
			for i in range(index, last + 1):
				var point = points[i]
				if point.phase != air:
					continue
				var t := float(i - index) / denominator
				point.position += player_movement * lerpf(front_follow, 1.0, pow(t, follow_curve_power))
		index = last + 1


## Releasing the trigger drops the line pressure. The front of the strand is
## already coasting on its own momentum and keeps its speed, while the points
## still at the muzzle lose the most, so the trail that lands afterwards starts
## at full range and is drawn back toward the player.
##
## Only the burst that was being fired loses pressure, and `t` is measured inside
## it: an earlier burst is already coasting and must not be decayed twice.
static func apply_release_pressure_loss(points: Array, burst_index: int,
		air: int, release_pressure_loss: float,
		release_pressure_curve: float) -> void:
	if release_pressure_loss <= 0.0 or points.is_empty():
		return
	var start := 0
	while start < points.size():
		var last := burst_end(points, start)
		if points[start].burst_index == burst_index:
			var denominator := maxf(float(last - start), 1.0)
			for i in range(start, last + 1):
				var point = points[i]
				if point.phase != air:
					continue
				# The burst's index 0 is its front tip; its last index is the muzzle.
				var t := float(i - start) / denominator
				point.velocity *= 1.0 - release_pressure_loss * pow(t, release_pressure_curve)
				# Nothing is being pushed any more, so gravity takes over immediately.
				point.powered = false
		start = last + 1


## Pulls pairs that have stretched past their travel spacing back together.
##
## Only along the pair's own launch direction, and only the ends that are still
## in the air: a point that has landed is where it landed. Several passes, because
## one pass leaves the correction spread unevenly along a long strand.
static func enforce_spacing(points: Array, burst_index: int,
		attack_direction: Vector3, air: int, passes: int, point_spacing: float,
		extend_speed: float, emission_speed: float) -> void:
	if points.size() < 2:
		return
	for _pass in passes:
		for i in points.size() - 1:
			var front = points[i]
			var back = points[i + 1]
			# Inlined `points_connected`: this runs once per pair per pass.
			if front.burst_index != burst_index or back.severed:
				continue
			# Annotated, not inferred: a point arrives as Variant by design (see the
			# duck-typing note above), so nothing read off one has a static type.
			var direction: Vector3 = (front.launch_direction + back.launch_direction).normalized()
			if direction.length_squared() < 0.000001:
				direction = attack_direction
			var projected_gap: float = (front.position - back.position).dot(direction)
			var travel_spacing := point_spacing * extend_speed / maxf(emission_speed, 0.001)
			if projected_gap <= travel_spacing:
				continue
			var correction: Vector3 = direction * (projected_gap - travel_spacing)
			var front_free: bool = front.phase == air
			var back_free: bool = back.phase == air
			if front_free and back_free:
				front.position -= correction * 0.5
				back.position += correction * 0.5
			elif front_free:
				front.position -= correction
			elif back_free:
				back.position += correction
