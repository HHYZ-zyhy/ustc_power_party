extends SceneTree

# 无头浸泡测试：随机角色/曜彩 + AI（或随机策略）打完整局，检查状态不变量。
# 用法：
#   Godot_v4.7.2-stable_win64.exe --headless --path . -s res://tests/soak.gd -- --games=2000 --policy=ai
#   Godot_v4.7.2-stable_win64.exe --headless --path . -s res://tests/soak.gd -- --games=200 --policy=random
#
# 说明：GameRng 是 Crypto、无种子且禁止加种子通道；本测试只用固定 LCG 决定“随机策略的动作”，
# 掷骰仍由 Crypto 产生。失败时打印完整 case（角色/曜彩/策略/局号）供回放定位，不靠 seed 重掷。

var _checks: int = 0
var _fails: int = 0
var _args: Dictionary = {}

# 仅用于测试动作选择的确定性 LCG（不是游戏随机数；游戏掷骰仍走 GameRng/Crypto）
class Lcg:
	var _s: int

	func _init(seed: int) -> void:
		_s = seed

	func next(n: int) -> int:
		if n <= 0:
			return 0
		_s = (_s * 1103515245 + 12345) & 0x7fffffff
		return (_s >> 8) % n

class RandomCtrl:
	var _lcg: Lcg

	func _init(seed: int) -> void:
		_lcg = Lcg.new(seed)

	func choose_yaocai(_p: Dictionary, _phase: String) -> bool:
		return _lcg.next(2) == 0

	func choose_reroll(p: Dictionary) -> Array:
		var picks: Array = []
		for d in p.dice:
			if _lcg.next(2) == 0:
				picks.append(d)
		return picks

	func choose_selection(p: Dictionary, _phase: String, count: int) -> Array:
		var pool: Array = p.dice.duplicate()
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

func _init() -> void:
	_args = _parse_args()
	var games: int = int(_args.games)
	var policy: String = str(_args.policy)
	if policy != "ai" and policy != "random":
		print("SOAK FAIL 未知 policy=%s（只能是 ai/random）" % policy)
		quit(1)
		return
	var ids: Array = GameData.CHARACTERS.keys()
	var yc_all: Array = GameData.YAOCAI.keys()
	if ids.is_empty():
		print("SOAK FAIL 角色表为空")
		quit(1)
		return
	var wins := [0, 0]
	var ko_games := 0
	var timeout_games := 0
	var games_run := 0
	var t0: int = Time.get_ticks_msec()
	for g in range(games):
		var rng := GameRng.new()
		var id_a: String = str(ids[rng.randi_range(0, ids.size() - 1)])
		var id_b: String = str(ids[rng.randi_range(0, ids.size() - 1)])
		var yc_a: String = ""
		var yc_b: String = ""
		if not yc_all.is_empty():
			if int(GameData.CHARACTERS[id_a].yc) > 0:
				yc_a = str(yc_all[rng.randi_range(0, yc_all.size() - 1)])
			if int(GameData.CHARACTERS[id_b].yc) > 0:
				yc_b = str(yc_all[rng.randi_range(0, yc_all.size() - 1)])
		var b := Battle.new()
		if not b.setup([id_a, id_b], [yc_a, yc_b], rng):
			_check("Battle.setup 成功", false, "局%d %s/%s 曜彩=%s/%s" % [g, id_a, id_b, yc_a, yc_b])
			continue
		var base_dice: Array = [b.players[0].dice.size(), b.players[1].dice.size()]
		var ctrls: Array
		if policy == "random":
			ctrls = [RandomCtrl.new(12345 + g), RandomCtrl.new(67890 + g)]
		else:
			ctrls = [AIController.new(), AIController.new()]
		# 自行编排，以便区分“击倒”与“80 回合 HP 判定”（Driver.run_game 会把两者都写成 winner）
		# rounds_run 是防死循环的硬上限：round_close 若因异常不增回合，不能让进程永久挂起
		var rounds_run := 0
		while b.winner < 0 and b.round <= 80 and rounds_run < 200:
			Driver.run_round(b, ctrls)
			rounds_run += 1
		if rounds_run >= 200 and b.winner < 0:
			_check("单局在 200 个回合内结束", false, "局%d %s/%s" % [g, id_a, id_b])
		var timed_out: bool = b.winner < 0
		if timed_out:
			b.winner = 0 if b.players[0].hp > b.players[1].hp else 1
			timeout_games += 1
		else:
			ko_games += 1
		var w: int = b.winner
		if w == 0 or w == 1:
			wins[w] += 1
		games_run += 1
		_check_game(b, g, id_a, id_b, yc_a, yc_b, policy, base_dice, w)
	var ms: int = Time.get_ticks_msec() - t0
	var ok: bool = _fails == 0
	print("SOAK %s games=%d fails=%d ko=%d timeout=%d checks=%d ms=%d" % [
		"OK" if ok else "FAIL", games_run, _fails, ko_games, timeout_games, _checks, ms])
	print("  胜场分布：玩家0=%d 玩家1=%d" % [wins[0], wins[1]])
	quit(0 if ok else 1)

