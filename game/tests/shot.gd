extends SceneTree

# 布局截图工具：进入人类选骰阶段后截两张（常规 / 曜彩弹窗）
# godot --path . -s res://tests/shot.gd

func _init() -> void:
	# 输出目录 = 工程根上一级的 _frames/（随工程位置推导，勿写死盘符路径；
	# 目录被清理时自动重建，避免截图散落/失败）
	var frames_dir: String = ProjectSettings.globalize_path("res://").path_join("..").simplify_path() + "/_frames/"
	DirAccess.make_dir_recursive_absolute(frames_dir)
	var sel: Node = load("res://scenes/select.tscn").instantiate()
	root.add_child(sel)
	for i in range(30):
		await process_frame
	root.get_texture().get_image().save_png(frames_dir + "shot_selectscene.png")
	root.remove_child(sel)
	sel.free()
	var ui: Node = load("res://scenes/battle.tscn").instantiate()
	root.add_child(ui)
	for i in range(30):
		await process_frame
	for i in range(6000):
		await process_frame
		if ui._human_active:
			break
	for i in range(10):
		await process_frame
	root.get_texture().get_image().save_png(frames_dir + "shot_select.png")
	ui._on_yc()
	for i in range(10):
		await process_frame
	root.get_texture().get_image().save_png(frames_dir + "shot_yc.png")
	ui._on_yc_close()
	ui.glossary.open("骇入")
	for i in range(10):
		await process_frame
	root.get_texture().get_image().save_png(frames_dir + "shot_glossary.png")
	ui.glossary.visible = false
	ui.hp_hist = [[28, 22, 15, 8, 0], [25, 25, 12, 6, 3]]
	ui.battle.stats[0].dmg_dealt = 37
	ui.battle.stats[1].dmg_dealt = 28
	ui.battle.stats[0].fx = {"combo": 2, "pierce": 1, "yaocai": 1, "reroll": 3}
	ui.battle.stats[1].fx = {"thorns": 2, "hack": 1}
	ui.battle.winner = 0
	ui._show_summary()
	for i in range(10):
		await process_frame
	root.get_texture().get_image().save_png(frames_dir + "shot_summary.png")
	quit(0)
