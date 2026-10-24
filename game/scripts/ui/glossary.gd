class_name GlossaryPanel
extends PanelContainer

# 效果显示弹窗（原「关键词图鉴」）：18 条效果逐条列出（名称 + 定义，定义照录 DESIGN.md §3）
# 布局参照原作「效果解释」面板：纵向列表 + 滚动条，可滚动查看全部效果
# 打开方式：点击界面内任意效果词（RichTextLabel meta 链接）；打开后高亮并滚动到该效果，
# 行本身也可点击切换高亮；定义内的效果词仍可点击跳转

const GOLD := Color(1.0, 0.84, 0.42)
const NAME_NORMAL := Color(0.94, 0.95, 0.98)
const DESC_NORMAL := Color(0.84, 0.86, 0.92)

var _scroll: ScrollContainer
var _rows := {}    # 关键词 -> PanelContainer
var _names := {}   # 关键词 -> Label
var _current: String = ""
var _scroll_seq := 0   # 连点多个效果时，旧滚动协程自动作废

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
	sb.bg_color = Color(0.16, 0.16, 0.23, 1.0)
	sb.border_color = Color(0.40, 0.44, 0.60)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 14.0
	sb.content_margin_bottom = 14.0
	add_theme_stylebox_override("panel", sb)
	anchor_left = 0.5
	anchor_top = 0.5
	anchor_right = 0.5
	anchor_bottom = 0.5
	offset_left = -500.0
	offset_top = -410.0
	offset_right = 500.0
	offset_bottom = 410.0
	grow_horizontal = 2
	grow_vertical = 2
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	add_child(vbox)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	vbox.add_child(header)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(84, 0)
	header.add_child(spacer)
	var title := Label.new()
	title.text = "效果显示"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 32)
	header.add_child(title)
	var close := Button.new()
	close.text = "关闭"
	close.custom_minimum_size = Vector2(84, 0)
	close.add_theme_font_size_override("font_size", 22)
	close.pressed.connect(func() -> void: visible = false)
	header.add_child(close)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_scroll)
	# 滚动条按原作样式：细亮条 + 透明轨道
	var vs: VScrollBar = _scroll.get_v_scroll_bar()
	vs.custom_minimum_size = Vector2(10, 0)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0, 0, 0, 0)
	track.content_margin_left = 3.0
	track.content_margin_right = 3.0
	vs.add_theme_stylebox_override("scroll", track)
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
		var grab := StyleBoxFlat.new()
		grab.bg_color = Color(0.80, 0.83, 0.90, 0.75)
		grab.set_corner_radius_all(3)
		vs.add_theme_stylebox_override(state, grab)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 0)
	_scroll.add_child(list)
	var kws: Array = GameData.KEYWORDS.keys()
	for i in range(kws.size()):
		list.add_child(_make_row(kws[i]))
		if i < kws.size() - 1:
			var sep := HSeparator.new()
			var line := StyleBoxLine.new()
			line.color = Color(0.40, 0.43, 0.55, 0.6)
			line.thickness = 1
			sep.add_theme_stylebox_override("separator", line)
			list.add_child(sep)

func _make_row(kw: String) -> Control:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _row_style(false))
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_select(kw, false))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	row.add_child(box)
	var name_lbl := Label.new()
	name_lbl.text = kw
	name_lbl.add_theme_font_size_override("font_size", 27)
	name_lbl.add_theme_color_override("font_color", NAME_NORMAL)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_lbl)
	var desc := RichTextLabel.new()
	desc.bbcode_enabled = true
	desc.fit_content = true
	desc.scroll_active = false
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.text = kw_bbcode(GameData.KEYWORDS[kw])
	desc.add_theme_font_size_override("normal_font_size", 22)
	desc.add_theme_color_override("default_color", DESC_NORMAL)
	desc.mouse_filter = Control.MOUSE_FILTER_PASS   # 滚轮事件继续传给 ScrollContainer
	desc.meta_clicked.connect(func(meta: Variant) -> void: open(str(meta)))
	box.add_child(desc)
	_rows[kw] = row
	_names[kw] = name_lbl
	return row

func _row_style(highlight: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.content_margin_left = 20.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 12.0
	sb.content_margin_bottom = 12.0
	sb.set_corner_radius_all(8)
	if highlight:
		sb.bg_color = Color(1.0, 0.82, 0.32, 0.10)
		sb.border_color = GOLD
		sb.border_width_left = 4
	return sb

func _select(kw: String, scroll_to: bool) -> void:
	_scroll_seq += 1
	_current = kw
	for k in _rows:
		var on: bool = (k == kw)
		(_rows[k] as PanelContainer).add_theme_stylebox_override("panel", _row_style(on))
		(_names[k] as Label).add_theme_color_override("font_color", GOLD if on else NAME_NORMAL)
	if scroll_to and _rows.has(kw):
		_scroll_to(kw, _scroll_seq)

# 打开时滚动到相关效果：连续几帧重设滚动位置，等滚动条出现/文本换行导致的行高变化收敛
# （只设一次会因行位置随后下移而停在上一行残条处）
func _scroll_to(kw: String, seq: int) -> void:
	var row: Control = _rows[kw]
	for i in range(6):
		await get_tree().process_frame
		if not visible or seq != _scroll_seq:
			return
		_scroll.scroll_vertical = maxi(0, int(row.position.y) - 6)

func open(kw: String = "") -> void:
	visible = true
	var known: bool = _rows.has(kw)
	_select(kw if known else "", known)
	if not known:
		_scroll.scroll_vertical = 0
