extends SceneTree

# UI 压力测试：完整 UI 对局 + select↔battle 场景往返，检查节点/孤儿节点/Tween 泄漏
# 用法：
#   godot --headless --path . -s res://tests/ui_stress.gd -- --mode=lifecycle --cycles=20
#   godot --path . -s res://tests/ui_stress.gd -- --games=2 --cycles=20 --time-scale=10
# 参数（OS.get_cmdline_user_args，格式 --key=value）：
#   --games=30        完整 UI 对局数（仅 full 模式跑）
#   --cycles=100      select↔battle 场景往返次数（两种模式都跑）
#   --time-scale=10   full 模式对局快进倍率，结束时复位 1.0
#   --mode=full       full=开窗跑完整对局；lifecycle=可无头，只跑场景往返
#   --timeout=60      单局超时秒数（真实时间，不受 time_scale 影响）
#   --settle=5        每轮释放场景后的收尾帧数
# 说明：与 ui_play.gd 不同，这里不用固定帧数上限，而是"超过 N 秒未结束即判失败"，
# 因为窗口模式与不同机器的帧率差异大，固定帧数会误杀慢机器。

var _fails: int = 0
var _checks: int = 0
var _args: Dictionary = {}
var _iter: int = 0          # 全局轮次：每局完整对局 / 每次场景往返各算一轮
var _games_done: int = 0
var _cycles_done: int = 0
var _baseline: Dictionary = {}
var _first_compare: bool = true
var _frame_seq: int = 0

func _init() -> void:
	_args = _parse_args()
	if str(_args.mode) != "full" and str(_args.mode) != "lifecycle":
		_check("mode 只能是 full 或 lifecycle", false, "--mode=%s" % str(_args.mode))
		print("UI STRESS FAIL fails=%d" % _fails)
		quit(1)
		return
	print("UI STRESS 开始：mode=%s games=%d cycles=%d time_scale=%.1f timeout=%.0fs" % [
			str(_args.mode), int(_args.games), int(_args.cycles),
			float(_args.time_scale), float(_args.timeout)])
	Engine.time_scale = float(_args.time_scale) if str(_args.mode) == "full" else 1.0
	if str(_args.mode) == "full":
		await _run_games(int(_args.games))
	Engine.time_scale = 1.0   # 场景往返统一按 1.0 跑，避免上一阶段倍率带入
	await _run_cycles(int(_args.cycles))
	await _final_checks()
	Engine.time_scale = 1.0   # quit 前显式复位，避免同进程后续脚本继承快进倍率
	var orphans := _orphan_count()
	print("检查 %d 项，失败 %d 项；收尾 orphans=%d" % [_checks, _fails, orphans])
	if _fails == 0:
		print("UI STRESS OK games=%d cycles=%d orphans=%d" % [_games_done, _cycles_done, orphans])
		quit(0)
	else:
		print("UI STRESS FAIL fails=%d" % _fails)
		quit(1)

# ---------- 完整对局 ----------

func _run_games(n: int) -> void:
	if n <= 0:
		return
	print("— 完整对局 %d 局（time_scale=%.1f）—" % [n, float(_args.time_scale)])
	for i in range(n):
		await _run_one_game(i + 1)
		await _after_iteration()

# 一局完整 UI 对局：假人操作沿用 ui_play.gd 的思路，直到战绩页出现或超时
func _run_one_game(no: int) -> void:
	GameStateData.char_id = "physics"
	GameStateData.yc_name = "网络渗透"
	_frame_seq = 0
	var ui: Node = load("res://scenes/battle.tscn").instantiate()
	root.add_child(ui)
	# 加到 root 后先等一帧，确保 @onready 变量（summary_view/battle）完成初始化；
	# 否则第一局会在 _init 的同一帧访问到 null，脚本错误导致提前 return、场景未释放。
	await process_frame
	_frame_seq += 1
	if not is_instance_valid(ui) or ui.summary_view == null or ui.battle == null \
			or ui.battle.players.size() != 2:
		_check("对局 %d 场景初始化" % no, false, "ui/battle/@onready 未完成或 Battle.setup 失败")
		_release(ui)
		return
	var t0: int = Time.get_ticks_msec()
	var timeout_ms: int = int(float(_args.timeout) * 1000.0)
	var timed_out := false
	while is_instance_valid(ui) and ui.summary_view != null and not ui.summary_view.visible:
		await process_frame
		_frame_seq += 1
		if not is_instance_valid(ui) or ui.summary_view == null:
			break
		if ui.summary_view.visible:
			break
		if ui.battle != null and ui.battle.winner < 0 and ui._human_active:
			_click_human(ui)
		if Time.get_ticks_msec() - t0 > timeout_ms:
			timed_out = true
			break
	if not is_instance_valid(ui) or ui.summary_view == null:
		_check("对局 %d 场景初始化" % no, false, "ui 已释放或 summary_view 为空")
		_release(ui)
		return
	var elapsed: float = float(Time.get_ticks_msec() - t0) / 1000.0
	var round_n: int = int(ui.battle.round) if ui.battle != null else -1
	var winner: int = int(ui.battle.winner) if ui.battle != null else -1
	_check("对局 %d 在 %.0fs 内打完" % [no, float(_args.timeout)], not timed_out,
			"超时：round=%d winner=%d human_active=%s" % [round_n, winner, str(ui._human_active)])
	# 战绩页出现后 _run 已停在「等待返回选卡」，再等几帧让 show_summary 的布局收尾
	for i in range(3):
		await process_frame
	_release(ui)
	for i in range(5):
		await process_frame
	_games_done += 1
	print("  [对局 %d] winner=%d round=%d 用时=%.1fs" % [no, winner, round_n, elapsed])

