extends SceneTree
## Smoke-тест без окна: godot --headless --path . -s tests/smoke_test.gd
## Загружает демо-уровень, эмулирует ввод и проверяет ключевые состояния персонажа.

var _failed := 0
var _passed := 0
var _player: Player


func _initialize() -> void:
	var level := (load("res://level/demo_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	_run()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
		print("  [OK]   ", what)
	else:
		_failed += 1
		print("  [FAIL] ", what)


func _teleport(pos: Vector2) -> void:
	_player.global_position = pos
	_player.velocity = Vector2.ZERO


func _set_mouse(world_pos: Vector2) -> void:
	# В headless-режиме позиции курсора нет — используем переопределение точки прицеливания.
	_player.aim_target_override = world_pos


func _run() -> void:
	await process_frame
	_player = get_first_node_in_group("player") as Player
	_check(_player != null, "игрок найден")
	var rig := _player.rig
	await _frames(40)
	_check(_player.is_on_floor(), "стоит на полу")
	_check(_player.state == Player.State.IDLE, "состояние idle")
	_check(rig.get_state() == &"idle", "AnimationTree: idle")

	print("-- бег / ходьба / присед")
	Input.action_press(&"move_right")
	await _frames(45)
	_check(_player.state == Player.State.RUN, "бег (state=%d)" % _player.state)
	_check(_player.velocity.x > 200.0, "скорость бега %.0f" % _player.velocity.x)
	Input.action_press(&"walk")
	await _frames(45)
	_check(_player.state == Player.State.WALK, "ходьба с Shift")
	Input.action_release(&"walk")
	Input.action_press(&"crouch")
	await _frames(30)
	_check(_player.state == Player.State.CROUCH and _player.crouched, "присед + ходьба в приседе")
	_check(rig.get_state() == &"crouch_walk", "AnimationTree: crouch_walk")
	Input.action_release(&"crouch")
	Input.action_release(&"move_right")
	await _frames(30)
	_check(_player.state == Player.State.IDLE, "снова idle")

	print("-- прыжок")
	Input.action_press(&"jump")
	await _frames(3)
	Input.action_release(&"jump")
	_check(_player.state == Player.State.JUMP, "прыжок")
	await _frames(40)
	_check(_player.state == Player.State.FALL or _player.state == Player.State.LAND or _player.state == Player.State.IDLE, "падение/приземление (state=%d)" % _player.state)
	await _frames(60)
	_check(_player.state == Player.State.IDLE, "приземлился в idle")

	print("-- кувырок")
	var x0 := _player.global_position.x
	Input.action_press(&"roll")
	await _frames(3)
	Input.action_release(&"roll")
	_check(_player.state == Player.State.ROLL, "кувырок")
	await _frames(50)
	_check(_player.global_position.x > x0 + 80.0, "кувырок сдвинул вперёд на %.0f" % (_player.global_position.x - x0))
	_check(_player.state == Player.State.IDLE, "после кувырка idle")

	print("-- прицеливание / выстрел / перезарядка")
	_set_mouse(_player.global_position + Vector2(300.0, -260.0))
	Input.action_press(&"aim")
	await _frames(40)
	_check(_player.aiming, "aiming")
	_check(rig.anim_tree.get("parameters/aim/blend_amount") > 0.9, "aim blend = %.2f" % rig.anim_tree.get("parameters/aim/blend_amount"))
	_check(rig.pistol.visible and not rig.holster.visible, "пистолет в руке, кобура скрыта")
	var aim_dir: Vector2 = rig.get_aim_direction()
	_check(aim_dir.x > 0.5 and aim_dir.y < -0.2, "ствол направлен к курсору (%.2f, %.2f)" % [aim_dir.x, aim_dir.y])
	var head := rig.skeleton.get_node("Hips/Torso/Neck/Head") as Bone2D
	_check(absf(head.rotation_degrees) > 5.0, "голова повернулась к цели (%.1f°)" % head.rotation_degrees)
	var ammo0 := _player.ammo
	Input.action_press(&"shoot")
	await _frames(3)
	Input.action_release(&"shoot")
	await _frames(2)
	_check(_player.ammo == ammo0 - 1, "патрон израсходован")
	var bullets := 0
	for n in root.get_node("DemoLevel").get_children():
		if n is Bullet:
			bullets += 1
	_check(bullets == 1, "пуля создана")
	Input.action_press(&"reload")
	await _frames(3)
	Input.action_release(&"reload")
	await _frames(10)
	_check(_player.reloading and rig.is_reloading(), "перезарядка идёт")
	await _frames(100)
	_check(not _player.reloading and _player.ammo == _player.magazine_size, "перезарядка завершена, магазин полон")
	# Разворот к курсору слева.
	_set_mouse(_player.global_position + Vector2(-300.0, -100.0))
	await _frames(20)
	_check(_player.facing == -1 and rig.visual.scale.x < 0.0, "развернулся к курсору влево")
	aim_dir = rig.get_aim_direction()
	_check(aim_dir.x < -0.5, "ствол смотрит влево (%.2f, %.2f)" % [aim_dir.x, aim_dir.y])
	Input.action_release(&"aim")
	await _frames(30)
	_check(not rig.pistol.visible and rig.holster.visible, "пистолет убран в кобуру")

	print("-- удар кулаком")
	Input.action_press(&"punch")
	await _frames(3)
	Input.action_release(&"punch")
	await _frames(4)
	_check(rig.is_punching(), "анимация удара активна")
	await _frames(40)
	_check(not rig.is_punching(), "удар закончился")

	print("-- IK ног на лестнице")
	_teleport(Vector2(758.0, -79.0))
	await _frames(70)
	_check(_player.is_on_floor(), "стоит на рампе лестницы")
	var foot_ik := rig.foot_ik
	var off: Array = foot_ik._offsets
	_check(absf(off[0]) > 1.0 or absf(off[1]) > 1.0, "IK сместил стопы к ступеням (%.1f, %.1f)" % [off[0], off[1]])
	var foot_f := rig.skeleton.get_node("Hips/Thigh_F/Shin_F/Foot_F") as Bone2D
	var foot_b := rig.skeleton.get_node("Hips/Thigh_B/Shin_B/Foot_B") as Bone2D
	_check(absf(foot_f.global_position.y - foot_b.global_position.y) > 4.0, "стопы на разной высоте (%.1f / %.1f)" % [foot_f.global_position.y, foot_b.global_position.y])
	_player.foot_ik_enabled = false
	await _frames(40)
	_check(absf(foot_ik._offsets[0]) < 0.5 and absf(foot_ik._offsets[1]) < 0.5, "IK выключен — смещения обнулились")
	_player.foot_ik_enabled = true

	print("-- захват уступа")
	_teleport(Vector2(1640.0, 0.0))
	_player.facing = 1
	await _frames(20)
	Input.action_press(&"move_right")
	Input.action_press(&"jump")
	await _frames(3)
	Input.action_release(&"jump")
	var hung := false
	for i in 90:
		await physics_frame
		if _player.state == Player.State.LEDGE_HANG:
			hung = true
			break
	Input.action_release(&"move_right")
	_check(hung, "зацепился за уступ")
	await _frames(10)
	_check(rig.hands_ik.weight > 0.9, "IK кистей включён (%.2f)" % rig.hands_ik.weight)
	var hand := rig.skeleton.get_node("Hips/Torso/UpperArm_F/Forearm_F/Hand_F") as Bone2D
	_check(hand.global_position.distance_to(Vector2(1700.0, -200.0)) < 40.0, "кисть у угла уступа (%.0f, %.0f)" % [hand.global_position.x, hand.global_position.y])
	Input.action_press(&"jump")
	await _frames(3)
	Input.action_release(&"jump")
	_check(_player.state == Player.State.LEDGE_CLIMB, "подтягивание")
	await _frames(60)
	_check(_player.state == Player.State.IDLE and _player.global_position.y < -190.0, "залез наверх (y=%.0f)" % _player.global_position.y)

	print("-- скольжение по крутому склону")
	_teleport(Vector2(2230.0, -160.0))
	var slid := false
	for i in 90:
		await physics_frame
		if _player.state == Player.State.SLIDE:
			slid = true
			break
	_check(slid, "состояние SLIDE на склоне 56°")
	await _frames(20)
	_check(_player.state == Player.State.SLIDE and _player.global_position.x > 2240.0, "скользит вниз по склону (x=%.0f)" % _player.global_position.x)
	await _frames(90)

	print("-- рагдолл по клавише и вставание")
	_teleport(Vector2(2300.0, 0.0))
	await _frames(20)
	_player.start_ragdoll(Vector2(200.0, -400.0))
	await _frames(5)
	_check(_player.state == Player.State.RAGDOLL and rig.ragdoll.active, "рагдолл активен")
	var pelvis := rig.ragdoll.get_pelvis_body()
	_check(not pelvis.freeze and pelvis.collision_layer != 0, "тела рагдолла разморожены")
	await _frames(60)
	_check(_player.global_position.distance_to(pelvis.global_position) < 1.0, "игрок следует за тазом рагдолла")
	var recovered := false
	for i in 500:
		await physics_frame
		if _player.state == Player.State.GET_UP:
			recovered = true
			break
	_check(recovered, "встаёт после рагдолла")
	await _frames(70)
	_check(_player.state == Player.State.IDLE and _player.is_on_floor(), "после вставания idle на полу")

	print("-- взрыв бочек и манекен")
	_teleport(Vector2(2420.0, 0.0))
	_player.facing = 1
	await _frames(20)
	var barrels_before := root.get_node("DemoLevel/Barrels").get_child_count()
	var barrel := root.get_node("DemoLevel/Barrels").get_child(0) as RigidBody2D
	barrel.call("explode")
	await _frames(90)
	var barrels_after := root.get_node("DemoLevel/Barrels").get_child_count()
	_check(barrels_after < barrels_before - 1, "цепная реакция бочек (%d -> %d)" % [barrels_before, barrels_after])
	_check(_player.state == Player.State.RAGDOLL, "взрыв включил рагдолл игрока")
	var dummy := root.get_node("DemoLevel/Dummies/Dummy1") as CharacterBody2D
	var drig := dummy.get_node("Rig") as CharacterRig2D
	_check(not drig.ragdoll.active, "манекен вдали не задет")
	dummy.call("bullet_hit", dummy.global_position + Vector2(0, -80), Vector2.LEFT)
	await _frames(5)
	_check(drig.ragdoll.active, "манекен упал от пули")
	for i in 700:
		await physics_frame
		if not drig.ragdoll.active:
			break
	_check(not drig.ragdoll.active, "манекен встал")

	print("-- кастомизация")
	var skin_soldier := load("res://character/skins/skin_soldier.tres") as CharacterSkin
	rig.skin = skin_soldier
	_check(rig.is_gear_visible(&"helmet") and rig.is_gear_visible(&"knee_pads"), "скин «Солдат»: каска и наколенники видны")
	var torso_part := rig.skeleton.get_node("Hips/Torso/Part") as Sprite2D
	_check(torso_part.texture == skin_soldier.torso, "текстура торса заменена")
	rig.set_gear(&"cap", true)
	_check(rig.is_gear_visible(&"cap"), "кепка включена вручную")

	print("\n%d OK, %d FAIL" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
