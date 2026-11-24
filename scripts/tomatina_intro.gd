extends Node3D
## The cold open is staged over the playable street and plaza. Its performers
## and projectiles are presentation only, and never enter the enemy roster.

const GUEST := preload("res://assets/characters/Stage2_FestivalGuest/Stage2_FestivalGuest.glb")
const CROWD := preload("res://assets/audio/tomatina_intro/crowd.wav")
const HOSE := preload("res://assets/audio/tomatina_intro/hose.wav")
const ENGINE := preload("res://assets/audio/tomatina_intro/bongo_engine.wav")
const LATCH := preload("res://assets/audio/tomatina_intro/bongo_latch.wav")
const GROWL := preload("res://assets/audio/tomatina_intro/tomato_growl.wav")
const SPLAT := preload("res://assets/audio/sauce/splat_2.wav")
const PANIC_BREATH := preload("res://assets/audio/tomatina_intro/panic_breath.wav")
const DISTRESS_GRADE := preload("res://scripts/tomatina_intro_grade.gdshader")
const STREET_CLOSE := 3.6
const PLAZA_WIDE := 7.1
const SPLASH_CLOSE := 9.4
const CRATE_ATTACK := 11.65
const TRUCK_ATTACK := 14.4
const PANIC_CHASE := 15.93
const ARRIVAL := 18.35
const TRUCK_REAR := 20.98
const LATCH_TIME := 22.55
const FIRST_PERSON := 23.15
const DURATION := 24.05
const THROW_PERIOD := 34.0 / 24.0
const THROW_RELEASE := 14.0 / 24.0
const DROP_COUNT := 88
const SHIRTS := [Color("f4e4cb"), Color("dcad53"), Color("669d98"),
	Color("d87957"), Color("6887a7"), Color("8da475")]
const SKIN := [Color("cf906a"), Color("a36648"), Color("d7a37c"), Color("84523b")]

class Guest:
	var actor: Node3D
	var animation: AnimationPlayer
	var mug: Node3D
	var hand: BoneAttachment3D
	var release_offset: Vector3
	var skeleton: Skeleton3D
	var head: int
	var tomato: Node3D
	var start: Vector3
	var yaw: float
	var phase: float
	var action: String
	var escape: Vector3
	var at_square: bool

class Toss:
	var thrower: Guest
	var receiver: Guest
	var release_time: float
	var hit_time: float
	var from: Vector3
	var contact: Vector3
	var splash: Array[MeshInstance3D] = []
	var smear: Node3D

var world
var active := true
var elapsed := 0.0
var entrance
var camera: Camera3D
var layer: CanvasLayer
var blackout: ColorRect
var grade: ColorRect
var party: Node3D
var performers: Node3D
var passengers: Node3D
var guests: Array[Guest] = []
var tosses: Array[Toss] = []
var incoming_tosses: Dictionary = {}
var outgoing_tosses: Dictionary = {}
var victim: Guest
var runner: Guest
var street := TomatinaMap.at_cell(Vector2(29.25, 222.25))
var square := TomatinaMap.at_cell(Vector2(30.3, 29.3))
var crate_at: Vector3
var truck_at: Vector3
var crate_monster: Node3D
var truck_monster: Node3D
var truck_grunt: Node3D
var crate_planks: Array[MeshInstance3D] = []
var hose_cloud: MultiMeshInstance3D
var water_core := []
var water_core_material: StandardMaterial3D
var nozzle: Vector3
var hose_from: Vector3
var hose_sections: Array[MeshInstance3D] = []
var hose_tip: MeshInstance3D
var held_visibility: Dictionary = {}
var frozen_before: Dictionary = {}
var hud_was_visible: bool
var restored_world := false
var first_person_ready := false
var crowd_audio: AudioStreamPlayer
var hose_audio: AudioStreamPlayer
var engine_audio: AudioStreamPlayer
var effects: AudioStreamPlayer
var splat_audio: AudioStreamPlayer
var escape_audio: AudioStreamPlayer
var tomato_mesh: SphereMesh
var leaf_mesh: CylinderMesh
var pulp_mesh: SphereMesh


func prepare(stage: Node3D, staggered: bool) -> void:
	world = stage
	entrance = world._tomatina_entrance
	active = false
	performers = Node3D.new()
	performers.name = "FestivalBeforeTheAttack"
	performers.hide()
	add_child(performers)
	party = Node3D.new()
	party.name = "FestivalGuests"
	performers.add_child(party)
	_build_tomato_meshes()
	_build_street()
	if staggered:
		await get_tree().process_frame
	_build_square()
	if staggered:
		await get_tree().process_frame
	_build_passengers()
	passengers.hide()


