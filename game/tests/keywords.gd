extends SceneTree

# 关键词级断言测试：无 RNG 摆定骰面，直接断言 commit/settle 数值
# godot --headless -s res://tests/keywords.gd
# 数值依据 DESIGN.md 冻结规则；改核心结算逻辑后必须先跑本文件

var _pass := 0
var _fail := 0

func _check(cond: bool, name: String, detail: String = "") -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  %s  %s" % [name, detail])

func _mk(a: String, d: String) -> Battle:
	var b := Battle.new()
	b.setup([a, d], ["", ""], GameRng.new())
	b.attacker = 0
	b.round_open()
	return b

func _yc(name: String, face: int) -> Die:
	var y := Die.new()
	y.yaocai = name
	y.face = face
	y.value = GameData.YAOCAI[name].faces[face].points
	return y

func _basic(b: Battle) -> void:
	# math(d6=6,d8=8)=14 攻 vs ai(d4=3,d4=4)=7 防
	b.players[0].dice[3].value = 6
	b.players[0].dice[4].value = 8
	b.commit_selection(0, "attack", [b.players[0].dice[3], b.players[0].dice[4]])
	b.players[1].dice[0].value = 3
	b.players[1].dice[1].value = 4
	b.commit_selection(1, "defense", [b.players[1].dice[0], b.players[1].dice[1]])

func _t_basic() -> void:
	var b := _mk("math", "ai")
	_basic(b)
	var s: Dictionary = b.settle()
	_check(s.atk == 14, "基础攻击值", str(s.atk))
	_check(s.def == 7, "基础防御值", str(s.def))
	_check(s.dmg == 7, "基础伤害", str(s.dmg))
	_check(not s.get("pierce", false), "非洞穿场景 pierce 标记为假", str(s.get("pierce", false)))
	_check(b.players[1].hp == 20, "守方扣血", str(b.players[1].hp))
	_check(b.players[0].hp == 33, "攻方无损", str(b.players[0].hp))

func _t_toughness() -> void:
	var b := _mk("math", "ai")
	b.players[1].toughness = 3
	_basic(b)
	var s: Dictionary = b.settle()
	_check(s.def == 10, "韧性加防", str(s.def))
	_check(s.dmg == 4, "韧性后伤害", str(s.dmg))
	_check(b.players[1].hp == 23, "守方血量", str(b.players[1].hp))
	_check(b.players[0].hp == 30, "受伤≤5 反噬瞬伤3", str(b.players[0].hp))

func _t_clamp_ko() -> void:
	var b := _mk("math", "ai")
	b.damage(b.players[1], 99, 1)
	_check(b.players[1].hp == 0, "HP 钳制≥0", str(b.players[1].hp))
	_check(b.winner == 0, "KO 判胜", str(b.winner))

func _t_combo() -> void:
	var b := _mk("shaonianban", "ai")
	b.players[0].dice[0].value = 4
	b.players[0].dice[2].value = 6
	b.commit_selection(0, "attack", [b.players[0].dice[0], b.players[0].dice[2]])
	b.players[1].dice[0].value = 3
	b.players[1].dice[1].value = 4
	b.commit_selection(1, "defense", [b.players[1].dice[0], b.players[1].dice[1]])
	var s: Dictionary = b.settle()
	_check(s.dmg == 3 and s.dmg2 == 3, "连击两次均 10−7", "%s/%s" % [s.dmg, s.dmg2])
	_check(b.players[1].hp == 21, "连击总扣血", str(b.players[1].hp))
	_check(b.players[0].hp == 24, "受伤≤5 逐次瞬伤 3×2", str(b.players[0].hp))

func _t_combo_stack() -> void:
	# 用户 2026-11-11 裁决：多来源连击叠加（每个来源各多打 1 段）
	# 少年班「选定≤3 颗→连击」+ 重复试验面 4/5「4+连击」同时触发
	var b := _mk("shaonianban", "ai")
	var y := _yc("重复试验", 4)
	b.players[0].dice.append(y)
	b.players[0].dice[0].value = 4
	b.players[0].dice[2].value = 3
	b.commit_selection(0, "attack", [b.players[0].dice[0], b.players[0].dice[2], y])
	b.players[1].dice[0].value = 3
	b.players[1].dice[1].value = 4
	b.commit_selection(1, "defense", [b.players[1].dice[0], b.players[1].dice[1]])
	var s: Dictionary = b.settle()
	_check(s.atk == 11, "叠加连击攻击值 4+3+4", str(s.atk))
	_check(s.dmg == 4, "叠加连击主伤害 11−7", str(s.dmg))
	_check(s.dmg2 == 8 and s.combo_n == 2, "双来源连击：两段各 4", "%s/%s" % [s.dmg2, s.combo_n])
	_check(b.players[1].hp == 15, "叠加连击总扣血 4×3", str(b.players[1].hp))
	_check(b.stats[0].fx.get("combo", 0) == 2, "战绩记两次连击来源", str(b.stats[0].fx.get("combo", 0)))
	# AI 受伤≤5 被动按每次正式伤害逐次触发：三击各瞬伤 3
	_check(b.players[0].hp == 21, "叠加连击逐段触发受伤被动 3×3", str(b.players[0].hp))

	# 前一段连击击倒守方后，剩余连击段不再结算（KO 后所有效果停止）
	var b2 := _mk("shaonianban", "ai")
	var y2 := _yc("重复试验", 5)
	b2.players[0].dice.append(y2)
	b2.players[0].dice[0].value = 4
	b2.players[0].dice[2].value = 3
	b2.commit_selection(0, "attack", [b2.players[0].dice[0], b2.players[0].dice[2], y2])
	b2.players[1].hp = 5
	b2.players[1].dice[0].value = 3
	b2.players[1].dice[1].value = 4
	b2.commit_selection(1, "defense", [b2.players[1].dice[0], b2.players[1].dice[1]])
	var s2: Dictionary = b2.settle()
	_check(s2.dmg == 4, "KO 前主伤害 4", str(s2.dmg))
	_check(s2.dmg2 == 4 and s2.combo_n == 1, "第二段连击击倒后不再打第三段",
		"%s/%s" % [s2.dmg2, s2.combo_n])
	_check(b2.winner == 0 and b2.players[1].hp == 0, "连击段击倒守方", "%d/%d" % [b2.winner, b2.players[1].hp])
	_check(b2.players[0].hp == 27, "KO 段不触发受伤被动", str(b2.players[0].hp))

func _t_pierce() -> void:
	var b := _mk("shaonianban", "ai")
	b.players[0].dice[4].value = 8
	b.commit_selection(0, "attack", [b.players[0].dice[4]])
	b.players[1].dice[0].value = 5
	b.players[1].dice[1].value = 6
	b.commit_selection(1, "defense", [b.players[1].dice[0], b.players[1].dice[1]])
	var s: Dictionary = b.settle()
	_check(s.dmg == 8 and s.dmg2 == 8, "单颗洞穿无视防御(含连击)", "%s/%s" % [s.dmg, s.dmg2])
	_check(s.get("pierce", false), "洞穿场景 pierce 标记为真", str(s.get("pierce", false)))
	_check(b.players[1].hp == 11, "洞穿扣血", str(b.players[1].hp))
	_check(b.players[1].atk_perm == 2 and b.players[1].def_perm == 2, "受伤≥8 逐次双等级+1×2")

	# 洞穿无视一切防御（用户 2026-11-10 重申）：防御值不参与伤害，也不满足「防御值更大」的反击条件
	var b2 := _mk("shaonianban", "cyber")
	b2.players[1].counter_pending = true
	b2.players[0].dice[4].value = 4
	b2.commit_selection(0, "attack", [b2.players[0].dice[4]])
	b2.players[1].dice[2].value = 8
	b2.players[1].dice[3].value = 8
	b2.commit_selection(1, "defense", [b2.players[1].dice[2], b2.players[1].dice[3]])
	var s2: Dictionary = b2.settle()
	_check(s2.get("pierce", false) and s2.dmg == 4 and s2.dmg2 == 4,
		"洞穿主伤害与连击均无视防御", "%s/%s" % [s2.dmg, s2.dmg2])
	_check(s2.counter == 0, "洞穿不触发反击", str(s2.counter))
	_check(b2.players[0].hp == 30, "攻方未被反击", str(b2.players[0].hp))

