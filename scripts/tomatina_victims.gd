class_name TomatinaVictims
extends Node3D
## The festival-goers already lying in the streets when the party arrives.
##
## Each is the village kit's body mesh with a `TomatinaVictimCorpse` box around
## it, so the sauce sticks to them, and each can be searched once with the
## interact key for a few coins. The coins are dropped beside the body as
## ordinary coin pickups -- the team's shared purse picks them up the usual way
## -- so the only new state on the wire is which bodies have been searched,
## and that rides on the coin state (see `TomatinaSauceParts.coin_state`).

## How close, flat, a player has to stand to the middle of a body to search it.
const LOOT_REACH := 1.9
## What one body gives up. A special tomato is worth one coin half the time and
## a part costs five to seven, so a body is worth a good fight, not a shop trip.
const LOOT_COINS_MIN := 1
const LOOT_COINS_MAX := 2

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
		var mesh: Mesh = art.mesh_for(placement.model) if art != null else null
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


## Authority only: searches body `index` and drops its coins beside it.
func loot(index: int) -> void:
	if index < 0 or index >= positions.size() or _looted.has(index):
		return
	_looted[index] = true
	var parts = world._sauce_parts
	var count := _rng.randi_range(LOOT_COINS_MIN, LOOT_COINS_MAX)
	for coin in count:
		var angle := TAU * (float(coin) + _rng.randf_range(0.0, 0.6)) / float(count)
		parts.drop_coin(positions[index] + Vector3(cos(angle), 0.0, sin(angle)) * 0.55)
	parts.dirty = true


## What a peer has been told was searched.
func set_looted(indices: Array) -> void:
	_looted.clear()
	for index in indices:
		_looted[int(index)] = true


func looted_indices() -> Array:
	return _looted.keys()


func reset() -> void:
	_looted.clear()