func begin(stage: Node3D) -> void:
	if performers == null:
		await prepare(stage, false)
	active = true
	performers.show()
	passengers.show()
	world.set_gameplay_input_enabled(false)
	hud_was_visible = world._hud_layer.visible
	world._hud_layer.hide()
	for peer_id in world.shooter_ids():
		var shooter = world.shooter_for(peer_id)
		frozen_before[shooter.player] = shooter.player.frozen
		shooter.player.frozen = true
		_hide_temporarily(shooter.player)
	for enemy in world._enemies:
		_hide_temporarily(enemy)
	for item in [world._boss_entrance, world._truck_arrival, world._pump_generator,
			world._siren_label, world._camera, world.get_node_or_null("Siren"),
			world.get_node_or_null("StartArrow")]:
		_hide_temporarily(item)
	for stand in world.find_children("HoseStand*", "Node3D", false, false):
		_hide_temporarily(stand)
	world._tomatina_art.set_before_attack(true)
	_set_pavement_phase(true)

	camera = Camera3D.new()
	camera.name = "TomatinaFilmCamera"
	camera.near = 0.055
	add_child(camera)
	camera.make_current()
	layer = CanvasLayer.new()
	layer.layer = 7
	add_child(layer)
	grade = ColorRect.new()
	grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var color_pass := ShaderMaterial.new()
	color_pass.shader = DISTRESS_GRADE
	grade.material = color_pass
	layer.add_child(grade)
	grade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grade.hide()
	blackout = ColorRect.new()
	blackout.color = Color.BLACK
	blackout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(blackout)
	blackout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	entrance.approach(13.0, 0.0)
	entrance.open_doors(0.0)

	crowd_audio = _audio_loop(CROWD)
	hose_audio = _audio_loop(HOSE)
	engine_audio = _audio_loop(ENGINE)
	effects = AudioStreamPlayer.new()
	effects.bus = &"SFX"
	add_child(effects)
	splat_audio = AudioStreamPlayer.new()
	splat_audio.bus = &"SFX"
	splat_audio.stream = SPLAT
	splat_audio.volume_db = -5.0
	add_child(splat_audio)
	escape_audio = AudioStreamPlayer.new()
	escape_audio.bus = &"SFX"
	escape_audio.stream = PANIC_BREATH
	escape_audio.volume_db = -3.0
	add_child(escape_audio)
	_render(0.0)


func _process(delta: float) -> void:
	if not active:
		return
	var previous := elapsed
	elapsed = minf(elapsed + delta, DURATION)
	_render(previous)
	if elapsed >= DURATION:
		_finish()


## Cut to the end: the world is put back exactly as the full run leaves it.
func skip() -> void:
	if active:
		_finish()


func music_duck() -> float:
	return 27.0 * smoothstep(CRATE_ATTACK - .48, CRATE_ATTACK + .28, elapsed) \
		* (1.0 - smoothstep(FIRST_PERSON, DURATION, elapsed))


func _render(previous: float) -> void:
	var t := elapsed
	if t < ARRIVAL:
		_animate_crowd(t)
		_animate_tosses(t)
		_animate_monsters(t)
		_animate_water(t)
	if t < STREET_CLOSE:
		_shot(street, Vector3(6, 4.9, 10), Vector3(2.8, 3.45, 6.8),
			Vector3(-.5, 1.24, -3.8), Vector3(-.2, 1.12, -5), t / STREET_CLOSE, 67)
	elif t < PLAZA_WIDE:
		_shot(street, Vector3(-4.8, 2.27, 4.1), Vector3(-3.68, 1.92, 3.35),
			Vector3(-1.15, 1.61, -.4), Vector3(-.14, 1.7, -.62),
			inverse_lerp(STREET_CLOSE, PLAZA_WIDE, t), 52)
	elif t < SPLASH_CLOSE:
		_shot(square, Vector3(7.3, 5, 11.7), Vector3(5.75, 3.85, 9.9),
			Vector3(-2.15, 1.39, -1.8), Vector3(-2.25, 1.35, -1.65),
			inverse_lerp(PLAZA_WIDE, SPLASH_CLOSE, t), 60)
	elif t < CRATE_ATTACK:
		_shot(square, Vector3(3.0, 2.08, 2.2), Vector3(2.3, 1.99, 1.38),
			Vector3(1.52, 1.76, -1.5), Vector3(.98, 1.68, -1.96),
			inverse_lerp(SPLASH_CLOSE, CRATE_ATTACK, t), 56)
	elif t < TRUCK_ATTACK:
		_shot(square, Vector3(-4.75, 1.9, .4), Vector3(-5.4, 2.35, 2.2),
			Vector3(-.3, 1.3, -3.14), Vector3(2.0, 1.74, -.47),
			inverse_lerp(CRATE_ATTACK, TRUCK_ATTACK, t), 62)
	elif t < PANIC_CHASE:
		_shot(square, Vector3(8.7, 2.7, 7.15), Vector3(5.7, 3.87, 12.0),
			Vector3(5.75, 1.8, -.7), Vector3(.8, 1.3, 1.25),
			inverse_lerp(TRUCK_ATTACK, PANIC_CHASE, t), 65)
	elif t < ARRIVAL:
		var run_time := t - PANIC_CHASE
		var shake := Vector3(.075 * sin(run_time * 19.0), .085 * sin(run_time * 27.0), 0)
		_shot(runner.actor.position, Vector3(-1.87, 1.53, 4.4) + shake,
			Vector3(-1.43, 1.42, 3.5) + shake, Vector3(.45, 1.54, -.8),
			Vector3(.58, 1.45, -1.38), run_time / (ARRIVAL - PANIC_CHASE), 64)
		camera.rotation.z += .055 * sin(run_time * 10.5)
	elif t < FIRST_PERSON:
		_prepare_arrival()
		var travel := clampf(inverse_lerp(ARRIVAL, 21.38, t), 0.0, 1.0)
		var distance := 13.0 * pow(1.0 - travel, 1.65)
		entrance.approach(distance, sin(travel * 35.0) * .04 * (1.0 - travel))
		var truck_at_gate := TomatinaMap.party_truck_position()
		var anchor := TomatinaMap.entrance_position()
		if t < TRUCK_REAR:
			var focus := anchor.lerp(truck_at_gate, .44) + Vector3(0, 2.7, distance * .48)
			_shot(anchor, Vector3(-9.45, 3.45, 20.5), Vector3(-6, 2.85, 14.6),
				focus - anchor, focus - anchor, inverse_lerp(ARRIVAL, TRUCK_REAR, t), 63)
		else:
			_shot(truck_at_gate, Vector3(-.64, 2.2, 7.12), Vector3(-.16, 2.1, 6.16),
				Vector3(0, 1.94, 2.8), Vector3(0, 2.01, 2.9),
				inverse_lerp(TRUCK_REAR, 22.3, t), 55)
		passengers.position.y = .015 * sin(travel * 37.0)
		if t >= LATCH_TIME:
			entrance.open_doors(smoothstep(LATCH_TIME + .09, FIRST_PERSON - .035, t))
	else:
		_prepare_first_person()

	var fade_in := 1.0 - smoothstep(.11, 1.18, t)
	var first_black := smoothstep(17.28, 17.95, t) * (1.0 - smoothstep(ARRIVAL, 19.03, t))
	var second_black := smoothstep(21.96, 22.51, t) * (1.0 - smoothstep(FIRST_PERSON, DURATION, t))
	blackout.color.a = maxf(fade_in, maxf(first_black, second_black))
	var fear := smoothstep(CRATE_ATTACK - .22, TRUCK_ATTACK + .82, t)
	grade.visible = fear > 0.0 and t < ARRIVAL
	if grade.visible:
		grade.material.set_shader_parameter("distress", fear)
	_sound_cues(previous, t)


