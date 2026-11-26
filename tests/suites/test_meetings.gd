# Contratos grandes y Sala de reuniones: la primera oferta grande habilita la sala; sin ella
# no se aceptan; los de élite solo llegan en Corporación.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=meetings
extends Node

## Lo escucha test_all: fallos y comprobaciones.
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SEED: int = 20261147
## Zona abierta del local inicial (39 m², fuera de la Oficina Ejecutiva).
const OPEN_CELL := Vector2i(3, 3)
const TABLE_CELL := Vector2i(3, 4)
## Pared norte de la zona abierta; con rotación 2 queda detrás.
const SCREEN_CELL := Vector2i(4, 0)

var _failures: int = 0
var _checks: int = 0
var _notices: Array[String] = []
var _builder := Builder.new()


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	EventBus.notice.connect(func(text: String) -> void: _notices.append(text))
	_check_catalog()
	_check_allowed_sizes()
	_check_unlock()
	_check_accept()
	_check_elite()
	_check_screen()
	_check_save()
	await _check_ui()
	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _new_game() -> void:
	GameClock.stop()
	SaveManager.new_game()
	Staff.set_seed(SEED)
	Projects.set_seed(SEED)
	for objective: Dictionary in Company.get_objectives():
		Company.objectives_done.append(String(objective["id"]))
	Economy.earn(100000, "Prueba")
	Projects.offers.clear()


# Hasta la próxima llegada de ofertas (9:00 del día siguiente).
func _to_next_arrival() -> void:
	GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)


func _meeting_room() -> void:
	_expect(_builder.mark_room("meeting_room", OPEN_CELL)["ok"], "marcar la Sala de reuniones")
	_expect(_builder.place("meeting_table", TABLE_CELL, 0)["ok"], "mesa de reuniones")


func _sizes_seen(days: int) -> Dictionary[String, int]:
	var seen: Dictionary[String, int] = {}
	var ids: Dictionary[int, bool] = {}
	for day: int in range(days):
		_to_next_arrival()
		for offer: Dictionary in Projects.offers:
			if not ids.has(offer["id"]):
				ids[offer["id"]] = true
				seen[offer["size"]] = seen.get(offer["size"], 0) + 1
		for offer: Dictionary in Projects.offers.duplicate():
			Projects.reject(offer["id"])
	return seen


func _check_catalog() -> void:
	var large: Dictionary = ContractCatalog.get_size("large")
	var elite: Dictionary = ContractCatalog.get_size("elite")
	_expect(int(large["min_stage"]) == 4 and float(large["min_reputation"]) == 4.0 and large["requires_room"] == "meeting_room",
		"grande: desde Mediana empresa, 4 ★ y Sala de reuniones")
	_expect(int(elite["min_stage"]) == 5 and float(elite["min_reputation"]) == 5.0 and elite["requires_room"] == "meeting_room"
		and ContractCatalog.is_elite("elite") and not ContractCatalog.is_elite("large"), "élite: Corporación, 5 ★ y Sala de reuniones")
	_expect(ContractCatalog.get_size_range("elite", "points") == ContractCatalog.get_size_range("large", "points")
		and ContractCatalog.get_size_range("elite", "pay") == Vector2i(57000, 114000), "élite: los puntos del grande y el pago ×1.5")
	_expect(ContractCatalog.get_size_name("elite") == "De élite" and ContractCatalog.get_elite_clients().size() >= 5, "nombre y clientes de élite")
	for client: String in ContractCatalog.get_elite_clients():
		_expect(not ContractCatalog.get_clients().has(client), "%s solo es de élite" % client)
	_expect(FurnitureCatalog.get_price("meeting_table") == 1200 and FurnitureCatalog.get_footprint("meeting_table", Vector2i.ZERO, 0).size() == 4,
		"mesa de reuniones 2×2 a $1,200")
	_expect(FurnitureCatalog.is_wall_mounted("presentation_screen") and FurnitureCatalog.get_price("presentation_screen") == 800
		and FurnitureCatalog.is_presentation_screen("presentation_screen"), "pantalla de presentaciones de pared a $800")
	_expect(RoomCatalog.is_unlocked_by_offer("meeting_room") and not RoomCatalog.is_unlocked_by_offer("work_area"),
		"la Sala de reuniones se habilita con una oferta")


