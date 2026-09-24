class_name RagdollJoint2D
extends PinJoint2D
## Сустав рагдолла. Лимиты, заданные в инспекторе, считаются относительно позы покоя;
## при активации они пересчитываются под текущую позу и зеркало.

## Кость, начало которой является точкой сустава (относительно Skeleton2D).
@export var bone: NodePath

var base_lower := 0.0
var base_upper := 0.0


func _ready() -> void:
	base_lower = angular_limit_lower
	base_upper = angular_limit_upper
