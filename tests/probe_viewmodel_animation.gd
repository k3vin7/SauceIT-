extends SceneTree
class Body extends RefCounted:
	var velocity := Vector3.ZERO
	var walk_speed := 5.0
	var floor_contact := true
	func is_on_floor() -> bool:
		return floor_contact
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var animation = preload("res://scripts/viewmodel_animation.gd").new()
	root.add_child(animation)
	var body := Body.new()
	var shooter := {"player": body, "bottle_shake_show": 0.0, "was_firing": false}
	for firing in [false, true, false]:
		shooter.was_firing = firing
		for frame in 60:
			animation.advance(1.0 / 60, shooter, true, 1.0)
			assert(animation.pose == Transform3D.IDENTITY, "standing/fire moved viewmodel")
	body.velocity.x = 3.0
	for frame in 20:
		animation.advance(1.0 / 60, shooter, true, 1.0)
	assert(animation.movement_player.current_animation == "walk")
	assert(animation.pose.origin.length() > 0.001)
	body.velocity.x = 8.0
	animation.advance(0.016, shooter, true, 1.0)
	assert(animation.movement_player.current_animation == "run")
	body.velocity = Vector3.ZERO
	animation.advance(0.016, shooter, true, 1.0)
	assert(animation.pose == Transform3D.IDENTITY, "stopping leaves sway")
	body.floor_contact = false
	body.velocity.y = 7
	animation.advance(0.016, shooter, true, 1.0)
	assert(animation.pose == Transform3D.IDENTITY, "airborne sway")
	shooter.bottle_shake_show = 1.0
	for frame in 30:
		animation.advance(1.0 / 60, shooter, true, 1.0)
	assert(animation.action_player.current_animation == "shake_loop")
	assert(animation.pose != Transform3D.IDENTITY, "intentional shake removed")
	animation.reset()
	animation.queue_free()
	await process_frame
	print("VIEWMODEL_ANIMATION_OK")
	quit()