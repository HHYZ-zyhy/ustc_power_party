class_name Battle
extends RefCounted

# 分步回合 API：round_open → (yaocai/reroll/commit_selection × 攻防) → settle → round_close
# 同步对局（模拟）用 driver.gd 编排；人类对局由 battle_ui.gd 异步编排

var players: Array = []
var round: int = 1
var attacker: int = 0
var rng: GameRng
var log: Array = []
var winner: int = -1

var _ctx_a: Dictionary = {}
var _ctx_d: Dictionary = {}
var atk_value: int = 0
var def_value: int = 0
var stats: Array = []
# 逐次掉血事件（界面飘字/闪红用）：{target: 受击方索引, amount: 实际扣血, kind: main/combo/counter/instant/thorns/poison}
# damage() 是唯一扣血入口，事件按发生顺序累积，界面自行记录已消费位置
var hits: Array = []
# 稳定性守卫：每回合 settle/round_close 只允许一次，round_open 重置；
# 提交/投掷的幂等分别由玩家字段 sel（非空=已提交）与 rolled（本回合已 roll_phase）判定
var _settled: bool = false
var _closed: bool = false

func _valid_idx(idx: int) -> bool:
	return idx >= 0 and idx < players.size()

func _make_player(char_id: String, yc_name: String) -> Dictionary:
	var cfg: Dictionary = GameData.CHARACTERS[char_id]
	var dice: Array = []
	for sides in Die.CHAIN:
		for i in range(cfg.pool[sides]):
			var d := Die.new()
			d.sides = sides
			dice.append(d)
	return {
		"cfg": cfg, "hp": cfg.hp, "hp_max": cfg.hp, "dice": dice,
		"atk_perm": 0, "def_perm": 0, "atk_set": -1,
		"strength": [], "toughness": 0, "thorns": 0, "poison": 0,
		"field": false, "counter_round": false, "def_pending": 0, "counter_pending": false,
		"unyielding_round": false, "unyielding_used": false,
		"leap_perm": false, "leap_round": false,
		"yc_name": yc_name, "yc_uses": cfg.yc, "yc_rolled": false, "yc_triggered": 0,
		"accum": 0, "face_counts": {1: 0, 4: 0},
		"sel": [], "rerolls": 0, "rolled": false, "hack_pending": false,
	}

func setup(char_ids: Array, yc_names: Array, rng_obj: GameRng) -> bool:
	# 入口校验：非法角色/曜彩/随机源直接拒绝，避免 _make_player 裸下标崩溃
	if rng_obj == null or char_ids.size() != 2 or yc_names.size() != 2:
		return false
	for id in char_ids:
		if not GameData.CHARACTERS.has(str(id)):
			return false
	var safe_yc: Array = []
	for i in range(2):
		var yc: String = str(yc_names[i])
		if yc != "" and not GameData.YAOCAI.has(yc):
			return false
		# 无曜彩角色即使传入曜彩名也不生效（选卡界面正常流程不会传）
		if int(GameData.CHARACTERS[str(char_ids[i])].yc) == 0:
			yc = ""
		safe_yc.append(yc)
	rng = rng_obj
	# 允许在同一对象上重开一局：日志/掉血事件/胜负/回合数全部归零
	log = []
	hits = []
	winner = -1
	round = 1
	_settled = false
	_closed = false
	_ctx_a = _empty_ctx()
	_ctx_d = _empty_ctx()
	atk_value = 0
	def_value = 0
	players = [_make_player(str(char_ids[0]), str(safe_yc[0])),
		_make_player(str(char_ids[1]), str(safe_yc[1]))]
	stats = [
		{"dmg_dealt": 0, "dmg_taken": 0, "fx": {}},
		{"dmg_dealt": 0, "dmg_taken": 0, "fx": {}},
	]
	attacker = rng.coin_flip()
	return true

# 普通骰总数：攻/防等级上限与选骰数封顶的唯一口径
static func pool_count(p: Dictionary) -> int:
	var n := 0
	for k in p.cfg.pool:
		n += p.cfg.pool[k]
	return n

func atk_eff(p: Dictionary) -> int:
	var base: int
	if p.atk_set >= 0:
		base = p.atk_set
	else:
		base = p.cfg.atk + p.atk_perm
	# 等级增加上限 = 角色普通骰子数量（用户裁决 2026-10-13）
	return mini(base, pool_count(p))

