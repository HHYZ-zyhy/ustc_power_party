extends Node3D

# 投骰 3D 演出：骰子翻滚约 1 秒后发出 finished
# 骰型用风格化网格区分：d4 三棱柱 / d6 立方 / d8 四棱柱斜置 / d12 六棱柱

signal finished

const TIER_COLOR := {4: Color(0.451, 0.910, 0.988), 6: Color(0.765, 0.365, 0.969), 8: Color(0.969, 0.812, 0.682), 12: Color(0.10, 0.10, 0.15)}
const TIER_TEXT := {4: Color(0.05, 0.20, 0.25), 6: Color(0.15, 0.05, 0.25), 8: Color(0.30, 0.15, 0.05), 12: Color(0.85, 0.80, 1.0)}
const YAOCAI_COLOR := Color(0.12, 0.11, 0.18)
const YAOCAI_TEXT := Color(0.85, 0.80, 1.0)

var _spawned: Array = []

func _ready() -> void:
	var cam := Camera3D.new()
	cam.look_at_from_position(Vector3(0, 7, 7), Vector3(0, 0, 0.5))
	add_child(cam)
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.9, 0.4, 0)
	add_child(light)

func _mesh_for(d: Die) -> Mesh:
	if d.is_yaocai():
		var b := BoxMesh.new()
		b.size = Vector3(0.9, 0.9, 0.9)
		return b
	match d.sides:
		4:
			var c := CylinderMesh.new()
			c.radial_segments = 3
			c.top_radius = 0.5
			c.bottom_radius = 0.5
			c.height = 0.8
			return c
		8:
			var c := CylinderMesh.new()
			c.radial_segments = 4
			c.top_radius = 0.55
			c.bottom_radius = 0.55
			c.height = 0.8
			return c
		12:
			var c := CylinderMesh.new()
			c.radial_segments = 6
			c.top_radius = 0.55
			c.bottom_radius = 0.55
			c.height = 0.8
			return c
	var b := BoxMesh.new()
	b.size = Vector3(0.85, 0.85, 0.85)
	return b

func roll(dice_a: Array, dice_b: Array) -> void:
	var grng := GameRng.new()
	for n in _spawned:
		n.queue_free()
	_spawned.clear()
	var rows := [dice_a, dice_b]
	for r in range(rows.size()):
		var row: Array = rows[r]
		for i in range(row.size()):
			var d: Die = row[i]
			var mi := MeshInstance3D.new()
			mi.mesh = _mesh_for(d)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = YAOCAI_COLOR if d.is_yaocai() else TIER_COLOR.get(d.sides, Color.WHITE)
			mi.material_override = mat
			mi.position = Vector3((i - (row.size() - 1) / 2.0) * 1.3, 0.5, r * 2.2 - 1.1)
			add_child(mi)
			_spawned.append(mi)
			var lab := Label3D.new()
			lab.text = str(d.value)
			lab.font_size = 64
			lab.pixel_size = 0.01
			lab.position = Vector3(0, 0.9, 0)
			lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lab.modulate = YAOCAI_TEXT if d.is_yaocai() else TIER_TEXT.get(d.sides, Color.WHITE)
			mi.add_child(lab)
			var tw := create_tween()
			var target := Vector3(grng.randi_range(0, 628) / 100.0, grng.randi_range(0, 628) / 100.0, grng.randi_range(0, 628) / 100.0)
			tw.tween_property(mi, "rotation", target, 1.8).set_trans(Tween.TRANS_CUBIC)
			var tw2 := create_tween()
			tw2.tween_property(mi, "position:y", 1.4, 0.7).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
			tw2.tween_property(mi, "position:y", 0.5, 0.7).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(2.3).timeout
	finished.emit()
