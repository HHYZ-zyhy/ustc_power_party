extends Control

# 战斗界面：人类 = 玩家0，AI = 玩家1；异步编排 Battle 的分步 API

var battle: Battle
var rng: GameRng
var ai: AIController
var _phase: String = ""
var _human_active: bool = false
var _sel: Array = []
var _need: int = 0
var _en_rolled: bool = false
var _en_committed: bool = false
var _phase_done: bool = false   # 人类阶段是否已成功确认（_on_confirm 置 true）
var _roll_done: bool = false    # 当前投骰演出是否已收到 finished（看门狗用）
var _roll_cb: Callable         # 当前投骰的 finished 回调（超时/重入时断开，防串台）
var _leaving: bool = false      # 防止总结页重复切场景

@onready var enemy_name: Label = %EnemyName
@onready var enemy_hp: Label = %EnemyHp
@onready var enemy_hp_bar: ProgressBar = %EnemyHpBar
@onready var enemy_yc: Label = %EnemyYc
@onready var enemy_status: RichTextLabel = %EnemyStatus
@onready var enemy_passive: RichTextLabel = %EnemyPassive
@onready var enemy_dice: GridContainer = %EnemyDice
@onready var enemy_dice_label: Label = %EnemyDiceLabel
@onready var enemy_dice_block: VBoxContainer = %EnemyDiceBlock
@onready var enemy_dice_head: HBoxContainer = %EnemyDiceHead
@onready var enemy_dice_total: Label = %EnemyDiceTotal
@onready var enemy_bar: PanelContainer = $EnemyBar
@onready var player_bar: PanelContainer = $PlayerBar
@onready var banner: Label = %Banner
@onready var big: Label = %Big
@onready var info_label: RichTextLabel = %InfoLabel
@onready var player_passive: RichTextLabel = %PlayerPassive
@onready var player_name: Label = %PlayerName
@onready var player_hp: Label = %PlayerHp
@onready var player_hp_bar: ProgressBar = %PlayerHpBar
@onready var player_yc: Label = %PlayerYc
@onready var player_status: RichTextLabel = %PlayerStatus
@onready var dice_row: HBoxContainer = %DiceRow
@onready var dice_tip: Label = %DiceTip
@onready var btn_yc: Button = %BtnYc
@onready var btn_reroll: Button = %BtnReroll
@onready var btn_confirm: Button = %BtnConfirm
@onready var log_line: Label = %LogLine
@onready var round_label: Label = %RoundLabel
@onready var yc_dim: ColorRect = %YcDim
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
var roller: Node
var glossary: GlossaryPanel
var _badge_atk := {}   # idx -> Label：攻等级徽章（被动改等级后需随 refresh 更新）
var _badge_def := {}   # idx -> Label：防等级徽章
var _hit_seen: int = 0 # battle.hits 已消费到的位置（每次掉血只飘一次字/闪一次红）
var _die_views := {}   # Die -> DieView：玩家候选行池化，避免每次 refresh 重建 SubViewport
var _enemy_views := {} # Die -> DieView：敌方骰块（信息条框外）缩小行池化
var _primary: ButtonStyles

func _ready() -> void:
	rng = GameRng.new()
	ai = AIController.new()
	battle = Battle.new()
	# 直接运行 battle.tscn 调试时没有选卡结果：统一校验/回退（非法角色→physics，非法曜彩→推荐）
	GameStateData.sanitize()
	var ids: Array = GameData.CHARACTERS.keys()
	if ids.is_empty():
		_fail_to_select("战斗初始化失败：角色数据为空，正在返回选卡")
		return
	var others: Array = ids.duplicate()
	others.erase(GameStateData.char_id)
	# 只有一个角色时允许镜像对局，避免 randi_range(0, -1) 越界
	var ai_id: String = GameStateData.char_id
	if not others.is_empty():
		ai_id = str(others[rng.randi_range(0, others.size() - 1)])
	var ai_cfg: Dictionary = GameData.CHARACTERS[ai_id]
	var yc_keys: Array = GameData.YAOCAI.keys()
	var ai_yc: String = ""
	if int(ai_cfg.yc) > 0 and not yc_keys.is_empty():
		ai_yc = str(yc_keys[rng.randi_range(0, yc_keys.size() - 1)])
	if not battle.setup([GameStateData.char_id, ai_id], [GameStateData.yc_name, ai_yc], rng):
		_fail_to_select("战斗初始化失败：角色/曜彩配置非法，正在返回选卡")
		return
	_hit_seen = 0
	btn_yc.pressed.connect(_on_yc)
	btn_reroll.pressed.connect(_on_reroll)
	btn_confirm.pressed.connect(_on_confirm)
	yc_use_btn.pressed.connect(_on_yc_use)
	yc_close_btn.pressed.connect(_on_yc_close)
	yc_dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed \
				and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_hide_yc_popup())
	glossary = GlossaryPanel.new()
	add_child(glossary)
	for r in [info_label, enemy_status, player_status, enemy_passive, player_passive, yc_intro, sum_stats]:
		r.meta_clicked.connect(_on_kw_meta)
	roller = get_node("RollView/SubViewport/DiceRoll")
	_style_hp_bar(enemy_hp_bar)
	_style_hp_bar(player_hp_bar)
	_pad_info_bar(enemy_bar)
	_pad_info_bar(player_bar)
	_primary = ButtonStyles.new()
	_primary.apply_primary(sum_btn, true)
	sum_stats.add_theme_constant_override("table_h_separation", 28)
	sum_stats.add_theme_constant_override("table_v_separation", 6)
	get_viewport().size_changed.connect(func() -> void:
		_fit_yc_popup()
		_fit_sum_panel())
	_fit_yc_popup()
	_fit_sum_panel()
	_refresh_static()
	_run()

# 初始化失败（角色表为空/Battle.setup 拒绝）：不能停在无响应的战斗界面；
# 先显示原因，下一帧回选卡页（_ready 内直接切场景会释放当前节点，故延迟一帧）
func _fail_to_select(msg: String) -> void:
	push_error("battle_ui: " + msg)
	banner.text = msg
	big.text = ""
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var err: int = get_tree().change_scene_to_file("res://scenes/select.tscn")
	if err != OK:
		banner.text = "返回选卡失败（错误码 %d）" % err