func def_eff(p: Dictionary) -> int:
	return mini(p.cfg.def + p.def_perm, pool_count(p))

func strength_total(p: Dictionary) -> int:
	var s := 0
	for e in p.strength:
		s += e.n
	return s

func heal(p: Dictionary, n: int) -> void:
	if winner >= 0:
		return   # KO 后所有效果停止（含治疗）
	if n <= 0 or p.hp <= 0:
		return   # 已阵亡不复活（KO 后所有效果停止）
	p.hp = mini(p.hp + n, p.hp_max)

func damage(p: Dictionary, n: int, idx: int, dealer: int = -1, kind: String = "") -> int:
	if not _valid_idx(idx):
		return 0
	if dealer >= 0 and not _valid_idx(dealer):
		return 0
	if winner >= 0:
		return 0
	if n <= 0 or p.hp <= 0:
		return 0
	var before: int = p.hp
	if p.unyielding_round and p.hp - n <= 0:
		p.hp = 1
	else:
		p.hp = maxi(0, p.hp - n)
	var actual: int = before - p.hp
	# 战绩统计与实际扣血同口径（溢出击杀、不屈保命时名义伤害 ≠ 实际掉血），
	# 与 hits 掉血事件、界面飘字、战绩统计一致
	stats[idx].dmg_taken += actual
	if dealer >= 0:
		stats[dealer].dmg_dealt += actual
	if actual > 0:
		hits.append({"target": idx, "amount": actual, "kind": kind})
	if p.hp <= 0 and winner < 0:
		winner = 1 - idx
		log.append("KO: player%d" % idx)
	return actual

# 骰点总和：结算、AI、界面预览/总计共用的唯一口径
static func dice_sum(dice: Array) -> int:
	var s := 0
	for d in dice:
		s += d.value
	return s

# 对子数（按值分组后每组 floor(数量/2) 之和）：结算与 AI 估值共用的唯一口径
static func pairs_count(values: Array) -> int:
	var counts := {}
	for v in values:
		counts[v] = counts.get(v, 0) + 1
	var pairs := 0
	for v in counts:
		pairs += int(counts[v]) / 2
	return pairs

# 纯函数：只读条件定义、玩家状态、本次选择与上下文；AI 估值与界面预期效果共用
static func eval_cond(c: Dictionary, p: Dictionary, sel: Array, ctx: Dictionary) -> bool:
	var values: Array = []
	for d in sel:
		values.append(d.value)
	match c.t:
		"always": return true
		"count_le": return sel.size() <= c.n
		"count_eq": return sel.size() == c.n
		"all_eq_value":
			for v in values:
				if v != c.v:
					return false
			return values.size() > 0
		"not_all_eq_value":
			for v in values:
				if v != c.v:
					return true
			return false
		"pairs_ge": return pairs_count(values) >= c.n
		"full_hp": return p.hp == p.hp_max
		"all_even":
			for v in values:
				if v % 2 != 0:
					return false
			return values.size() > 0
		"has_pair": return pairs_count(values) >= 1
		"all_same":
			for v in values:
				if v != values[0]:
					return false
			return values.size() > 0
		"sum_ge": return ctx.get("atk_value", 0) >= c.n
		"dmg_ge": return ctx.get("dmg", 0) >= c.n
		"dmg_le": return ctx.get("dmg", 0) >= 1 and ctx.get("dmg", 0) <= c.n
		"yc_triggered_ge": return p.yc_triggered >= c.n
		"accum_ge": return p.accum >= c.n
	return false

