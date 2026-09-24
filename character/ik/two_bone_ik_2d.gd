class_name TwoBoneIK2D
extends Node
## Аналитический двухкостный IK для цепочки Bone2D (плечо → локоть → кисть, бедро → колено → стопа).
## Ставится как узел-модификатор в риг. Может работать сам (по [member target]),
## либо вызываться другими модификаторами через [method solve_global].

@export var enabled := true
## Первая кость цепочки (плечо / бедро).
@export var upper_bone: NodePath
## Вторая кость цепочки (предплечье / голень).
@export var lower_bone: NodePath
## Конечная кость (кисть / стопа) — используется только для вычисления длины второй кости.
@export var end_bone: NodePath
## Необязательная цель (Node2D). Если задана — модификатор решает IK сам при каждом кадре.
@export var target: NodePath
## В какую сторону выгибается сустав: +1 — колено вперёд (для ног), -1 — локоть назад (для рук).
@export_range(-1.0, 1.0, 2.0) var bend_direction := 1.0
@export_range(0.0, 1.0) var weight := 1.0

var _upper: Bone2D
var _lower: Bone2D
var _end: Bone2D
var _target: Node2D
var upper_length := 0.0
var lower_length := 0.0


func _ready() -> void:
	_upper = get_node_or_null(upper_bone) as Bone2D
	_lower = get_node_or_null(lower_bone) as Bone2D
	_end = get_node_or_null(end_bone) as Bone2D
	_target = get_node_or_null(target) as Node2D
	if _upper == null or _lower == null:
		push_warning("TwoBoneIK2D '%s': не заданы кости." % name)
		return
	upper_length = _lower.position.length()
	lower_length = _end.position.length() if _end != null else _lower.get_length()


## Полная досягаемость цепочки.
func reach() -> float:
	return upper_length + lower_length


func root_global() -> Vector2:
	return _upper.global_position


## Вызывается ригом каждый кадр после применения анимации.
func apply(_rig: Node2D) -> void:
	if enabled and _target != null and weight > 0.0:
		solve_global(_target.global_position, weight)


## Решает IK так, чтобы конец второй кости оказался в мировой точке [param target_global].
func solve_global(target_global: Vector2, w: float = 1.0) -> void:
	if _upper == null or _lower == null or w <= 0.0:
		return
	var a := upper_length
	var b := lower_length
	var root := _upper.global_position
	var to_target := target_global - root
	if to_target.length_squared() < 0.0001:
		return
	var d := clampf(to_target.length(), absf(a - b) + 0.01, a + b - 0.01)
	var dir := to_target.normalized()
	var cos_a := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var ang_a := acos(cos_a)
	# В зеркале направление изгиба меняется на противоположное.
	var bend := bend_direction * BoneMath2D.mirror_sign(_upper)
	var upper_dir := dir.rotated(-ang_a * bend)
	BoneMath2D.set_global_dir(_upper, upper_dir, w)
	var lower_dir := (target_global - _lower.global_position).normalized()
	BoneMath2D.set_global_dir(_lower, lower_dir, w)
