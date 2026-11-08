extends SceneTree
func _initialize():
	call_deferred("run")
func run():
	var rear = MayoEnemy.new()
	var front = MayoEnemy.new()
	root.add_child(rear)
	root.add_child(front)
	rear.health = 10
	front.health = 10
	rear.radius = 1
	front.radius = 1
	front.position = Vector3(0,0,-3)
	rear.crowd_peers = [rear,front]
	rear._crowd_side = 1
	var right: Vector3 = rear._crowd_direction(Vector3.FORWARD)
	rear._passing_left = 0
	rear._crowd_smoothed = Vector3.ZERO
	rear._crowd_side = -1
	var left: Vector3 = rear._crowd_direction(Vector3.FORWARD)
	if absf(right.x) < 0.1 or right.x * left.x >= 0 or right.z >= 0 or left.z >= 0:
		push_error("blocked pursuers did not spread while advancing")
		quit(1)
		return
	# Slight changes across the centre must not reverse the chosen side.
	for i in 40:
		front.position.x = 0.25 if i % 2 == 0 else -0.25
		var stable: Vector3 = rear._crowd_direction(Vector3.FORWARD)
		if stable.x * left.x <= 0:
			push_error("passing direction oscillated within its commitment window")
			quit(1)
			return
	front.position = Vector3(30,0,0)
	for i in 180:
		rear._crowd_direction(Vector3.FORWARD)
	if rear._crowd_direction(Vector3.FORWARD).distance_to(Vector3.FORWARD) > 0.001:
		push_error("distant enemies affect steering")
		quit(1)
		return
	print("CROWD_STEERING_OK")
	quit()
