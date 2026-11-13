class_name TomatinaVillageArt
extends RefCounted

const KIT_PATH := "res://assets/props/Stage2_TomatinaVillage/Stage2_TomatinaVillage.glb"
const TOON_SHADER := preload("res://assets/props/Stage2_TomatinaVillage/tomatina_toon.gdshader")
const PARTICLE_FIRE := preload("res://assets/props/Stage2_TomatinaVillage/tomatina_particle_fire.gdshader")
const FLAME_VOLUME := preload("res://assets/props/Stage2_TomatinaVillage/tomatina_flame_volume.gdshader")
const FESTIVAL_DECOR := preload("res://scripts/tomatina_festival_decor.gd")
const HOUSES := ["HouseCream", "HousePeach", "HouseLime", "HouseSage", "HouseBlue", "HouseHoney"]
const BANNERS := ["BannerWater", "BannerMarket", "BannerFestival"]
const CARDINAL := [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
const CHUNK_SIZE := 70.0
const HOUSE_CHUNK_WIDTH := 110.0
const WALL_DEPTH := 0.54
const STREET_ACCENTS := {"WaterFront": Color("447d87"), "MarketFront": Color("b87e41"), "FestivalFront": Color("934950"), "TrimStone": Color("dcc5a0")}

# The cell is inside the street. The step points through its exterior wall.
# Arrows read from the approach to each bend, with the market marking the main street.
const PLAZA_WAYMARKS := [
	[Vector2i(31, 207), Vector2i.RIGHT, "◆  ↑"],
	[Vector2i(38, 192), Vector2i.RIGHT, "←  ◆"],
	[Vector2i(8, 165), Vector2i.UP, "광장  ↗"],
	[Vector2i(34, 129), Vector2i.LEFT, "◆  ↑"],
	[Vector2i(14, 122), Vector2i.LEFT, "광장  ↑"],
	[Vector2i(13, 93), Vector2i.UP, "◆  ↑"],
	[Vector2i(28, 66), Vector2i.UP, "◆  →"],
	[Vector2i(32, 56), Vector2i.UP, "◆  ↑"],
	[Vector2i(31, 42), Vector2i.RIGHT, "광장  ↑"],
]

var _meshes: Dictionary = {}
var _batches: Dictionary = {}
var _facades: Array[Transform3D] = []


static func configure_pavement(floor_body: FloorContamination) -> void:
	var bounds := TomatinaMap.bounds()
	var mask := Image.create_empty(bounds.size.x, bounds.size.y, false, Image.FORMAT_R8)
	for cell: Vector2i in TomatinaMap.floor_cells():
		var pixel := cell - bounds.position
		mask.set_pixel(pixel.x, pixel.y, Color.WHITE)
	var corner := TomatinaMap.at_cell(Vector2(bounds.position))
	floor_body.pavement_mask = ImageTexture.create_from_image(mask)
	floor_body.pavement_bounds = Rect2(Vector2(corner.x, corner.z), Vector2(bounds.size) * StreetMap.CELL)


static func build_plaza_waymarks(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "PlazaWaymarks"
	parent.add_child(root)
	var rim := BoxMesh.new()
	rim.size = Vector3(1.48, 0.51, 0.11)
	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color("c3a77b")
	frame.roughness = 0.92
	rim.material = frame
	var tile := BoxMesh.new()
	tile.size = Vector3(1.38, 0.42, 0.036)
	var glaze := StandardMaterial3D.new()
	glaze.albedo_color = Color("3f6168")
	glaze.roughness = 0.78
	tile.material = glaze

	for entry in PLAZA_WAYMARKS:
		var step: Vector2i = entry[1]
		var facing := Vector3(-step.x, 0.0, -step.y)
		var curb := Vector2(entry[0]) + Vector2.ONE * 0.5 + Vector2(step) * 0.5
		var plaque := MeshInstance3D.new()
		plaque.mesh = rim
		plaque.position = TomatinaMap.at_cell(curb) + Vector3.UP * 2.24 + facing * 0.058
		plaque.rotation.y = atan2(facing.x, facing.z)
		root.add_child(plaque)

		var face := MeshInstance3D.new()
		face.mesh = tile
		face.position.z = 0.063
		plaque.add_child(face)

		var lettering := Label3D.new()
		lettering.text = entry[2]
		lettering.position.z = 0.085
		lettering.pixel_size = 0.007
		lettering.font_size = 42
		lettering.outline_size = 0
		lettering.modulate = Color("e7d7b1")
		plaque.add_child(lettering)


func load_kit() -> bool:
	var kit := load(KIT_PATH) as PackedScene
	if kit == null:
		return false
	var scene := kit.instantiate()
	for model in scene.find_children("*", "MeshInstance3D", true, false):
		_meshes[model.name] = model.mesh
	scene.free()
	_meshes["BoundaryWall"] = _boundary_mesh()
	for name in STREET_ACCENTS:
		_meshes[name] = BoxMesh.new()
	return _meshes.has("HouseCream")


func build(parent: Node3D, debris: Array[Dictionary], parked_trucks: Array[Dictionary], fire_truck: Dictionary) -> void:
	_build_frontages()
	FESTIVAL_DECOR.build(parent, _facades)
	var ember_mesh := _make_ember_mesh()
	var ember_process := _make_ember_process()
	for box in debris:
		_add_debris(box)
		if box["name"] == "RefugeBrazier":
			var centre: Vector3 = box["position"]
			_add_fire(parent, Vector3(centre.x, 0.38, centre.z),
				Vector3(1.24, 1.63, 1.21), ember_mesh, ember_process)
	for box in parked_trucks:
		_add_debris(box)
	for index in TomatinaMap.SAFE_ROOMS.size():
		var room: Rect2i = TomatinaMap.SAFE_ROOMS[index]
		var centre := Vector2(float(room.get_center().x) + 0.5, float(room.position.y) + 1.5)
		_place(BANNERS[index], TomatinaMap.at_cell(centre))
		_place("RefugeShower", TomatinaMap.refuge_shower_at(index))
	_place("Church", TomatinaMap.at_cell(Vector2(36.5, 20.6)), Vector3.BACK, Vector3(17, 15, 9))
	var root := Node3D.new()
	root.name = "TomatinaVillageArt"
	parent.add_child(root)
	var material := ShaderMaterial.new()
	material.shader = TOON_SHADER
	var stained_walls := ShaderMaterial.new()
	stained_walls.shader = TOON_SHADER
	stained_walls.set_shader_parameter("tomato_wall", true)
	var street_walls := stained_walls.duplicate() as ShaderMaterial
	street_walls.set_shader_parameter("boundary_wall", true)
	for name: String in _batches:
		var finish: Material = material
		if name == "BoundaryWall":
			finish = street_walls
		elif name == "Church" or name in HOUSES:
			finish = stained_walls
		if STREET_ACCENTS.has(name):
			var accent := StandardMaterial3D.new()
			accent.albedo_color = STREET_ACCENTS[name].darkened(0.36)
			accent.roughness = 0.82
			finish = accent
		for chunk: Vector2i in _batches[name]:
			var transforms: Array = _batches[name][chunk]
			var multimesh := MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.mesh = _meshes[name]
			multimesh.instance_count = transforms.size()
			for index in transforms.size():
				multimesh.set_instance_transform(index, transforms[index])
			var batch := MultiMeshInstance3D.new()
			batch.name = "%s_%d_%d" % [name, chunk.x, chunk.y]
			batch.multimesh = multimesh
			batch.material_override = finish
			if name == "BrokenBoards" or name == "CrushedTomatoes":
				batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(batch)


## The curb is also the face of the collision. The visual panel sits just
## behind it so that the paint projected onto the collider has room to draw.
func _build_frontages() -> void:
	var floor := TomatinaMap.floor_cells()
	var blocked := TomatinaMap.blocked_cells()
	for cell: Vector2i in floor:
		var open := not blocked.has(cell)
		var patch := posmod((cell.x * 73) ^ (cell.y * 157), 83)
		if open and patch < 4 and TomatinaMap.safe_room_at(cell) < 0:
			var at := TomatinaMap.at_cell(Vector2(cell) + Vector2(0.38, 0.62))
			_place_litter(at, cell, patch < 2, 1.38)
		for step: Vector2i in CARDINAL:
			if floor.has(cell + step):
				continue
			var tangent := Vector2i(-step.y, step.x)
			var facing := Vector3(-step.x, 0.0, -step.y)
			var curb := Vector2(cell) + Vector2(0.5, 0.5) + Vector2(step) * 0.5
			var base := TomatinaMap.at_cell(curb)
			_place("BoundaryWall", base - facing * (WALL_DEPTH * 0.5 + 0.016), facing,
				Vector3(StreetMap.CELL + 0.06, TomatinaMap.BOUNDARY_HEIGHT, WALL_DEPTH))
			var scatter := posmod(cell.x * 31 + cell.y * 47 + step.x * 13 + step.y * 7, 19)
			if scatter < 6:
				_place_street_front(base, facing, cell)
			elif scatter < 15:
				_place_facade_detail(base, facing, scatter)
			if scatter < 3 and open:
				var at := base + facing * (0.82 + float(scatter) * 0.68)
				at += Vector3(tangent.x, 0.0, tangent.y) * 0.44
				_place_litter(at, cell, scatter == 2, 1.50 + float(scatter) * 0.29)
			var outside := cell + step
			var across := cell.x if step.y != 0 else cell.y
			var paired := floor.has(cell + tangent) and not floor.has(outside + tangent)
			var previous_edge := floor.has(cell - tangent) and not floor.has(outside - tangent)
			if paired and posmod(across, 2) != 0:
				continue
			if not paired and (previous_edge or posmod(cell.x * 37 + cell.y * 19, 3) == 0):
				continue
			# Leave a clear backdrop for the extraction bay and the bell tower.
			if outside.y < 22 and outside.x >= 25 and outside.x <= 39:
				continue
			var depth := 7.8
			if floor.has(outside + step) or floor.has(outside + step + tangent):
				depth = StreetMap.CELL * 0.45
			var shift := StreetMap.CELL * 0.5 if paired else 0.0
			var behind := base + Vector3(tangent.x, 0.0, tangent.y) * shift
			behind -= facing * (depth * 0.5 + 0.18)
			var variant := posmod(cell.x * 71 + cell.y * 29, HOUSES.size())
			var height := 9.0 + 0.6 * float(posmod(cell.x * 17 + cell.y * 31, 6))
			var width := StreetMap.CELL * (1.92 if paired else 0.94)
			_place(HOUSES[variant], behind, facing, Vector3(width, height, depth))
			var anchor := behind + facing * (depth * 0.46 + 0.07) + Vector3.UP * (height * 0.84)
			_facades.push_back(Transform3D(Basis.looking_at(-facing), anchor))

	_build_backlots(floor)


func _place_facade_detail(base: Vector3, facing: Vector3, scatter: int) -> void:
	var front := base + facing * 0.23
	var along := facing.cross(Vector3.UP)
	if scatter < 9:
		_place("FacadeWindow", front + Vector3.UP * 3.45, facing)
	elif scatter < 12:
		_place("FacadeLantern", front + along * 1.25 + Vector3.UP * 2.65, facing)
	else:
		_place("FacadePots", front + along * 1.25 + Vector3.UP * 0.04, facing)


func _place_street_front(base: Vector3, facing: Vector3, cell: Vector2i) -> void:
	var key := "WaterFront" if cell.y >= 190 else ("MarketFront" if cell.y >= 120 else "FestivalFront")
	var tangent := facing.cross(Vector3.UP)
	var front := base + facing * 0.10
	if key == "WaterFront":
		_place(key, front + Vector3.UP * 1.7, facing, Vector3(3.65, 0.20, 0.20))
		_place(key, front - tangent * 1.62, facing, Vector3(0.20, 1.9, 0.20))
		_place("TrimStone", front + tangent * 0.7, facing, Vector3(1.22, 0.48, 0.26))
	else:
		_place("TrimStone", front, facing, Vector3(2.65, 3.12, 0.22))
		_place(key, front + facing * 0.15 + Vector3.UP * 0.16, facing, Vector3(2.25, 2.72, 0.16))
		for index in 5:
			var lift := 0.55 + float(index) * 0.42
			_place("TrimStone", front + facing * 0.27 + Vector3.UP * lift, facing, Vector3(2.20, 0.06, 0.07))
		_place(key, front + Vector3.UP * 3.07, facing, Vector3(3.1, 0.22, 0.55))


func _boundary_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var panel := BoxMesh.new()
	panel.size = Vector3(0.996, 0.96, 0.88)
	var coping := BoxMesh.new()
	coping.size = Vector3(1.0, 0.04, 1.0)
	for box: BoxMesh in [panel, coping]:
		var arrays := box.surface_get_arrays(0)
		var base := Vector3.UP * (0.48 if box == panel else 0.98)
		var tint := Color("b8a18a") if box == panel else Color("d5bb97")
		for index: int in arrays[Mesh.ARRAY_INDEX]:
			surface.set_color(tint)
			surface.set_normal(arrays[Mesh.ARRAY_NORMAL][index])
			surface.add_vertex(arrays[Mesh.ARRAY_VERTEX][index] + base)
	return surface.commit()


## A second row of homes makes the winding roads read as lanes within a village.
## These homes live behind the street boundary and never obstruct a route.
func _build_backlots(floor: Dictionary) -> void:
	var candidates := {}
	for cell: Vector2i in floor:
		for step: Vector2i in CARDINAL:
			for distance: int in [3, 4]:
				var site: Vector2i = cell + step * distance
				if posmod(site.x, 3) == 0 and posmod(site.y, 3) == 0:
					candidates[site] = true
	for site: Vector2i in candidates:
		if site.y < 19 or site.y > 221 or posmod(site.x * 31 + site.y * 19, 5) == 0:
			continue
		var near_road := false
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if floor.has(site + Vector2i(dx, dy)):
					near_road = true
					break
			if near_road:
				break
		if near_road:
			continue
		var variant := posmod(site.x * 71 + site.y * 29, HOUSES.size())
		var turn := float(posmod(site.x * 47 + site.y * 17, 37)) * 0.17
		var at := TomatinaMap.at_cell(Vector2(site) + Vector2(0.5, 0.5))
		var size := Vector3(8.8, 7.6 + float(variant) * 1.2, 8.1)
		_place(HOUSES[variant], at, Vector3(sin(turn), 0.0, cos(turn)), size)


func _place_litter(at: Vector3, cell: Vector2i, boards: bool, spread: float) -> void:
	var angle := float(posmod(cell.x * 9 + cell.y * 17, 37)) * 0.17
	var facing := Vector3(sin(angle), 0.0, cos(angle))
	var model := "BrokenBoards" if boards else "CrushedTomatoes"
	_place(model, at, facing, Vector3(spread, 0.09 if boards else 0.07, spread * 0.72))


func _add_debris(box: Dictionary) -> void:
	var name: String = box["name"]
	var size: Vector3 = box["size"]
	var key := "Rubble"
	var facing := Vector3.BACK
	if TomatinaMap.is_aftermath_prop(box):
		key = name
		facing = box["facing"]
		if absf(facing.x) > 0.5:
			size = Vector3(size.z, size.y, size.x)
	elif name.begins_with("TomatoCrateStack"):
		key = "TomatoCrateStack"
	elif TomatinaMap.is_refill_crate(box):
		if name.ends_with("WreckCrate"):
			key = "TomatoCrateWreck"
		elif name.begins_with("TomatoCratesSupply"):
			key = "TomatoCrateRefuge"
		else:
			key = "TomatoCrate"
		var at: Vector3 = box["position"]
		at.y -= size.y * 0.5
		_place(key, at)
		return
	elif name == "MarketBarrels" or name == "CrushedTomatoes":
		key = name
	elif name.ends_with("WreckCanopy"):
		key = "BrokenBoards"
	elif name == "ParkedVan" or name == "LoadedTomatoTruck" or name == "OverturnedTomatoTruck":
		match name:
			"ParkedVan":
				key = "SauceVan"
			"LoadedTomatoTruck":
				key = "TomatoTruck"
			"OverturnedTomatoTruck":
				key = name
		if name == "OverturnedTomatoTruck":
			var at: Vector3 = box["position"]
			at.y = 0.0
			_place("BrokenBoards", at + Vector3(4.7, 0.0, 1.9), Vector3.BACK, Vector3(2.8, 0.10, 1.7))
		facing = box["facing"]
		if absf(facing.x) > 0.5:
			size = Vector3(size.z, size.y, size.x)
	elif name == "RefugeTent":
		key = "RefugeTent"
	elif name == "RefugeBrazier":
		key = "Brazier"
	elif name.begins_with("PlazaTree"):
		key = "PlanterTree"
		size.y = 4.6
	elif name.begins_with("PlazaStall"):
		key = "MarketStall"
	elif name == "SirenColumn":
		key = "FestivalColumn"
	elif name.ends_with("WreckBody"):
		key = "WreckBody"
		if size.x > size.z:
			facing = Vector3.RIGHT
			size = Vector3(size.z, size.y, size.x)
	_add_box_model(key, box, facing, size)


func _make_ember_mesh() -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = 0.045
	mesh.height = 0.09
	mesh.radial_segments = 8
	mesh.rings = 4
	var material := ShaderMaterial.new()
	material.shader = PARTICLE_FIRE
	mesh.material = material
	return mesh


func _make_ember_process() -> ParticleProcessMaterial:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.19
	process.direction = Vector3.UP
	process.spread = 16.0
	process.initial_velocity_min = 0.95
	process.initial_velocity_max = 1.45
	process.gravity = Vector3.UP * 0.28
	process.scale_min = 0.38
	process.scale_max = 1.0

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.65))
	scale_curve.add_point(Vector2(0.24, 1.0))
	scale_curve.add_point(Vector2(1.0, 0.03))
	var scale_texture := CurveTexture.new()
	scale_texture.curve = scale_curve
	process.scale_curve = scale_texture

	var colors := Gradient.new()
	colors.colors = PackedColorArray([Color("ffe487"), Color("ed4b18")])
	var color_texture := GradientTexture1D.new()
	color_texture.gradient = colors
	process.color_ramp = color_texture
	return process


