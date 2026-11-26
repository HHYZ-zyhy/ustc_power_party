class_name ButtonStyles
extends RefCounted

# 选卡页与战斗页共用的按钮样式：选中金边/推荐金字/禁用暗色；
# 主操作按钮（开始对局/确认选骰/使用曜彩/返回选卡）同样共用一份，避免两处样式漂移

const GOLD := Color(1.0, 0.85, 0.3)
const OFF_BORDER := Color(0.30, 0.32, 0.40)
const TEXT := Color(0.80, 0.82, 0.88)
const TEXT_SEL := Color(1.0, 1.0, 1.0)
const TEXT_DIS := Color(0.45, 0.47, 0.54)

var _primary_on: StyleBoxFlat
var _primary_hover: StyleBoxFlat
var _primary_off: StyleBoxFlat
var _styles := {}

func _init() -> void:
	for key in ["sel", "off", "dis"]:
		var bg := Color(0.22, 0.20, 0.29)
		var border := GOLD
		var width := 2
		if key == "off":
			bg = Color(0.14, 0.15, 0.19)
			border = OFF_BORDER
			width = 1
		elif key == "dis":
			bg = Color(0.11, 0.11, 0.14)
			border = Color(0.22, 0.23, 0.28)
			width = 1
		_styles[key + "_normal"] = _make(bg, border, width)
		_styles[key + "_hover"] = _make(bg.lightened(0.06), border, width)
		_styles[key + "_pressed"] = _make(bg.darkened(0.08), border, width)
		_styles[key + "_focus"] = _styles[key + "_normal"]
	_primary_on = _make(Color(0.24, 0.20, 0.10), GOLD, 2)
	_primary_hover = _make(Color(0.30, 0.24, 0.12), GOLD, 2)
	_primary_off = _make(Color(0.13, 0.14, 0.17), OFF_BORDER, 1)

func _make(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	return sb

# 主操作按钮：可用时金色描边 + 暖色底，不可用时暗色
func apply_primary(b: Button, enabled: bool) -> void:
	b.add_theme_stylebox_override("normal", _primary_on if enabled else _primary_off)
	b.add_theme_stylebox_override("hover", _primary_hover if enabled else _primary_off)
	b.add_theme_stylebox_override("pressed", _primary_on if enabled else _primary_off)
	b.add_theme_stylebox_override("focus", _primary_on if enabled else _primary_off)
	b.add_theme_stylebox_override("disabled", _primary_off)
	var col: Color = GOLD if enabled else TEXT_DIS
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		b.add_theme_color_override(key, col)

# 次级按钮：选中金色；推荐金色文字；普通浅灰；禁用暗灰
func apply(b: Button, selected: bool, disabled: bool = false, reco: bool = false) -> void:
	var key := "dis" if disabled else ("sel" if selected else "off")
	for state in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(state, _styles[key + "_" + state])
	var text_color: Color = TEXT_DIS
	if not disabled:
		if reco:
			text_color = GOLD
		elif selected:
			text_color = TEXT_SEL
		else:
			text_color = TEXT
	b.add_theme_color_override("font_color", text_color)
	b.add_theme_color_override("font_hover_color", text_color)
	b.add_theme_color_override("font_pressed_color", text_color)
	b.add_theme_color_override("font_disabled_color", TEXT_DIS)
