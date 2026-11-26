extends Node3D

# 投骰 3D 演出：真骰型 + 逐面数字，翻滚约 1.7 秒后停在所掷面，发出 finished
# 几何/刻字/网格/材质由 DieVisuals 静态模块提供（静态缓存跨场景保留）
# d4 正四面体 / d6 立方 / d8 正八面体 / d12 正十二面体（曜彩骰与 d6 同为立方）
# 骰型只影响外观与面数；掷出的点数取自 Die.value（曜彩骰为 Die.face 对应面点数）

signal finished

var _spawned: Array = []
var _cam: Camera3D
var _token: int = 0   # 重入令牌：新一次 roll 开始后，旧协程不得再 emit finished

func _ready() -> void:
	var cam := Camera3D.new()
	cam.fov = 52.0
	cam.look_at_from_position(Vector3(0, 4.9, 5.7), Vector3(0, 0.9, 0))
	add_child(cam)
	cam.current = true
	_cam = cam
	# 灯光/环境光与静态选骰共用（DieVisuals）
	DieVisuals.add_lighting(self)

# 骰子少时把镜头推近，单颗曜彩骰也有存在感
func _frame_for(n: int) -> void:
	var pos := Vector3(0, 4.9, 5.7)
	var target := Vector3(0, 0.9, 0)
	if n <= 1:
		pos = Vector3(0, 3.0, 3.2)
		target = Vector3(0, 1.2, 0)
	elif n <= 3:
		pos = Vector3(0, 4.5, 5.2)
		target = Vector3(0, 0.95, 0)
	_cam.look_at_from_position(pos, target)

# ---------- 投骰 ----------

# quick=true 用于重投：只滚所选骰，时长压到约 1.3s，避免每回合节奏被拖慢
func roll(dice_a: Array, dice_b: Array, quick: bool = false) -> void:
	_token += 1
	var my_token := _token
	var grng := GameRng.new()
	for n in _spawned:
		n.visible = false   # 先隐藏再延迟释放，避免下一轮同帧叠出旧骰
		n.queue_free()
	_spawned.clear()
	_frame_for(maxi(dice_a.size(), dice_b.size()))
	var spin: float = 0.95 if quick else 1.7
	var hop_h: float = 1.55 if quick else 2.10
	var up_t: float = 0.38 if quick else 0.55
	var down_t: float = 0.48 if quick else 0.75
	var total: float = 1.30 if quick else 2.3
	var rows := [dice_a, dice_b]
	# 只有一行骰子时居中；两行同时存在时前后分开
	var both: bool = not dice_a.is_empty() and not dice_b.is_empty()
	for r in range(rows.size()):
		var row: Array = rows[r]
		if row.is_empty():
			continue
		var z := (r * 2.0 - 1.0) * 1.3 if both else 0.0
		var spacing: float = minf(2.25, 12.6 / maxf(1.0, float(row.size() - 1)))
		for i in range(row.size()):
			var d: Die = row[i]
			var spec := DieVisuals._faces_for(d)
			var faces: Array = spec.faces
			var mi := DieVisuals.make_die_instance(d, spec)
			mi.position = Vector3((i - (row.size() - 1) / 2.0) * spacing, 0.9, z)
			mi.rotation = Vector3(
				grng.randi_range(0, 628) / 100.0,
				grng.randi_range(0, 628) / 100.0,
				grng.randi_range(0, 628) / 100.0)
			add_child(mi)
			_spawned.append(mi)
			# 翻滚：欧拉角加整圈数，落点精确停在所掷面
			var fi := DieVisuals._face_index_for(d, faces)
			if fi < 0 or fi >= faces.size():
				fi = 0   # 面表异常时兜底，避免 faces[fi] 越界导致 finished 永不发出
			var rest := DieVisuals._rest_rotation(d, faces, fi)
			var turns := Vector3(
				TAU * grng.randi_range(1, 2),
				TAU * grng.randi_range(1, 2),
				TAU * grng.randi_range(1, 2))
			if quick:
				turns = Vector3(TAU, TAU, TAU)   # 重投少转一圈，缩短演出
			var tw := create_tween()
			tw.tween_property(mi, "rotation", rest.get_euler() + turns, spin).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			var tw2 := create_tween()
			tw2.tween_property(mi, "position:y", hop_h, up_t).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
			tw2.tween_property(mi, "position:y", 0.9, down_t).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(total).timeout
	if my_token != _token or not is_inside_tree():
		return
	finished.emit()