func _shot(anchor: Vector3, start: Vector3, end: Vector3, target_start: Vector3,
		target_end: Vector3, progress: float, fov: float) -> void:
	var blend := smoothstep(0.0, 1.0, progress)
	camera.global_position = anchor + start.lerp(end, blend)
	camera.look_at(anchor + target_start.lerp(target_end, blend))
	camera.fov = fov


func _hide_temporarily(item: Node3D) -> void:
	if is_instance_valid(item):
		held_visibility[item] = item.visible
		item.hide()


func _set_pavement_phase(before_attack: bool) -> void:
	for tile in world._floor.grid.tile_count():
		world._floor.grid.tile_material(tile).set_shader_parameter("festival_before_attack", before_attack)


func _prepare_arrival() -> void:
	if restored_world:
		return
	restored_world = true
	world._tomatina_art.set_before_attack(false)
	_set_pavement_phase(false)
	performers.hide()


func _prepare_first_person() -> void:
	if first_person_ready:
		return
	first_person_ready = true
	_prepare_arrival()
	passengers.hide()
	entrance.park()
	for item in held_visibility:
		if is_instance_valid(item):
			item.visible = held_visibility[item]
	world.set_first_person(true)
	world._update_camera()
	world._camera.make_current()


func _finish() -> void:
	_prepare_first_person()
	active = false
	for player in frozen_before:
		if is_instance_valid(player):
			player.frozen = frozen_before[player]
	world._hud_layer.visible = hud_was_visible
	world.set_gameplay_input_enabled(true)
	passengers.queue_free()
	queue_free()


func _build_street() -> void:
	_add_guest(street, Vector3(-1.32, 0, -.2), -.24, "Sip", .24)
	var surprised := _add_guest(street, Vector3(1.05, 0, .38), -.58, "Cheer", .6)
	_add_guest(street, Vector3(-3.85, 0, -4.5), .96, "Throw", .05)
	var pitcher := _add_guest(street, Vector3(2.45, 0, -7.5), -1.03, "Throw", .72)
	var back_guest := _add_guest(street, Vector3(-.7, 0, -10.3), .57, "Cheer", .2)
	var back_pitcher := _add_guest(street, Vector3(2.55, 0, -12.0), -1.4, "Throw", 1.0)
	_add_guest(street, Vector3(-4, 0, -13.7), .38, "Sip", 1.1)
	_add_guest(street, Vector3(.9, 0, -15.8), -.65, "Throw", 1.16)
	_add_toss(back_pitcher, back_guest, 1.7, 2.24)
	_add_toss(pitcher, surprised, 4.05, 4.69)


