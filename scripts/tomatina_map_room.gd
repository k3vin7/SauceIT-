@tool
class_name TomatinaMapRoom
extends MeshInstance3D

## 피난처 하나. 노드 위치 = 마당 가운데(바닥), 크기는 칸 단위.
## 마당 칸은 자동으로 바닥이 되고(구간 -1), 샤워기·상점 위치가 이 사각형 기준으로 정해진다.
## 배너·샤워기 모델은 이 노드의 자식이라 같이 움직인다. 텐트·화로·보급 상자는 Props 쪽이라 따로 옮긴다.
## 피난처 수는 3개로 유지한다(배너·체크포인트가 3개를 전제로 한다).

@export var room_name := "피난처":
	set(value):
		room_name = value
		_refresh()
@export var size_cells := Vector2i(5, 5):
	set(value):
		size_cells = Vector2i(maxi(value.x, 1), maxi(value.y, 1))
		_refresh()

static var _material: StandardMaterial3D
var _label: Label3D


func _validate_property(property: Dictionary) -> void:
	TomatinaArtPiece.hide_generated(property)


func _ready() -> void:
	_refresh()


func cell_rect(xf: Transform3D) -> Rect2i:
	var centre := TomatinaAuthoredMap.world_to_cell(xf.origin)
	var corner := centre - Vector2(size_cells) * 0.5
	return Rect2i(Vector2i(roundi(corner.x), roundi(corner.y)), size_cells)


func _refresh() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.albedo_color = Color(0.2, 0.75, 0.5, 0.35)
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var slab := BoxMesh.new()
	slab.size = Vector3(size_cells.x * StreetMap.CELL, 0.3, size_cells.y * StreetMap.CELL)
	slab.material = _material
	mesh = TomatinaArtPiece.offset_mesh(slab, Transform3D(Basis(), Vector3.UP * 0.15))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _label == null:
		_label = Label3D.new()
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.pixel_size = 0.03
		_label.position = Vector3.UP * 5.0
		add_child(_label, false, Node.INTERNAL_MODE_FRONT)
	_label.text = room_name