func _check_game(b: Battle, g: int, id_a: String, id_b: String, yc_a: String, yc_b: String,
		policy: String, base_dice: Array, w: int) -> void:
	var tag := "局%d %s/%s 曜彩=%s/%s 策略=%s" % [g, id_a, id_b, yc_a, yc_b, policy]
	_check("winner 范围", w >= 0 and w <= 1, tag + " winner=%d" % w)
	_check("winner 已定", b.winner >= 0, tag + " winner=%d" % b.winner)
	_check("round 范围", b.round >= 1 and b.round <= 81, tag + " round=%d" % b.round)
	for i in range(2):
		var p: Dictionary = b.players[i]
		_check("hp 范围 p%d" % i, p.hp >= 0 and p.hp <= p.hp_max,
				tag + " hp=%d/%d" % [p.hp, p.hp_max])
		# 游戏结束时 round_close 已移除本回合曜彩骰，骰数应回到普通骰基线
		_check("骰数恒定 p%d" % i, p.dice.size() == int(base_dice[i]),
				tag + " dice=%d base=%d" % [p.dice.size(), int(base_dice[i])])
		_check("rerolls 范围 p%d" % i, p.rerolls >= 0 and p.rerolls <= 2,
				tag + " rerolls=%d" % p.rerolls)
		_check("stats 非负 p%d" % i,
				int(b.stats[i].dmg_taken) >= 0 and int(b.stats[i].dmg_dealt) >= 0, tag)
		var seen := {}
		for d in p.sel:
			# round_close 会移除曜彩骰但不清 sel；允许“本方曜彩且已从 dice 移除”的残留
			var owned: bool = p.dice.has(d) or (d.is_yaocai() and d.yaocai == p.yc_name)
			_check("sel 属于本方 p%d" % i, owned, tag + " die=%s" % str(d))
			_check("sel 无重复 p%d" % i, not seen.has(d), tag)
			seen[d] = true
		for d in p.dice:
			if d.is_yaocai():
				_check("曜彩 face 范围 p%d" % i, d.face == -1 or (d.face >= 0 and d.face <= 5),
						tag + " face=%d" % d.face)
			else:
				# 攻方 commit 瞬伤提前结束时，守方本回合可能尚未投掷（value=0）
				_check("骰值范围 p%d" % i, d.value == 0 or (d.value >= 1 and d.value <= d.sides),
						tag + " value=%d sides=%d" % [d.value, d.sides])
	_check("log 无空行", not _has_empty_log(b.log), tag)

func _has_empty_log(lines: Array) -> bool:
	for line in lines:
		if str(line).strip_edges() == "":
			return true
	return false

func _check(name: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	if cond:
		return
	_fails += 1
	if _fails <= 20:
		print("SOAK_FAIL ", name, " ", detail)

func _parse_args() -> Dictionary:
	var out := {"games": 2000, "policy": "ai"}
	for arg in OS.get_cmdline_user_args():
		var key: String = arg.get_slice("=", 0)
		var val: String = arg.get_slice("=", 1)
		match key:
			"--games":
				out.games = maxi(1, int(val))
			"--policy":
				out.policy = val.strip_edges()
			_:
				push_warning("soak: 未识别参数 %s" % arg)
	return out
