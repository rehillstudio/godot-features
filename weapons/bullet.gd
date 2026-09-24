class_name Bullet
extends Node2D
## Пуля: летит по прямой, каждый физический кадр проверяет отрезок пути лучом
## (не пролетает сквозь тонкие стены). Толкает физические тела, вызывает bullet_hit() у целей.

@export var speed := 1600.0
@export var lifetime := 1.5
@export var impulse := 320.0
@export_flags_2d_physics var hit_mask := 1 | 4 | 16
@export var impact_scene: PackedScene

var direction := Vector2.RIGHT
var _shooter: Node
var _life := 0.0


func setup(dir: Vector2, shooter: Node) -> void:
	direction = dir.normalized()
	_shooter = shooter
	rotation = direction.angle()


func _physics_process(delta: float) -> void:
	_life += delta
	if _life > lifetime:
		queue_free()
		return
	var from := global_position
	var to := from + direction * speed * delta
	var query := PhysicsRayQueryParameters2D.create(from, to, hit_mask)
	if _shooter is CollisionObject2D:
		query.exclude = [(_shooter as CollisionObject2D).get_rid()]
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		global_position = to
		return
	global_position = hit.position
	_impact(hit)
	queue_free()


func _impact(hit: Dictionary) -> void:
	var collider: Object = hit.collider
	if collider is RigidBody2D:
		var body := collider as RigidBody2D
		body.apply_impulse(direction * impulse, hit.position - body.global_position)
	if collider != null and collider.has_method("bullet_hit"):
		collider.call("bullet_hit", hit.position, direction)
	if impact_scene != null:
		var fx := impact_scene.instantiate() as Node2D
		get_parent().add_child(fx)
		fx.global_position = hit.position
		fx.rotation = (hit.normal as Vector2).angle()
