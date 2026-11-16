# Recepción y visitas: con recepcionista presente la visita deja su oferta; sin él el cliente se va
# y se pierde; con sofá espera más.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=reception
extends Node

## Lo escucha test_all: fallos y comprobaciones.
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const SEED: int = 20261114
const RECEPTIONIST: String = "receptionist"
const COUNTER_CELL := Vector2i(4, 5)
const CHAIR_CELL := Vector2i(4, 6)
## Sofá contra la pared este, de (5, 6) a (5, 7).
const SOFA_CELL := Vector2i(5, 6)
const SOFA_ROTATION: int = 3

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE_PATH)
		return
	# Carpeta aparte para no tocar las partidas del jugador.
	SaveManager.save_dir = "user://test_saves"
	_check_catalog()
	_check_station()
	_check_enabled()
	_check_arrivals()
	_check_attended()
	_check_left()
	_check_sofa()
	_check_agenda()
	_check_save()
	await _check_ui()

	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


# Startup, dinero de sobra y objetivos cumplidos; con reception, Recepción en la entrada con mostrador y silla.
func _new_game(reception: bool = true, stage: int = 1) -> void:
	SaveManager.new_game()
	Staff.set_seed(SEED)
	Projects.set_seed(SEED)
	for objective: Dictionary in Company.get_objectives():
		Company.objectives_done.append(String(objective["id"]))
	Company.stage = stage
	Economy.earn(100000, "Prueba")
	Projects.offers.clear()
	if reception:
		_build_reception()


func _build_reception() -> void:
	var builder := Builder.new()
	var x: int = GridEdge.AXIS_X
	var y: int = GridEdge.AXIS_Y
	var walls: Array[Dictionary] = [
		{"edge": Vector3i(3, 4, y), "kind": ConstructionCatalog.DOOR},
		{"edge": Vector3i(4, 4, y), "kind": ConstructionCatalog.WALL},
		{"edge": Vector3i(5, 4, y), "kind": ConstructionCatalog.WALL},
		{"edge": Vector3i(2, 5, x), "kind": ConstructionCatalog.WALL},
		{"edge": Vector3i(2, 6, x), "kind": ConstructionCatalog.WALL},
		{"edge": Vector3i(2, 7, x), "kind": ConstructionCatalog.WALL},
	]
	var result: Dictionary = builder.apply(walls)
	_expect(result["ok"], "paredes de la Recepción: %s" % result.get("message", ""))
	result = builder.mark_room(Workstations.RECEPTION, Vector2i(3, 6))
	_expect(result["ok"], "marcar la Recepción: %s" % result.get("message", ""))
	result = builder.place("reception_counter", COUNTER_CELL, 2)
	_expect(result["ok"], "mostrador: %s" % result.get("message", ""))
	result = builder.place("basic_chair", CHAIR_CELL, 0)
	_expect(result["ok"], "silla del mostrador: %s" % result.get("message", ""))


func _place_sofa() -> void:
	var result: Dictionary = Builder.new().place("waiting_sofa", SOFA_CELL, SOFA_ROTATION)
	_expect(result["ok"], "sofá de espera: %s" % result.get("message", ""))


func _hire(role: String, level: String) -> Dictionary:
	var opened: Dictionary = Staff.open_vacancy(role, level, StaffCatalog.get_salary(role, level), true)
	_expect(opened["ok"], "publicar %s: %s" % [role, opened["message"]])
	var arrival: int = int(StaffCatalog.get_hiring("arrival_hour"))
	var hours: int = posmod(arrival - GameClock.get_hour(), GameConstants.HOURS_PER_DAY)
	GameClock.fast_forward_hours(hours if hours > 0 else GameConstants.HOURS_PER_DAY)
	var candidate: Dictionary = Staff.get_vacancy(opened["id"])["candidates"][0]
	var result: Dictionary = Staff.make_offer(candidate["id"], candidate["asked_salary"])
	var employee: Dictionary = Staff.get_employee(candidate["id"])
	_expect(not employee.is_empty(), "contratado: %s %s (%s)" % [role, level, result["message"]])
	return employee


