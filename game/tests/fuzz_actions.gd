extends SceneTree

# 随机动作模糊测试：valid 模式按合法状态机随机推进；invalid 模式故意传越界/错阶段/对方骰。
# 用法：
#   Godot_v4.7.2-stable_win64.exe --headless --path . -s res://tests/fuzz_actions.gd -- --steps=20000 --mode=valid
#   Godot_v4.7.2-stable_win64.exe --headless --path . -s res://tests/fuzz_actions.gd -- --steps=200 --mode=invalid
#
# 说明：GameRng 是 Crypto、无种子且禁止加种子通道；本测试只用固定 LCG 决定“测试动作”，
# 掷骰仍由 Crypto 产生。invalid 模式在修复守卫前预期会暴露崩溃：崩溃时最后一行
# “FUZZ INVALID step=N case=...” 就是最小定位；修复后应跑到 SURVIVED。

var _checks: int = 0
var _fails: int = 0
var _fail_printed: int = 0
var _steps: int = 0
var _args: Dictionary = {}
var _history: Array = []
var _lcg := Lcg.new(20261125)

class Lcg:
	var _s: int

	func _init(seed: int) -> void:
		_s = seed

	func next(n: int) -> int:
		if n <= 0:
			return 0
		_s = (_s * 1103515245 + 12345) & 0x7fffffff
		return (_s >> 8) % n

func _init() -> void:
	_args = _parse_args()
	var steps: int = int(_args.steps)
	var mode: String = str(_args.mode)
	if mode == "invalid":
		_run_invalid(steps)
	elif mode == "valid":
		_run_valid(steps)
	else:
		print("FUZZ FAIL 未知 mode=%s（只能是 valid/invalid）" % mode)
		quit(1)
		return
	var ok: bool = _fails == 0
	print("FUZZ %s steps=%d fails=%d checks=%d" % [
		"OK" if ok else "FAIL", _steps, _fails, _checks])
	if not ok:
		print("  最后动作（从头复现用）：")
		for h in _history:
			print("    ", h)
	quit(0 if ok else 1)

# ---------------- valid：合法状态机随机推进 ----------------

func _run_valid(steps: int) -> void:
	var b := _new_battle()
	if b.players.size() != 2:
		return
	while _steps < steps:
		if b.winner >= 0 or b.round > 80:
			b = _new_battle()
			if b.players.size() != 2:
				return
			continue
		_record("round_open")
		b.round_open()
		_check("round_open 清空双方 sel", b.players[0].sel.is_empty() and b.players[1].sel.is_empty())
		_check("round_open 重置双方 rolled", not b.players[0].rolled and not b.players[1].rolled)
		_steps += 1
		_check_invariants(b, "round_open")
		for step in [[b.attacker, "attack"], [1 - b.attacker, "defense"]]:
			if b.winner >= 0:
				break
			var idx: int = step[0]
			var phase: String = step[1]
			_record("roll_phase", "idx=%d" % idx)
			b.roll_phase(idx)
			_check("roll_phase 置 rolled p%d" % idx, b.players[idx].rolled)
			_steps += 1
			_check_invariants(b, "roll_phase")
			if b.yaocai_usable(idx, phase) and _lcg.next(2) == 0:
				_record("roll_yaocai", "idx=%d phase=%s" % [idx, phase])
				_check("合法 yaocai 投掷成功", b.roll_yaocai(idx, phase), "idx=%d phase=%s" % [idx, phase])
				_steps += 1
				_check_invariants(b, "roll_yaocai")
			if phase == "attack":
				var reroll_times: int = _lcg.next(3)
				for _r in range(reroll_times):
					if b.rerolls_left(idx) <= 0:
						break
					var picks: Array = []
					for d in b.players[idx].dice:
						if _lcg.next(2) == 0:
							picks.append(d)
					_record("do_reroll", "idx=%d picks=%d" % [idx, picks.size()])
					var rr_before: int = b.rerolls_left(idx)
					var actual: Array = b.do_reroll(idx, picks)
					if not picks.is_empty():
						_check("合法重投有返回", not actual.is_empty(), "picks=%d" % picks.size())
					_check("重投次数不增加", b.rerolls_left(idx) <= rr_before)
					_steps += 1
					_check_invariants(b, "do_reroll")
			var count: int = b.selection_count(idx, phase)
			var sel: Array = _pick_selection(b, idx, count)
			_record("commit_selection", "idx=%d phase=%s sel=%d need=%d" % [idx, phase, sel.size(), count])
			_check("合法 commit 成功", b.commit_selection(idx, phase, sel),
					"idx=%d phase=%s sel=%d need=%d" % [idx, phase, sel.size(), count])
			_steps += 1
			_check_invariants(b, "commit_selection")
		_record("settle")
		b.settle()
		_steps += 1
		_check_invariants(b, "settle")
		_record("round_close")
		_check("合法 round_close 成功", b.round_close())
		_steps += 1
		_check_invariants(b, "round_close")

func _new_battle() -> Battle:
	var b := Battle.new()
	if not b.setup(["physics", "life"], ["网络渗透", "实验防护"], GameRng.new()):
		_check("Battle.setup 成功", false, "physics/life")
	return b