# 假人点击：规则与 ui_play.gd 一致（必要时曜彩 → 进攻期重投 → 选满/选一颗后确认）
func _click_human(ui: Node) -> void:
	if ui._phase != "" and not ui.battle.players[0].yc_rolled \
			and ui.battle.yaocai_usable(0, ui._phase) and _frame_seq % 5 == 2:
		ui._on_yc()
		ui._on_yc_use()
	elif ui._phase == "attack" and ui.battle.rerolls_left(0) > 0 \
			and _frame_seq % 5 == 0 and ui._sel.is_empty():
		ui._sel.append(ui.battle.players[0].dice[0])
		ui._on_reroll()
	else:
		ui._sel.clear()
		var dice: Array = ui.battle.players[0].dice
		if ui._need > 0:
			for i in range(mini(ui._need, dice.size())):
				ui._sel.append(dice[i])
		elif dice.size() > 0:
			ui._sel.append(dice[0])
		ui._on_confirm()

# ---------- 场景往返 ----------

func _run_cycles(n: int) -> void:
	if n <= 0:
		return
	print("— select↔battle 场景往返 %d 次 —" % n)
	for i in range(n):
		await _run_one_cycle(i + 1)
		await _after_iteration()

# 一次往返：选卡 2 帧 → 释放 → 战斗 2–5 帧 → 释放；每轮重置跨场景状态与时间缩放
func _run_one_cycle(no: int) -> void:
	GameStateData.char_id = ""
	GameStateData.yc_name = ""
	Engine.time_scale = 1.0
	var sel_scene: PackedScene = load("res://scenes/select.tscn")
	if sel_scene == null:
		_check("往返 %d 选卡场景加载" % no, false, "load 返回 null")
		return
	var sel: Node = sel_scene.instantiate()
	root.add_child(sel)
	for i in range(2):
		await process_frame
	_check("往返 %d 选卡场景已初始化" % no,
			is_instance_valid(sel) and sel.get_child_count() > 0)
	_release(sel)
	# 战斗场景需要合法组合（正常流程由 select_ui._on_start 写入 GameStateData）
	GameStateData.char_id = "physics"
	GameStateData.yc_name = "网络渗透"
	var battle_scene: PackedScene = load("res://scenes/battle.tscn")
	if battle_scene == null:
		_check("往返 %d 战斗场景加载" % no, false, "load 返回 null")
		return
	var ui: Node = battle_scene.instantiate()
	root.add_child(ui)
	# 2–5 帧覆盖初始化 + 起手投骰；不等演出，回合协程随 free 中止
	for i in range(2 + no % 4):
		await process_frame
	var battle_ok: bool = is_instance_valid(ui) and ui.battle != null and ui.battle.players.size() == 2
	_check("往返 %d 战斗场景已初始化" % no, battle_ok, "battle 为 null 或 setup 失败")
	_release(ui)
	for i in range(3):
		await process_frame
	_cycles_done += 1
	print("  [往返 %d] select/battle 已创建并释放" % no)

# ---------- 泄漏检查 ----------

# 每轮结束后统一收尾与采样：第 1 轮先取一次基线（短跑也可收尾比较），
# 预热 3 轮后再取更稳定的基线；之后每 10 轮比较一次
func _after_iteration() -> void:
	_iter += 1
	for i in range(int(_args.settle)):
		await process_frame
	if _iter == 1 or _iter == 3:
		_baseline = _snapshot()
		print("  · 泄漏基线（第 %d 轮后）：%s" % [_iter, _fmt(_baseline)])
	elif _iter > 3 and _iter % 10 == 0:
		_compare_leaks()

