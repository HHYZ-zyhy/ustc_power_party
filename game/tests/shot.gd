extends SceneTree

# 布局截图工具：依次截取选卡 / 战斗 / 选中骰 / 曜彩弹窗 / 效果显示 / 战绩页六张
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
	# 等人类首个可操作阶段（进攻或防御）直接截图；若本局在人类操作前就结束，换一局。
	# 旧实现会替人类确认防御再等进攻，偶尔在首回合被击倒后截到终局态。
	var ui: Node = null
	for attempt in range(4):
		var cand: Node = load("res://scenes/battle.tscn").instantiate()
		root.add_child(cand)
		for i in range(30):
			await process_frame
		await _wait_human_phase(cand)
		if cand.battle.winner < 0 and cand._human_active:
			ui = cand
			break
		await _wait_summary(cand)   # 让协程停在战绩页再释放，避免 await 中途 free
		root.remove_child(cand)
		cand.free()
	if ui == null:
		push_error("shot: 4 次尝试均未取得人类可操作阶段")
		quit(1)
		return
	for i in range(10):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(frames_dir + "shot_select.png")
	# 选中两颗骰：展示 3D 骰的金色描边（不重建 SubViewport）
	ui._sel.clear()
	var pick: Array = ui.battle.players[0].dice
	for i in range(mini(2, pick.size())):
		ui._sel.append(pick[i])
	ui.refresh()
	for i in range(10):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(frames_dir + "shot_dice_selected.png")
	ui._sel.clear()
	ui.refresh()
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
	var reached: bool = await _play_to_summary(ui)
	if not reached:
		push_error("shot: 对局在 60000 帧内未到达战绩页，终止截图")
		quit(1)
		return
	for i in range(10):
		await process_frame
	root.get_texture().get_image().save_png(frames_dir + "shot_summary.png")
	quit(0)

# 等到人类首个可操作阶段（进攻或防御）；不替人类确认，保留真实可操作界面用于截图
func _wait_human_phase(ui: Node) -> void:
	Engine.time_scale = 10.0
	var frame := 0
	while frame < 12000 and not ui.summary_view.visible:
		await process_frame
		frame += 1
		if ui.battle.winner >= 0 or ui._human_active:
			break
	Engine.time_scale = 1.0

func _wait_summary(ui: Node) -> void:
	Engine.time_scale = 10.0
	var frame := 0
	while frame < 60000 and not ui.summary_view.visible:
		await process_frame
		frame += 1
	Engine.time_scale = 1.0

# 快进完整对局到战绩页：time_scale 只加速演出/等待，规则与真实对局一致
func _play_to_summary(ui: Node) -> bool:
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
			_fill_and_confirm(ui)
	Engine.time_scale = 1.0
	return ui.summary_view.visible

# 截图工具用：按当前需选数选满前 N 颗并确认（不绕过规则校验）
func _fill_and_confirm(ui: Node) -> void:
	ui._sel.clear()
	var dice: Array = ui.battle.players[0].dice
	if ui._need > 0:
		for i in range(mini(ui._need, dice.size())):
			ui._sel.append(dice[i])
	elif dice.size() > 0:
		ui._sel.append(dice[0])
	ui._on_confirm()