func _build_square() -> void:
	crate_at = square + Vector3(-.25, 0, -3.5)
	truck_at = square + Vector3(6.9, 0, -1.6)
	var art = world._tomatina_art
	art.film_prop("TomatoCrateStack", performers, crate_at, Vector3(2.35, 1.14, 1.46), -.25)
	art.film_prop("TomatoTruck", performers, truck_at, Vector3(3.4, 3.15, 6.75), .64)
	art.film_prop("FireEngine", performers, square + Vector3(-7.85, 0, -5.0),
		Vector3(3.25, 3.4, 7.6), -.36)
	for index in 5:
		var plank := _box(Vector3(.31, .087, 1.15), Color("a47742"), performers)
		plank.position = crate_at + Vector3((index - 2) * .34, 1.18, .05)
		crate_planks.append(plank)
	_add_guest(square, Vector3(-6.1, 0, -.6), .93, "Hose", .2, Vector2(-1, .5))
	var pitcher := _add_guest(square, Vector3(-3.9, 0, 3.05), 2.03, "Throw", .25, Vector2(-.9, .45))
	runner = _add_guest(square, Vector3(-1.5, 0, 4.15), -2.1, "Cheer", .6, Vector2(-.16, 1))
	victim = _add_guest(square, Vector3(1.75, 0, -1.35), .02, "Cheer", .7)
	var onlooker := _add_guest(square, Vector3(3.55, 0, 2.35), -1.4, "Throw", .12, Vector2(.18, 1))
	var close_pitcher := _add_guest(square, Vector3(5.05, 0, 3.5), -1.57, "Throw", .45, Vector2(.65, .8))
	_add_guest(square, Vector3(3.25, 0, -5.55), -.2, "Throw", .35, Vector2(.15, -1))
	_add_guest(square, Vector3(-3.45, 0, -4.2), .83, "Throw", .93, Vector2(-.5, -1))
	_add_guest(square, Vector3(-8.7, 0, 3.4), 1.48, "Cheer", .3, Vector2(-.9, .68))
	_add_guest(square, Vector3(-3.6, 0, 7.7), -2.2, "Throw", .75, Vector2(-.4, 1))
	_add_guest(square, Vector3(4.4, 0, 7.35), -.94, "Sip", .85, Vector2(.8, 1))
	_add_guest(square, Vector3(8.5, 0, -5.5), -.65, "Cheer", .26, Vector2(.85, -.6))
	_add_guest(square, Vector3(-.09, 0, -8.5), .6, "Throw", 1.05, Vector2(-.15, -1))
	_add_toss(pitcher, onlooker, 7.82, 8.49)
	_add_toss(close_pitcher, victim, 9.52, 10.11)
	crate_monster = TomatoVisuals.brute(1.06)
	truck_monster = TomatoVisuals.brute(1.37)
	truck_grunt = TomatoVisuals.grunt(.71, 1)
	for monster in [crate_monster, truck_monster, truck_grunt]:
		performers.add_child(monster)
		monster.hide()
	_set_brute_glare(crate_monster)
	_set_brute_glare(truck_monster)
	_build_water()


func _set_brute_glare(monster: Node3D) -> void:
	monster.get_node("CrookedGrin/Tongue").hide()
	for side in ["L", "R"]:
		var eye := monster.get_node("Eye" + side) as Node3D
		eye.scale.y *= .71
		for feature in ["Pupil", "Glint"]:
			var part := monster.get_node(feature + side) as Node3D
			part.position.y = lerpf(part.position.y, eye.position.y, .67)
		var brow := monster.get_node("Brow" + side) as Node3D
		brow.scale *= Vector3(1.22, 1.6, 1.1)
		brow.rotation.z = -.48 if side == "L" else .48
		brow.position.y = lerpf(brow.position.y, eye.position.y, .41)


func _add_guest(anchor: Vector3, offset: Vector3, yaw: float, action: String, phase: float,
		escape_direction := Vector2.ZERO) -> Guest:
	var guest := Guest.new()
	var index := guests.size()
	guest.actor = GUEST.instantiate() as Node3D
	party.add_child(guest.actor)
	guest.start = anchor + offset
	guest.actor.position = guest.start
	guest.yaw = yaw
	guest.phase = phase
	guest.action = action
	guest.at_square = anchor == square
	var size := [1.0, .92, 1.11, .98, .86][index % 5] as float
	guest.actor.scale = Vector3(size * (1 + .05 * sin(index * 2.3)), size, size)
	var body := guest.actor.find_child("GuestBody", true, false) as MeshInstance3D
	for surface in body.mesh.get_surface_count():
		var original := body.mesh.surface_get_material(surface) as StandardMaterial3D
		var color := original.albedo_color
		match original.resource_name:
			"Shirt": color = Color("344e69") if action == "Hose" else SHIRTS[index % SHIRTS.size()].darkened(.12)
			"Scarf": color = Color("f0bc51") if action == "Hose" else color
			"Skin": color = SKIN[index % SKIN.size()].darkened(.06)
			"Cheeks": color = SKIN[index % SKIN.size()].lerp(Color("d96554"), .23)
			"Lip": color = SKIN[index % SKIN.size()].lerp(Color("7c3c31"), .45)
			"Hair": color = [Color("3e2826"), Color("342827"), Color("8d552e"), Color("56453a")][index % 4]
			_: continue
		var material := original.duplicate() as StandardMaterial3D
		material.albedo_color = color
		body.set_surface_override_material(surface, material)
	guest.animation = guest.actor.find_child("AnimationPlayer", true, false) as AnimationPlayer
	guest.animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	guest.mug = guest.actor.find_child("BeerMug", true, false) as Node3D
	var helmet := guest.actor.find_child("FireHelmet", true, false) as Node3D
	helmet.visible = action == "Hose"
	var skeleton := guest.actor.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	guest.skeleton = skeleton
	guest.head = skeleton.find_bone("Head")
	for bone in skeleton.get_bone_count():
		var bone_name := skeleton.get_bone_name(bone)
		if bone_name.begins_with("Hand") and bone_name.ends_with("R"):
			guest.hand = BoneAttachment3D.new()
			skeleton.add_child(guest.hand)
			guest.hand.bone_idx = bone
			break
	if action == "Throw":
		guest.tomato = _make_tomato()
		party.add_child(guest.tomato)
		guest.actor.rotation.y = yaw
		_pose_guest(guest, "Throw", THROW_RELEASE)
		skeleton.force_update_all_bone_transforms()
		guest.release_offset = guest.actor.to_local(_held_tomato_at(guest))
	guest.escape = Vector3(escape_direction.x, 0, escape_direction.y).normalized()
	guests.append(guest)
	return guest


