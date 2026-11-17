extends RefCounted
const UI := preload("res://scripts/sauce_ui.gd")
const CATEGORIES := [["kills", "전체 처치"], ["specials", "특수 적 처치"],
	["chain_kills", "폭발 연쇄 처치"], ["rescues", "동료 구조"],
	["damage", "적에게 준 피해"], ["damage_taken", "받은 피해"], ["downs", "쓰러진 횟수"]]

static func build(parent: VBoxContainer, report: Dictionary) -> void:
	if report.is_empty():
		return
	var clock := Label.new()
	var seconds := int(report.get("seconds", 0))
	clock.text = "임무 기록 · %02d:%02d" % [int(seconds / 60), seconds % 60]
	parent.add_child(clock)
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(540, 240)
	parent.add_child(tabs)
	var players: Array = report.get("players", [])
	for category in CATEGORIES:
		var column := VBoxContainer.new()
		column.name = category[1]
		tabs.add_child(column)
		var sorted := players.duplicate(true)
		var key: String = category[0]
		sorted.sort_custom(func(a, b): return float(a.get(key, 0)) > float(b.get(key, 0)))
		var maximum := 1.0
		for row in sorted:
			maximum = maxf(maximum, float(row.get(key, 0)))
		for row in sorted:
			var line := HBoxContainer.new()
			column.add_child(line)
			var label := Label.new()
			label.text = "플레이어 %d" % (int(row.get("seat", 0)) + 1)
			label.custom_minimum_size.x = 110
			line.add_child(label)
			var bar := ProgressBar.new()
			bar.max_value = maximum
			bar.value = float(row.get(key, 0))
			bar.show_percentage = false
			bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bar.custom_minimum_size.y = 24
			line.add_child(bar)
			var value := Label.new()
			value.text = str(roundi(float(row.get(key, 0))))
			value.custom_minimum_size.x = 64
			value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			line.add_child(value)
