extends MeshInstance3D

const AVATAR_LAYER := 18
const SURFACE_LAYER := 19
const MAX_DISTANCE := 13.0
const CAMERA_CLIP := 0.015

var _reflection: SubViewport
var _camera: Camera3D
var _half_size: Vector2


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	var quad := mesh as QuadMesh
	_half_size = quad.size * 0.5
	layers = 1 << (SURFACE_LAYER - 1)
	_reflection = SubViewport.new()
	# Match the 1.8 × 1.1 m glass. Only draw while the glass can be seen.
	_reflection.size = Vector2i(576, 352)
	_reflection.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_reflection)
	_camera = Camera3D.new()
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.set_cull_mask_value(SURFACE_LAYER, false)
	_reflection.add_child(_camera)
	_camera.make_current()

	var glass := StandardMaterial3D.new()
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass.albedo_color = Color(0.95, 0.97, 1.0)
	glass.albedo_texture = _reflection.get_texture()
	# The virtual camera looks out of the glass, reversing its horizontal axis.
	glass.uv1_scale = Vector3(-1.0, 1.0, 1.0)
	glass.uv1_offset = Vector3.RIGHT
	material_override = glass


func _process(_delta: float) -> void:
	var viewer := get_viewport().get_camera_3d()
	var centre := global_position
	var frame := global_basis.orthonormalized()
	var normal := frame.z
	var eye := viewer.get_camera_transform().origin if viewer != null else centre
	var relative := eye - centre
	var depth := relative.dot(normal)
	if viewer == null or depth < 0.05 or relative.length_squared() > MAX_DISTANCE * MAX_DISTANCE:
		_reflection.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	var radius := _half_size.length()
	for plane in viewer.get_frustum():
		if plane.distance_to(centre) > radius:
			_reflection.render_target_update_mode = SubViewport.UPDATE_DISABLED
			return

	# Match the virtual eye's rays to the four edges of the glass. Placing the
	# near plane just past its face clips the wall behind the virtual camera.
	var reflected := eye - normal * (depth * 2.0)
	var basis := Basis(-frame.x, frame.y, -normal)
	_camera.global_transform = Transform3D(basis, reflected)
	var near := depth + CAMERA_CLIP
	var projected := near / depth
	var offset := Vector2(relative.dot(frame.x), -relative.dot(frame.y)) * projected
	_camera.set_frustum(_half_size.y * 2.0 * projected, offset, near, near + 25.0)
	_reflection.render_target_update_mode = SubViewport.UPDATE_ALWAYS
