class_name Player
extends CharacterBody2D
## Контроллер игрока: ходьба/бег/прыжок/присед/кувырок/скольжение по крутым склонам,
## захват уступов и подтягивание, прицеливание за курсором, стрельба и перезарядка,
## бокс (джеб/кросс), рагдолл от взрывов и жёстких падений с последующим вставанием.

enum State { IDLE, WALK, RUN, JUMP, FALL, LAND, CROUCH, ROLL, SLIDE, LEDGE_HANG, LEDGE_CLIMB, RAGDOLL, GET_UP }

const STATE_ANIM := {
	State.IDLE: &"idle", State.WALK: &"walk", State.RUN: &"run", State.JUMP: &"jump",
	State.FALL: &"fall", State.LAND: &"land", State.CROUCH: &"crouch_idle", State.ROLL: &"roll",
	State.SLIDE: &"slide", State.LEDGE_HANG: &"ledge_hang", State.LEDGE_CLIMB: &"ledge_climb",
	State.RAGDOLL: &"fall", State.GET_UP: &"get_up",
}
const STATE_NAMES := {
	State.IDLE: "Стоит", State.WALK: "Ходьба", State.RUN: "Бег", State.JUMP: "Прыжок",
	State.FALL: "Падение", State.LAND: "Приземление", State.CROUCH: "Присед", State.ROLL: "Кувырок",
	State.SLIDE: "Скольжение", State.LEDGE_HANG: "Висит на уступе", State.LEDGE_CLIMB: "Подтягивание",
	State.RAGDOLL: "Рагдолл", State.GET_UP: "Встаёт",
}
const GROUND_STATES := [State.IDLE, State.WALK, State.RUN, State.CROUCH, State.LAND, State.GET_UP]
const UPPER_BODY_STATES := [State.IDLE, State.WALK, State.RUN, State.CROUCH, State.JUMP, State.FALL, State.LAND]

const ACCEL := 2400.0
const AIR_ACCEL := 1300.0
const ROLL_TIME := 0.6
const LAND_TIME := 0.32
const CLIMB_TIME := 0.7
const GET_UP_TIME := 0.9
## Положение ног относительно угла уступа при висе (x — от стены, y — вниз).
const HANG_OFFSET := Vector2(16.0, 176.0)
const PUNCH_HIT_TIME := 0.12
const PUNCH_FORCE := 420.0

@export var walk_speed := 130.0
@export var run_speed := 300.0
@export var crouch_speed := 90.0
@export var roll_speed := 360.0
@export var jump_velocity := -560.0
@export var terminal_velocity := 1400.0
## Скорость падения, после которой приземление жёсткое (короткая потеря контроля).
@export var hard_land_speed := 700.0
## Скорость падения, после которой персонаж падает рагдоллом.
@export var ragdoll_land_speed := 1150.0
@export var magazine_size := 8
@export var fire_interval := 0.16
@export var bullet_scene: PackedScene
@export var foot_ik_enabled := true
## Длина шага (px) за один цикл анимации — от неё зависит скорость проигрывания, чтобы стопы не скользили.
@export var walk_stride := 90.0
@export var run_stride := 210.0
@export var crouch_stride := 60.0
## Если задано (не INF) — точка прицеливания берётся отсюда, а не из курсора (боты, тесты).
var aim_target_override := Vector2.INF

var state := State.IDLE
var state_time := 0.0
var facing := 1
var aiming := false
var ammo := 8
var reloading := false
var crouched := false
var fire_cooldown := 0.0
var reload_timer := 0.0
var punch_index := 1
var punch_timer := -1.0
var no_control_time := 0.0
var _ledge_corner := Vector2.ZERO
var _ledge_cooldown := 0.0
var _climb_from := Vector2.ZERO
var _climb_to := Vector2.ZERO

@onready var rig: CharacterRig2D = $Rig
@onready var shape_stand: CollisionShape2D = $ShapeStand
@onready var shape_crouch: CollisionShape2D = $ShapeCrouch
@onready var rays: Node2D = $Rays
@onready var wall_ray: RayCast2D = $Rays/WallRay
@onready var ledge_clear_ray: RayCast2D = $Rays/LedgeClearRay
@onready var ledge_down_ray: RayCast2D = $Rays/LedgeDownRay
@onready var ceiling_ray: RayCast2D = $Rays/CeilingRay
@onready var ground_ray: RayCast2D = $GroundRay
@onready var camera: ShakeCamera2D = $Camera2D


func _ready() -> void:
	ammo = magazine_size
	add_to_group("player")
	add_to_group("explodable")
	add_to_group("humanoid")
	rig.set_state(&"idle")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ragdoll_test"):
		start_ragdoll(Vector2(facing * 220.0, -320.0))
	elif event.is_action_pressed(&"toggle_foot_ik"):
		foot_ik_enabled = not foot_ik_enabled


