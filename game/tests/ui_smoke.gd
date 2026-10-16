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
	print("UI SMOKE OK")
	quit(0)
