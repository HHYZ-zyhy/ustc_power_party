extends SceneTree

# 布局截图工具：依次截取选卡 / 战斗 / 曜彩弹窗 / 效果显示 / 战绩页五张
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
	sel._on_char("physics")   # 展示「选中角色 → 自动选推荐曜彩」的界面状态
	for i in range(5):
		await process_frame
	root.get_texture().get_image().save_png(frames_dir + "shot_selectscene.png")
	root.remove_child(sel)
	sel.free()
	GameStateData.char_id = "physics"
	GameStateData.yc_name = "网络渗透"
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
	# 战绩页必须来自真实对局：自动替人类打完（含曜彩/重投），沿用 _run 的汇总逻辑，
	# 不再手工摆 stats/winner（旧截图因此显示「总回合数 0」、承受伤害 0）
	await _play_to_summary(ui)
	for i in range(10):
		await process_frame
	root.get_texture().get_image().save_png(frames_dir + "shot_summary.png")
	quit(0)

# 快进完整对局到战绩页：time_scale 只加速演出/等待，规则与真实对局一致
func _play_to_summary(ui: Node) -> void:
	Engine.time_scale = 10.0
	var frame := 0
	while not ui.summary_view.visible and frame < 60000:
		await process_frame
		frame += 1
		if ui.battle.winner >= 0 or not ui._human_active:
			continue
		if ui._phase != "" and not ui.battle.players[0].yc_rolled \
				and ui.battle.yaocai_usable(0, ui._phase) and frame % 5 == 2:
			ui._on_yc()
			ui._on_yc_use()
		elif ui._phase == "attack" and ui.battle.rerolls_left(0) > 0 \
				and frame % 5 == 0 and ui._sel.is_empty():
			ui._sel.append(ui.battle.players[0].dice[0])
			ui._on_reroll()
		else:
			ui._sel.clear()
			var dice: Array = ui.battle.players[0].dice
			if ui._need > 0:
				for i in range(mini(ui._need, dice.size())):
					ui._sel.append(dice[i])
			else:
				ui._sel.append(dice[0])
			ui._on_confirm()
	Engine.time_scale = 1.0
