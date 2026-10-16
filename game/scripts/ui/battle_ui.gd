extends Control

# 战斗界面：人类 = 玩家0，AI = 玩家1；异步编排 Battle 的分步 API

signal phase_confirmed

var battle: Battle
var rng: GameRng
var ai: AIController
var _phase: String = ""
var _human_active: bool = false
var _sel: Array = []
var _need: int = 0
var _en_rolled: bool = false
var _en_committed: bool = false

@onready var enemy_name: Label = %EnemyName
@onready var enemy_hp: Label = %EnemyHp
@onready var enemy_yc: Label = %EnemyYc
@onready var enemy_status: RichTextLabel = %EnemyStatus
@onready var enemy_passive: RichTextLabel = %EnemyPassive
@onready var enemy_dice: HBoxContainer = %EnemyDice
@onready var banner: Label = %Banner
@onready var big: Label = %Big
@onready var info_label: RichTextLabel = %InfoLabel
@onready var player_passive: RichTextLabel = %PlayerPassive
@onready var player_name: Label = %PlayerName
@onready var player_hp: Label = %PlayerHp
@onready var player_yc: Label = %PlayerYc
@onready var player_status: RichTextLabel = %PlayerStatus
@onready var dice_row: HBoxContainer = %DiceRow
@onready var btn_yc: Button = %BtnYc
@onready var btn_reroll: Button = %BtnReroll
@onready var btn_confirm: Button = %BtnConfirm
@onready var log_line: Label = %LogLine
@onready var round_label: Label = %RoundLabel
@onready var yc_popup: PanelContainer = %YcPopup
@onready var yc_title: Label = %YcTitle
@onready var yc_intro: RichTextLabel = %YcIntro
@onready var yc_faces: GridContainer = %YcFaces
@onready var yc_uses: Label = %YcUses
@onready var yc_use_btn: Button = %YcUseBtn
@onready var yc_close_btn: Button = %YcCloseBtn
@onready var roll_view: SubViewportContainer = %RollView
@onready var summary_view: Control = %SummaryView
@onready var sum_panel: PanelContainer = %SumPanel
@onready var sum_title: Label = %SumTitle
@onready var sum_stats: RichTextLabel = %SumStats
@onready var sum_btn: Button = %SumBtn
@onready var chart_host: Control = %ChartHost
var roller: Node
var glossary: GlossaryPanel
var sum_chart: HpChart
var hp_hist: Array = [[], []]
var _badge_atk := {}   # idx -> Label：攻等级徽章（被动改等级后需随 refresh 更新）
var _badge_def := {}   # idx -> Label：防等级徽章

func _ready() -> void:
	rng = GameRng.new()
	ai = AIController.new()
	battle = Battle.new()
	var ids: Array = GameData.CHARACTERS.keys()
	var others: Array = ids.duplicate()
	others.erase(GameStateData.char_id)
	var ai_id: String = others[rng.randi_range(0, others.size() - 1)]
	var ai_cfg: Dictionary = GameData.CHARACTERS[ai_id]
	var yc_keys: Array = GameData.YAOCAI.keys()
	var ai_yc: String = "" if ai_cfg.yc == 0 else yc_keys[rng.randi_range(0, yc_keys.size() - 1)]
	battle.setup([GameStateData.char_id, ai_id], [GameStateData.yc_name, ai_yc], rng)
	btn_yc.pressed.connect(_on_yc)
	btn_reroll.pressed.connect(_on_reroll)
	btn_confirm.pressed.connect(_on_confirm)
	yc_use_btn.pressed.connect(_on_yc_use)
	yc_close_btn.pressed.connect(_on_yc_close)
	glossary = GlossaryPanel.new()
	add_child(glossary)
	sum_chart = HpChart.new()
	sum_chart.set_anchors_preset(Control.PRESET_FULL_RECT)
	chart_host.add_child(sum_chart)
	for r in [info_label, enemy_status, player_status, enemy_passive, player_passive, yc_intro, sum_stats]:
		r.meta_clicked.connect(_on_kw_meta)
	roller = get_node("RollView/SubViewport/DiceRoll")
	_refresh_static()
	_run()

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _fx_list_text(fx_arr: Array) -> String:
	var parts: Array = []
	for fx in fx_arr:
		parts.append(_fx_text(fx))
	return "、".join(parts)

