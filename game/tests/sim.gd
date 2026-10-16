extends SceneTree

# 无头平衡模拟：godot --headless -s res://tests/sim.gd
# 全角色两两对战（双方均用贪心 AI），输出胜率与平均回合数

func _init() -> void:
	var ids: Array = GameData.CHARACTERS.keys()
	var wins := {}
	var games := {}
	var rounds_sum := {}
	for id in ids:
		wins[id] = 0
		games[id] = 0
		rounds_sum[id] = 0
	for i in range(ids.size()):
		for j in range(ids.size()):
			if i == j:
				continue
			for g in range(6):
				var battle := Battle.new()
				var rng := GameRng.new()
				var yc_pool: Array = GameData.YAOCAI.keys()
				var yc_a: String = "" if GameData.CHARACTERS[ids[i]].yc == 0 else yc_pool[rng.randi_range(0, yc_pool.size() - 1)]
				var yc_b: String = "" if GameData.CHARACTERS[ids[j]].yc == 0 else yc_pool[rng.randi_range(0, yc_pool.size() - 1)]
				battle.setup([ids[i], ids[j]], [yc_a, yc_b], rng)
				var w := Driver.run_game(battle, [AIController.new(), AIController.new()])
				var winner_id: String = ids[i] if w == 0 else ids[j]
				wins[winner_id] += 1
				games[ids[i]] += 1
				games[ids[j]] += 1
				rounds_sum[ids[i]] += battle.round
				rounds_sum[ids[j]] += battle.round
	print("=== balance sim ===")
	for id in ids:
		var total: int = games[id]
		var wr: float = 100.0 * wins[id] / total if total > 0 else 0.0
		var ar: float = float(rounds_sum[id]) / total if total > 0 else 0.0
		print("%-14s win %3d/%3d = %5.1f%%  avg_rounds %4.1f" % [GameData.CHARACTERS[id].name, wins[id], total, wr, ar])
	quit(0)