func apply_fx(fx: Dictionary, holder: Dictionary, holder_idx: int, opp: Dictionary, ctx: Dictionary) -> void:
	# ctx 允许是最小上下文（on_damaged/round_end 不建完整 commit 上下文）：缺键补默认值
	if not ctx.has("flags"):
		ctx["flags"] = {}
	var flags: Dictionary = ctx.flags
	stats[holder_idx].fx[fx.op] = stats[holder_idx].fx.get(fx.op, 0) + 1
	match fx.op:
		# 多来源连击叠加（用户裁决 2026-11-11）：每个来源各记 1 段，settle() 逐段结算
		"combo": flags.combo_count = flags.get("combo_count", 0) + 1
		"pierce": flags.pierce = true
		"atk_add": ctx.bonus = ctx.get("bonus", 0) + fx.n
		"upgrade_sel":
			for d in ctx.get("sel", []):
				if not d.is_yaocai():
					d.upgrade()
		"hack": holder.hack_pending = true
		"instant": damage(opp, fx.n, 1 - holder_idx, holder_idx, "instant")
		"instant_per_pair": damage(opp, pairs_count(ctx.get("values", [])) * fx.n, 1 - holder_idx, holder_idx, "instant")
		"thorns": holder.thorns += fx.n
		"field": holder.field = true
		"unyielding": holder.unyielding_round = true
		"unyielding_once":
			if not holder.unyielding_used:
				holder.unyielding_used = true
				holder.unyielding_round = true
		"heal_same": heal(holder, int(ctx.get("face_points", 0)))
		"heal": heal(holder, fx.n)
		"strength": holder.strength.append({"n": fx.n, "expire": round + 1})
		"strength_set": holder.strength = [{"n": int(int(ctx.get("atk_value", 0)) * fx.pct / 100.0), "expire": -1}]
		"leech": flags.leech = fx.pct
		"yaocai_use_add":
			if not holder.yc_rolled:
				holder.yc_uses += fx.n
		"leap_perm": holder.leap_perm = true
		"atk_level_add": holder.atk_perm += fx.n
		"def_level_add":
			if fx.get("dur", "") == "next_defense":
				holder.def_pending += fx.n
			else:
				holder.def_perm += fx.n
		"counter": holder.counter_pending = true
		"atk_level_set": holder.atk_set = fx.n
		"mingding": pass

# 可用性判定唯一实现：yaocai_reason() 返回 "" 即当前可用。
# 旧实现两份条件链（布尔版/中文原因版）容易在新增使用条件时漂移。
func yaocai_usable(idx: int, phase: String) -> bool:
	return yaocai_reason(idx, phase) == ""

# 不可用原因（中文，供界面提示）；返回 "" 表示当前可用
func yaocai_reason(idx: int, phase: String) -> String:
	if not _valid_idx(idx):
		return "无效玩家"
	if winner >= 0:
		return "对局已结束"
	var p: Dictionary = players[idx]
	if not p.sel.is_empty():
		return "本回合已提交"
	if p.yc_name == "":
		return "无曜彩骰"
	if not GameData.YAOCAI.has(p.yc_name):
		return "曜彩配置无效"
	if p.yc_uses <= 0:
		return "次数已用完"
	if p.yc_rolled:
		return "本回合已投过"
	var use: Dictionary = GameData.YAOCAI[p.yc_name].use
	var phase_txt: String = ""
	if use.has("phase") and phase != use.phase:
		phase_txt = "仅%s时可用" % ("防御" if use.phase == "defense" else "攻击")
	match use.t:
		"any": return ""
		"phase": return phase_txt
		"round_ge":
			if phase_txt != "":
				return phase_txt
			if round < use.n:
				return "第%d回合起" % use.n
			return ""
		"round_le":
			if round > use.n:
				return "仅前%d回合" % use.n
			return ""
		"accum_face":
			if phase_txt != "":
				return phase_txt
			var cnt: int = p.face_counts.get(use.v, 0)
			if cnt < use.n:
				return "需累计%d次%d点" % [use.n, use.v]
			return ""
	return "当前不可用"

func roll_yaocai(idx: int, phase: String) -> bool:
	# 兜底：次数/本回合已投/使用条件/胜负任一不满足都不消耗、不入池
	if not yaocai_usable(idx, phase):
		return false
	var p: Dictionary = players[idx]
	var d := Die.new()
	d.yaocai = p.yc_name
	d.roll(rng)
	p.dice.append(d)
	p.yc_uses -= 1
	p.yc_rolled = true
	stats[idx].fx["yaocai"] = stats[idx].fx.get("yaocai", 0) + 1
	log.append("yc roll p%d %s face%d=%d" % [idx, p.yc_name, d.face, d.value])
	return true

func rerolls_left(idx: int) -> int:
	if not _valid_idx(idx):
		return 0
	return players[idx].rerolls