func _fx_text(fx: Dictionary) -> String:
	match fx.op:
		"combo": return "连击"
		"pierce": return "洞穿"
		"atk_add": return "攻击值+%d" % fx.n
		"upgrade_sel": return "升级所选骰"
		"hack": return "骇入"
		"instant": return "瞬伤%d" % fx.n
		"instant_per_pair": return "每对瞬伤%d" % fx.n
		"thorns": return "荆棘%d" % fx.n
		"field": return "力场"
		"unyielding", "unyielding_once": return "不屈"
		"heal_same": return "治愈（同点数）"
		"heal": return "治愈%d" % fx.n
		"strength": return "力量%d" % fx.n
		"strength_set": return "力量=攻击值×%d%%" % fx.pct
		"leech": return "虹吸%d%%" % fx.pct
		"yaocai_use_add": return "曜彩次数+%d" % fx.n
		"leap_perm": return "永久跃升"
		"atk_level_add": return "攻击等级+%d" % fx.n
		"def_level_add": return "防御等级+%d" % fx.n
		"atk_level_set": return "攻击等级=%d" % fx.n
		"counter": return "反击"
		"mingding": return "命定"
	return fx.op

const BADGE_ATK_BG := Color(0.82, 0.32, 0.22)
const BADGE_DEF_BG := Color(0.23, 0.45, 0.80)

# 骰型配色（用户指定，与 3D 演出同色系）：4 天蓝 / 6 紫 / 8 橙 / 12 与曜彩近黑+蓝紫点缀
const TIER_BG := {4: Color(0.451, 0.910, 0.988), 6: Color(0.765, 0.365, 0.969), 8: Color(0.969, 0.812, 0.682), 12: Color(0.10, 0.10, 0.15)}
const TIER_ACCENT := {4: Color(0.20, 0.78, 0.95), 6: Color(0.58, 0.25, 0.90), 8: Color(0.92, 0.62, 0.35), 12: Color(0.55, 0.45, 0.95)}
const DARK_DIE_BG := Color(0.10, 0.10, 0.15)
const DARK_DIE_ACCENT := Color(0.55, 0.45, 0.95)
const SEL_BORDER := Color(1.0, 0.85, 0.3)
const LOCK_BORDER := Color(1.0, 0.45, 0.75)

func _die_colors(d: Die) -> Dictionary:
	if d.is_yaocai():
		return {"bg": DARK_DIE_BG, "accent": DARK_DIE_ACCENT, "font": Color(0.85, 0.80, 1.0)}
	if d.sides == 12:
		return {"bg": DARK_DIE_BG, "accent": DARK_DIE_ACCENT, "font": Color(0.85, 0.80, 1.0)}
	return {"bg": TIER_BG[d.sides], "accent": TIER_ACCENT[d.sides], "font": Color(0.10, 0.12, 0.18)}

func _style_die_button(b: Button, d: Die, selected: bool, locked: bool) -> void:
	var c := _die_colors(d)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = c.bg if state != "disabled" else c.bg.darkened(0.45)
		if selected:
			sb.border_color = SEL_BORDER
		elif locked:
			sb.border_color = LOCK_BORDER
		else:
			sb.border_color = c.accent
		sb.set_border_width_all(4 if (selected or locked) else 2)
		sb.set_corner_radius_all(10)
		b.add_theme_stylebox_override(state, sb)
	var font_col: Color = c.font
	for fc in ["font_color", "font_color_hover", "font_color_pressed"]:
		b.add_theme_color_override(fc, font_col)
	b.add_theme_color_override("font_color_disabled", Color(0.55, 0.55, 0.60))

func _make_badge(txt: String, bg: Color, tip: String) -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 2.0
	sb.content_margin_bottom = 2.0
	panel.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(l)
	panel.custom_minimum_size = Vector2(0, 44)
	panel.tooltip_text = tip
	return panel

