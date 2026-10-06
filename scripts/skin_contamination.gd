class_name SkinContamination
extends Node3D

## **Sauce painted into the model's own UV map, one mask per mesh.**
##
## The chart this replaces wraps a cylinder round the body and maps a hit by its
## angle about the axis. That is honest for a solid of revolution and the burger
## is not one: it has two arms, and a cylinder gives an arm the same column of
## the mask as the body behind it, so sauce on one shows up on the other. It also
## throws the radius away, so anything that is not exactly at the wrapping radius
## -- a mouth, a bun's curve -- lands beside where it was aimed.
##
## The model is already unwrapped. Its artist laid every piece out in a 0..1
## atlas with the arms well away from the body, so painting into that map puts
## the sauce on the skin and leaves it there: the mask is read back through the
## same UV the texture is, which means a stain **follows the animation** rather
## than swimming over a body that moves underneath it.
##
## **One mask per mesh, because each mesh fills the atlas.** Both of the burger's
## meshes use the whole 0..1 square, so sharing one would stack the hand on top
## of the body.

## How a hit finds its triangle: a short ray against a static copy of the mesh,
## on a layer nothing else uses, which returns the face it crossed. The primary
## strand ray hits the usual colliders; this one only answers "which triangle".
const PAINT_LAYER := 8

var grids: Array[ContaminationGrid] = []
var meshes: Array[MeshInstance3D] = []
var resolution := 512
var brush_radius := 0.2
var mayo_color := Color("fff0a8")

var _body: Node3D
var _probe: StaticBody3D
## Per mesh: the arrays the UV lookup reads, and how many UV units a metre is.
var _faces: Array = []


## Builds a mask and a lookup table for every mesh under `visual_root`, and one
## static copy of them all to raycast against.
func configure(body: Node3D, visual_root: Node3D, clean_color: Color,
		atlas: int, radius: float) -> void:
	_body = body
	resolution = atlas
	brush_radius = radius
	_probe = StaticBody3D.new()
	_probe.name = "PaintProbe"
	# Seen by the paint ray and by nothing else: it must not block a player, a
	# monster, or the strand itself.
	_probe.collision_layer = PAINT_LAYER
	_probe.collision_mask = 0
	add_child(_probe)

	for node in visual_root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null or mesh_node.mesh.get_surface_count() == 0:
			continue
		var arrays: Array = mesh_node.mesh.surface_get_arrays(0)
		if arrays[Mesh.ARRAY_TEX_UV] == null:
			continue
		var grid := ContaminationGrid.new()
		# **Measured in texels, not in UV units.** The grid floors its cell size at
		# a centimetre -- it was built for a floor measured in metres -- so asking
		# for a 1/512 cell over a one-unit square silently gives a hundred cells
		# across instead of five hundred. One texel to a cell says the same thing
		# in units the grid will accept.
		grid.configure(Vector2(float(resolution), float(resolution)), 1.0,
			clean_color, mayo_color, 128)
		grids.push_back(grid)
		meshes.push_back(mesh_node)
		_faces.push_back({
			"vertices": arrays[Mesh.ARRAY_VERTEX],
			"uvs": arrays[Mesh.ARRAY_TEX_UV],
			"indices": arrays[Mesh.ARRAY_INDEX],
		})
		var shape := CollisionShape3D.new()
		var trimesh := mesh_node.mesh.create_trimesh_shape()
		# **Hit from either side.** A trimesh is one-sided by default, and this
		# ray often starts inside the body: the pose has moved the skin off the
		# rest mesh the probe is built from, so the point sauce landed on can sit
		# behind the surface rather than in front of it. One-sided, those rays
		# pass straight through and the splat is lost.
		trimesh.backface_collision = true
		shape.shape = trimesh
		_probe.add_child(shape)
		shape.global_transform = mesh_node.global_transform

		var material := ShaderMaterial.new()
		material.shader = preload("res://scripts/skin_contamination.gdshader")
		material.set_shader_parameter("mask_texture", grid.texture)
		material.set_shader_parameter("mayo_color", mayo_color)
		mesh_node.material_overlay = material


