class_name DieVisuals
extends RefCounted

# 骰子视觉静态模块：几何、刻字、网格与材质，供投骰演出（dice_roll.gd）与静态候选骰共用
# 全部 static：面数据/网格/材质挂在静态变量上缓存，跨场景保留；同一骰型与颜色只算一次几何
# d4 正四面体 / d6 立方 / d8 正八面体 / d12 正十二面体（曜彩骰与 d6 同为立方）
# 注意：_faces_for() 返回的 faces 是共享只读数据，调用方不得修改（刻字与停骰都直接读它）

const TIER_COLOR := {4: Color(0.451, 0.910, 0.988), 6: Color(0.765, 0.365, 0.969), 8: Color(0.969, 0.812, 0.682), 12: Color(0.34, 0.29, 0.55)}
const TIER_TEXT := {4: Color(0.05, 0.20, 0.25), 6: Color(1.0, 0.93, 1.0), 8: Color(0.30, 0.15, 0.05), 12: Color(0.92, 0.88, 1.0)}
const YAOCAI_COLOR := Color(0.30, 0.25, 0.50)
const YAOCAI_TEXT := Color(0.92, 0.88, 1.0)

# 各骰型外接球半径（统一口径，屏幕上大小接近）；立方骰半边长 = R/√3
# Godot 4.7 没有内置正四面体/正八面体/正十二面体 Mesh，只有 BoxMesh；
# 立方用 BoxMesh，其余用标准正多面体顶点精确生成（外接球半径 = TIER_RADIUS）
const TIER_RADIUS := {4: 1.20, 6: 1.13, 8: 1.08, 12: 1.05}
const FONT_SIZE := 96
# 正四面体停姿的水平偏转角：结果面本来就上仰 19.47°，再转开一点露出相邻面，
# 避免从正面看像一张平面三角形；角度过大则结果面数字会被压得太扁
const TETRA_YAW_DEG := -12.0

# 静态选骰视图的正视姿态：结果面正对镜头，再绕屏幕水平轴轻微上仰，
# 正面朝上翻、露出一点底面/侧面厚度（参考原作选骰截图；负号即为该方向）
const DISPLAY_TILT_DEG := -18.0
# 三角面（d4/d8）需要更大一点的上翻，才能像参考图一样露出底侧面
const DISPLAY_TILT_TRI_DEG := -28.0

# 面数据（键 yc:<曜彩名> / n:<面数>）、网格、材质缓存：键见 _mesh_key_for
static var _spec_cache: Dictionary = {}
static var _mesh_cache: Dictionary = {}
static var _mat_cache: Dictionary = {}
static var _env: Environment

# 投骰演出与静态小视口共用同一套灯光/环境光（方向光 + 环境光避免深色 d12 背面糊成黑块）
static func shared_environment() -> Environment:
	if _env == null:
		_env = Environment.new()
		_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		_env.ambient_light_color = Color(0.70, 0.70, 0.88)
		_env.ambient_light_energy = 0.70
	return _env

static func add_lighting(node: Node) -> void:
	var key_light := DirectionalLight3D.new()
	key_light.rotation = Vector3(-0.9, 0.4, 0)
	key_light.light_energy = 1.1
	node.add_child(key_light)
	var fill_light := DirectionalLight3D.new()
	fill_light.rotation = Vector3(-0.6, -2.3, 0)
	fill_light.light_energy = 0.45
	node.add_child(fill_light)
	var we := WorldEnvironment.new()
	we.environment = shared_environment()
	node.add_child(we)

# ---------- 几何：按面法线从顶点集里取面 ----------

static func _cube_half() -> float:
	# TIER_RADIUS 是外接球半径；立方骰半边长为 R/√3
	return float(TIER_RADIUS[6]) / sqrt(3.0)

static func _cube_verts(h: float) -> Array:
	var vs: Array = []
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				vs.append(Vector3(sx * h, sy * h, sz * h))
	return vs

static func _tetra_verts(r: float) -> Array:
	var k: float = r / sqrt(3.0)
	var vs: Array = []
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				if sx * sy * sz > 0.0:
					vs.append(Vector3(sx * k, sy * k, sz * k))
	return vs

static func _octa_verts(r: float) -> Array:
	return [Vector3(r, 0, 0), Vector3(-r, 0, 0), Vector3(0, r, 0), Vector3(0, -r, 0), Vector3(0, 0, r), Vector3(0, 0, -r)]

static func _dodeca_verts(r: float) -> Array:
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