func _atk_badge_text(p: Dictionary) -> String:
	var v: int = battle.atk_eff(p)
	return "?" if v == 0 else str(v)

func _def_level_shown(p: Dictionary) -> int:
	# 防御等级徽章 = def_eff + 网安「下次防御+3」类 def_pending，按普通骰数封顶（与 selection_count 口径一致）
	var pool_n := 0
	for k in p.cfg.pool:
		pool_n += p.cfg.pool[k]
	return mini(battle.def_eff(p) + p.def_pending, pool_n)

func _add_stat_badges(row: Node, p: Dictionary, idx: int) -> void:
	var atk_b := _make_badge("攻 %s" % _atk_badge_text(p), BADGE_ATK_BG, "攻击等级：进攻时需选定的骰子数")
	var def_b := _make_badge("防 %d" % _def_level_shown(p), BADGE_DEF_BG, "防御等级：防御时需选定的骰子数")
	row.add_child(atk_b)
	row.add_child(def_b)
	row.move_child(atk_b, 1)
	row.move_child(def_b, 2)
	_badge_atk[idx] = atk_b.get_child(0)
	_badge_def[idx] = def_b.get_child(0)

# 徽章文本原只在 _refresh_static 求值一次；被动改等级（数学洞穿+1、AI 受伤+1、工程变5、网安下次防御+3）
# 后必须随 refresh 更新，否则双方成长在界面上永远看不到
func _refresh_badges() -> void:
	for idx in [0, 1]:
		if _badge_atk.has(idx):
			_badge_atk[idx].text = "攻 %s" % _atk_badge_text(battle.players[idx])
		if _badge_def.has(idx):
			_badge_def[idx].text = "防 %d" % _def_level_shown(battle.players[idx])

func _refresh_static() -> void:
	var me: Dictionary = battle.players[0]
	var en: Dictionary = battle.players[1]
	player_name.text = me.cfg.name
	enemy_name.text = en.cfg.name
	player_passive.text = (GlossaryPanel.kw_bbcode(me.cfg.intro))
	enemy_passive.text = (GlossaryPanel.kw_bbcode(en.cfg.intro))
	_add_stat_badges(enemy_name.get_parent(), en, 1)
	_add_stat_badges(player_name.get_parent(), me, 0)

func _yc_text(p: Dictionary) -> String:
	if p.yc_name == "":
		return "无曜彩"
	return "%s 剩%d次" % [p.yc_name, p.yc_uses]

