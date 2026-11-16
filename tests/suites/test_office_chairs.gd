# Silla de visita: la Oficina Ejecutiva y la Oficina única solo funcionan con dos sillas,
# la de quien trabaja ahí y una de visita.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=office_chairs
extends Node

## Lo escucha test_all: fallos y comprobaciones.
signal finished(failures: int, checks: int)

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	SaveManager.start_with_demo = false
	SaveManager.new_game()
	_check()
	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _furniture(chairs: int) -> Array[Dictionary]:
	var items: Array[Dictionary] = [
		{"id": "simple_desk", "cell": Vector2i(20, 20), "rotation": 2, "assigned_to": "", "computer": "basic_computer"},
		{"id": "basic_chair", "cell": Vector2i(20, 21), "rotation": 0, "assigned_to": ""}]
	if chairs >= 2:
		items.append({"id": "basic_chair", "cell": Vector2i(21, 21), "rotation": 3, "assigned_to": ""})
	return items


func _check() -> void:
	var room: Dictionary = {"type": "single_office", "cells": [] as Array[Vector2i]}
	for x: int in range(20, 22):
		for y: int in range(20, 22):
			(room["cells"] as Array[Vector2i]).append(Vector2i(x, y))
	var one: Array[String] = RoomRules.function_problems(room, _furniture(1))
	_expect(one.size() == 1 and one[0] == "faltan sillas (la suya y una de visita) (1 de 2)",
		"una Oficina única con una silla no funciona: %s" % [one])
	_expect(RoomRules.function_problems(room, _furniture(2)).is_empty(), "con la silla de visita sí")
	var rooms: Array[Dictionary] = [room]
	_expect(Workstations.find_all(_furniture(1), rooms, Workstations.SINGLE_OFFICE).is_empty(), "sin silla de visita no hay puesto")
	_expect(Workstations.find_all(_furniture(2), rooms, Workstations.SINGLE_OFFICE).size() == 1,
		"con dos sillas, un solo puesto (la otra es de visita)")
	RoomRules.counts_enabled = false
	_expect(RoomRules.function_problems(room, _furniture(1)).is_empty(), "sin la regla, una silla alcanza")
	RoomRules.counts_enabled = true

	var office: Dictionary = OfficeState.find_room("executive_office")
	_expect(RoomRules.function_problems(office, OfficeState.furniture).is_empty(), "la Oficina Ejecutiva inicial funciona")
	var guest: Dictionary = {}
	for item: Dictionary in OfficeState.furniture:
		if item["id"] == "basic_chair" and String(item["assigned_to"]).is_empty() and Array(office["cells"]).has(item["cell"]):
			guest = item
	_expect(not guest.is_empty(), "con una silla de visita libre")
	var builder := Builder.new()
	var cell: Vector2i = guest.get("cell", Vector2i.ZERO)
	_expect(builder.sell_furniture_at(cell)["ok"], "la silla de visita se vende")
	var problems: Array[String] = RoomRules.function_problems(OfficeState.find_room("executive_office"), OfficeState.furniture)
	_expect(problems.has("faltan sillas (la suya y una de visita) (1 de 2)"), "sin ella no funciona: %s" % [problems])
	_expect(Staff.get_guest_chair("ceo").is_empty(), "y el CEO no tiene dónde sentar a un candidato")
	_expect(builder.place("basic_chair", cell, 3)["ok"], "se vuelve a poner")
	_expect(RoomRules.function_problems(OfficeState.find_room("executive_office"), OfficeState.furniture).is_empty()
		and Staff.get_guest_chair("ceo").get("cell", Vector2i.ZERO) == cell, "y funciona con su silla de visita")
	SaveManager.start_with_demo = true
	SaveManager.new_game()
	var working: bool = true
	var offices: int = 0
	for item: Dictionary in OfficeState.rooms:
		if item["type"] == "single_office" or item["type"] == "executive_office":
			offices += 1
			var office_problems: Array[String] = RoomRules.function_problems(item, OfficeState.furniture)
			if not office_problems.is_empty():
				print(item["type"], " ", Array(item["cells"]).slice(0, 2), " ", office_problems)
			working = working and office_problems.is_empty()
	_expect(offices == 5 and working, "las 5 oficinas de la empresa de prueba funcionan")
	SaveManager.start_with_demo = false
	SaveManager.new_game()