func _physics_process(delta: float) -> void:
	state_time += delta
	fire_cooldown -= delta
	_ledge_cooldown -= delta
	match state:
		State.RAGDOLL:
			_process_ragdoll(delta)
		State.GET_UP:
			_process_get_up(delta)
		State.LEDGE_HANG:
			_process_ledge_hang(delta)
		State.LEDGE_CLIMB:
			_process_ledge_climb(delta)
		State.ROLL:
			_process_roll(delta)
		_:
			_process_locomotion(delta)
	_update_upper_body(delta)
	_update_rig(delta)


func get_state_name() -> String:
	return STATE_NAMES[state]


## Мировая точка, в которую целится персонаж (курсор или переопределение).
func get_aim_point() -> Vector2:
	if aim_target_override != Vector2.INF:
		return aim_target_override
	return get_global_mouse_position()


# --- Локомоция ----------------------------------------------------------------

func _process_locomotion(delta: float) -> void:
	var input_dir := Input.get_axis(&"move_left", &"move_right")
	var mouse := get_aim_point()
	if not is_on_floor():
		velocity.y = minf(velocity.y + get_gravity().y * delta, terminal_velocity)
	aiming = Input.is_action_pressed(&"aim") and state != State.SLIDE
	if aiming:
		facing = 1 if mouse.x >= global_position.x else -1
	elif absf(input_dir) > 0.1:
		facing = 1 if input_dir > 0.0 else -1
	var want_crouch := Input.is_action_pressed(&"crouch") and is_on_floor()
	if crouched and not want_crouch and _ceiling_blocked():
		want_crouch = true
	_set_crouched(want_crouch)
	var speed := run_speed
	if Input.is_action_pressed(&"walk") or aiming:
		speed = walk_speed
	if crouched:
		speed = crouch_speed
	var accel := ACCEL if is_on_floor() else AIR_ACCEL
	if state == State.SLIDE:
		accel *= 0.25
	velocity.x = move_toward(velocity.x, input_dir * speed, accel * delta)
	if no_control_time > 0.0:
		no_control_time -= delta
		velocity.x = move_toward(velocity.x, 0.0, ACCEL * delta)
	if Input.is_action_just_pressed(&"jump") and is_on_floor() and not crouched and no_control_time <= 0.0:
		velocity.y = jump_velocity
		_change_state(State.JUMP)
	elif Input.is_action_just_released(&"jump") and velocity.y < 0.0:
		velocity.y *= 0.55
	if Input.is_action_just_pressed(&"roll") and is_on_floor() and no_control_time <= 0.0 \
			and state in [State.IDLE, State.WALK, State.RUN, State.CROUCH, State.LAND]:
		_start_roll()
		return
	var prev_vy := velocity.y
	var was_on_floor := is_on_floor()
	move_and_slide()
	if is_on_floor():
		if not was_on_floor:
			_on_landed(prev_vy)
			if state == State.RAGDOLL:
				return
		if state == State.LAND and state_time < LAND_TIME:
			pass
		elif crouched:
			_change_state(State.CROUCH)
		elif absf(velocity.x) > 8.0:
			var run := absf(velocity.x) > (walk_speed + run_speed) * 0.5
			_change_state(State.RUN if run else State.WALK)
		else:
			_change_state(State.IDLE)
	else:
		if _is_on_steep_slope():
			if state != State.SLIDE:
				_change_state(State.SLIDE)
			facing = 1 if get_wall_normal().x >= 0.0 else -1
		elif velocity.y > 0.0:
			if state != State.FALL:
				_change_state(State.FALL)
			_try_ledge_grab()
		elif state == State.JUMP:
			if velocity.y > -160.0:
				_try_ledge_grab()
		elif state != State.FALL:
			_change_state(State.FALL)


func _on_landed(prev_vy: float) -> void:
	if prev_vy > ragdoll_land_speed:
		start_ragdoll(Vector2(velocity.x * 0.5, prev_vy * 0.35))
		get_tree().call_group(&"camera", &"shake", 12.0)
		return
	if prev_vy > hard_land_speed:
		no_control_time = 0.35
		_change_state(State.LAND)
		get_tree().call_group(&"camera", &"shake", 5.0)
	elif prev_vy > 420.0:
		_change_state(State.LAND)


func _is_on_steep_slope() -> bool:
	if not is_on_wall():
		return false
	var n := get_wall_normal()
	return n.y < -0.2 and absf(n.x) > 0.25


func _start_roll() -> void:
	_change_state(State.ROLL)
	velocity.x = facing * roll_speed
	aiming = false
	_set_crouched(true)