func _style_hp_bar(bar: ProgressBar) -> void:
	bar.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.16, 0.09, 0.13)
	bg.border_color = Color(0.45, 0.20, 0.29)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = HP_RED
	fill.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("fill", fill)

# 信息栏复制主题 panel 样式后加内边距，保留原有底色/圆角；
# 同时裁切内容，避免将来更长的名字/文案越出黑色面板压到右侧按钮列
func _pad_info_bar(bar: PanelContainer) -> void:
	var sb: StyleBox = bar.get_theme_stylebox("panel").duplicate()
	sb.content_margin_left = INFO_PAD_X
	sb.content_margin_right = INFO_PAD_X
	sb.content_margin_top = INFO_PAD_Y
	sb.content_margin_bottom = INFO_PAD_Y
	bar.add_theme_stylebox_override("panel", sb)
	bar.clip_contents = true

# 帧驱动等待：不用 SceneTreeTimer（场景释放后它仍会 timeout，协程可能在已释放节点上恢复）。
# get_process_delta_time() 受 Engine.time_scale 影响，ui_stress 的 time_scale=10 仍能快进。
func _wait(sec: float) -> bool:
	var elapsed := 0.0
	while elapsed < sec:
		if not is_inside_tree():
			return false
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	return is_inside_tree()

func _fx_list_text(fx_arr: Array) -> String:
	var parts: Array = []
	for fx in fx_arr:
		parts.append(_fx_text(fx))
	return "、".join(parts)

func _fx_text(fx: Dictionary) -> String:
	match fx.op:
		# 无参数效果与战绩统计共用同一套中文名，避免两份文案漂移
		"combo", "pierce", "hack", "field", "unyielding", "unyielding_once", "counter", "mingding":
			return _fx_name(fx.op)
		"atk_add": return "攻击值+%d" % fx.n
		"upgrade_sel": return "升级所选骰"
		"instant": return "瞬伤%d" % fx.n
		"instant_per_pair": return "每对瞬伤%d" % fx.n
		"thorns": return "荆棘%d" % fx.n
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
	return fx.op

const BADGE_ATK_BG := Color(0.82, 0.32, 0.22)
const BADGE_DEF_BG := Color(0.23, 0.45, 0.80)

# HP 进度条（用户指定色 #E9517D）与掉血飘字的来源文案
const HP_RED := Color(0.914, 0.318, 0.490)
const HIT_KIND_TEXT := {
	"combo": "连击", "counter": "反击", "instant": "瞬伤", "thorns": "荆棘", "poison": "中毒",
}
const YC_POPUP_BASE := Vector2(580, 500)
const YC_POPUP_MARGIN := 40.0
const YC_POPUP_TOP := 100.0
const SUM_PANEL_BASE := Vector2(1040, 520)
const SUM_PANEL_MIN_H := 300.0
# 信息栏文字与深色面板边缘的呼吸空间（默认 panel 样式 content margin 为 0，文字贴边）
const INFO_PAD_X := 20.0
const INFO_PAD_Y := 8.0
# 敌方骰块在信息条框外、名字正下方：信息条只按名字/被动/状态内容收紧，不再为骰块预留高度
const ENEMY_BAR_EMPTY_MIN := 120.0
const ENEMY_BAR_FIT_PAD := 4.0
const ENEMY_DICE_GAP := 4.0
# 骰块每行最多 5 颗：5 颗仍不越过居中横幅文字，第 6 颗（曜彩骰）自动换第二行
const ENEMY_DICE_COLS := 5

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
	return mini(battle.def_eff(p) + p.def_pending, Battle.pool_count(p))

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
	player_hp_bar.max_value = maxi(1, me.hp_max)
	player_hp_bar.value = me.hp
	enemy_hp_bar.max_value = maxi(1, en.hp_max)
	enemy_hp_bar.value = en.hp
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
		# 回合收尾会移除曜彩骰，但 en.sel 要到下回合 round_open 才清空；
		# 只展示仍在骰池里的实体，避免「总计」把已消失的骰子算进去
		for d in en.sel:
			if en.dice.has(d):
				en_dice.append(d)
		en_dice.sort_custom(_die_less)
	elif _en_rolled or battle.round > 1:
		# 守方本回合尚未重投时，显示其上回合投出的骰子（同原作；第 1 回合无历史）
		en_dice = en.dice.duplicate()
		en_dice.sort_custom(_die_less)
	_sync_enemy_row(en, en_dice)
	var my_dice: Array = me.dice.duplicate()
	my_dice.sort_custom(_die_less)
	var fx_hints: Dictionary = _die_fx_hints(me, _need) if _human_active else {}
	_sync_dice_row(my_dice, fx_hints)
	var has_yc: bool = battle.players[0].yc_name != ""
	btn_yc.disabled = not _human_active or not has_yc
	if not has_yc:
		btn_yc.text = "无曜彩骰"
	elif not _human_active:
		btn_yc.text = "曜彩 %s\n剩%d次" % [battle.players[0].yc_name, battle.players[0].yc_uses]
	else:
		var reason: String = battle.yaocai_reason(0, _phase)
		if reason == "":
			btn_yc.text = "曜彩 %s\n剩%d次·可用" % [battle.players[0].yc_name, battle.players[0].yc_uses]
		else:
			btn_yc.text = "曜彩 %s\n%s" % [battle.players[0].yc_name, reason]
	if not _human_active or not has_yc:
		_hide_yc_popup()
	if not _human_active:
		btn_reroll.text = "重投"
		btn_reroll.disabled = true
	elif _phase == "attack":
		btn_reroll.text = "重投所选%d颗\n（剩%d次）" % [_sel.size(), battle.rerolls_left(0)]
		btn_reroll.disabled = not (battle.rerolls_left(0) > 0 and _sel.size() >= 1)
	else:
		btn_reroll.text = "重投\n防守方剩0次"
		btn_reroll.disabled = true
	if not _human_active:
		btn_confirm.text = "确认选骰"
	elif _need > 0:
		btn_confirm.text = "确认选骰 %d/%d" % [_sel.size(), _need]
	else:
		btn_confirm.text = "确认选骰 %d/任意" % _sel.size()
	# 选够才能确认：按钮直接置灰，比点了以后再报错更直观
	var sel_ok: bool = (_sel.size() == _need) if _need > 0 else (_sel.size() >= 1)
	btn_confirm.disabled = not _human_active or not sel_ok
	_primary.apply_primary(btn_confirm, not btn_confirm.disabled)
	if _human_active and not sel_ok:
		btn_confirm.tooltip_text = ("需选 %d 颗" % _need) if _need > 0 else "至少选 1 颗"
	else:
		btn_confirm.tooltip_text = ""
	_update_dice_tip()
	if battle.log.size() > 0:
		log_line.text = _log_text(battle.log[battle.log.size() - 1])
	_flush_hits()

