class_name GameData
extends RefCounted

# 数值依据：参考素材/角色，骰子参数.xlsx（sheet1 角色属性 / sheet2 骰子属性）与 DESIGN.md
# pool 键为骰型面数；atk=0 表示自由选骰（少年班学院）
# intro 字段照录 Excel 原文，界面展示不得简写

const CHARACTERS := {
	"shaonianban": {
		"name": "少年班学院", "hp": 30, "atk": 0, "def": 3,
		"pool": {4: 2, 6: 2, 8: 1, 12: 0}, "yc": 2, "yc_reco": "理实积淀",
		"intro": "攻击时：可以选定任意数量的骰子（至少1个），本次攻击若选定3个以下骰子则获得连击，若只选定1个骰子则再获得洞穿。",
		"passives": [
			{"t": "attack", "c": {"t": "count_le", "n": 3}, "fx": [{"op": "combo"}]},
			{"t": "attack", "c": {"t": "count_eq", "n": 1}, "fx": [{"op": "pierce"}]},
		],
	},
	"ai": {
		"name": "人工智能与数据科学学院", "hp": 27, "atk": 3, "def": 2,
		"pool": {4: 2, 6: 1, 8: 2, 12: 0}, "yc": 2, "yc_reco": "军训急救",
		"intro": "防御时：如果受到伤害值>=8，则使攻击等级与防御等级+1；如果受到伤害，且伤害值<=5，则立即造成3点瞬伤。",
		"passives": [
			{"t": "on_damaged", "c": {"t": "dmg_ge", "n": 8}, "fx": [{"op": "atk_level_add", "n": 1, "perm": true}, {"op": "def_level_add", "n": 1, "perm": true}]},
			{"t": "on_damaged", "c": {"t": "dmg_le", "n": 5}, "fx": [{"op": "instant", "n": 3}]},
		],
	},
	"math": {
		"name": "数学科学学院", "hp": 33, "atk": 2, "def": 3,
		"pool": {4: 3, 6: 1, 8: 1, 12: 0}, "yc": 2, "yc_reco": "重复试验",
		"intro": "攻击时：若选定的骰子点数全为4，则本次攻击获得洞穿；每成功触发一次洞穿，攻击等级+1。",
		"passives": [
			{"t": "attack", "c": {"t": "all_eq_value", "v": 4}, "fx": [{"op": "pierce"}, {"op": "atk_level_add", "n": 1, "perm": true}]},
		],
	},
	"physics": {
		"name": "物理学院", "hp": 28, "atk": 4, "def": 3,
		"pool": {4: 2, 6: 3, 8: 0, 12: 0}, "yc": 2, "yc_reco": "网络渗透",
		"intro": "攻击时：若选定的骰子包含2组2个相同点数，则本次攻击获得连击。如果自身满生命值，攻击值+5。",
		"passives": [
			{"t": "attack", "c": {"t": "pairs_ge", "n": 2}, "fx": [{"op": "combo"}]},
			{"t": "attack", "c": {"t": "full_hp"}, "fx": [{"op": "atk_add", "n": 5}]},
		],
	},
	"chem": {
		"name": "化学与材料科学学院", "hp": 30, "atk": 4, "def": 3,
		"pool": {4: 3, 6: 2, 8: 0, 12: 0}, "yc": 0, "yc_reco": "",
		"intro": "攻击时：若选定的骰子全为偶数，则使选定的骰子获得升级。",
		"passives": [
			{"t": "attack", "c": {"t": "all_even"}, "fx": [{"op": "upgrade_sel"}]},
		],
	},
	"management": {
		"name": "管理学院", "hp": 42, "atk": 3, "def": 2,
		"pool": {4: 0, 6: 3, 8: 2, 12: 0}, "yc": 2, "yc_reco": "通宵鏖战",
		"intro": "回合结束时：获得一次曜彩骰使用次数。若已触发4次以上曜彩骰的特殊效果，则此后每回合获得跃升。",
		"passives": [
			{"t": "round_end", "c": {"t": "always"}, "fx": [{"op": "yaocai_use_add", "n": 1}]},
			{"t": "round_end", "c": {"t": "yc_triggered_ge", "n": 4}, "fx": [{"op": "leap_perm"}]},
		],
	},
	"nuclear": {
		"name": "核科学技术学院", "hp": 25, "atk": 4, "def": 3,
		"pool": {4: 3, 6: 2, 8: 0, 12: 0}, "yc": 2, "yc_reco": "东风导弹",
		"intro": "攻击或防御时：选定的骰子每出现1组2个相同的点数，立即造成3点瞬伤。",
		"passives": [
			{"t": "attack", "c": {"t": "pairs_ge", "n": 1}, "fx": [{"op": "instant_per_pair", "n": 3}]},
			{"t": "defense", "c": {"t": "pairs_ge", "n": 1}, "fx": [{"op": "instant_per_pair", "n": 3}]},
		],
	},
	"cyber": {
		"name": "网络空间安全学院", "hp": 25, "atk": 3, "def": 2,
		"pool": {4: 0, 6: 3, 8: 2, 12: 0}, "yc": 2, "yc_reco": "网络渗透",
		"intro": "攻击时：若攻击值大于18，下次防御时防御等级+3，并获得反击，防御结束将还原至初始防御等级。",
		"passives": [
			{"t": "attack", "c": {"t": "sum_ge", "n": 19}, "fx": [{"op": "def_level_add", "n": 3, "dur": "next_defense"}, {"op": "counter", "dur": "next_defense"}]},
		],
	},
	"info": {
		"name": "信息科学技术学院", "hp": 22, "atk": 4, "def": 3,
		"pool": {4: 2, 6: 2, 8: 1, 12: 0}, "yc": 2, "yc_reco": "网络渗透",
		"intro": "攻击或防御时：若选定的骰子包含相同点数，则获得骇入。",
		"passives": [
			{"t": "attack", "c": {"t": "has_pair"}, "fx": [{"op": "hack"}]},
			{"t": "defense", "c": {"t": "has_pair"}, "fx": [{"op": "hack"}]},
		],
	},
	"engineering": {
		"name": "工程科学学院", "hp": 30, "atk": 3, "def": 2,
		"pool": {4: 1, 6: 3, 8: 1, 12: 0}, "yc": 2, "yc_reco": "选课盲赌",
		"intro": "将每回合自身的攻击值与防御值进行累加，总计超过24后，攻击等级变为5，此后每回合获得跃升。",
		"passives": [
			{"t": "round_end", "c": {"t": "accum_ge", "n": 25}, "fx": [{"op": "atk_level_set", "n": 5, "perm": true}, {"op": "leap_perm"}]},
		],
	},
	"life": {
		"name": "生命科学学院", "hp": 20, "atk": 4, "def": 2,
		"pool": {4: 0, 6: 3, 8: 2, 12: 0}, "yc": 2, "yc_reco": "实验防护",
		"intro": "攻击时：虹吸自己造成伤害数额50%的生命值。防御时：若选定的骰子点数全部相同，则获得不屈，最多触发1次。",
		"passives": [
			{"t": "attack", "c": {"t": "always"}, "fx": [{"op": "leech", "pct": 50}]},
			{"t": "defense", "c": {"t": "all_same"}, "fx": [{"op": "unyielding_once"}]},
		],
	},
	"earth": {
		"name": "地球和空间科学学院", "hp": 28, "atk": 2, "def": 2,
		"pool": {4: 0, 6: 4, 8: 1, 12: 0}, "yc": 2, "yc_reco": "铜砖誓言",
		"intro": "攻击后：将力量层数设置为本次攻击值的50%；若选定的骰子点数全为6，则设置为100%并治愈6点生命值。",
		"passives": [
			{"t": "attack_after", "c": {"t": "all_eq_value", "v": 6}, "fx": [{"op": "strength_set", "pct": 100}, {"op": "heal", "n": 6}]},
			{"t": "attack_after", "c": {"t": "not_all_eq_value", "v": 6}, "fx": [{"op": "strength_set", "pct": 50}]},
		],
	},
}

