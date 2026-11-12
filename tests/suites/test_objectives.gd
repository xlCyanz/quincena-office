# Prueba del hito 28: objetivos guiados.
# Criterio: al contratar al primer programador el objetivo se marca, cobra su recompensa
# una sola vez y aparece el siguiente; una partida de la fase 2 carga con sus objetivos
# ya cumplidos marcados.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=objectives
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const CONCEPT: String = "Objetivo cumplido"
const SEED: int = 28

var _failures: int = 0
var _checks: int = 0
var _notices: Array[String] = []
var _completed: Array[String] = []


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE_PATH)
		return
	# Las pruebas guardan en otra carpeta para no tocar las partidas del jugador.
	SaveManager.save_dir = "user://test_saves"
	EventBus.notice.connect(func(text: String) -> void: _notices.append(text))
	EventBus.objective_completed.connect(func(objective_id: String) -> void: _completed.append(objective_id))
	_check_start()
	_check_first_programmer()
	_check_rewards()
	_check_save()
	await _check_ui()

	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _new_game() -> void:
	SaveManager.new_game()
	Staff.set_seed(SEED)
	Projects.set_seed(SEED)
	_notices.clear()
	_completed.clear()


func _sum(concept: String) -> int:
	var total: int = 0
	for movement: Dictionary in Economy.movements:
		if movement["concept"] == concept:
			total += int(movement["amount"])
	return total


func _visible_ids() -> Array[String]:
	var ids: Array[String] = []
	for objective: Dictionary in Company.get_visible_objectives():
		ids.append(String(objective["id"]))
	return ids


# Área de trabajo de 3×3 al este de la Oficina Ejecutiva con tres puestos (escritorio
# con computadora y silla delante). Cumple el objetivo «Arma un Área de trabajo».
func _prepare_office() -> void:
	_build_work_area()
	_build_stations()


func _build_work_area() -> void:
	var builder := Builder.new()
	var y: int = GridEdge.AXIS_Y
	var walls: Array[Dictionary] = [
		{"edge": Vector3i(3, 2, y), "kind": ConstructionCatalog.WALL},
		{"edge": Vector3i(4, 2, y), "kind": ConstructionCatalog.DOOR},
		{"edge": Vector3i(5, 2, y), "kind": ConstructionCatalog.WALL},
	]
	Economy.earn(5000, "Prueba")
	_expect(builder.apply(walls)["ok"] and builder.mark_room(Workstations.WORK_AREA, Vector2i(4, 1))["ok"], "área de trabajo")


func _build_stations() -> void:
	var builder := Builder.new()
	for x: int in [3, 4, 5]:
		_expect(builder.place("simple_desk", Vector2i(x, 0), 2)["ok"] and builder.place("basic_chair", Vector2i(x, 1), 0)["ok"]
			and builder.install_computer("basic_computer", Vector2i(x, 0))["ok"], "puesto en x %d" % x)


# Contrata un programador por el camino normal: vacante, candidato y oferta.
func _hire(role: String) -> Dictionary:
	var vacancy_id: int = Staff.open_vacancy(role, "junior", 1000, true)["id"]
	GameClock.fast_forward_hours(1)
	var candidates: Array = Staff.get_vacancy(vacancy_id)["candidates"]
	if candidates.is_empty():
		GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)
		candidates = Staff.get_vacancy(vacancy_id)["candidates"]
	var candidate: Dictionary = candidates[0]
	return Staff.make_offer(candidate["id"], candidate["asked_salary"])


func _check_start() -> void:
	_new_game()
	_expect(Company.get_objectives().size() == 15, "15 objetivos")
	_expect(_visible_ids() == (["work_area", "first_programmer", "first_contract"] as Array[String]), "se ven los 3 primeros: %s" % [_visible_ids()])
	_expect(Company.objectives_done.is_empty() and _sum(CONCEPT) == 0, "una partida nueva no cumple ninguno")
	var five: Dictionary = Company.get_objectives()[6]
	_expect(Company.get_objective_progress(five) == {"met": false, "progress": "0 / 5"}, "progreso: %s" % Company.get_objective_progress(five))


func _check_first_programmer() -> void:
	_new_game()
	_prepare_office()
	_expect(_completed == (["work_area"] as Array[String]) and _sum(CONCEPT) == 300, "el área de trabajo paga $300: %d" % _sum(CONCEPT))
	var hired: Dictionary = _hire("programmer")
	_expect(hired["ok"] and Staff.employees.size() == 1, "contratar: %s" % hired.get("message", ""))
	_expect(Company.is_objective_done("first_programmer") and _completed == (["work_area", "first_programmer"] as Array[String]), "se marca: %s" % [_completed])
	_expect(_sum(CONCEPT) == 800, "cobra $500: %d" % _sum(CONCEPT))
	_expect(_visible_ids() == (["first_contract", "first_delivery", "first_qa"] as Array[String]), "entra el siguiente: %s" % [_visible_ids()])
	var notice: String = ""
	for text: String in _notices:
		if text.begins_with("Objetivo cumplido"):
			notice = text
	_expect(notice == "Objetivo cumplido: Contrata a tu primer programador. Recompensa: $500.", "aviso: %s" % notice)
	# Una sola vez: otros avisos y otro programador no lo vuelven a pagar.
	EventBus.staff_changed.emit()
	_hire("programmer")
	_expect(_sum(CONCEPT) == 800 and Staff.employees.size() == 2, "se cobra una sola vez: %d" % _sum(CONCEPT))