func _add_fire(parent: Node3D, base: Vector3, size: Vector3, ember_mesh: Mesh,
		ember_process: ParticleProcessMaterial) -> void:
	var fire := Node3D.new()
	fire.position = base
	fire.add_to_group("tomatina_fire")
	parent.add_child(fire)

	var volume := MeshInstance3D.new()
	volume.name = "FlameVolume"
	volume.mesh = BoxMesh.new()
	volume.scale = size
	volume.position.y = size.y * 0.5
	volume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = FLAME_VOLUME
	material.set_shader_parameter("phase", fposmod(base.x + base.z, 19.0))
	volume.material_override = material
	fire.add_child(volume)

	var embers := GPUParticles3D.new()
	embers.name = "Embers"
	embers.amount = 4
	embers.lifetime = 0.91
	embers.preprocess = 1.0
	embers.randomness = 0.62
	embers.local_coords = true
	embers.position.y = size.y * 0.27
	embers.visibility_aabb = AABB(Vector3(-0.8, -0.3, -0.8), Vector3(1.6, 2.7, 1.6))
	embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	embers.draw_pass_1 = ember_mesh
	embers.process_material = ember_process
	fire.add_child(embers)

	var light := OmniLight3D.new()
	light.name = "CampfireGlow"
	light.position.y = 0.72
	light.light_color = Color("ff9352")
	light.light_energy = 1.35
	light.omni_range = 7.5
	light.omni_attenuation = 1.45
	fire.add_child(light)


