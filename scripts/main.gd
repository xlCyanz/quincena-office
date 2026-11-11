# Escena principal del juego. En el hito 0 solo confirma que el proyecto arranca;
# a partir del hito 1 contendrá la oficina, la cámara y la interfaz.
extends Node2D


func _ready() -> void:
	var game_name: String = ProjectSettings.get_setting("application/config/name")
	var godot_version: String = Engine.get_version_info().string
	print("%s — Godot %s" % [game_name, godot_version])