func _add_toss(thrower: Guest, receiver: Guest, releases: float, hits: float) -> void:
	var toss := Toss.new()
	toss.thrower = thrower
	toss.receiver = receiver
	toss.release_time = releases
	toss.hit_time = hits
	outgoing_tosses[thrower] = toss
	incoming_tosses[receiver] = toss
	var direction := receiver.start - thrower.start
	thrower.yaw = atan2(direction.x, direction.z)
	thrower.actor.rotation.y = thrower.yaw
	_pose_guest(thrower, "Throw", THROW_RELEASE)
	thrower.skeleton.force_update_all_bone_transforms()
	toss.from = _held_tomato_at(thrower)
	receiver.actor.rotation.y = receiver.yaw
	_pose_guest(receiver, "TomatoHit", 0.0)
	receiver.skeleton.force_update_all_bone_transforms()
	toss.contact = _head_transform(receiver) * Vector3(-.075, 1.97, .437)
	for index in 18:
		var piece := MeshInstance3D.new()
		piece.mesh = pulp_mesh
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		performers.add_child(piece)
		piece.hide()
		toss.splash.append(piece)
	toss.smear = Node3D.new()
	toss.smear.name = "TomatoOnCheek"
	receiver.actor.add_child(toss.smear)
	var marks := [Vector3(.26,1.9,.385), Vector3(.307,1.935,.365), Vector3(.33,1.896,.35),
		Vector3(.211,1.867,.406), Vector3(.222,1.943,.398), Vector3(.294,1.853,.366)]
	for index in marks.size():
		var stain := MeshInstance3D.new()
		stain.mesh = pulp_mesh
		stain.position = marks[index]
		var radius := .051 if index == 0 else .028
		stain.scale = Vector3(radius, radius * .57, .026)
		stain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		toss.smear.add_child(stain)
	toss.smear.hide()
	tosses.append(toss)


func _held_tomato_at(guest: Guest) -> Vector3:
	var hand := guest.skeleton.get_bone_global_pose(guest.hand.bone_idx)
	return guest.skeleton.to_global(hand.origin) + guest.actor.basis.z.normalized() * .11 + Vector3.DOWN * .08


func _head_transform(guest: Guest) -> Transform3D:
	var skeleton := guest.skeleton
	return (skeleton.global_transform * skeleton.get_bone_global_pose(guest.head)
		* skeleton.get_bone_global_rest(guest.head).affine_inverse())


func _animate_tosses(time: float) -> void:
	for toss in tosses:
		var thrower := toss.thrower
		var tomato := thrower.tomato
		if thrower.actor.visible:
			var local_time := time - toss.release_time
			tomato.visible = local_time >= -THROW_RELEASE and time < toss.hit_time
			if tomato.visible:
				if local_time < 0.0:
					tomato.global_position = _held_tomato_at(thrower)
				else:
					var flight := clampf(inverse_lerp(toss.release_time, toss.hit_time, time), 0.0, 1.0)
					tomato.global_position = toss.from.lerp(toss.contact, flight) + Vector3.UP * sin(flight * PI) * .64
				tomato.rotation = Vector3(local_time * 15, local_time * 3, 0)
		var receiver := toss.receiver
		var impact := time - toss.hit_time
		var revealed := receiver.actor.visible and impact >= 0.0
		toss.smear.visible = revealed
		if revealed:
			toss.smear.global_transform = _head_transform(receiver)
		for index in toss.splash.size():
			var piece := toss.splash[index]
			piece.visible = revealed and impact < .43
			if not piece.visible:
				continue
			var angle := float(index) * 2.39996
			var speed := 1.2 + float(index % 5) * .79
			var scatter := Vector3(cos(angle) * speed, 1.35 + sin(angle) * 2.48, sin(angle * .73) * speed)
			piece.position = toss.contact + scatter * impact + Vector3.DOWN * 5.8 * impact * impact
			var radius := (.023 + .014 * float(index % 4)) * (1.0 - smoothstep(.26, .43, impact))
			piece.scale = Vector3(radius * 1.28, radius * .77, radius)


func _pose_guest(guest: Guest, action: String, time: float) -> void:
	var animation_name := StringName(action)
	if guest.animation.current_animation != animation_name:
		guest.animation.play(animation_name)
	var clip := guest.animation.get_animation(animation_name)
	var sample := (fposmod(time, clip.length) if clip.loop_mode
		else clampf(time, 0.0, clip.length))
	guest.animation.seek(sample, true)
	guest.mug.visible = action == "Sip"
	if is_instance_valid(guest.tomato):
		guest.tomato.visible = action == "Throw"


