class_name CharacterRig2D
extends Node2D
## Риг персонажа: Skeleton2D + модульные спрайты частей тела/экипировки + AnimationPlayer/AnimationTree,
## стек модификаторов (IK ног, прицеливание, IK кистей) и рагдолл.
## Модификаторы применяются после анимации (сигнал AnimationMixer.mixer_applied), в порядке
## узлов внутри Modifiers — аналог SkeletonModificationStack2D, но устойчивый к зеркалированию.

## Внешний вид (текстуры слотов и экипировка). Меняется в инспекторе или через set_skin().
@export var skin: CharacterSkin: set = set_skin
## Направление взгляда: 1 — вправо, -1 — влево (Visual.scale.x).
@export_range(-1, 1, 2) var facing := 1: set = set_facing
## Мировая точка прицеливания (курсор).
@export var aim_target_global := Vector2.ZERO
## Целевой вес прицеливания (0 — руки по анимации, 1 — руки/голова/торс на цель).
@export_range(0.0, 1.0) var aim_weight := 0.0
@export var aim_blend_speed := 7.0

@onready var visual: Node2D = $Visual
@onready var skeleton: Skeleton2D = $Visual/Skeleton2D
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var anim_tree: AnimationTree = $AnimationTree
@onready var modifiers: Node = $Modifiers
@onready var foot_ik: FootIK2D = $Modifiers/FootIK
@onready var aim_ik: AimIK2D = $Modifiers/AimIK
@onready var hands_ik: HandsIK2D = $Modifiers/HandsIK
@onready var ragdoll: Ragdoll2D = $Ragdoll
@onready var pistol: Node2D = %Pistol
@onready var holster: CanvasItem = %Holster
@onready var punch_hitbox: Area2D = %PunchHitbox

var _aim_current := 0.0
var _parts: Dictionary = {}  # StringName -> Array[Sprite2D]
var _gear: Dictionary = {}   # StringName -> Array[CanvasItem]


func _ready() -> void:
	_collect(visual)
	set_facing(facing)
	anim_tree.active = true
	anim_tree.mixer_applied.connect(_on_mixer_applied)
	# Transition не начинает проигрывать стартовый вход сам — запрашиваем его явно.
	anim_tree.set("parameters/state/transition_request", anim_tree.get("parameters/state/current_state"))
	if skin != null:
		apply_skin()


func _process(delta: float) -> void:
	_aim_current = move_toward(_aim_current, aim_weight, aim_blend_speed * delta)
	anim_tree.set("parameters/aim/blend_amount", _aim_current)
	aim_ik.weight = _aim_current
	aim_ik.target_global = aim_target_global
	var weapon_out := _aim_current > 0.5
	pistol.visible = weapon_out
	holster.visible = not weapon_out


func _on_mixer_applied() -> void:
	if ragdoll.active:
		ragdoll.apply_to_bones()
		return
	for m in modifiers.get_children():
		if m.has_method("apply"):
			m.apply(self)
	ragdoll.apply_recovery()


# --- Состояния анимации -------------------------------------------------------

func set_state(state: StringName) -> void:
	if anim_tree.get("parameters/state/current_state") != state:
		anim_tree.set("parameters/state/transition_request", state)


func get_state() -> StringName:
	return anim_tree.get("parameters/state/current_state")


func set_time_scale(param: StringName, value: float) -> void:
	anim_tree.set("parameters/%s/scale" % param, value)


func fire_shot() -> void:
	anim_tree.set("parameters/shoot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	aim_ik.add_recoil()
	if pistol.has_method("fire"):
		pistol.call("fire")


func start_reload() -> void:
	anim_tree.set("parameters/reload/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func is_reloading() -> bool:
	return bool(anim_tree.get("parameters/reload/active"))


func punch(kind: StringName) -> void:
	anim_tree.set("parameters/punch_sel/transition_request", kind)
	anim_tree.set("parameters/punch/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func is_punching() -> bool:
	return bool(anim_tree.get("parameters/punch/active"))


func abort_upper() -> void:
	anim_tree.set("parameters/reload/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	anim_tree.set("parameters/punch/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)


## Прицел полностью сведён (руки уже на цели) — можно стрелять.
func is_aim_ready() -> bool:
	return _aim_current > 0.85


func get_muzzle_global() -> Vector2:
	var m := pistol.get_node_or_null("Muzzle") as Node2D
	return m.global_position if m != null else pistol.global_position


func get_aim_direction() -> Vector2:
	return aim_ik.get_aim_direction()


# --- Рагдолл ----------------------------------------------------------------------

func start_ragdoll(velocity: Vector2, impulse: Vector2 = Vector2.ZERO, origin: Vector2 = Vector2.INF) -> void:
	aim_weight = 0.0
	_aim_current = 0.0
	abort_upper()
	ragdoll.activate(velocity, impulse, origin)


func stop_ragdoll() -> void:
	ragdoll.deactivate()


# --- Кастомизация -------------------------------------------------------------

func set_facing(value: int) -> void:
	facing = 1 if value >= 0 else -1
	if visual != null:
		visual.scale.x = float(facing)


func set_skin(value: CharacterSkin) -> void:
	skin = value
	if is_node_ready():
		apply_skin()


func apply_skin() -> void:
	if skin == null:
		return
	for slot: StringName in _parts:
		var tex := skin.get_slot_texture(slot)
		if tex == null:
			continue
		for sprite: Sprite2D in _parts[slot]:
			sprite.texture = tex
	for id: StringName in _gear:
		set_gear(id, id in skin.gear)


## Показывает/скрывает элемент экипировки по идентификатору (метаданные gear_id у спрайтов).
func set_gear(id: StringName, visible_now: bool) -> void:
	if not _gear.has(id):
		return
	for item: CanvasItem in _gear[id]:
		item.visible = visible_now


func is_gear_visible(id: StringName) -> bool:
	return _gear.has(id) and (_gear[id][0] as CanvasItem).visible


func get_gear_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in _gear:
		out.append(id)
	return out


func get_part_slots() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in _parts:
		out.append(id)
	return out


func _collect(node: Node) -> void:
	for c in node.get_children():
		if c.has_meta("part_slot") and c is Sprite2D:
			var slot: StringName = c.get_meta("part_slot")
			if not _parts.has(slot):
				_parts[slot] = []
			_parts[slot].append(c)
		if c.has_meta("gear_id") and c is CanvasItem:
			var id: StringName = c.get_meta("gear_id")
			if not _gear.has(id):
				_gear[id] = []
			_gear[id].append(c)
		_collect(c)