func _t_field() -> void:
	var b := _mk("math", "ai")
	var y := _yc("实验防护", 5)
	b.players[1].dice.append(y)
	_basic(b)
	b.players[1].dice[0].value = 3
	b.commit_selection(1, "defense", [y, b.players[1].dice[0]])
	var s: Dictionary = b.settle()
	_check(s.dmg == 0, "力场挡常规攻击", str(s.dmg))
	_check(b.players[1].hp == 27, "力场下守方无损", str(b.players[1].hp))

	var b2 := _mk("shaonianban", "ai")
	var y2 := _yc("实验防护", 5)
	b2.players[1].dice.append(y2)
	b2.players[0].dice[4].value = 8
	b2.commit_selection(0, "attack", [b2.players[0].dice[4]])
	b2.players[1].dice[0].value = 3
	b2.commit_selection(1, "defense", [y2, b2.players[1].dice[0]])
	var s2: Dictionary = b2.settle()
	_check(s2.dmg == 8 and s2.dmg2 == 8, "洞穿破力场", "%s/%s" % [s2.dmg, s2.dmg2])

	# 力场只挡常规攻击伤害：非洞穿的主伤害与连击两次均归零
	var b3 := _mk("shaonianban", "ai")
	var y3 := _yc("实验防护", 5)
	b3.players[1].dice.append(y3)
	b3.players[0].dice[0].value = 6
	b3.players[0].dice[1].value = 6
	b3.commit_selection(0, "attack", [b3.players[0].dice[0], b3.players[0].dice[1]])
	b3.players[1].dice[0].value = 3
	b3.commit_selection(1, "defense", [y3, b3.players[1].dice[0]])
	var s3: Dictionary = b3.settle()
	_check(s3.dmg == 0 and s3.dmg2 == 0, "力场挡常规连击（主伤害与连击均0）",
		"%s/%s" % [s3.dmg, s3.dmg2])

func _t_hack() -> void:
	var pick2 := 0
	var pick3 := 0
	for t in range(200):
		var b := _mk("info", "physics")
		b.players[0].dice[0].value = 1
		b.players[0].dice[2].value = 6
		b.players[0].dice[3].value = 6
		b.players[0].dice[4].value = 8
		b.commit_selection(0, "attack", [b.players[0].dice[0], b.players[0].dice[2], b.players[0].dice[3], b.players[0].dice[4]])
		var y := _yc("东风导弹", 5)
		b.players[1].dice.append(y)
		b.players[1].dice[2].value = 6
		b.players[1].dice[3].value = 6
		b.commit_selection(1, "defense", [b.players[1].dice[2], b.players[1].dice[3], y])
		var s: Dictionary = b.settle()
		_check(s.atk == 21, "骇入攻击值", str(s.atk))
		_check(s.def == 15, "骇入后防御 6+6+7→2+6+7", str(s.def))
		_check(s.dmg == 6, "骇入影响伤害", str(s.dmg))
		_check(y.value == 7, "骇入不作用于曜彩骰", str(y.value))
		_check(b.players[0].hp == 19, "守方曜彩瞬伤3", str(b.players[0].hp))
		if b.players[1].dice[2].value == 2:
			pick2 += 1
		elif b.players[1].dice[3].value == 2:
			pick3 += 1
	_check(pick2 > 0 and pick3 > 0, "骇入并列随机", "%d/%d" % [pick2, pick3])

	# 用户 2026-11-10 裁决：对手全部骰子为 1 时，骇入将其中一颗 1 变为 2（保持现有实现）
	var b2 := _mk("info", "chem")
	b2.players[0].dice[0].value = 1
	b2.players[0].dice[1].value = 1
	b2.players[0].dice[2].value = 3
	b2.players[0].dice[3].value = 6
	b2.commit_selection(0, "attack", [b2.players[0].dice[0], b2.players[0].dice[1], b2.players[0].dice[2], b2.players[0].dice[3]])
	for d in b2.players[1].dice:
		d.value = 1
	b2.commit_selection(1, "defense", [b2.players[1].dice[0], b2.players[1].dice[1], b2.players[1].dice[2]])
	var s2: Dictionary = b2.settle()
	var twos := 0
	for d in b2.players[1].sel:
		if d.value == 2:
			twos += 1
	_check(s2.def == 4 and twos == 1, "骇入把全1中的一颗变2", "%d/%d" % [s2.def, twos])

func _t_leap() -> void:
	var b := _mk("physics", "info")
	var d1: Die = b.players[0].dice[2]
	var d2: Die = b.players[0].dice[3]
	var p1 := 0
	for t in range(200):
		d1.value = 3
		d2.value = 3
		b.players[0].leap_round = true
		b.players[0].sel = [d1, d2]
		b._apply_leap(0)
		if d1.value == 6 and d2.value == 3:
			p1 += 1
		elif d2.value == 6 and d1.value == 3:
			pass
		else:
			_check(false, "跃升结果异常", "%d/%d" % [d1.value, d2.value])
	_check(p1 > 0 and p1 < 200, "跃升并列随机", str(p1))

	var b2 := _mk("physics", "info")
	b2.players[0].dice[2].value = 1
	b2.players[0].dice[3].value = 2
	b2.players[0].dice[4].value = 2
	b2.players[0].dice[0].value = 4
	b2.commit_selection(0, "attack", [b2.players[0].dice[2], b2.players[0].dice[3], b2.players[0].dice[4], b2.players[0].dice[0]])
	b2.players[1].dice[2].value = 3
	b2.players[1].dice[3].value = 3
	b2.players[1].dice[0].value = 5
	b2.players[1].leap_round = true
	b2.commit_selection(1, "defense", [b2.players[1].dice[0], b2.players[1].dice[2], b2.players[1].dice[3]])
	b2.settle()
	_check(b2.def_value == 14, "跃升先改点再求和 5+6+3", str(b2.def_value))

func _t_leap_hack_order() -> void:
	# 用户裁决 2026-10-16：跃升与骇入同时结算时先跃升后骇入（骇入把跃升刚升上来的骰打掉）
	# math 攻方 d6=1 + d8=5：先跃升 1→6（成为最大），后骇入把 6 打回 2；若先骇后跃则为 d8 被打、攻击值 8
	var b := _mk("math", "ai")
	var ld: Die = b.players[0].dice[3]   # d6，最小点数 → 跃升目标
	var hd: Die = b.players[0].dice[4]   # d8，原最大点数
	ld.value = 1
	hd.value = 5
	b.commit_selection(0, "attack", [ld, hd])
	b.players[1].dice[0].value = 3
	b.players[1].dice[1].value = 4
	b.commit_selection(1, "defense", [b.players[1].dice[0], b.players[1].dice[1]])
	b.players[0].leap_round = true
	b.players[1].hack_pending = true
	var s: Dictionary = b.settle()
	_check(ld.value == 2, "跃升 1→6 后被骇入打回 2", str(ld.value))
	_check(hd.value == 5, "原最大骰未被骇入", str(hd.value))
	_check(s.atk == 7, "攻击值 2+5", str(s.atk))
	_check(s.dmg == 0, "攻防相抵无伤害", str(s.dmg))

