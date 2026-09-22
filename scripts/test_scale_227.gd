extends ScaleTestBase

const SCALE_FACTOR := 2.27


func _ready() -> void:
	await initialize_scale(SCALE_FACTOR)