func do_reroll(idx: int, dice: Array) -> Array:
	if not _valid_idx(idx) or winner >= 0 or idx != attacker:
		return []
	var p: Dictionary = players[idx]
	if not p.sel.is_empty():
		return []   # 已提交：选骰点数锁定，不能再重投改写
	if dice.is_empty() or p.rerolls <= 0:
		return []
	# 严格只接受本方骰子；传入对方骰/非骰对象直接拒绝，避免重投对方骰
	var picks: Array = []
	for d in dice:
		if not p.dice.has(d):
			return []
		if not picks.has(d):
			picks.append(d)
	# 命定曜彩骰无法取消选中：只要发生重投，就必须把它一起重投（用户 2026-11-11 澄清）。
	# 返回值是实际重投的骰子，调用方应以它驱动 3D 演出，避免漏演强制加入的命定骰。
	for d in p.dice:
		if is_mingding(d) and not picks.has(d):
			picks.append(d)
	if picks.is_empty():
		return []
	for d in picks:
		d.roll(rng)
	p.rerolls -= 1
	stats[idx].fx["reroll"] = stats[idx].fx.get("reroll", 0) + 1
	return picks

func selection_count(idx: int, phase: String) -> int:
	if not _valid_idx(idx) or (phase != "attack" and phase != "defense"):
		return 0
	var p: Dictionary = players[idx]
	var n: int
	if phase == "attack":
		n = atk_eff(p)
	else:
		n = def_eff(p) + p.def_pending
	# 等级增加上限 = 普通骰子数量（用户裁决 2026-10-13）；再钳制到本回合实际可用骰数
	# （被动可令攻/防等级无限累积——数学洞穿+1、AI学院受伤+1，超池则人类软锁、AI 枚举越界）
	n = mini(n, pool_count(p))
	return mini(n, p.dice.size())

# 曜彩面表下标守卫：面数由 GameData.YAOCAI 数据驱动（当前均为 6 面），
# 非法曜彩/面号返回 false，避免各处重复写 face < 0 or face >= 6
func _yaocai_face_valid(d: Die) -> bool:
	if not d.is_yaocai() or not GameData.YAOCAI.has(d.yaocai):
		return false
	var faces: Array = GameData.YAOCAI[d.yaocai].faces
	return d.face >= 0 and d.face < faces.size()

# 曜彩骰当前面是否带「命定」：投出后必须被选中，且重投时不能被排除在外
func is_mingding(d: Die) -> bool:
	if not _yaocai_face_valid(d):
		return false
	for fx in GameData.YAOCAI[d.yaocai].faces[d.face].fx:
		if fx.op == "mingding":
			return true
	return false

func _enforce_mingding(p: Dictionary, sel: Array, count: int) -> Array:
	for d in p.dice:
		if is_mingding(d) and not sel.has(d):
			sel.append(d)
			if count > 0 and sel.size() > count:
				var worst: Die = null
				for cand in sel:
					if cand != d and (worst == null or cand.value < worst.value):
						worst = cand
				sel.erase(worst)
	return sel

