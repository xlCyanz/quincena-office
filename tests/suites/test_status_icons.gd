# Prueba del hito 57: iconos de estado y avisos con destino.
# Criterio: un empleado cansado muestra su icono y deja de mostrarlo al recuperarse; un clic
# en el aviso de renuncia abre su ficha.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=status_icons
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SEED: int = 20261157

var _failures: int = 0
var _checks: int = 0
var _builder := Builder.new()


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	_check_data()
	_check_icons()
	_check_priority()
	await _check_character()
	await _check_notices()
	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


# Partida nueva con un Área de trabajo de tres puestos al norte (como en test_breaks).
func _new_game() -> void:
	GameClock.stop()
	SaveManager.new_game()
	Staff.set_seed(SEED)
	Projects.set_seed(SEED)
	for objective: Dictionary in Company.get_objectives():
		Company.objectives_done.append(String(objective["id"]))
	Economy.earn(100000, "Prueba")
	Projects.offers.clear()
	var y: int = GridEdge.AXIS_Y
	var walls: Array[Dictionary] = [
		{"edge": Vector3i(3, 2, y), "kind": ConstructionCatalog.WALL},
		{"edge": Vector3i(4, 2, y), "kind": ConstructionCatalog.DOOR},
		{"edge": Vector3i(5, 2, y), "kind": ConstructionCatalog.WALL},
	]
	_expect(_builder.apply(walls)["ok"], "paredes del área de trabajo")
	_expect(_builder.mark_room(Workstations.WORK_AREA, Vector2i(4, 1))["ok"], "marcar el área de trabajo")
	for x: int in [3, 4, 5]:
		_expect(_builder.place("simple_desk", Vector2i(x, 0), 2)["ok"], "escritorio en %d" % x)
		_expect(_builder.place("basic_chair", Vector2i(x, 1), 0)["ok"], "silla en %d" % x)
		_expect(_builder.install_computer("basic_computer", Vector2i(x, 0))["ok"], "computadora en %d" % x)


func _hire(role: String = "programmer") -> Dictionary:
	var employee: Dictionary = Staff.hire_directly(role, "junior")
	_expect(not employee.is_empty(), "contratado: %s" % role)
	(employee["traits"] as Array).clear()
	employee["energy"] = 100
	employee["mood"] = 70
	employee["stress"] = 20
	return employee


# Le da al CEO un contrato pequeño: el programador sin equipo lo lleva con él.
func _give_work(employee: Dictionary) -> void:
	var team: Dictionary = Staff.create_team()
	Staff.add_to_team(team["id"], employee["id"])
	Projects.offers.append(Projects._make_offer(GameClock.get_day_count(), "small"))
	Projects.accept(Projects.offers[-1]["id"])
	Projects.contracts[-1]["team_id"] = team["id"]


func _check_data() -> void:
	var order: Array = StaffCatalog.get_status_icons("order")
	_expect(order == ["no_station", "tired", "upset", "stressed", "idle"], "orden de los iconos: %s" % [order])
	_expect(int(StaffCatalog.get_status_icons("tired_below")) == 30 and int(StaffCatalog.get_status_icons("upset_below")) == 30
		and int(StaffCatalog.get_status_icons("stressed_from")) == 70, "cansado bajo 30, molesto bajo 30, estresado desde 70")
	for icon: Variant in order:
		_expect(OfficeCharacter.STATUS_ICONS.has(String(icon)), "se dibuja %s" % icon)


func _check_icons() -> void:
	_new_game()
	var employee: Dictionary = _hire()
	_expect(Staff.get_status_icon(employee) == "idle", "sin proyecto: sin tarea")
	_give_work(employee)
	_expect(Staff.get_status_icon(employee) == "", "con proyecto y bien: sin icono")
	employee["energy"] = 29
	_expect(Staff.get_status_icon(employee) == "tired", "energía 29: cansado")
	employee["energy"] = 30
	_expect(Staff.get_status_icon(employee) == "", "energía 30: ya no")
	employee["mood"] = 29
	_expect(Staff.get_status_icon(employee) == "upset", "ánimo 29: molesto")
	employee["mood"] = 70
	employee["quit_day"] = GameClock.get_day_count() + 3
	_expect(Staff.get_status_icon(employee) == "upset", "con aviso de renuncia: molesto")
	employee["quit_day"] = Staff.NO_QUIT
	employee["stress"] = 70
	_expect(Staff.get_status_icon(employee) == "stressed", "estrés 70: estresado")
	employee["stress"] = 20
	# Sin silla: se la quita del puesto.
	var seat: Dictionary = OfficeState.find_furniture_assigned_to(Staff.employee_key(employee["id"]))
	seat["assigned_to"] = ""
	_expect(Staff.get_status_icon(employee) == "no_station", "sin silla: sin puesto")
	seat["assigned_to"] = Staff.employee_key(employee["id"])
	# Un vendedor no produce: no está «sin tarea» aunque no haya proyecto.
	var seller: Dictionary = _hire("salesperson")
	_expect(Staff.get_status_icon(seller) == "", "el vendedor no está sin tarea")