func refresh() -> void:
	var me: Dictionary = battle.players[0]
	var en: Dictionary = battle.players[1]
	player_hp.text = "HP %d/%d" % [me.hp, me.hp_max]
	enemy_hp.text = "HP %d/%d" % [en.hp, en.hp_max]
	player_yc.text = _yc_text(me)
	enemy_yc.text = _yc_text(en)
	_refresh_badges()
	if _human_active:
		for d in me.dice:
			if _is_mingding(d) and not _sel.has(d):
				_sel.append(d)
	round_label.text = "回合 %d" % battle.round
	enemy_status.text = (GlossaryPanel.kw_bbcode(_status_text(en)))
	player_status.text = (GlossaryPanel.kw_bbcode(_status_text(me)))
	if _human_active:
		_refresh_preview()
	else:
		info_label.text = ""
	var en_dice: Array = []
	if _en_committed:
		en_dice = en.sel.duplicate()
		en_dice.sort_custom(_die_less)
	elif _en_rolled or battle.round > 1:
		# 守方本回合尚未重投时，显示其上回合投出的骰子（同原作；第 1 回合无历史）
		en_dice = en.dice.duplicate()
		en_dice.sort_custom(_die_less)
	for c in enemy_dice.get_children():
		c.queue_free()
	for d in en_dice:
		var l := Label.new()
		l.text = _die_text(d)
		l.add_theme_font_size_override("font_size", 30)
		l.add_theme_color_override("font_color", _die_colors(d).accent)
		enemy_dice.add_child(l)
	if _en_committed and en_dice.size() > 0:
		var sum := 0
		for d in en_dice:
			sum += d.value
		var total := Label.new()
		total.text = "总计 %d" % sum
		total.add_theme_font_size_override("font_size", 34)
		total.add_theme_color_override("font_color", Color(0.72, 0.76, 0.86))
		enemy_dice.add_child(total)
	var my_dice: Array = me.dice.duplicate()
	my_dice.sort_custom(_die_less)
	var fx_hints: Dictionary = _die_fx_hints(me, _need) if _human_active else {}
	for c in dice_row.get_children():
		c.queue_free()
	for d in my_dice:
		var b := Button.new()
		var locked := _is_mingding(d)
		if locked:
			b.text = "命定·%s\n%d" % [d.yaocai, d.value]
			b.add_theme_font_size_override("font_size", 26)
		elif d.is_yaocai():
			b.text = _die_text(d)
			b.add_theme_font_size_override("font_size", 26)
		else:
			b.text = _die_text(d)
		b.custom_minimum_size = Vector2(104, 88)
		if d.is_yaocai() and not locked:
			var fx_arr: Array = GameData.YAOCAI[d.yaocai].faces[d.face].fx
			var fx_lbl := RichTextLabel.new()
			fx_lbl.bbcode_enabled = true
			fx_lbl.text = (GlossaryPanel.kw_bbcode(_fx_list_text(fx_arr) if fx_arr.size() > 0 else "无效果"))
			fx_lbl.add_theme_font_size_override("normal_font_size", 13)
			fx_lbl.add_theme_color_override("default_color",
				Color(1.0, 0.85, 0.4) if fx_arr.size() > 0 else Color(0.62, 0.62, 0.62))
			fx_lbl.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
			fx_lbl.offset_top = -22.0
			fx_lbl.offset_bottom = -4.0
			fx_lbl.meta_clicked.connect(_on_kw_meta)
			b.add_child(fx_lbl)
		elif fx_hints.has(d):
			var hint := RichTextLabel.new()
			hint.bbcode_enabled = true
			hint.text = (GlossaryPanel.kw_bbcode("、".join(fx_hints[d])))
			hint.add_theme_font_size_override("normal_font_size", 14)
			hint.add_theme_color_override("default_color", Color(1.0, 0.85, 0.4))
			hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
			hint.offset_top = 4.0
			hint.offset_bottom = 26.0
			hint.meta_clicked.connect(_on_kw_meta)
			b.add_child(hint)
		if locked:
			_style_die_button(b, d, false, true)
		elif _sel.has(d):
			_style_die_button(b, d, true, false)
		else:
			_style_die_button(b, d, false, false)
		b.disabled = not _human_active or locked
		b.pressed.connect(_on_die.bind(d))
		dice_row.add_child(b)
	var has_yc: bool = battle.players[0].yc_name != ""
	btn_yc.disabled = not _human_active or not has_yc
	if not has_yc:
		btn_yc.text = "无曜彩骰"
	elif not _human_active:
		btn_yc.text = "曜彩「%s」\n剩%d次" % [battle.players[0].yc_name, battle.players[0].yc_uses]
	else:
		var reason: String = battle.yaocai_reason(0, _phase)
		if reason == "":
			btn_yc.text = "曜彩「%s」\n剩%d次·可用" % [battle.players[0].yc_name, battle.players[0].yc_uses]
		else:
			btn_yc.text = "曜彩「%s」\n%s" % [battle.players[0].yc_name, reason]
	if not _human_active or not has_yc:
		yc_popup.visible = false
	if _phase == "attack":
		btn_reroll.text = "重投所选%d颗（剩%d次）" % [_sel.size(), battle.rerolls_left(0)]
		btn_reroll.disabled = not (_human_active and battle.rerolls_left(0) > 0 and _sel.size() >= 1)
	else:
		btn_reroll.text = "重投（防守方剩0次）"
		btn_reroll.disabled = true
	if _need > 0:
		btn_confirm.text = "确认选骰 %d/%d" % [_sel.size(), _need]
	else:
		btn_confirm.text = "确认选骰 %d/任意" % _sel.size()
	btn_confirm.disabled = not _human_active
	if battle.log.size() > 0:
		log_line.text = _log_text(battle.log[battle.log.size() - 1])

