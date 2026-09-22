class_name ScaleTestBase
extends Node3D

const PLAYER_HEIGHT_M := 2.56
const PLAYER_RADIUS_M := 0.64


func initialize_scale(scale_factor: float) -> void:
	$ScaledMap.scale = Vector3.ONE * scale_factor
	$HUD/Info.text = "Map %.2fx  |  Player %.2f m  |  Corridor 45 m" % [
		scale_factor, PLAYER_HEIGHT_M]
	$Camera3D.position = Vector3(18.0, 18.0, 24.0)
	$Camera3D.look_at(Vector3(0.0, 1.2, -10.0), Vector3.UP)
	_capture_if_requested()


func _capture_if_requested() -> void:
	var requested_path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-scale-test="):
			requested_path = argument.trim_prefix("--capture-scale-test=")
	if requested_path.is_empty():
		return
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var absolute_path := ProjectSettings.globalize_path(requested_path)
	var error := image.save_png(absolute_path)
	if error != OK:
		push_error("Could not save scale-test screenshot: %s" % absolute_path)
	else:
		print("SCALE_TEST_SCREENSHOT %s" % absolute_path)
	get_tree().quit(error)