func _animate_crowd(time: float) -> void:
	for guest in guests:
		guest.actor.visible = guest.at_square == (time >= PLAZA_WIDE)
		if not guest.actor.visible:
			if is_instance_valid(guest.tomato):
				guest.tomato.hide()
			continue
		var actor := guest.actor
		actor.position = guest.start
		actor.rotation = Vector3(0, guest.yaw, 0)
		var incoming: Toss = incoming_tosses.get(guest)
		var outgoing: Toss = outgoing_tosses.get(guest)
		var startled := CRATE_ATTACK + .39 + guest.phase * .72
		var takeoff := TRUCK_ATTACK + .91 if guest == runner else startled + .62
		if guest == victim and time >= CRATE_ATTACK + 1.25:
			var hit := time - CRATE_ATTACK - 1.25
			var toss := clampf(hit / 1.34, 0, 1)
			_pose_guest(guest, "Hit", hit)
			actor.position += Vector3(1.9 * toss, sin(toss * PI) * 2.8 + .52 * toss, 4.1 * toss)
			actor.rotation.x = -1.52 * smoothstep(.13, 1.0, toss)
			actor.rotation.z = .21 * sin(toss * PI * 1.25)
		elif guest == victim and time >= CRATE_ATTACK - .08:
			_pose_guest(guest, "Startle", time - CRATE_ATTACK + .08)
		elif guest.at_square and time >= startled:
			var heading := guest.escape
			var escape_yaw := atan2(heading.x, heading.z)
			if time < takeoff:
				_pose_guest(guest, "Startle", time - startled)
				var recoil := smoothstep(startled + .05, startled + .78, time)
				actor.rotation.y = lerp_angle(guest.yaw, escape_yaw, recoil * .48)
				actor.position += heading * recoil * .63
			else:
				var run := time - takeoff
				var trip := guest == runner or guest.phase >= .9
				var struggle := .73 if trip else .0
				if run < struggle:
					_pose_guest(guest, "Stumble", run)
				else:
					_pose_guest(guest, "Panic", (run - struggle) * 1.52 + guest.phase)
				actor.rotation.y = lerp_angle(guest.yaw, escape_yaw, smoothstep(-.26, .18, run))
				var sprint := (1.65 * minf(run, struggle) + 5.3 * maxf(0, run - struggle))
				actor.position += heading * (.55 + sprint)
		elif incoming != null and time >= incoming.hit_time:
			var reaction := time - incoming.hit_time
			if reaction < 33.0 / 24.0:
				_pose_guest(guest, "TomatoHit", reaction)
			else:
				_pose_guest(guest, "Cheer", reaction - 33.0 / 24.0)
			actor.position += actor.basis.z.normalized() * (-.28 * sin(clampf(reaction * 1.6, 0, 1) * PI))
		elif outgoing != null:
			var release_sample := time - outgoing.release_time + THROW_RELEASE
			var visible_throw := release_sample >= 0.0 and release_sample < THROW_PERIOD
			_pose_guest(guest, "Throw" if visible_throw else "Cheer",
				release_sample if visible_throw else time + guest.phase)
		else:
			var event_time := time + guest.phase
			_pose_guest(guest, guest.action, event_time)
			if guest.action == "Throw":
				_animate_throw(guest, fposmod(event_time, THROW_PERIOD))


func _animate_throw(guest: Guest, time: float) -> void:
	var direction := guest.actor.basis.z.normalized()
	if time < THROW_RELEASE and is_instance_valid(guest.hand):
		guest.tomato.global_position = _held_tomato_at(guest)
	else:
		var flight := maxf(time - THROW_RELEASE, 0.0)
		var release := guest.actor.to_global(guest.release_offset)
		guest.tomato.position = (release + direction * (flight * 9.2)
			+ Vector3.UP * (flight * 2.2 - flight * flight * 7.0))
		guest.tomato.rotation.x = flight * 12
		guest.tomato.visible = guest.tomato.position.y > .105


func _animate_monsters(time: float) -> void:
	var first := time - CRATE_ATTACK
	var jump := clampf((first - .38) / .87, 0, 1)
	crate_monster.visible = first >= .38
	crate_monster.position = (crate_at.lerp(victim.start, jump)
		+ Vector3.UP * (1.05 + 1.94 * sin(jump * PI)))
	crate_monster.rotation.y = lerp_angle(2.15, -2.4, smoothstep(.18, .9, jump))
	crate_monster.rotation.x = -.29 * sin(jump * PI)
	crate_monster.scale = Vector3(1, 1.0 - .28 * exp(-pow((first - 1.24) / .12, 2)), 1)
	if first > 1.25:
		var step_time := first - 1.25
		crate_monster.position += Vector3(-.75, absf(sin(step_time * 7)) * .49, 1.05) * minf(step_time, 2.4)
	for index in crate_planks.size():
		var plank := crate_planks[index]
		var burst := clampf(first - .38, 0, .92)
		plank.position = crate_at + Vector3((index - 2) * (.34 + burst * .57),
			maxf(.06, 1.18 + burst * (2.3 + index * .31) - 4.8 * burst * burst), .05 + burst * .8)
		var settle := 1.0 - smoothstep(.69, .92, burst)
		plank.rotation = Vector3(burst * (2 + index) * settle, -.25 + burst * .7, burst * .66 * settle)
	var second := time - TRUCK_ATTACK
	_truck_jump(truck_monster, second - .22, Vector3(-3.8, .98, 4.6), 2.3, 1.58)
	_truck_jump(truck_grunt, second - .64, Vector3(-5.8, .70, 1.3), 2.75, .98)
	if time >= PANIC_CHASE - .1:
		var chase := time - PANIC_CHASE
		var reach := smoothstep(-.1, .58, chase)
		var gap := lerpf(6.0, 2.8, smoothstep(.0, 1.8, chase))
		var hunt_at := runner.actor.position - runner.escape * gap + Vector3(2.1, 1.31, 0)
		hunt_at.y = 1.26 + .49 * absf(sin(chase * 9))
		truck_monster.position = truck_monster.position.lerp(hunt_at, reach)
		var hunt := runner.actor.position - truck_monster.position
		truck_monster.rotation.y = lerp_angle(truck_monster.rotation.y, atan2(-hunt.x, -hunt.z), reach)
		truck_monster.rotation.z = .14 * sin(chase * 8)
		for index in 2:
			var arm := truck_monster.get_node("ShoulderL" if index == 0 else "ShoulderR") as Node3D
			arm.rotation.x = reach * (.65 + .57 * sin(chase * 11 + index * PI))
			arm.rotation.z = reach * (.2 if index == 0 else -.2)


