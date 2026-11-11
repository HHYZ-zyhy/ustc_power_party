extends Node3D

# 投骰 3D 演出：真骰型 + 逐面数字，翻滚约 1.7 秒后停在所掷面，发出 finished
# d4 正四面体 / d6 立方 / d8 正八面体 / d12 正十二面体（曜彩骰与 d6 同为立方）
# 骰型只影响外观与面数；掷出的点数取自 Die.value（曜彩骰为 Die.face 对应面点数）

signal finished

const TIER_COLOR := {4: Color(0.451, 0.910, 0.988), 6: Color(0.765, 0.365, 0.969), 8: Color(0.969, 0.812, 0.682), 12: Color(0.34, 0.29, 0.55)}
const TIER_TEXT := {4: Color(0.05, 0.20, 0.25), 6: Color(1.0, 0.93, 1.0), 8: Color(0.30, 0.15, 0.05), 12: Color(0.92, 0.88, 1.0)}
const YAOCAI_COLOR := Color(0.30, 0.25, 0.50)
const YAOCAI_TEXT := Color(0.92, 0.88, 1.0)

# 各骰型外接球半径：让四种骰子屏幕上看起来差不多大（立方骰半边长的 √3 倍才是外接半径）
const TIER_RADIUS := {4: 1.20, 6: 0.65, 8: 1.08, 12: 1.05}
const FONT_SIZE := 96

var _spawned: Array = []
var _cam: Camera3D
# 面数据/网格/材质缓存：同一骰型只算一次几何；重投时只重建节点与停骰动画
var _spec_cache: Dictionary = {}
var _mesh_cache: Dictionary = {}
var _mat_cache: Dictionary = {}

func _ready() -> void:
	var cam := Camera3D.new()
	cam.fov = 52.0
	cam.look_at_from_position(Vector3(0, 4.9, 5.7), Vector3(0, 0.9, 0))
	add_child(cam)
	cam.current = true
	_cam = cam
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.9, 0.4, 0)
	light.light_energy = 1.1
	add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(-0.6, -2.3, 0)
	fill.light_energy = 0.45
	add_child(fill)
	# 环境光：d12/曜彩骰是深色，只有方向光时背光面会糊成黑块
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.70, 0.70, 0.88)
	env.ambient_light_energy = 0.70
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

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

# ---------- 几何：按面法线从顶点集里取面 ----------

func _cube_verts(h: float) -> Array:
	var vs: Array = []
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				vs.append(Vector3(sx * h, sy * h, sz * h))
	return vs

func _tetra_verts(r: float) -> Array:
	var k: float = r / sqrt(3.0)
	var vs: Array = []
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				if sx * sy * sz > 0.0:
					vs.append(Vector3(sx * k, sy * k, sz * k))
	return vs

func _octa_verts(r: float) -> Array:
	return [Vector3(r, 0, 0), Vector3(-r, 0, 0), Vector3(0, r, 0), Vector3(0, -r, 0), Vector3(0, 0, r), Vector3(0, 0, -r)]

func _dodeca_verts(r: float) -> Array:
	# 正十二面体顶点：(±1,±1,±1)、(0,±1/φ,±φ)、(±1/φ,±φ,0)、(±φ,0,±1/φ)
	var phi: float = (1.0 + sqrt(5.0)) / 2.0
	var inv: float = 1.0 / phi
	var raw: Array = []
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				raw.append(Vector3(sx, sy, sz))
	for s1 in [-1.0, 1.0]:
		for s2 in [-1.0, 1.0]:
			raw.append(Vector3(0, s1 * inv, s2 * phi))
			raw.append(Vector3(s1 * inv, s2 * phi, 0))
			raw.append(Vector3(s1 * phi, 0, s2 * inv))
	var scale: float = r / sqrt(3.0)
	var vs: Array = []
	for v in raw:
		vs.append(v * scale)
	return vs

func _hull_faces(verts: Array) -> Array:
	# 凸多面体：枚举三点定面，取所有顶点都在平面同侧的支撑面并去重
	# （正十二面体的面法线手写容易错位，直接由顶点算更稳）
	var out: Array = []
	for i in range(verts.size()):
		for j in range(i + 1, verts.size()):
			for k in range(j + 1, verts.size()):
				var a: Vector3 = verts[i]
				var b: Vector3 = verts[j]
				var c: Vector3 = verts[k]
				var n := (b - a).cross(c - a)
				if n.length() < 0.000001:
					continue
				n = n.normalized()
				var d := n.dot(a)
				var flip := false
				for v in verts:
					if (v as Vector3).dot(n) > d + 0.001:
						flip = true
						break
				if flip:
					n = -n
					d = -d
					var bad := false
					for v in verts:
						if (v as Vector3).dot(n) > d + 0.001:
							bad = true
							break
					if bad:
						continue
				var dup := false
				for f in out:
					if (f.normal as Vector3).dot(n) > 0.999:
						dup = true
						break
				if dup:
					continue
				var face: Array = []
				for v in verts:
					if absf((v as Vector3).dot(n) - d) < 0.001:
						face.append(v)
				if face.size() < 3:
					continue
				face = _sort_face(face, n)
				var cc := Vector3.ZERO
				for v in face:
					cc += v
				cc /= float(face.size())
				var fn: Vector3 = ((face[1] as Vector3) - (face[0] as Vector3)).cross((face[2] as Vector3) - (face[0] as Vector3))
				if fn.dot(n) < 0.0:
					face.reverse()
				out.append({
					"normal": n, "center": cc, "verts": face,
					"inradius": _face_inradius(face, cc), "basis": _face_basis(n), "label": 0,
				})
	return out

