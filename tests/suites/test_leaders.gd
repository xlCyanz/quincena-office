# Líderes de equipo: en Startup un equipo sin líder presente rinde 75 % y con él 100 %;
# en Emprendimiento siempre 100 %; un líder fuera de turno no cuenta.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=leaders
extends Node

## Lo escucha test_all: fallos y comprobaciones.
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const SEED: int = 20261113
const LEADER: String = "team_leader"

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE_PATH)
		return
	# Carpeta aparte para no tocar las partidas del jugador.
	SaveManager.save_dir = "user://test_saves"
	_check_unlock()
	_check_promotion()
	_check_factor()
	_check_team_rules()
	_check_hiring()
	_check_save()
	await _check_ui()

	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


# Tres puestos, dinero de sobra y los objetivos ya cumplidos.
func _new_game() -> void:
	SaveManager.new_game()
	Staff.set_seed(SEED)
	Projects.set_seed(SEED)
	for objective: Dictionary in Company.get_objectives():
		Company.objectives_done.append(String(objective["id"]))
	Economy.earn(50000, "Prueba")
	var builder := Builder.new()
	var y: int = GridEdge.AXIS_Y
	var walls: Array[Dictionary] = [
		{"edge": Vector3i(3, 2, y), "kind": ConstructionCatalog.WALL},
		{"edge": Vector3i(4, 2, y), "kind": ConstructionCatalog.DOOR},
		{"edge": Vector3i(5, 2, y), "kind": ConstructionCatalog.WALL},
	]
	_expect(builder.apply(walls)["ok"], "paredes del área de trabajo")
	_expect(builder.mark_room(Workstations.WORK_AREA, Vector2i(4, 1))["ok"], "marcar el área de trabajo")
	for x: int in [3, 4, 5]:
		_expect(builder.place("simple_desk", Vector2i(x, 0), 2)["ok"], "escritorio en %d" % x)
		_expect(builder.place("basic_chair", Vector2i(x, 1), 0)["ok"], "silla en %d" % x)
		_expect(builder.install_computer("basic_computer", Vector2i(x, 0))["ok"], "computadora en %d" % x)


# Contrata a alguien de ese cargo y nivel en la próxima tanda de candidatos.
func _hire(role: String, level: String) -> Dictionary:
	var opened: Dictionary = Staff.open_vacancy(role, level, StaffCatalog.get_salary(role, level), true)
	_expect(opened["ok"], "publicar %s: %s" % [role, opened["message"]])
	var arrival: int = int(StaffCatalog.get_hiring("arrival_hour"))
	var hours: int = posmod(arrival - GameClock.get_hour(), GameConstants.HOURS_PER_DAY)
	GameClock.fast_forward_hours(hours if hours > 0 else GameConstants.HOURS_PER_DAY)
	var candidate: Dictionary = Staff.get_vacancy(opened["id"])["candidates"][0]
	Staff.make_offer(candidate["id"], candidate["asked_salary"])
	var employee: Dictionary = Staff.get_employee(candidate["id"])
	# Sin rasgos: se miden rendimientos exactos.
	(employee.get("traits", []) as Array).clear()
	_expect(not employee.is_empty(), "contratado: %s %s" % [role, level])
	return employee


# Hora absoluta del próximo día hábil, en el turno de 8 a 17 y fuera del almuerzo.
func _work_hour() -> int:
	var at: int = Staff.get_absolute_hour() + 1
	while Staff.get_weekday_at(at) >= 5 or posmod(at, 24) != 10:
		at += 1
	return at


func _check_unlock() -> void:
	_new_game()
	var senior: Dictionary = _hire("programmer", "senior")
	var progress: Dictionary = Staff.get_promotion_progress(senior)
	_expect(progress["next_role"] == LEADER and not bool(progress["ready"]), "un Senior ascenderá a líder, todavía no")
	_expect(Staff.promote(senior["id"], 5000)["ok"] == false, "en Emprendimiento no asciende a líder")
	var opened: Dictionary = Staff.open_vacancy(LEADER, "junior", 4200, false)
	_expect(not opened["ok"] and String(opened["message"]).contains("Startup"), "en Emprendimiento no hay vacante de líder: %s" % opened["message"])
	Company.stage = 1
	_expect(bool(Staff.get_promotion_progress(senior)["ready"]), "en Startup ya puede")
	# Un Junior no asciende a líder.
	var junior: Dictionary = senior.duplicate(true)
	junior["level"] = "junior"
	_expect(String(Staff.get_promotion_progress(junior)["next_role"]).is_empty(), "un Junior no puede ser líder")


