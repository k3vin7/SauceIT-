@tool
class_name TomatinaMapVictim
extends MeshInstance3D

## 길에 쓰러져 있는 축제 참가자 하나(뒤지면 동전이 나온다). 위치·Y축 회전이 그대로 쓰인다.

@export_enum("FestivalVictimProne", "FestivalVictimSprawled", "FestivalVictimSide")
var model := "FestivalVictimProne":
	set(value):
		model = value
		_refresh()

static var _meshes := {}
static var _material: ShaderMaterial


func _validate_property(property: Dictionary) -> void:
	TomatinaArtPiece.hide_generated(property)


func _ready() -> void:
	_refresh()


func to_placement(xf: Transform3D) -> Dictionary:
	var yaw := xf.basis.get_euler().y
	return {"at": xf.origin, "facing": Vector3(sin(yaw), 0.0, cos(yaw)), "model": model}


func _refresh() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if not _meshes.has(model):
		var kit := TomatinaArtPiece.kit()
		# 게임과 같은 몸 변환을 노드 기준(원점·정면)으로 메시에 구워 넣는다.
		_meshes[model] = TomatinaArtPiece.offset_mesh(kit.mesh_for(model),
			kit.placement_transform(model, Vector3.ZERO, Vector3.BACK, TomatinaVillageArt.VICTIM_SIZE))
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = TomatinaVillageArt.TOON_SHADER
	mesh = _meshes[model]
	material_override = _material