# Hasta las 9:00 de un día hábil.
func _to_weekday_morning() -> void:
	var hours: int = posmod(9 - GameClock.get_hour(), GameConstants.HOURS_PER_DAY)
	GameClock.fast_forward_hours(hours if hours > 0 else GameConstants.HOURS_PER_DAY)
	while GameClock.get_weekday() > 4:
		GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)
	# Sin las visitas y ofertas que llegaron solas.
	Projects.visits.clear()
	Projects.offers.clear()


func _visit() -> Dictionary:
	var offer: Dictionary = Projects._make_offer(GameClock.get_day_count(), "small")
	Projects._add_visit(offer)
	return offer


func _has_offer(offer: Dictionary) -> bool:
	for item: Dictionary in Projects.offers:
		if item["id"] == offer["id"]:
			return true
	return false


func _check_catalog() -> void:
	_expect(StaffCatalog.get_role_ids().has(RECEPTIONIST) and StaffCatalog.get_role_name(RECEPTIONIST) == "Recepcionista", "cargo Recepcionista")
	_expect(StaffCatalog.get_salary(RECEPTIONIST, "intern") == 700 and not StaffCatalog.has_levels(RECEPTIONIST), "$700 sin niveles")
	_expect(StaffCatalog.get_role_min_stage(RECEPTIONIST) == 1, "desde Startup")
	_expect(StaffCatalog.get_workplace(RECEPTIONIST) == Workstations.RECEPTION, "trabaja en la Recepción")
	_expect(StaffCatalog.get_role_department(RECEPTIONIST) == "sales", "es de Ventas")
	_expect(FurnitureCatalog.get_price("reception_counter") == 600 and FurnitureCatalog.get_item("reception_counter")["size"] == Vector2i(2, 1),
		"mostrador de $600 y 2 casillas")
	_expect(bool(FurnitureCatalog.get_item("waiting_sofa")["waiting_seat"]) and FurnitureCatalog.get_item("waiting_sofa")["size"] == Vector2i(2, 1),
		"sofá de espera de 2 casillas")


func _check_station() -> void:
	_new_game(false)
	_expect(Staff.get_station_problem(RECEPTIONIST) == Staff.NO_RECEPTION_MESSAGE, "sin Recepción no hay puesto")
	_build_reception()
	var stations: Array[Dictionary] = Workstations.find_all(OfficeState.furniture, OfficeState.rooms, Workstations.RECEPTION)
	_expect(stations.size() == 1 and stations[0]["cell"] == CHAIR_CELL, "la silla delante del mostrador es un puesto: %s" % [stations])
	_expect(Workstations.find_free(OfficeState.furniture, OfficeState.rooms).is_empty(), "no es un puesto del Área de trabajo")
	_expect(Builder.new().place("basic_chair", Vector2i(5, 6), 0)["ok"], "otra silla delante")
	_expect(Workstations.find_all(OfficeState.furniture, OfficeState.rooms, Workstations.RECEPTION).size() == 1, "un recepcionista por mostrador")
	var receptionist: Dictionary = _hire(RECEPTIONIST, "senior")
	_expect(receptionist["salary"] >= 600 and Staff.has_working_station(receptionist), "contratado en su mostrador")
	_expect(OfficeState.find_furniture_assigned_to(Staff.employee_key(receptionist["id"]))["cell"] == CHAIR_CELL, "se sienta en la silla del mostrador")
	_expect(Staff.get_station_problem(RECEPTIONIST) == Staff.NO_RECEPTION_MESSAGE, "el mostrador queda ocupado")


func _check_enabled() -> void:
	_new_game(true, 0)
	_expect(not Projects.visits_enabled(), "en Emprendimiento no vienen clientes")
	_new_game(false)
	_expect(not Projects.visits_enabled(), "sin Recepción no vienen clientes")
	_new_game()
	_expect(Projects.visits_enabled(), "en Startup con Recepción sí")
	_expect(Projects.get_visit_wait_hours() == 3, "esperan 3 horas")
	_expect(Projects.get_waiting_spots().size() == 5 and not Projects.get_waiting_spots().has(OfficeState.entrance),
		"esperan en las casillas libres, sin tapar la entrada: %s" % [Projects.get_waiting_spots()])
	_place_sofa()
	_expect(Projects.get_visit_wait_hours() == 6, "con sofá esperan 6")
	var sofa: Array[Vector2i] = FurnitureCatalog.get_footprint("waiting_sofa", SOFA_CELL, SOFA_ROTATION)
	_expect(Projects.get_waiting_spots().slice(0, 2) == sofa and Projects.get_waiting_spots().size() == 5,
		"primero en el sofá: %s" % [Projects.get_waiting_spots()])
	var counter: int = OfficeState.find_furniture_at(COUNTER_CELL)
	OfficeState.furniture.remove_at(counter)
	_expect(not Projects.visits_enabled(), "sin mostrador no vienen")