func _truck_jump(monster: Node3D, time: float, toward: Vector3, height: float, start_height: float) -> void:
	monster.visible = time >= 0
	var flight := clampf(time / 1.12, 0, 1)
	var bounce := maxf(0, time - 1.12)
	monster.position = (truck_at + Vector3(0, lerpf(start_height, 0, flight), .3)
		+ toward * flight + Vector3.UP * (sin(flight * PI) * height + absf(sin(bounce * 9)) * .55))
	monster.position += Vector3(toward.x, 0, toward.z).normalized() * bounce * 2.8
	monster.rotation.y = atan2(-toward.x, -toward.z)


func _build_water() -> void:
	nozzle = square + Vector3(-5.05, 1.63, .16)
	hose_from = square + Vector3(-7.5, 1.1, -2.65)
	var hose_material := _material(Color("b28a49"))
	var last := hose_from
	for index in 12:
		var progress := (float(index) + 1.0) / 12
		var point := hose_from.lerp(nozzle, progress) + Vector3.DOWN * (sin(progress * PI) * 1.21)
		hose_sections.append(_tube(last, point, .104, hose_material))
		last = point
	hose_tip = _tube(nozzle - Vector3(.32, .12, .06), nozzle + Vector3(.25, .1, .05),
		.145, _material(Color("45494b")))
	water_core_material = _material(Color(.54, .86, .96, .72))
	water_core_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_core_material.roughness = .24
	var drop := SphereMesh.new()
	drop.radius = .046
	drop.height = .092
	drop.radial_segments = 7
	drop.rings = 3
	drop.material = _material(Color("88d8ef"))
	drop.material.roughness = .29
	var mesh := MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.mesh = drop
	mesh.instance_count = DROP_COUNT
	hose_cloud = MultiMeshInstance3D.new()
	hose_cloud.name = "FirefightersWaterJet"
	hose_cloud.multimesh = mesh
	hose_cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	performers.add_child(hose_cloud)


func _animate_water(time: float) -> void:
	var released := smoothstep(CRATE_ATTACK - .16, CRATE_ATTACK + .44, time)
	var tip := nozzle + Vector3(0, -1.42 * released, .4 * released)
	var last := hose_from
	for index in hose_sections.size():
		var progress := float(index + 1) / hose_sections.size()
		var point := hose_from.lerp(tip, progress)
		point.y = maxf(.12, point.y - sin(progress * PI) * lerpf(1.21, .9, released))
		_place_tube(hose_sections[index], last, point)
		last = point
	_place_tube(hose_tip, tip - Vector3(.32, .12 * (1 - released), .06), tip + Vector3(.25, .1, .05))
	hose_cloud.visible = time >= PLAZA_WIDE and time < CRATE_ATTACK - .16
	if not hose_cloud.visible:
		for segment in water_core:
			segment.hide()
		return
	var reach := 1.0 - smoothstep(CRATE_ATTACK - .65, CRATE_ATTACK - .16, time)
	var sweep := 1.85 + .32 * sin(time * 3.8)
	var path := PackedVector3Array([nozzle])
	for section in range(1, 13):
		var progress := float(section) / 12 * reach
		path.append(nozzle + Vector3(progress * 9.1, progress * 4.9 - progress * progress * 6.1, progress * sweep))
	world._lay_segments(water_core, path, water_core_material,
		func(section: int, steps: int) -> float: return lerpf(.072, .037, float(section) / steps))
	for segment in water_core:
		if segment.get_parent() == world:
			segment.reparent(performers)
	for index in DROP_COUNT:
		var progress := fposmod(float(index) / DROP_COUNT + time * 1.15, 1) * reach
		var diff := Vector3(progress * (9.1 + sin(index * 5.5) * 1.5),
			progress * (4.9 + sin(index * 8.3) * 1.04) - progress * progress * 6.1,
			progress * sweep + sin(index * 2.39) * progress * .72)
		var direction := Vector3(9.1, 4.9 - progress * 12.2, 1.85).normalized()
		var spray := Basis.looking_at(direction).scaled_local(Vector3(.72, .72, 2.7 - progress * 1.17))
		hose_cloud.multimesh.set_instance_transform(index, Transform3D(spray, nozzle + diff))


