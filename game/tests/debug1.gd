extends SceneTree

# 单局调试：godot --headless -s res://tests/debug1.gd

func _init() -> void:
	var battle := Battle.new()
	var rng := GameRng.new()
	battle.setup(["physics", "life"], ["网络渗透", "实验防护"], rng)
	print("attacker=", battle.attacker)
	var ctrls := [AIController.new(), AIController.new()]
	for r in range(12):
		if battle.winner >= 0:
			break
		var s: Dictionary = Driver.run_round(battle, ctrls)
		print("round %d hp=%d/%d atk=%d def=%d dmg=%d+%d counter=%d" % [battle.round, battle.players[0].hp, battle.players[1].hp, s.atk, s.def, s.dmg, s.dmg2, s.counter])
	print("winner=", battle.winner)
	for line in battle.log:
		print("  ", line)
	quit(0)
