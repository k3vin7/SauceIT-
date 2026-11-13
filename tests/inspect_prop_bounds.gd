extends SceneTree
func _initialize() -> void:
	var kit := TomatinaVillageArt.new()
	kit.load_kit()
	for key in ["TomatoCrate", "TomatoCrateRefuge", "TomatoCrateWreck", "TomatoCrateStack", "CrushedTomatoes", "MarketBarrels"]:
		print(key, " ", kit._meshes[key].get_aabb())
	quit()