# 候选骰上方的操作提示：明确「3D 骰可直接点」，并实时显示已选/需选数量
func _update_dice_tip() -> void:
	if not _human_active:
		dice_tip.text = ""
		dice_tip.add_theme_color_override("font_color", Color(0.72, 0.74, 0.80))
		return
	var need_txt: String = ("需选 %d 颗" % _need) if _need > 0 else "任意数量，至少 1 颗"
	var sel_ok: bool = (_sel.size() == _need) if _need > 0 else (_sel.size() >= 1)
	dice_tip.text = "点击骰子选择/取消 · 已选 %d 颗（%s）%s" % [
		_sel.size(), need_txt, "· 可以确认" if sel_ok else ""]
	dice_tip.add_theme_color_override("font_color",
		Color(1.0, 0.85, 0.3) if sel_ok else Color(0.72, 0.74, 0.80))

# 按 Die 对象池化 DieView：玩家候选行与敌方行共用创建/复用逻辑，避免两处各写一份
func _obtain_view(cache: Dictionary, parent: Node, d: Die, enemy: bool) -> DieView:
	var v: DieView = cache.get(d)
	if v == null:
		v = DieView.new()
		cache[d] = v
		parent.add_child(v)
		if enemy:
			v.setup_enemy(d)
		else:
			v.setup(d)
			v.die_pressed.connect(_on_die)
		v.keyword_clicked.connect(_on_kw_meta)
	else:
		v.set_die(d)
	return v

func _prune_views(cache: Dictionary, parent: Node, live: Dictionary) -> void:
	for d in cache.keys().duplicate():
		if not live.has(d):
			var v: DieView = cache[d]
			cache.erase(d)
			parent.remove_child(v)
			v.queue_free()

# 玩家候选骰行：按 Die 对象池化 DieView，refresh 只更新点数/面/选中/锁定/提示，
# 不重建 SubViewport（每次点选都重建 World3D 会掉帧并闪烁）
func _sync_dice_row(my_dice: Array, fx_hints: Dictionary) -> void:
	var live := {}
	for i in range(my_dice.size()):
		var d: Die = my_dice[i]
		live[d] = true
		var v: DieView = _obtain_view(_die_views, dice_row, d, false)
		var locked: bool = _is_mingding(d)
		v.set_locked(locked)
		v.set_selected(_sel.has(d))
		v.set_interactive(_human_active and not locked)
		v.set_dimmed(not _human_active)
		v.set_hint(_dice_hint_bbcode(d, fx_hints))
		v.set_tooltip(_die_text(d))
		dice_row.move_child(v, i)
	_prune_views(_die_views, dice_row, live)

# 敌方骰块（信息条框外、名字正下方；玩家候选行的缩小版，不可点击）：p.dice 全部保留视图，
# 只显示本回合应展示的骰子（已提交=所选；否则=上回合/本回合投出）
func _sync_enemy_row(en: Dictionary, shown: Array) -> void:
	var shown_set := {}
	for d in shown:
		shown_set[d] = true
	var live := {}
	var all_dice: Array = en.dice
	for d in all_dice:
		live[d] = true
		var v: DieView = _obtain_view(_enemy_views, enemy_dice, d, true)
		v.set_interactive(false)
		v.set_dimmed(false)
		v.set_selected(false)
		v.set_locked(false)
		v.set_hint(_dice_hint_bbcode(d, {}))
		v.set_tooltip(_die_text(d))
	_prune_views(_enemy_views, enemy_dice, live)
	var pos := 0
	for d in shown:
		var v: DieView = _enemy_views.get(d)
		if v != null:
			enemy_dice.move_child(v, pos)
			if not v.visible:
				v.visible = true
				v.arm_render()   # 隐藏期间没有渲染，重新显示时补一帧
			pos += 1
	for d in all_dice:
		if not shown_set.has(d):
			var v: DieView = _enemy_views.get(d)
			if v != null:
				enemy_dice.move_child(v, pos)
				v.visible = false
				pos += 1
	if _en_committed and shown.size() > 0:
		enemy_dice_total.text = "总计 %d" % Battle.dice_sum(shown)
		enemy_dice_total.visible = true
	else:
		enemy_dice_total.visible = false
	# 敌方骰块来源提示：本回合已提交 / 上回合残留 / 本回合已投
	if shown.is_empty():
		enemy_dice_label.text = ""
	elif _en_committed:
		enemy_dice_label.text = "敌方所选"
	elif not _en_rolled and battle.round > 1:
		enemy_dice_label.text = "敌方上回合"
	else:
		enemy_dice_label.text = "敌方骰子"
	# 信息条只按内容收紧（名字/HP 行 + 被动/状态），骰块移到框外、与名字左对齐
	var fit_h: float = enemy_bar.get_combined_minimum_size().y + ENEMY_BAR_FIT_PAD
	var bar_bottom: float = enemy_bar.offset_top + maxf(ENEMY_BAR_EMPTY_MIN, fit_h)
	enemy_bar.offset_bottom = bar_bottom
	# 骰块：框外名字正下方，最多 5 列；第 6 颗（曜彩骰）换第二行，块宽不越过居中横幅文字
	var n: int = shown.size()
	enemy_dice_label.visible = n > 0
	var h_sep: float = float(enemy_dice.get_theme_constant("h_separation"))
	var v_sep: float = float(enemy_dice.get_theme_constant("v_separation"))
	var rows: int = 0 if n == 0 else int(ceil(float(n) / float(ENEMY_DICE_COLS)))
	var full_cols: int = mini(n, ENEMY_DICE_COLS)
	var grid_w: float = float(full_cols) * DieView.ENEMY_SIZE.x + float(maxi(0, full_cols - 1)) * h_sep
	var head_min: Vector2 = enemy_dice_head.get_combined_minimum_size()
	var block_w: float = maxf(grid_w, head_min.x)
	var block_h: float = head_min.y + float(enemy_dice_block.get_theme_constant("separation")) \
		+ float(rows) * DieView.ENEMY_SIZE.y + float(maxi(0, rows - 1)) * v_sep
	enemy_dice_block.visible = n > 0
	if n > 0:
		enemy_dice_block.offset_left = enemy_bar.offset_left + INFO_PAD_X
		enemy_dice_block.offset_right = enemy_dice_block.offset_left + clampf(block_w, DieView.ENEMY_SIZE.x, 680.0)
		enemy_dice_block.offset_top = bar_bottom + ENEMY_DICE_GAP
		enemy_dice_block.offset_bottom = enemy_dice_block.offset_top + block_h

