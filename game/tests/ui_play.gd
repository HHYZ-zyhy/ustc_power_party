extends SceneTree

# 无头假人测试：实例化战斗场景，模拟人类点击走完整个对局
# godot --headless -s res://tests/ui_play.gd

func _init() -> void:
	var ui: Node = load("res://scenes/battle.tscn").instantiate()
	root.add_child(ui)
	var done := false
	for frame in range(60000):
		await process_frame
		if ui.battle.winner >= 0:
			done = true
			break
		if ui._human_active:
			if ui._phase != "" and not ui.battle.players[0].yc_rolled \
					and ui.battle.yaocai_usable(0, ui._phase) and frame % 5 == 2:
				ui._on_yc()
				ui._on_yc_use()
			elif ui._phase == "attack" and ui.battle.rerolls_left(0) > 0 and frame % 5 == 0 and ui._sel.is_empty():
				ui._sel.append(ui.battle.players[0].dice[0])
				ui._on_reroll()
			else:
				ui._sel.clear()
				var dice: Array = ui.battle.players[0].dice
				if ui._need > 0:
					for i in range(mini(ui._need, dice.size())):
						ui._sel.append(dice[i])
				else:
					ui._sel.append(dice[0])
				ui._on_confirm()
	if not done:
		print("UI PLAY TIMEOUT round=", ui.battle.round)
	else:
		print("UI PLAY DONE winner=", ui.battle.winner, " round=", ui.battle.round)
	quit(0)
