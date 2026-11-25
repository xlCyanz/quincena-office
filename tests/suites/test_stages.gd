# Etapas y menú Empresa: con 5 empleados y 3 entregas pasa a Startup con aviso y llegan medianos
# sin vendedor; despedir después no la baja.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=stages
extends Node

## Lo escucha test_all: fallos y comprobaciones.
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const SEED: int = 27

var _failures: int = 0
var _checks: int = 0
var _notices: Array[String] = []
var _stages_seen: Array[int] = []


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE_PATH)
		return
	# Carpeta aparte para no tocar las partidas del jugador.
	SaveManager.save_dir = "user://test_saves"
	EventBus.notice.connect(func(text: String) -> void: _notices.append(text))
	EventBus.stage_changed.connect(func(stage: int) -> void: _stages_seen.append(stage))
	_check_catalog()
	_check_startup()
	_check_loan_cap()
	_check_rooms()
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
	_stages_seen.clear()


# Empleado falso sin sueldo para contar en los requisitos.
func _add_fake_employee(employee_id: int, role: String) -> void:
	Staff.employees.append({"id": employee_id, "name": "Empleado %d" % employee_id, "role": role, "level": "junior",
		"salary": 0, "schedule": StaffCatalog.get_role_schedule(role), "energy": 100, "mood": 70,
		"stress": 20, "paid_until": GameClock.get_day_count(), "owed": 0})


func _to_next_day() -> void:
	GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY - GameClock.get_hour())


func _to_next_arrival() -> void:
	var arrival: int = int(ContractCatalog.get_offers("arrival_hour"))
	var hours: int = posmod(arrival - GameClock.get_hour(), GameConstants.HOURS_PER_DAY)
	GameClock.fast_forward_hours(hours if hours > 0 else GameConstants.HOURS_PER_DAY)


func _check_catalog() -> void:
	_new_game()
	_expect(Company.get_stage_count() == 5, "cinco etapas")
	var names: Array[String] = []
	for index: int in range(Company.get_stage_count()):
		names.append(Company.get_stage_name(index))
	_expect(names == ["Emprendimiento", "Startup", "Pequeña empresa", "Mediana empresa", "Corporación"], "nombres: %s" % [names])
	_expect(Company.stage == 0 and Company.get_stage_name() == "Emprendimiento", "se empieza en Emprendimiento")
	var startup: Array[Dictionary] = Company.get_requirements(1)
	_expect(startup.size() == 2 and startup[0]["key"] == "employees" and startup[0]["needed"] == 5
		and startup[1]["key"] == "delivered" and startup[1]["needed"] == 3, "Startup pide 5 empleados y 3 entregados: %s" % [startup])
	# Mediana y Corporación piden productos y ejecutivos.
	_expect(not Company.meets(3) and not Company.meets(4), "Mediana y Corporación no se alcanzan aún")


func _check_startup() -> void:
	_new_game()
	_expect(Projects.get_allowed_sizes() == (["small"] as Array[String]), "en Emprendimiento solo pequeños: %s" % [Projects.get_allowed_sizes()])
	# El CEO no cuenta: 4 contratados y 3 entregas no alcanzan.
	for index: int in range(4):
		_add_fake_employee(900 + index, "programmer")
	Projects.delivered_count = 3
	_to_next_day()
	_expect(Company.stage == 0, "con 4 empleados (más el CEO) sigue en Emprendimiento")
	_add_fake_employee(904, "designer")
	_expect(Company.stage == 0, "se revisa cada día, no al momento")
	_to_next_day()
	_expect(Company.stage == 1 and _stages_seen == ([1] as Array[int]), "pasa a Startup al cambiar el día: %d" % Company.stage)
	var notice: String = ""
	for text: String in _notices:
		if text.contains("Startup"):
			notice = text
	_expect(notice.begins_with("¡La empresa pasó a Startup!") and notice.contains("contratos medianos")
		and notice.contains("préstamos de hasta $30,000"), "aviso: %s" % notice)
	_expect(Projects.get_allowed_sizes() == (["small", "medium"] as Array[String]) and Projects.get_salesperson_count() == 0,
		"llegan medianos sin vendedor: %s" % [Projects.get_allowed_sizes()])
	var fired_a: Dictionary = Staff.fire(904)
	var fired_b: Dictionary = Staff.fire(903)
	_expect(fired_a["ok"] and fired_b["ok"], "despedir: %s / %s" % [fired_a["message"], fired_b["message"]])
	_to_next_day()
	_expect(Company.stage == 1 and Staff.employees.size() == 3, "despedir no baja de etapa")
	# Llegan ofertas medianas (en 30 días los falsos renuncian: tampoco baja).
	var medium: int = 0
	for day: int in range(30):
		for offer: Dictionary in Projects.offers.duplicate():
			if offer["size"] == "medium":
				medium += 1
			Projects.reject(offer["id"])
		_to_next_arrival()
	_expect(medium > 0, "llegaron ofertas medianas: %d" % medium)
	_expect(Company.stage == 1, "sin empleados sigue en Startup")
	_expect(_stages_seen == ([1] as Array[int]), "no hubo otro cambio de etapa: %s" % [_stages_seen])


