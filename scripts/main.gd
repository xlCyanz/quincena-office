# Escena principal del juego: reúne la oficina y la cámara.
# Sigue la regla de Godot "llamar hacia abajo, avisar hacia arriba": el nodo padre
# configura a sus hijos directamente, y los hijos avisarán con señales cuando haga falta.
extends Node2D

@onready var _office_grid: OfficeGrid = $OfficeGrid
@onready var _camera: OfficeCamera = $OfficeCamera


func _ready() -> void:
	var game_name: String = ProjectSettings.get_setting("application/config/name")
	var godot_version: String = Engine.get_version_info().string
	print("%s — Godot %s" % [game_name, godot_version])
	_camera.set_bounds(_office_grid.get_lot_world_rect())