func _check_arrivals() -> void:
	_new_game()
	var visits: int = 0
	var total: int = 0
	for day: int in range(400):
		Projects.offers.clear()
		Projects.visits.clear()
		Projects._process_arrivals(GameClock.get_day_count())
		visits += Projects.visits.size()
		total += Projects.visits.size() + Projects.offers.size()
	var ratio: float = float(visits) / maxf(1.0, total)
	_expect(total > 100 and ratio > 0.3 and ratio < 0.5, "cerca del 40 %% llega como visita: %d de %d" % [visits, total])
	_new_game(false)
	Projects.visits.clear()
	for day: int in range(50):
		Projects._process_arrivals(GameClock.get_day_count())
	_expect(Projects.visits.is_empty() and not Projects.offers.is_empty(), "sin Recepción todas van a la bandeja")
	_new_game()
	for i: int in range(6):
		_visit()
	Projects._process_arrivals(GameClock.get_day_count())
	_expect(Projects.offers.is_empty() and Projects.visits.size() == 6, "con 6 esperando no llega ninguna más")


func _check_attended() -> void:
	_new_game()
	var receptionist: Dictionary = _hire(RECEPTIONIST, "senior")
	_to_weekday_morning()
	var offer: Dictionary = _visit()
	_expect(Projects.visits.size() == 1 and not _has_offer(offer), "el cliente espera en la Recepción")
	GameClock.fast_forward_hours(1)
	_expect(Projects.visits.is_empty() and _has_offer(offer), "con la recepcionista presente deja su oferta")
	# Si llega más tarde, pero antes de que se vaya el cliente, lo atiende.
	Staff.set_own_schedule(receptionist["id"], 11, [0, 1, 2, 3, 4])
	_to_weekday_morning()
	offer = _visit()
	GameClock.fast_forward_hours(2)
	_expect(Projects.visits.size() == 1, "a las 11 todavía espera")
	GameClock.fast_forward_hours(1)
	_expect(Projects.visits.is_empty() and _has_offer(offer), "a las 12 lo atendió quien llegó a las 11")


func _check_left() -> void:
	_new_game()
	_to_weekday_morning()
	var offer: Dictionary = _visit()
	GameClock.fast_forward_hours(2)
	_expect(Projects.visits.size() == 1, "sin recepcionista espera")
	GameClock.fast_forward_hours(1)
	_expect(Projects.visits.is_empty() and not _has_offer(offer), "a las 3 horas se va y la oferta se pierde")
	_hire(RECEPTIONIST, "senior")
	_to_weekday_morning()
	while GameClock.get_weekday() != 5:
		GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)
	Projects.visits.clear()
	offer = _visit()
	GameClock.fast_forward_hours(3)
	_expect(Projects.visits.is_empty() and not _has_offer(offer), "el sábado no hay nadie y se va")


func _check_sofa() -> void:
	_new_game()
	_place_sofa()
	_to_weekday_morning()
	var offer: Dictionary = _visit()
	_expect(int(Projects.visits[0]["leaves_at"]) - int(Projects.visits[0]["arrived_at"]) == 6, "con sofá se queda 6 horas")
	GameClock.fast_forward_hours(5)
	_expect(Projects.visits.size() == 1, "a las 5 horas sigue esperando")
	GameClock.fast_forward_hours(1)
	_expect(Projects.visits.is_empty() and not _has_offer(offer), "a las 6 horas se va")


