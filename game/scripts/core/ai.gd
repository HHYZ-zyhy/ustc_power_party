class_name AIController
extends RefCounted

# v1 贪心 AI：枚举选骰组合取期望净收益最大；重投与曜彩投掷用简单启发式

func _combos(pool: Array, k: int) -> Array:
	var result: Array = []
	if k == 0:
		for mask in range(1, 1 << pool.size()):
			var combo: Array = []
			for i in range(pool.size()):
				if mask & (1 << i):
					combo.append(pool[i])
			if combo.size() <= 4:
				result.append(combo)
		return result
	var idx: Array = []
	_combo_rec(pool, k, 0, idx, result)
	return result

func _combo_rec(pool: Array, k: int, start: int, idx: Array, result: Array) -> void:
	if idx.size() == k:
		var combo: Array = []
		for i in idx:
			combo.append(pool[i])
		result.append(combo)
		return
	for i in range(start, pool.size()):
		idx.append(i)
		_combo_rec(pool, k, i + 1, idx, result)
		idx.pop_back()

func _pairs(values: Array) -> int:
	var counts := {}
	for v in values:
		counts[v] = counts.get(v, 0) + 1
	var pairs := 0
	for v in counts:
		pairs += int(counts[v]) / 2
	return pairs

func _trigger_bonus(p: Dictionary, combo: Array, phase: String) -> float:
	var values: Array = []
	for d in combo:
		values.append(d.value)
	var bonus := 0.0
	var sum := 0
	for v in values:
		sum += v
	for pas in p.cfg.passives:
		var t := "attack" if phase == "attack" else "defense"
		if pas.t != t:
			continue
		var ok := false
		match pas.c.t:
			"always": ok = true
			"count_le": ok = combo.size() <= pas.c.n
			"count_eq": ok = combo.size() == pas.c.n
			"all_eq_value":
				ok = values.size() > 0
				for v in values:
					if v != pas.c.v:
						ok = false
			"pairs_ge": ok = _pairs(values) >= pas.c.n
			"full_hp": ok = p.hp == p.hp_max
			"all_even":
				ok = values.size() > 0
				for v in values:
					if v % 2 != 0:
						ok = false
			"has_pair": ok = _pairs(values) >= 1
			"all_same": ok = values.size() > 0
		if not ok:
			continue
		for fx in pas.fx:
			match fx.op:
				"combo": bonus += sum * 0.5
				"pierce": bonus += sum * 0.6
				"atk_add": bonus += fx.n
				"upgrade_sel": bonus += 4.0
				"hack": bonus += 3.0
				"instant_per_pair": bonus += 3.0 * _pairs(values)
				"leech": bonus += sum * 0.25
				"unyielding_once": bonus += 6.0
	for d in combo:
		if d.is_yaocai():
			for fx in GameData.YAOCAI[d.yaocai].faces[d.face].fx:
				match fx.op:
					"combo": bonus += sum * 0.5
					"hack": bonus += 3.0
					"instant": bonus += fx.n
					"heal_same": bonus += d.value * 0.5 if p.hp < p.hp_max else 0.0
					"field": bonus += 8.0
					"unyielding": bonus += 6.0
					"strength": bonus += fx.n * 0.5
	return bonus

func choose_selection(p: Dictionary, phase: String, count: int) -> Array:
	var combos := _combos(p.dice, count)
	if combos.is_empty():
		return []
	var best: Array = combos[0]
	var best_score := -1e9
	var opp_est := 3.5 * 3 if phase == "attack" else 3.5 * 4
	for combo in combos:
		var sum := 0
		for d in combo:
			sum += d.value
		var bonus := _trigger_bonus(p, combo, phase)
		var score: float
		if phase == "attack":
			score = maxf(0.0, sum + bonus - opp_est) + bonus
		else:
			score = -maxf(0.0, opp_est - sum) + bonus
		if score > best_score:
			best_score = score
			best = combo
	return best

func choose_reroll(p: Dictionary) -> Array:
	if p.rerolls <= 0:
		return []
	var count: int = p.cfg.atk + p.atk_perm
	if p.atk_set >= 0:
		count = p.atk_set
	if count <= 0:
		count = 3
	var values: Array = []
	for d in p.dice:
		values.append(d.value)
	values.sort()
	var best_sum := 0
	for i in range(values.size() - 1, maxi(-1, values.size() - count - 1), -1):
		best_sum += values[i]
	if best_sum >= count * 3:
		return []
	var picks: Array = []
	for d in p.dice:
		if d.value <= 2:
			picks.append(d)
	if picks.is_empty():
		var weakest: Die = p.dice[0]
		for d in p.dice:
			if d.value < weakest.value:
				weakest = d
		picks.append(weakest)
	return picks

func choose_yaocai(p: Dictionary, phase: String) -> bool:
	if p.yc_name == "" or p.yc_uses <= 0:
		return false
	var faces: Array = GameData.YAOCAI[p.yc_name].faces
	var avg := 0.0
	for f in faces:
		avg += f.points
	avg /= faces.size()
	return avg >= 3.5