static func _hull_faces(verts: Array) -> Array:
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
				out.append(_make_face(face, n, 0))
	return out

static func _face_basis(n: Vector3) -> Basis:
	# Label3D 文字面朝 +Z：让 +Z 对齐面法线，+Y 取接近世界竖直的方向
	var up_ref := Vector3.UP
	if absf(n.dot(up_ref)) > 0.95:
		up_ref = Vector3.FORWARD
	var y := (up_ref - n * up_ref.dot(n)).normalized()
	var x := y.cross(n)
	return Basis(x, y, n)

static func _face_inradius(face: Array, c: Vector3) -> float:
	var best := INF
	for i in range(face.size()):
		var a: Vector3 = face[i]
		var b: Vector3 = face[(i + 1) % face.size()]
		var ab := b - a
		var t := clampf((c - a).dot(ab) / maxf(ab.length_squared(), 0.000001), 0.0, 1.0)
		best = minf(best, (c - (a + ab * t)).length())
	return best

static func _sort_face(face: Array, n: Vector3) -> Array:
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

# 由已排序的有序顶点环生成面数据；统一处理质心与绕序，凸包/法线两种建面共用
static func _make_face(face: Array, n: Vector3, label: int) -> Dictionary:
	var c := Vector3.ZERO
	for v in face:
		c += v
	c /= float(face.size())
	var fn: Vector3 = ((face[1] as Vector3) - (face[0] as Vector3)).cross((face[2] as Vector3) - (face[0] as Vector3))
	if fn.dot(n) < 0.0:
		face.reverse()
	return {
		"normal": n, "center": c, "verts": face,
		"inradius": _face_inradius(face, c), "basis": _face_basis(n), "label": label,
	}

static func _build_faces(verts: Array, normals: Array, labels: Array) -> Array:
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
		out.append(_make_face(face, n, int(labels[i])))
	return out

static func _mesh_from_faces(faces: Array, base: Color) -> ArrayMesh:
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
			# Godot 3D 以顺时针为正面：这里按 [0, i+1, i] 绕序，保证外表面朝外
			# （旧实现为逆时针，CULL_BACK 下骰子实际显示的是内壁，选中壳也会盖住骰面）
			for v in [vs[0], vs[i + 1], vs[i]]:
				st.set_color(col)
				st.set_normal(n)
				st.add_vertex(v)
	return st.commit()

static func _cube_faces(labels: Array) -> Array:
	# 立方骰（普通 d6 / 曜彩骰）6 面法线固定，只有刻字点数按骰型不同
	return _build_faces(_cube_verts(_cube_half()), [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD], labels)

# ---------- 骰型与面数字 ----------

static func _faces_for(d: Die) -> Dictionary:
	# 几何只与骰型有关：普通骰按面数、曜彩骰按名称（不同曜彩的六面点数不同）缓存
	# 返回的 faces 为共享只读数据，调用方不得修改
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
		spec = {"faces": _cube_faces(labels), "color": base, "text": text}
	elif d.sides == 4:
		var r: float = TIER_RADIUS[4]
		var vs := _tetra_verts(r)
		var ns: Array = []
		for v in vs:
			ns.append(-(v as Vector3).normalized())
		var tf: Array = _build_faces(vs, ns, [1, 2, 3, 4])
		_orient_tetra_labels(tf)
		spec = {"faces": tf, "color": base, "text": text}
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
		spec = {"faces": _cube_faces([1, 6, 2, 5, 3, 4]), "color": base, "text": text}
	_spec_cache[key] = spec
	return spec

static func _face_index_for(d: Die, faces: Array) -> int:
	if d.is_yaocai():
		return clampi(d.face, 0, faces.size() - 1)
	for i in range(faces.size()):
		if int(faces[i].label) == d.value:
			return i
	return 0

# 停骰姿态：骰子必须像真实骰子一样“有一个面着地”。
# 立方/八面体/十二面体：结果面水平朝上，对面着地，镜头从上前方读结果面；
# 正四面体：选一个非结果面着地，结果面以 19.47° 朝镜头倾斜（几何上唯一能同时做到的姿态）。
static func _rest_rotation(d: Die, faces: Array, fi: int) -> Basis:
	if not d.is_yaocai() and d.sides == 4:
		return _tetra_rest_rotation(faces, fi)
	var target := Vector3.UP
	var up_ref := Vector3.FORWARD   # 顶面上的文字顶端朝远处，镜头俯视时为正
	var y := (up_ref - target * up_ref.dot(target)).normalized()
	var x := y.cross(target)
	return Basis(x, y, target) * (faces[fi].basis as Basis).inverse()

