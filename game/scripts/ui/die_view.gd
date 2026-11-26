class_name DieView
extends VBoxContainer

# 单个骰子的静态 3D 视图：上方是 3D 骰子（无方框），下方是逐骰效果提示。
# 每个视图一个 own_world_3d 的小 SubViewport，静态内容用 UPDATE_ONCE，只有骰面/选中/
# 锁定发生变化时才重渲染；玩家候选行与敌方小行共用同一套视图，仅尺寸和交互不同。

signal die_pressed(die: Die)
signal keyword_clicked(meta: Variant)

const CELL_SIZE := Vector2(128, 150)
const DIE_SIZE := Vector2(128, 108)
const ENEMY_SIZE := Vector2(96, 132)
const ENEMY_DIE_SIZE := Vector2(96, 96)
const HINT_HEIGHT := 42.0
const ENEMY_HINT_HEIGHT := 36.0
# 静态展示按参考截图：结果面正对玩家，镜头略高于骰心，配合 DieVisuals.display_rotation
# 绕屏幕水平轴轻上仰，正面翻起、露出一点底面/侧面厚度
const CAM_NORMAL := Vector3(0.0, 0.40, 3.0)
const CAM_SIZE := 2.0

const SEL_COLOR := Color(1.0, 0.85, 0.3)
const LOCK_COLOR := Color(1.0, 0.45, 0.75)
# 反壳描边厚度由壳层放大比例决定：选中金边略加粗，命定保留原厚度
const SEL_SHELL_SCALE := 1.10
const LOCK_SHELL_SCALE := 1.06

var _die: Die
var _selected: bool = false
var _locked: bool = false
var _interactive: bool = false

var _spec_key: String = ""
var _shown_value: int = -9999
var _shown_face: int = -9999
var _button: Button
var _sub: SubViewportContainer
var _sv: SubViewport
var _cam: Camera3D
var _pivot: Node3D
var _mesh: MeshInstance3D
var _sel_shell: MeshInstance3D
var _lock_shell: MeshInstance3D
var _hint: RichTextLabel
var _hover_tween: Tween

func _init() -> void:
	add_theme_constant_override("separation", 0)
	custom_minimum_size = CELL_SIZE
	_build_static_ui()

func _build_static_ui() -> void:
	_button = Button.new()
	_button.text = ""
	_button.focus_mode = Control.FOCUS_NONE
	_button.disabled = true   # 交互由 set_interactive() 显式开启，避免池化前误点
	_button.mouse_default_cursor_shape = Control.CURSOR_ARROW
	_button.custom_minimum_size = DIE_SIZE
	_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_button.pressed.connect(activate)
	_button.mouse_entered.connect(_on_hover.bind(true))
	_button.mouse_exited.connect(_on_hover.bind(false))
	_button.resized.connect(_refresh_pivot)
	add_child(_button)

	_sub = SubViewportContainer.new()
	_sub.stretch = false
	_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sub.set_anchors_preset(Control.PRESET_FULL_RECT)
	_button.add_child(_sub)

	_sv = SubViewport.new()
	_sv.size = Vector2i(DIE_SIZE)
	_sv.own_world_3d = true
	_sv.transparent_bg = true
	_sv.render_target_update_mode = SubViewport.UPDATE_ONCE
	_sub.add_child(_sv)

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = CAM_SIZE
	_cam.look_at_from_position(CAM_NORMAL, Vector3.ZERO)
	_sv.add_child(_cam)
	_cam.current = true
	DieVisuals.add_lighting(_sv)

	_pivot = Node3D.new()
	_sv.add_child(_pivot)

	_hint = RichTextLabel.new()
	_hint.bbcode_enabled = true
	_hint.fit_content = false
	_hint.scroll_active = false
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(DIE_SIZE.x, HINT_HEIGHT)
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.mouse_filter = Control.MOUSE_FILTER_STOP
	_hint.add_theme_font_size_override("normal_font_size", 16)
	_hint.add_theme_color_override("default_color", Color(0.90, 0.92, 0.97))
	_hint.meta_clicked.connect(_on_hint_meta)
	add_child(_hint)

func setup(die: Die) -> void:
	_apply_setup(die, false)

func setup_enemy(die: Die) -> void:
	_apply_setup(die, true)

func _apply_setup(die: Die, enemy_mode: bool) -> void:
	var cell_size: Vector2 = ENEMY_SIZE if enemy_mode else CELL_SIZE
	var die_size: Vector2 = ENEMY_DIE_SIZE if enemy_mode else DIE_SIZE
	var hint_h: float = ENEMY_HINT_HEIGHT if enemy_mode else HINT_HEIGHT
	var hint_font: int = 13 if enemy_mode else 16
	custom_minimum_size = cell_size
	_button.custom_minimum_size = die_size
	_sv.size = Vector2i(die_size)
	_hint.custom_minimum_size = Vector2(die_size.x, hint_h)
	_hint.add_theme_font_size_override("normal_font_size", hint_font)
	set_die(die)