func _process_roll(delta: float) -> void:
	if not is_on_floor():
		velocity.y = minf(velocity.y + get_gravity().y * delta, terminal_velocity)
	var k := clampf(1.35 - state_time / ROLL_TIME * 1.1, 0.35, 1.0)
	velocity.x = facing * roll_speed * k
	move_and_slide()
	if state_time >= ROLL_TIME:
		_set_crouched(_ceiling_blocked())
		_change_state(State.CROUCH if crouched else State.IDLE)


# --- Уступы -------------------------------------------------------------------

func _try_ledge_grab() -> void:
	if velocity.y < -160.0 or _ledge_cooldown > 0.0:
		return
	rays.scale.x = float(facing)
	wall_ray.force_raycast_update()
	ledge_clear_ray.force_raycast_update()
	ledge_down_ray.force_raycast_update()
	if not wall_ray.is_colliding() or ledge_clear_ray.is_colliding() or not ledge_down_ray.is_colliding():
		return
	if absf(wall_ray.get_collision_normal().x) < 0.85:
		return
	if ledge_down_ray.get_collision_normal().y > -0.85:
		return
	_ledge_corner = Vector2(wall_ray.get_collision_point().x, ledge_down_ray.get_collision_point().y)
	global_position = Vector2(_ledge_corner.x - facing * HANG_OFFSET.x, _ledge_corner.y + HANG_OFFSET.y)
	velocity = Vector2.ZERO
	aiming = false
	_set_crouched(false)
	_change_state(State.LEDGE_HANG)


func _process_ledge_hang(_delta: float) -> void:
	velocity = Vector2.ZERO
	aiming = false
	if Input.is_action_just_pressed(&"jump"):
		_climb_from = global_position
		_climb_to = Vector2(_ledge_corner.x + facing * 20.0, _ledge_corner.y)
		_set_crouched(true)
		_change_state(State.LEDGE_CLIMB)
	elif Input.is_action_just_pressed(&"crouch") or Input.is_action_pressed(&"crouch"):
		_ledge_cooldown = 0.45
		global_position.x -= facing * 6.0
		velocity.y = 60.0
		_change_state(State.FALL)


func _process_ledge_climb(_delta: float) -> void:
	var t := clampf(state_time / CLIMB_TIME, 0.0, 1.0)
	var ty := smoothstep(0.0, 0.65, t)
	var tx := smoothstep(0.35, 1.0, t)
	global_position = Vector2(lerpf(_climb_from.x, _climb_to.x, tx), lerpf(_climb_from.y, _climb_to.y, ty))
	velocity = Vector2.ZERO
	if t >= 1.0:
		_set_crouched(_ceiling_blocked())
		_change_state(State.CROUCH if crouched else State.IDLE)


# --- Рагдолл ------------------------------------------------------------------

## Включает рагдолл с импульсом. [param origin] — центр взрыва (если есть).
func start_ragdoll(impulse: Vector2, origin: Vector2 = Vector2.INF) -> void:
	if state == State.RAGDOLL:
		return
	_change_state(State.RAGDOLL)
	shape_stand.disabled = true
	shape_crouch.disabled = true
	aiming = false
	reloading = false
	punch_timer = -1.0
	rig.start_ragdoll(velocity, impulse, origin)
	velocity = Vector2.ZERO


## Вызывается взрывом (группа «explodable»).
func explode_hit(origin: Vector2, force: float) -> void:
	var dir := (global_position + Vector2(0.0, -70.0) - origin).normalized()
	start_ragdoll(dir * force, origin)


## Удар по персонажу (кулак/пуля) — для игрока только толчок.
func hit(impulse: Vector2) -> void:
	velocity += impulse * 0.5


func _process_ragdoll(_delta: float) -> void:
	global_position = rig.ragdoll.get_pelvis_position()
	velocity = Vector2.ZERO
	if (state_time > 2.0 and rig.ragdoll.is_settled()) or state_time > 7.0:
		_recover_from_ragdoll()


func _recover_from_ragdoll() -> void:
	var p := rig.ragdoll.get_pelvis_position()
	ground_ray.global_position = p
	ground_ray.force_raycast_update()
	if ground_ray.is_colliding():
		global_position = ground_ray.get_collision_point()
	else:
		global_position = p + Vector2(0.0, 76.0)
	rig.stop_ragdoll()
	crouched = not crouched  # принудительно обновить формы коллизии
	_set_crouched(_ceiling_blocked())
	velocity = Vector2.ZERO
	_change_state(State.GET_UP)


func _process_get_up(delta: float) -> void:
	velocity.x = 0.0
	if not is_on_floor():
		velocity.y = minf(velocity.y + get_gravity().y * delta, terminal_velocity)
	move_and_slide()
	if state_time >= GET_UP_TIME:
		_change_state(State.IDLE)


# --- Верхняя часть тела: прицеливание, стрельба, перезарядка, бокс ---------------