func _check_rewards() -> void:
	_new_game()
	var reputation: float = Projects.reputation
	var balance: int = Economy.balance
	Projects.accepted_count = 1
	Projects.delivered_count = 1
	EventBus.projects_changed.emit()
	# Aceptar y entregar se cumplen juntos: se pagan los dos, cada uno una vez.
	_expect(Company.is_objective_done("first_contract") and Company.is_objective_done("first_delivery"), "aceptado y entregado")
	_expect(Economy.balance == balance + 800 and _sum(CONCEPT) == 800, "$300 + $500: %d" % (Economy.balance - balance))
	_expect(is_equal_approx(Projects.reputation, reputation + 0.1), "+0.1 ★: %.2f" % Projects.reputation)
	var notice: String = _notices[-1] if not _notices.is_empty() else ""
	_expect(_notices.has("Objetivo cumplido: Entrega tu primer contrato. Recompensa: $500 y +0.1 ★."), "aviso con estrellas: %s" % [_notices])
	_expect(_visible_ids() == (["work_area", "first_programmer", "first_qa"] as Array[String]), "siguen en orden: %s" % [_visible_ids()])
	# Terreno: una condición que no cuenta.
	Builder.new().buy_land(Builder.SIDE_EAST, 1, 1, 0)
	_expect(not Company.is_objective_done("buy_land"), "un objetivo que aún no se ve no se cumple")
	_expect(notice != "", "hubo avisos")


func _check_save() -> void:
	_new_game()
	_prepare_office()
	_hire("programmer")
	_expect(SaveManager.save_game("slot_5"), "guardar")
	SaveManager.new_game()
	_expect(Company.objectives_done.is_empty(), "partida nueva sin objetivos cumplidos")
	_expect(SaveManager.load_game("slot_5") and Company.objectives_done == (["work_area", "first_programmer"] as Array[String]), "se guardan: %s" % [Company.objectives_done])
	_expect(_sum(CONCEPT) == 800, "cargar no vuelve a pagar: %d" % _sum(CONCEPT))
	# Partida de la fase 2: sin objetivos guardados. Tiene un programador, un QA y un
	# contrato entregado; al cargar quedan marcados sin recompensa.
	_new_game()
	_prepare_office()
	_hire("programmer")
	_hire("qa")
	Projects.delivered_count = 1
	_expect(SaveManager.save_game("slot_5"), "guardar otra")
	var path: String = "%s/slot_5.json" % SaveManager.save_dir
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	data.erase("company")
	(data["projects"] as Dictionary).erase("accepted_count")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	SaveManager.new_game()
	var movements: int = Economy.movements.size()
	_completed.clear()
	_expect(SaveManager.load_game("slot_5"), "cargar la partida vieja")
	_expect(Company.is_objective_done("work_area") and Company.is_objective_done("first_programmer")
		and Company.is_objective_done("first_qa") and Company.is_objective_done("first_delivery"), "marcados: %s" % [Company.objectives_done])
	_expect(not Company.is_objective_done("first_contract") and not Company.is_objective_done("first_team"), "los que no cumple siguen: %s" % [Company.objectives_done])
	_expect(_completed.is_empty() and _sum(CONCEPT) == 1300, "sin recompensa al cargar (solo las 3 de antes): %d" % _sum(CONCEPT))
	_expect(Economy.movements.size() >= movements, "movimientos cargados")


func _check_ui() -> void:
	_new_game()
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var panel: ObjectivesPanel = game.get_node("ObjectivesPanel")
	var staff: StaffPanel = game.get_node("StaffPanel")
	var bank: BankPanel = game.get_node("BankPanel")
	var text: String = panel.get_text()
	_expect(panel.is_shown() and panel.is_expanded() and text.begins_with("▾ Objetivos")
		and text.contains("• Arma un Área de trabajo") and text.contains("Recompensa: $300")
		and text.contains("• Acepta tu primer contrato"), "lista: %s" % text)
	staff.set_open(true)
	_expect(not panel.is_shown(), "se pliega al abrir Personal")
	bank.get_open_button().pressed.emit()
	_expect(not panel.is_shown() and not staff.is_open(), "sigue plegada al pasar al Banco")
	bank.set_open(false)
	_expect(panel.is_shown() and panel.is_expanded(), "al cerrar vuelve como estaba")
	panel.get_header_button().pressed.emit()
	_expect(not panel.is_expanded() and panel.get_text() == "▸ Objetivos", "el jugador la pliega")
	staff.set_open(true)
	staff.set_open(false)
	_expect(panel.is_shown() and not panel.is_expanded(), "si la plegó él, sigue plegada")
	panel.get_header_button().pressed.emit()
	_build_work_area()
	# La recompensa se paga mientras se avisa el gasto de las paredes: el Hud no puede
	# quedarse con el saldo o el valor de antes de cobrarla.
	var hud: Hud = game.get_node("Hud")
	_expect(hud.get_balance_text() == MoneyFormat.format(Economy.balance), "Hud: saldo al día: %s" % hud.get_balance_text())
	_expect(hud.get_value_text() == "Valor %s" % MoneyFormat.format(Company.get_value()), "Hud: valor al día: %s" % hud.get_value_text())
	_build_stations()
	_hire("programmer")
	await get_tree().process_frame
	_expect(panel.get_text().contains("• Entrega tu primer contrato") and not panel.get_text().contains("primer programador"), "se actualiza: %s" % panel.get_text())
	for objective: Dictionary in Company.get_objectives():
		if not Company.is_objective_done(String(objective["id"])):
			Company.objectives_done.append(String(objective["id"]))
	EventBus.objectives_changed.emit()
	_expect(not panel.is_shown(), "sin objetivos pendientes no se muestra")
	game.queue_free()
	await get_tree().process_frame
