class_name GlossaryPanel
extends PanelContainer

# 关键词图鉴弹窗：定义照录 DESIGN.md §3（GameData.KEYWORDS）
# 打开方式：点击界面内任意效果词（RichTextLabel meta 链接）；弹窗内定义里的效果词也可继续点击跳转

var _def_label: RichTextLabel

static func kw_bbcode(text: String) -> String:
	var kws: Array = GameData.KEYWORDS.keys()
	kws.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	var out := text
	for kw in kws:
		out = out.replace(kw, "[url=%s][color=#ffd66b]%s[/color][/url]" % [kw, kw])
	return out

func _ready() -> void:
	visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.14, 0.17, 0.98)
	sb.border_color = Color(0.45, 0.48, 0.55)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	add_theme_stylebox_override("panel", sb)
	anchor_left = 0.5
	anchor_top = 0.5
	anchor_right = 0.5
	anchor_bottom = 0.5
	offset_left = -400.0
	offset_top = -280.0
	offset_right = 400.0
	offset_bottom = 280.0
	grow_horizontal = 2
	grow_vertical = 2
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	add_child(vbox)
	var title := Label.new()
	title.text = "关键词图鉴"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	vbox.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(grid)
	for kw in GameData.KEYWORDS.keys():
		var b := Button.new()
		b.text = kw
		b.pressed.connect(_show.bind(kw))
		grid.add_child(b)
	_def_label = RichTextLabel.new()
	_def_label.bbcode_enabled = true
	_def_label.fit_content = true
	_def_label.add_theme_font_size_override("normal_font_size", 26)
	_def_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_def_label.meta_clicked.connect(func(meta: Variant) -> void: _show(str(meta)))
	vbox.add_child(_def_label)
	var close := Button.new()
	close.text = "关闭"
	close.pressed.connect(func() -> void: visible = false)
	vbox.add_child(close)

func open(kw: String = "") -> void:
	visible = true
	if kw == "":
		_def_label.text = "点击上方关键词查看官方解释"
	else:
		_show(kw)

func _show(kw: String) -> void:
	_def_label.text = "「%s」%s" % [kw, kw_bbcode(GameData.KEYWORDS[kw])]