func _log_text(s: String) -> String:
	if s.begins_with("KO: player"):
		return "%s 被击倒！" % battle.players[int(s.right(1))].cfg.name
	if s.begins_with("yc roll p"):
		# 日志格式 "yc roll p<idx> <曜彩名> face<N>=<V>"（p0=人类），按序号归属，
		# 避免旧实现用名字 find 匹配在「人类无曜彩/双方同名曜彩」时误判
		return "%s投出了曜彩骰" % ("你" if s.get_slice(" ", 2) == "p0" else "敌方")
	return s

const SIDES_TEXT := {4: "四面", 6: "六面", 8: "八面", 12: "十二面"}

# 本回合待结算/生效中的状态（荆棘在结算开始才扣血，故需在信息条预告）
func _status_text(p: Dictionary) -> String:
	var parts: Array = []
	if p.thorns > 0:
		parts.append("荆棘%d（待结算）" % p.thorns)
	if p.field:
		parts.append("力场")
	if p.unyielding_round:
		parts.append("不屈")
	if p.poison > 0:
		parts.append("中毒%d" % p.poison)
	if p.strength.size() > 0:
		var total := 0
		for e in p.strength:
			total += e.n
		var tag: String = "（下回合）" if p.strength[0].expire == battle.round + 1 else ""
		parts.append("力量%d%s" % [total, tag])
	if p.leap_round:
		parts.append("跃升")
	return "、".join(parts)

# 选骰效果预览：已选组合触发的效果（金色，InfoLabel 汇总行）
func _refresh_preview() -> void:
	var p: Dictionary = battle.players[0]
	var triggered: Array = []
	var sum := 0
	for d in _sel:
		sum += d.value
	var ctx := {"flags": {}, "sel": _sel, "values": [], "atk_value": sum, "bonus": 0, "face_points": 0}
	for pas in p.cfg.passives:
		if pas.t != _phase and not (_phase == "attack" and pas.t == "attack_after"):
			continue
		if battle.eval_cond(pas.c, p, _sel, ctx):
			for fx in pas.fx:
				var t: String = _fx_text(fx)
				if not triggered.has(t):
					triggered.append(t)
	for d in _sel:
		if d.is_yaocai():
			for fx in GameData.YAOCAI[d.yaocai].faces[d.face].fx:
				var t2: String = _fx_text(fx)
				if not triggered.has(t2):
					triggered.append(t2)
	if triggered.size() > 0:
		info_label.text = (GlossaryPanel.kw_bbcode("预期效果：%s" % "、".join(triggered)))
		info_label.add_theme_color_override("default_color", Color(1.0, 0.84, 0.42))
	else:
		info_label.text = "预期效果：无"
		info_label.add_theme_color_override("default_color", Color(0.62, 0.66, 0.72))

# 逐骰效果提示（参照原作：骰子点数下方标注可能出现的效果）
# 规则：该骰凭借自身点数参与当前骰池即可达成条件时，标注对应效果；
# 计数类条件（少年班连击/洞穿）与满血/always 等与骰值无关的条件不标注
func _die_fx_hints(p: Dictionary, need: int) -> Dictionary:
	var result := {}
	if need <= 0:
		return result
	var pool: Array = p.dice.duplicate()
	var values: Array = []
	for d in pool:
		values.append(d.value)
	var group := {}
	for v in values:
		group[v] = group.get(v, 0) + 1
	var pairs_total := 0
	for v in group:
		pairs_total += int(group[v]) / 2
	for d in pool:
		if d.is_yaocai():
			continue
		var texts: Array = []
		for pas in p.cfg.passives:
			if pas.t != _phase and not (_phase == "attack" and pas.t == "attack_after"):
				continue
			var show := false
			match pas.c.t:
				"has_pair":
					show = group.get(d.value, 0) >= 2
				"pairs_ge":
					show = group.get(d.value, 0) >= 2 and pairs_total >= pas.c.n
				"all_eq_value":
					show = d.value == pas.c.v and group.get(pas.c.v, 0) >= need
				"not_all_eq_value":
					var has_non_v := false
					for x in values:
						if x != pas.c.v:
							has_non_v = true
					show = pool.size() >= need and has_non_v
				"all_even":
					var even := 0
					for x in values:
						if x % 2 == 0:
							even += 1
					show = d.value % 2 == 0 and even >= need
				"all_same":
					show = group.get(d.value, 0) >= need
				"sum_ge":
					var rest: Array = values.duplicate()
					rest.erase(d.value)
					rest.sort()
					var best := 0
					for i in range(maxi(0, rest.size() - (need - 1)), rest.size()):
						best += rest[i]
					show = d.value + best >= pas.c.n
			if show:
				for fx in pas.fx:
					var t: String = _fx_text(fx)
					if not texts.has(t):
						texts.append(t)
		if texts.size() > 0:
			result[d] = texts
	return result