# 骰子下方提示：类型/曜彩名用灰紫小字，效果词沿用效果显示的金色可点击链接
func _dice_hint_bbcode(d: Die, fx_hints: Dictionary) -> String:
	if d.is_yaocai():
		var faces: Array = GameData.YAOCAI[d.yaocai].faces
		var fi: int = clampi(d.face, 0, faces.size() - 1)
		var fx_arr: Array = faces[fi].fx
		var head := "[color=#cabaff]%s[/color]" % d.yaocai
		if fx_arr.is_empty():
			return "%s · [color=#aab0c0]无效果[/color]" % head
		return "%s · %s" % [head, GlossaryPanel.kw_bbcode(_fx_list_text(fx_arr))]
	var head := "[color=#b6bccb]%s[/color]" % _die_head(d)
	if fx_hints.has(d) and not (fx_hints[d] as Array).is_empty():
		return "%s · %s" % [head, GlossaryPanel.kw_bbcode("、".join(fx_hints[d]))]
	return head

# 演出期间锁骰：不改 _sel，只禁用点击并把骰子调暗（不重建视图）
func _set_dice_input(on: bool) -> void:
	for d in _die_views:
		var v: DieView = _die_views[d]
		v.set_interactive(on and not _is_mingding(d))
		v.set_dimmed(not on)

func _arm_views(cache: Dictionary) -> void:
	for v in cache.values():
		(v as DieView).arm_render()

func _log_text(s: String) -> String:
	var out: String = s
	if s.begins_with("KO: player"):
		out = "%s 被击倒！" % battle.players[int(s.right(1))].cfg.name
	elif s.begins_with("yc roll p"):
		# 日志格式 "yc roll p<idx> <曜彩名> face<N>=<V>"（p0=人类），按序号归属，
		# 避免旧实现用名字 find 匹配在「人类无曜彩/双方同名曜彩」时误判
		out = "%s投出了曜彩骰" % ("你" if s.get_slice(" ", 2) == "p0" else "敌方")
	# 单独一行居中显示，加前缀避免被误认成骰行标签
	return "战报｜" + out

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
		var tag: String = "（下回合）" if p.strength[0].expire == battle.round + 1 else ""
		parts.append("力量%d%s" % [battle.strength_total(p), tag])
	if p.leap_round:
		parts.append("跃升")
	return "、".join(parts)

# 当前阶段生效的被动：攻击后（attack_after）只在攻击阶段的预览/提示里展示
func _phase_passives(p: Dictionary) -> Array:
	var out: Array = []
	for pas in p.cfg.passives:
		if pas.t == _phase or (_phase == "attack" and pas.t == "attack_after"):
			out.append(pas)
	return out

# 选骰效果预览：已选组合触发的效果（金色，InfoLabel 汇总行）
func _refresh_preview() -> void:
	var p: Dictionary = battle.players[0]
	var triggered: Array = []
	# 预期效果按实际攻击值判定（含已有力量层数；网安「攻击值≥19」等条件在选骰时就要看准）
	var ctx := {"flags": {}, "sel": _sel, "values": [], "atk_value": Battle.dice_sum(_sel) + battle.strength_total(p), "bonus": 0, "face_points": 0}
	for pas in _phase_passives(p):
		if Battle.eval_cond(pas.c, p, _sel, ctx):
			for fx in pas.fx:
				_push_preview_fx(triggered, fx)
	for d in _sel:
		if d.is_yaocai():
			for fx in GameData.YAOCAI[d.yaocai].faces[d.face].fx:
				_push_preview_fx(triggered, fx)
	if triggered.size() > 0:
		info_label.text = "[center]%s[/center]" % GlossaryPanel.kw_bbcode("预期效果：%s" % "、".join(triggered))
		info_label.add_theme_color_override("default_color", Color(1.0, 0.84, 0.42))
	else:
		info_label.text = "[center]预期效果：无[/center]"
		info_label.add_theme_color_override("default_color", Color(0.62, 0.66, 0.72))

# 预期效果入列：连击可多来源叠加，显示为「连击×N」；其余效果仍去重
func _push_preview_fx(arr: Array, fx: Dictionary) -> void:
	var t: String = _fx_text(fx)
	if fx.op == "combo":
		# 必须按前缀找已有的「连击/连击×N」；旧实现直接 find("连击")，到第 3 个来源
		# 就找不到「连击×2」而重复追加一条「连击」
		for i in range(arr.size()):
			var s: String = arr[i]
			if s.begins_with("连击"):
				var n: int = 1 if s == "连击" else int(s.substr(3))
				arr[i] = "连击×%d" % (n + 1)
				return
		arr.append("连击")
		return
	if not arr.has(t):
		arr.append(t)

