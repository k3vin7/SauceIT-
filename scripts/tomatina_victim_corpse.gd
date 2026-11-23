class_name TomatinaVictimCorpse
extends ContaminableObject
## A festival-goer lying in the street, as something the sauce lands on.
##
## The body itself is the village kit's mesh; this is the invisible box it lies
## in. The box is on the corpse layer -- the stream's casts find it, nobody
## walks into it -- and it is one of the world's walls as far as the sauce is
## concerned, so a splat on it is recorded, sent and replayed exactly as one on
## a wall is, and a late joiner gets it in the grid snapshot.
##
## **Everything goes on the top face.** The body lies flat and is seen from
## above, and the overlay on its mesh projects the top face straight down onto
## it. A strand coming in low from the side would otherwise land on a side face
## that nothing draws.

const OVERLAY_SHADER := preload("res://scripts/victim_contamination_overlay.gdshader")
const TOP_FACE := 2

var _view: MeshInstance3D
var _overlay: ShaderMaterial


## Draws this box's sauce on `view`, the body lying in it. The overlay goes on
## at the first stain rather than now, so a clean body costs no extra pass.
func attach_view(view: MeshInstance3D) -> void:
	_view = view
	_overlay = ShaderMaterial.new()
	_overlay.shader = OVERLAY_SHADER
	_overlay.set_shader_parameter("box_size", size)
	_overlay.set_shader_parameter("mayo_color", mayo_color)
	_refresh_overlay()


func paint_mayo(world_position: Vector3, _world_normal: Vector3,
		kind := ContaminationGrid.KIND_MAYO) -> Vector3i:
	return super.paint_mayo(world_position, global_transform.basis.y, kind)


func wash_at(world_position: Vector3, _world_normal: Vector3, radius_meters: float) -> Vector3i:
	return super.wash_at(world_position, global_transform.basis.y, radius_meters)


func _rebuild() -> void:
	super._rebuild()
	_refresh_overlay()


func _queue_face_upload(face: int) -> void:
	super._queue_face_upload(face)
	if face == TOP_FACE and is_instance_valid(_view) and _view.material_overlay == null \
			and grids[TOP_FACE].painted_cell_count() > 0:
		_view.material_overlay = _overlay


func _refresh_overlay() -> void:
	if _overlay == null or grids.size() <= TOP_FACE:
		return
	_overlay.set_shader_parameter("mask_texture", grids[TOP_FACE].texture)
	if is_inside_tree():
		_overlay.set_shader_parameter("world_to_box", global_transform.affine_inverse())
