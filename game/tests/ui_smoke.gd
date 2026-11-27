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
		var spec: Dictionary = DieVisuals._faces_for(d)
		assert(spec.faces.size() == sides)
		var nums := {}
		for f in spec.faces:
			nums[int(f.label)] = true
		assert(nums.size() == sides)
		# 官方 BoxMesh 只用于立方（d6/曜彩）；其余为精确正多面体网格
		var mesh: Mesh = DieVisuals._mesh_for(d, spec)
		assert((mesh is BoxMesh) == (sides == 6))
		# 骰子本体必须完全不透明
		assert(DieVisuals._material_for(d, spec).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED)
		# 数字贴面：只在面外侧 0.0015，且不穿透/不双面
		var lab: Label3D = DieVisuals._label_for(spec.faces[0], Color.WHITE)
		assert(lab.transform.origin.distance_to(spec.faces[0].center) < 0.01)
		assert(not lab.no_depth_test and not lab.double_sided)
		lab.free()
		# 停骰姿态：非 d4 的结果面朝上；d4 有一个面着地且结果面朝镜头
		var rest: Basis = DieVisuals._rest_rotation(d, spec.faces, 0)
		var up: Vector3 = rest * (spec.faces[0].normal as Vector3)
		if sides == 4:
			assert(absf(up.y - 1.0 / 3.0) < 0.01 and up.z > 0.0)
			var down_ok := false
			for f in spec.faces:
				if (rest * (f.normal as Vector3)).is_equal_approx(Vector3.DOWN):
					down_ok = true
			assert(down_ok)
			# 正四面体结果面倾斜时，刻字仍必须尽量竖直（否则 1 会歪成 7）
			for fi in range(spec.faces.size()):
				var rr: Basis = DieVisuals._rest_rotation(d, spec.faces, fi)
				var d4_lab: Label3D = DieVisuals._label_for(spec.faces[fi], Color.WHITE)
				assert((rr * d4_lab.transform.basis.y).dot(Vector3.UP) > 0.9)
				d4_lab.free()
		else:
			assert(up.y > 0.999 and absf(up.x) < 0.01 and absf(up.z) < 0.01)
		# 静态选骰视图：结果面朝镜头，再绕屏幕水平轴轻微上仰（参考原作截图）
		var disp: Basis = DieVisuals.display_rotation(spec.faces, 0, DieView.CAM_NORMAL)
		var to_cam: Vector3 = (disp * (spec.faces[0].normal as Vector3)).normalized()
		assert(to_cam.dot(DieView.CAM_NORMAL.normalized()) > 0.8)
		# 倾角按骰型区分：d8 压到接近正视玩家，d6 略减，d4/d12 保持原样
		var face_on: float = to_cam.dot(DieView.CAM_NORMAL.normalized())
		if sides == 8:
			assert(face_on > 0.985)
		elif sides == 6:
			assert(face_on > 0.96)
		elif sides == 4:
			assert(face_on < 0.90)
		else:
			assert(face_on > 0.94)
	var yd := Die.new()
	yd.yaocai = "网络渗透"
	yd.face = 0
	var yspec: Dictionary = DieVisuals._faces_for(yd)
	assert(yspec.faces.size() == 6)
	assert(DieVisuals._mesh_for(yd, yspec) is BoxMesh)
	assert(DieVisuals._material_for(yd, yspec).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED)
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
	# 多来源连击在 _active_fx 里按来源计数（3 个来源 -> 3），预览再格式化为「连击×N」
	var combo_player := {"cfg": {"name": "t", "intro": "", "atk": 1, "def": 1, "hp": 1,
		"passives": [
			{"t": "attack", "c": {"t": "always"}, "fx": [{"op": "combo"}]},
			{"t": "attack", "c": {"t": "always"}, "fx": [{"op": "combo"}]},
			{"t": "attack", "c": {"t": "always"}, "fx": [{"op": "combo"}]},
		]}, "dice": [], "strength": []}
	var combo_counts: Dictionary = s2._active_fx(combo_player, [])
	assert(int(combo_counts.get("连击", 0)) == 3)
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
	# 候选骰 3D 化：DiceRow 是池化的 DieView，点骰子切换 _sel，提示在骰子下方
	s2._human_active = true
	s2._phase = "attack"
	s2._need = s2.battle.selection_count(0, "attack")
	s2._sel.clear()
	s2.refresh()
	for i in range(10):
		await process_frame
	var my_dice: Array = s2.battle.players[0].dice
	assert(s2.dice_row.get_child_count() == my_dice.size())
	for c in s2.dice_row.get_children():
		assert(c is DieView)
		var dv: DieView = c
		assert(dv.get_sub_viewport().size == Vector2i(DieView.DIE_SIZE))
		assert(dv.get_sub_viewport().own_world_3d)
		assert(dv.get_child(1) == dv.get_hint_label())
		assert(dv.get_die_button().custom_minimum_size == DieView.DIE_SIZE)
		assert(dv.get_hint_label().custom_minimum_size.y == DieView.HINT_HEIGHT)
	assert(s2.dice_tip.text.contains("点击骰子"))
	assert(s2.btn_confirm.disabled)   # 未选够，确认按钮置灰
	var first_view: DieView = s2.dice_row.get_child(0)
	var first_die: Die = first_view.get_die()
	var first_id: int = first_view.get_instance_id()
	# 骰体背面剔除 + 不透明；选中描边是 CULL_FRONT 不透明反壳（依赖网格顺时针绕序）
	assert(first_view._mesh.material_override.cull_mode == BaseMaterial3D.CULL_BACK)
	assert(first_view._sel_shell.material_override.cull_mode == BaseMaterial3D.CULL_FRONT)
	assert(first_view._sel_shell.material_override.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED)
	assert(first_view.is_interactive())
	first_view.activate()
	assert(s2._sel.has(first_die))
	first_view.activate()
	assert(not s2._sel.has(first_die))
	# 非人类阶段只压暗颜色，不得把骰子调成半透明
	first_view.set_dimmed(true)
	assert(first_view.modulate.a == 1.0)
	first_view.set_dimmed(false)
	s2.refresh()
	assert(s2.dice_row.get_child(0).get_instance_id() == first_id)
	# 逐骰提示：物理学院 2 组对子，普通骰只列「可能出现的效果」（不再标面数），
	# 未选中为浅色（不含金色）；选满触发后同一提示加深为金色
	var sides_txt := GameData.SIDES_TEXT
	for i in range(4):
		my_dice[i].value = 2 if i < 2 else 3
	s2._need = 4
	s2._sel.clear()
	s2.refresh()
	var hint_ok := false
	var lit_hex: String = s2.HINT_FX_LIT.to_html(false)
	for c in s2.dice_row.get_children():
		var dv: DieView = c
		var txt: String = dv.get_hint_label().text
		assert(not txt.contains(sides_txt.get(dv.get_die().sides, "面")))
		if txt.contains("连击"):
			hint_ok = true
			assert(not txt.contains(lit_hex))
	assert(hint_ok)
	# 选够后确认按钮启用，提示行同步显示需选数量；2 组对子生效，已选骰提示加深
	s2._sel.clear()
	for i in range(mini(s2._need, my_dice.size())):
		s2._sel.append(my_dice[i])
	s2.refresh()
	assert(s2._sel.size() == s2._need and not s2.btn_confirm.disabled)
	assert(s2.dice_tip.text.contains("需选 %d 颗" % s2._need))
	for c in s2.dice_row.get_children():
		var dv2: DieView = c
		if s2._sel.has(dv2.get_die()):
			assert(dv2.get_hint_label().text.contains(lit_hex))
	# 骰下提示按用户 2026-11-27 逐角色验收：
	# 1) 网安 sum_ge、工程 round_end 不逐骰标注
	s2._phase = "attack"
	var cp := {"cfg": GameData.CHARACTERS["cyber"], "dice": [], "strength": [], "hp": 25, "hp_max": 25}
	for v in [1, 1, 10, 10, 10]:
		var cd := Die.new()
		cd.sides = 6
		cd.value = v
		cp.dice.append(cd)
	assert(s2._die_fx_hints(cp, 3).is_empty())
	var eng_p := {"cfg": GameData.CHARACTERS["engineering"], "dice": [], "strength": [], "hp": 30, "hp_max": 30}
	for v in [3, 3, 5, 6, 4]:
		var ed := Die.new()
		ed.sides = 6
		ed.value = v
		eng_p.dice.append(ed)
	assert(s2._die_fx_hints(eng_p, 3).is_empty())
	# 2) 化学：全偶数须选满 4 颗才加深，选两颗偶数不提前变金
	var chem_p := {"cfg": GameData.CHARACTERS["chem"], "dice": [], "strength": [], "hp": 30, "hp_max": 30}
	for v in [2, 4, 6, 4, 8]:
		var chd := Die.new()
		chd.sides = 6
		chd.value = v
		chem_p.dice.append(chd)
	s2._need = 4
	s2._sel = [chem_p.dice[0], chem_p.dice[1]]
	assert(s2._die_lit_fx(chem_p, chem_p.dice[0], s2._sel).is_empty())
	s2._sel = [chem_p.dice[0], chem_p.dice[1], chem_p.dice[2], chem_p.dice[3]]
	assert(s2._die_lit_fx(chem_p, chem_p.dice[0], s2._sel).has("升级所选骰"))
	# 3) 信息：只在有同点数的骰下标注；选中对子即加深，非对子骰不变金
	var info_p := {"cfg": GameData.CHARACTERS["info"], "dice": [], "strength": [], "hp": 22, "hp_max": 22}
	for v in [3, 3, 5, 6, 4]:
		var id := Die.new()
		id.sides = 6
		id.value = v
		info_p.dice.append(id)
	s2._need = 4
	var info_hints: Dictionary = s2._die_fx_hints(info_p, 4)
	assert(info_hints.has(info_p.dice[0]) and info_hints.has(info_p.dice[1]))
	assert(not info_hints.has(info_p.dice[2]))   # 5 没有同点数伙伴，不标注
	s2._sel = [info_p.dice[0], info_p.dice[1]]
	assert(s2._die_lit_fx(info_p, info_p.dice[0], s2._sel).has("骇入"))
	s2._sel = [info_p.dice[0], info_p.dice[1], info_p.dice[2], info_p.dice[3]]
	assert(s2._die_lit_fx(info_p, info_p.dice[2], s2._sel).is_empty())
	# 4) 核科学：只在能凑对的骰下标注；选中对子即金，且非对子骰不变金
	var nuc_p := {"cfg": GameData.CHARACTERS["nuclear"], "dice": [], "strength": [], "hp": 25, "hp_max": 25}
	for v in [3, 3, 5, 6, 4]:
		var nd := Die.new()
		nd.sides = 6
		nd.value = v
		nuc_p.dice.append(nd)
	s2._need = 4
	var nuc_hints: Dictionary = s2._die_fx_hints(nuc_p, 4)
	assert(nuc_hints.has(nuc_p.dice[0]) and not nuc_hints.has(nuc_p.dice[2]))
	s2._sel = [nuc_p.dice[0], nuc_p.dice[1]]
	assert(s2._die_lit_fx(nuc_p, nuc_p.dice[0], s2._sel).has("每对瞬伤3"))
	s2._sel = [nuc_p.dice[0], nuc_p.dice[1], nuc_p.dice[2], nuc_p.dice[3]]
	assert(s2._die_lit_fx(nuc_p, nuc_p.dice[0], s2._sel).has("每对瞬伤3"))
	assert(s2._die_lit_fx(nuc_p, nuc_p.dice[2], s2._sel).is_empty())
	# 5) 生命：不屈触发过一次后不再显示提示
	var life_p := {"cfg": GameData.CHARACTERS["life"], "dice": [], "strength": [], "hp": 20, "hp_max": 20, "unyielding_used": false}
	for v in [6, 6, 8, 6, 6]:
		var ld := Die.new()
		ld.sides = 6
		ld.value = v
		life_p.dice.append(ld)
	s2._phase = "defense"
	s2._need = 2
	assert(not s2._die_fx_hints(life_p, 2).is_empty())
	life_p.unyielding_used = true
	assert(s2._die_fx_hints(life_p, 2).is_empty())
	# 6) 地球：只标注「全为6 → 力量×100% + 治愈」，不标注 50% 力量
	s2._phase = "attack"
	var earth_p := {"cfg": GameData.CHARACTERS["earth"], "dice": [], "strength": [], "hp": 28, "hp_max": 28}
	for v in [6, 6, 8, 6, 6]:
		var ead := Die.new()
		ead.sides = 6
		ead.value = v
		earth_p.dice.append(ead)
	var earth_hints: Dictionary = s2._die_fx_hints(earth_p, 2)
	assert(earth_hints.has(earth_p.dice[0]))
	assert(not earth_hints.has(earth_p.dice[2]))   # 8 不参与「全为6」
	var earth_txt: String = "、".join(earth_hints[earth_p.dice[0]])
	assert(earth_txt.contains("治愈") and not earth_txt.contains("50%"))
	# 释放假玩家占位，恢复真实选骰状态
	s2._need = 4
	s2._sel = []
	# 命定骰的 DieView 必须锁定，点击不能取消
	var md2 := Die.new()
	md2.yaocai = "命运签约"
	md2.face = 0
	md2.value = 1
	s2.battle.players[0].dice.append(md2)
	s2._human_active = true
	s2.refresh()
	var mv: DieView = s2._die_views[md2]
	assert(mv.is_locked())
	assert(not mv.is_interactive())
	assert(s2._sel.has(md2))
	mv.activate()
	assert(s2._sel.has(md2))
	s2.battle.players[0].dice.erase(md2)
	s2._sel.erase(md2)
	s2.refresh()
	# 敌方骰块：黑色信息条框外、名字正下方的玩家候选行缩小版（96×132，带提示、不可点击）
	var en: Dictionary = s2.battle.players[1]
	for i in range(en.dice.size()):
		en.dice[i].value = i + 1
	s2._en_rolled = true
	s2._en_committed = false
	s2.refresh()
	var enemy_views := 0
	for c in s2.enemy_dice.get_children():
		if c is DieView:
			enemy_views += 1
			assert(c.get_sub_viewport().size == Vector2i(DieView.ENEMY_DIE_SIZE))
			assert(c.get_hint_label().visible)
			assert(c.get_hint_label().custom_minimum_size.y == DieView.ENEMY_HINT_HEIGHT)
			assert(not c.is_interactive())
	assert(enemy_views == en.dice.size())
	s2._en_committed = true
	en.sel = [en.dice[0], en.dice[1]]
	s2.refresh()
	# 页面中心选骰合计：玩家阶段按 _sel 实时求和；敌方提交后显示其选骰合计
	assert(s2.sel_sum.visible)
	assert(s2.sel_sum_value.text == str(Battle.dice_sum(s2._sel)))
	assert(s2.sel_sum_title.text == "我方选骰合计")
	s2._enemy_sum_shown = true
	s2._human_active = false
	s2.refresh()
	assert(s2.sel_sum.visible)
	assert(s2.sel_sum_value.text == str(Battle.dice_sum(en.sel)))
	assert(s2.sel_sum_title.text == "敌方选骰合计")
	# 中心圆环位于页面中心附近、在骰行提示之上，不压候选骰区
	# （按 1080 设计高度校验：纵向锚点 0.5 + offset 90 = 630 < DiceTip 664）
	assert(absf((s2.sel_sum.offset_top + s2.sel_sum.offset_bottom) * 0.5) <= 120.0)
	assert(540.0 + s2.sel_sum.offset_bottom <= s2.dice_tip.offset_top)
	# 非选骰阶段隐藏
	s2._enemy_sum_shown = false
	s2.refresh()
	assert(not s2.sel_sum.visible)
	s2._human_active = true
	s2.refresh()
	var visible_views := 0
	for c in s2.enemy_dice.get_children():
		if c is DieView and c.visible:
			visible_views += 1
	assert(visible_views == 2)
	assert(s2.enemy_dice_total.visible and s2.enemy_dice_total.text.begins_with("总计"))
	assert(s2.enemy_dice_label.text == "敌方所选")
	# 布局：玩家骰行 720–870 不压 LogLine 872；敌方骰块在信息条框外、名字正下方且不压结算区
	for i in range(10):
		await process_frame
	assert(s2.dice_row.offset_top == 720.0 and s2.dice_row.offset_bottom == 870.0)
	assert(s2.dice_row.offset_bottom <= s2.log_line.offset_top)
	assert(s2.log_line.offset_bottom <= s2.player_bar.offset_top)
	assert(s2.dice_tip.offset_bottom <= s2.dice_row.offset_top)
	assert(not s2.enemy_bar.is_ancestor_of(s2.enemy_dice))
	assert(s2.enemy_dice_block.offset_top >= s2.enemy_bar.offset_bottom)
	assert(is_equal_approx(s2.enemy_dice_block.offset_left, s2.enemy_bar.offset_left + 20.0))
	assert(s2.enemy_dice is GridContainer)
	assert(s2.enemy_dice.columns == 5)
	assert(s2.enemy_dice_label.get_parent() == s2.enemy_dice_head)
	assert(s2.enemy_dice_total.get_parent() == s2.enemy_dice_head)
	assert(s2.enemy_dice_label.get_index() < s2.enemy_dice_total.get_index())
	assert(s2.enemy_dice_block.offset_right <= 900.0)
	assert(s2.enemy_dice_block.offset_bottom <= s2.dice_row.offset_top)
	assert(s2.enemy_bar.offset_bottom <= s2.banner.offset_top)
	assert(s2.enemy_dice.get_combined_minimum_size().x <= 680.0)
	# 敌方信息条只放名字/被动/状态：最长被动 + 状态行不得把内容顶出面板
	s2.enemy_passive.text = "攻击时：可以选定任意数量的骰子（至少1个），本次攻击若选定3个以下骰子则获得连击，若只选定1个骰子则再获得洞穿。"
	s2.enemy_status.text = "荆棘9（待结算）、力场、不屈、力量99（下回合）、跃升"
	for i in range(2):
		await process_frame
	assert(s2.enemy_bar.get_combined_minimum_size().y <= s2.enemy_bar.size.y + 0.5)
	# 最坏情况：6 颗敌方骰 + 长被动/状态，信息条仍不溢出、骰块换行后不越界
	var extra := Die.new()
	extra.sides = 6
	extra.value = 2
	en.dice.append(extra)
	en.sel = en.dice.duplicate()
	s2._en_committed = true
	s2.refresh()
	for i in range(2):
		await process_frame
	assert(s2.enemy_bar.get_combined_minimum_size().y <= s2.enemy_bar.size.y + 0.5)
	assert(s2.enemy_dice.get_combined_minimum_size().x <= 680.0)
	# 6 颗时第 6 颗换第二行，骰块仍不越过居中横幅文字、也不到玩家骰行
	assert(s2.enemy_dice_block.offset_right <= 900.0)
	assert(s2.enemy_dice_block.offset_bottom <= s2.dice_row.offset_top)
	en.sel = []
	en.dice.erase(extra)
	s2._en_committed = false
	s2.refresh()
	# 信息栏内边距：文字与深色面板边缘留出 20/8px，且面板裁切内容不越界
	for bar_path in ["EnemyBar", "PlayerBar"]:
		var bar: PanelContainer = s2.get_node(bar_path)
		var bar_style: StyleBox = bar.get_theme_stylebox("panel")
		assert(is_equal_approx(bar_style.content_margin_left, 20.0))
		assert(is_equal_approx(bar_style.content_margin_right, 20.0))
		assert(is_equal_approx(bar_style.content_margin_top, 8.0))
		assert(bar.clip_contents)
	# 最长被动（2 行）+ 状态行：玩家条向下增长时仍不得越过 1080 逻辑高度
	s2.player_passive.text = "攻击时：可以选定任意数量的骰子（至少1个），本次攻击若选定3个以下骰子则获得连击，若只选定1个骰子则再获得洞穿。"
	s2.player_status.text = "荆棘9（待结算）、力场、不屈、力量99（下回合）、跃升"
	for i in range(2):
		await process_frame
	assert(s2.player_bar.offset_top + s2.player_bar.get_combined_minimum_size().y <= 1080.0)
	# 按钮列宽度固定 260：最长文案必须能装下，否则 VBox 会向左扩展压住玩家信息栏
	s2.btn_yc.text = "曜彩 网络渗透\n剩12次·可用"
	s2.btn_reroll.text = "重投所选5颗\n（剩2次）"
	s2.btn_confirm.text = "确认选骰 5/5"
	for i in range(2):
		await process_frame
	for b in [s2.btn_yc, s2.btn_reroll, s2.btn_confirm]:
		assert((b as Button).get_combined_minimum_size().x <= 260.0)
	s2._human_active = false
	s2._en_committed = false
	s2._en_rolled = false
	en.sel = []
	s2._sel.clear()
	s2._phase = ""
	s2.refresh()
	# 非人类阶段：选骰提示清空；第 2 回合未投时敌方标题显示「敌方上回合」
	assert(s2.dice_tip.text == "")
	assert(s2.enemy_dice_label.text == "")
	assert(not s2.enemy_dice_label.visible)
	assert(s2.enemy_bar.offset_bottom < 180.0)
	s2.battle.round = 2
	s2.refresh()
	assert(s2.enemy_dice_label.text == "敌方上回合")
	s2.battle.round = 1
	s2.refresh()
	# 状态栏是信息条 VBox 的独立第三行（不是名字/HP 横排的子项）
	assert(s2.enemy_status.get_parent() == s2.enemy_passive.get_parent())
	assert(s2.enemy_status.get_index() > s2.enemy_passive.get_index())
	assert(s2.player_status.get_parent() == s2.player_passive.get_parent())
	assert(s2.player_status.get_index() > s2.player_passive.get_index())
	# 战绩页全屏遮罩（防止战斗界面文字透出）
	var summary_dim: ColorRect = s2.summary_view.get_node("Dim")
	assert(summary_dim.color.a >= 0.6)
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
	# GameStateData 入口校验（2026-11-25）：非法角色/曜彩回退，无曜彩角色清空，有效空曜彩保持
	GameStateData.char_id = "bogus"
	GameStateData.yc_name = "bogus"
	GameStateData.sanitize()
	assert(GameStateData.char_id == "physics")
	assert(GameStateData.yc_name == "网络渗透")
	GameStateData.char_id = "chem"
	GameStateData.yc_name = "网络渗透"
	GameStateData.sanitize()
	assert(GameStateData.yc_name == "")
	GameStateData.char_id = "physics"
	GameStateData.yc_name = ""
	GameStateData.sanitize()
	assert(GameStateData.yc_name == "")
	# 静态残留非法角色时，选卡页应回到未选中态而不是崩在裸下标
	GameStateData.char_id = "bogus"
	GameStateData.yc_name = "bogus"
	var s4: Node = load("res://scenes/select.tscn").instantiate()
	root.add_child(s4)
	for i in range(2):
		await process_frame
	assert(s4._sel_char == "")
	assert(s4.start_btn.disabled)
	s4._sel_char = "bogus"
	assert(not s4._can_start())
	root.remove_child(s4)
	s4.free()
	print("UI SMOKE OK")
	quit(0)
