@tool
class_name TomatinaMapProp
extends MeshInstance3D

## 토마티나 맵의 소품 하나(잔해, 상자, 트럭, 소방차 ...). 게임에서는 이 상자 크기대로
## 충돌·오염 상자가 생기고, `prop_name`에 맞는 마을 아트 모델이 그 자리에 놓인다.
##
## - 노드 원점 = 상자 바닥 가운데. 위치를 옮기면 그대로 반영된다.
## - Y축 회전은 90° 단위로만 반영된다(충돌 상자가 축 정렬이라서). 회전하면 크기 X/Z와
##   facing이 함께 돈다.
## - `prop_name`이 아트와 동작을 정한다: TomatoCrate*/TomatoCrateStack*/TomatoCratesSupply*
##   (토마토 보급), *WreckCrate, LoadedTomatoTruck/OverturnedTomatoTruck(보급 트럭),
##   ParkedVan, MarketBarrels, CrushedTomatoes, RefugeTent, RefugeBrazier(불), PlazaTree*,
##   ClosedShortcut*(지름길 문 칸) 등. 모르는 이름은 잔해(Rubble) 모델로 그린다.

enum Group { DEBRIS, PARKED_TRUCK, FIRE_TRUCK }

@export var prop_name := "TomatoCrates":
	set(value):
		prop_name = value
		_refresh()
@export var group := Group.DEBRIS
## 회전 전(0°) 기준 상자 크기, 미터.
@export var size := Vector3(2.6, 1.2, 1.1):
	set(value):
		size = value
		_refresh()
@export var color := Color("8c7a4a"):
	set(value):
		color = value
		_refresh()
## 트럭·잔해 모델이 바라보는 방향(0° 기준). (0,0,0)이면 없음.
@export var facing := Vector3.ZERO:
	set(value):
		facing = value
		_refresh()
## 넘어갈 수 있는 낮은 것(길찾기에서 막지 않음). 0.12m 이하면 충돌 상자도 만들지 않는다.
@export var jumpable := false
## 축제 잔해 모델(CollapsedStall 등)로 그린다. facing이 필요하다.
@export var aftermath := false
## 막힌 골목 잔해 더미 모델로 그린다.
@export var closed_passage := false

static var _materials := {}


func _validate_property(property: Dictionary) -> void:
	TomatinaArtPiece.hide_generated(property)


func _ready() -> void:
	_refresh()


func quarter_turns(xf: Transform3D) -> int:
	return posmod(roundi(xf.basis.orthonormalized().get_euler().y / (PI * 0.5)), 4)


## 게임이 읽는 상자 사전. `xf`는 맵 루트 기준 변환.
func to_box(xf: Transform3D) -> Dictionary:
	var turns := quarter_turns(xf)
	var scaled := size * xf.basis.get_scale().abs()
	var world_size := scaled if turns % 2 == 0 else Vector3(scaled.z, scaled.y, scaled.x)
	var box := {
		"name": prop_name,
		"position": xf.origin + Vector3.UP * world_size.y * 0.5,
		"size": world_size,
		"color": color,
	}
	if facing != Vector3.ZERO:
		box["facing"] = facing if turns == 0 else facing.rotated(Vector3.UP, turns * PI * 0.5).round()
	if jumpable:
		box["jumpable"] = true
	if aftermath:
		box["aftermath"] = true
	if closed_passage:
		box["closed_passage"] = true
	return box


## 에디터 미리보기: 노드 자신이 반투명 충돌 상자(+ facing 쪽 노란 점)를 메시로 가진다.
func _refresh() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var box := BoxMesh.new()
	box.size = size
	box.material = _material(color)
	var preview := TomatinaArtPiece.offset_mesh(box, Transform3D(Basis(), Vector3.UP * size.y * 0.5))
	if facing != Vector3.ZERO:
		var tip := BoxMesh.new()
		tip.size = Vector3(0.3, 0.3, 0.3)
		tip.material = _material(Color.YELLOW)
		var flat := Vector3(facing.x, 0.0, facing.z).normalized()
		var reach := absf(flat.x) * size.x * 0.5 + absf(flat.z) * size.z * 0.5
		var arrow := TomatinaArtPiece.offset_mesh(tip, Transform3D(Basis(), Vector3.UP * size.y + flat * reach))
		var tool := SurfaceTool.new()
		tool.create_from(arrow, 0)
		tool.commit(preview)
		preview.surface_set_material(preview.get_surface_count() - 1, tip.material)
	mesh = preview
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _material(tint: Color) -> StandardMaterial3D:
	var key := tint.to_html()
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(tint, 0.25)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_materials[key] = material
	return _materials[key]
