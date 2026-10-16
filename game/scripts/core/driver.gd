class_name Driver
extends RefCounted

# 同步编排：供无头模拟使用（双方 AI）。人类对局由 battle_ui.gd 异步编排同一套分步 API

static func run_round(battle: Battle, ctrls: Array) -> Dictionary:
	battle.round_open()
	var order := [[battle.attacker, "attack"], [1 - battle.attacker, "defense"]]
	for step in order:
		var idx: int = step[0]
		var phase: String = step[1]
		var p: Dictionary = battle.players[idx]
		battle.roll_phase(idx)
		if battle.yaocai_usable(idx, phase) and ctrls[idx].choose_yaocai(p, phase):
			battle.roll_yaocai(idx, phase)
		if phase == "attack":
			while battle.rerolls_left(idx) > 0:
				var picks: Array = ctrls[idx].choose_reroll(p)
				if picks.is_empty():
					break
				battle.do_reroll(idx, picks)
		var count: int = battle.selection_count(idx, phase)
		var sel: Array = ctrls[idx].choose_selection(p, phase, count)
		battle.commit_selection(idx, phase, sel)
	var summary: Dictionary = battle.settle()
	battle.round_close()
	return summary

static func run_game(battle: Battle, ctrls: Array, max_rounds: int = 80) -> int:
	while battle.winner < 0 and battle.round <= max_rounds:
		run_round(battle, ctrls)
	if battle.winner < 0:
		battle.winner = 0 if battle.players[0].hp > battle.players[1].hp else 1
	return battle.winner