func _check_promotion() -> void:
	_new_game()
	Company.stage = 1
	var senior: Dictionary = _hire("programmer", "senior")
	var other: Dictionary = _hire("designer", "junior")
	var team: Dictionary = Staff.create_team()
	Staff.add_to_team(team["id"], senior["id"])
	Staff.add_to_team(team["id"], other["id"])
	var salary: int = senior["salary"]
	_expect(Staff.promote(senior["id"], salary)["ok"] == false, "con el mismo sueldo no asciende")
	var result: Dictionary = Staff.promote(senior["id"], 4200)
	_expect(result["ok"], "asciende a líder: %s" % result["message"])
	_expect(String(result["message"]).contains("Lidera %s" % team["name"]), "aviso: %s" % result["message"])
	_expect(senior["role"] == LEADER and int(senior["salary"]) == 4200, "es líder con $4,200")
	_expect(int(team["leader_id"]) == senior["id"] and not (team["members"] as Array).has(senior["id"]), "lidera su equipo y deja de ser miembro")
	_expect(Staff.get_team_of(senior["id"]) == team, "su equipo sigue siendo ese (sigue el turno)")
	_expect(Staff.describe_employee(senior) == "Líder de equipo · %s al mes" % MoneyFormat.format(4200), "sin nivel: %s" % Staff.describe_employee(senior))
	_expect(Staff.get_promotion_progress(senior)["next_role"] == "manager" and not bool(Staff.get_promotion_progress(senior)["ready"]), "un líder no asciende a gerente en Startup")
	_expect(Staff.get_market_salary(senior) == 4200, "su sueldo de mercado es el del cargo")
	_expect(not Staff.is_idle(senior), "un líder no queda ocioso por no producir")
	# El líder no suma puntos: solo trabaja el diseñador.
	Projects.offers.append(Projects._make_offer(GameClock.get_day_count(), "small"))
	Projects.accept(Projects.offers[-1]["id"])
	var contract: Dictionary = Projects.contracts[-1]
	Projects.assign(contract["id"], team["id"])
	var workers: Array[Dictionary] = Projects.get_workers(contract, _work_hour())
	_expect(workers.size() == 1 and workers[0]["key"] == Staff.employee_key(other["id"]), "el líder no suma puntos: %s" % [workers])
	# Un Senior de un equipo que ya tiene líder queda sin equipo al ascender.
	var second: Dictionary = _hire("qa", "senior")
	Staff.add_to_team(team["id"], second["id"])
	result = Staff.promote(second["id"], 4300)
	_expect(String(result["message"]).contains("ya tiene líder"), "otro Senior del equipo: %s" % result["message"])
	_expect(Staff.get_team_of(second["id"]).is_empty() and int(team["leader_id"]) == senior["id"], "queda sin equipo")


func _check_factor() -> void:
	_new_game()
	var worker: Dictionary = _hire("programmer", "junior")
	var leader: Dictionary = _hire("programmer", "senior")
	worker["energy"] = 100
	worker["mood"] = 100
	var team: Dictionary = Staff.create_team()
	Staff.add_to_team(team["id"], worker["id"])
	Projects.offers.append(Projects._make_offer(GameClock.get_day_count(), "small"))
	Projects.accept(Projects.offers[-1]["id"])
	var contract: Dictionary = Projects.contracts[-1]
	Projects.assign(contract["id"], team["id"])
	var at: int = _work_hour()
	var full: float = Production.get_rate("junior", 100.0, 0.0, 100.0)
	_expect(is_equal_approx(Staff.get_team_factor(team, at), 1.0), "Emprendimiento sin líder: 100 %")
	_expect(is_equal_approx(float(Projects.get_workers(contract, at)[0]["rate"]), full), "rinde completo")
	Company.stage = 1
	_expect(is_equal_approx(Staff.get_team_factor(team, at), 0.75), "Startup sin líder: 75 %")
	_expect(is_equal_approx(float(Projects.get_workers(contract, at)[0]["rate"]), full * 0.75), "rinde 75 %%: %s" % Projects.get_workers(contract, at)[0]["rate"])
	Staff.promote(leader["id"], 4200)
	_expect(Staff.add_to_team(team["id"], leader["id"])["ok"], "nombrar líder")
	_expect(Staff.is_leader_present(team, at), "el líder está en su turno")
	_expect(is_equal_approx(float(Projects.get_workers(contract, at)[0]["rate"]), full), "con líder presente rinde 100 %")
	var night: int = at - 10 + 22
	_expect(not Staff.is_leader_present(team, night), "a las 22 el líder no está")
	_expect(is_equal_approx(Staff.get_team_factor(team, night), 0.75), "fuera de turno no cuenta")
	# Producción real de una hora con el líder.
	var before: float = float(contract["progress"]["design"]) + float(contract["progress"]["programming"]) + float(contract["progress"]["testing"])
	while Staff.get_absolute_hour() != at + 1:
		GameClock.fast_forward_hours(1)
	var after: float = float(contract["progress"]["design"]) + float(contract["progress"]["programming"]) + float(contract["progress"]["testing"])
	_expect(after - before > full * 0.75 + 0.01, "la hora producida rinde completo: %.2f" % (after - before))
	Staff.fire(leader["id"])
	_expect(int(team["leader_id"]) == 0, "despedido, el equipo queda sin líder")
	_expect(is_equal_approx(Staff.get_team_factor(team, at), 0.75), "y vuelve a 75 %")


