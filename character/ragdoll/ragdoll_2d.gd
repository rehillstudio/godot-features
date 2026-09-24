class_name Ragdoll2D
extends Node2D
## Рагдолл, собранный в сцене из RagdollBody2D (RigidBody2D) и RagdollJoint2D (PinJoint2D).
## При активации тела ставятся по текущей позе костей, получают импульс,
## после чего кости каждый кадр повторяют положение тел. При деактивации поза
## плавно сводится обратно к анимации.

signal activated
signal deactivated

@export var skeleton: NodePath
@export var root_bone: NodePath
## Время плавного возврата от позы рагдолла к анимации (с).
@export var recover_time := 0.4
## Скорость, ниже которой тело считается «успокоившимся».
@export var settle_speed := 25.0

var active := false
var _skeleton: Skeleton2D
var _root: Bone2D
var _bodies: Array[RagdollBody2D] = []
var _joints: Array[RagdollJoint2D] = []
var _bones_of_bodies: Array[Bone2D] = []
var _recover_t := 1.0e9
var _recover_rot: Dictionary = {}
var _recover_root_pos := Vector2.ZERO


func _ready() -> void:
	_skeleton = get_node(skeleton) as Skeleton2D
	_root = get_node(root_bone) as Bone2D
	for c in get_children():
		if c is RagdollBody2D:
			_bodies.append(c)
			_bones_of_bodies.append(_skeleton.get_node(c.bone) as Bone2D)
		elif c is RagdollJoint2D:
			_joints.append(c)


func get_pelvis_body() -> RagdollBody2D:
	return _bodies[0]


func get_pelvis_position() -> Vector2:
	return _bodies[0].global_position


func get_velocity() -> Vector2:
	return _bodies[0].linear_velocity


func is_settled() -> bool:
	for b in _bodies:
		if b.linear_velocity.length() > settle_speed and not b.sleeping:
			return false
	return true


## Включает рагдолл. [param velocity] — скорость персонажа (наследуется телами),
## [param impulse] — дополнительный импульс (взрыв), [param impulse_origin] — его центр.
func activate(velocity: Vector2, impulse: Vector2 = Vector2.ZERO, impulse_origin: Vector2 = Vector2.INF) -> void:
	if active:
		return
	active = true
	_recover_t = 1.0e9
	var mirror := BoneMath2D.mirror_sign(_skeleton)
	for i in _bodies.size():
		var body := _bodies[i]
		var bone := _bones_of_bodies[i]
		var p0 := bone.global_position
		var p1 := BoneMath2D.tip_global(bone)
		var dir := (p1 - p0).normalized()
		if body.reverse:
			dir = -dir
		body.global_position = (p0 + p1) * 0.5
		body.global_rotation = dir.angle()
		body.freeze = false
		body.sleeping = false
		body.collision_layer = body.active_layer
		body.collision_mask = body.active_mask
		body.linear_velocity = velocity
		body.angular_velocity = 0.0
	# Суставы пересоздаются в точках костей текущей позы.
	for joint in _joints:
		var bone := _skeleton.get_node(joint.bone) as Bone2D
		joint.global_position = bone.global_position
		var a := get_node_or_null(joint.node_a) as RagdollBody2D
		var b := get_node_or_null(joint.node_b) as RagdollBody2D
		var lo := joint.base_lower
		var hi := joint.base_upper
		if mirror < 0.0:
			var t := lo
			lo = -hi
			hi = -t
		if a != null and b != null:
			# Лимиты PinJoint2D отсчитываются от направления между центрами тел в момент
			# создания, поэтому компенсируем текущий изгиб сустава (примерно половина угла).
			var rel := BoneMath2D.wrap_angle(b.global_rotation - a.global_rotation)
			lo -= rel * 0.5
			hi -= rel * 0.5
		joint.angular_limit_lower = lo
		joint.angular_limit_upper = hi
		var path_a := joint.node_a
		var path_b := joint.node_b
		joint.node_a = NodePath()
		joint.node_b = NodePath()
		joint.node_a = path_a
		joint.node_b = path_b
	# Импульс.
	for body in _bodies:
		var imp := impulse
		if impulse_origin != Vector2.INF:
			var d := body.global_position - impulse_origin
			var dist := maxf(d.length(), 20.0)
			imp = d / dist * impulse.length() * clampf(60.0 / dist, 0.35, 1.0)
		body.apply_central_impulse(imp * body.mass * body.impulse_scale)
		body.apply_torque_impulse(randf_range(-1.0, 1.0) * imp.length() * body.mass * 0.6)
	activated.emit()


## Выключает рагдолл, запоминая позу для плавного возврата к анимации.
func deactivate() -> void:
	if not active:
		return
	active = false
	_recover_rot.clear()
	for bone in _all_bones(_root):
		_recover_rot[bone] = bone.rotation
	_recover_root_pos = _root.position
	_recover_t = 0.0
	for body in _bodies:
		body.freeze = true
		body.collision_layer = 0
		body.collision_mask = 0
		body.linear_velocity = Vector2.ZERO
		body.angular_velocity = 0.0
	deactivated.emit()


## Кости повторяют положение физических тел (вызывается ригом после анимации).
func apply_to_bones() -> void:
	if not active:
		return
	for i in _bodies.size():
		var body := _bodies[i]
		var bone := _bones_of_bodies[i]
		var dir := Vector2.RIGHT.rotated(body.global_rotation)
		if body.reverse:
			dir = -dir
		if bone == _root:
			bone.global_position = body.global_position - dir * bone.get_length() * 0.5
		BoneMath2D.set_global_dir(bone, dir, 1.0)
		for p in body.passive_bones:
			var passive := _skeleton.get_node_or_null(p) as Bone2D
			if passive != null:
				passive.rotation = 0.0


## Плавное смешивание позы рагдолла с анимацией после деактивации.
func apply_recovery() -> void:
	if active or _recover_t >= recover_time:
		return
	var t := smoothstep(0.0, 1.0, _recover_t / recover_time)
	for bone: Bone2D in _recover_rot:
		bone.rotation = lerp_angle(_recover_rot[bone], bone.rotation, t)
	_root.position = _recover_root_pos.lerp(_root.position, t)
	_recover_t += get_process_delta_time()


func _all_bones(bone: Bone2D) -> Array[Bone2D]:
	var out: Array[Bone2D] = [bone]
	for c in bone.get_children():
		if c is Bone2D:
			out.append_array(_all_bones(c))
	return out
