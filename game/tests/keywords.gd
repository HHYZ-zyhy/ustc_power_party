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
	b3._ctx_a.flags.combo = true
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

func _init() -> void:
	_t_basic()
	_t_toughness()
	_t_clamp_ko()
	_t_combo()
	_t_pierce()
	_t_field()
	_t_hack()
	_t_leap()
	_t_leap_hack_order()
	_t_ko_effects_stop()
	_t_instant()
	_t_leech()
	_t_heal()
	_t_upgrade()
	_t_thorns()
	_t_thorns_ko_order()
	_t_poison()
	_t_unyielding()
	_t_strength()
	_t_counter()
	_t_mingding()
	_t_usable_matrix()
	_t_reroll()
	_t_on_damaged_rule()
	_t_on_damaged_ko()
	_t_over_count_clamp()
	print("KEYWORDS pass=%d fail=%d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