func _face_basis(n: Vector3) -> Basis:
	# Label3D 文字面朝 +Z：让 +Z 对齐面法线，+Y 取接近世界竖直的方向
	var up_ref := Vector3.UP
	if absf(n.dot(up_ref)) > 0.95:
		up_ref = Vector3.FORWARD
	var y := (up_ref - n * up_ref.dot(n)).normalized()
	var x := y.cross(n)
	return Basis(x, y, n)

func _face_inradius(face: Array, c: Vector3) -> float:
	var best := INF
	for i in range(face.size()):
		var a: Vector3 = face[i]
		var b: Vector3 = face[(i + 1) % face.size()]
		var ab := b - a
		var t := clampf((c - a).dot(ab) / maxf(ab.length_squared(), 0.000001), 0.0, 1.0)
		best = minf(best, (c - (a + ab * t)).length())
	return best

func _sort_face(face: Array, n: Vector3) -> Array:
	var c := Vector3.ZERO
	for v in face:
		c += v
	c /= float(face.size())
	var ref := Vector3.UP
	if absf(n.dot(ref)) > 0.9:
		ref = Vector3.FORWARD
	var u := (ref - n * ref.dot(n)).normalized()
	var w := n.cross(u)
	var arr: Array = face.duplicate()
	arr.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		var da: Vector3 = a - c
		var db: Vector3 = b - c
		return atan2(da.dot(w), da.dot(u)) < atan2(db.dot(w), db.dot(u))
	)
	return arr

func _build_faces(verts: Array, normals: Array, labels: Array) -> Array:
	var out: Array = []
	for i in range(normals.size()):
		var n: Vector3 = (normals[i] as Vector3).normalized()
		var maxd := -INF
		for v in verts:
			maxd = maxf(maxd, (v as Vector3).dot(n))
		var face: Array = []
		for v in verts:
			if (v as Vector3).dot(n) > maxd - 0.0001:
				face.append(v)
		face = _sort_face(face, n)
		var c := Vector3.ZERO
		for v in face:
			c += v
		c /= float(face.size())
		# 保证三角形绕序朝外（法线方向）
		var fn: Vector3 = ((face[1] as Vector3) - (face[0] as Vector3)).cross((face[2] as Vector3) - (face[0] as Vector3))
		if fn.dot(n) < 0.0:
			face.reverse()
		out.append({
			"normal": n, "center": c, "verts": face,
			"inradius": _face_inradius(face, c), "basis": _face_basis(n),
			"label": int(labels[i]),
		})
	return out