# 逐骰效果提示（参照原作：骰子点数下方标注可能出现的效果）
# 只标注「该骰参与某个刚好 need 颗的选择即可触发」的骰值相关被动；条件判定直接复用
# Battle.eval_cond，避免与结算逻辑出现两套口径。命定骰必须入选，作为固定成员参与穷举。
# 计数类（少年班连击/洞穿）与满血/always 等与骰值无关的条件不标注，避免每颗骰都挂提示。
const HINT_COND_TYPES := ["has_pair", "pairs_ge", "all_eq_value", "not_all_eq_value", "all_even", "all_same", "sum_ge"]

func _die_fx_hints(p: Dictionary, need: int) -> Dictionary:
	var result := {}
	if need <= 0 or need > p.dice.size():
		return result
	var mandatory: Array = []
	for d in p.dice:
		if _is_mingding(d):
			mandatory.append(d)
	if mandatory.size() > need:
		return result
	var strength: int = battle.strength_total(p)
	for d in p.dice:
		if d.is_yaocai():
			continue
		var fixed: Array = [d]
		for m in mandatory:
			if not fixed.has(m):
				fixed.append(m)
		var slots: int = need - fixed.size()
		if slots < 0:
			continue
		var rest: Array = []
		for x in p.dice:
			if not fixed.has(x):
				rest.append(x)
		if slots > rest.size():
			continue
		var combos: Array = AIController.combinations(rest, slots)
		var texts: Array = []
		for pas in _phase_passives(p):
			if not HINT_COND_TYPES.has(pas.c.t):
				continue
			var hit := false
			for extra in combos:
				var sel: Array = fixed.duplicate()
				sel.append_array(extra)
				if Battle.eval_cond(pas.c, p, sel, {"atk_value": Battle.dice_sum(sel) + strength}):
					hit = true
					break
			if not hit:
				continue
			for fx in pas.fx:
				var t: String = _fx_text(fx)
				if not texts.has(t):
					texts.append(t)
		if not texts.is_empty():
			result[d] = texts
	return result

func _die_head(d: Die) -> String:
	return d.yaocai if d.is_yaocai() else GameData.SIDES_TEXT.get(d.sides, "%d面" % d.sides)

func _die_text(d: Die) -> String:
	return "%s\n%d" % [_die_head(d), d.value]

func _die_less(a: Die, b: Die) -> bool:
	if a.value != b.value:
		return a.value < b.value
	return (1 if a.is_yaocai() else 0) < (1 if b.is_yaocai() else 0)

func _is_mingding(d: Die) -> bool:
	return battle.is_mingding(d)

func _run() -> void:
	while battle.winner < 0 and battle.round <= 80:
		await _round_ui()
		if not is_inside_tree():
			return
	if not is_inside_tree():
		return
	if battle.winner < 0:
		# 达到回合上限仍未 KO：按 HP 判定胜者（与 driver.gd run_game 一致，避免误判人类输）
		battle.winner = 0 if battle.players[0].hp > battle.players[1].hp else 1
	await _show_summary()
	if not is_inside_tree():
		return
	# 允许返回失败后重试；_leaving 防止切场景过程中重复触发
	while is_inside_tree():
		await sum_btn.pressed
		if _leaving or not is_inside_tree():
			return
		_leaving = true
		var err: int = get_tree().change_scene_to_file("res://scenes/select.tscn")
		if err == OK:
			return
		_leaving = false
		sum_title.text = "返回选卡失败（错误码 %d），请再点一次" % err

func _show_summary() -> void:
	_hide_yc_popup()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.14, 0.17, 1.0)
	sb.border_color = Color(0.45, 0.48, 0.55)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sum_panel.add_theme_stylebox_override("panel", sb)
	sum_title.text = "对局结束：%s" % ("你赢了！" if battle.winner == 0 else "你输了")
	sum_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3) if battle.winner == 0 else Color(1.0, 0.4, 0.35))
	sum_stats.text = (GlossaryPanel.kw_bbcode(_summary_text()))
	summary_view.visible = true
	# 先让面板以目标宽度完成一次布局：RichTextLabel 在宽度 1px 时 fit_content 会把最小高度
	# 算成逐字竖排的 1700+px；布局后再按实际换行高度收面板，避免固定 520px 的中部空白
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_fit_sum_panel()

func _round_ui() -> void:
	battle.round_open()
	_sel.clear()   # 上回合的高亮不带到新回合（human_phase 开始时会再清一次）
	_en_rolled = false
	_en_committed = false
	refresh()
	var order := [[battle.attacker, "attack"], [1 - battle.attacker, "defense"]]
	var def_skipped := false
	for step in order:
		# 攻方 commit 阶段的瞬伤可能已击倒守方：不再给已阵亡方显示防御回合
		if battle.winner >= 0:
			def_skipped = true
			break
		var idx: int = step[0]
		var phase: String = step[1]
		banner.text = "%s%s" % ["你" if idx == 0 else "敌方", "进攻" if phase == "attack" else "防御"]
		big.text = ""
		await _phase_ui(idx, phase)
		if not is_inside_tree():
			return
	var def_idx: int = 1 - battle.attacker
	var hp_before: int = battle.players[def_idx].hp
	var ended_early: bool = battle.winner >= 0
	var s: Dictionary = battle.settle()
	var hp_after: int = battle.players[def_idx].hp
	var lost: int = maxi(0, hp_before - hp_after)
	var diff: int = maxi(0, s.atk - s.def)
	var settled_ko: bool = battle.winner >= 0
	var notes: Array = _settle_notes(def_skipped, ended_early, settled_ko, s, diff)
	var note := "" if notes.is_empty() else "（%s）" % "、".join(notes)
	# 「主伤害」= 结算公式算出的名义伤害（溢出击杀、不屈保命时会高于实际掉血）；
	# 「共掉血」= HP 差值（含连击/荆棘/中毒），与掉血飘字、战绩统计同口径
	big.text = "攻击值 %d ｜ 防御值 %d\n差值 %d ｜ 主伤害 %d%s\n守方生命 %d → %d（共掉血 %d）" % [
		s.atk, s.def, diff, s.dmg, note, hp_before, hp_after, lost]
	refresh()
	if not await _wait(2.0):
		return
	if not battle.round_close():
		push_warning("battle_ui: round_close 被拒绝（round=%d）" % battle.round)
	refresh()

