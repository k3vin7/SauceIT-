@tool
class_name TomatinaArtPiece
extends MeshInstance3D

## 마을 키트(Stage2_TomatinaVillage.glb)의 모델 한 조각: 집, 담장, 창문, 등불, 소품 모델 ...
## 노드 변환(위치·회전·크기)이 그대로 모델 변환이다. 충돌은 없다 -- 순수 그림이다.
## 게임에서는 같은 모델끼리 MultiMesh로 다시 묶어 그린다(원래 맵과 같은 방식).
## 모델 이름은 `TomatinaVillageArt` 키트의 메시 이름(HouseCream, BoundaryWall, TrimStone ...).
## 메시·재질은 `model`에서 매번 만들어지므로 씬 파일에는 저장하지 않는다.

@export var model := "HouseCream":
	set(value):
		model = value
		_refresh()

static var _kit: TomatinaVillageArt
static var _finishes := {}


static func kit() -> TomatinaVillageArt:
	if _kit == null:
		_kit = TomatinaVillageArt.new()
		if not _kit.load_kit():
			push_warning("TomatinaArtPiece: village kit did not load")
	return _kit


## `source`의 모든 면을 `xf`만큼 옮긴 새 메시(면별 재질 유지). 미리보기 메시를 노드 원점에서
## 띄워 놓을 때 쓴다 -- 노드 자신이 그 메시를 가져야 에디터에서 클릭으로 잡힌다.
static func offset_mesh(source: Mesh, xf: Transform3D) -> ArrayMesh:
	# 면이 하나도 없는 ArrayMesh는 렌더러에 빈 메시로 넘어가 에러를 낸다. 그럴 땐 null.
	if source == null or source.get_surface_count() == 0:
		return null
	var out := ArrayMesh.new()
	for surface in source.get_surface_count():
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		tool.append_from(source, surface, xf)
		tool.commit(out)
		out.surface_set_material(out.get_surface_count() - 1, source.surface_get_material(surface))
	return out


## 그림 속성은 코드가 채우므로 씬에 저장하지 않는다.
static func hide_generated(property: Dictionary) -> void:
	if property.name in ["mesh", "material_override", "cast_shadow"]:
		property.usage &= ~PROPERTY_USAGE_STORAGE


func _validate_property(property: Dictionary) -> void:
	hide_generated(property)


func _ready() -> void:
	_refresh()


func _refresh() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	mesh = kit().mesh_for(model)
	material_override = TomatinaVillageArt.finish_for(model, _finishes)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if model in TomatinaVillageArt.NO_SHADOW \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
