class_name Die
extends RefCounted

const CHAIN := [4, 6, 8, 12]

var sides: int = 6
var value: int = 0
var yaocai: String = ""
var face: int = -1

func is_yaocai() -> bool:
	return yaocai != ""

func upgrade() -> bool:
	var i := CHAIN.find(sides)
	if i < 0 or i >= CHAIN.size() - 1:
		return false
	sides = CHAIN[i + 1]
	return true

func roll(rng: RefCounted) -> void:
	if is_yaocai():
		# 面数取曜彩面表实际长度（当前均为 6 面），避免调用点写死面号范围
		var faces: Array = GameData.YAOCAI[yaocai].faces
		face = rng.randi_range(0, faces.size() - 1)
		value = faces[face].points
	else:
		value = rng.randi_range(1, sides)
