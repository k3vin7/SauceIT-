extends SceneTree
var scene
func _initialize():
	MayoTutorial.disabled = true
	call_deferred("run")
func run():
	root.size = Vector2i(1000, 1400)
	scene = load("res://stage_2_tomatina.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	root.content_scale_size = Vector2i(1000,1400)
	root.size = Vector2i(1000,1400)
	for layer in scene.find_children("*", "CanvasLayer", true, false):
		layer.hide()
	scene.set_physics_process(false)
	for n in scene.find_children("*", "Node", true, false):
		n.set_physics_process(false)
	var cam = Camera3D.new()
	scene.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 87.0 * StreetMap.CELL
	cam.far = 3000
	var centre = TomatinaMap.at_cell(Vector2(29.5,56))
	cam.position = centre + Vector3(0,600,0)
	cam.look_at(centre, Vector3(0,0,-1))
	cam.current = true
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/tomatina_map_current.png")
	var overlay = Control.new()
	root.add_child(overlay)
	for entry in TomatinaMap.roster():
		var kind = str(entry[0])
		var pos = cam.unproject_position(TomatinaMap.at_cell(entry[1]))
		var dot = ColorRect.new()
		dot.size = Vector2(10,10) if kind == "TOMATO_GRUNT" else Vector2(20,20)
		dot.position = pos - dot.size/2
		var colors = {"TOMATO_GRUNT": Color("ff6868"), "TOMATO_BRUTE": Color("ffb52e"), "BOWLING_TOMATO": Color("66caff"), "KETCHUP_SPITTER": Color("ff68ee"), "CAPRESE_CRAWLER": Color("83ff98")}
		dot.color = colors.get(kind,Color.WHITE)
		overlay.add_child(dot)
		if kind != "TOMATO_GRUNT":
			var label = Label.new()
			label.text = kind.replace("TOMATO_", "").replace("KETCHUP_", "").replace("CAPRESE_", "")
			label.position = pos + Vector2(13,-12)
			label.add_theme_font_size_override("font_size", 17)
			label.add_theme_color_override("font_outline_color", Color.BLACK)
			label.add_theme_constant_override("outline_size", 6)
			overlay.add_child(label)
	var title = Label.new()
	title.text = "LA TOMATINA | INITIAL ENEMY POSITIONS\nRed: Grunt (88)   Orange: Brute (3)   Blue: Bowler (2)\nPink: Spitter (3)   Green: Crawler (2)\nPlaza trigger: additional horde (base 64, player-scaled)"
	title.position = Vector2(25,20)
	title.add_theme_font_size_override("font_size",22)
	title.add_theme_color_override("font_outline_color",Color.BLACK)
	title.add_theme_constant_override("outline_size",8)
	overlay.add_child(title)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/tomatina_enemy_layout_current.png")
	quit()

