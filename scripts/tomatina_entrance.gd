extends Node3D

const GATE := preload("res://assets/props/Stage2_FestivalEntrance/Stage2_FestivalEntrance.glb")
const BONGO := preload("res://assets/props/Stage2_PartyBongo/Stage2_PartyBongo.glb")
const OPEN_ANGLE := 1.76

var truck: Node3D
var left_door: Node3D
var right_door: Node3D
var wheels: Array[Node3D] = []


func build(world: Node3D) -> void:
	var gate := GATE.instantiate() as Node3D
	add_child(gate)
	gate.position = TomatinaMap.entrance_position()
	var sign := Label3D.new()
	sign.name = "FestivalGateLettering"
	sign.text = "LA TOMATINA"
	sign.font_size = 116
	sign.pixel_size = 0.0088
	sign.outline_size = 0
	sign.modulate = Color("fff0ce")
	sign.position = Vector3(0.0, 6.13, 1.235)
	gate.add_child(sign)
	truck = BONGO.instantiate() as Node3D
	truck.name = "PartyBongo"
	add_child(truck)
	left_door = truck.find_child("RearDoorLeft", true, false) as Node3D
	right_door = truck.find_child("RearDoorRight", true, false) as Node3D
	for wheel in truck.find_children("Wheel*", "Node3D", true, false):
		wheels.append(wheel)
	park()
	for box in TomatinaMap.entrance_obstacles():
		world._create_wall(box.name, box.position, box.size, Color("885e49"), false)


func approach(distance: float, bounce: float) -> void:
	truck.position = TomatinaMap.party_truck_position() + Vector3(0.0, bounce, distance)
	for wheel in wheels:
		wheel.rotation.x = distance / 0.54


func open_doors(amount: float) -> void:
	left_door.rotation.y = -OPEN_ANGLE * amount
	right_door.rotation.y = OPEN_ANGLE * amount


func park() -> void:
	approach(0.0, 0.0)
	open_doors(1.0)