func _die_text(d: Die) -> String:
	if d.is_yaocai():
		return "%s\n%d" % [d.yaocai, d.value]
	return "%s\n%d" % [SIDES_TEXT.get(d.sides, "%d面" % d.sides), d.value]

func _die_less(a: Die, b: Die) -> bool:
	if a.value != b.value:
		return a.value < b.value
	return (1 if a.is_yaocai() else 0) < (1 if b.is_yaocai() else 0)

func _is_mingding(d: Die) -> bool:
	if not d.is_yaocai():
		return false
	for fx in GameData.YAOCAI[d.yaocai].faces[d.face].fx:
		if fx.op == "mingding":
			return true
	return false

func _run() -> void:
	hp_hist = [[battle.players[0].hp], [battle.players[1].hp]]
	while battle.winner < 0 and battle.round <= 80:
		await _round_ui()
	if battle.winner < 0:
		# 达到回合上限仍未 KO：按 HP 判定胜者（与 driver.gd run_game 一致，避免误判人类输）
		battle.winner = 0 if battle.players[0].hp > battle.players[1].hp else 1
	var me: Dictionary = battle.players[0]
	var en: Dictionary = battle.players[1]
	_show_summary()
	await sum_btn.pressed
	get_tree().change_scene_to_file("res://scenes/select.tscn")

func _show_summary() -> void:
	var me: Dictionary = battle.players[0]
	var en: Dictionary = battle.players[1]
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.14, 0.17, 0.98)
	sb.border_color = Color(0.45, 0.48, 0.55)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sum_panel.add_theme_stylebox_override("panel", sb)
	sum_title.text = "对局结束：%s" % ("你赢了！" if battle.winner == 0 else "你输了")
	sum_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3) if battle.winner == 0 else Color(1.0, 0.4, 0.35))
	sum_stats.text = (GlossaryPanel.kw_bbcode(_summary_text()))
	sum_chart.h0 = hp_hist[0]
	sum_chart.h1 = hp_hist[1]
	sum_chart.max0 = me.hp_max
	sum_chart.max1 = en.hp_max
	sum_chart.queue_redraw()
	summary_view.visible = true

func _round_ui() -> void:
	battle.round_open()
	_en_rolled = false
	_en_committed = false
	refresh()
	var order := [[battle.attacker, "attack"], [1 - battle.attacker, "defense"]]
	for step in order:
		var idx: int = step[0]
		var phase: String = step[1]
		banner.text = "%s%s" % ["你" if idx == 0 else "敌方", "进攻" if phase == "attack" else "防御"]
		big.text = ""
		await _phase_ui(idx, phase)
	var def_idx: int = 1 - battle.attacker
	var hp_before: int = battle.players[def_idx].hp
	var s: Dictionary = battle.settle()
	var diff: int = maxi(0, s.atk - s.def)
	var note := ""
	if s.get("pierce", false):
		note = "（洞穿：无视防御）"
	elif s.dmg == 0 and diff > 0:
		note = "（力场挡下）"
	big.text = "攻击值 %d ｜ 防御值 %d\n差值 %d ｜ 实际伤害 %d%s\n守方生命 %d → %d" % [
		s.atk, s.def, diff, s.dmg, note, hp_before, battle.players[def_idx].hp]
	refresh()
	_hit_flash(enemy_hp if def_idx == 1 else player_hp, s.dmg + s.dmg2)
	_hit_flash(player_hp if def_idx == 1 else enemy_hp, s.counter)
	await _wait(2.0)
	battle.round_close()
	hp_hist[0].append(battle.players[0].hp)
	hp_hist[1].append(battle.players[1].hp)
	refresh()

