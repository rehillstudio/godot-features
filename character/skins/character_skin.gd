class_name CharacterSkin
extends Resource
## Набор внешнего вида персонажа: текстуры для слотов частей тела и список видимой экипировки.
## Слот у спрайта задаётся метаданными «part_slot», экипировка — метаданными «gear_id».

@export var skin_name := "Default"

@export_group("Слоты частей тела")
@export var head: Texture2D
@export var torso: Texture2D
@export var hips: Texture2D
@export var upper_arm: Texture2D
@export var forearm: Texture2D
@export var hand: Texture2D
@export var thigh: Texture2D
@export var shin: Texture2D
@export var foot: Texture2D

@export_group("Экипировка")
## Идентификаторы видимой экипировки: cap, helmet, knee_pads, elbow_pads, backpack.
@export var gear: Array[StringName] = []


func get_slot_texture(slot: StringName) -> Texture2D:
	return get(slot) as Texture2D
