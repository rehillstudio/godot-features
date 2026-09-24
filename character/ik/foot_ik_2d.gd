class_name FootIK2D
extends Node2D
## IK стоп «как в 3D»: лучи под каждой стопой находят реальную поверхность
## (ступени, склоны), стопа ставится на неё, таз опускается к нижней стопе,
## стопа поворачивается по нормали поверхности.
## Узел должен находиться вне зеркалируемого Visual (лучи в мировых координатах).

@export var enabled := true
@export var leg_ik_front: NodePath
@export var leg_ik_back: NodePath
@export var foot_front: NodePath
@export var foot_back: NodePath
@export var hips_bone: NodePath
@export var ray_front: NodePath
@export var ray_back: NodePath
## Насколько выше линии пола персонажа может стоять стопа (ступенька вверх).
@export var max_step_up := 44.0
## Насколько ниже линии пола может опуститься стопа (ступенька вниз).
@export var max_step_down := 30.0
## Высота лодыжки над подошвой.
@export var ankle_height := 8.0
## Если в анимации стопа поднята выше этого значения — IK на неё не действует (мах ногой).
@export var lift_fade := 12.0
## Насколько выносить стопу вперёд на каждый пиксель подъёма на ступеньку (поза «шага»).
@export var raise_forward := 0.35
@export var smooth_speed := 16.0
@export var hips_drop := true
@export var rotate_feet := true
@export_range(0.0, 1.0) var foot_rotation_weight := 0.8

var _legs: Array[TwoBoneIK2D] = []
var _feet: Array[Bone2D] = []
var _rays: Array[RayCast2D] = []
var _hips: Bone2D
var _offsets: Array[float] = [0.0, 0.0]
var _normals: Array[Vector2] = [Vector2.UP, Vector2.UP]
var _drop := 0.0
var _w := 0.0


func _ready() -> void:
	_legs = [get_node(leg_ik_front) as TwoBoneIK2D, get_node(leg_ik_back) as TwoBoneIK2D]
	_feet = [get_node(foot_front) as Bone2D, get_node(foot_back) as Bone2D]
	_rays = [get_node(ray_front) as RayCast2D, get_node(ray_back) as RayCast2D]
	_hips = get_node(hips_bone) as Bone2D
	for r in _rays:
		r.enabled = false  # обновляем вручную через force_raycast_update


func apply(rig: Node2D) -> void:
	var dt := get_process_delta_time()
	_w = move_toward(_w, 1.0 if enabled else 0.0, dt * 5.0)
	if _w <= 0.0001:
		_offsets = [0.0, 0.0]
		_drop = 0.0
		return
	var floor_y := rig.global_position.y
	var k := 1.0 - exp(-smooth_speed * dt)
	var targets: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
	var weights: Array[float] = [0.0, 0.0]
	for i in 2:
		var ankle := _feet[i].global_position
		var sole_lift := -(ankle.y + ankle_height - floor_y)  # > 0 — стопа поднята в анимации
		var wl := clampf(1.0 - sole_lift / lift_fade, 0.0, 1.0) * _w
		var ray := _rays[i]
		ray.global_position = Vector2(ankle.x, floor_y - max_step_up - 8.0)
		ray.target_position = Vector2(0.0, max_step_up + max_step_down + 16.0)
		ray.force_raycast_update()
		var desired := 0.0
		if ray.is_colliding():
			var hit := ray.get_collision_point()
			_normals[i] = _normals[i].lerp(ray.get_collision_normal(), k).normalized()
			desired = clampf(hit.y - floor_y, -max_step_up, max_step_down)
		else:
			wl = 0.0
		_offsets[i] = lerpf(_offsets[i], desired * wl, k)
		targets[i] = ankle + Vector2(0.0, _offsets[i])
		weights[i] = wl
	var forward := rig.global_transform.basis_xform(Vector2.RIGHT).normalized()
	for i in 2:
		if _offsets[i] < 0.0:
			targets[i] += forward * (-_offsets[i]) * raise_forward
	# Таз опускается к самой низкой стопе, чтобы нога не «висела» над нижней ступенькой.
	var drop_target := maxf(maxf(_offsets[0], _offsets[1]), 0.0) if hips_drop else 0.0
	_drop = lerpf(_drop, drop_target, k)
	_hips.position.y += _drop
	var mirror := BoneMath2D.mirror_sign(_hips)
	for i in 2:
		if weights[i] <= 0.001 and _drop <= 0.001:
			continue
		var anim_dir := BoneMath2D.global_dir(_feet[i])
		_legs[i].solve_global(targets[i], 1.0)
		if rotate_feet:
			# Стопа ложится вдоль поверхности: касательная к нормали + угол носка из позы покоя.
			var tangent := _normals[i].rotated(PI * 0.5 * mirror)
			if tangent.dot(forward) < 0.0:
				tangent = -tangent
			var ground_dir := tangent.rotated(_feet[i].get_bone_angle() * mirror)
			var final_dir := anim_dir.slerp(ground_dir, weights[i] * foot_rotation_weight)
			BoneMath2D.set_global_dir(_feet[i], final_dir, 1.0)
		else:
			BoneMath2D.set_global_dir(_feet[i], anim_dir, 1.0)