# 结算横幅注记：区分「防御阶段已跳过」「commit 已分胜负」「结算中（荆棘/中毒等）分出胜负」
# 与「力场挡下」——后三种都会让主伤害为 0，不能仅凭 dmg==0 判定为力场
func _settle_notes(def_skipped: bool, ended_early: bool, settled_ko: bool, s: Dictionary, diff: int) -> Array:
	var notes: Array = []
	if def_skipped:
		notes.append("守方已被击倒，防御阶段跳过")
	elif ended_early:
		notes.append("攻方已被击倒，伤害不再结算")
	elif settled_ko and s.dmg == 0 and s.get("dmg2", 0) == 0 and s.get("counter", 0) == 0:
		notes.append("结算中已分出胜负，主伤害未造成")
	elif s.get("pierce", false):
		notes.append("洞穿：无视防御")
	elif s.dmg == 0 and diff > 0:
		notes.append("力场挡下")
	if s.get("dmg2", 0) > 0:
		var combo_n: int = int(s.get("combo_n", 1))
		if combo_n > 1:
			notes.append("连击 %d（%d 段）" % [s.dmg2, combo_n])
		else:
			notes.append("连击 %d" % s.dmg2)
	return notes

func _phase_ui(idx: int, phase: String) -> void:
	battle.roll_phase(idx)
	if idx == 1:
		_en_rolled = true
	# 投骰演出期间隐藏对应骰行，避免静态 3D 骰提前露出停骰结果（演出与重投共用 _animate_roll）
	var row: Control = dice_row if idx == 0 else enemy_dice
	row.visible = false
	refresh()
	if not await _animate_roll(battle.players[idx].dice, idx):
		return
	if idx == 0:
		await _human_phase(phase)
	else:
		await _ai_phase(idx, phase)

# 单次投骰/重投演出：只把传入的骰子放进 3D 视口；重投走 quick 短版动画
# 返回 false 表示节点已离开场景树（调用方应立即收手）；动画超时则强制继续并返回 true
func _animate_roll(dice: Array, idx: int, quick: bool = false) -> bool:
	var row: Control = dice_row if idx == 0 else enemy_dice
	row.visible = false
	if idx == 1:
		enemy_dice_label.visible = false   # 骰行隐藏时标题也别悬在空处
	if dice.is_empty():
		row.visible = true
		if idx == 1:
			enemy_dice_label.visible = enemy_dice_label.text != ""
		return is_inside_tree()
	roll_view.visible = true
	if idx == 0:
		roller.roll(dice, [], quick)
	else:
		roller.roll([], dice, quick)
	# 看门狗：dice_roll 异常/信号丢失时不能让整个回合永久等待
	_roll_done = false
	_roll_cb = func() -> void: _roll_done = true
	roller.finished.connect(_roll_cb, CONNECT_ONE_SHOT)
	var elapsed := 0.0
	while not _roll_done and elapsed < 8.0:
		if not is_inside_tree():
			if roller.finished.is_connected(_roll_cb):
				roller.finished.disconnect(_roll_cb)
			return false
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	if roller.finished.is_connected(_roll_cb):
		roller.finished.disconnect(_roll_cb)
	if not _roll_done:
		push_warning("battle_ui: 投骰演出超时，强制继续")
	roll_view.visible = false
	row.visible = true
	if idx == 1:
		enemy_dice_label.visible = enemy_dice_label.text != ""
	_arm_views(_die_views if idx == 0 else _enemy_views)
	return is_inside_tree()

# 曜彩骰投掷的 3D 演出：普通骰在 _phase_ui 已有演出，曜彩骰此前只在 2D 行直接出现、无动画
func _animate_yaocai(idx: int) -> bool:
	var yc_die: Die = null
	for d in battle.players[idx].dice:
		if d.is_yaocai():
			yc_die = d
			break
	if yc_die == null:
		return true
	var ok: bool = await _animate_roll([yc_die], idx)
	return ok

func _ai_phase(idx: int, phase: String) -> void:
	var p: Dictionary = battle.players[idx]
	if battle.yaocai_usable(idx, phase) and ai.choose_yaocai(p, phase):
		if battle.roll_yaocai(idx, phase):
			refresh()
			if not await _animate_yaocai(idx):
				return
	if phase == "attack":
		while battle.rerolls_left(idx) > 0:
			var picks: Array = ai.choose_reroll(p)
			if picks.is_empty():
				break
			# do_reroll 会把命定曜彩骰强制加入并返回实际重投集合，演出必须用它
			picks = battle.do_reroll(idx, picks)
			if picks.is_empty():
				break
			if not await _animate_roll(picks, idx, true):
				return
			refresh()
	var count: int = battle.selection_count(idx, phase)
	var sel: Array = ai.choose_selection(p, phase, count)
	if not battle.commit_selection(idx, phase, sel):
		# AI 选骰异常时用空选兜底（commit 会自动补足/截断），避免整局在没有有效提交的情况下结算
		push_warning("battle_ui: AI commit 被拒绝（idx=%d phase=%s），改用空选兜底" % [idx, phase])
		if not battle.commit_selection(idx, phase, []):
			push_error("battle_ui: AI 空选兜底仍被拒绝（idx=%d phase=%s）" % [idx, phase])
	_en_committed = true
	refresh()
	if not await _wait(0.5):
		return

