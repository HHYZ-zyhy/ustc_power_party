class_name GameStateData
extends RefCounted

# 开局选择结果（选卡场景 → 战斗场景），静态变量跨场景保持
# 初始为空 = 首次启动未选；上一局结束后由 select_ui 据此恢复上次选择
static var char_id: String = ""
static var yc_name: String = ""
