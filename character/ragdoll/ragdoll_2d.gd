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
## Доля нарушения лимита, устраняемая за один физический кадр поворотом тел вокруг сустава (0..1).
@export_range(0.0, 1.0) var limit_correction := 0.6
## Слабая «мышечная» пружина к позе покоя — не даёт рагдоллу сминаться в кашу.
@export var pose_stiffness := 40.0
@export var pose_damping := 5.0
## Ограничение угловой скорости тел (рад/с), чтобы взрыв не закручивал конечности в кашу.
@export var max_angular_speed := 18.0

var active := false
var _skeleton: Skeleton2D
var _root: Bone2D
var _bodies: Array[RagdollBody2D] = []
var _joints: Array[RagdollJoint2D] = []
var _bones_of_bodies: Array[Bone2D] = []
var _recover_t := 1.0e9
var _recover_rot: Dictionary = {}
var _recover_root_pos := Vector2.ZERO
var _mirror := 1.0
var _inertia: Dictionary = {}
var _joint_of_body: Dictionary = {}   # RagdollBody2D -> RagdollJoint2D (сустав, где тело — B)
var _children: Dictionary = {}        # RagdollBody2D -> Array[RagdollBody2D]
var _joint_offset: Dictionary = {}    # RagdollBody2D -> локальное смещение точки сустава от центра тела


func _ready() -> void:
	_skeleton = get_node(skeleton) as Skeleton2D
	_root = get_node(root_bone) as Bone2D
	for c in get_children():
		if c is RagdollBody2D:
			_bodies.append(c)
			_bones_of_bodies.append(_skeleton.get_node(c.bone) as Bone2D)
		elif c is RagdollJoint2D:
			_joints.append(c)
	for i in _bodies.size():
		var body := _bodies[i]
		var bone := _bones_of_bodies[i]
		_joint_offset[body] = Vector2((1.0 if body.reverse else -1.0) * bone.get_length() * 0.5, 0.0)
		_children[body] = []
	for joint in _joints:
		var a := get_node_or_null(joint.node_a) as RagdollBody2D
		var b := get_node_or_null(joint.node_b) as RagdollBody2D
		if a != null and b != null:
			_joint_of_body[b] = joint
			_children[a].append(b)


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
	_mirror = BoneMath2D.mirror_sign(_skeleton)
	for i in _bodies.size():
		var body := _bodies[i]
		var bone := _bones_of_bodies[i]
		var p0 := bone.global_position
		var p1 := BoneMath2D.tip_global(bone)
		if not (is_finite(p0.x) and is_finite(p0.y) and is_finite(p1.x) and is_finite(p1.y)):
			push_warning("Ragdoll2D: кость %s имеет недопустимую трансформацию, беру позицию рига" % bone.name)
			p0 = global_position + Vector2(0.0, -80.0)
			p1 = p0 + Vector2(0.0, 10.0)
		var dir := (p1 - p0).normalized()
		if body.reverse:
			dir = -dir
		# Полная трансформация, чтобы не унаследовать масштаб/наклон от прошлых состояний.
		body.global_transform = Transform2D(dir.angle(), (p0 + p1) * 0.5)
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
		var path_a := joint.node_a
		var path_b := joint.node_b
		joint.node_a = NodePath()
		joint.node_b = NodePath()
		joint.node_a = path_a
		joint.node_b = path_b
	_inertia.clear()
	for body in _bodies:
		# У тел инерция задана явно в сцене (у замороженных тел движок её ещё не считает).
		var inertia := body.inertia
		if inertia <= 0.0:
			inertia = PhysicsServer2D.body_get_param(body.get_rid(), PhysicsServer2D.BODY_PARAM_INERTIA)
		_inertia[body] = maxf(inertia, 1.0)
	# Импульс.
	for body in _bodies:
		var imp := impulse
		if impulse_origin != Vector2.INF:
			var d := body.global_position - impulse_origin
			var dist := maxf(d.length(), 20.0)
			imp = d / dist * impulse.length() * clampf(60.0 / dist, 0.35, 1.0)
		body.apply_central_impulse(imp * body.mass * body.impulse_scale)
		body.apply_torque_impulse(randf_range(-1.0, 1.0) * imp.length() * body.mass * 0.35)
	activated.emit()


