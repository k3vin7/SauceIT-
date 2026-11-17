extends Node3D
## Two actual AnimationPlayers: locomotion and bottle actions can overlap.
const LIBRARY := preload("res://assets/players/first_person/movement.tres")
var movement: Node3D
var action: Node3D
var movement_player: AnimationPlayer
var action_player: AnimationPlayer
var grounded := true
var initialized := false
var was_firing := false
var was_shaking := false
var pose := Transform3D.IDENTITY

func _init() -> void:
	movement = Node3D.new()
	movement.name = "Locomotion"
	add_child(movement)
	action = Node3D.new()
	action.name = "BottleAction"
	movement.add_child(action)
	movement_player = _make_player(movement)
	action_player = _make_player(action)

func _make_player(target: Node3D) -> AnimationPlayer:
	var player := AnimationPlayer.new()
	target.add_child(player)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.add_animation_library("", LIBRARY)
	return player

func reset() -> void:
	movement_player.stop()
	action_player.stop()
	movement.transform = Transform3D.IDENTITY
	action.transform = Transform3D.IDENTITY
	pose = Transform3D.IDENTITY
	initialized = false
	was_firing = false
	was_shaking = false

func _play(player: AnimationPlayer, clip: String, blend := 0.07) -> void:
	if player.current_animation != clip or not player.is_playing():
		player.play(clip, blend)

func advance(dt: float, shooter, enabled: bool, strength: float) -> void:
	if not enabled:
		reset()
		return
	var body = shooter.player
	var on_floor: bool = body.is_on_floor()
	if not initialized:
		grounded = on_floor
		initialized = true
	var speed := Vector2(body.velocity.x, body.velocity.z).length()
	if on_floor and speed > 0.3:
		_play(movement_player, "run" if speed > body.walk_speed * 1.15 else "walk", 0.14)
	else:
		movement_player.stop()
		movement.transform = Transform3D.IDENTITY
	grounded = on_floor
	var shaking: bool = shooter.bottle_shake_show > 0.08
	var firing: bool = shooter.was_firing
	var current := str(action_player.current_animation)
	if shaking:
		if not was_shaking:
			_play(action_player, "shake_start", 0.04)
		elif current != "shake_start" or not action_player.is_playing():
			_play(action_player, "shake_loop", 0.06)
	elif was_shaking:
		_play(action_player, "recover", 0.1)
	elif current != "recover" or not action_player.is_playing():
		action_player.stop()
		action.transform = Transform3D.IDENTITY
	was_firing = firing
	was_shaking = shaking
	movement_player.advance(minf(dt, 0.05))
	action_player.advance(minf(dt, 0.05))
	var combined := movement.transform * action.transform
	pose = Transform3D(Basis(Quaternion.IDENTITY.slerp(combined.basis.get_rotation_quaternion(), strength)), combined.origin * strength)