# faces: 6 面，points + fx；use: 对局中使用条件；intro: 照录 Excel sheet2 原文
const YAOCAI := {
	"理实积淀": {
		"intro": "面 3/3/4/4/4/5；每面提供N点数，并获得N层仅下个回合可用的力量；条件：回合数≥3时，可以在防御时使用",
		"faces": [
			{"points": 3, "fx": [{"op": "strength", "n": 3, "dur": "next_turn"}]},
			{"points": 3, "fx": [{"op": "strength", "n": 3, "dur": "next_turn"}]},
			{"points": 4, "fx": [{"op": "strength", "n": 4, "dur": "next_turn"}]},
			{"points": 4, "fx": [{"op": "strength", "n": 4, "dur": "next_turn"}]},
			{"points": 4, "fx": [{"op": "strength", "n": 4, "dur": "next_turn"}]},
			{"points": 5, "fx": [{"op": "strength", "n": 5, "dur": "next_turn"}]},
		],
		"use": {"t": "round_ge", "n": 3, "phase": "defense"},
	},
	"命运签约": {
		"intro": "面 1/3/3/12/12/16；每面+命定（持有命定的骰子投出后必须被选择使用）；条件：随时可用",
		"faces": [
			{"points": 1, "fx": [{"op": "mingding"}]},
			{"points": 3, "fx": [{"op": "mingding"}]},
			{"points": 3, "fx": [{"op": "mingding"}]},
			{"points": 12, "fx": [{"op": "mingding"}]},
			{"points": 12, "fx": [{"op": "mingding"}]},
			{"points": 16, "fx": [{"op": "mingding"}]},
		],
		"use": {"t": "any"},
	},
	"军训急救": {
		"intro": "面 1/2/3/4/6/6；每面+同值治愈；条件：随时可用",
		"faces": [
			{"points": 1, "fx": [{"op": "heal_same"}]},
			{"points": 2, "fx": [{"op": "heal_same"}]},
			{"points": 3, "fx": [{"op": "heal_same"}]},
			{"points": 4, "fx": [{"op": "heal_same"}]},
			{"points": 6, "fx": [{"op": "heal_same"}]},
			{"points": 6, "fx": [{"op": "heal_same"}]},
		],
		"use": {"t": "any"},
	},
	"重复试验": {
		"intro": "面 1/1/4/4/4+连击/4+连击；条件：累计选择2次点数为4的骰面后，可以在攻击时使用",
		"faces": [
			{"points": 1, "fx": []},
			{"points": 1, "fx": []},
			{"points": 4, "fx": []},
			{"points": 4, "fx": []},
			{"points": 4, "fx": [{"op": "combo"}]},
			{"points": 4, "fx": [{"op": "combo"}]},
		],
		"use": {"t": "accum_face", "v": 4, "n": 2, "phase": "attack"},
	},
	"网络渗透": {
		"intro": "面 4/4/4/4+骇入/6+骇入/6+骇入；条件：随时可用",
		"faces": [
			{"points": 4, "fx": []},
			{"points": 4, "fx": []},
			{"points": 4, "fx": []},
			{"points": 4, "fx": [{"op": "hack"}]},
			{"points": 6, "fx": [{"op": "hack"}]},
			{"points": 6, "fx": [{"op": "hack"}]},
		],
		"use": {"t": "any"},
	},
	"通宵鏖战": {
		"intro": "面 4/4/8+荆棘2/8+荆棘2/12+荆棘3/12+荆棘3（荆棘加给自身）；条件：随时可用",
		"faces": [
			{"points": 4, "fx": []},
			{"points": 4, "fx": []},
			{"points": 8, "fx": [{"op": "thorns", "n": 2}]},
			{"points": 8, "fx": [{"op": "thorns", "n": 2}]},
			{"points": 12, "fx": [{"op": "thorns", "n": 3}]},
			{"points": 12, "fx": [{"op": "thorns", "n": 3}]},
		],
		"use": {"t": "any"},
	},
	"东风导弹": {
		"intro": "面 3/5/7/3+瞬伤3/5+瞬伤3/7+瞬伤3；条件：随时可用",
		"faces": [
			{"points": 3, "fx": []},
			{"points": 5, "fx": []},
			{"points": 7, "fx": []},
			{"points": 3, "fx": [{"op": "instant", "n": 3}]},
			{"points": 5, "fx": [{"op": "instant", "n": 3}]},
			{"points": 7, "fx": [{"op": "instant", "n": 3}]},
		],
		"use": {"t": "any"},
	},
	"选课盲赌": {
		"intro": "面 1/1/6/8/10/12，无附加效果；条件：仅能在前4回合内使用",
		"faces": [
			{"points": 1, "fx": []},
			{"points": 1, "fx": []},
			{"points": 6, "fx": []},
			{"points": 8, "fx": []},
			{"points": 10, "fx": []},
			{"points": 12, "fx": []},
		],
		"use": {"t": "round_le", "n": 4},
	},
	"顶刊论文": {
		"intro": "面 99/99/99/99/99/99（秒杀，可被力场抗衡）；条件：累计选择9次点数为1的骰面后，可以在攻击时使用",
		"faces": [
			{"points": 99, "fx": []},
			{"points": 99, "fx": []},
			{"points": 99, "fx": []},
			{"points": 99, "fx": []},
			{"points": 99, "fx": []},
			{"points": 99, "fx": []},
		],
		"use": {"t": "accum_face", "v": 1, "n": 9, "phase": "attack"},
	},
	"实验防护": {
		"intro": "面 7/7/7/1+力场/1+力场/1+力场；条件：只能在防御时使用",
		"faces": [
			{"points": 7, "fx": []},
			{"points": 7, "fx": []},
			{"points": 7, "fx": []},
			{"points": 1, "fx": [{"op": "field"}]},
			{"points": 1, "fx": [{"op": "field"}]},
			{"points": 1, "fx": [{"op": "field"}]},
		],
		"use": {"t": "phase", "phase": "defense"},
	},
	"铜砖誓言": {
		"intro": "面 8/8/4+不屈/4+不屈/6+不屈/6+不屈；条件：只能在防御时使用",
		"faces": [
			{"points": 8, "fx": []},
			{"points": 8, "fx": []},
			{"points": 4, "fx": [{"op": "unyielding"}]},
			{"points": 4, "fx": [{"op": "unyielding"}]},
			{"points": 6, "fx": [{"op": "unyielding"}]},
			{"points": 6, "fx": [{"op": "unyielding"}]},
		],
		"use": {"t": "phase", "phase": "defense"},
	},
}

