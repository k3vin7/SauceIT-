@tool
class_name TomatinaMapWall
extends MeshInstance3D

## 벽 충돌 상자 하나(보이지 않는 벽, 소스가 묻는 면). 보이는 담장·집은 Art 쪽 조각이다.
## 노드 원점 = 상자 바닥 가운데. Y축 회전은 90° 단위로만 반영된다.
## 적 길찾기는 Floor 칸 기준이라, 벽을 길 안쪽으로 옮기면 Floor 칸도 같이 지워야 한다.
## Walls 폴더는 기본으로 숨겨 둔다(집을 클릭할 때 가리지 않게). 눈 아이콘으로 켜서 편집한다.

@export var size := Vector3(4.608, TomatinaMap.BOUNDARY_HEIGHT, 4.608):
	set(value):
		size = value
		_refresh()

static var _material: StandardMaterial3D


func _validate_property(property: Dictionary) -> void:
	TomatinaArtPiece.hide_generated(property)


func _ready() -> void:
	_refresh()


func to_box(xf: Transform3D) -> Dictionary:
	var turns := posmod(roundi(xf.basis.get_euler().y / (PI * 0.5)), 4)
	var world_size := size if turns % 2 == 0 else Vector3(size.z, size.y, size.x)
	return {"position": xf.origin + Vector3.UP * world_size.y * 0.5, "size": world_size}


func _refresh() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.albedo_color = Color(0.35, 0.55, 1.0, 0.22)
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var box := BoxMesh.new()
	box.size = size
	box.material = _material
	mesh = TomatinaArtPiece.offset_mesh(box, Transform3D(Basis(), Vector3.UP * size.y * 0.5))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
