class_name TomatinaVillageArt
extends RefCounted

const KIT_PATH := "res://assets/props/Stage2_TomatinaVillage/Stage2_TomatinaVillage.glb"
const FALLEN_GUESTS := preload("res://assets/characters/Stage2_FestivalGuest/Stage2_FestivalGuest_Fallen.glb")
const TOON_SHADER := preload("res://assets/props/Stage2_TomatinaVillage/tomatina_toon.gdshader")
const PARTICLE_FIRE := preload("res://assets/props/Stage2_TomatinaVillage/tomatina_particle_fire.gdshader")
const FLAME_VOLUME := preload("res://assets/props/Stage2_TomatinaVillage/tomatina_flame_volume.gdshader")
const FESTIVAL_DECOR := preload("res://scripts/tomatina_festival_decor.gd")
const HOUSES := ["HouseCream", "HousePeach", "HouseLime", "HouseSage", "HouseBlue", "HouseHoney"]
const BANNERS := ["BannerWater", "BannerMarket", "BannerFestival"]
const VICTIM_MODELS := ["FallenFront", "FallenBack", "FallenSide"]
const ATTACK_AFTERMATH := ["FallenFront", "FallenBack", "FallenSide", "CollapsedStall",
	"OverturnedHandcart", "CollapsedStoneWall", "BrokenFestivalBarrier", "Rubble",
	"OverturnedTomatoTruck", "WreckBody", "BrokenBoards", "TornBuntingHeap"]