func _phase_ui(idx: int, phase: String) -> void:
	battle.roll_phase(idx)
	if idx == 1:
		_en_rolled = true
	refresh()
	roll_view.visible = true
	if idx == 0:
		roller.roll(battle.players[0].dice, [])
	else:
		roller.roll([], battle.players[1].dice)
	await roller.finished
	roll_view.visible = false
	if idx == 0:
		await _human_phase(phase)
	else:
		await _ai_phase(idx, phase)

# 曜彩骰投掷的 3D 演出：普通骰在 _phase_ui 已有演出，曜彩骰此前只在 2D 行直接出现、无动画
func _animate_yaocai(idx: int) -> void:
	var yc_die: Die = null
	for d in battle.players[idx].dice:
		if d.is_yaocai():
			yc_die = d
			break
	if yc_die == null:
		return
	roll_view.visible = true
	if idx == 0:
		roller.roll([yc_die], [])
	else:
		roller.roll([], [yc_die])
	await roller.finished
	roll_view.visible = false

func _ai_phase(idx: int, phase: String) -> void:
	var p: Dictionary = battle.players[idx]
	if battle.yaocai_usable(idx, phase) and ai.choose_yaocai(p, phase):
		battle.roll_yaocai(idx, phase)
		refresh()
		await _animate_yaocai(idx)
	if phase == "attack":
		while battle.rerolls_left(idx) > 0:
			var picks: Array = ai.choose_reroll(p)
			if picks.is_empty():
				break
			battle.do_reroll(idx, picks)
			refresh()
			await _wait(0.5)
	var count: int = battle.selection_count(idx, phase)
	var sel: Array = ai.choose_selection(p, phase, count)
	battle.commit_selection(idx, phase, sel)
	_en_committed = true
	refresh()
	await _wait(0.5)

func _human_phase(phase: String) -> void:
	_phase = phase
	_sel.clear()
	_need = battle.selection_count(0, phase)
	_human_active = true
	refresh()
	await phase_confirmed
	_human_active = false
	refresh()

func _on_die(d: Die) -> void:
	if _is_mingding(d):
		return
	if _sel.has(d):
		_sel.erase(d)
	else:
		_sel.append(d)
	refresh()

func _on_kw_meta(meta: Variant) -> void:
	glossary.open(str(meta))

func _summary_text() -> String:
	# round_close 每回合结束都 round+=1（终局那回合也不例外），故实际打完的回合数 = battle.round - 1
	var lines: Array = ["总回合数 %d" % (battle.round - 1)]
	for i in [0, 1]:
		var p: Dictionary = battle.players[i]
		var st: Dictionary = battle.stats[i]
		var fx_parts: Array = []
		for op in st.fx:
			fx_parts.append("%s×%d" % [_fx_name(op), st.fx[op]])
		lines.append("%s（%s）：造成 %d 伤害｜承受 %d 伤害%s" % [
			p.cfg.name, "你" if i == 0 else "敌", st.dmg_dealt, st.dmg_taken,
			"" if fx_parts.size() == 0 else "\n　触发：%s" % "、".join(fx_parts)])
	lines.append("HP 曲线：蓝=你｜红=敌（横轴为回合）")
	return "\n".join(lines)

func _fx_name(op: String) -> String:
	match op:
		"combo": return "连击"
		"pierce": return "洞穿"
		"counter": return "反击"
		"hack": return "骇入"
		"instant", "instant_per_pair": return "瞬伤"
		"thorns": return "荆棘"
		"field": return "力场"
		"unyielding", "unyielding_once": return "不屈"
		"leech": return "虹吸"
		"heal", "heal_same": return "治愈"
		"upgrade_sel": return "升级"
		"strength", "strength_set": return "力量"
		"leap_perm": return "跃升"
		"yaocai": return "曜彩投掷"
		"reroll": return "重投"
		"atk_level_add", "atk_level_set": return "攻击等级变化"
		"def_level_add": return "防御等级变化"
	return op

