class_name HandsIK2D
extends Node
## Кладёт обе кисти на точку (угол уступа) — используется при захвате уступа и подтягивании.

@export var arm_ik_front: NodePath
@export var arm_ik_back: NodePath
@export var hand_front: NodePath
@export var hand_back: NodePath
## Смещения кистей от точки захвата в локальных координатах рига (+X — вперёд).
@export var offset_front := Vector2(7.0, 3.0)
@export var offset_back := Vector2(-3.0, 3.0)

var weight := 0.0
var target_global := Vector2.ZERO

var _arm_f: TwoBoneIK2D
var _arm_b: TwoBoneIK2D
var _hand_f: Bone2D
var _hand_b: Bone2D


func _ready() -> void:
	_arm_f = get_node(arm_ik_front) as TwoBoneIK2D
	_arm_b = get_node(arm_ik_back) as TwoBoneIK2D
	_hand_f = get_node(hand_front) as Bone2D
	_hand_b = get_node(hand_back) as Bone2D


func apply(rig: Node2D) -> void:
	if weight <= 0.001:
		return
	var visual := rig.get_node("Visual") as Node2D
	var b := visual.global_transform
	var p_f := target_global + b.basis_xform(offset_front)
	var p_b := target_global + b.basis_xform(offset_back)
	_arm_f.solve_global(p_f, weight)
	_arm_b.solve_global(p_b, weight)
	var grip_dir := b.basis_xform(Vector2(1.0, 0.6)).normalized()
	BoneMath2D.set_global_dir(_hand_f, grip_dir, weight)
	BoneMath2D.set_global_dir(_hand_b, grip_dir, weight)