func _check_team_rules() -> void:
	_new_game()
	Company.stage = 1
	var a: Dictionary = _hire("programmer", "senior")
	var b: Dictionary = _hire("programmer", "senior")
	Staff.promote(a["id"], 4200)
	Staff.promote(b["id"], 4200)
	var team: Dictionary = Staff.create_team()
	var other_team: Dictionary = Staff.create_team()
	_expect(Staff.add_to_team(team["id"], a["id"])["ok"], "un líder entra como líder")
	_expect(int(team["leader_id"]) == a["id"] and (team["members"] as Array).is_empty(), "no como miembro")
	var second: Dictionary = Staff.add_to_team(team["id"], b["id"])
	_expect(not second["ok"] and String(second["message"]).contains("ya tiene líder"), "un equipo tiene un solo líder: %s" % second["message"])
	_expect(Staff.add_to_team(other_team["id"], a["id"])["ok"], "mover al líder")
	_expect(int(team["leader_id"]) == 0 and int(other_team["leader_id"]) == a["id"], "cambió de equipo")
	_expect(Staff.remove_from_team(a["id"]), "quitar al líder")
	_expect(int(other_team["leader_id"]) == 0 and a["role"] == LEADER and Staff.get_team_of(a["id"]).is_empty(), "sigue siendo líder, sin equipo")
	# Un equipo sin miembros no cuenta como activo aunque tenga líder.
	Staff.add_to_team(team["id"], a["id"])
	_expect(Staff.get_active_team_count() == 0, "un líder solo no hace un equipo activo")
	var template: Dictionary = Staff.employees[0]
	for i: int in range(10):
		var fake: Dictionary = template.duplicate(true)
		fake["id"] = 1000 + i
		fake["role"] = "programmer"
		Staff.employees.append(fake)
		_expect(Staff.add_to_team(team["id"], fake["id"])["ok"], "miembro %d" % (i + 1))
	var fake: Dictionary = template.duplicate(true)
	fake["id"] = 2000
	fake["role"] = "programmer"
	Staff.employees.append(fake)
	var full: Dictionary = Staff.add_to_team(team["id"], fake["id"])
	_expect(not full["ok"] and String(full["message"]).contains("10 miembros"), "el 11.º no entra: %s" % full["message"])


func _check_hiring() -> void:
	_new_game()
	Company.stage = 1
	var leader: Dictionary = _hire(LEADER, "intern")
	_expect(leader["role"] == LEADER and leader["level"] == StaffCatalog.get_level_ids()[-1], "la vacante de líder ignora el nivel")
	_expect(int(leader["skills"]["leadership"]) >= StaffCatalog.get_main_skill_range("senior").x, "su habilidad principal es el liderazgo: %d" % leader["skills"]["leadership"])
	_expect(absi(int(leader["asked_salary"]) - 4200) <= 4200 * 0.3, "pide cerca de $4,200: %d" % leader["asked_salary"])
	_expect(Staff.describe_vacancy({"role": LEADER, "level": "senior", "salary": 4200}) == "Líder de equipo · %s al mes" % MoneyFormat.format(4200), "vacante sin nivel")


func _check_save() -> void:
	_new_game()
	Company.stage = 1
	var leader: Dictionary = _hire("programmer", "senior")
	var worker: Dictionary = _hire("designer", "junior")
	Staff.promote(leader["id"], 4200)
	var team: Dictionary = Staff.create_team()
	Staff.add_to_team(team["id"], leader["id"])
	Staff.add_to_team(team["id"], worker["id"])
	var before: String = JSON.stringify(Staff.export_state())
	_expect(SaveManager.save_game("slot_4"), "guardar")
	SaveManager.new_game()
	_expect(SaveManager.load_game("slot_4"), "cargar")
	_expect(JSON.stringify(Staff.export_state()) == before, "el líder vuelve igual")
	# Partida vieja: equipos sin líder.
	var old: Dictionary = Staff.export_state()
	for saved: Dictionary in old["teams"]:
		saved.erase("leader_id")
	Staff.import_state(old)
	_expect(int(Staff.teams[0]["leader_id"]) == 0, "partida vieja: sin líder")
	old = Staff.export_state()
	old["teams"][0]["leader_id"] = worker["id"]
	Staff.import_state(old)
	_expect(int(Staff.teams[0]["leader_id"]) == 0, "un líder inválido se descarta")