func _check_allowed_sizes() -> void:
	_new_game()
	Projects.reputation = 5.0
	Company.stage = 2
	_expect(not Projects.get_allowed_sizes().has("large"), "en Pequeña empresa no llegan grandes, ni con 5 ★")
	Company.stage = 3
	Projects.reputation = 3.9
	_expect(not Projects.get_allowed_sizes().has("large"), "en Mediana empresa con menos de 4 ★ tampoco")
	Projects.reputation = 4.0
	_expect(Projects.get_allowed_sizes().has("large") and not Projects.get_allowed_sizes().has("elite"), "con 4 ★ llegan grandes, no de élite")
	Projects.reputation = 5.0
	_expect(not Projects.get_allowed_sizes().has("elite"), "los de élite no llegan antes de Corporación")
	Company.stage = 4
	Projects.reputation = 4.9
	_expect(Projects.get_allowed_sizes().has("large") and not Projects.get_allowed_sizes().has("elite"), "en Corporación con 4.9 ★ no hay élite")
	Projects.reputation = 5.0
	_expect(Projects.get_allowed_sizes().has("elite"), "en Corporación con 5 ★ sí")


func _check_unlock() -> void:
	_new_game()
	_expect(not Projects.meeting_room_unlocked and not Company.is_room_unlocked("meeting_room"), "al empezar no se puede construir")
	var result: Dictionary = _builder.quote_mark_room("meeting_room", OPEN_CELL)
	_expect(not result["ok"] and String(result["message"]).contains("primera oferta grande"), "el modo construcción lo dice: %s" % result["message"])
	Company.stage = 4
	_expect(not Company.is_room_unlocked("meeting_room"), "tampoco por la etapa")
	Projects.create_offer("medium")
	_expect(not Projects.meeting_room_unlocked, "una oferta mediana no la habilita")
	var unlocked: Array[bool] = [false]
	var listener: Callable = func() -> void: unlocked[0] = true
	EventBus.rooms_unlocked.connect(listener)
	_notices.clear()
	var offer: Dictionary = Projects.create_offer("large")
	EventBus.rooms_unlocked.disconnect(listener)
	_expect(Projects.meeting_room_unlocked and Company.is_room_unlocked("meeting_room") and unlocked[0], "la primera oferta grande la habilita")
	_expect(_notices.any(func(text: String) -> bool: return text.contains("Sala de reuniones")), "y avisa: %s" % [_notices])
	_notices.clear()
	Projects.create_offer("large")
	_expect(not _notices.any(func(text: String) -> bool: return text.contains("ya puedes construir")), "avisa una sola vez")
	Projects.reject(offer["id"])
	Projects.offers.clear()
	_expect(Company.is_room_unlocked("meeting_room") and _builder.quote_mark_room("meeting_room", OPEN_CELL)["ok"],
		"sigue habilitada sin la oferta")
	_builder.mark_room("meeting_room", OPEN_CELL)
	var room: Dictionary = OfficeState.find_room("meeting_room")
	_expect(RoomRules.function_problems(room, OfficeState.furniture).has("falta mesa de reuniones"), "sin mesa no funciona")
	_builder.place("meeting_table", TABLE_CELL, 0)
	_expect(RoomRules.function_problems(OfficeState.find_room("meeting_room"), OfficeState.furniture).is_empty(), "con mesa funciona")


func _check_accept() -> void:
	_new_game()
	Company.stage = 3
	Projects.reputation = 4.0
	var offer: Dictionary = Projects.create_offer("large")
	var problem: String = Projects.accept_problem(offer["id"])
	_expect(problem.contains("Sala de reuniones"), "sin sala no se acepta: %s" % problem)
	_expect(not Projects.accept(offer["id"])["ok"] and Projects.contracts.is_empty(), "no pasa a contratos")
	_builder.mark_room("meeting_room", OPEN_CELL)
	_expect(Projects.accept_problem(offer["id"]).contains("Sala de reuniones"), "una sala sin mesa no alcanza")
	_builder.place("meeting_table", TABLE_CELL, 0)
	var result: Dictionary = Projects.accept(offer["id"])
	_expect(result["ok"] and Projects.contracts.size() == 1 and Projects.contracts[0]["size"] == "large", "con la sala se acepta: %s" % result["message"])
	var days: Vector2i = ContractCatalog.get_days_range("large", int(offer["total_points"]))
	_expect(int(offer["days"]) >= days.x and int(offer["days"]) <= days.y and int(offer["total_points"]) >= 4000, "plazo y puntos del grande")


