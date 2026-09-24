extends Node2D
## Взрыв: вспышка (AnimationPlayer), частицы, тряска камеры, ударная волна по телам в радиусе.

@export var force := 750.0
@export var radius := 170.0
@export var camera_shake := 14.0

@onready var area: Area2D = $Area2D
@onready var anim: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	anim.play(&"burst")
	$Particles.emitting = true
	get_tree().call_group(&"camera", &"shake", camera_shake)
	# Area2D обновляет пересечения на следующем физическом кадре.
	await get_tree().physics_frame
	await get_tree().physics_frame
	for body in area.get_overlapping_bodies():
		var d := body.global_position - global_position
		var falloff := clampf(1.0 - d.length() / radius, 0.15, 1.0)
		if body.is_in_group("explodable"):
			body.call("explode_hit", global_position, force * falloff)
		elif body is RigidBody2D:
			var rb := body as RigidBody2D
			rb.apply_central_impulse(d.normalized() * force * falloff * rb.mass * 0.4)