func _pick_selection(b: Battle, idx: int, count: int) -> Array:
	var pool: Array = b.players[idx].dice.duplicate()
	for i in range(pool.size() - 1, 0, -1):
		var j: int = _lcg.next(i + 1)
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	if count <= 0:
		if pool.is_empty():
			return []
		return pool.slice(0, 1)
	return pool.slice(0, mini(count, pool.size()))

# ---------------- invalid：越界/错阶段/对方骰（修复前预期崩溃或状态被污染） ----------------

func _run_invalid(steps: int) -> void:
	var b := _new_battle()
	if b.players.size() != 2:
		return
	b.attacker = 0
	b.round_open()
	b.roll_phase(0)
	b.roll_phase(1)
	var cases: Array = [
		"roll_yaocai(-1)", "roll_yaocai(2)",
		"rerolls_left(-1)", "rerolls_left(2)",
		"selection_count(-1)", "selection_count(2)",
		"yaocai_usable(-1)", "yaocai_usable(2)",
		"yaocai_reason(-1)", "yaocai_reason(2)",
		"do_reroll(-1,[对方骰])", "do_reroll(2,[])",
		"commit_selection(-1)", "commit_selection(2)",
		"commit_selection(0,错阶段)", "commit_selection(0,对方骰)",
		"damage(target=2)", "damage(dealer=2)",
		"settle 两次", "round_close 两次",
		"roll_phase(-1)", "roll_phase(2)",
	]
	for i in range(steps):
		var name: String = str(cases[i % cases.size()])
		print("FUZZ INVALID step=%d case=%s" % [_steps, name])
		_record(name)
		var before := _sig(b)
		var mid := ""
		match name:
			"roll_yaocai(-1)": b.roll_yaocai(-1, "attack")
			"roll_yaocai(2)": b.roll_yaocai(2, "attack")
			"rerolls_left(-1)": b.rerolls_left(-1)
			"rerolls_left(2)": b.rerolls_left(2)
			"selection_count(-1)": b.selection_count(-1, "attack")
			"selection_count(2)": b.selection_count(2, "attack")
			"yaocai_usable(-1)": b.yaocai_usable(-1, "attack")
			"yaocai_usable(2)": b.yaocai_usable(2, "attack")
			"yaocai_reason(-1)": b.yaocai_reason(-1, "attack")
			"yaocai_reason(2)": b.yaocai_reason(2, "attack")
			"do_reroll(-1,[对方骰])": b.do_reroll(-1, [b.players[0].dice[0]])
			"do_reroll(2,[])": b.do_reroll(2, [])
			"commit_selection(-1)": b.commit_selection(-1, "attack", [])
			"commit_selection(2)": b.commit_selection(2, "attack", [])
			"commit_selection(0,错阶段)": b.commit_selection(0, "bogus", [])
			"commit_selection(0,对方骰)": b.commit_selection(0, "attack", [b.players[1].dice[0]])
			"damage(target=2)": b.damage(b.players[0], 1, 2)
			"damage(dealer=2)": b.damage(b.players[1], 1, 1, 2)
			"settle 两次":
				b.round_open()
				b.settle()
				mid = _sig(b)
				b.settle()
			"round_close 两次":
				b.round_open()
				b.settle()
				b.round_close()
				mid = _sig(b)
				b.round_close()
			"roll_phase(-1)": b.roll_phase(-1)
			"roll_phase(2)": b.roll_phase(2)
		_steps += 1
		var after := _sig(b)
		if mid != "":
			# 这类 case 的第一次调用是合法的（settle/round_close 各一次），只要求第二次幂等
			_check("第二次调用不应改变状态：" + name, mid == after,
					"after_first=%s after_second=%s" % [mid, after])
		else:
			_check("非法调用不应改变状态：" + name, before == after,
					"before=%s after=%s" % [before, after])
	_run_guard_cases()
	print("FUZZ INVALID SURVIVED steps=%d" % _steps)