func set_die(die: Die) -> void:
	if die == null:
		return
	var key: String = ("yc:" + die.yaocai) if die.is_yaocai() else ("n:%d" % die.sides)
	var rebuild: bool = _die != die or key != _spec_key or _mesh == null
	var pose_changed: bool = rebuild or die.value != _shown_value or die.face != _shown_face
	_die = die
	if rebuild:
		_spec_key = key
		_rebuild_visual()
	elif pose_changed:
		_apply_rest()
	if pose_changed:
		_arm_render()
	_shown_value = die.value
	_shown_face = die.face

func _rebuild_visual() -> void:
	if _pivot != null:
		_sv.remove_child(_pivot)
		_pivot.queue_free()
	_pivot = Node3D.new()
	_sv.add_child(_pivot)
	var spec: Dictionary = DieVisuals._faces_for(_die)
	_mesh = DieVisuals.make_die_instance(_die, spec)
	_pivot.add_child(_mesh)
	# 选中/命定描边：放大壳 + 只渲染背面（CULL_FRONT），在骰子轮廓外形成一圈
	# 不透明描边；不使用半透明发光壳，骰子本体保持完全不透明
	_sel_shell = _make_shell(_mesh.mesh, SEL_COLOR, SEL_SHELL_SCALE)
	_lock_shell = _make_shell(_mesh.mesh, LOCK_COLOR, LOCK_SHELL_SCALE)
	_apply_rest()
	_apply_outline()

func _make_shell(mesh: Mesh, color: Color, scale_factor: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_FRONT
	mat.albedo_color = color
	mi.material_override = mat
	mi.mesh = mesh
	mi.scale = Vector3.ONE * scale_factor
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	_pivot.add_child(mi)
	return mi

func _apply_rest() -> void:
	if _die == null or _mesh == null:
		return
	var spec: Dictionary = DieVisuals._faces_for(_die)
	var faces: Array = spec.faces
	var fi: int = DieVisuals._face_index_for(_die, faces)
	_pivot.transform = Transform3D(DieVisuals.display_rotation(faces, fi, CAM_NORMAL), Vector3.ZERO)
	DieVisuals.align_display_labels(_mesh, faces, _pivot.transform.basis)

func _apply_outline() -> void:
	var show_sel: bool = _selected and not _locked
	if _sel_shell != null:
		_sel_shell.visible = show_sel
	if _lock_shell != null:
		_lock_shell.visible = _locked

func set_selected(on: bool) -> void:
	if _selected == on:
		return
	_selected = on
	_apply_outline()
	_arm_render()

func set_locked(on: bool) -> void:
	if _locked == on:
		return
	_locked = on
	_button.disabled = not _interactive or _locked
	if _locked:
		_reset_hover_scale()
	_update_cursor()
	_apply_outline()
	_arm_render()

func set_interactive(on: bool) -> void:
	if _interactive == on:
		return
	_interactive = on
	_button.disabled = not on or _locked
	if not on or _locked:
		_reset_hover_scale()
	_update_cursor()

func _update_cursor() -> void:
	_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _interactive and not _locked else Control.CURSOR_ARROW

func set_dimmed(on: bool) -> void:
	# 只压暗颜色，不压 alpha：骰子本体必须始终完全不透明（旧实现会变成半透明）
	var m: Color = Color(0.58, 0.60, 0.66, 1.0) if on else Color.WHITE
	if modulate == m:
		return
	modulate = m

func set_hint(bbcode: String) -> void:
	var txt: String = "" if bbcode == "" else "[center]%s[/center]" % bbcode
	if _hint.text == txt:
		return
	_hint.text = txt
	_hint.tooltip_text = "点击效果词可查看解释" if txt.contains("[url") else ""

func set_tooltip(text: String) -> void:
	if tooltip_text == text and _button.tooltip_text == text:
		return
	tooltip_text = text
	_button.tooltip_text = text

func activate() -> void:
	if not _interactive or _locked or _die == null:
		return
	die_pressed.emit(_die)

func get_die() -> Die:
	return _die

func is_locked() -> bool:
	return _locked

func is_interactive() -> bool:
	return _interactive

func get_die_button() -> Button:
	return _button

func get_sub_viewport() -> SubViewport:
	return _sv

func get_hint_label() -> RichTextLabel:
	return _hint

func arm_render() -> void:
	_arm_render()

func _arm_render() -> void:
	if not is_inside_tree():
		call_deferred("_arm_render")
		return
	_sv.render_target_update_mode = SubViewport.UPDATE_ONCE

func _on_hint_meta(meta: Variant) -> void:
	keyword_clicked.emit(meta)

func _on_hover(on: bool) -> void:
	if not _interactive or _locked:
		return
	_refresh_pivot()
	if _hover_tween != null:
		_hover_tween.kill()
	var target := Vector2(1.04, 1.04) if on else Vector2.ONE
	_hover_tween = create_tween()
	_hover_tween.tween_property(_button, "scale", target, 0.12)

func _refresh_pivot() -> void:
	_button.pivot_offset = _button.size * 0.5

func _reset_hover_scale() -> void:
	if _hover_tween != null:
		_hover_tween.kill()
	_button.scale = Vector2.ONE

func _exit_tree() -> void:
	if _hover_tween != null:
		_hover_tween.kill()