func commit_selection(idx: int, phase: String, sel_in: Array) -> bool:
	if not _valid_idx(idx):
		return false
	if phase != "attack" and phase != "defense":
		return false
	if phase != ("attack" if idx == attacker else "defense"):
		return false
	var p: Dictionary = players[idx]
	if not p.sel.is_empty():
		return false   # 本回合已提交：禁止二次提交（防双击/网络重放二次触发瞬伤、治愈、被动）
	var opp: Dictionary = players[1 - idx]
	var count := selection_count(idx, phase)
	# 严格只接受本方骰子；重复项/对方骰/非骰对象直接拒绝
	var sel: Array = []
	for d in sel_in:
		if not p.dice.has(d) or sel.has(d):
			return false
		sel.append(d)
	if count > 0:
		while sel.size() > count:
			sel.pop_back()
		while sel.size() < count:
			var added := false
			for die in p.dice:
				if not sel.has(die):
					sel.append(die)
					added = true
					break
			if not added:
				break
	elif sel.is_empty() and not p.dice.is_empty():
		# 少年班自由选骰的规则下限是「至少 1 颗」；空选会让 count_le 误触发连击
		sel.append(p.dice[0])
	sel = _enforce_mingding(p, sel, count)
	# 曜彩面效果表下标守卫（非法曜彩/面号直接拒绝，避免 faces[face] 越界）
	for d in sel:
		if d.is_yaocai() and not _yaocai_face_valid(d):
			return false
	if phase == "defense":
		p.counter_round = p.counter_pending
		p.counter_pending = false
		p.def_pending = 0
	p.sel = sel
	var values: Array = []
	for d in sel:
		values.append(d.value)
		if d.value == 1 or d.value == 4:
			p.face_counts[d.value] = p.face_counts.get(d.value, 0) + 1
		if d.is_yaocai():
			var face_fx: Array = GameData.YAOCAI[d.yaocai].faces[d.face].fx
			if face_fx.size() > 0:
				p.yc_triggered += 1
	var ctx := {"flags": {}, "sel": sel, "values": values, "atk_value": 0, "bonus": 0, "face_points": 0}
	# 一方 KO 后所有效果不再结算（用户裁决 2026-10-16）：commit 阶段的曜彩面效果
	# 与攻防被动（含瞬伤）全部跳过——被击倒方的瞬伤不再打到已获胜方
	if winner < 0:
		for d in sel:
			if winner >= 0:
				break
			if d.is_yaocai():
				ctx.face_points = d.value
				for fx in GameData.YAOCAI[d.yaocai].faces[d.face].fx:
					if winner >= 0:
						break
					apply_fx(fx, p, idx, opp, ctx)
		for pas in p.cfg.passives:
			if winner >= 0:
				break
			# 第一轮只评估非 sum_ge 的 attack 被动；sum_ge 依赖攻击值，留到下面攻击值算出后评估，
			# 避免条件 n≤0 时被提前触发一次
			if pas.t == phase and not (phase == "attack" and pas.c.t == "sum_ge") and eval_cond(pas.c, p, sel, ctx):
				for fx in pas.fx:
					if winner >= 0:
						break
					apply_fx(fx, p, idx, opp, ctx)
	if phase == "attack":
		atk_value = dice_sum(sel) + strength_total(p) + ctx.get("bonus", 0)
		ctx.atk_value = atk_value
		if winner < 0:
			for pas in p.cfg.passives:
				if winner >= 0:
					break
				# 「攻击时·攻击值≥N」类被动必须在此判定（条件依赖本次攻击值，效果只给下次防御加成）；
				# 「攻击后」被动不在这里结算——见 settle() 中攻击结算之后（用户裁决 2026-11-11：不参与本次伤害）
				if pas.t == "attack" and pas.c.t == "sum_ge" and eval_cond(pas.c, p, sel, ctx):
					for fx in pas.fx:
						if winner >= 0:
							break
						apply_fx(fx, p, idx, opp, ctx)
		_ctx_a = ctx
	else:
		def_value = dice_sum(sel) + p.toughness + ctx.get("bonus", 0)
		_ctx_d = ctx
	return true

func round_open() -> void:
	if players.size() != 2:
		return
	if attacker < 0 or attacker >= players.size():
		push_error("Battle.round_open: attacker 越界 %d，重置为 0" % attacker)
		attacker = 0
	_settled = false
	_closed = false
	# 清掉上一回合的上下文，避免防御阶段被跳过（攻方 commit 瞬伤致胜）时
	# settle 仍读到上一回合的 bonus/攻防值
	_ctx_a = _empty_ctx()
	_ctx_d = _empty_ctx()
	atk_value = 0
	def_value = 0
	for p in players:
		p.leap_round = p.leap_perm
		p.sel = []
		p.rerolls = 0   # 防守方/上回合残留的重投次数不得带进新回合
		p.rolled = false   # 每回合每人只允许 roll_phase 一次
		p.hack_pending = false   # 骇入仅在授予它的那一回合结算，KO 等跳过路径不得残留到下一回合
	players[attacker].rerolls = 2

func roll_phase(idx: int) -> void:
	if not _valid_idx(idx) or winner >= 0:
		return
	var p: Dictionary = players[idx]
	if p.rolled:
		return   # 重复投掷：点数已确定，不得再次随机改写
	p.rolled = true
	for die in p.dice:
		if not die.is_yaocai():
			die.roll(rng)

func _apply_leap(idx: int) -> void:
	var p: Dictionary = players[idx]
	if not p.leap_round:
		return
	var best_v := -1
	var targets: Array = []
	for d in p.sel:
		if d.is_yaocai():
			continue
		if best_v < 0 or d.value < best_v:
			best_v = d.value
			targets = [d]
		elif d.value == best_v:
			targets.append(d)
	if targets.size() > 0:
		var pick: Die = targets[rng.randi_range(0, targets.size() - 1)]
		pick.value = pick.sides

