extends SceneTree

# UI 冒烟测试：无头实例化选卡与战斗场景，跑若干帧抓初始化错误
# godot --headless -s res://tests/ui_smoke.gd

func _init() -> void:
	var s1: Node = load("res://scenes/select.tscn").instantiate()
	root.add_child(s1)
	for i in range(30):
		await process_frame
	# 初始状态：不选中角色/曜彩，开始按钮与曜彩按钮均禁用
	assert(s1._sel_char == "")
	assert(s1._sel_yc == "")
	assert(s1.start_btn.disabled)
	assert(s1._yc_btns["理实积淀"].disabled)
	# 选中角色：自动选推荐曜彩，星标 + 信息栏推荐行，开始按钮可用
	s1._on_char("physics")
	assert(s1._sel_yc == "网络渗透")
	assert(not s1.start_btn.disabled)
	var reco: String = GameData.CHARACTERS[s1._sel_char].yc_reco
	assert(reco != "" and s1._yc_btns[reco].text.begins_with("★"))
	assert(s1.info_label.text.contains("推荐曜彩骰"))
	# 手动改选后重复点击同一角色，不重置手动选择
	s1._on_yc("东风导弹")
	s1._on_char("physics")
	assert(s1._sel_yc == "东风导弹")
	# 化学无曜彩：清空曜彩但仍可开始
	s1._on_char("chem")
	assert(s1._sel_yc == "")
	assert(s1.info_label.text.contains("本院系无曜彩骰"))
	assert(not s1.start_btn.disabled)
	# 上一局返回：保留上次角色与手动改选的曜彩（不强制回到推荐）
	GameStateData.char_id = "math"
	GameStateData.yc_name = "网络渗透"
	var s3: Node = load("res://scenes/select.tscn").instantiate()
	root.add_child(s3)
	for i in range(10):
		await process_frame
	assert(s3._sel_char == "math")
	assert(s3._sel_yc == "网络渗透")
	assert(s3._yc_btns["重复试验"].text.begins_with("★"))
	assert(s3.info_label.text.contains("推荐曜彩骰"))
	root.remove_child(s3)
	s3.free()
	# 战斗场景用明确组合（正常流程由 select_ui._on_start 写入 GameStateData）
	GameStateData.char_id = "physics"
	GameStateData.yc_name = "网络渗透"
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
	# 曜彩六面表：每面卡片要有最小宽度（防止再被 GridContainer 挤成一字一列）
	var cell: Control = s2._make_face_cell(GameData.YAOCAI["网络渗透"].faces[0])
	assert(cell.custom_minimum_size.x >= 150)
	cell.free()
	# 3D 投骰：每种骰型的面数与刻字数量必须一致（d4/d6/d8/d12；曜彩骰 6 面）
	for sides in [4, 6, 8, 12]:
		var d := Die.new()
		d.sides = sides
		d.value = 1
		var spec: Dictionary = s2.roller._faces_for(d)
		assert(spec.faces.size() == sides)
		var nums := {}
		for f in spec.faces:
			nums[int(f.label)] = true
		assert(nums.size() == sides)
	var yd := Die.new()
	yd.yaocai = "网络渗透"
	yd.face = 0
	assert(s2.roller._faces_for(yd).faces.size() == 6)
	# HP 进度条：与双方血量/上限同步
	assert(s2.enemy_hp_bar.max_value == s2.battle.players[1].hp_max)
	assert(s2.enemy_hp_bar.value == s2.battle.players[1].hp)
	assert(s2.player_hp_bar.max_value == s2.battle.players[0].hp_max)
	assert(s2.player_hp_bar.value == s2.battle.players[0].hp)
	# 预期效果：多来源连击显示为「连击×2」（物理学院 2 组对子被动 + 重复试验面 4+连击）
	s2._phase = "attack"
	var cy := Die.new()
	cy.yaocai = "重复试验"
	cy.face = 4
	cy.value = 4
	for i in range(4):
		s2.battle.players[0].dice[i].value = 2 if i < 2 else 3
	s2._sel = [s2.battle.players[0].dice[0], s2.battle.players[0].dice[1],
		s2.battle.players[0].dice[2], s2.battle.players[0].dice[3], cy]
	s2._refresh_preview()
	assert(s2.info_label.text.contains("连击"))
	assert(s2.info_label.text.contains("×2"))
	# 结算横幅注记：结算中（荆棘/中毒等）分出胜负不能误标「力场挡下」；多段连击显示段数
	var no_hit := {"dmg": 0, "dmg2": 0, "counter": 0, "combo_n": 0, "pierce": false}
	assert(s2._settle_notes(false, false, true, no_hit, 5)[0].contains("主伤害未造成"))
	assert(s2._settle_notes(false, false, false, no_hit, 5)[0] == "力场挡下")
	assert(s2._settle_notes(false, true, false, no_hit, 5)[0].contains("伤害不再结算"))
	var combo_hit := {"dmg": 4, "dmg2": 8, "counter": 0, "combo_n": 2, "pierce": false}
	assert(s2._settle_notes(false, false, false, combo_hit, 0).has("连击 8（2 段）"))
	# 命定曜彩骰无法手动取消选中（重投时也必然一起重投，核心层由 do_reroll 兜底）
	var md := Die.new()
	md.yaocai = "命运签约"
	md.face = 0
	md.value = 1
	assert(s2._is_mingding(md))
	s2._human_active = true
	s2._sel = [md]
	s2._on_die(md)
	assert(s2._sel.has(md))
	s2._human_active = false
	# 窄窗口自适应：600px 宽视口下曜彩弹窗/效果显示/战绩面板都不出屏
	s2._fit_yc_popup(Vector2(600, 1080))
	assert(600.0 + s2.yc_popup.offset_left >= 0.0)
	assert(600.0 + s2.yc_popup.offset_right <= 600.0)
	s2._fit_sum_panel(Vector2(600, 1080))
	assert(300.0 + s2.sum_panel.offset_left >= 0.0)
	assert(300.0 + s2.sum_panel.offset_right <= 600.0)
	s2.glossary._fit_to_viewport(Vector2(600, 1080))
	assert(300.0 + s2.glossary.offset_left >= 0.0)
	assert(300.0 + s2.glossary.offset_right <= 600.0)
	# 战绩统计里的效果名必须全中文：遍历角色被动与曜彩面实际用到的所有 op
	for c in GameData.CHARACTERS.values():
		for pas in c.passives:
			for fx in pas.fx:
				assert(s2._fx_name(fx.op) != fx.op)
	for y in GameData.YAOCAI.values():
		for f in y.faces:
			for fx in f.fx:
				assert(s2._fx_name(fx.op) != fx.op)
	assert(s2._fx_name("atk_add") == "攻击值加成")
	assert(s2._fx_name("mingding") == "命定")
	print("UI SMOKE OK")
	quit(0)