func _t_ko_effects_stop() -> void:
	# 用户裁决 2026-10-16：一方 KO 后所有效果不再结算（虹吸/中毒/回合结束被动与连击/反击/受伤被动口径一致）
	# ① 主伤害 KO：虹吸不回血（life 自带 leech 50%，残血可观测）
	var b := _mk("life", "physics")
	b.players[0].hp = 10
	b.players[0].dice[3].value = 8
	b.players[0].dice[4].value = 8
	b.commit_selection(0, "attack", [b.players[0].dice[3], b.players[0].dice[4]])
	b.players[1].hp = 8
	b.players[1].dice[0].value = 3
	b.players[1].dice[1].value = 4
	b.commit_selection(1, "defense", [b.players[1].dice[0], b.players[1].dice[1]])
	var s: Dictionary = b.settle()
	_check(s.dmg == 9, "虹吸 KO 主伤害 16−7", str(s.dmg))
	_check(b.winner == 0 and b.players[1].hp == 0, "守方被击倒", str(b.players[1].hp))
	_check(b.players[0].hp == 10, "KO 后虹吸不回血", str(b.players[0].hp))

	# ② 主伤害 KO：中毒不结算、层数不变（攻方摆 poison，math 无 leech 干扰）
	var b2 := _mk("math", "physics")
	b2.players[0].poison = 3
	b2.players[0].dice[3].value = 6
	b2.players[0].dice[4].value = 8
	b2.commit_selection(0, "attack", [b2.players[0].dice[3], b2.players[0].dice[4]])
	b2.players[1].hp = 5
	b2.players[1].dice[0].value = 3
	b2.players[1].dice[1].value = 4
	b2.commit_selection(1, "defense", [b2.players[1].dice[0], b2.players[1].dice[1]])
	var s2: Dictionary = b2.settle()
	_check(s2.dmg == 7, "中毒 KO 主伤害 14−7", str(s2.dmg))
	_check(b2.winner == 0 and b2.players[1].hp == 0, "守方被击倒", str(b2.players[1].hp))
	_check(b2.players[0].hp == 33, "KO 后中毒不扣血", str(b2.players[0].hp))
	_check(b2.players[0].poison == 3, "KO 后中毒层数不变", str(b2.players[0].poison))

	# ③ 连击第二击 KO：第一击 leech 正常回血、第二击 KO 后 leech 不回（摆 combo flag，life 自带 leech）
	var b3 := _mk("life", "physics")
	b3.players[0].hp = 10
	b3.players[0].dice[3].value = 8
	b3.players[0].dice[4].value = 4
	b3.commit_selection(0, "attack", [b3.players[0].dice[3], b3.players[0].dice[4]])
	b3._ctx_a.flags.combo_count = 1
	b3.players[1].hp = 8
	b3.players[1].dice[0].value = 3
	b3.players[1].dice[1].value = 4
	b3.commit_selection(1, "defense", [b3.players[1].dice[0], b3.players[1].dice[1]])
	var s3: Dictionary = b3.settle()
	_check(s3.dmg == 5 and s3.dmg2 == 5, "连击两击均 12−7", "%s/%s" % [s3.dmg, s3.dmg2])
	_check(b3.winner == 0 and b3.players[1].hp == 0, "第二击击倒守方", str(b3.players[1].hp))
	_check(b3.players[0].hp == 12, "第一击虹吸回 2、第二击 KO 后不回", str(b3.players[0].hp))

	# ④ KO 后回合结束被动不触发（management round_end always +1 曜彩次数）
	var b4 := _mk("management", "physics")
	b4.players[0].dice[3].value = 8
	b4.players[0].dice[4].value = 8
	b4.players[0].dice[0].value = 6
	b4.commit_selection(0, "attack", [b4.players[0].dice[0], b4.players[0].dice[3], b4.players[0].dice[4]])
	b4.players[1].hp = 8
	b4.players[1].dice[0].value = 3
	b4.players[1].dice[1].value = 4
	b4.players[1].dice[2].value = 6
	b4.commit_selection(1, "defense", [b4.players[1].dice[0], b4.players[1].dice[1], b4.players[1].dice[2]])
	var s4: Dictionary = b4.settle()
	_check(s4.dmg == 9 and b4.winner == 0, "守方被主伤害击倒", "%s/%s" % [s4.dmg, b4.winner])
	b4.round_close()
	_check(b4.players[0].yc_uses == 2, "KO 后回合结束被动不触发", str(b4.players[0].yc_uses))

func _t_ko_commit_stop() -> void:
	# 用户裁决 2026-10-16（续）：commit 阶段瞬伤致死同样令所有效果停止
	# ① 守方被 commit 瞬伤击倒后，settle 的荆棘不结算（攻方不扣血、层数保留）
	var b := _mk("nuclear", "physics")
	b.players[0].hp = 20
	b.players[0].thorns = 2
	b.players[1].hp = 3
	b.players[0].dice[3].value = 6
	b.players[0].dice[4].value = 6
	b.players[0].dice[0].value = 4
	b.players[0].dice[1].value = 2
	b.commit_selection(0, "attack", [b.players[0].dice[0], b.players[0].dice[1], b.players[0].dice[3], b.players[0].dice[4]])
	_check(b.winner == 0, "commit 瞬伤击倒守方", str(b.winner))
	b.settle()
	_check(b.players[0].hp == 20, "KO 后荆棘不扣血", str(b.players[0].hp))
	_check(b.players[0].thorns == 2, "KO 后荆棘层数保留", str(b.players[0].thorns))
	_check(b.players[1].hp == 0, "守方保持被击倒", str(b.players[1].hp))

	# ② 被击倒方 commit：其瞬伤（核科学对子）不再打到已获胜方
	var b2 := _mk("nuclear", "nuclear")
	b2.players[1].hp = 3
	b2.players[0].dice[3].value = 6
	b2.players[0].dice[4].value = 6
	b2.players[0].dice[0].value = 4
	b2.players[0].dice[1].value = 2
	b2.commit_selection(0, "attack", [b2.players[0].dice[0], b2.players[0].dice[1], b2.players[0].dice[3], b2.players[0].dice[4]])
	_check(b2.winner == 0 and b2.players[1].hp == 0, "攻方 commit 瞬伤击倒守方", "%s/%s" % [b2.winner, b2.players[1].hp])
	b2.players[1].dice[3].value = 6
	b2.players[1].dice[4].value = 6
	b2.players[1].dice[0].value = 4
	b2.commit_selection(1, "defense", [b2.players[1].dice[0], b2.players[1].dice[3], b2.players[1].dice[4]])
	_check(b2.players[0].hp == 25, "被击倒方的瞬伤不结算", str(b2.players[0].hp))
	_check(b2.winner == 0, "胜负不被改写", str(b2.winner))

	# ③ 被击倒方曜彩：不可用、有中文原因、投掷不消耗次数不入池
	var b3 := _mk("nuclear", "nuclear")
	b3.players[1].yc_name = "军训急救"
	b3.players[1].yc_uses = 2
	b3.players[1].hp = 3
	b3.players[0].dice[3].value = 6
	b3.players[0].dice[4].value = 6
	b3.players[0].dice[0].value = 4
	b3.players[0].dice[1].value = 2
	b3.commit_selection(0, "attack", [b3.players[0].dice[0], b3.players[0].dice[1], b3.players[0].dice[3], b3.players[0].dice[4]])
	_check(b3.winner == 0, "守方被 commit 瞬伤击倒", str(b3.winner))
	_check(b3.yaocai_usable(1, "defense") == false, "被击倒方曜彩不可用", "")
	_check(b3.yaocai_reason(1, "defense") != "", "被击倒方曜彩有中文原因", b3.yaocai_reason(1, "defense"))
	b3.roll_yaocai(1, "defense")
	_check(b3.players[1].yc_uses == 2, "KO 后投曜彩不消耗次数", str(b3.players[1].yc_uses))
	_check(b3.players[1].dice.size() == 5, "KO 后曜彩骰不入池", str(b3.players[1].dice.size()))