# 结算前骇入：把对手已选骰中点数最大的一颗（并列随机取）变为 2；不作用于曜彩骰
func _apply_hacks() -> void:
	for i in range(players.size()):
		var p: Dictionary = players[i]
		if not p.hack_pending:
			continue
		p.hack_pending = false
		var best_v := 0
		var targets: Array = []
		for die in players[1 - i].sel:
			if die.is_yaocai():
				continue
			if die.value > best_v:
				best_v = die.value
				targets = [die]
			elif die.value == best_v:
				targets.append(die)
		if targets.size() > 0:
			var pick: Die = targets[rng.randi_range(0, targets.size() - 1)]
			pick.value = 2

func _empty_summary() -> Dictionary:
	return {"dmg": 0, "dmg2": 0, "combo_n": 0, "counter": 0, "atk": 0, "def": 0, "pierce": false}

# 主伤害与每段连击共用的有效伤害公式：洞穿取攻击值并无视防御/力场，力场挡下普通伤害
func _damage_after_defense(atk: int, def: int, pierce: bool, field: bool) -> int:
	if pierce:
		return atk
	if field:
		return 0
	return maxi(0, atk - def)

func _empty_ctx() -> Dictionary:
	# settle 在 commit 前被调用（非法/异常路径）时也要有可读的 flags，不能是空字典
	return {"flags": {}, "sel": [], "values": [], "atk_value": 0, "bonus": 0, "face_points": 0}

# 结算顺序：跃升/骇入先改点 → 重算攻防值 → 荆棘 → 主伤害/连击/洞穿/反击 → 攻击后被动 → 中毒
# 跃升与骇入同时结算时先跃升后骇入（用户裁决 2026-10-16）：骇入会把跃升刚升上来的骰打掉
# 任何改骰点数的效果必须放在求和之前，否则伤害用旧值（骇入曾因此失效）
func settle() -> Dictionary:
	if players.size() != 2 or not _valid_idx(attacker):
		return _empty_summary()
	if _settled:
		return _empty_summary()   # 同一回合重复 settle 不二次结算
	_settled = true
	var a := attacker
	var d := 1 - a
	var A: Dictionary = players[a]
	var D: Dictionary = players[d]
	var summary := _empty_summary()
	# commit 阶段瞬伤可能已分出胜负：跃升/骇入也属于「效果」，KO 后不得再改点
	if winner < 0:
		_apply_leap(a)
		_apply_leap(d)
		_apply_hacks()
	atk_value = dice_sum(A.sel) + strength_total(A) + _ctx_a.get("bonus", 0)
	def_value = dice_sum(D.sel) + D.toughness + _ctx_d.get("bonus", 0)
	summary.atk = atk_value
	summary.def = def_value
	summary.pierce = _ctx_a.flags.get("pierce", false)
	for i in range(players.size()):
		var p: Dictionary = players[i]
		# 一方 KO 后所有效果不再结算（用户裁决 2026-10-16）：荆棘与连击/反击/中毒口径一致
		# （commit 阶段瞬伤致死时 winner 已定，荆棘不扣血、层数保留）
		if winner < 0 and p.thorns > 0:
			var t: int = p.thorns
			p.thorns = 0
			damage(p, t, i, -1, "thorns")
	if winner >= 0:
		return summary
	var dmg := _damage_after_defense(atk_value, def_value, _ctx_a.flags.get("pierce", false), D.field)
	summary.dmg = dmg
	damage(D, dmg, d, a, "main")
	# 被击倒后不再触发受伤被动（与连击/反击的 winner 守卫一致；用户裁决 2026-10-15）
	if winner < 0:
		_eval_on_damaged(D, d, A, dmg)
	# 一方 KO 后所有效果不再结算（用户裁决 2026-10-16）：虹吸/中毒与连击/反击/受伤被动口径一致
	if winner < 0 and _ctx_a.flags.get("leech", 0) > 0:
		heal(A, int(dmg * _ctx_a.flags.leech / 100.0))
	# 多来源连击叠加（用户裁决 2026-11-11）：N 个来源 = 主伤害之后再结算 N 段连击
	# （少年班/物理学院被动 + 重复试验面 4+连击可同时触发）；每段独立判定 KO/受伤被动/虹吸
	var combo_n: int = int(_ctx_a.flags.get("combo_count", 0))
	for _ci in range(combo_n):
		if winner >= 0:
			break
		var dmg2 := _damage_after_defense(atk_value, def_value, _ctx_a.flags.get("pierce", false), D.field)
		summary.dmg2 += dmg2
		summary.combo_n += 1
		damage(D, dmg2, d, a, "combo")
		if winner < 0:
			_eval_on_damaged(D, d, A, dmg2)
		if winner < 0 and _ctx_a.flags.get("leech", 0) > 0:
			heal(A, int(dmg2 * _ctx_a.flags.leech / 100.0))
	# 洞穿无视一切防御（用户 2026-11-10 重申）：防御值不参与伤害，也不满足「防御值更大」的反击条件，
	# 带洞穿的攻击不再触发对方反击
	if winner < 0 and D.counter_round and def_value > atk_value and not summary.pierce:
		summary.counter = def_value - atk_value
		damage(A, summary.counter, a, d, "counter")
	# 地球「攻击后：力量层数设置为本次攻击值的 50%/100%」在攻击结算（主伤害/连击/反击）之后、
	# 中毒之前生效（用户裁决 2026-11-11：不得反过来抬升本次伤害；治愈同样在攻击结算后）。
	# 之前放在 commit 里，strength_set 写入的新力量会被 settle 重算攻击值时吃进本次伤害。
	if winner < 0:
		_ctx_a.atk_value = atk_value   # 跃升/骇入可能已改点，按最终攻击值取百分比
		for pas in A.cfg.passives:
			if winner >= 0:
				break
			if pas.t == "attack_after" and eval_cond(pas.c, A, A.sel, _ctx_a):
				for fx in pas.fx:
					if winner >= 0:
						break
					apply_fx(fx, A, a, D, _ctx_a)
	# 中毒同口径：一方 KO 后不再结算（含层数递减）；先结算方毒发致死后，
	# 后结算方的中毒也不再扣血/减层（与荆棘循环的逐迭代 winner 守卫一致）
	if winner < 0:
		for i in range(players.size()):
			var p: Dictionary = players[i]
			if winner < 0 and p.poison > 0:
				damage(p, p.poison, i, -1, "poison")
				p.poison -= 1
	return summary

