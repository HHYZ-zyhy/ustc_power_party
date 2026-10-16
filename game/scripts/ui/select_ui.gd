extends Control

# 选卡界面：1 角色 + 1 曜彩骰（化学与材料科学学院无曜彩骰）

var _char_btns := {}
var _yc_btns := {}
var _sel_char: String = "physics"
var _sel_yc: String = "网络渗透"
var _last_yc: String = "网络渗透"  # 上次有效曜彩选择：化学禁曜彩时暂存，切回可用角色后恢复

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
	_on_char("physics")
	_on_yc("网络渗透")
	start_btn.pressed.connect(_on_start)
	glossary = GlossaryPanel.new()
	add_child(glossary)
	info_label.meta_clicked.connect(func(meta: Variant) -> void: glossary.open(str(meta)))

func _on_char(id: String) -> void:
	_sel_char = id
	if GameData.CHARACTERS[id].yc == 0:
		# 化学禁曜彩：暂存当前选择并清空显示；切回可用角色时恢复，避免静默丢失
		if _sel_yc != "":
			_last_yc = _sel_yc
		_sel_yc = ""
	elif _sel_yc == "":
		_sel_yc = _last_yc
	for k in _char_btns:
		_char_btns[k].modulate = Color.WHITE if k == id else Color(0.6, 0.6, 0.6)
	_refresh_yc()
	_update_info()

func _on_yc(name: String) -> void:
	if GameData.CHARACTERS[_sel_char].yc == 0:
		return
	_sel_yc = name
	_last_yc = name
	_refresh_yc()
	_update_info()

func _refresh_yc() -> void:
	var disabled: bool = GameData.CHARACTERS[_sel_char].yc == 0
	for k in _yc_btns:
		_yc_btns[k].disabled = disabled
		_yc_btns[k].modulate = Color.WHITE if k == _sel_yc else Color(0.6, 0.6, 0.6)

func _update_info() -> void:
	var cfg: Dictionary = GameData.CHARACTERS[_sel_char]
	if _sel_yc == "":
		info_label.text = (GlossaryPanel.kw_bbcode("已选：%s\n%s\n%s\n曜彩骰：无" % [cfg.name, _pool_text(cfg), cfg.intro]))
	else:
		info_label.text = (GlossaryPanel.kw_bbcode("已选：%s\n%s\n%s\n曜彩骰：%s（%d 次/局）\n%s" % [cfg.name, _pool_text(cfg), cfg.intro, _sel_yc, cfg.yc, GameData.YAOCAI[_sel_yc].intro]))

func _on_start() -> void:
	GameStateData.char_id = _sel_char
	GameStateData.yc_name = _sel_yc
	get_tree().change_scene_to_file("res://scenes/battle.tscn")