func _check_loan_cap() -> void:
	_new_game()
	Bank.monthly_income = 20000
	_expect(Bank.get_available() > 30000, "el banco prestaría más: %d" % Bank.get_available())
	_expect(Company.get_max_loan() == 10000 and Bank.get_max_request() == 10000, "Emprendimiento: hasta $10,000")
	var problem: String = Bank.loan_problem(10500, 12)
	_expect(problem == "En Emprendimiento el banco presta hasta $10,000 por préstamo.", "tope de la etapa: %s" % problem)
	_expect(Bank.loan_problem(10000, 12).is_empty(), "$10,000 sí")
	Company.stage = 1
	_expect(Bank.get_max_request() == 30000 and not Bank.loan_problem(30500, 12).is_empty() and Bank.loan_problem(30000, 12).is_empty(),
		"Startup: hasta $30,000")
	Company.stage = 2
	_expect(Company.get_max_loan() == 30000, "Pequeña empresa: hasta $30,000")
	Company.stage = 3
	_expect(Company.get_max_loan() == 0 and Bank.get_max_request() == Bank.get_available(), "Mediana: solo el límite del banco")


func _check_rooms() -> void:
	_new_game()
	_expect(not Company.is_room_unlocked("single_office") and not Company.is_room_unlocked("server_room")
		and Company.is_room_unlocked("work_area") and not Company.is_room_unlocked("meeting_room"), "habitaciones de la etapa 3 bloqueadas")
	_expect(Company.get_room_stage("server_room") == 2, "sala de servidores en Pequeña empresa")
	var builder := Builder.new()
	builder.apply([{"edge": Vector3i(3, 3, GridEdge.AXIS_Y), "kind": ConstructionCatalog.WALL}])
	var result: Dictionary = builder.quote_mark_room("single_office", Vector2i(4, 4))
	_expect(not result["ok"] and result["message"] == "La Oficina única se desbloquea en Pequeña empresa.", "no se marca: %s" % result["message"])
	# Pequeña empresa: 15 empleados y 2 equipos completos.
	Projects.delivered_count = 3
	for index: int in range(15):
		_add_fake_employee(1000 + index, ["designer", "programmer", "qa"][index % 3])
	_expect(Company.get_complete_team_count() == 0, "sin equipos no hay equipos completos")
	Staff.teams.append({"id": 1, "name": "A", "members": [1000, 1001, 1002], "schedule": {}})
	Staff.teams.append({"id": 2, "name": "B", "members": [1003, 1004], "schedule": {}})
	_expect(Company.get_complete_team_count() == 1, "un equipo sin QA no está completo")
	(Staff.teams[1]["members"] as Array).append(1005)
	_expect(Company.get_complete_team_count() == 2, "dos equipos completos")
	_to_next_day()
	_expect(Company.stage == 2 and _stages_seen == ([2] as Array[int]), "salta directo a Pequeña empresa si cumple las dos: %s" % [_stages_seen])
	_expect(Company.is_room_unlocked("single_office"), "oficina única desbloqueada")
	Staff.teams.clear()
	Staff.employees.clear()