const CARDINAL := [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
const CHUNK_SIZE := 42.0
const HOUSE_CHUNK_WIDTH := 56.0
const MERGED_FRONTAGE_MODELS := ["UrbanArcade", "UrbanArcadePier", "UrbanUpperShutters", "UrbanUpperCasements"]
const DISTANT_DETAILS := ["FacadeWindow", "FacadeLantern", "FacadePots",
	"CrushedTomatoes", "BrokenBoards", "TornBuntingHeap"]
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
var _aftermath: Array[MultiMeshInstance3D] = []
## 묶음(MultiMesh)이 아닌 습격 흔적 -- 길에 쓰러진 사람들(`TomatinaVictims`)처럼 따로 서
## 있는 노드. 인트로의 "습격 전" 장면에서 묶음과 함께 숨긴다.
var aftermath_nodes: Array[Node3D] = []
var _stained_materials: Array[ShaderMaterial] = []
var _film_arcade_finish: ShaderMaterial
static var _merged_victim_meshes: Dictionary[String, Mesh] = {}


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
	var fallen := FALLEN_GUESTS.instantiate()
	for model in fallen.find_children("*", "MeshInstance3D", true, false):
		_meshes[model.name] = model.mesh
	fallen.free()
	_meshes["BoundaryWall"] = _boundary_mesh()
	_meshes["UrbanArcade"] = _arcade_mesh()
	_meshes["UrbanArcadePier"] = _arcade_pier_mesh()
	_meshes["UrbanUpperShutters"] = _upper_storey_mesh(Color("536b6c"))
	_meshes["UrbanUpperCasements"] = _upper_storey_mesh(Color("825747"))
	for name in STREET_ACCENTS:
		_meshes[name] = BoxMesh.new()
	return _meshes.has("HouseCream")


func build(parent: Node3D, debris: Array[Dictionary], parked_trucks: Array[Dictionary], fire_truck: Dictionary) -> void:
	record_tag = "street"
	_build_frontages()
	if not recording:
		add_arcades()
	FESTIVAL_DECOR.build(parent, _facades)
	var ember_mesh := _make_ember_mesh()
	var ember_process := _make_ember_process()
	for index in debris.size():
		var box := debris[index]
		record_tag = "debris:%d" % index
		_add_debris(box)
		if box["name"] == "RefugeBrazier":
			var centre: Vector3 = box["position"]
			_add_fire(parent, Vector3(centre.x, TomatinaMap.ground_height(centre) + 0.38, centre.z),
				Vector3(1.24, 1.63, 1.21), ember_mesh, ember_process)
	for index in parked_trucks.size():
		record_tag = "parked:%d" % index
		_add_debris(parked_trucks[index])
	for index in TomatinaMap.safe_rooms().size():
		var room: Rect2i = TomatinaMap.safe_rooms()[index]
		var centre := Vector2(float(room.get_center().x) + 0.5, float(room.position.y) + 1.5)
		record_tag = "room:%d" % index
		_place(BANNERS[index], TomatinaMap.at_cell(centre))
		_place("RefugeShower", TomatinaMap.refuge_shower_at(index))
	record_tag = "landmark"
	_place("Church", TomatinaMap.at_cell(Vector2(36.5, 20.6)), Vector3.BACK, Vector3(17, 15, 9))
	emit_batches(parent)


## 노드 맵 굽기용: 켜 두면 `_place`가 놓는 조각마다 [모델, 변환, record_tag]를 남긴다.
var recording := false
var record_tag := ""
var recorded: Array = []


func add_arcades() -> void:
	for front in TomatinaMap.arcade_fronts():
		add_placement("UrbanArcade", front)
		add_placement("UrbanArcadePier", front)
		_place("FacadeWindow", front * Vector3(0.0, TomatinaMap.ARCADE_DECK_TOP + 0.09, 0.33), front.basis.z,
			Vector3(1.55, 2.25, 0.18))


## 노드 맵의 아트 조각 하나를 묶음에 넣는다(`emit_batches` 전에).
func add_placement(key: String, placement: Transform3D) -> void:
	if not _meshes.has(key):
		return
	var chunk_width := HOUSE_CHUNK_WIDTH if key in HOUSES else CHUNK_SIZE
	var chunk := Vector2i(floori(placement.origin.x / chunk_width), floori(placement.origin.z / CHUNK_SIZE))
	if not _batches.has(key):
		_batches[key] = {}
	if not _batches[key].has(chunk):
		_batches[key][chunk] = []
	_batches[key][chunk].push_back(placement)
	if recording:
		recorded.push_back([key, placement, record_tag])


## 모아 둔 조각을 모델·구역별 MultiMesh로 `parent` 아래 "TomatinaVillageArt"에 만든다.
func emit_batches(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "TomatinaVillageArt"
	parent.add_child(root)
	var finishes := {}
	var frontage_surfaces := _frontage_surfaces()
	for name: String in _batches:
		var finish := finish_for(name, finishes)
		for chunk: Vector2i in _batches[name]:
			var transforms: Array = _batches[name][chunk]
			if name in MERGED_FRONTAGE_MODELS and frontage_surfaces.has(chunk):
				var surface := frontage_surfaces[chunk]
				var origin := Vector3(chunk.x * CHUNK_SIZE, 0.0, chunk.y * CHUNK_SIZE)
				for placement: Transform3D in transforms:
					placement.origin -= origin
					surface.append_from(_meshes[name], 0, placement)
				continue
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
			if name in NO_SHADOW:
				batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if name in DISTANT_DETAILS:
				batch.visibility_range_end = 70.0
				batch.visibility_range_end_margin = 8.0
			root.add_child(batch)
			if name in ATTACK_AFTERMATH:
				_aftermath.append(batch)
	for chunk in frontage_surfaces:
		var surface := frontage_surfaces[chunk]
		surface.index()
		var batch := MeshInstance3D.new()
		batch.name = "StreetFrontage_%d_%d" % [chunk.x, chunk.y]
		batch.position = Vector3(chunk.x * CHUNK_SIZE, 0.0, chunk.y * CHUNK_SIZE)
		batch.mesh = surface.commit()
		batch.material_override = finish_for(MERGED_FRONTAGE_MODELS[0], finishes)
		root.add_child(batch)
	_add_village_occluder(parent)
	# 습격 전/후를 바꿔 칠하는 벽 재질(집·교회, 길가 담장).
	_stained_materials.clear()
	for key in ["stained", "street"]:
		if finishes.get(key) is ShaderMaterial:
			_stained_materials.append(finishes[key])
	_batches.clear()
	_facades.clear()


func _frontage_surfaces() -> Dictionary[Vector2i, SurfaceTool]:
	var surfaces: Dictionary[Vector2i, SurfaceTool] = {}
	var counts: Dictionary[Vector2i, int] = {}
	# The Press King entrance removes individual frontage pieces west of the plaza.
	var breach_area := TomatinaMap.plaza_rect().grow(2.0 * StreetMap.CELL)
	for name: String in MERGED_FRONTAGE_MODELS:
		for chunk: Vector2i in _batches.get(name, {}):
			var bounds := Rect2(Vector2(chunk) * CHUNK_SIZE, Vector2.ONE * CHUNK_SIZE)
			if not bounds.intersects(breach_area):
				counts[chunk] = counts.get(chunk, 0) + 1
	for chunk in counts:
		if counts[chunk] >= 2:
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			surfaces[chunk] = surface
	return surfaces


func _add_village_occluder(parent: Node3D) -> void:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	# Keep the proxy inside each solid panel. The houses have solid cores
	# behind their modeled trim, but roofs, arcade openings and props are omitted.
	for model: String in ["BoundaryWall"] + HOUSES:
		var chunks: Dictionary = _batches.get(model, {})
		if chunks.is_empty():
			continue
		var bounds: AABB = _meshes[model].get_aabb()
		var centre := bounds.get_center()
		var half_width := bounds.size.x * (0.48 if model == "BoundaryWall" else 0.32)
		var low := bounds.position.y + bounds.size.y * 0.03
		var high := bounds.position.y + bounds.size.y * (0.94 if model == "BoundaryWall" else 0.57)
		var left := centre.x - half_width
		var right := centre.x + half_width
		var corners := [Vector3(left, low, centre.z), Vector3(right, low, centre.z),
			Vector3(right, high, centre.z), Vector3(left, high, centre.z)]
		for placements: Array in chunks.values():
			for placement: Transform3D in placements:
				var start := vertices.size()
				for corner: Vector3 in corners:
					vertices.append(placement * corner)
				for offset in [0, 1, 2, 0, 2, 3, 0, 2, 1, 0, 3, 2]:
					indices.append(start + offset)
	if vertices.is_empty():
		return
	var shape := ArrayOccluder3D.new()
	shape.set_arrays(vertices, indices)
	var occluder := OccluderInstance3D.new()
	occluder.name = "TomatinaVillageOccluder"
	occluder.occluder = shape
	parent.add_child(occluder)



func set_before_attack(enabled: bool) -> void:
	for batch in _aftermath:
		batch.visible = not enabled
	for node in aftermath_nodes:
		if is_instance_valid(node):
			node.visible = not enabled
	for material in _stained_materials:
		material.set_shader_parameter("festival_before_attack", enabled)


func film_prop(key: String, parent: Node3D, at: Vector3, size: Vector3,
		yaw := 0.0) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = key
	instance.mesh = _meshes[key]
	var bounds := instance.mesh.get_aabb()
	var dimensions := size / bounds.size
	var basis := Basis(Vector3.UP, yaw).scaled_local(dimensions)
	var base := bounds.get_center()
	base.y = bounds.position.y
	instance.transform = Transform3D(basis, at - basis * base)
	var material := ShaderMaterial.new()
	material.shader = TOON_SHADER
	instance.material_override = material
	parent.add_child(instance)
	return instance


func film_arcade(parent: Node3D, frontage: Transform3D) -> void:
	if _film_arcade_finish == null:
		_film_arcade_finish = ShaderMaterial.new()
		_film_arcade_finish.shader = TOON_SHADER
	for key in ["UrbanArcade", "UrbanArcadePier"]:
		var instance := MeshInstance3D.new()
		instance.name = key
		instance.mesh = _meshes[key]
		instance.material_override = _film_arcade_finish
		instance.transform = frontage
		parent.add_child(instance)


const NO_SHADOW := ["BrokenBoards", "CrushedTomatoes", "FestivalTrashPile",
	"TomatoBasketSpill", "TornBuntingHeap", "FacadeWindow", "FacadeLantern", "FacadePots"]


## 모델 이름에 맞는 재질. 같은 `cache`를 쓰는 조각끼리 재질을 나눈다.
static func finish_for(name: String, cache: Dictionary) -> Material:
	var key := "toon"
	if STREET_ACCENTS.has(name):
		key = name
	elif name == "BoundaryWall":
		key = "street"
	elif name == "Church" or name in HOUSES:
		key = "stained"
	if cache.has(key):
		return cache[key]
	var finish: Material
	if STREET_ACCENTS.has(name):
		var accent := StandardMaterial3D.new()
		accent.albedo_color = STREET_ACCENTS[name].darkened(0.36)
		accent.roughness = 0.82
		finish = accent
	else:
		var toon := ShaderMaterial.new()
		toon.shader = TOON_SHADER
		if key != "toon":
			toon.set_shader_parameter("tomato_wall", true)
		if key == "street":
			toon.set_shader_parameter("boundary_wall", true)
		finish = toon
	cache[key] = finish
	return finish


## The curb is also the face of the collision. The visual panel sits just
## behind it so that the paint projected onto the collider has room to draw.
func _build_frontages() -> void:
	var floor := TomatinaMap.floor_cells()
	var blocked := TomatinaMap.blocked_cells()
	var street_profile := TomatinaMap.street_profile_enabled()
	var arcade_edges := {}
	if street_profile:
		for entry in TomatinaMap.ARCADES:
			arcade_edges[Vector4i(entry[0].x, entry[0].y, entry[1].x, entry[1].y)] = true
	for cell: Vector2i in floor:
		var open := not blocked.has(cell)
		var patch := posmod((cell.x * 73) ^ (cell.y * 157), 83)
		var at_entrance := TomatinaMap.FESTIVAL_ENTRANCE.has_point(cell)
		if open and patch < 9 and TomatinaMap.safe_room_at(cell) < 0 and not at_entrance:
			var at := TomatinaMap.at_cell(Vector2(cell) + Vector2(0.38, 0.62))
			_place_litter(at, cell, patch < 2, 1.38)
		for step: Vector2i in CARDINAL:
			if floor.has(cell + step):
				continue
			var tangent := Vector2i(-step.y, step.x)
			var facing := Vector3(-step.x, 0.0, -step.y)
			var curb := Vector2(cell) + Vector2(0.5, 0.5) + Vector2(step) * 0.5
			var base := TomatinaMap.at_cell(curb)
			var wall_base := base - facing * (WALL_DEPTH * 0.5 + 0.016)
			var half_panel := Vector2(tangent) * 0.5
			wall_base.y = minf(base.y, minf(TomatinaMap.at_cell(curb - half_panel).y,
				TomatinaMap.at_cell(curb + half_panel).y)) - 0.25
			_place("BoundaryWall", wall_base, facing,
				Vector3(StreetMap.CELL + 0.06, TomatinaMap.BOUNDARY_HEIGHT + base.y - wall_base.y, WALL_DEPTH))
			var scatter := posmod(cell.x * 31 + cell.y * 47 + step.x * 13 + step.y * 7, 19)
			var edge_key := Vector4i(cell.x, cell.y, step.x, step.y)
			if street_profile and not at_entrance and scatter < 15 and not arcade_edges.has(edge_key):
				var panel := "UrbanUpperShutters" if scatter < 8 else "UrbanUpperCasements"
				add_placement(panel, Transform3D(Basis(Vector3.UP, atan2(facing.x, facing.z)), base))
			if scatter < 6:
				_place_street_front(base, facing, cell)
			elif scatter < 15:
				_place_facade_detail(base, facing, scatter)
			if scatter < 5 and open and not at_entrance:
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
			var height := 8.7 + 0.9 * float(posmod(cell.x * 17 + cell.y * 31, 6))
			if cell.y > 120 and cell.y < 185:
				height += 1.35
			elif cell.y < 48:
				height -= 0.85
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


func _arcade_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var width := StreetMap.CELL + 0.035
	var clearance := TomatinaMap.ARCADE_CLEARANCE
	var top := TomatinaMap.ARCADE_DECK_TOP
	var depth := TomatinaMap.ARCADE_DEPTH
	var stone := Color("c1a487")
	var trim := Color("dfc3a2")
	var iron := Color("394044")
	_append_box(surface, Vector3(0, (clearance + top) * 0.5, depth * 0.5),
		Vector3(width, top - clearance, depth + 0.08), stone)
	_append_box(surface, Vector3(0, top - 0.08, depth - 0.03), Vector3(width, 0.14, 0.25), trim)
	_append_box(surface, Vector3(0, clearance + 0.04, depth - 0.08), Vector3(width, 0.11, 0.30), trim)
	for level in [0.16, 0.91]:
		_append_box(surface, Vector3(0, top + level, depth - 0.13), Vector3(width, 0.06, 0.095), iron)
		for side in [-1.0, 1.0]:
			_append_box(surface, Vector3(side * (width - 0.10) * 0.5, top + level, depth * 0.5),
				Vector3(0.075, 0.06, depth - 0.14), iron)
	for index in 13:
		var x := lerpf(-width * 0.47, width * 0.47, float(index) / 12.0)
		_append_box(surface, Vector3(x, top + 0.50, depth - 0.13), Vector3(0.048, 0.82, 0.052), iron)
	for x in [-1.62, 0.0, 1.62]:
		_append_box(surface, Vector3(x, clearance - 0.066, depth * 0.48), Vector3(0.18, 0.15, depth), stone.darkened(0.18))
	return surface.commit()


func _arcade_pier_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centre := Vector3(TomatinaMap.ARCADE_PIER_X, 0.0, TomatinaMap.ARCADE_PIER_Z)
	var rise := TomatinaMap.ARCADE_CLEARANCE
	var stone := Color("b39980")
	_append_box(surface, centre + Vector3.UP * (rise * 0.5 - 0.20), Vector3(0.62, rise + 0.4, 0.62), stone)
	for level in [0.08, 0.37, rise - 0.18]:
		_append_box(surface, centre + Vector3.UP * level, Vector3(0.81, 0.18, 0.81), stone.lightened(0.14))
	return surface.commit()


func _upper_storey_mesh(shutter: Color) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var limestone := Color("d9baa0")
	var shade := Color("393737")
	_append_box(surface, Vector3(0, 3.77, 0.06), Vector3(StreetMap.CELL + 0.015, 0.16, 0.16), limestone)
	for x in [-1.06, 1.06]:
		_append_box(surface, Vector3(x, 5.18, 0.078), Vector3(1.05, 1.56, 0.16), limestone)
		_append_box(surface, Vector3(x, 5.19, 0.165), Vector3(0.74, 1.30, 0.04), shade)
		_append_box(surface, Vector3(x, 4.41, 0.20), Vector3(1.16, 0.15, 0.26), limestone.lightened(0.08))
		_append_box(surface, Vector3(x, 6.00, 0.13), Vector3(1.14, 0.13, 0.20), limestone)
		for side in [-1.0, 1.0]:
			var shutter_x: float = x + side * 0.48
			_append_box(surface, Vector3(shutter_x, 5.18, 0.15), Vector3(0.30, 1.26, 0.15), shutter)
			for level in [4.86, 5.17, 5.48]:
				_append_box(surface, Vector3(shutter_x, level, 0.24), Vector3(0.27, 0.035, 0.04), shutter.darkened(0.22))
	return surface.commit()


func _append_box(surface: SurfaceTool, centre: Vector3, size: Vector3, tint: Color) -> void:
	var box := BoxMesh.new()
	box.size = size
	var arrays := box.surface_get_arrays(0)
	for index: int in arrays[Mesh.ARRAY_INDEX]:
		surface.set_color(tint)
		surface.set_normal(arrays[Mesh.ARRAY_NORMAL][index])
		surface.add_vertex(arrays[Mesh.ARRAY_VERTEX][index] + centre)


## A second row of homes makes the winding roads read as lanes within a village.
## These homes live behind the street boundary and never obstruct a route.
func _build_backlots(floor: Dictionary) -> void:
	var previous_tag := record_tag
	record_tag = "backlot"
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
	record_tag = previous_tag


func _place_litter(at: Vector3, cell: Vector2i, boards: bool, spread: float) -> void:
	var angle := float(posmod(cell.x * 9 + cell.y * 17, 37)) * 0.17
	var facing := Vector3(sin(angle), 0.0, cos(angle))
	var model := "BrokenBoards" if boards else "CrushedTomatoes"
	_place(model, at, facing, Vector3(spread, 0.09 if boards else 0.07, spread * 0.72))
	# Every dirty patch gets a second, smaller festival-specific story beat.  The
	# offset keeps the two silhouettes readable while both remain collisionless.
	var variant: int = posmod(cell.x * 43 + cell.y * 67, 3)
	var accent: String = ["FestivalTrashPile", "TomatoBasketSpill", "TornBuntingHeap"][variant]
	var side := Vector3(facing.z, 0.0, -facing.x)
	var accent_at := at + side * (spread * (0.28 if variant != 1 else -0.31))
	accent_at += facing * spread * 0.16
	var height := 0.34 if variant == 1 else 0.11
	_place(accent, accent_at, -facing, Vector3(spread * 0.72, height, spread * 0.58))


func _add_debris(box: Dictionary) -> void:
	var name: String = box["name"]
	var size: Vector3 = box["size"]
	var key := "Rubble"
	var facing := Vector3.BACK
	if box.get("closed_passage", false):
		key = "BrokenFestivalBarrier" if name.ends_with("BrokenBarrier") else "CollapsedStoneWall"
	elif TomatinaMap.is_aftermath_prop(box):
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
			at.y = TomatinaMap.ground_height(at)
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
		return # Replaced by the dedicated pump generator model.
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
	volume.visibility_range_end = 48.0
	volume.visibility_range_end_margin = 5.0
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
	embers.visibility_range_end = 42.0
	embers.visibility_range_end_margin = 5.0
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


## The festival-goers lying in the street, in the order every peer builds them
## -- the floor's own cell order -- so body N is the same body everywhere. Not
## batched with the scenery: each one is a body of its own, which the sauce can
## land on and a player can search. See `TomatinaVictims`.
static func victim_placements() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if TomatinaMap.authored != null and TomatinaMap.authored.has_victims:
		out.assign(TomatinaMap.authored.victims)
		return out
	var blocked := TomatinaMap.blocked_cells()
	for cell: Vector2i in TomatinaMap.floor_cells():
		var victim_mark := posmod((cell.x * 97) ^ (cell.y * 193), 113)
		if blocked.has(cell) or victim_mark >= 2 or TomatinaMap.safe_room_at(cell) >= 0 \
				or TomatinaMap.FESTIVAL_ENTRANCE.has_point(cell) \
				or TomatinaMap.START_PLAZA.has_point(cell) \
				or TomatinaMap.CAPRESE_RESCUE_BAY.has_point(cell) \
				or TomatinaMap.FIRE_BAY.has_point(cell):
			continue
		var victim_angle := float(posmod(cell.x * 31 + cell.y * 59, 41)) * 0.153
		out.push_back({
			"at": TomatinaMap.at_cell(Vector2(cell) + Vector2(
				0.34 + float(posmod(cell.x * 11, 29)) / 100.0,
				0.34 + float(posmod(cell.y * 13, 27)) / 100.0)),
			"facing": Vector3(sin(victim_angle), 0.0, cos(victim_angle)),
			"model": VICTIM_MODELS[posmod(cell.x * 7 + cell.y * 13, VICTIM_MODELS.size())],
		})
	return out


const VICTIM_SIZE := Vector3(1.65, 0.48, 2.15)


func mesh_for(key: String) -> Mesh:
	return _meshes.get(key)


## Bake the fallen guests' material palette into the vertex colors read by the
## toon shader, so each body can still use one surface per pass.
func victim_mesh_for(key: String) -> Mesh:
	var source := mesh_for(key)
	if source == null or key not in VICTIM_MODELS:
		return source
	if not _merged_victim_meshes.has(key):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var colors := PackedColorArray()
		for index in source.get_surface_count():
			surface.append_from(source, index, Transform3D.IDENTITY)
			var arrays := source.surface_get_arrays(index)
			var material := source.surface_get_material(index) as BaseMaterial3D
			var surface_colors := PackedColorArray()
			if material == null and arrays[Mesh.ARRAY_COLOR] != null:
				surface_colors = arrays[Mesh.ARRAY_COLOR]
			else:
				surface_colors.resize(arrays[Mesh.ARRAY_VERTEX].size())
				surface_colors.fill(material.albedo_color if material != null else Color.WHITE)
			colors.append_array(surface_colors)
		var arrays := surface.commit_to_arrays()
		arrays[Mesh.ARRAY_COLOR] = colors
		var merged := ArrayMesh.new()
		merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_merged_victim_meshes[key] = merged
	return _merged_victim_meshes[key]


## Where `_place` puts a model: standing on `at`, turned to `facing`, stretched
## to `size` when one is given. Identity when the model is not in the kit.
func placement_transform(key: String, at: Vector3, facing := Vector3.BACK, size := Vector3.ZERO) -> Transform3D:
	var mesh: Mesh = _meshes.get(key)
	if mesh == null:
		return Transform3D.IDENTITY
	var bounds := mesh.get_aabb()
	var offset := bounds.get_center()
	offset.y = bounds.position.y
	if key == "RefugeShower":
		offset = Vector3.ZERO
	var scale := size / bounds.size if size != Vector3.ZERO else Vector3.ONE
	var basis := Basis(Vector3.UP, atan2(facing.x, facing.z)).scaled_local(scale)
	return Transform3D(basis, at - basis * offset)


func _place(key: String, at: Vector3, facing := Vector3.BACK, size := Vector3.ZERO) -> void:
	add_placement(key, placement_transform(key, at, facing, size))