func _t_instant() -> void:
	var b := _mk("nuclear", "ai")
	b.players[0].dice[3].value = 6
	b.players[0].dice[4].value = 6
	b.players[0].dice[0].value = 4
	b.players[0].dice[1].value = 2
	b.commit_selection(0, "attack", [b.players[0].dice[0], b.players[0].dice[1], b.players[0].dice[3], b.players[0].dice[4]])
	_check(b.players[1].hp == 24, "瞬伤在 commit 立即结算", str(b.players[1].hp))
	b.players[1].dice[0].value = 3
	b.players[1].dice[1].value = 4
	b.commit_selection(1, "defense", [b.players[1].dice[0], b.players[1].dice[1]])
	var s: Dictionary = b.settle()
	_check(s.dmg == 11, "瞬伤后主伤害 18−7", str(s.dmg))
	_check(b.players[1].hp == 13, "守方最终血量", str(b.players[1].hp))

func _t_leech() -> void:
	var b := _mk("life", "ai")
	b.players[0].hp = 10
	b.players[0].dice[0].value = 6
	b.players[0].dice[1].value = 6
	b.players[0].dice[2].value = 6
	b.players[0].dice[3].value = 8
	b.commit_selection(0, "attack", [b.players[0].dice[0], b.players[0].dice[1], b.players[0].dice[2], b.players[0].dice[3]])
	b.players[1].dice[0].value = 3
	b.players[1].dice[1].value = 4
	b.commit_selection(1, "defense", [b.players[1].dice[0], b.players[1].dice[1]])
	var s: Dictionary = b.settle()
	_check(s.dmg == 19, "虹吸前伤害 26−7", str(s.dmg))
	_check(b.players[0].hp == 19, "虹吸 50% 回血 10+9", str(b.players[0].hp))
	_check(b.players[1].hp == 8, "守方扣血", str(b.players[1].hp))

func _t_heal() -> void:
	var b := _mk("math", "ai")
	b.players[1].hp = 10
	var y := _yc("军训急救", 2)
	b.players[1].dice.append(y)
	_basic(b)
	b.players[1].dice[0].value = 3
	b.commit_selection(1, "defense", [y, b.players[1].dice[0]])
	_check(b.players[1].hp == 13, "同值治愈 commit 即回", str(b.players[1].hp))
	var s: Dictionary = b.settle()
	_check(s.dmg == 8, "治愈后伤害 14−6", str(s.dmg))
	_check(b.players[1].hp == 5, "守方最终血量", str(b.players[1].hp))

func _t_upgrade() -> void:
	var b := _mk("chem", "ai")
	b.players[0].dice[0].value = 2
	b.players[0].dice[1].value = 4
	b.players[0].dice[3].value = 2
	b.players[0].dice[4].value = 4
	b.commit_selection(0, "attack", [b.players[0].dice[0], b.players[0].dice[1], b.players[0].dice[3], b.players[0].dice[4]])
	_check(b.players[0].dice[0].sides == 6 and b.players[0].dice[1].sides == 6, "d4 全偶升 d6")
	_check(b.players[0].dice[3].sides == 8 and b.players[0].dice[4].sides == 8, "d6 全偶升 d8")
	_check(b.players[0].dice[2].sides == 4, "未选骰不升")
	_check(b.players[0].dice[0].value == 2, "升级当回合保留点数")
	b.players[1].dice[0].value = 3
	b.players[1].dice[1].value = 4
	b.commit_selection(1, "defense", [b.players[1].dice[0], b.players[1].dice[1]])
	var s: Dictionary = b.settle()
	_check(s.atk == 12 and s.dmg == 5, "升级后攻击 12−7", "%s/%s" % [s.atk, s.dmg])

func _t_thorns() -> void:
	var b := _mk("math", "ai")
	var y := _yc("通宵鏖战", 3)
	b.players[0].dice.append(y)
	b.players[0].dice[4].value = 8
	b.commit_selection(0, "attack", [y, b.players[0].dice[4]])
	b.players[1].dice[0].value = 3
	b.players[1].dice[1].value = 4
	b.commit_selection(1, "defense", [b.players[1].dice[0], b.players[1].dice[1]])
	var s: Dictionary = b.settle()
	_check(b.players[0].hp == 31, "荆棘结算前自伤2", str(b.players[0].hp))
	_check(s.dmg == 9, "主伤害 16−7", str(s.dmg))
	_check(b.players[1].hp == 18, "守方扣血", str(b.players[1].hp))
	_check(b.players[0].thorns == 0, "荆棘结算后清除", str(b.players[0].thorns))

func _t_thorns_ko_order() -> void:
	var b := _mk("math", "ai")
	b.players[0].hp = 1
	var y := _yc("通宵鏖战", 4)
	b.players[0].dice.append(y)
	b.players[0].dice[4].value = 8
	b.commit_selection(0, "attack", [y, b.players[0].dice[4]])
	b.players[1].dice[0].value = 3
	b.players[1].dice[1].value = 4
	b.commit_selection(1, "defense", [b.players[1].dice[0], b.players[1].dice[1]])
	var s: Dictionary = b.settle()
	_check(b.winner == 1, "荆棘先于主伤害致死", str(b.winner))
	_check(s.dmg == 0, "主伤害未结算", str(s.dmg))
	_check(b.players[1].hp == 27, "守方无损", str(b.players[1].hp))

func _t_poison() -> void:
	var b := _mk("math", "ai")
	b.players[1].poison = 2
	_basic(b)
	b.settle()
	_check(b.players[1].hp == 18, "中毒结算后 20−2", str(b.players[1].hp))
	_check(b.players[1].poison == 1, "中毒层数-1", str(b.players[1].poison))
	b.round_close()
	b.attacker = 0
	b.round_open()
	_basic(b)
	b.settle()
	_check(b.players[1].hp == 10, "次回合中毒 11−1", str(b.players[1].hp))
	_check(b.players[1].poison == 0, "中毒耗尽", str(b.players[1].poison))

