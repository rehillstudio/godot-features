class_name AimIK2D
extends Node
## Прицеливание за точкой (курсором): торс и шея доворачиваются частично,
## голова смотрит на цель, передняя рука вытягивается к цели через TwoBoneIK2D,
## задняя рука держит оружие за точку SupportGrip. Учитывает отдачу.

@export var torso_bone: NodePath
@export var neck_bone: NodePath
@export var head_bone: NodePath
@export var arm_ik_front: NodePath
@export var arm_ik_back: NodePath
@export var hand_front: NodePath
@export var hand_back: NodePath
## Оружие (Node2D) с дочерними Marker2D «Muzzle» и «SupportGrip».
@export var weapon: NodePath
## Доля угла прицеливания, которую берёт на себя торс.
@export_range(0.0, 1.0) var torso_share := 0.22
@export_range(0.0, 1.0) var neck_share := 0.12
@export var head_max_deg := 70.0
@export var aim_max_deg := 85.0
## Как далеко вытягивается рука (доля полной длины).
@export_range(0.5, 1.0) var arm_extension := 0.96
@export var recoil_kick_deg := 8.0
@export var recoil_pull := 7.0
@export var recoil_recover := 14.0

## Текущий вес прицеливания (0..1), выставляет риг.
var weight := 0.0
## Вес рук (0 во время перезарядки/удара — руки тогда анимируются).
var arms_weight := 1.0
var target_global := Vector2.ZERO

var _torso: Bone2D
var _neck: Bone2D
var _head: Bone2D
var _arm_f: TwoBoneIK2D
var _arm_b: TwoBoneIK2D
var _hand_f: Bone2D
var _hand_b: Bone2D
var _weapon: Node2D
var _recoil := 0.0
var _arms_w := 1.0


func _ready() -> void:
	_torso = get_node(torso_bone) as Bone2D
	_neck = get_node(neck_bone) as Bone2D
	_head = get_node(head_bone) as Bone2D
	_arm_f = get_node(arm_ik_front) as TwoBoneIK2D
	_arm_b = get_node(arm_ik_back) as TwoBoneIK2D
	_hand_f = get_node(hand_front) as Bone2D
	_hand_b = get_node(hand_back) as Bone2D
	_weapon = get_node_or_null(weapon) as Node2D


func add_recoil(strength: float = 1.0) -> void:
	_recoil = minf(_recoil + strength, 1.5)


## Мировое направление ствола (после применения IK).
func get_aim_direction() -> Vector2:
	if _weapon != null:
		return _weapon.global_transform.basis_xform(Vector2.RIGHT).normalized()
	return BoneMath2D.global_dir(_hand_f)


func apply(rig: Node2D) -> void:
	var dt := get_process_delta_time()
	_recoil = lerpf(_recoil, 0.0, 1.0 - exp(-recoil_recover * dt))
	_arms_w = move_toward(_arms_w, arms_weight, dt * 6.0)
	if weight <= 0.001:
		return
	var visual := rig.get_node("Visual") as Node2D
	var basis_inv := visual.global_transform.affine_inverse()
	var origin := _arm_f.root_global()
	var world_dir := (target_global - origin)
	if world_dir.length_squared() < 1.0:
		return
	# Угол цели в локальных координатах рига: +X — «вперёд» персонажа.
	var local_dir := basis_inv.basis_xform(world_dir.normalized()).normalized()
	var angle := clampf(local_dir.angle(), -deg_to_rad(aim_max_deg), deg_to_rad(aim_max_deg))
	var angle_recoil := angle - deg_to_rad(recoil_kick_deg) * _recoil
	# Торс и шея доворачиваются частично.
	_torso.rotation += angle_recoil * torso_share * weight
	_neck.rotation += angle_recoil * neck_share * weight
	# Голова смотрит на цель (её «лицо» — локальный +X).
	var head_angle := clampf(angle, -deg_to_rad(head_max_deg), deg_to_rad(head_max_deg))
	var head_dir := visual.global_transform.basis_xform(Vector2.RIGHT.rotated(head_angle)).normalized()
	BoneMath2D.set_global_dir(_head, head_dir, weight, Vector2.RIGHT)
	# Руки.
	var w := weight * _arms_w
	if w <= 0.001:
		return
	var aim_dir := visual.global_transform.basis_xform(Vector2.RIGHT.rotated(angle_recoil)).normalized()
	var reach := _arm_f.reach() * arm_extension - recoil_pull * _recoil
	_arm_f.solve_global(origin + aim_dir * reach, w)
	BoneMath2D.set_global_dir(_hand_f, aim_dir, w)
	if _weapon != null and _weapon.visible:
		var grip := _weapon.get_node_or_null("SupportGrip") as Node2D
		if grip != null:
			_arm_b.solve_global(grip.global_position, w)
			BoneMath2D.set_global_dir(_hand_b, get_aim_direction(), w)
