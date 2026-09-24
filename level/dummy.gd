extends CharacterBody2D
## Манекен: стоит, использует тот же риг. От выстрела, удара или взрыва падает рагдоллом,
## затем встаёт. Показывает, что риг/рагдолл переиспользуются любым персонажем.

@export var get_up_delay := 2.5

var _ragdolled := false
var _t := 0.0

@onready var rig: CharacterRig2D = $Rig
@onready var shape: CollisionShape2D = $CollisionShape2D
@onready var ground_ray: RayCast2D = $GroundRay


func _ready() -> void:
	add_to_group("explodable")
	add_to_group("humanoid")
	rig.set_state(&"idle")


func _physics_process(delta: float) -> void:
	if _ragdolled:
		_t += delta
		global_position = rig.ragdoll.get_pelvis_position()
		if (_t > get_up_delay and rig.ragdoll.is_settled()) or _t > 8.0:
			_recover()
		return
	if not is_on_floor():
		velocity.y += get_gravity().y * delta
	velocity.x = 0.0
	move_and_slide()
	rig.foot_ik.enabled = is_on_floor()
	if _t > 0.0:
		_t -= delta
		if _t <= 0.0:
			rig.set_state(&"idle")


func explode_hit(origin: Vector2, force: float) -> void:
	var dir := (global_position + Vector2(0.0, -70.0) - origin).normalized()
	_ragdoll(dir * force, origin)


func hit(impulse: Vector2) -> void:
	_ragdoll(impulse + Vector2(0.0, -120.0))


func bullet_hit(_point: Vector2, dir: Vector2) -> void:
	_ragdoll(dir * 380.0 + Vector2(0.0, -160.0))


func _ragdoll(impulse: Vector2, origin: Vector2 = Vector2.INF) -> void:
	if _ragdolled:
		return
	_ragdolled = true
	_t = 0.0
	shape.disabled = true
	rig.start_ragdoll(velocity, impulse, origin)


func _recover() -> void:
	var p := rig.ragdoll.get_pelvis_position()
	ground_ray.global_position = p
	ground_ray.force_raycast_update()
	global_position = ground_ray.get_collision_point() if ground_ray.is_colliding() else p + Vector2(0.0, 76.0)
	rig.stop_ragdoll()
	shape.disabled = false
	velocity = Vector2.ZERO
	_ragdolled = false
	rig.set_state(&"get_up")
	_t = 0.9
