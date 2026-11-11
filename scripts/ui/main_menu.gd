# Menú principal: lo primero que se ve al abrir el juego. "Nueva partida" empieza de
# cero; "Cargar partida" muestra el autoguardado y las ranuras manuales.
extends Control

const GAME_SCENE_PATH: String = "res://scenes/main.tscn"
const SLOT_BUTTON_SIZE := Vector2(460, 44)

@onready var _new_game_button: Button = %NewGameButton
@onready var _load_button: Button = %LoadButton
@onready var _load_list: VBoxContainer = %LoadList


func _ready() -> void:
	_new_game_button.pressed.connect(_on_new_game_pressed)
	_load_button.pressed.connect(_show_load_list.bind(true))
	_load_button.disabled = not SaveManager.has_any_save()
	_build_load_list()
	_new_game_button.grab_focus()


## Botón de una ranura en la lista de carga (null si no existe).
func get_slot_button(slot: String) -> Button:
	return _load_list.get_node_or_null(slot) as Button


func _build_load_list() -> void:
	var slots: Array[String] = [SaveManager.AUTOSAVE]
	slots.append_array(SaveManager.get_manual_slots())
	for slot: String in slots:
		var button := Button.new()
		button.name = slot
		button.text = SaveManager.describe_slot(slot)
		button.custom_minimum_size = SLOT_BUTTON_SIZE
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.disabled = not SaveManager.has_save(slot)
		button.pressed.connect(_on_slot_pressed.bind(slot))
		_load_list.add_child(button)
	var back := Button.new()
	back.name = "Back"
	back.text = "Volver"
	back.custom_minimum_size = SLOT_BUTTON_SIZE
	back.pressed.connect(_show_load_list.bind(false))
	_load_list.add_child(back)


func _show_load_list(shown: bool) -> void:
	_load_list.visible = shown
	_new_game_button.visible = not shown
	_load_button.visible = not shown


func _on_new_game_pressed() -> void:
	SaveManager.new_game()
	get_tree().change_scene_to_file(GAME_SCENE_PATH)


func _on_slot_pressed(slot: String) -> void:
	if SaveManager.load_game(slot):
		get_tree().change_scene_to_file(GAME_SCENE_PATH)
	else:
		var button: Button = get_slot_button(slot)
		button.text = "%s — no se pudo cargar" % SaveManager.get_slot_name(slot)
		button.disabled = true