func _physics_process(delta: float) -> void:
	if not active:
		return
	_guard_bodies()
	for joint in _joints:
		var a := joint.body_a
		var b := joint.body_b
		if a == null or b == null:
			continue
		var lo := joint.limit_lower
		var hi := joint.limit_upper
		var rest := joint.rest_angle
		if _mirror < 0.0:
			var t := lo
			lo = -hi
			hi = -t
			rest = -rest
		var rel := BoneMath2D.wrap_angle(b.global_rotation - a.global_rotation)
		var rel_vel := b.angular_velocity - a.angular_velocity
		var ia: float = _inertia[a]
		var ib: float = _inertia[b]
		if rel < lo or rel > hi:
			var err := (rel - lo) if rel < lo else (rel - hi)
			# Гасим относительную угловую скорость, уводящую за лимит (распределяем по инерции).
			if err * rel_vel > 0.0:
				b.angular_velocity -= rel_vel * ia / (ia + ib)
				a.angular_velocity += rel_vel * ib / (ia + ib)
			# Поворачиваем тело (и всё, что за ним) вокруг точки сустава обратно в диапазон.
			_rotate_subtree(b, b.to_global(_joint_offset[b]), -err * limit_correction)
		else:
			# Внутри диапазона — слабая «мышечная» пружина к позе покоя.
			var i_red := 1.0 / (1.0 / ia + 1.0 / ib)
			var impulse := -((rel - rest) * pose_stiffness + rel_vel * pose_damping) * i_red * delta
			b.apply_torque_impulse(impulse)
			a.apply_torque_impulse(-impulse)
	for body in _bodies:
		body.angular_velocity = clampf(body.angular_velocity, -max_angular_speed, max_angular_speed)


## Страховка: если физика выдала NaN/бесконечность, тело возвращается к тазу с нулевой скоростью.
func _guard_bodies() -> void:
	var anchor := _bodies[0].global_position
	if not (is_finite(anchor.x) and is_finite(anchor.y)):
		anchor = global_position + Vector2(0.0, -80.0)
	for body in _bodies:
		var p := body.global_position
		var v := body.linear_velocity
		if is_finite(p.x) and is_finite(p.y) and is_finite(body.global_rotation) and is_finite(body.angular_velocity) and is_finite(v.x) and is_finite(v.y):
			continue
		push_warning("Ragdoll2D: недопустимое значение у тела %s — сбрасываю (pos=%s rot=%s w=%s v=%s)" % [body.name, p, body.global_rotation, body.angular_velocity, v])
		body.global_position = anchor + Vector2(randf_range(-4.0, 4.0), randf_range(-4.0, 4.0))
		body.global_rotation = 0.0
		body.linear_velocity = Vector2.ZERO
		body.angular_velocity = 0.0


func _rotate_subtree(body: RagdollBody2D, pivot: Vector2, angle: float) -> void:
	var pos := pivot + (body.global_position - pivot).rotated(angle)
	body.global_transform = Transform2D(body.global_rotation + angle, pos)
	for child: RagdollBody2D in _children[body]:
		_rotate_subtree(child, pivot, angle)


## Выключает рагдолл, запоминая позу для плавного возврата к анимации.
func deactivate() -> void:
	if not active:
		return
	active = false
	_recover_rot.clear()
	for bone in _all_bones(_root):
		_recover_rot[bone] = bone.rotation if is_finite(bone.rotation) else 0.0
	_recover_root_pos = _root.position
	if not (is_finite(_recover_root_pos.x) and is_finite(_recover_root_pos.y)):
		_recover_root_pos = Vector2(0.0, -76.0)
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
		# Гарантия анатомии: локальный угол кости (он всегда в системе «смотрит вправо») в лимитах сустава.
		if _joint_of_body.has(body):
			var joint: RagdollJoint2D = _joint_of_body[body]
			bone.rotation = clampf(BoneMath2D.wrap_angle(bone.rotation), joint.limit_lower, joint.limit_upper)
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


## Отладка: относительные углы суставов и их лимиты (в системе «смотрит вправо»).
func get_joint_report() -> String:
	var out := ""
	for joint in _joints:
		if joint.body_a == null or joint.body_b == null:
			continue
		var rel := BoneMath2D.wrap_angle(joint.body_b.global_rotation - joint.body_a.global_rotation) * _mirror
		out += "%s=%.2f[%.2f..%.2f] " % [joint.name, rel, joint.limit_lower, joint.limit_upper]
	return out


func _all_bones(bone: Bone2D) -> Array[Bone2D]:
	var out: Array[Bone2D] = [bone]
	for c in bone.get_children():
		if c is Bone2D:
			out.append_array(_all_bones(c))
	return out