func _update_upper_body(delta: float) -> void:
	var can_upper := state in UPPER_BODY_STATES
	rig.aim_target_global = get_aim_point()
	rig.aim_weight = 1.0 if (aiming and can_upper) else 0.0
	if reloading:
		reload_timer += delta
		if reload_timer > 0.3 and not rig.is_reloading():
			reloading = false
			ammo = magazine_size
	if aiming and can_upper and rig.is_aim_ready():
		if Input.is_action_just_pressed(&"reload") and ammo < magazine_size and not reloading:
			_reload()
		elif Input.is_action_pressed(&"shoot") and fire_cooldown <= 0.0 and not reloading and not rig.is_punching():
			if ammo > 0:
				_shoot()
			else:
				_reload()
	if Input.is_action_just_pressed(&"punch") and can_upper and not aiming and not rig.is_punching() and not reloading:
		_punch()
	if punch_timer >= 0.0:
		punch_timer += delta
		if punch_timer >= PUNCH_HIT_TIME:
			punch_timer = -1.0
			_punch_hit()
	rig.aim_ik.arms_weight = 0.0 if (reloading or rig.is_punching()) else 1.0


func _shoot() -> void:
	fire_cooldown = fire_interval
	ammo -= 1
	rig.fire_shot()
	if bullet_scene != null:
		var bullet := bullet_scene.instantiate() as Node2D
		get_parent().add_child(bullet)
		var muzzle := rig.get_muzzle_global()
		bullet.global_position = muzzle
		# Пуля летит в точку прицеливания; если курсор слишком близко или за спиной — вдоль ствола.
		var to_target := get_aim_point() - muzzle
		var dir := rig.get_aim_direction()
		if to_target.length() > 40.0 and to_target.x * facing > 0.0:
			dir = to_target.normalized()
		if bullet.has_method("setup"):
			bullet.call("setup", dir, self)
	camera.shake(2.0)


func _reload() -> void:
	reloading = true
	reload_timer = 0.0
	rig.start_reload()


func _punch() -> void:
	punch_index = 1 - punch_index
	rig.punch(&"jab" if punch_index == 0 else &"cross")
	punch_timer = 0.0


func _punch_hit() -> void:
	var impulse := Vector2(facing * PUNCH_FORCE, -160.0)
	var hit_any := false
	for body in rig.punch_hitbox.get_overlapping_bodies():
		if body == self:
			continue
		hit_any = true
		if body is RigidBody2D:
			(body as RigidBody2D).apply_central_impulse(impulse * (body as RigidBody2D).mass * 0.6)
		if body.has_method("hit"):
			body.call("hit", impulse)
	if hit_any:
		camera.shake(3.0)


# --- Обновление рига и параметров анимации ---------------------------------------

func _update_rig(delta: float) -> void:
	rig.facing = facing
	rays.scale.x = float(facing)
	rig.foot_ik.enabled = foot_ik_enabled and is_on_floor() and state in GROUND_STATES
	match state:
		State.LEDGE_HANG:
			rig.hands_ik.target_global = _ledge_corner
			rig.hands_ik.weight = move_toward(rig.hands_ik.weight, 1.0, delta * 10.0)
		State.LEDGE_CLIMB:
			rig.hands_ik.target_global = _ledge_corner
			rig.hands_ik.weight = 1.0 - smoothstep(0.4, 0.8, state_time / CLIMB_TIME)
		_:
			rig.hands_ik.weight = move_toward(rig.hands_ik.weight, 0.0, delta * 10.0)
	var moving := absf(velocity.x) > 8.0
	var backward := moving and signf(velocity.x) != float(facing)
	var dir_sign := -1.0 if backward else 1.0
	if state == State.CROUCH:
		rig.set_state(&"crouch_walk" if moving else &"crouch_idle")
		rig.set_time_scale(&"crouch_walk_ts", maxf(absf(velocity.x) / crouch_stride, 0.4) * dir_sign)
	rig.set_time_scale(&"walk_ts", maxf(absf(velocity.x) / walk_stride, 0.35) * dir_sign)
	rig.set_time_scale(&"run_ts", maxf(absf(velocity.x) / run_stride, 0.5) * dir_sign)
	var target_offset := Vector2(0.0, -90.0)
	if aiming:
		target_offset += (get_aim_point() - global_position) * 0.15
	camera.base_offset = camera.base_offset.lerp(target_offset, 1.0 - exp(-6.0 * delta))


func _change_state(new_state: State) -> void:
	if new_state == state:
		return
	state = new_state
	state_time = 0.0
	rig.set_state(STATE_ANIM[new_state])


func _set_crouched(value: bool) -> void:
	if value == crouched and shape_stand.disabled == value and shape_crouch.disabled == not value:
		return
	crouched = value
	shape_stand.disabled = value
	shape_crouch.disabled = not value


func _ceiling_blocked() -> bool:
	ceiling_ray.force_raycast_update()
	return ceiling_ray.is_colliding()
