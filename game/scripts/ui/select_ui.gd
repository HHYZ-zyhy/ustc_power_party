extends Control

# 选卡界面：1 角色 + 1 曜彩骰（化学与材料科学学院无曜彩骰）
# 初始不选中任何项；选中角色后自动选其推荐曜彩（Excel H 列，仍可手动改选）
# 上一局结束后返回时，从 GameStateData 恢复上次的角色/曜彩选择

var _char_btns := {}
var _yc_btns := {}
var _sel_char: String = ""
var _sel_yc: String = ""

@onready var chars_grid: GridContainer = %CharsGrid
@onready var ycs_grid: GridContainer = %YcsGrid
@onready var info_label: RichTextLabel = %InfoLabel
@onready var start_btn: Button = %StartBtn
var glossary: GlossaryPanel

const SIDES_TEXT := {4: "四面", 6: "六面", 8: "八面", 12: "十二面"}

func _pool_text(cfg: Dictionary) -> String:
	var parts: Array = []
	for sides in [4, 6, 8, 12]:
		if cfg.pool.get(sides, 0) > 0:
			parts.append("%s骰×%d" % [SIDES_TEXT[sides], cfg.pool[sides]])
	return "骰池：%s" % "、".join(parts)

func _atk_text(cfg: Dictionary) -> String:
	return "?" if cfg.atk == 0 else str(cfg.atk)

func _ready() -> void:
	for id in GameData.CHARACTERS.keys():
		var cfg: Dictionary = GameData.CHARACTERS[id]
		var b := Button.new()
		b.text = "%s\n%d血 攻%s 防%d" % [cfg.name, cfg.hp, _atk_text(cfg), cfg.def]
		b.custom_minimum_size = Vector2(220, 64)
		b.pressed.connect(_on_char.bind(id))
		chars_grid.add_child(b)
		_char_btns[id] = b
	for name in GameData.YAOCAI.keys():
		var b := Button.new()
		b.text = name
		b.custom_minimum_size = Vector2(120, 40)
		b.pressed.connect(_on_yc.bind(name))
		ycs_grid.add_child(b)
		_yc_btns[name] = b
	start_btn.pressed.connect(_on_start)
	glossary = GlossaryPanel.new()
	add_child(glossary)
	info_label.meta_clicked.connect(func(meta: Variant) -> void: glossary.open(str(meta)))
	# 从上一局返回时恢复上次选择；首次启动 GameStateData 为空，保持未选中角色/曜彩
	if GameStateData.char_id != "" and GameData.CHARACTERS.has(GameStateData.char_id):
		_sel_char = GameStateData.char_id
		var cfg: Dictionary = GameData.CHARACTERS[_sel_char]
		_sel_yc = GameStateData.yc_name
		if cfg.yc == 0:
			_sel_yc = ""
		elif not GameData.YAOCAI.has(_sel_yc):
			_sel_yc = str(cfg.yc_reco)
	_refresh_chars()
	_refresh_yc()
	_update_info()

func _refresh_chars() -> void:
	for k in _char_btns:
		_char_btns[k].modulate = Color.WHITE if (_sel_char == "" or k == _sel_char) else Color(0.6, 0.6, 0.6)

func _on_char(id: String) -> void:
	if id == _sel_char:
		return   # 重复点击已选角色不重置手动改选的曜彩
	_sel_char = id
	var cfg: Dictionary = GameData.CHARACTERS[id]
	# 用户要求：选中角色即自动选其推荐曜彩（化学无曜彩则为空；之后仍可手动改选）
	_sel_yc = "" if cfg.yc == 0 else str(cfg.yc_reco)
	_refresh_chars()
	_refresh_yc()
	_update_info()

func _on_yc(name: String) -> void:
	if _sel_char == "" or GameData.CHARACTERS[_sel_char].yc == 0:
		return
	_sel_yc = name
	_refresh_yc()
	_update_info()

func _refresh_yc() -> void:
	var cfg: Dictionary = GameData.CHARACTERS.get(_sel_char, {})
	var no_char: bool = cfg.is_empty()
	var disabled: bool = no_char or cfg.yc == 0
	var reco: String = "" if no_char else str(cfg.yc_reco)
	for k in _yc_btns:
		var b: Button = _yc_btns[k]
		b.disabled = disabled
		b.text = ("★ %s" % k) if (not no_char and k == reco) else k
		b.tooltip_text = ("本角色推荐曜彩骰（Excel H 列推荐，不强制）" if (not no_char and k == reco) else "")
		if not no_char and k == reco:
			b.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		else:
			b.remove_theme_color_override("font_color")
		b.modulate = Color.WHITE if (no_char or _sel_yc == "" or k == _sel_yc) else Color(0.6, 0.6, 0.6)

# Excel H 列推荐（gamedata.yc_reco）：仅展示给玩家参考，不强制
func _reco_line(cfg: Dictionary) -> String:
	if cfg.yc_reco == "":
		return "推荐曜彩骰：无（本院系无曜彩骰）"
	return "推荐曜彩骰：★%s（不强制）" % cfg.yc_reco

func _can_start() -> bool:
	if _sel_char == "":
		return false
	return GameData.CHARACTERS[_sel_char].yc == 0 or _sel_yc != ""

func _update_info() -> void:
	start_btn.disabled = not _can_start()
	if _sel_char == "":
		info_label.text = (GlossaryPanel.kw_bbcode("请选择角色。\n选中角色后会自动选择该角色的推荐曜彩骰，可再手动更改。"))
		return
	var cfg: Dictionary = GameData.CHARACTERS[_sel_char]
	var head := "已选：%s\n%s\n%s\n%s" % [cfg.name, _pool_text(cfg), cfg.intro, _reco_line(cfg)]
	if _sel_yc == "":
		info_label.text = (GlossaryPanel.kw_bbcode(head + "\n曜彩骰：无"))
	else:
		info_label.text = (GlossaryPanel.kw_bbcode(head + "\n曜彩骰：%s（%d 次/局）\n%s" % [_sel_yc, cfg.yc, GameData.YAOCAI[_sel_yc].intro]))

func _on_start() -> void:
	if not _can_start():
		return
	GameStateData.char_id = _sel_char
	GameStateData.yc_name = _sel_yc
	get_tree().change_scene_to_file("res://scenes/battle.tscn")