func _t_damage_events() -> void:
	# 界面掉血反馈依赖 battle.hits：每次 damage 按发生顺序记 {target, amount, kind}，
	# amount 为实际扣血（不屈等场景与名义伤害不同）
	var b := _mk("nuclear", "ai")
	b.players[0].dice[3].value = 6
	b.players[0].dice[4].value = 6
	b.players[0].dice[0].value = 4
	b.players[0].dice[1].value = 2
	b.commit_selection(0, "attack", [b.players[0].dice[0], b.players[0].dice[1], b.players[0].dice[3], b.players[0].dice[4]])
	_check(b.hits.size() == 1 and b.hits[0].kind == "instant", "瞬伤记录掉血事件", str(b.hits))
	_check(b.hits[0].target == 1 and b.hits[0].amount == 3, "瞬伤事件目标/实际扣血", str(b.hits[0]))
	b.players[1].dice[0].value = 3
	b.players[1].dice[1].value = 4
	b.commit_selection(1, "defense", [b.players[1].dice[0], b.players[1].dice[1]])
	b.settle()
	_check(b.hits.size() == 2 and b.hits[1].kind == "main", "主伤害事件追加", str(b.hits))
	_check(b.hits[1].amount == 11, "主伤害记实际掉血", str(b.hits[1]))

	var b2 := _mk("math", "ai")
	var y := _yc("通宵鏖战", 3)
	b2.players[0].dice.append(y)
	b2.players[0].dice[4].value = 8
	b2.commit_selection(0, "attack", [y, b2.players[0].dice[4]])
	b2.players[1].dice[0].value = 3
	b2.players[1].dice[1].value = 4
	b2.commit_selection(1, "defense", [b2.players[1].dice[0], b2.players[1].dice[1]])
	b2.settle()
	_check(b2.hits.size() == 2 and b2.hits[0].kind == "thorns" and b2.hits[0].target == 0,
		"荆棘事件指向自伤者", str(b2.hits))
	_check(b2.hits[0].amount == 2, "荆棘记实际自伤", str(b2.hits[0]))
	_check(b2.hits[1].kind == "main" and b2.hits[1].target == 1, "荆棘后主伤害事件", str(b2.hits[1]))

	var b3 := _mk("math", "ai")
	b3.players[1].poison = 2
	_basic(b3)
	b3.settle()
	_check(b3.hits.size() == 2 and b3.hits[1].kind == "poison" and b3.hits[1].amount == 2,
		"中毒事件在结算末尾记录", str(b3.hits))

	var b4 := _mk("shaonianban", "ai")
	b4.players[0].dice[0].value = 4
	b4.players[0].dice[2].value = 4
	b4.commit_selection(0, "attack", [b4.players[0].dice[0], b4.players[0].dice[2]])
	b4.players[1].dice[0].value = 3
	b4.players[1].dice[1].value = 3
	b4.commit_selection(1, "defense", [b4.players[1].dice[0], b4.players[1].dice[1]])
	b4.settle()
	var kinds4: Array = []
	for h in b4.hits:
		kinds4.append(h.kind)
	_check(kinds4 == ["main", "instant", "combo", "instant"], "连击/受伤瞬伤事件顺序", str(kinds4))

	var b5 := _mk("ai", "cyber")
	b5.players[1].counter_pending = true
	b5.players[0].dice[0].value = 1
	b5.players[0].dice[1].value = 1
	b5.commit_selection(0, "attack", [b5.players[0].dice[0], b5.players[0].dice[1]])
	b5.players[1].dice[2].value = 8
	b5.players[1].dice[3].value = 8
	b5.commit_selection(1, "defense", [b5.players[1].dice[2], b5.players[1].dice[3]])
	b5.settle()
	_check(b5.hits.size() == 1 and b5.hits[0].kind == "counter" and b5.hits[0].target == 0,
		"反击事件指向攻方", str(b5.hits))

func _t_stats_actual() -> void:
	# 战绩统计按实际扣血（与 hits 掉血事件、界面飘字同口径）：
	# 溢出击杀与不屈保命时，结算公式算出的名义伤害高于实际掉血，统计不得按名义值累计
	var b := _mk("math", "chem")
	b.players[1].hp = 5
	b.players[0].atk_set = 3
	b.players[0].dice[2].value = 4
	b.players[0].dice[3].value = 6
	b.players[0].dice[4].value = 8
	b.commit_selection(0, "attack", [b.players[0].dice[2], b.players[0].dice[3], b.players[0].dice[4]])
	b.players[1].dice[0].value = 1
	b.players[1].dice[1].value = 1
	b.players[1].dice[2].value = 1
	b.commit_selection(1, "defense", [b.players[1].dice[0], b.players[1].dice[1], b.players[1].dice[2]])
	var s: Dictionary = b.settle()
	_check(s.atk == 18 and s.def == 3, "统计场景攻防值", "%d/%d" % [s.atk, s.def])
	_check(s.dmg == 15, "统计场景名义伤害 18−3", str(s.dmg))
	_check(b.players[1].hp == 0, "守方 5 血被击倒", str(b.players[1].hp))
	_check(b.stats[0].dmg_dealt == 5 and b.stats[1].dmg_taken == 5,
		"溢出击杀统计记实际扣血 5", "%d/%d" % [b.stats[0].dmg_dealt, b.stats[1].dmg_taken])
	_check(b.hits.size() == 1 and b.hits[0].amount == 5, "掉血事件与统计同口径", str(b.hits))

	var b2 := _mk("math", "chem")
	b2.players[1].hp = 5
	b2.players[1].unyielding_round = true
	b2.players[0].atk_set = 3
	b2.players[0].dice[2].value = 4
	b2.players[0].dice[3].value = 6
	b2.players[0].dice[4].value = 8
	b2.commit_selection(0, "attack", [b2.players[0].dice[2], b2.players[0].dice[3], b2.players[0].dice[4]])
	b2.players[1].dice[0].value = 1
	b2.players[1].dice[1].value = 1
	b2.players[1].dice[2].value = 1
	b2.commit_selection(1, "defense", [b2.players[1].dice[0], b2.players[1].dice[1], b2.players[1].dice[2]])
	b2.settle()
	_check(b2.players[1].hp == 1, "不屈保留 1 血", str(b2.players[1].hp))
	_check(b2.stats[0].dmg_dealt == 4 and b2.stats[1].dmg_taken == 4,
		"不屈场景统计记实际扣血 4", "%d/%d" % [b2.stats[0].dmg_dealt, b2.stats[1].dmg_taken])

func _t_unyielding() -> void:
	var b := _mk("math", "life")
	b.players[1].hp = 1
	b.players[0].dice[3].value = 6
	b.players[0].dice[4].value = 8
	b.commit_selection(0, "attack", [b.players[0].dice[3], b.players[0].dice[4]])
	b.players[1].dice[0].value = 6
	b.players[1].dice[1].value = 6
	b.commit_selection(1, "defense", [b.players[1].dice[0], b.players[1].dice[1]])
	b.settle()
	_check(b.players[1].hp == 1, "不屈保留 1 点", str(b.players[1].hp))
	_check(b.winner < 0, "不屈未判负")
	_check(b.players[1].unyielding_used, "不屈仅一次已消耗")
	b.round_close()
	b.attacker = 0
	b.round_open()
	b.players[0].dice[3].value = 6
	b.players[0].dice[4].value = 8
	b.commit_selection(0, "attack", [b.players[0].dice[3], b.players[0].dice[4]])
	b.players[1].dice[0].value = 6
	b.players[1].dice[1].value = 6
	b.commit_selection(1, "defense", [b.players[1].dice[0], b.players[1].dice[1]])
	b.settle()
	_check(b.players[1].hp == 0 and b.winner == 0, "不屈用过即败", "%s/%s" % [b.players[1].hp, b.winner])

func _t_strength() -> void:
	var b := _mk("math", "ai")
	b.round = 3
	var y := _yc("理实积淀", 2)
	b.players[1].dice.append(y)
	_basic(b)
	b.players[1].dice[0].value = 3
	b.commit_selection(1, "defense", [y, b.players[1].dice[0]])
	_check(b.def_value == 7, "理实积淀防御 4+3", str(b.def_value))
	b.round_close()
	_check(b.players[1].strength.size() == 1, "力量保留到下回合")
	b.attacker = 1
	b.round_open()
	b.players[1].dice[1].value = 4
	b.players[1].dice[2].value = 6
	b.players[1].dice[3].value = 8
	b.commit_selection(1, "attack", [b.players[1].dice[1], b.players[1].dice[2], b.players[1].dice[3]])
	_check(b.atk_value == 22, "力量+4 攻击 18+4", str(b.atk_value))
	b.players[0].dice[0].value = 2
	b.players[0].dice[3].value = 5
	b.players[0].dice[4].value = 6
	b.commit_selection(0, "defense", [b.players[0].dice[0], b.players[0].dice[3], b.players[0].dice[4]])
	b.settle()
	_check(b.players[0].hp == 24, "守方承伤 22−13", str(b.players[0].hp))
	b.round_close()
	_check(b.players[1].strength.size() == 0, "力量下回合后过期")