func _build_passengers() -> void:
	passengers = Node3D.new()
	passengers.name = "TeamInTruck"
	entrance.truck.add_child(passengers)
	var seats := [Vector3(-.49, 1.19, 2.0), Vector3(.49, 1.20, 1.75),
		Vector3(-.36, 1.2, .82), Vector3(.35, 1.2, .58)]
	for peer_id in world.shooter_ids():
		var shooter = world.shooter_for(peer_id)
		var rider := world.PLAYER_CHARACTERS[shooter.character_index].instantiate() as Node3D
		passengers.add_child(rider)
		rider.position = seats[shooter.spawn_slot % seats.size()]
		rider.scale = shooter.player_visual.scale * .46 if is_instance_valid(shooter.player_visual) else Vector3.ONE * .4
		rider.rotation = Vector3(-.08, .36 if rider.position.x < 0 else -.36, 0)
		var animation := rider.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if is_instance_valid(animation) and animation.has_animation(shooter.walk_animation):
			animation.play(shooter.walk_animation)
			animation.seek(.12 + .085 * shooter.spawn_slot, true)
			animation.pause()


func _build_tomato_meshes() -> void:
	tomato_mesh = SphereMesh.new()
	tomato_mesh.radius = .144
	tomato_mesh.height = .23
	tomato_mesh.radial_segments = 10
	tomato_mesh.rings = 6
	tomato_mesh.material = _material(Color("e04632"))
	leaf_mesh = CylinderMesh.new()
	leaf_mesh.radial_segments = 5
	leaf_mesh.rings = 1
	leaf_mesh.bottom_radius = .057
	leaf_mesh.top_radius = .019
	leaf_mesh.height = .058
	leaf_mesh.material = _material(Color("54753c"))
	pulp_mesh = SphereMesh.new()
	pulp_mesh.radius = 1.0
	pulp_mesh.height = 2.0
	pulp_mesh.radial_segments = 8
	pulp_mesh.rings = 5
	pulp_mesh.material = _material(Color("b52816"))


func _make_tomato() -> Node3D:
	var root := Node3D.new()
	var fruit := MeshInstance3D.new()
	fruit.mesh = tomato_mesh
	root.add_child(fruit)
	var crown := MeshInstance3D.new()
	crown.mesh = leaf_mesh
	crown.position.y = .124
	root.add_child(crown)
	return root


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .86
	return material


func _box(dimensions: Vector3, color: Color, parent: Node3D) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	mesh.material = _material(color)
	instance.mesh = mesh
	parent.add_child(instance)
	return instance


func _tube(from: Vector3, to: Vector3, radius: float, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 1.0
	mesh.radial_segments = 7
	mesh.rings = 1
	mesh.material = material
	instance.mesh = mesh
	_place_tube(instance, from, to)
	performers.add_child(instance)
	return instance


func _place_tube(piece: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var span := to - from
	var direction := Basis(Quaternion(Vector3.UP, span.normalized()))
	piece.transform = Transform3D(direction.scaled_local(Vector3(1, span.length() + .035, 1)), (from + to) * .5)


func _audio_loop(source: AudioStreamWAV) -> AudioStreamPlayer:
	var stream := source.duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = roundi(stream.get_length() * stream.mix_rate)
	var player := AudioStreamPlayer.new()
	player.bus = &"SFX"
	player.stream = stream
	player.volume_db = -80
	add_child(player)
	player.play()
	return player


func _sound_cues(previous: float, time: float) -> void:
	var crowd_gate := (smoothstep(.2, 1.1, time) * (1.0 - smoothstep(17.05, 18.12, time))
		* (1.0 - .93 * smoothstep(CRATE_ATTACK - .53, CRATE_ATTACK - .10, time)
			* (1.0 - smoothstep(CRATE_ATTACK + .5, CRATE_ATTACK + .98, time))))
	crowd_audio.volume_db = -16 + linear_to_db(maxf(.0001, crowd_gate))
	crowd_audio.pitch_scale = 1.29 if time >= CRATE_ATTACK + .55 else 1.0
	var water_gate := (smoothstep(PLAZA_WIDE, PLAZA_WIDE + .4, time)
		* (1.0 - smoothstep(CRATE_ATTACK - .65, CRATE_ATTACK - .16, time)))
	hose_audio.volume_db = -15 + linear_to_db(maxf(.0001, water_gate))
	var engine_gate := smoothstep(ARRIVAL, ARRIVAL + .56, time) * (1.0 - smoothstep(21.36, 22.31, time))
	engine_audio.volume_db = -8 + linear_to_db(maxf(.0001, engine_gate))
	engine_audio.pitch_scale = lerpf(1.19, .68, smoothstep(19.6, 21.43, time))
	for toss in tosses:
		if previous < toss.hit_time and time >= toss.hit_time:
			splat_audio.pitch_scale = 1.07 if toss.receiver.at_square else 1.21
			splat_audio.play()
	if previous < TRUCK_ATTACK - .28 and time >= TRUCK_ATTACK - .28:
		escape_audio.play()
	escape_audio.volume_db = -3.0 + linear_to_db(maxf(.0001, 1.0 - smoothstep(17.64, 18.16, time)))
	for cue in [[CRATE_ATTACK + .38, GROWL, -5.0], [CRATE_ATTACK + 1.27, SPLAT, -5.0],
			[TRUCK_ATTACK + .24, GROWL, -7.0], [LATCH_TIME, LATCH, -2.5]]:
		if previous < cue[0] and time >= cue[0]:
			effects.stream = cue[1]
			effects.volume_db = cue[2]
			effects.play()
