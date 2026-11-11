# Menú principal: lo primero que se ve al abrir el juego.
extends Control

const GAME_SCENE_PATH: String = "res://scenes/main.tscn"

@onready var _new_game_button: Button = %NewGameButton


func _ready() -> void:
	_new_game_button.pressed.connect(_on_new_game_pressed)
	_new_game_button.grab_focus()


func _on_new_game_pressed() -> void:
	SaveManager.new_game()
	get_tree().change_scene_to_file(GAME_SCENE_PATH)