func _t_counter() -> void:
	var b := _mk("cyber", "physics")
	b.players[0].dice[0].value = 6
	b.players[0].dice[2].value = 6
	b.players[0].dice[3].value = 8
	b.commit_selection(0, "attack", [b.players[0].dice[0], b.players[0].dice[2], b.players[0].dice[3]])
	b.players[1].dice[0].value = 5
	b.players[1].dice[1].value = 5
	b.players[1].dice[2].value = 5
	b.commit_selection(1, "defense", [b.players[1].dice[0], b.players[1].dice[1], b.players[1].dice[2]])
	var s: Dictionary = b.settle()
	_check(s.atk == 20, "网安攻击 20 触发", str(s.atk))
	_check(b.players[0].def_pending == 3, "下次防御等级+3", str(b.players[0].def_pending))
	_check(b.players[1].hp == 23, "主伤害 20−15", str(b.players[1].hp))
	b.round_close()
	b.round_open()
	b.players[0].dice[0].value = 2
	b.players[0].dice[1].value = 2
	b.players[0].dice[2].value = 2
	b.players[0].dice[3].value = 2
	b.players[0].dice[4].value = 2
	_check(b.selection_count(0, "defense") == 5, "防御等级 2+3", str(b.selection_count(0, "defense")))
	b.commit_selection(0, "defense", [b.players[0].dice[0], b.players[0].dice[1], b.players[0].dice[2], b.players[0].dice[3], b.players[0].dice[4]])
	b.players[1].dice[0].value = 1
	b.players[1].dice[1].value = 2
	b.players[1].dice[2].value = 1
	b.players[1].dice[3].value = 3
	b.commit_selection(1, "attack", [b.players[1].dice[0], b.players[1].dice[1], b.players[1].dice[2], b.players[1].dice[3]])
	var s2: Dictionary = b.settle()
	_check(s2.dmg == 0, "攻击 7 < 防御 10", str(s2.dmg))
	_check(s2.counter == 3, "反击差值 10−7", str(s2.counter))
	_check(b.players[1].hp == 20, "反击扣血 23−3", str(b.players[1].hp))
	b.round_close()
	_check(b.selection_count(0, "defense") == 2, "防御结束还原等级")

	# 反击对象包含常规攻击的连击：非洞穿的连击仍可触发反击（用户 2026-11-10）
	var b2 := _mk("physics", "cyber")
	b2.players[0].hp = 20   # 非满血，避免物理「满血攻击值+5」
	b2.players[1].counter_pending = true
	b2.players[0].dice[0].value = 2
	b2.players[0].dice[1].value = 2
	b2.players[0].dice[2].value = 3
	b2.players[0].dice[3].value = 3
	b2.commit_selection(0, "attack", [b2.players[0].dice[0], b2.players[0].dice[1], b2.players[0].dice[2], b2.players[0].dice[3]])
	b2.players[1].dice[2].value = 8
	b2.players[1].dice[3].value = 8
	b2.commit_selection(1, "defense", [b2.players[1].dice[2], b2.players[1].dice[3]])
	var s3: Dictionary = b2.settle()
	_check(b2.stats[0].fx.get("combo", 0) == 1 and s3.counter == 6,
		"常规连击仍触发反击", "combo=%d counter=%d" % [b2.stats[0].fx.get("combo", 0), s3.counter])
	_check(b2.players[0].hp == 14, "连击场景攻方被反击 6", str(b2.players[0].hp))

func _t_mingding() -> void:
	var b := _mk("math", "ai")
	var y := _yc("命运签约", 3)
	b.players[0].dice.append(y)
	b.players[0].dice[3].value = 6
	b.players[0].dice[4].value = 8
	b.commit_selection(0, "attack", [b.players[0].dice[3], b.players[0].dice[4]])
	var sel: Array = b.players[0].sel
	_check(sel.has(y), "命定强制入选")
	_check(sel.size() == 2 and not sel.has(b.players[0].dice[3]), "挤掉点数最低的已选骰")
	_check(b.atk_value == 20, "命定 12+8 攻击值", str(b.atk_value))

func _t_mingding_reroll() -> void:
	# 用户裁决 2026-11-11：持有「命定」的曜彩骰可以被重投，但重投后仍必须用于结算
	var b := _mk("earth", "ai")
	var y := _yc("命运签约", 3)
	b.players[0].dice.append(y)
	b.players[0].dice[0].value = 6
	b.players[0].dice[1].value = 6
	b.do_reroll(0, [y])
	_check(b.players[0].rerolls == 1 and b.stats[0].fx.get("reroll", 0) == 1, "命定骰可被重投", str(b.players[0].rerolls))
	b.commit_selection(0, "attack", [b.players[0].dice[0], b.players[0].dice[1]])
	var sel: Array = b.players[0].sel
	_check(sel.has(y), "命定重投后仍强制入选")
	_check(sel.size() == 2, "命定重投后仍恰好占 1 个选骰位", str(sel.size()))

func _t_mingding_reroll_force() -> void:
	# 用户 2026-11-11 澄清：命定曜彩骰无法取消选中，只要发生重投就必须一起重投
	var b := _mk("math", "ai")
	var y := _yc("命运签约", 3)
	var other: Die = b.players[0].dice[0]
	b.players[0].dice.append(y)
	var picks: Array = b.do_reroll(0, [other])
	_check(picks.has(y), "命定骰被强制加入重投", str(picks.size()))
	_check(picks.has(other) and picks.size() == 2, "重投集合=指定骰+命定骰", str(picks.size()))
	_check(b.players[0].rerolls == 1, "强制重投仍只消耗 1 次", str(b.players[0].rerolls))
	_check(y.face >= 0 and y.value == GameData.YAOCAI["命运签约"].faces[y.face].points,
		"命定骰重投后点数与面表一致", "%d/%d" % [y.face, y.value])

	# 非命定曜彩骰不应被强制加入
	var b2 := _mk("math", "ai")
	var y2 := _yc("东风导弹", 0)
	var d2: Die = b2.players[0].dice[0]
	b2.players[0].dice.append(y2)
	var picks2: Array = b2.do_reroll(0, [d2])
	_check(not picks2.has(y2) and picks2.size() == 1, "非命定曜彩骰不强制重投", str(picks2.size()))

	# 空重投不消耗次数；只挑普通骰重投后，命定骰仍必须用于结算
	var b3 := _mk("math", "ai")
	var y3 := _yc("命运签约", 0)
	var d3: Die = b3.players[0].dice[0]
	b3.players[0].dice.append(y3)
	var empty: Array = b3.do_reroll(0, [])
	_check(empty.is_empty() and b3.players[0].rerolls == 2, "空重投不消耗次数", str(b3.players[0].rerolls))
	var picks3: Array = b3.do_reroll(0, [d3])
	_check(picks3.has(y3), "只选普通骰重投也带上命定骰", str(picks3.size()))
	b3.players[0].dice[3].value = 6
	b3.players[0].dice[4].value = 8
	b3.commit_selection(0, "attack", [b3.players[0].dice[3], b3.players[0].dice[4]])
	_check(b3.players[0].sel.has(y3), "强制重投后仍强制入选")

