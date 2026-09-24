class_name ShakeCamera2D
extends Camera2D
## Камера игрока с тряской (вызывается через группу «camera»: shake(сила)).

var base_offset := Vector2(0.0, -90.0)
var _shake := 0.0


func _ready() -> void:
	add_to_group("camera")


func shake(strength: float) -> void:
	_shake = maxf(_shake, strength)


func _process(delta: float) -> void:
	if _shake > 0.0:
		offset = base_offset + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake
		_shake = move_toward(_shake, 0.0, delta * 45.0)
	else:
		offset = base_offset
