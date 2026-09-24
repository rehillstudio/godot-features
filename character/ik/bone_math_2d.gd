class_name BoneMath2D
## Вспомогательная математика для Bone2D.
## Все функции работают в мировых координатах и корректно учитывают зеркальный
## разворот персонажа (scale.x = -1 у родителя скелета).


## Направление кости в её локальных координатах (задаётся свойством bone_angle).
static func chain_dir_local(bone: Bone2D) -> Vector2:
	return Vector2.RIGHT.rotated(bone.get_bone_angle())


## Направление кости в мировых координатах.
static func global_dir(bone: Bone2D) -> Vector2:
	return bone.global_transform.basis_xform(chain_dir_local(bone)).normalized()


## Мировая позиция конца кости (начало + длина вдоль направления).
static func tip_global(bone: Bone2D) -> Vector2:
	return bone.to_global(chain_dir_local(bone) * bone.get_length())


## Поворачивает кость так, чтобы её локальный вектор [param local_vec]
## (по умолчанию — направление кости) смотрел в мировом направлении [param dir].
## [param weight] < 1 плавно смешивает с текущим поворотом.
static func set_global_dir(bone: Bone2D, dir: Vector2, weight: float = 1.0, local_vec: Vector2 = Vector2.INF) -> void:
	if dir.length_squared() < 0.000001 or weight <= 0.0:
		return
	if local_vec == Vector2.INF:
		local_vec = chain_dir_local(bone)
	var parent := bone.get_parent() as Node2D
	var local := parent.global_transform.affine_inverse().basis_xform(dir)
	var target_rot := local.angle() - local_vec.angle()
	if weight >= 1.0:
		bone.rotation = target_rot
	else:
		bone.rotation = lerp_angle(bone.rotation, target_rot, weight)


## +1 если узел не отзеркален, -1 если отзеркален (scale.x < 0 где-то выше по дереву).
static func mirror_sign(node: Node2D) -> float:
	return -1.0 if node.global_transform.determinant() < 0.0 else 1.0


## Разница углов, приведённая к диапазону [-PI, PI].
static func wrap_angle(a: float) -> float:
	return wrapf(a, -PI, PI)