# 静态视图姿态：结果面法线对准镜头方向，再绕镜头右轴（屏幕与水平面的交线）上仰
# DISPLAY_TILT_DEG；返回的是骰子整体旋转。仅用于 DieView，不改变投骰演出的物理停姿。
static func display_rotation(faces: Array, fi: int, view_dir: Vector3) -> Basis:
	var target_n := view_dir.normalized()
	var up_ref := Vector3.UP
	if absf(target_n.dot(up_ref)) > 0.95:
		up_ref = Vector3.FORWARD
	var target_up := (up_ref - target_n * target_n.dot(up_ref)).normalized()
	var target_x := target_up.cross(target_n)
	var target := Basis(target_x, target_up, target_n)
	var r := target * (faces[fi].basis as Basis).inverse()
	var tilt: float = DISPLAY_TILT_TRI_DEG if (faces[fi].verts as Array).size() == 3 else DISPLAY_TILT_DEG
	r = Basis(target_x, deg_to_rad(tilt)) * r
	# 三角形面（d4/d8）在正视姿态下再绕面法线转一下，保证一个顶点朝上、底边水平，
	# 否则某些面会呈现倒三角；旋转不改变结果面朝向。
	var f: Dictionary = faces[fi]
	if (f.verts as Array).size() == 3:
		var n_world: Vector3 = (r * (f.normal as Vector3)).normalized()
		r = Basis(n_world, _triangle_top_yaw(f, r, target_x, target_up)) * r
	return r

static func _triangle_top_yaw(f: Dictionary, r: Basis, screen_x: Vector3, screen_y: Vector3) -> float:
	var best_y := -INF
	var best_angle := 0.0
	for v in f.verts:
		var p: Vector3 = r * ((v as Vector3) - (f.center as Vector3))
		var py: float = p.dot(screen_y)
		if py > best_y:
			best_y = py
			best_angle = atan2(py, p.dot(screen_x))
	return PI * 0.5 - best_angle

# 静态视图的刻字朝向：面法线朝外、文字上沿尽量对齐屏幕竖直方向。
# 在 pivot 旋转确定后按“世界朝向 → mesh 局部”反算，任何面/任何姿态都不会歪。
static func align_display_labels(mesh: MeshInstance3D, faces: Array, pivot: Basis) -> void:
	var inv := pivot.inverse()
	for i in range(faces.size()):
		var lab := mesh.get_child(i) as Label3D
		if lab == null:
			continue
		var n := (pivot * ((faces[i].normal as Vector3))).normalized()
		var up_ref := Vector3.UP
		if absf(n.dot(up_ref)) > 0.95:
			up_ref = Vector3.FORWARD
		var y := (up_ref - n * n.dot(up_ref)).normalized()
		var x := y.cross(n)
		lab.transform = Transform3D(inv * Basis(x, y, n), lab.transform.origin)

# 刻字朝向（不依赖 pivot 的测试/工具接口）
static func display_label_basis(f: Dictionary) -> Basis:
	return _face_basis((f.normal as Vector3).normalized())

# 正四面体：任选一个非结果面作为底面，结果面到竖直方向夹角固定为 arccos(1/3)≈70.53°；
# 在三个候选底面中选“文字顶端最朝上”的一个，避免数字歪倒；最后绕竖直轴转开
# TETRA_YAW_DEG，露出一个相邻面增强立体感（结果面仰角不变）。
static func _tetra_rest_rotation(faces: Array, fi: int) -> Basis:
	var result_n := (faces[fi].normal as Vector3).normalized()
	var world := Basis(Vector3.DOWN, Vector3.BACK, Vector3.DOWN.cross(Vector3.BACK))
	var best := Basis()
	var best_score := -INF
	for j in range(faces.size()):
		if j == fi:
			continue
		var down_n := (faces[j].normal as Vector3).normalized()
		var side := (result_n - down_n * down_n.dot(result_n)).normalized()
		var third := down_n.cross(side).normalized()
		var model := Basis(down_n, side, third)
		var r := world * model.transposed()
		var up_world: Vector3 = r * (faces[fi].basis as Basis).y
		var score := up_world.dot(Vector3.UP)
		if score > best_score:
			best_score = score
			best = r
	# 再绕竖直轴转开，露出一个相邻面增强立体感；绕竖直轴不改变结果面的仰角
	return Basis(Vector3.UP, deg_to_rad(TETRA_YAW_DEG)) * best