func _t_ai_all_same_bonus() -> void:
	# AI 评估缺陷回归：all_same 条件原只检查「非空」，导致生命学院防御任意组合都算不屈 +6
	var ai := AIController.new()
	var b := _mk("life", "ai")
	var p: Dictionary = b.players[0]
	p.dice[0].value = 3
	p.dice[1].value = 3
	p.dice[2].value = 5
	var same: float = ai._trigger_bonus(p, [p.dice[0], p.dice[1]], "defense")
	var diff: float = ai._trigger_bonus(p, [p.dice[0], p.dice[2]], "defense")
	_check(same == 6.0, "AI 评估 all_same 同点数给不屈 +6", str(same))
	_check(diff == 0.0, "AI 评估非全同不再误加不屈", str(diff))
	# 不屈一次性：已用过后不应再估值
	p.unyielding_used = true
	var used: float = ai._trigger_bonus(p, [p.dice[0], p.dice[1]], "defense")
	_check(used == 0.0, "AI 评估不屈已用不再加值", str(used))

func _t_earth_after() -> void:
	# 用户裁决 2026-11-11：地球「攻击后」力量设置不参与本次伤害，整套结算后才生效
	var b := _mk("earth", "management")
	b.players[0].dice[0].value = 6
	b.players[0].dice[1].value = 6
	b.players[0].hp = 10
	b.players[1].dice[0].value = 1
	b.players[1].dice[1].value = 1
	b.commit_selection(0, "attack", [b.players[0].dice[0], b.players[0].dice[1]])
	_check(b.atk_value == 12 and b.players[0].strength.size() == 0,
		"攻击后力量不在 commit 生效", "atk=%d str=%d" % [b.atk_value, b.players[0].strength.size()])
	b.commit_selection(1, "defense", [b.players[1].dice[0], b.players[1].dice[1]])
	var s: Dictionary = b.settle()
	_check(s.atk == 12, "本次攻击值不含新力量", str(s.atk))
	_check(s.dmg == 10, "本次伤害按 12−2 结算", str(s.dmg))
	_check(b.players[0].strength.size() == 1 and b.players[0].strength[0].n == 12,
		"全 6 攻击后力量设为本次攻击值 100%", str(b.players[0].strength))
	_check(b.players[0].hp == 16, "全 6 攻击后治愈 6 点", str(b.players[0].hp))
	# 非全 6：设置为 50%，且力量为永久层（expire=-1）在下回合攻击计入
	var b2 := _mk("earth", "management")
	b2.players[0].dice[0].value = 6
	b2.players[0].dice[1].value = 5
	b2.players[1].dice[0].value = 1
	b2.players[1].dice[1].value = 1
	b2.commit_selection(0, "attack", [b2.players[0].dice[0], b2.players[0].dice[1]])
	b2.commit_selection(1, "defense", [b2.players[1].dice[0], b2.players[1].dice[1]])
	var s2: Dictionary = b2.settle()
	_check(s2.dmg == 9, "非全 6 本次伤害按 11−2 结算", str(s2.dmg))
	_check(b2.players[0].strength.size() == 1 and b2.players[0].strength[0].n == 5,
		"非全 6 攻击后力量设为本次攻击值 50%", str(b2.players[0].strength))
	_check(b2.players[0].hp == 28, "非全 6 不治愈", str(b2.players[0].hp))
	b2.round_close()
	b2.round_open()
	b2.players[0].dice[0].value = 6
	b2.players[0].dice[1].value = 6
	b2.commit_selection(0, "attack", [b2.players[0].dice[0], b2.players[0].dice[1]])
	_check(b2.atk_value == 17, "攻击后力量在下回合攻击生效（12+5）", str(b2.atk_value))

func _t_usable_matrix() -> void:
	var mismatch := 0
	var rng := GameRng.new()
	for r in range(1, 7):
		for yc_name in GameData.YAOCAI.keys():
			var b := Battle.new()
			b.setup(["physics", "info"], [yc_name, "网络渗透"], rng)
			b.round_open()
			b.roll_phase(0)
			b.round = r
			b.players[0].face_counts = {1: 9, 4: 2}
			for phase in ["attack", "defense"]:
				if (b.yaocai_reason(0, phase) == "") != b.yaocai_usable(0, phase):
					mismatch += 1
	_check(mismatch == 0, "yaocai_reason 与 yaocai_usable 一致", str(mismatch))

func _t_reroll() -> void:
	var b := _mk("math", "ai")
	var d: Die = b.players[0].dice[0]
	b.do_reroll(0, [d])
	_check(b.rerolls_left(0) == 1, "重投次数-1", str(b.rerolls_left(0)))
	_check(d.value >= 1 and d.value <= 4, "d4 重投后点数合法", str(d.value))
	var y := _yc("东风导弹", 0)
	b.players[0].dice.append(y)
	b.do_reroll(0, [y])
	_check(y.face >= 0 and y.face <= 5, "曜彩骰可重投")
	_check(y.value == GameData.YAOCAI["东风导弹"].faces[y.face].points, "曜彩点数与面表一致")

func _t_on_damaged_rule() -> void:
	# 用户裁决 2026-10-13：受伤被动仅防御时、仅正式结算伤害、连击逐次判定、不含荆棘/反击等
	var b := _mk("shaonianban", "ai")
	b.players[0].dice[0].value = 4
	b.players[0].dice[2].value = 4
	b.commit_selection(0, "attack", [b.players[0].dice[0], b.players[0].dice[2]])
	b.players[1].dice[0].value = 3
	b.players[1].dice[1].value = 3
	b.commit_selection(1, "defense", [b.players[1].dice[0], b.players[1].dice[1]])
	var s: Dictionary = b.settle()
	_check(s.dmg == 2 and s.dmg2 == 2, "连击两次均 8−6", "%s/%s" % [s.dmg, s.dmg2])
	_check(b.players[0].hp == 24, "两次≤5 各瞬伤3 共6", str(b.players[0].hp))
	var b2 := _mk("shaonianban", "ai")
	b2.players[0].dice[4].value = 8
	b2.players[0].dice[2].value = 6
	b2.commit_selection(0, "attack", [b2.players[0].dice[4], b2.players[0].dice[2]])
	b2.players[1].dice[0].value = 1
	b2.players[1].dice[1].value = 1
	b2.commit_selection(1, "defense", [b2.players[1].dice[0], b2.players[1].dice[1]])
	b2.settle()
	_check(b2.players[1].atk_perm == 2, "两次≥8 攻击等级+1×2", str(b2.players[1].atk_perm))
	_check(b2.players[1].def_perm == 2, "两次≥8 防御等级+1×2", str(b2.players[1].def_perm))
	var b3 := _mk("math", "ai")
	b3.players[1].thorns = 3
	_basic(b3)
	b3.settle()
	_check(b3.players[0].hp == 33, "荆棘自伤≤5 不触发瞬伤", str(b3.players[0].hp))
	var b4 := _mk("ai", "cyber")
	b4.players[1].counter_pending = true
	b4.players[0].dice[0].value = 1
	b4.players[0].dice[1].value = 1
	b4.commit_selection(0, "attack", [b4.players[0].dice[0], b4.players[0].dice[1]])
	b4.players[1].dice[2].value = 8
	b4.players[1].dice[3].value = 8
	b4.commit_selection(1, "defense", [b4.players[1].dice[2], b4.players[1].dice[3]])
	var s4: Dictionary = b4.settle()
	_check(s4.counter == 14, "反击 16−2", str(s4.counter))
	_check(b4.players[0].atk_perm == 0, "反击伤害≥8 不触发受伤被动", str(b4.players[0].atk_perm))

