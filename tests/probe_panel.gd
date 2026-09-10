extends SceneTree

# The F2 connection panel is built in code, and a Control built in code starts
# with no rect at all: a preset that moves only the anchors leaves it zero-sized,
# and everything anchored inside it then lands on the screen's top-left corner
# instead of its middle. Nothing else in the suite looks at the HUD, so this is
# the check that the panel is actually on screen:
#   * the panel's root and its dim backdrop cover the whole viewport
#   * the dialog is centred in it and fits inside it
#   * both still hold when the design canvas changes size, so nothing about the
#     layout is a baked offset
#
# Sizes are measured against the canvas, not the window: the project stretches
# in `canvas_items` mode, so the GUI lives at the design resolution whatever the
# window is doing.
#   * opening it frees the mouse and takes the keys away from the game

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.push_back(message)


func _run() -> void:
	var world = load("res://main.tscn").instantiate()
	root.add_child(world)
	await process_frame

	for size in [Vector2i(1280, 720), Vector2i(800, 600)]:
		root.content_scale_size = size
		world.set_network_panel_open(true)
		# Containers settle over a couple of frames, so measure after they have.
		for _f in 4:
			await process_frame

		var panel: Control = world._net_panel
		var view := root.get_visible_rect().size
		var dialog: Control = null
		var dim: Control = null
		for child in panel.get_children():
			if child is CenterContainer:
				dialog = (child as Control).get_child(0)
			elif child is ColorRect:
				dim = child
		if dialog == null or dim == null:
			_check(false, "the panel is missing its dialog or its backdrop")
			break

		var centre := dialog.global_position + dialog.size * 0.5
		print("at %.0v: root %.0v, backdrop %.0v, dialog %.0v at %.0v, centre %.0v" % [
			view, panel.size, dim.size, dialog.size, dialog.global_position, centre])
		_check(panel.size == view,
			"the panel root is %.0v on a %.0v canvas" % [panel.size, view])
		_check(dim.size == view,
			"the backdrop is %.0v on a %.0v canvas, so it does not cover the game" % [
				dim.size, view])
		_check(dialog.size.x > 200.0 and dialog.size.y > 100.0,
			"the dialog collapsed to %.0v" % dialog.size)
		_check(centre.distance_to(view * 0.5) < 1.0,
			"the dialog's centre is %.0v, not the middle of the screen %.0v" % [
				centre, view * 0.5])
		_check(dialog.global_position.x >= 0.0 and dialog.global_position.y >= 0.0
				and dialog.global_position.x + dialog.size.x <= view.x
				and dialog.global_position.y + dialog.size.y <= view.y,
			"the dialog runs off the canvas: %.0v at %.0v in %.0v" % [
				dialog.size, dialog.global_position, view])
		_check(panel.visible, "the panel is not visible after being opened")
		_check(not world._input_enabled, "the game still takes keys while the panel is open")

		world.set_network_panel_open(false)
		await process_frame
		_check(not panel.visible, "the panel stayed up after being closed")
		_check(world._input_enabled, "the game did not take its keys back")

	if failures.is_empty():
		print("MAYO_PANEL_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
