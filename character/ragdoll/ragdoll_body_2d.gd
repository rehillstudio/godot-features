class_name RagdollBody2D
extends RigidBody2D
## Физическое тело одной кости рагдолла. Локальный +X тела направлен вдоль кости
## (или против неё, если [member reverse] — для костей, смотрящих вверх: таз, торс, голова).

## Путь к кости относительно Skeleton2D.
@export var bone: NodePath
## Тело ориентировано против направления кости (все тела в позе покоя смотрят вниз — так
## лимиты суставов не проходят через 180°).
@export var reverse := false
## Кости без собственных тел, которые просто выпрямляются вслед за этой (шея, кисть, стопа).
@export var passive_bones: Array[NodePath] = []
## Доля импульса (взрыв/удар), которую получает это тело. Конечностям даём меньше,
## чтобы они «отставали» и рагдолл болтался, а не летел жёсткой статуей.
@export_range(0.0, 1.0) var impulse_scale := 1.0

var active_layer := 0
var active_mask := 0


func _ready() -> void:
	top_level = true
	active_layer = collision_layer
	active_mask = collision_mask
	collision_layer = 0
	collision_mask = 0
	freeze = true
	freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