func _check_priority() -> void:
	_new_game()
	var employee: Dictionary = _hire()
	employee["energy"] = 10
	employee["mood"] = 10
	employee["stress"] = 90
	_expect(Staff.get_status_icon(employee) == "tired", "cansado antes que molesto, estresado y sin tarea")
	employee["energy"] = 80
	_expect(Staff.get_status_icon(employee) == "upset", "después molesto")
	employee["mood"] = 80
	_expect(Staff.get_status_icon(employee) == "stressed", "después estresado")
	employee["stress"] = 10
	_expect(Staff.get_status_icon(employee) == "idle", "al final sin tarea")
	var seat: Dictionary = OfficeState.find_furniture_assigned_to(Staff.employee_key(employee["id"]))
	seat["assigned_to"] = ""
	employee["energy"] = 10
	_expect(Staff.get_status_icon(employee) == "no_station", "sin puesto antes que todo")


func _check_character() -> void:
	_new_game()
	var employee: Dictionary = _hire()
	_give_work(employee)
	employee["energy"] = 20
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var character: OfficeCharacter = game.employees[int(employee["id"])]
	_expect(character.status_icon == "tired", "el cansado muestra su icono: %s" % character.status_icon)
	# No cambia en cada cuadro: recién al cambiar la hora.
	employee["energy"] = 100
	await get_tree().process_frame
	_expect(character.status_icon == "tired", "el icono no se recalcula en cada cuadro")
	GameClock.fast_forward_hours(1)
	_expect(character.status_icon == "", "recuperado, deja de mostrarlo: %s" % character.status_icon)
	Projects.contracts.clear()
	EventBus.projects_changed.emit()
	_expect(character.status_icon == "idle", "sin proyecto: sin tarea")
	game.queue_free()
	await get_tree().process_frame


func _check_notices() -> void:
	_new_game()
	var employee: Dictionary = _hire()
	_give_work(employee)
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var hud: Hud = game.get_node("Hud")
	var card: EmployeeCard = game.get_node("EmployeeCard")
	EventBus.notice.emit("Aviso común.")
	_expect(hud.get_notice_text() == "Aviso común." and hud.get_notice_target().is_empty(), "un aviso común no lleva a nada")
	hud.click_notice()
	_expect(hud.get_notice_text() == "Aviso común.", "el clic no lo cierra")
	# El aviso de renuncia lleva a la ficha.
	employee["mood"] = 0
	employee["bad_days"] = int(StaffCatalog.get_morale("quit_bad_days"))
	Staff._update_morale()
	_expect(hud.get_notice_text().contains("avisa que renuncia"), "aviso de renuncia: %s" % hud.get_notice_text())
	_expect(hud.get_notice_target() == EventBus.target_employee(int(employee["id"])), "lleva a su ficha: %s" % [hud.get_notice_target()])
	_expect(not card.is_open(), "la ficha está cerrada")
	hud.click_notice()
	_expect(card.is_open() and card.get_employee_id() == int(employee["id"]), "el clic abre su ficha")
	_expect(hud.get_notice_text().is_empty(), "y cierra el aviso")
	card.close()
	# Un menú.
	var bank: BankPanel = game.get_node("BankPanel")
	EventBus.send_notice(EventBus.target_menu("bank"), "La calificación sube.")
	hud.click_notice()
	_expect(bank.is_open(), "un aviso del banco abre el Banco")
	# Un contrato y un producto abren Proyectos en su pestaña.
	var projects: ProjectsPanel = game.get_node("ProjectsPanel")
	EventBus.send_notice(EventBus.target_product(1), "Producto.")
	hud.click_notice()
	_expect(projects.is_open() and projects.get_tab() == ProjectsPanel.TAB_PRODUCTS and not bank.is_open(),
		"un producto abre Proyectos en Productos")
	EventBus.send_notice(EventBus.target_contract(int(Projects.contracts[0]["id"])), "Contrato.")
	hud.click_notice()
	_expect(projects.get_tab() == ProjectsPanel.TAB_CONTRACTS, "un contrato, en Contratos")
	# Una habitación mueve la cámara.
	var camera: OfficeCamera = game.get_node("OfficeCamera")
	var grid: OfficeGrid = game.get_node("OfficeGrid")
	EventBus.send_notice(EventBus.target_room(Vector2i(5, 6)), "Sucia.")
	hud.click_notice()
	_expect(camera.position.distance_to(grid.grid_to_world(Vector2(5, 6))) < 1.0, "una habitación centra la cámara")
	# Los sistemas mandan sus avisos con destino.
	Projects.contracts[0]["deadline_day"] = GameClock.get_day_count() - 1
	Projects._check_late_contracts(GameClock.get_day_count())
	_expect(hud.get_notice_target() == EventBus.target_contract(int(Projects.contracts[0]["id"])), "el atraso lleva al contrato")
	Staff.give_raise(int(employee["id"]), int(employee["salary"]) + 500)
	_expect(hud.get_notice_target() == EventBus.target_employee(int(employee["id"])), "el aumento lleva a la ficha")
	game.queue_free()
	await get_tree().process_frame