func _check_elite() -> void:
	_new_game()
	Projects.reputation = 5.0
	Company.stage = 3
	var seen: Dictionary[String, int] = _sizes_seen(150)
	_expect(seen.get("large", 0) > 0 and seen.get("elite", 0) == 0, "en Mediana empresa llegan grandes y ninguno de élite: %s" % [seen])
	_new_game()
	Projects.reputation = 5.0
	Company.stage = 4
	var elite: Array[Dictionary] = []
	var ids: Dictionary[int, bool] = {}
	for day: int in range(200):
		_to_next_arrival()
		for offer: Dictionary in Projects.offers:
			if not ids.has(offer["id"]) and offer["size"] == "elite":
				elite.append(offer)
			ids[offer["id"]] = true
		for offer: Dictionary in Projects.offers.duplicate():
			Projects.reject(offer["id"])
	_expect(elite.size() > 0, "en Corporación con 5 ★ llegan de élite: %d" % elite.size())
	for offer: Dictionary in elite:
		_expect(ContractCatalog.get_elite_clients().has(offer["client"]), "cliente de élite: %s" % offer["client"])
		_expect(int(offer["pay"]) >= 57000 and int(offer["pay"]) <= 114000, "pago de élite: %d" % offer["pay"])
	if not elite.is_empty():
		var offer: Dictionary = Projects.create_offer("elite")
		_expect(Projects.accept_problem(offer["id"]).contains("Sala de reuniones"), "el de élite también exige la sala")


func _check_screen() -> void:
	_new_game()
	_expect(is_equal_approx(Projects.get_size_weight("large"), 1.0), "peso del grande: 1")
	Projects.meeting_room_unlocked = true
	_meeting_room()
	var result: Dictionary = _builder.place("presentation_screen", SCREEN_CELL, 2)
	_expect(result["ok"], "pantalla en la pared de la sala: %s" % result["message"])
	_expect(Projects.has_presentation_screen("meeting_room"), "la sala tiene pantalla")
	_expect(is_equal_approx(Projects.get_size_weight("large"), 1.25) and is_equal_approx(Projects.get_size_weight("elite"), 1.25)
		and is_equal_approx(Projects.get_size_weight("small"), 6.0), "con pantalla llegan más grandes y de élite: %.2f" % Projects.get_size_weight("large"))
	var table: int = OfficeState.find_furniture_at(TABLE_CELL)
	OfficeState.furniture.remove_at(table)
	_expect(is_equal_approx(Projects.get_size_weight("large"), 1.0), "en una sala que no funciona no cuenta")
	# 20,000 sorteos con pantalla.
	OfficeState.furniture.append({"id": "meeting_table", "cell": TABLE_CELL, "rotation": 0, "assigned_to": "", "computer": ""})
	Projects.reputation = 4.0
	Company.stage = 3
	var with_screen: int = _count_large()
	_builder.sell_wall_item(SCREEN_CELL, 2)
	var without: int = _count_large()
	# Pesos 6, 3 y 1: sin pantalla 1/10 = 2,000; con pantalla 1.25/10.25 ≈ 2,439.
	_expect(without > 1800 and without < 2200 and with_screen > 2260 and with_screen < 2620,
		"con pantalla salen más grandes: %d contra %d de 20,000" % [with_screen, without])


func _count_large() -> int:
	Projects.set_seed(SEED)
	var count: int = 0
	for index: int in range(20000):
		if Projects.call("_pick_size") == "large":
			count += 1
	return count


func _check_save() -> void:
	_new_game()
	Projects.create_offer("large")
	SaveManager.save_game("slot_5")
	SaveManager.new_game()
	_expect(not Projects.meeting_room_unlocked, "partida nueva: bloqueada")
	_expect(SaveManager.load_game("slot_5") and Projects.meeting_room_unlocked, "se guarda habilitada")
	# Partida vieja: sin la clave.
	var state: Dictionary = Projects.export_state()
	state.erase("meeting_room_unlocked")
	state["offers"] = []
	Projects.import_state(state)
	_expect(not Projects.meeting_room_unlocked, "sin sala ni ofertas grandes queda bloqueada")
	var office: Dictionary = OfficeState.export_state()
	office["rooms"].append({"type": "meeting_room", "cells": [[3, 3], [4, 3], [5, 3]], "dirt": 0.0})
	OfficeState.import_state(office)
	Projects.import_state(state)
	_expect(Projects.meeting_room_unlocked, "con una Sala de reuniones ya marcada queda habilitada")


func _check_ui() -> void:
	_new_game()
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var meeting_button: Button = null
	for button: Node in game.find_children("*", "Button", true, false):
		if (button as Button).text == "Sala de reuniones":
			meeting_button = button
	_expect(meeting_button != null and meeting_button.disabled and meeting_button.tooltip_text.contains("primera oferta grande"),
		"el botón de la Sala de reuniones está deshabilitado")
	Projects.create_offer("large")
	_expect(meeting_button != null and not meeting_button.disabled, "al llegar la oferta grande se habilita")
	var shop: ShopScreen = (game.get_node("BuildPanel") as BuildPanel).get_shop()
	_expect(shop.get_card("meeting_table") != null and shop.get_card("presentation_screen") != null,
		"la Tienda vende la mesa y la pantalla")
	game.queue_free()
	await get_tree().process_frame