func _mesh_from_faces(faces: Array, base: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for fi in range(faces.size()):
		var f: Dictionary = faces[fi]
		var n: Vector3 = f.normal
		# 逐面轻微明暗差，让多面体轮廓更清楚（顶点色乘到反照率上）
		var k := 0.80 + 0.25 * float((fi * 5 + 3) % 7) / 6.0
		var col := Color(base.r * k, base.g * k, base.b * k, 1.0)
		var vs: Array = f.verts
		for i in range(1, vs.size() - 1):
			for v in [vs[0], vs[i], vs[i + 1]]:
				st.set_color(col)
				st.set_normal(n)
				st.add_vertex(v)
	return st.commit()

# ---------- 骰型与面数字 ----------

func _faces_for(d: Die) -> Dictionary:
	# 几何只与骰型有关：普通骰按面数、曜彩骰按名称（不同曜彩的六面点数不同）缓存
	var key: String = ("yc:" + d.yaocai) if d.is_yaocai() else ("n:%d" % d.sides)
	if _spec_cache.has(key):
		return _spec_cache[key]
	var base: Color = YAOCAI_COLOR if d.is_yaocai() else TIER_COLOR.get(d.sides, Color.WHITE)
	var text: Color = YAOCAI_TEXT if d.is_yaocai() else TIER_TEXT.get(d.sides, Color.WHITE)
	var spec: Dictionary
	if d.is_yaocai():
		# 曜彩骰固定 6 面：每面刻该面的实际点数（面表见 gamedata）
		var labels: Array = []
		for f in GameData.YAOCAI[d.yaocai].faces:
			labels.append(int(f.points))
		var h: float = TIER_RADIUS[6]
		spec = {"faces": _build_faces(_cube_verts(h), [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD], labels), "color": base, "text": text}
	elif d.sides == 4:
		var r: float = TIER_RADIUS[4]
		var vs := _tetra_verts(r)
		var ns: Array = []
		for v in vs:
			ns.append(-(v as Vector3).normalized())
		spec = {"faces": _build_faces(vs, ns, [1, 2, 3, 4]), "color": base, "text": text}
	elif d.sides == 8:
		var ns: Array = []
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					ns.append(Vector3(sx, sy, sz).normalized())
		spec = {"faces": _build_faces(_octa_verts(TIER_RADIUS[8]), ns, [1, 2, 3, 4, 5, 6, 7, 8]), "color": base, "text": text}
	elif d.sides == 12:
		var faces := _hull_faces(_dodeca_verts(TIER_RADIUS[12]))
		for i in range(faces.size()):
			faces[i]["label"] = i + 1
		spec = {"faces": faces, "color": base, "text": text}
	else:
		# d6 立方：对面点数和为 7，和真骰子一样
		spec = {"faces": _build_faces(_cube_verts(TIER_RADIUS[6]), [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD], [1, 6, 2, 5, 3, 4]), "color": base, "text": text}
	_spec_cache[key] = spec
	return spec

func _face_index_for(d: Die, faces: Array) -> int:
	if d.is_yaocai():
		return clampi(d.face, 0, faces.size() - 1)
	for i in range(faces.size()):
		if int(faces[i].label) == d.value:
			return i
	return 0

# 停骰姿态：让所掷面朝上略朝镜头，且数字读起来是正的
func _rest_rotation(label_basis: Basis) -> Basis:
	var target := Vector3(0, 0.90, 0.44).normalized()
	var up_ref := Vector3.FORWARD   # 文字顶端朝远处，镜头俯视时为正
	var y := (up_ref - target * up_ref.dot(target)).normalized()
	var x := y.cross(target)
	return Basis(x, y, target) * label_basis.inverse()

func _label_for(f: Dictionary, txt: Color) -> Label3D:
	var lab := Label3D.new()
	lab.text = str(int(f.label))
	lab.font_size = FONT_SIZE
	# 字号随面大小收缩，保证数字落在面内
	lab.pixel_size = clampf(1.35 * float(f.inradius) / float(FONT_SIZE), 0.0035, 0.012)
	lab.modulate = txt
	lab.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	lab.double_sided = false
	lab.no_depth_test = false
	lab.transform = Transform3D(f.basis, (f.center as Vector3) + (f.normal as Vector3) * 0.012)
	return lab

# ---------- 投骰 ----------

func _mesh_key_for(d: Die) -> String:
	# 网格按几何+基色缓存：曜彩骰全部共用同一立方网格；普通骰按面数区分
	return "yc" if d.is_yaocai() else ("n%d" % d.sides)

func _mesh_for(d: Die, spec: Dictionary) -> ArrayMesh:
	var key := _mesh_key_for(d)
	if not _mesh_cache.has(key):
		_mesh_cache[key] = _mesh_from_faces(spec.faces, spec.color)
	return _mesh_cache[key]

func _material_for(d: Die, spec: Dictionary) -> StandardMaterial3D:
	var key := _mesh_key_for(d)
	if _mat_cache.has(key):
		return _mat_cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.40
	mat.metallic = 0.05
	if (spec.color as Color).get_luminance() < 0.35:
		mat.emission_enabled = true
		mat.emission = spec.color
		mat.emission_energy_multiplier = 0.30
	_mat_cache[key] = mat
	return mat

# quick=true 用于重投：只滚所选骰，时长压到约 1.3s，避免每回合节奏被拖慢
func roll(dice_a: Array, dice_b: Array, quick: bool = false) -> void:
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
			var spec := _faces_for(d)
			var faces: Array = spec.faces
			var mi := MeshInstance3D.new()
			mi.mesh = _mesh_for(d, spec)
			mi.material_override = _material_for(d, spec)
			mi.position = Vector3((i - (row.size() - 1) / 2.0) * spacing, 0.9, z)
			mi.rotation = Vector3(
				grng.randi_range(0, 628) / 100.0,
				grng.randi_range(0, 628) / 100.0,
				grng.randi_range(0, 628) / 100.0)
			add_child(mi)
			_spawned.append(mi)
			for f in faces:
				mi.add_child(_label_for(f, spec.text))
			# 翻滚：欧拉角加整圈数，落点精确停在所掷面
			var fi := _face_index_for(d, faces)
			var rest := _rest_rotation(faces[fi].basis)
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
	finished.emit()
