extends SceneTree

# UI 冒烟测试：无头实例化选卡与战斗场景，跑若干帧抓初始化错误
# godot --headless -s res://tests/ui_smoke.gd

func _init() -> void:
	var s1: Node = load("res://scenes/select.tscn").instantiate()
	root.add_child(s1)
	var s2: Node = load("res://scenes/battle.tscn").instantiate()
	root.add_child(s2)
	for i in range(30):
		await process_frame
	# 效果显示：全部关键词都要列出，且打开时高亮到点击的那条
	s2.glossary.open("命定")
	for i in range(5):
		await process_frame
	assert(s2.glossary._rows.size() == GameData.KEYWORDS.size())
	assert(s2.glossary._current == "命定")
	# 列表行点击切换高亮（gui_input 已接线）
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	s2.glossary._rows["洞穿"].gui_input.emit(ev)
	assert(s2.glossary._current == "洞穿")
	print("UI SMOKE OK")
	quit(0)