func _t_on_damaged_ko() -> void:
	# 用户裁决 2026-10-15：被击倒的防守方不再触发受伤被动（与连击/反击的 winner 守卫一致）
	var b := _mk("math", "ai")
	b.players[1].hp = 4   # 守方残血：主伤害 4 既致死又 ≤5（满足瞬伤触发条件）
	b.players[0].dice[3].value = 6
	b.players[0].dice[4].value = 5
	b.commit_selection(0, "attack", [b.players[0].dice[3], b.players[0].dice[4]])
	b.players[1].dice[0].value = 3
	b.players[1].dice[1].value = 4
	b.commit_selection(1, "defense", [b.players[1].dice[0], b.players[1].dice[1]])
	var s: Dictionary = b.settle()
	_check(s.dmg == 4, "致死主伤害 11−7", str(s.dmg))
	_check(b.players[1].hp == 0, "守方被击倒", str(b.players[1].hp))
	_check(b.winner == 0, "攻方判胜", str(b.winner))
	_check(b.players[0].hp == 33, "被击倒后不触发≤5瞬伤反打", str(b.players[0].hp))

func _t_over_count_clamp() -> void:
	# 被动可令攻/防等级无限累积（数学：每次洞穿攻击等级+1；AI学院：受伤≥8 双等级+1）。
	# 超过骰池上限时需选数必须钳制到可用骰数，否则人类无法选够颗数（软锁）、AI 组合枚举越界
	var b := _mk("math", "ai")
	b.players[0].atk_perm = 4  # 攻击等级 2+4=6 > 骰池 5
	_check(b.selection_count(0, "attack") == 5, "攻击等级超池钳制到 5", str(b.selection_count(0, "attack")))
	var ai := AIController.new()
	var sel: Array = ai.choose_selection(b.players[0], "attack", b.selection_count(0, "attack"))
	_check(sel.size() == 5, "AI 超池选骰不越界", str(sel.size()))
	var y := _yc("东风导弹", 0)
	b.players[0].dice.append(y)
	_check(b.selection_count(0, "attack") == 5, "曜彩入池后等级上限仍为普通骰数5", str(b.selection_count(0, "attack")))
	var sel2: Array = ai.choose_selection(b.players[0], "attack", 5)
	_check(sel2.size() == 5, "含曜彩 6 颗中 AI 选 5 颗", str(sel2.size()))
	var b2 := _mk("shaonianban", "ai")
	b2.players[1].def_perm = 4  # 防御等级 2+4=6 > 骰池 5
	_check(b2.selection_count(1, "defense") == 5, "防御等级超池钳制到 5", str(b2.selection_count(1, "defense")))
	var sel3: Array = ai.choose_selection(b2.players[1], "defense", 5)
	_check(sel3.size() == 5, "AI 防御超池不越界", str(sel3.size()))
	var b3 := _mk("math", "ai")
	_check(b3.selection_count(0, "attack") == 2, "正常攻击等级不受影响", str(b3.selection_count(0, "attack")))
	var b4 := _mk("shaonianban", "ai")
	_check(b4.selection_count(0, "attack") == 0, "少年班自由选骰保持 0", str(b4.selection_count(0, "attack")))

func _t_ko_hardening() -> void:
	# ① 双方中毒：先结算方毒发致死后，后结算方的中毒不再结算（逐迭代 winner 守卫）
	var b := _mk("math", "ai")
	b.players[0].dice[0].value = 3
	b.players[0].dice[1].value = 4
	b.commit_selection(0, "attack", [b.players[0].dice[0], b.players[0].dice[1]])
	b.players[1].dice[0].value = 3
	b.players[1].dice[1].value = 4
	b.commit_selection(1, "defense", [b.players[1].dice[0], b.players[1].dice[1]])
	b.players[0].poison = 10
	b.players[1].poison = 10
	b.players[0].hp = 3
	b.players[1].hp = 3
	b.settle()
	_check(b.players[0].hp == 0 and b.winner == 1, "双方中毒先结算方阵亡", "%d/%d" % [b.players[0].hp, b.winner])
	_check(b.players[1].hp == 3, "KO 后对方中毒不扣血", str(b.players[1].hp))
	_check(b.players[1].poison == 10, "KO 后对方中毒层数不变", str(b.players[1].poison))

	# ② commit 瞬伤致死后，settle 的跃升/骇入不得再改点
	var b2 := _mk("nuclear", "ai")
	b2.players[1].hp = 3
	b2.players[0].dice[0].value = 4
	b2.players[0].dice[1].value = 4
	b2.players[0].dice[3].value = 2
	b2.players[0].dice[4].value = 2
	b2.commit_selection(0, "attack", [b2.players[0].dice[0], b2.players[0].dice[1], b2.players[0].dice[3], b2.players[0].dice[4]])
	_check(b2.winner == 0, "commit 瞬伤击倒守方", "%d/%d" % [b2.winner, b2.players[1].hp])
	b2.players[0].leap_round = true
	b2.players[0].hack_pending = true
	b2.players[1].dice[0].value = 5
	b2.players[1].dice[1].value = 1
	b2.players[1].dice[2].value = 1
	b2.commit_selection(1, "defense", [b2.players[1].dice[0], b2.players[1].dice[1], b2.players[1].dice[2]])
	var s2: Dictionary = b2.settle()
	_check(b2.players[0].dice[3].value == 2 and b2.players[0].dice[4].value == 2,
		"KO 后跃升不改点", "%d/%d" % [b2.players[0].dice[3].value, b2.players[0].dice[4].value])
	_check(b2.players[1].dice[0].value == 5, "KO 后骇入不改点", str(b2.players[1].dice[0].value))
	_check(s2.atk == 12, "KO 后攻防值按未改点计算", str(s2.atk))

	# ③ 已阵亡的玩家不再被不屈救回（damage 不应作用于 HP≤0 的目标）
	var b3 := _mk("math", "ai")
	b3.winner = 1
	b3.players[0].hp = 0
	b3.players[0].unyielding_round = true
	var actual: int = b3.damage(b3.players[0], 5, 0)
	_check(actual == 0 and b3.players[0].hp == 0, "已阵亡不再被不屈救回", "%d/%d" % [actual, b3.players[0].hp])
	_check(b3.winner == 1, "阵亡后胜负不改写", str(b3.winner))

	# ④ 曜彩面瞬伤在 commit 阶段致死后，同一玩家的被动不再结算
	var b4 := _mk("nuclear", "ai")
	var y4 := _yc("东风导弹", 3)
	b4.players[0].dice.append(y4)
	b4.players[1].hp = 3
	b4.players[0].dice[0].value = 1
	b4.players[0].dice[1].value = 1
	b4.players[0].dice[2].value = 1
	b4.commit_selection(0, "attack", [y4, b4.players[0].dice[0], b4.players[0].dice[1], b4.players[0].dice[2]])
	_check(b4.winner == 0 and b4.stats[0].fx.get("instant_per_pair", 0) == 0,
		"KO 后 commit 被动不结算", "%d/%d" % [b4.winner, b4.stats[0].fx.get("instant_per_pair", 0)])

func _init() -> void:
	_t_basic()
	_t_toughness()
	_t_clamp_ko()
	_t_combo()
	_t_combo_stack()
	_t_pierce()
	_t_field()
	_t_hack()
	_t_leap()
	_t_leap_hack_order()
	_t_ko_effects_stop()
	_t_ko_commit_stop()
	_t_instant()
	_t_leech()
	_t_heal()
	_t_upgrade()
	_t_thorns()
	_t_thorns_ko_order()
	_t_poison()
	_t_damage_events()
	_t_stats_actual()
	_t_unyielding()
	_t_strength()
	_t_counter()
	_t_mingding()
	_t_mingding_reroll()
	_t_mingding_reroll_force()
	_t_ai_all_same_bonus()
	_t_earth_after()
	_t_usable_matrix()
	_t_reroll()
	_t_on_damaged_rule()
	_t_on_damaged_ko()
	_t_ko_hardening()
	_t_over_count_clamp()
	print("KEYWORDS pass=%d fail=%d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