func _compare_leaks(is_final: bool = false) -> void:
	var cur := _snapshot()
	# 首次比较允许更大漂移（预热不足时引擎侧缓存可能尚未稳定）；收尾用严格口径
	var tol: int = 16 if (_first_compare and not is_final) else 8
	var orphan_tol: int = 0 if is_final else tol
	var tag: String = "（收尾严格比较）" if is_final else ("（首次比较允许 +%d 漂移）" % tol if _first_compare else "")
	_first_compare = false
	_check("第 %d 轮孤儿节点未持续增长%s" % [_iter, tag],
			int(cur.orphans) - int(_baseline.orphans) <= orphan_tol,
			"基线 %d → 现在 %d" % [int(_baseline.orphans), int(cur.orphans)])
	_check("第 %d 轮节点总数未持续增长%s" % [_iter, tag],
			int(cur.nodes) - int(_baseline.nodes) <= tol,
			"基线 %d → 现在 %d" % [int(_baseline.nodes), int(cur.nodes)])
	_check("第 %d 轮末 root 无残留子节点" % _iter,
			int(cur.root_children) == 0, "root 子节点 %d" % int(cur.root_children))
	_check("第 %d 轮末无残留 Tween" % _iter,
			int(cur.tweens) == 0, "残留 %d 个" % int(cur.tweens))

# 收尾检查：root 无子节点、无残留 Timer、无残留 Tween（测试脚本本身不是 Node）
func _final_checks() -> void:
	# 多等几帧，让 free 后的延迟清理（Tween 解绑、队列释放）全部生效
	for i in range(10):
		await process_frame
	Engine.time_scale = 1.0
	for i in range(2):
		await process_frame
	_check("至少运行一局或一次场景往返", _iter > 0, "iter=%d" % _iter)
	var kids: int = root.get_child_count()
	_check("结束时 root 无残留子节点", kids == 0, "root.get_child_count()=%d" % kids)
	var timers: Array = root.find_children("*", "Timer", true, false)
	var timer_names: Array = []
	for t in timers:
		timer_names.append(str(t.name))
	_check("结束时无残留 Timer 节点", timers.is_empty(),
			"残留 %d 个：%s" % [timers.size(), "、".join(timer_names)])
	var tweens := get_processed_tweens()
	_check("结束时无残留 Tween", tweens.is_empty(), "残留 %d 个" % tweens.size())
	var cur := _snapshot()
	if _baseline.is_empty():
		_check("已取得泄漏基线", false, "iter=%d" % _iter)
	else:
		_compare_leaks(true)
		print("  · 收尾快照：%s" % _fmt(cur))
		print("  · 泄漏基线：%s" % _fmt(_baseline))

func _snapshot() -> Dictionary:
	# 测试脚本本身就是 SceneTree，直接调用树方法（SceneTree 没有 get_tree()）
	return {
		"orphans": _orphan_count(),
		"nodes": get_node_count(),
		"root_children": root.get_child_count(),
		"tweens": get_processed_tweens().size(),
	}

func _orphan_count() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))

func _fmt(s: Dictionary) -> String:
	return "orphans=%d nodes=%d root_children=%d tweens=%d" % [
			int(s.orphans), int(s.nodes), int(s.root_children), int(s.tweens)]

# 统一检查入口：不用 assert（release 版会剥离），失败只计数并打印
func _check(name: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	if cond:
		return
	_fails += 1
	print("  [FAIL] %s%s" % [name, "" if detail == "" else "：" + detail])

# 立即释放场景（对齐 shot.gd/ui_smoke.gd：先 remove_child 再 free，确保当场离开树）
func _release(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()

func _parse_args() -> Dictionary:
	var out := {
		"games": 30,
		"cycles": 100,
		"time_scale": 10.0,
		"mode": "full",
		"timeout": 60.0,
		"settle": 5,
	}
	for arg in OS.get_cmdline_user_args():
		var key: String = arg.get_slice("=", 0)
		var val: String = arg.get_slice("=", 1)
		match key:
			"--games":
				out.games = maxi(0, int(val))
			"--cycles":
				out.cycles = maxi(0, int(val))
			"--time-scale":
				out.time_scale = maxf(1.0, float(val))
			"--mode":
				out.mode = val.strip_edges()
			"--timeout":
				out.timeout = maxf(1.0, float(val))
			"--settle":
				out.settle = maxi(1, int(val))
			_:
				push_warning("ui_stress: 未识别参数 %s" % arg)
	return out
