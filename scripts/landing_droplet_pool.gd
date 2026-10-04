class_name LandingDropletPool
extends RefCounted

## **The settled sauce a landing leaves behind, and nothing else.**
##
## Purely decorative: these are drawn, they expire, and that is all they do. They
## mark no surface, damage nothing and travel over no wire -- a peer that drew
## none of them would still agree with every other peer about the state of the
## world. The thrown pieces of an impact are a different pool with a different
## job (`MayoSpeck`, which lands and paints), and the two are deliberately not
## the same thing.
##
## **What it is given, it is given.** The pool holds no reference to the world
## and reads nothing off it. The tuning a spawn needs arrives as arguments on the
## call, so a value changed in the inspector between two landings is used by the
## second one without this having to know that a value changed at all -- and the
## random source is handed in rather than owned, because the order its numbers
## are drawn in is shared with everything else that draws from it.

## One drawn droplet.
class Droplet:
	## Which sauce this one is, so the pool -- one pool for the whole world,
	## shared by everyone firing into it -- can hold four players' worth of
	## different sauce at once. Written into the instance's own colour, because
	## the alternative is a pool per sauce and three times the instances.
	var sauce := ContaminationGrid.KIND_MAYO
	var active := false
	var position := Vector3.ZERO
	var radius := 0.014
	var expires_at := 0.0


var multimesh: MultiMesh
var instance: MultiMeshInstance3D
var droplets: Array[Droplet] = []
var active_indices := PackedInt32Array()

## Landings that threw droplets, droplets replaced while still alive, and how
## much life those had left. The last two are what say whether the pool is big
## enough: a pool that is full is only a problem if the life left is not near
## zero. Kept here rather than on the world because this is the only thing that
## can count them.
var spawns := 0
var overwrites := 0
var overwritten_life := 0.0

var _buffer := PackedFloat32Array()
var _buffer_dirty := false
var _cursor := 0
## The layout of one slot, handed in at build time so the pool does not have to
## agree with the rest of the game about it twice.
var _stride := 16
var _colour_offset := 12


## Builds the pool and hangs it under `parent`.
##
## `size` slots, all of them allocated up front: a landing takes its droplets
## whether or not there is room, and a full pool replaces the droplet taken
## longest ago. What it has to hold is
##
##     needed = landings per second x droplets per landing x lifetime
##
## and `overwrites` against `overwritten_life` is what says whether it does.
func build(parent: Node3D, material: Material, size: int, stride: int,
		colour_offset: int) -> void:
	_stride = stride
	_colour_offset = colour_offset

	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 8
	mesh.rings = 4
	mesh.material = material

	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	# Per-instance colour, because the pool is one pool for the whole world and a
	# party can have three sauces in the air at once.
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = size
	_buffer.resize(size * _stride)
	_buffer.fill(0.0)
	multimesh.buffer = _buffer

	instance = MultiMeshInstance3D.new()
	instance.name = "LandingDropletPool"
	instance.add_to_group("mayo_droplets")
	instance.multimesh = multimesh
	# Like the strand ribbons, the pool's bounds are set by hand -- a MultiMesh
	# whose buffer is written directly does not work them out -- and, like them,
	# they used to be a fixed box around the origin from when the world was one
	# 48 m floor. Now they follow the droplets that are actually alive.
	update_bounds()
	parent.add_child(instance)

	droplets.resize(size)
	for i in size:
		droplets[i] = Droplet.new()


## A landing threw sauce. Every number the burst needs is an argument: nothing
## here is cached from a previous call, so the inspector stays live.
func spawn(position: Vector3, sauce: int, tint: Color, count: int,
		lifetime: float, radius_min: float, radius_max: float,
		rng: RandomNumberGenerator, now: float) -> void:
	if multimesh == null:
		return
	spawns += 1
	var expires_at := now + lifetime
	for _i in count:
		var droplet := droplets[_cursor]
		if not droplet.active:
			active_indices.push_back(_cursor)
		else:
			# The cursor walks the pool in order and every droplet is given the
			# same lifetime, so the slot it arrives at is always the one taken
			# longest ago. Recorded so that can be checked rather than assumed:
			# if it holds, what is overwritten was about to expire anyway.
			overwrites += 1
			overwritten_life += maxf(droplet.expires_at - now, 0.0)
		_cursor = (_cursor + 1) % droplets.size()
		var angle := rng.randf_range(0.0, TAU)
		var spread_radius := sqrt(rng.randf()) * 0.12
		droplet.active = true
		droplet.sauce = sauce
		droplet.expires_at = expires_at
		droplet.radius = rng.randf_range(radius_min, radius_max)
		droplet.position = position + Vector3(cos(angle) * spread_radius, droplet.radius, sin(angle) * spread_radius)
		write((_cursor - 1 + droplets.size()) % droplets.size(),
			droplet.position, droplet.radius * 2.0, tint)
	_buffer_dirty = true


## Retires whatever has run out, and sends the buffer up if anything changed.
func advance(now: float) -> void:
	if multimesh == null or active_indices.is_empty():
		return
	for active_index in range(active_indices.size() - 1, -1, -1):
		var i := active_indices[active_index]
		var droplet := droplets[i]
		if now >= droplet.expires_at:
			droplet.active = false
			write(i, Vector3.ZERO, 0.0)
			active_indices.remove_at(active_index)
			_buffer_dirty = true
	if _buffer_dirty:
		multimesh.buffer = _buffer
		update_bounds()
		_buffer_dirty = false


## Bounds over the live droplets only. Droplets land in bursts a few metres
## across and last a third of a second, so this box is small and moves with the
## fight rather than covering the map -- which is the point of having one.
func update_bounds() -> void:
	if instance == null:
		return
	if active_indices.is_empty():
		# An empty box draws nothing, which is what an empty pool should do.
		instance.custom_aabb = AABB()
		return
	var low := Vector3.INF
	var high := -Vector3.INF
	for i in active_indices:
		var droplet: Droplet = droplets[i]
		var extent := Vector3.ONE * droplet.radius
		low = low.min(droplet.position - extent)
		high = high.max(droplet.position + extent)
	instance.custom_aabb = AABB(low, high - low)


func write(index: int, position: Vector3, uniform_scale: float,
		tint := Color.WHITE) -> void:
	var offset := index * _stride
	# MultiMesh 3D transform buffer: three rows of (basis xyz, origin).
	_buffer[offset] = uniform_scale
	_buffer[offset + 1] = 0.0
	_buffer[offset + 2] = 0.0
	_buffer[offset + 3] = position.x
	_buffer[offset + 4] = 0.0
	_buffer[offset + 5] = uniform_scale
	_buffer[offset + 6] = 0.0
	_buffer[offset + 7] = position.y
	_buffer[offset + 8] = 0.0
	_buffer[offset + 9] = 0.0
	_buffer[offset + 10] = uniform_scale
	_buffer[offset + 11] = position.z
	var colour := offset + _colour_offset
	_buffer[colour] = tint.r
	_buffer[colour + 1] = tint.g
	_buffer[colour + 2] = tint.b
	_buffer[colour + 3] = tint.a


func reset_counters() -> void:
	spawns = 0
	overwrites = 0
	overwritten_life = 0.0