class HpChart extends Control:
	var h0: Array = []
	var h1: Array = []
	var max0: int = 1
	var max1: int = 1

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.13, 0.14, 0.18))
		_line(h0, max0, Color(0.35, 0.75, 1.0))
		_line(h1, max1, Color(1.0, 0.45, 0.45))

	func _line(hist: Array, mx: int, col: Color) -> void:
		if hist.size() < 2 or mx <= 0:
			return
		var pts := PackedVector2Array()
		for i in range(hist.size()):
			var x: float = size.x * float(i) / float(hist.size() - 1)
			var y: float = size.y - size.y * float(hist[i]) / float(mx)
			pts.append(Vector2(x, y))
		draw_polyline(pts, col, 3.0)

func _on_yc() -> void:
	if not _human_active or battle.players[0].yc_name == "":
		return
	if yc_popup.visible:
		yc_popup.visible = false
		return
	var p: Dictionary = battle.players[0]
	yc_title.text = "曜彩「%s」" % p.yc_name
	yc_intro.text = (GlossaryPanel.kw_bbcode(GameData.YAOCAI[p.yc_name].intro))
	for c in yc_faces.get_children():
		c.queue_free()
	for f in GameData.YAOCAI[p.yc_name].faces:
		var l := RichTextLabel.new()
		var fx_text: String = _fx_list_text(f.fx) if f.fx.size() > 0 else "无效果"
		l.bbcode_enabled = true
		l.fit_content = true
		l.text = ("[center]%d点\n%s[/center]" % [f.points, GlossaryPanel.kw_bbcode(fx_text)])
		l.add_theme_font_size_override("normal_font_size", 24)
		l.meta_clicked.connect(_on_kw_meta)
		yc_faces.add_child(l)
	var reason: String = battle.yaocai_reason(0, _phase)
	yc_uses.text = "本局还可使用%d次" % p.yc_uses
	if reason != "":
		yc_uses.text += "\n当前不可用：%s" % reason
	yc_use_btn.disabled = reason != ""
	yc_popup.visible = true

func _on_yc_use() -> void:
	yc_popup.visible = false
	if battle.yaocai_usable(0, _phase):
		battle.roll_yaocai(0, _phase)
		_sel.clear()
		_human_active = false   # 演出期间锁定输入，避免动画中点选/确认
		refresh()
		await _animate_yaocai(0)
		_human_active = true
		refresh()

func _on_yc_close() -> void:
	yc_popup.visible = false

func _on_reroll() -> void:
	if _phase != "attack" or battle.rerolls_left(0) <= 0 or _sel.size() < 1:
		return
	battle.do_reroll(0, _sel.duplicate())
	refresh()

func _on_confirm() -> void:
	if _need > 0 and _sel.size() != _need:
		info_label.text = "必须恰好选 %d 颗！" % _need
		return
	if _need == 0 and _sel.size() < 1:
		info_label.text = "至少选 1 颗！"
		return
	battle.commit_selection(0, _phase, _sel.duplicate())
	refresh()
	phase_confirmed.emit()

func _hit_flash(lbl: Label, dmg: int) -> void:
	if dmg <= 0:
		return
	var tw := create_tween()
	tw.tween_property(lbl, "modulate", Color(1.0, 0.25, 0.2), 0.15)
	tw.tween_property(lbl, "modulate", Color.WHITE, 0.45)
	var f := Label.new()
	f.text = "-%d" % dmg
	f.add_theme_font_size_override("font_size", 44)
	f.add_theme_color_override("font_color", Color(1.0, 0.2, 0.15))
	add_child(f)
	f.global_position = lbl.global_position + Vector2(lbl.size.x + 12, -14)
	var tf := create_tween()
	tf.set_parallel(true)
	tf.tween_property(f, "global_position:y", f.global_position.y - 56, 0.9)
	tf.tween_property(f, "modulate:a", 0.0, 0.9)
	tf.chain().tween_callback(f.queue_free)