static func _orient_tetra_labels(faces: Array) -> void:
	# 正四面体的结果面停姿固定为 19.47° 上仰；每个面作为结果面时的绕法线角度
	# 都不同，因此逐面预旋转刻字，让该面成为结果面时数字尽量竖直（否则 1 会歪成 7）
	for fi in range(faces.size()):
		var rest := _tetra_rest_rotation(faces, fi)
		var nw := (rest * (faces[fi].normal as Vector3)).normalized()
		var upw := (rest * ((faces[fi].basis as Basis).y)).normalized()
		var desired := Vector3.UP - nw * nw.dot(Vector3.UP)
		if desired.length_squared() < 0.0001:
			continue
		desired = desired.normalized()
		var angle := atan2(nw.dot(upw.cross(desired)), upw.dot(desired))
		faces[fi]["label_basis"] = Basis(faces[fi].normal as Vector3, angle) * (faces[fi].basis as Basis)

static func _label_for(f: Dictionary, txt: Color) -> Label3D:
	var lab := Label3D.new()
	lab.text = str(int(f.label))
	lab.font_size = FONT_SIZE
	# 数字贴合面：按面的内切圆估算字号（1–2 位数字都不得越出骰面）；
	# 只沿法线外移 0.0015，配合深度测试看起来是印在面上而不是悬浮的牌子
	var inr: float = float(f.inradius)
	var digits: int = maxi(1, lab.text.length())
	var pixel_w: float = 1.55 * inr / (float(FONT_SIZE) * 0.62 * float(digits))
	var pixel_h: float = 1.35 * inr / float(FONT_SIZE)
	lab.pixel_size = clampf(minf(pixel_w, pixel_h), 0.0025, 0.012)
	lab.modulate = txt
	lab.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	lab.double_sided = false
	lab.no_depth_test = false
	lab.outline_size = 0
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.offset = Vector2.ZERO
	lab.transform = Transform3D(f.get("label_basis", f.basis), (f.center as Vector3) + (f.normal as Vector3) * 0.0015)
	return lab

# 构建完整的骰子节点（网格 + 逐面刻字）：静态候选骰与投骰演出只在摆放/动画上不同，
# 网格与刻字装配共用，避免两处漏挂数字或材质不一致
static func make_die_instance(d: Die, spec: Dictionary) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh_for(d, spec)
	mi.material_override = _material_for(d, spec)
	for f in spec.faces:
		mi.add_child(_label_for(f, spec.text))
	return mi

# ---------- 网格与材质 ----------

# 立方骰（普通 d6 / 曜彩骰）统一用 Godot 官方 BoxMesh；其余用精确正多面体 ArrayMesh
static func _is_box_die(d: Die) -> bool:
	return d.is_yaocai() or d.sides == 6

static func _mesh_key_for(d: Die, spec: Dictionary) -> String:
	# 网格/材质按几何+基色缓存：形状与颜色都进键，将来不同曜彩换了配色也不会串色
	var shape: String = "box" if _is_box_die(d) else ("n%d" % d.sides)
	return "%s|%s" % [shape, (spec.color as Color).to_html()]

static func _mesh_for(d: Die, spec: Dictionary) -> Mesh:
	var key := _mesh_key_for(d, spec)
	if not _mesh_cache.has(key):
		if _is_box_die(d):
			var box := BoxMesh.new()
			box.size = Vector3.ONE * _cube_half() * 2.0
			_mesh_cache[key] = box
		else:
			_mesh_cache[key] = _mesh_from_faces(spec.faces, spec.color)
	return _mesh_cache[key]

static func _material_for(d: Die, spec: Dictionary) -> StandardMaterial3D:
	var key := _mesh_key_for(d, spec)
	if _mat_cache.has(key):
		return _mat_cache[key]
	var mat := StandardMaterial3D.new()
	# 骰子本体必须完全不透明：关闭透明/混合，立方用基色，多面体用顶点色做逐面明暗
	var box: bool = _is_box_die(d)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mat.albedo_color = (spec.color as Color) if box else Color.WHITE
	mat.vertex_color_use_as_albedo = not box
	# 降低镜面高光，保留面片明暗；参考截图的骰面有渐变但不应发白
	mat.roughness = 0.65
	mat.metallic = 0.0
	mat.metallic_specular = 0.2
	if (spec.color as Color).get_luminance() < 0.28:
		mat.emission_enabled = true
		mat.emission = spec.color
		mat.emission_energy_multiplier = 0.12
	_mat_cache[key] = mat
	return mat
