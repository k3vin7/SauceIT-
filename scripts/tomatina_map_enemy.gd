@tool
class_name TomatinaMapEnemy
extends MeshInstance3D

## 토마티나 맵에 처음부터 서 있는 적 하나. 노드 위치가 생성 위치다.
## 어느 구간(leg)의 적인지는 발밑 바닥 칸(Floor GridMap 아이템)으로 정해진다.
## 광장(TomatinaMap.PLAZA) 안에 두면 최종전 경비로 묶인다.

const KIND_COLORS := {
	"TOMATO_GRUNT": Color("d9483b"),
	"TOMATO_BRUTE": Color("8f1d1d"),
	"BOWLING_TOMATO": Color("f08a24"),
	"KETCHUP_SPITTER": Color("e0c02a"),
	"CAPRESE_CRAWLER": Color("4fa35a"),
}

@export_enum("TOMATO_GRUNT", "TOMATO_BRUTE", "BOWLING_TOMATO", "KETCHUP_SPITTER", "CAPRESE_CRAWLER")
var kind := "TOMATO_GRUNT":
	set(value):
		kind = value
		_refresh()
## 비워 두면 일반 적. 골목 매복 그룹이나 거리 특수 적 역할을 지정할 수 있다.
@export var tag := ""

static var _meshes := {}


func _validate_property(property: Dictionary) -> void:
	TomatinaArtPiece.hide_generated(property)


func _ready() -> void:
	_refresh()


func to_entry(xf: Transform3D) -> Array:
	var entry: Array = [kind, TomatinaAuthoredMap.world_to_cell(xf.origin)]
	if tag == String(TomatinaMap.ALLEY_REINFORCEMENT):
		entry.append(TomatinaMap.ALLEY_REINFORCEMENT)
	elif tag.is_valid_int():
		entry.append(tag.to_int())
	else:
		for role in TomatinaMap.STREET_ELITES + TomatinaMap.STREET_REINFORCEMENTS:
			if tag == String(role[2]):
				entry.append(role[2])
				break
	return entry


func _refresh() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if not _meshes.has(kind):
		var big := kind == "TOMATO_BRUTE"
		var body := CapsuleMesh.new()
		body.radius = 0.75 if big else 0.45
		body.height = 2.6 if big else 1.6
		var material := StandardMaterial3D.new()
		material.albedo_color = KIND_COLORS.get(kind, Color.WHITE)
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		body.material = material
		_meshes[kind] = TomatinaArtPiece.offset_mesh(body, Transform3D(Basis(), Vector3.UP * body.height * 0.5))
	mesh = _meshes[kind]
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