# 2026-11-25 新增守卫的确定性用例（自包含，不依赖上面的共享对局状态）
func _run_guard_cases() -> void:
	var gb := _guard_battle(["nuclear", "ai"], ["", ""])
	if gb.players.size() != 2:
		return
	gb.players[0].dice[0].value = 4
	gb.players[0].dice[1].value = 4
	gb.players[0].dice[3].value = 2
	gb.players[0].dice[4].value = 2
	var gsel: Array = [gb.players[0].dice[0], gb.players[0].dice[1], gb.players[0].dice[3], gb.players[0].dice[4]]
	_check("首次 commit 成功", gb.commit_selection(0, "attack", gsel))
	var ghp: int = gb.players[1].hp
	_check("重复 commit 被拒", not gb.commit_selection(0, "attack", gsel))
	_check("重复 commit 不二次瞬伤", gb.players[1].hp == ghp)
	_check("提交后 do_reroll 被拒", gb.do_reroll(0, [gb.players[0].dice[0]]).is_empty())

	var gb2 := _guard_battle(["math", "ai"], ["", ""])
	if gb2.players.size() != 2:
		return
	gb2.players[0].dice[0].value = 0
	gb2.roll_phase(0)
	_check("重复 roll_phase 不重掷", gb2.players[0].dice[0].value == 0, str(gb2.players[0].dice[0].value))

	var gb3 := _guard_battle(["physics", "life"], ["网络渗透", "实验防护"])
	if gb3.players.size() != 2:
		return
	gb3.commit_selection(0, "attack", [gb3.players[0].dice[0], gb3.players[0].dice[1],
		gb3.players[0].dice[2], gb3.players[0].dice[3]])
	var uses: int = gb3.players[0].yc_uses
	var n_dice: int = gb3.players[0].dice.size()
	_check("提交后曜彩不可用", not gb3.yaocai_usable(0, "attack"))
	_check("提交后投曜彩被拒", not gb3.roll_yaocai(0, "attack"))
	_check("提交后曜彩不消耗/不入池",
			gb3.players[0].yc_uses == uses and gb3.players[0].dice.size() == n_dice)

func _guard_battle(char_ids: Array, yc_names: Array) -> Battle:
	var gb := Battle.new()
	if not gb.setup(char_ids, yc_names, GameRng.new()):
		_check("Battle.setup 成功", false, str(char_ids))
	gb.attacker = 0
	gb.round_open()
	gb.roll_phase(0)
	return gb

# ---------------- 公共检查 ----------------

func _check_invariants(b: Battle, tag: String) -> void:
	_check("winner 范围", b.winner >= -1 and b.winner <= 1, tag + " winner=%d" % b.winner)
	_check("round 范围", b.round >= 1 and b.round <= 81, tag + " round=%d" % b.round)
	for i in range(2):
		var p: Dictionary = b.players[i]
		_check("hp 范围 p%d" % i, p.hp >= 0 and p.hp <= p.hp_max,
				tag + " hp=%d/%d" % [p.hp, p.hp_max])
		_check("rerolls 范围 p%d" % i, p.rerolls >= 0 and p.rerolls <= 2,
				tag + " rerolls=%d" % p.rerolls)
		var seen := {}
		for d in p.sel:
			var owned: bool = p.dice.has(d) or (d.is_yaocai() and d.yaocai == p.yc_name)
			_check("sel 属于本方 p%d" % i, owned, tag)
			_check("sel 无重复 p%d" % i, not seen.has(d), tag)
			seen[d] = true
		for d in p.dice:
			if d.is_yaocai():
				# face=-1 表示本回合尚未投掷（例如守方阶段尚未开始）
				_check("曜彩 face 范围 p%d" % i, d.face == -1 or (d.face >= 0 and d.face <= 5),
						tag + " face=%d" % d.face)
			else:
				# value=0 表示尚未投掷（round_open 后、roll_phase 前的合法中间态）
				_check("骰值范围 p%d" % i, d.value == 0 or (d.value >= 1 and d.value <= d.sides),
						tag + " value=%d sides=%d" % [d.value, d.sides])

func _sig(b: Battle) -> String:
	var parts: Array = []
	for i in range(2):
		var p: Dictionary = b.players[i]
		var vals: Array = []
		for d in p.dice:
			vals.append("%d/%d/%d" % [d.sides, d.value, d.face])
		# sel 必须按“具体骰对象”比较：同数量换成对方骰/换一颗也不能算状态未变
		var sel_ids: Array = []
		for d in p.sel:
			sel_ids.append(str(d.get_instance_id()))
		parts.append("hp=%d/%d dice=[%s] sel=[%s] rr=%d rolled=%s yc=%d/%s fc=%s accum=%d lv=%d/%d str=%d thorns=%d poison=%d stats=%s" % [
			p.hp, p.hp_max, ",".join(vals), ",".join(sel_ids), p.rerolls, str(p.rolled),
			p.yc_uses, str(p.yc_rolled), str(p.face_counts), p.accum, p.atk_perm, p.def_perm,
			b.strength_total(p), p.thorns, p.poison, str(b.stats[i])])
	return "round=%d winner=%d hits=%s log=%d | %s" % [
		b.round, b.winner, str(b.hits), b.log.size(), " || ".join(parts)]

func _record(method: String, detail: String = "") -> void:
	_history.append("%d:%s%s" % [_steps, method, "" if detail == "" else "(" + detail + ")"])
	if _history.size() > 20:
		_history.pop_front()

func _check(name: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	if cond:
		return
	_fails += 1
	if _fail_printed < 20:
		_fail_printed += 1
		print("FUZZ_FAIL ", name, " ", detail)

func _parse_args() -> Dictionary:
	var out := {"steps": 20000, "mode": "valid"}
	for arg in OS.get_cmdline_user_args():
		var key: String = arg.get_slice("=", 0)
		var val: String = arg.get_slice("=", 1)
		match key:
			"--steps":
				out.steps = maxi(1, int(val))
			"--mode":
				out.mode = val.strip_edges()
			_:
				push_warning("fuzz_actions: 未识别参数 %s" % arg)
	return out