const UPGRADE_CHAIN := [4, 6, 8, 12]

# 关键词官方定义（照录 DESIGN.md §3，局内「效果显示」列表用，不得简写）
const KEYWORDS := {
	"攻击等级": "攻击时必须选择的骰子数量",
	"防御等级": "防御时必须选择的骰子数量",
	"力量": "层数；攻击时提供对应层数的攻击值加成（不自动消耗）。理实积淀仅防御时可用，故其力量作用于下一次攻击",
	"韧性": "层数；防御时提供对应层数的防御值加成",
	"连击": "额外进行 1 次基于当前攻击值的攻击；两次伤害均按 攻击值 − 防御值 结算（洞穿生效时除外）",
	"反击": "受到攻击时，若防御值更大，对攻击方造成差值伤害",
	"洞穿": "攻击时无视对方的防御值与力场效果",
	"瞬伤": "无需进入伤害结算环节，立刻造成的伤害",
	"虹吸": "攻击时，恢复造成伤害一定比例的生命值",
	"治愈": "回复指定点数的生命值",
	"升级": "将符合条件的骰子进行稀有度和最大面数提升，最高变为十二面",
	"骇入": "结算前，将对手已选择骰子中点数最大的一颗转变为 2 点（不作用于曜彩骰）",
	"力场": "生效期间，不会受到常规攻击伤害（洞穿可无视）",
	"荆棘": "回合结算前受到对应层数的伤害，结算后清除荆棘",
	"中毒": "回合结算后受到对应层数的伤害，随后层数 -1",
	"不屈": "生效期间，始终保留 1 点生命值",
	"跃升": "结算前，随机将已选择骰子中点数最小的一颗转变为该骰子的最大值（不作用于曜彩骰）。持有者参与的每次结算（自身攻击与自身防御）前各触发一次",
	"命定": "持有这一效果的骰子在投出后必须被选择使用",
}