func _check_agenda() -> void:
	_new_game()
	var row: Dictionary = {}
	for item: Dictionary in Staff.get_agenda(0):
		if item["kind"] == "reception":
			row = item
	_expect(not row.is_empty() and row["label"] == "Recepción", "la agenda tiene la fila Recepción")
	var cells: Array = row.get("cells", [])
	_expect(cells.size() == 24 and cells[8] == Staff.AGENDA_OFF and cells[9] == Staff.AGENDA_GAP and cells[11] == Staff.AGENDA_GAP
		and cells[12] == Staff.AGENDA_OFF, "sin recepcionista, de 9 a 12 es un hueco")
	_expect(Staff.get_agenda_gaps(0).has("nadie en la Recepción de 9:00 a 12:00"), "huecos: %s" % [Staff.get_agenda_gaps(0)])
	_hire(RECEPTIONIST, "senior")
	_expect(Staff.get_agenda_gaps(0).is_empty(), "con recepcionista no hay huecos el lunes")
	_expect(Staff.get_agenda_gaps(5).has("nadie en la Recepción de 9:00 a 12:00"), "el sábado sí")
	_new_game(false)
	for item: Dictionary in Staff.get_agenda(0):
		_expect(item["kind"] != "reception", "sin Recepción no hay fila")


func _check_save() -> void:
	_new_game()
	_to_weekday_morning()
	var offer: Dictionary = _visit()
	var visit: Dictionary = Projects.visits[0].duplicate(true)
	var state: Dictionary = JSON.parse_string(JSON.stringify(Projects.export_state()))
	Projects.new_game()
	_expect(Projects.visits.is_empty(), "una partida nueva no tiene visitas")
	Projects.import_state(state)
	_expect(Projects.visits.size() == 1 and int(Projects.visits[0]["leaves_at"]) == int(visit["leaves_at"])
		and Projects.visits[0]["offer"]["client"] == offer["client"] and int(Projects.visits[0]["offer"]["pay"]) == int(offer["pay"]),
		"las visitas se guardan con su oferta")
	state.erase("visits")
	Projects.import_state(state)
	_expect(Projects.visits.is_empty(), "una partida de antes del hito 36 no tiene visitas")


func _check_ui() -> void:
	_new_game()
	_place_sofa()
	_to_weekday_morning()
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var offer: Dictionary = _visit()
	EventBus.visits_changed.emit()
	await get_tree().process_frame
	var visitors: Dictionary = game.get("visitors")
	_expect(visitors.has(int(offer["id"])), "el cliente aparece en la oficina")
	var visitor: Visitor = visitors.get(int(offer["id"]))
	# Con la entrada ocupada espera en la calle sin verse (una persona por casilla).
	_expect(visitor != null and visitor.activity == OfficeCharacter.Activity.WALKING_TO_DESK
		and visitor.get_seat_cell() == SOFA_CELL, "y va al sofá")
	_expect(visitor != null and visitor.display_name == "Cliente de %s" % offer["client"], "con su nombre")
	var panel: ProjectsPanel = game.get_node("ProjectsPanel")
	panel.set_open(true)
	await get_tree().process_frame
	_expect(panel.get_list_text().contains("En la Recepción (1)") and panel.get_list_text().contains("Cliente de %s" % offer["client"])
		and panel.get_list_text().contains("nadie lo atiende"), "Proyectos lista quién espera: %s" % panel.get_list_text())
	panel.set_open(false)
	var staff_panel: StaffPanel = game.get_node("StaffPanel")
	staff_panel.set_open(true)
	await get_tree().process_frame
	var roles: OptionButton = staff_panel.get_role_option()
	var found: bool = false
	for index: int in range(roles.item_count):
		found = found or roles.get_item_text(index).begins_with("Recepcionista")
	_expect(found, "Personal ofrece la vacante de recepcionista")
	staff_panel.set_open(false)
	Projects.visits.clear()
	EventBus.visits_changed.emit()
	await get_tree().process_frame
	# Si aún esperaba en la calle, se va sin entrar y se borra.
	_expect(not visitors.has(int(offer["id"])) and (not is_instance_valid(visitor)
		or visitor.activity == OfficeCharacter.Activity.WALKING_OUT), "el cliente se va caminando")
	game.queue_free()
	await get_tree().process_frame
