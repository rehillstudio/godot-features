extends SceneTree
## Снимки поз персонажа для визуальной проверки (нужен реальный рендер, напр. под Xvfb):
## xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 -s tests/screenshots.gd -- /out/dir

var _player: Player
var _out := "/tmp"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	var level := (load("res://level/demo_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	_run()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_out, name])
	print("shot ", name)


func _teleport(pos: Vector2) -> void:
	_player.global_position = pos
	_player.velocity = Vector2.ZERO
	_player.camera.reset_smoothing()


func _run() -> void:
	await process_frame
	_player = get_first_node_in_group("player") as Player
	_player.camera.zoom = Vector2(3.0, 3.0)
	_player.camera.position_smoothing_enabled = false
	root.get_node("DemoLevel/HUD").visible = false
	await _frames(40)
	await _shot("01_idle")
	Input.action_press(&"move_right")
	await _frames(30)
	await _shot("02_run")
	Input.action_press(&"walk")
	await _frames(28)
	await _shot("03_walk")
	Input.action_release(&"walk")
	Input.action_press(&"crouch")
	await _frames(25)
	await _shot("04_crouch_walk")
	Input.action_release(&"move_right")
	await _frames(20)
	await _shot("05_crouch_idle")
	Input.action_release(&"crouch")
	await _frames(20)
	_player.aim_target_override = _player.global_position + Vector2(300.0, -200.0)
	Input.action_press(&"aim")
	await _frames(40)
	await _shot("06_aim_up_right")
	_player.aim_target_override = _player.global_position + Vector2(300.0, 120.0)
	await _frames(30)
	await _shot("07_aim_down_right")
	Input.action_press(&"shoot")
	await _frames(2)
	Input.action_release(&"shoot")
	await _shot("08_shoot")
	Input.action_press(&"reload")
	await _frames(2)
	Input.action_release(&"reload")
	await _frames(28)
	await _shot("09_reload_mid")
	await _frames(70)
	_player.aim_target_override = _player.global_position + Vector2(-300.0, -60.0)
	await _frames(30)
	await _shot("10_aim_left")
	Input.action_release(&"aim")
	_player.aim_target_override = Vector2.INF
	await _frames(30)
	Input.action_press(&"punch")
	await _frames(2)
	Input.action_release(&"punch")
	await _frames(6)
	await _shot("11_punch_jab")
	await _frames(25)
	Input.action_press(&"punch")
	await _frames(2)
	Input.action_release(&"punch")
	await _frames(8)
	await _shot("12_punch_cross")
	await _frames(30)
	Input.action_press(&"jump")
	await _frames(2)
	Input.action_release(&"jump")
	await _frames(12)
	await _shot("13_jump")
	await _frames(25)
	await _shot("14_fall")
	await _frames(40)
	Input.action_press(&"roll")
	await _frames(2)
	Input.action_release(&"roll")
	await _frames(16)
	await _shot("15_roll")
	await _frames(40)
	_teleport(Vector2(758.0, -79.0))
	await _frames(60)
	await _shot("16_stairs_ik")
	_player.foot_ik_enabled = false
	await _frames(40)
	await _shot("17_stairs_no_ik")
	_player.foot_ik_enabled = true
	_teleport(Vector2(1300.0, -100.0))
	await _frames(60)
	await _shot("18_slope_ik")
	_teleport(Vector2(1640.0, 0.0))
	_player.facing = 1
	await _frames(15)
	Input.action_press(&"move_right")
	Input.action_press(&"jump")
	await _frames(2)
	Input.action_release(&"jump")
	for i in 90:
		await physics_frame
		if _player.state == Player.State.LEDGE_HANG:
			break
	Input.action_release(&"move_right")
	await _frames(15)
	await _shot("19_ledge_hang")
	Input.action_press(&"jump")
	await _frames(2)
	Input.action_release(&"jump")
	await _frames(20)
	await _shot("20_ledge_climb")
	await _frames(40)
	_teleport(Vector2(2230.0, -160.0))
	await _frames(25)
	await _shot("21_slide")
	await _frames(60)
	_teleport(Vector2(2300.0, 0.0))
	await _frames(20)
	_player.start_ragdoll(Vector2(250.0, -450.0))
	await _frames(25)
	await _shot("22_ragdoll_air")
	await _frames(90)
	await _shot("23_ragdoll_ground")
	for i in 400:
		await physics_frame
		if _player.state == Player.State.GET_UP:
			break
	await _frames(15)
	await _shot("24_get_up")
	await _frames(60)
	_player.rig.skin = load("res://character/skins/skin_soldier.tres")
	await _frames(10)
	await _shot("25_skin_soldier")
	_player.rig.skin = load("res://character/skins/skin_casual.tres")
	await _frames(10)
	await _shot("26_skin_casual")
	_player.rig.skin = load("res://character/skins/skin_default.tres")
	_player.camera.zoom = Vector2(0.9, 0.9)
	_teleport(Vector2(2520.0, 0.0))
	await _frames(20)
	(root.get_node("DemoLevel/Barrels").get_child(0) as RigidBody2D).call("explode")
	await _frames(14)
	await _shot("27_explosion")
	await _frames(40)
	await _shot("28_after_explosion")
	_player.camera.zoom = Vector2(0.6, 0.6)
	await _frames(300)
	_teleport(Vector2(200.0, 0.0))
	await _frames(20)
	await _shot("29_overview")
	quit()