func _human_phase(phase: String) -> void:
	_phase = phase
	_sel.clear()
	_need = battle.selection_count(0, phase)
	_phase_done = false
	_human_active = true
	refresh()
	# 不直接 await 信号：confirm 失败/节点释放/winner 已定时也要能退出，避免永久软锁
	while not _phase_done and battle.winner < 0 and is_inside_tree():
		await get_tree().process_frame
	_human_active = false
	if is_inside_tree():
		refresh()   # 场景已释放时不得再刷 UI（会创建 Tween/触发延迟渲染）

func _on_die(d: Die) -> void:
	if not _human_active:
		return
	if _is_mingding(d):
		return
	if _sel.has(d):
		_sel.erase(d)
	else:
		_sel.append(d)
	refresh()

func _on_kw_meta(meta: Variant) -> void:
	glossary.open(str(meta))

# Esc 关闭当前弹窗（曜彩/效果显示）；不抢占按钮的鼠标操作
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo or key.keycode != KEY_ESCAPE:
		return
	if yc_popup.visible:
		_hide_yc_popup()
		get_viewport().set_input_as_handled()
	elif glossary != null and glossary.visible:
		glossary.visible = false
		get_viewport().set_input_as_handled()

func _summary_text() -> String:
	# round_close 每回合结束都 round+=1（终局那回合也不例外），故实际打完的回合数 = battle.round - 1
	# 用 BBCode 表格固定三列，避免名字长短不同导致「造成/承受」数字错位
	var lines: Array = [
		"总回合数 %d" % (battle.round - 1),
		"[table=3,3]",
		"[cell][color=#9aa0ad]玩家[/color][/cell]"
		+ "[cell][color=#9aa0ad]造成伤害[/color][/cell]"
		+ "[cell][color=#9aa0ad]承受伤害[/color][/cell]",
	]
	for i in [0, 1]:
		var p: Dictionary = battle.players[i]
		var st: Dictionary = battle.stats[i]
		var fx_parts: Array = []
		for op in st.fx:
			fx_parts.append("%s×%d" % [_fx_name(op), st.fx[op]])
		var name_text: String = "%s（%s）" % [p.cfg.name, "你" if i == 0 else "敌"]
		if fx_parts.size() > 0:
			name_text += "\n[color=#9aa0ad]　触发：%s[/color]" % "、".join(fx_parts)
		lines.append("[cell]%s[/cell][cell][color=#ffb366]%d[/color][/cell][cell]%d[/cell]" % [
			name_text, st.dmg_dealt, st.dmg_taken])
	lines.append("[/table]")
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
		"atk_add": return "攻击值加成"
		"mingding": return "命定"
		"yaocai_use_add": return "曜彩次数增加"
		"yaocai": return "曜彩投掷"
		"reroll": return "重投"
		"atk_level_add", "atk_level_set": return "攻击等级变化"
		"def_level_add": return "防御等级变化"
	return op

# 曜彩弹窗窄窗口适配：基准 580×500，右缘 40px 固定；窗口变窄时整体收窄，
# 六面卡片从 3 列降为 2/1 列并同步降低卡片最小宽度，避免固定尺寸把弹窗顶出屏幕
func _fit_yc_popup(vp: Vector2 = Vector2.ZERO) -> void:
	vp = _viewport_size(vp)
	var w: float = minf(YC_POPUP_BASE.x, maxf(vp.x - YC_POPUP_MARGIN * 2.0, 240.0))
	var h: float = minf(YC_POPUP_BASE.y, maxf(vp.y - YC_POPUP_TOP - YC_POPUP_MARGIN, 220.0))
	yc_popup.offset_left = -YC_POPUP_MARGIN - w
	yc_popup.offset_right = -YC_POPUP_MARGIN
	yc_popup.offset_top = YC_POPUP_TOP
	yc_popup.offset_bottom = YC_POPUP_TOP + h
	var cols: int = 3
	if w < 520.0:
		cols = 2
	if w < 360.0:
		cols = 1
	yc_faces.columns = cols
	var cell_w: float = minf(170.0, (w - 48.0 - 10.0 * float(cols - 1)) / float(cols))
	cell_w = maxf(90.0, cell_w)
	for c in yc_faces.get_children():
		if c is Control:
			(c as Control).custom_minimum_size = Vector2(cell_w, 94.0)

# 战绩面板：宽度基准 1040 居中；高度取内容最小高度（上限 520），
# 避免固定高度在战绩行数少时留下大片空白，窄窗口下同时受视口约束
func _fit_sum_panel(vp: Vector2 = Vector2.ZERO) -> void:
	vp = _viewport_size(vp)
	var w: float = minf(SUM_PANEL_BASE.x, maxf(vp.x - 48.0, 320.0))
	var max_h: float = minf(SUM_PANEL_BASE.y, maxf(vp.y - 48.0, 240.0))
	var content_h: float = sum_panel.get_combined_minimum_size().y
	var h: float = clampf(content_h, minf(SUM_PANEL_MIN_H, max_h), max_h)
	sum_panel.offset_left = -w * 0.5
	sum_panel.offset_right = w * 0.5
	sum_panel.offset_top = -h * 0.5
	sum_panel.offset_bottom = h * 0.5

func _viewport_size(vp: Vector2) -> Vector2:
	return get_viewport_rect().size if vp == Vector2.ZERO else vp

func _on_yc() -> void:
	if not _human_active or battle.players[0].yc_name == "":
		return
	if yc_popup.visible:
		_hide_yc_popup()
		return
	var p: Dictionary = battle.players[0]
	yc_title.text = "曜彩「%s」" % p.yc_name
	yc_intro.text = (GlossaryPanel.kw_bbcode(GameData.YAOCAI[p.yc_name].intro))
	for c in yc_faces.get_children():
		yc_faces.remove_child(c)
		c.queue_free()
	for f in GameData.YAOCAI[p.yc_name].faces:
		yc_faces.add_child(_make_face_cell(f))
	_fit_yc_popup()
	var reason: String = battle.yaocai_reason(0, _phase)
	yc_uses.text = "本局还可使用%d次" % p.yc_uses
	if reason != "":
		yc_uses.text += "\n当前不可用：%s" % reason
	yc_use_btn.disabled = reason != ""
	_primary.apply_primary(yc_use_btn, not yc_use_btn.disabled)
	yc_dim.visible = true
	yc_popup.visible = true

