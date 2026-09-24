extends CPUParticles2D
## Искры от попадания: одноразовые частицы, удаляются по окончании.


func _ready() -> void:
	emitting = true
	finished.connect(queue_free)
