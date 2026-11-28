class_name TomatinaVictims
extends Node3D
## The festival-goers already lying in the streets when the party arrives.
##
## Each is the village kit's body mesh with a `TomatinaVictimCorpse` box around
## it, so the sauce sticks to them. Each body can be searched once by holding
## interact for a full second. The coins go straight into every purse
## (`TomatinaSauceParts.grant_coins`) and the HUD flies them in one at a time,
## so the only new state on the wire is which bodies have been searched, and
## that rides on the coin state (see `TomatinaSauceParts.coin_state`).

## How close, flat, a player has to stand to the middle of a body to search it.
const LOOT_REACH := 1.9
const LOOT_TIME := 1.0
## What one body gives up: one to five coins, 19% each, and `LOOT_JACKPOT` the
## remaining 5% of the time.
const LOOT_COINS_MIN := 1
const LOOT_COINS_MAX := 5
const LOOT_JACKPOT := 10
const LOOT_JACKPOT_CHANCE := 0.05

var world: Node3D
var bodies: Array[TomatinaVictimCorpse] = []
var positions: Array[Vector3] = []
var _looted := {}
var _rng := RandomNumberGenerator.new()


## Builds every body, in `TomatinaVillageArt.victim_placements` order. Each box
## is added to the world's walls here, so call this at the same point of the
## build on every peer: the wall index is what a splat on it is sent as.
func build(art: TomatinaVillageArt) -> void:
	var finish := ShaderMaterial.new()
	finish.shader = TomatinaVillageArt.TOON_SHADER
	var size := TomatinaVillageArt.VICTIM_SIZE
	var placements := TomatinaVillageArt.victim_placements()
	for index in placements.size():
		var placement: Dictionary = placements[index]
		var at: Vector3 = placement.at
		var facing: Vector3 = placement.facing
		var body := TomatinaVictimCorpse.new()
		body.name = "FestivalVictim%02d" % index
		body.size = size
		body.paint_only = true
		body.visible_surface = false
		body.cell_size = world.grid_cell_size
		body.brush_radius = world.contamination_brush_radius
		# Found by the stream's casts, walked through by everyone.
		body.collision_layer = world.CORPSE_LAYER
		body.collision_mask = 0
		add_child(body)
		body.global_transform = Transform3D(Basis(Vector3.UP, atan2(facing.x, facing.z)),
			at + Vector3.UP * size.y * 0.5)
		world._walls.push_back(body)
		bodies.push_back(body)
		positions.push_back(at)
		# 시체마다 피부와 머리색이 다르다. 번호로 정하므로 모든 화면에서 같은 사람이다.
		var mesh: Mesh = art.victim_mesh_for(placement.model, look_of(index)) if art != null else null
		if mesh == null:
			continue
		var view := MeshInstance3D.new()
		view.name = "FestivalVictimBody%02d" % index
		view.mesh = mesh
		view.material_override = finish
		add_child(view)
		# 새 쓰러진 손님 모델(Fallen*)은 제 크기로 만든 것이라 늘이지 않는다.
		view.global_transform = art.placement_transform(placement.model, at, facing,
			Vector3.ZERO if String(placement.model).begins_with("Fallen") else size)
		body.attach_view(view)


## Which of `TomatinaVillageArt.VICTIM_LOOKS` body `index` wears. Neighbours in
## the build order never match, and the whole list comes round before repeating.
static func look_of(index: int) -> int:
	return posmod(index * 7 + 3, TomatinaVillageArt.VICTIM_LOOKS.size())


## The nearest body within reach of `at` that has not been searched, or -1.
func in_reach(at: Vector3) -> int:
	var best := -1
	var best_distance := LOOT_REACH * LOOT_REACH
	for index in positions.size():
		if _looted.has(index):
			continue
		var offset := positions[index] - at
		var distance := Vector2(offset.x, offset.z).length_squared()
		if distance <= best_distance and absf(offset.y) < 2.5:
			best = index
			best_distance = distance
	return best


func is_looted(index: int) -> bool:
	return _looted.has(index)


func can_loot(index: int, at: Vector3) -> bool:
	if index < 0 or index >= positions.size() or is_looted(index):
		return false
	var offset := positions[index] - at
	return Vector2(offset.x, offset.z).length_squared() <= LOOT_REACH * LOOT_REACH and absf(offset.y) < 2.5


## How many coins a body holds, given a roll in [0, 1).
static func coins_for(roll: float) -> int:
	if roll < LOOT_JACKPOT_CHANCE:
		return LOOT_JACKPOT
	var span := LOOT_COINS_MAX - LOOT_COINS_MIN + 1
	var rest := (roll - LOOT_JACKPOT_CHANCE) / (1.0 - LOOT_JACKPOT_CHANCE)
	return LOOT_COINS_MIN + clampi(int(rest * span), 0, span - 1)


## Authority only: searches body `index` and pays its coins into every purse.
func loot(index: int) -> void:
	if index < 0 or index >= positions.size() or _looted.has(index):
		return
	_looted[index] = true
	world._sauce_parts.grant_coins(coins_for(_rng.randf()), positions[index] + Vector3.UP * 0.4)


## What a peer has been told was searched.
func set_looted(indices: Array) -> void:
	var before := _looted
	_looted = {}
	for index in indices:
		_looted[int(index)] = true
		if not before.has(int(index)) and int(index) >= 0 and int(index) < positions.size() \
				and world != null and world.get("_sauce_parts") != null:
			world._sauce_parts.note_burst(positions[int(index)] + Vector3.UP * 0.4)


func looted_indices() -> Array:
	return _looted.keys()


func reset() -> void:
	_looted.clear()