# 曜彩六面表：每面一张卡片（点数 + 效果）。此前用 fit_content 的 RichTextLabel 直接塞进
# GridContainer，最小宽度为 0，被挤成一字一列的竖条，六面内容完全看不出来
func _make_face_cell(f: Dictionary) -> Control:
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(170, 94)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.10, 0.15, 0.95)
	sb.border_color = Color(0.55, 0.45, 0.95) if f.fx.size() > 0 else Color(0.33, 0.34, 0.42)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	cell.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	cell.add_child(box)
	var pts := Label.new()
	pts.text = "%d点" % f.points
	pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pts.add_theme_font_size_override("font_size", 32)
	pts.add_theme_color_override("font_color", Color(0.93, 0.94, 0.98))
	box.add_child(pts)
	var fx_text: String = _fx_list_text(f.fx) if f.fx.size() > 0 else "无效果"
	var fx := RichTextLabel.new()
	fx.bbcode_enabled = true
	fx.fit_content = true
	fx.scroll_active = false
	fx.text = ("[center]%s[/center]" % GlossaryPanel.kw_bbcode(fx_text))
	fx.add_theme_font_size_override("normal_font_size", 20)
	fx.add_theme_color_override("default_color",
		Color(1.0, 0.85, 0.4) if f.fx.size() > 0 else Color(0.62, 0.62, 0.62))
	fx.meta_clicked.connect(_on_kw_meta)
	box.add_child(fx)
	return cell

func _on_yc_use() -> void:
	if not _human_active:
		return
	_hide_yc_popup()
	if battle.yaocai_usable(0, _phase):
		if not battle.roll_yaocai(0, _phase):
			return
		_sel.clear()
		_human_active = false   # 演出期间锁定输入，避免动画中点选/确认
		refresh()
		if not await _animate_yaocai(0):
			return
		if not is_inside_tree():
			return
		_human_active = battle.winner < 0
		refresh()

func _hide_yc_popup() -> void:
	yc_popup.visible = false
	yc_dim.visible = false

func _on_yc_close() -> void:
	_hide_yc_popup()

func _on_reroll() -> void:
	if not _human_active or battle.winner >= 0:
		return
	if _phase != "attack" or battle.rerolls_left(0) <= 0 or _sel.size() < 1:
		return
	var picks: Array = battle.do_reroll(0, _sel.duplicate())
	if picks.is_empty():
		return
	_human_active = false   # 演出期间锁输入，避免动画中点选/确认
	# 不立即 refresh：先保持旧骰面，等翻滚停稳后再一次性显示新点数（少一次重建、也不剧透）
	info_label.text = ""
	dice_tip.text = ""
	_set_dice_input(false)
	btn_confirm.disabled = true
	btn_reroll.disabled = true
	btn_yc.disabled = true
	_hide_yc_popup()
	if not await _animate_roll(picks, 0, true):
		return
	if not is_inside_tree():
		return
	_human_active = battle.winner < 0
	refresh()

func _on_confirm() -> void:
	if not _human_active:
		return
	if _need > 0 and _sel.size() != _need:
		info_label.text = "[center]必须恰好选 %d 颗！[/center]" % _need
		return
	if _need == 0 and _sel.size() < 1:
		info_label.text = "[center]至少选 1 颗！[/center]"
		return
	if not battle.commit_selection(0, _phase, _sel.duplicate()):
		info_label.text = "[center]提交失败，请重新选择[/center]"
		return
	_human_active = false   # 立即锁输入：commit 可能有瞬伤，避免同一帧双击二次提交
	_phase_done = true
	refresh()

# 掉血反馈：Battle.damage() 每次扣血都往 battle.hits 记一笔，refresh 时消费新增事件。
# 主伤害/连击/反击/瞬伤/荆棘/中毒共用同一套闪红+飘字，非主伤害额外标注来源
# （此前只有 settle 的主伤害/连击/反击有反馈，瞬伤/荆棘/中毒掉血完全看不到原因）
func _flush_hits() -> void:
	if battle == null or _hit_seen >= battle.hits.size():
		return
	var batch: Array = battle.hits.slice(_hit_seen)
	_hit_seen = battle.hits.size()
	var stack := [0, 0]
	for h in batch:
		var idx: int = int(h.target)
		_damage_feedback(idx, int(h.amount), str(h.kind), stack[idx])
		stack[idx] += 1

func _damage_feedback(idx: int, amount: int, kind: String, stack: int) -> void:
	if amount <= 0:
		return
	var lbl: Label = enemy_hp if idx == 1 else player_hp
	var tw := create_tween()
	tw.tween_property(lbl, "modulate", Color(1.0, 0.25, 0.2), 0.15)
	tw.tween_property(lbl, "modulate", Color.WHITE, 0.45)
	var kind_txt: String = HIT_KIND_TEXT.get(kind, "")
	var f := Label.new()
	f.text = ("-%d" % amount) + ("" if kind_txt == "" else " %s" % kind_txt)
	f.add_theme_font_size_override("font_size", 40 if kind_txt == "" else 34)
	f.add_theme_color_override("font_color", Color(1.0, 0.2, 0.15))
	f.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	f.add_theme_constant_override("outline_size", 6)
	add_child(f)
	# 敌方血条在屏幕顶部：同批多笔掉血向下叠，避免第二笔被顶出屏幕；我方在底部则向上叠
	var dir: float = 1.0 if idx == 1 else -1.0
	f.global_position = lbl.global_position + Vector2(lbl.size.x + 12, -14.0 + dir * 46.0 * float(stack))
	var tf := create_tween()
	tf.set_parallel(true)
	tf.tween_property(f, "global_position:y", f.global_position.y - 56, 0.9)
	tf.tween_property(f, "modulate:a", 0.0, 0.9)
	tf.chain().tween_callback(f.queue_free)