# 「受到伤害」类被动：仅防御时、仅正式结算伤害（主伤害与每段连击逐次判定），
# 不含荆棘/中毒/反击/瞬伤等其他掉血（用户裁决 2026-10-13）
func _eval_on_damaged(D: Dictionary, d: int, A: Dictionary, dmg: int) -> void:
	for pas in D.cfg.passives:
		if winner >= 0:
			break
		if pas.t == "on_damaged" and eval_cond(pas.c, D, D.sel, {"dmg": dmg}):
			for fx in pas.fx:
				if winner >= 0:
					break
				# instant / 等级成长等统一走 apply_fx：保证战绩「触发」统计与 commit 阶段同口径
				apply_fx(fx, D, d, A, {"flags": {}, "sel": D.sel, "values": [], "atk_value": 0, "bonus": 0})

func round_close() -> bool:
	if players.size() != 2 or not _valid_idx(attacker):
		return false
	if not _settled:
		return false   # 必须先 settle 再关回合：避免 accum 吃旧攻防值/在无结算情况下推进回合
	if _closed:
		return false   # 同一回合重复 round_close 不二次加 accum/触发被动/增回合
	_closed = true
	var a := attacker
	var d := 1 - a
	players[a].accum += atk_value
	players[d].accum += def_value
	for idx in [a, d]:
		var p: Dictionary = players[idx]
		var opp: Dictionary = players[1 - idx]
		# 回合结束被动同口径：一方 KO 后不再结算（用户裁决 2026-10-16）
		if winner < 0:
			for pas in p.cfg.passives:
				if winner >= 0:
					break
				if pas.t == "round_end" and eval_cond(pas.c, p, p.sel, {"atk_value": atk_value}):
					for fx in pas.fx:
						if winner >= 0:
							break
						apply_fx(fx, p, idx, opp, {"flags": {}, "sel": [], "values": [], "atk_value": atk_value, "bonus": 0})
	for p in players:
		var keep: Array = []
		for e in p.strength:
			if e.expire < 0 or e.expire > round:
				keep.append(e)
		p.strength = keep
		p.field = false
		p.unyielding_round = false
		p.counter_round = false
		p.yc_rolled = false
		p.leap_round = false
		var keep_dice: Array = []
		for die in p.dice:
			if not die.is_yaocai():
				keep_dice.append(die)
		p.dice = keep_dice
	attacker = 1 - attacker
	round += 1
	return true
