extends "res://tests/probe_tutorial.gd"

# Run windowed to capture the same real traversal used by the end-to-end probe.
# Godot --path . --resolution 1280x720 --script res://tests/capture_tutorial.gd
func _initialize() -> void:
	_capture = true
	call_deferred("_run")

func _run() -> void:
	await scenario(true)
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
