extends Node2D
## Демо-уровень: задаёт лимиты камеры по маркерам, перезапуск (F5) и выход (Esc).

@onready var camera_min: Marker2D = $CameraLimitMin
@onready var camera_max: Marker2D = $CameraLimitMax


func _ready() -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	if player != null:
		var cam := player.camera
		cam.limit_left = int(camera_min.global_position.x)
		cam.limit_top = int(camera_min.global_position.y)
		cam.limit_right = int(camera_max.global_position.x)
		cam.limit_bottom = int(camera_max.global_position.y)
		cam.reset_smoothing()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"restart"):
		get_tree().reload_current_scene()
	elif event.is_action_pressed(&"quit"):
		get_tree().quit()