func _check_save() -> void:
	_new_game()
	Company.stage = 1
	_expect(SaveManager.save_game("slot_5"), "guardar")
	SaveManager.new_game()
	_expect(Company.stage == 0, "partida nueva en Emprendimiento")
	_expect(SaveManager.load_game("slot_5") and Company.stage == 1, "la etapa se guarda: %d" % Company.stage)
	# Partida vieja: calcula su etapa al cargar, sin aviso.
	_notices.clear()
	Company.stage = 0
	for index: int in range(5):
		_add_fake_employee(1100 + index, "qa")
	Projects.delivered_count = 4
	Company.import_state({})
	_expect(Company.stage == 1 and _notices.is_empty(), "partida vieja: etapa calculada en silencio")
	Staff.employees.clear()


func _check_ui() -> void:
	_new_game()
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var build: BuildPanel = game.get_node("BuildPanel")
	var panel: CompanyPanel = game.get_node("CompanyPanel")
	var bank: BankPanel = game.get_node("BankPanel")
	var bar: HFlowContainer = build.get_menu_bar()
	var names: Array[String] = []
	for child: Node in bar.get_children():
		names.append((child as Button).text)
	_expect(names.size() == 10 and names[2] == "Paredes" and names[6] == "Banco" and names[7] == "Empresa", "barra de menús: %s" % [names])
	await get_tree().process_frame
	_expect(bar.get_global_rect().size.x <= 1280.0, "la barra cabe en 1280 px: %.0f" % bar.get_global_rect().size.x)
	_expect(build.get_tool_button("single_office").disabled and not build.get_tool_button("work_area").disabled,
		"Construir: oficina única deshabilitada")
	bank.set_open(true)
	panel.get_open_button().pressed.emit()
	_expect(panel.is_open() and not bank.is_open(), "abrir Empresa cierra el Banco")
	Economy.earn(1000, "Contrato entregado")
	Economy.spend(300, "Prueba")
	Bank.request_loan(2000, 6)
	await get_tree().process_frame
	var text: String = panel.get_text()
	_expect(text.begins_with("Etapa 1 de 5: Emprendimiento") and text.contains("Tienes: Contratos pequeños, Préstamos de hasta $10,000."), "etapa: %s" % text)
	_expect(text.contains("Siguiente etapa: Startup") and text.contains("· Empleados | 0 / 5")
		and text.contains("· Contratos entregados | 0 / 3"), "requisitos: %s" % text)
	_expect(text.contains("Valor | %s" % MoneyFormat.format(Company.get_value())), "valor en Empresa")
	_expect(text.contains("Ingresos | +$1,000") and text.contains("Gastos | −$300") and text.contains("Resultado | +$700")
		and text.contains("Préstamos recibidos | +$2,000"), "mes (el préstamo va aparte): %s" % text)
	Projects.delivered_count = 3
	EventBus.projects_changed.emit()
	await get_tree().process_frame
	_expect(panel.get_text().contains("✓ Contratos entregados | 3 / 3"), "requisito cumplido con ✓")
	Company.stage = 1
	EventBus.stage_changed.emit(1)
	await get_tree().process_frame
	await get_tree().process_frame
	# En Startup el requisito más largo (equipos completos) se parte en líneas.
	var rect: Rect2 = (panel.get("_panel") as Control).get_global_rect()
	_expect(panel.get_text().contains("Equipos completos") and rect.size.x <= CompanyPanel.PANEL_WIDTH + 1.0, "el panel no se ensancha: %.0f" % rect.size.x)
	Company.stage = 2
	EventBus.stage_changed.emit(2)
	await get_tree().process_frame
	_expect(not build.get_tool_button("single_office").disabled, "al llegar a Pequeña empresa se habilita")
	text = panel.get_text()
	_expect(text.begins_with("Etapa 3 de 5: Pequeña empresa") and text.contains("Oficinas únicas"), "panel al día")
	_expect(text.contains("Préstamos de hasta $30,000") and not text.contains("$10,000"), "un solo tope de préstamo: %s" % text)
	_expect(text.contains("Préstamos sin tope de etapa"), "la siguiente etapa cuenta el tope nuevo")
	game.queue_free()
	await get_tree().process_frame