## **Which UV a world point is on, or (-1, -1) if it is on nothing.**
##
## Answered by a short ray through the point rather than by searching the mesh:
## the physics server already has the triangles indexed, and it hands back the
## face it crossed. The ray runs from a little outside the surface to a little
## inside it along the normal the first hit reported, so it crosses the same
## triangle the sauce landed on rather than one on the far side of the body.
func uv_at(world_position: Vector3, world_normal: Vector3) -> Dictionary:
	if _probe == null or grids.is_empty():
		return {}
	var space := _body.get_world_3d().direct_space_state
	# **Tried along more than one line.** The obvious one is the surface normal
	# the strand reported, and it is usually right -- but that normal comes off a
	# capsule that follows a bone, and where the pose has moved the skin away from
	# the rest mesh this probe is built from, a ray along it can run parallel to
	# the surface and cross nothing. Falling back to the line out from the body's
	# middle, and then to straight down, catches those without changing the answer
	# anywhere the first line already works.
	var middle: Vector3 = _body.global_position
	var radial := world_position - middle
	radial.y = 0.0
	var lines: Array[Vector3] = [world_normal.normalized()]
	if radial.length_squared() > 0.000001:
		lines.push_back(radial.normalized())
	lines.push_back(Vector3.UP)
	var hit := {}
	for line in lines:
		var out: Vector3 = line * 1.5
		var query := PhysicsRayQueryParameters3D.create(
			world_position + out, world_position - out)
		query.collision_mask = PAINT_LAYER
		query.collide_with_areas = false
		hit = space.intersect_ray(query)
		if not hit.is_empty() and hit.has("face_index"):
			break
		hit = {}
	if hit.is_empty():
		return {}
	var which: int = _mesh_of(hit["shape"])
	if which < 0:
		return {}
	var uv := _face_uv(which, int(hit["face_index"]), hit["position"])
	if uv.x < 0.0:
		return {}
	return {"mesh": which, "uv": uv}


## The index of the mesh a probe shape belongs to. The shapes are added in the
## same order as the meshes, which is what makes this a lookup and not a search.
func _mesh_of(shape_index: int) -> int:
	return shape_index if shape_index >= 0 and shape_index < grids.size() else -1


## Barycentric interpolation of the triangle's three UVs at the hit point.
func _face_uv(which: int, face: int, world_position: Vector3) -> Vector2:
	var data: Dictionary = _faces[which]
	var indices: PackedInt32Array = data["indices"]
	if face < 0 or face * 3 + 2 >= indices.size():
		return Vector2(-1.0, -1.0)
	var vertices: PackedVector3Array = data["vertices"]
	var uvs: PackedVector2Array = data["uvs"]
	var into: Transform3D = meshes[which].global_transform.affine_inverse()
	var at: Vector3 = into * world_position
	var a: Vector3 = vertices[indices[face * 3]]
	var b: Vector3 = vertices[indices[face * 3 + 1]]
	var c: Vector3 = vertices[indices[face * 3 + 2]]
	var weights := _barycentric(at, a, b, c)
	return uvs[indices[face * 3]] * weights.x \
		+ uvs[indices[face * 3 + 1]] * weights.y \
		+ uvs[indices[face * 3 + 2]] * weights.z


## Where a point sits inside a triangle, as the three corner weights.
static func _barycentric(at: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var v0 := b - a
	var v1 := c - a
	var v2 := at - a
	var d00 := v0.dot(v0)
	var d01 := v0.dot(v1)
	var d11 := v1.dot(v1)
	var d20 := v2.dot(v0)
	var d21 := v2.dot(v1)
	var denominator := d00 * d11 - d01 * d01
	if absf(denominator) < 0.000000001:
		return Vector3(1.0, 0.0, 0.0)
	var v := (d11 * d20 - d01 * d21) / denominator
	var w := (d00 * d21 - d01 * d20) / denominator
	return Vector3(1.0 - v - w, v, w)


## Marks the hit and returns which mesh and which cell, for the wire.
func paint_mayo(world_position: Vector3, world_normal: Vector3) -> Vector3i:
	var found := uv_at(world_position, world_normal)
	if found.is_empty():
		return Vector3i(-1, -1, -1)
	var which: int = found["mesh"]
	var cell := paint_cell_uv(which, found["uv"])
	return Vector3i(which, cell.x, cell.y)


## The side every peer runs: a cell on a mesh, already decided by the host.
func paint_mesh_cell(which: int, cell: Vector2i) -> void:
	if which < 0 or which >= grids.size():
		return
	grids[which].paint_cell(cell, _brush_in_texels())


func paint_cell_uv(which: int, uv: Vector2) -> Vector2i:
	var half := float(resolution) * 0.5
	return grids[which].paint(uv * float(resolution) - Vector2(half, half),
		_brush_in_texels())


## The brush in texels. Measured off the model rather than guessed: the atlas is
## not the world's scale, and on this one a metre is about a twelfth of the
## square, so a 0.20 m brush is a nine-texel disc at 512.
func _brush_in_texels() -> float:
	return brush_radius * _uv_per_metre * float(resolution)


var _uv_per_metre := 0.0866


func upload_if_dirty() -> void:
	for grid in grids:
		grid.upload_if_dirty()


func clear() -> void:
	for grid in grids:
		grid.clear()


func cells_md5() -> String:
	var parts := PackedStringArray()
	for grid in grids:
		parts.push_back(grid.cells_md5())
	return "|".join(parts)
