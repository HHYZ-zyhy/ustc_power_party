class_name GameStateData
extends RefCounted

# 开局选择结果（选卡场景 → 战斗场景），静态变量跨场景保持
# 初始为空 = 首次启动未选；上一局结束后由 select_ui 据此恢复上次选择
static var char_id: String = ""
static var yc_name: String = ""

# 进入战斗前统一校验：非法角色回退 physics；无曜彩角色清空；非法曜彩回推荐
# 注意：不把“有效角色 + 空曜彩”强行改成推荐，保持直接跑 battle.tscn 的调试路径
static func sanitize() -> void:
	if GameData.CHARACTERS.is_empty():
		return
	var changed := false
	if char_id == "" or not GameData.CHARACTERS.has(char_id):
		char_id = "physics"
		changed = true
	var cfg: Dictionary = GameData.CHARACTERS[char_id]
	if int(cfg.yc) == 0:
		yc_name = ""
	elif yc_name != "" and not GameData.YAOCAI.has(yc_name):
		yc_name = str(cfg.yc_reco)
	elif changed and yc_name == "":
		yc_name = str(cfg.yc_reco)