func _add_box_model(key: String, box: Dictionary, facing: Vector3, size := Vector3.ZERO) -> void:
	var at: Vector3 = box["position"]
	var footprint: Vector3 = box["size"]
	at.y -= footprint.y * 0.5
	_place(key, at, facing, footprint if size == Vector3.ZERO else size)


func _place(key: String, at: Vector3, facing := Vector3.BACK, size := Vector3.ZERO) -> void:
	var mesh: Mesh = _meshes.get(key)
	if mesh == null:
		return
	var bounds := mesh.get_aabb()
	var offset := bounds.get_center()
	offset.y = bounds.position.y
	if key == "RefugeShower":
		# The authored origin is under the nozzle, ahead of the post.
		offset = Vector3.ZERO
	var scale := size / bounds.size if size != Vector3.ZERO else Vector3.ONE
	var basis := Basis(Vector3.UP, atan2(facing.x, facing.z))
	basis = basis.scaled_local(scale)
	var chunk_width := HOUSE_CHUNK_WIDTH if key in HOUSES else CHUNK_SIZE
	var chunk := Vector2i(floori(at.x / chunk_width), floori(at.z / CHUNK_SIZE))
	if not _batches.has(key):
		_batches[key] = {}
	if not _batches[key].has(chunk):
		_batches[key][chunk] = []
	_batches[key][chunk].push_back(Transform3D(basis, at - basis * offset))
