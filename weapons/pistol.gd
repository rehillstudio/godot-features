class_name Pistol2D
extends Node2D
## Пистолет: крепится к кисти. Маркеры: Muzzle (ствол), SupportGrip (точка для второй руки).

@onready var anim: AnimationPlayer = $AnimationPlayer


func fire() -> void:
	anim.stop()
	anim.play(&"fire")


func get_forward() -> Vector2:
	return global_transform.basis_xform(Vector2.RIGHT).normalized()
