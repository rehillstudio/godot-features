extends RigidBody2D
## Взрывная бочка: два попадания или соседний взрыв (с небольшой задержкой — цепная реакция).

@export var health := 2
@export var explosion_scene: PackedScene
@export var chain_delay := 0.2

var _exploding := false


func _ready() -> void:
	add_to_group("explodable")


func bullet_hit(_point: Vector2, _dir: Vector2) -> void:
	damage(1)


func hit(impulse: Vector2) -> void:
	apply_central_impulse(impulse * mass * 0.5)
	damage(1)


func damage(amount: int) -> void:
	health -= amount
	if health <= 0:
		explode()


func explode_hit(_origin: Vector2, _force: float) -> void:
	if _exploding:
		return
	_exploding = true
	await get_tree().create_timer(chain_delay + randf() * 0.15).timeout
	_do_explode()


func explode() -> void:
	if _exploding:
		return
	_exploding = true
	_do_explode()


func _do_explode() -> void:
	if explosion_scene != null:
		var e := explosion_scene.instantiate() as Node2D
		get_parent().add_child(e)
		e.global_position = global_position + Vector2(0.0, -12.0)
	queue_free()
