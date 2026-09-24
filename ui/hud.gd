extends CanvasLayer
## HUD: состояние, патроны, подсказки и панель кастомизации (экипировка + скины).

const GEAR_ACTIONS := {
	&"gear_1": &"cap", &"gear_2": &"helmet", &"gear_3": &"knee_pads", &"gear_4": &"elbow_pads", &"gear_5": &"backpack",
}

## Скины, доступные в выпадающем списке (ресурсы CharacterSkin).
@export var skins: Array[CharacterSkin] = []

var _player: Player
var _buttons: Dictionary = {}

@onready var state_label: Label = %StateLabel
@onready var ammo_label: Label = %AmmoLabel
@onready var ik_label: Label = %IKLabel
@onready var gear_box: VBoxContainer = %GearBox
@onready var skin_option: OptionButton = %SkinOption


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player") as Player
	for child in gear_box.get_children():
		if child is CheckButton and child.has_meta("gear_id"):
			var id: StringName = child.get_meta("gear_id")
			_buttons[id] = child
			child.toggled.connect(_on_gear_toggled.bind(id))
	for i in skins.size():
		skin_option.add_item(skins[i].skin_name, i)
	skin_option.item_selected.connect(_on_skin_selected)
	_sync_buttons()


func _process(_delta: float) -> void:
	if _player == null:
		return
	state_label.text = "Состояние: %s" % _player.get_state_name()
	ammo_label.text = "Патроны: %d / %d%s" % [_player.ammo, _player.magazine_size, "  (перезарядка…)" if _player.reloading else ""]
	ik_label.text = "IK ног (T): %s" % ("вкл" if _player.foot_ik_enabled else "выкл")


func _unhandled_input(event: InputEvent) -> void:
	if _player == null:
		return
	for action: StringName in GEAR_ACTIONS:
		if event.is_action_pressed(action):
			var id: StringName = GEAR_ACTIONS[action]
			_player.rig.set_gear(id, not _player.rig.is_gear_visible(id))
			_sync_buttons()
	if event.is_action_pressed(&"gear_6") and skins.size() > 0:
		var next := (skin_option.selected + 1) % skins.size()
		skin_option.select(next)
		_on_skin_selected(next)


func _on_gear_toggled(pressed: bool, id: StringName) -> void:
	_player.rig.set_gear(id, pressed)


func _on_skin_selected(index: int) -> void:
	_player.rig.skin = skins[index]
	_sync_buttons()


func _sync_buttons() -> void:
	for id: StringName in _buttons:
		var b := _buttons[id] as CheckButton
		b.set_pressed_no_signal(_player.rig.is_gear_visible(id))
