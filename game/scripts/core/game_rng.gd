class_name GameRng
extends RefCounted

# 全部随机数经 Crypto 类获得（构思.txt 公平性要求），正式对局与模拟一致
var _crypto: Crypto = Crypto.new()

func randi_range(from: int, to: int) -> int:
	var span := to - from + 1
	var bytes: PackedByteArray = _crypto.generate_random_bytes(4)
	var u: int = (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]
	return from + (u % span)

func coin_flip() -> int:
	return randi_range(0, 1)