func _check_ui() -> void:
	_new_game()
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var senior: Dictionary = _hire("programmer", "senior")
	var worker: Dictionary = _hire("designer", "junior")
	var card: EmployeeCard = game.get_node("EmployeeCard")
	var staff_panel: StaffPanel = game.get_node("StaffPanel")
	var teams_panel: TeamsPanel = game.get_node("TeamsPanel")
	staff_panel.set_open(true)
	await get_tree().process_frame
	var roles: Array[String] = StaffCatalog.get_role_ids()
	var option: OptionButton = staff_panel.get_role_option()
	_expect(option.is_item_disabled(roles.find(LEADER)), "líder en gris en Emprendimiento")
	_expect(option.get_item_text(roles.find(LEADER)).contains("Startup"), "dice desde cuándo: %s" % option.get_item_text(roles.find(LEADER)))
	card.open_employee(senior["id"])
	await get_tree().process_frame
	_expect(card.get_text().contains("Ascenso a Líder de equipo: desde Startup"), "la ficha dice cuándo: %s" % card.get_text())
	_expect(not card.is_promote_visible(), "sin fila Ascender")
	Company.stage = 1
	EventBus.staff_changed.emit()
	await get_tree().process_frame
	_expect(not option.is_item_disabled(roles.find(LEADER)), "líder habilitado en Startup")
	option.select(roles.find(LEADER))
	option.item_selected.emit(roles.find(LEADER))
	_expect(staff_panel.get_level_option().disabled, "el líder no elige nivel")
	_expect(staff_panel.get_salary_offer() == 4200, "sueldo de tabla $4,200: %d" % staff_panel.get_salary_offer())
	staff_panel.set_open(false)
	card.refresh()
	await get_tree().process_frame
	_expect(card.is_promote_visible() and card.get_text().contains("Puede ascender a Líder de equipo"), "la ficha ofrece ascender: %s" % card.get_text())
	_expect(card.get_promote_salary() == 4200, "sugiere $4,200")
	var team: Dictionary = Staff.create_team()
	Staff.add_to_team(team["id"], worker["id"])
	teams_panel.set_open(true)
	await get_tree().process_frame
	var text: String = teams_panel.get_list_text()
	_expect(text.contains("Líder: ninguno") and text.contains("rinde 75 % sin su líder presente"), "Equipos avisa sin líder: %s" % text)
	await _click(card.get_promote_button())
	_expect(senior["role"] == LEADER, "ascendido desde la ficha")
	var character: Employee = game.get("employees")[senior["id"]]
	_expect(character.shirt_color == StaffCatalog.get_shirt_color(LEADER), "su camisa cambia al color de líder")
	_expect(card.get_text().contains("Líder de equipo · $4,200"), "la ficha muestra el cargo: %s" % card.get_text())
	var choice: OptionButton = teams_panel.get_team_control(team["id"], "add_choice")
	for index: int in range(choice.item_count):
		if choice.get_item_id(index) == senior["id"]:
			choice.select(index)
	await _click(teams_panel.get_team_control(team["id"], "add"))
	_expect(int(team["leader_id"]) == senior["id"], "nombrado desde Equipos: %s" % teams_panel.get_status_text())
	await get_tree().process_frame
	text = teams_panel.get_list_text()
	_expect(text.contains("+ líder"), "el título cuenta al líder: %s" % text)
	_expect(text.contains("Líder: %s (" % senior["name"]) and not text.contains("rinde 75 %"), "muestra al líder: %s" % text)
	card.open_employee(senior["id"])
	await get_tree().process_frame
	_expect(card.get_text().contains("(lo lidera)"), "la ficha dice que lo lidera: %s" % card.get_text())
	await _click(teams_panel.get_team_control(team["id"], "remove_leader"))
	_expect(int(team["leader_id"]) == 0 and senior["role"] == LEADER, "Quitar: sin líder y sigue siendo líder")
	teams_panel.set_open(false)
	game.queue_free()
	await get_tree().process_frame


func _click(control: Control) -> void:
	var card: Node = control.get_parent()
	while card != null and not card is EmployeeCard:
		card = card.get_parent()
	if card != null:
		(card as EmployeeCard).reveal(control)
		await get_tree().process_frame
	var at: Vector2 = control.get_global_rect().get_center()
	_expect(get_viewport().get_visible_rect().has_point(at), "%s visible en pantalla" % control.text)
	var motion := InputEventMouseMotion.new()
	motion.position = at
	await _push(motion)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		await _push(event)


func _push(event: InputEvent) -> void:
	get_viewport().push_input(event, true)
	await get_tree().process_frame
