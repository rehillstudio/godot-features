class_name RagdollJoint2D
extends PinJoint2D
## Сустав рагдолла: PinJoint2D держит точку, а угловые лимиты и «мышечная» пружина
## считаются в Ragdoll2D по реальному относительному углу тел (B − A).
## Значения задаются для персонажа, смотрящего вправо; при развороте зеркалируются.

## Кость, начало которой является точкой сустава (относительно Skeleton2D).
@export var bone: NodePath
## Минимальный относительный угол (рад). Например колено: 0 — прямая нога.
@export var limit_lower := -1.0
## Максимальный относительный угол (рад). Например колено: 2.3 — согнута назад.
@export var limit_upper := 1.0
## Угол покоя, к которому слабо тянет «мышечная» пружина.
@export var rest_angle := 0.0

var body_a: RagdollBody2D
var body_b: RagdollBody2D


func _ready() -> void:
	body_a = get_node_or_null(node_a) as RagdollBody2D
	body_b = get_node_or_null(node_b) as RagdollBody2D
